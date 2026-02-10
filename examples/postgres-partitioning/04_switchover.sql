-- ============================================================================
-- 04_switchover.sql
-- ============================================================================
-- This script performs the switchover from the original table to the 
-- partitioned table with minimal downtime.
-- ============================================================================

-- Step 1: Final sync - Copy any remaining data
-- This catches any inserts that happened after the initial backfill

INSERT INTO iot_measurements_partitioned 
    (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
SELECT 
    id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
FROM iot_measurements
WHERE id > (SELECT snapshot_id FROM migration_snapshot)
ON CONFLICT (id, measured_at) DO NOTHING;

-- Also sync from migration buffer one final time
INSERT INTO iot_measurements_partitioned 
    (device_id, measurement_type, value, unit, measured_at, created_at, metadata)
SELECT 
    device_id, measurement_type, value, unit, measured_at, created_at, metadata
FROM iot_measurements_migration_buffer
WHERE id NOT IN (
    SELECT id FROM iot_measurements_partitioned
    WHERE id IN (SELECT id FROM iot_measurements_migration_buffer)
)
ON CONFLICT (id, measured_at) DO NOTHING;

-- Step 2: Final validation before switchover
DO $$
DECLARE
    original_count BIGINT;
    partitioned_count BIGINT;
    count_diff BIGINT;
BEGIN
    SELECT COUNT(*) INTO original_count FROM iot_measurements;
    SELECT COUNT(*) INTO partitioned_count FROM iot_measurements_partitioned;
    count_diff := original_count - partitioned_count;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'FINAL VALIDATION BEFORE SWITCHOVER';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Original table rows: %', original_count;
    RAISE NOTICE 'Partitioned table rows: %', partitioned_count;
    RAISE NOTICE 'Difference: %', count_diff;
    
    IF ABS(count_diff) > 100 THEN
        RAISE EXCEPTION 'Row count difference too large: %. Aborting switchover.', count_diff;
    ELSIF count_diff != 0 THEN
        RAISE WARNING 'Minor row count difference: %. Review before proceeding.', count_diff;
    ELSE
        RAISE NOTICE 'Perfect match! Safe to proceed with switchover.';
    END IF;
    RAISE NOTICE '========================================';
END $$;

-- Step 3: Rename tables (this is the actual switchover)
-- This should be done in a transaction for atomicity

BEGIN;

-- Remove the migration trigger from the old table
DROP TRIGGER IF EXISTS trigger_buffer_measurements ON iot_measurements;

-- Rename the original table to a backup name
ALTER TABLE iot_measurements RENAME TO iot_measurements_old_backup;

-- Rename the partitioned table to the original name
ALTER TABLE iot_measurements_partitioned RENAME TO iot_measurements;

-- Update sequence ownership (if using SERIAL)
-- The sequence should now be owned by the new table
ALTER SEQUENCE iot_measurements_id_seq OWNED BY iot_measurements.id;

-- Rename the indexes to match the original naming convention
ALTER INDEX IF EXISTS idx_iot_measurements_part_device_id 
    RENAME TO idx_iot_measurements_device_id;

ALTER INDEX IF EXISTS idx_iot_measurements_part_measured_at 
    RENAME TO idx_iot_measurements_measured_at;

ALTER INDEX IF EXISTS idx_iot_measurements_part_device_time 
    RENAME TO idx_iot_measurements_device_time;

ALTER INDEX IF EXISTS idx_iot_measurements_part_metadata 
    RENAME TO idx_iot_measurements_metadata;

-- Rename old table indexes to avoid conflicts
ALTER INDEX IF EXISTS idx_iot_measurements_device_id 
    RENAME TO idx_iot_measurements_old_device_id;

ALTER INDEX IF EXISTS idx_iot_measurements_measured_at 
    RENAME TO idx_iot_measurements_old_measured_at;

ALTER INDEX IF EXISTS idx_iot_measurements_device_time 
    RENAME TO idx_iot_measurements_old_device_time;

ALTER INDEX IF EXISTS idx_iot_measurements_metadata 
    RENAME TO idx_iot_measurements_old_metadata;

COMMIT;

-- Step 4: Enable auto-partition creation trigger on the new table
CREATE TRIGGER trigger_auto_create_partition
    BEFORE INSERT ON iot_measurements
    FOR EACH ROW EXECUTE FUNCTION auto_create_partition();

-- Step 5: Update any views that reference the old table
-- (Add your view updates here if you have any)

-- Example:
-- CREATE OR REPLACE VIEW v_latest_measurements AS
-- SELECT * FROM iot_measurements
-- WHERE measured_at > CURRENT_TIMESTAMP - INTERVAL '1 day';

-- Step 6: Verify the switchover
SELECT 
    'CURRENT iot_measurements (partitioned)' AS table_info,
    COUNT(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('iot_measurements')) AS total_size,
    MIN(measured_at) AS earliest_measurement,
    MAX(measured_at) AS latest_measurement
FROM iot_measurements;

-- Verify partitions are active
SELECT 
    schemaname,
    tablename AS partition_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements_y%'
ORDER BY tablename;

-- Step 7: Test insert into the new partitioned table
DO $$
DECLARE
    test_record_id BIGINT;
BEGIN
    -- Insert a test record
    INSERT INTO iot_measurements 
        (device_id, measurement_type, value, unit, measured_at, metadata)
    VALUES 
        ('TEST_DEVICE_001', 'temperature', 25.5, 'celsius', CURRENT_TIMESTAMP,
         '{"test": true, "switchover": "successful"}'::jsonb)
    RETURNING id INTO test_record_id;
    
    RAISE NOTICE 'Test insert successful. New record ID: %', test_record_id;
    
    -- Verify the record was inserted
    IF EXISTS (SELECT 1 FROM iot_measurements WHERE id = test_record_id) THEN
        RAISE NOTICE 'Test record verified in partitioned table';
    ELSE
        RAISE EXCEPTION 'Test record NOT found after insert!';
    END IF;
    
    -- Clean up test record
    DELETE FROM iot_measurements WHERE id = test_record_id;
    RAISE NOTICE 'Test record cleaned up';
END $$;

-- Step 8: Test query performance with partition pruning
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM iot_measurements
WHERE measured_at >= '2024-06-01' 
  AND measured_at < '2024-07-01'
  AND device_id = 'DEVICE_001';

-- Display statistics
SELECT 
    schemaname,
    tablename,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE tablename IN ('iot_measurements', 'iot_measurements_old_backup')
ORDER BY tablename;

-- Step 9: Grant necessary permissions (adjust as needed)
-- Example:
-- GRANT SELECT, INSERT, UPDATE, DELETE ON iot_measurements TO your_app_user;
-- GRANT USAGE, SELECT ON SEQUENCE iot_measurements_id_seq TO your_app_user;

RAISE NOTICE '========================================';
RAISE NOTICE 'SWITCHOVER COMPLETED SUCCESSFULLY!';
RAISE NOTICE '========================================';
RAISE NOTICE 'The partitioned table is now active as "iot_measurements"';
RAISE NOTICE 'The old table is backed up as "iot_measurements_old_backup"';
RAISE NOTICE 'Auto-partition creation is enabled for future dates';
RAISE NOTICE 'Migration buffer table can be dropped after verification';
RAISE NOTICE '========================================';

-- ============================================================================
-- Notes:
-- - Switchover completed with minimal downtime
-- - Original table renamed to _old_backup for safety
-- - All indexes renamed to match original naming
-- - Auto-partition trigger enabled for future inserts
-- - Test insert verified the partitioned table is working
-- - Migration is complete, but keep backup table for a while
-- - Next step: Clean up old resources after verification period
-- ============================================================================
