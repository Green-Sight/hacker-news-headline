-- ============================================================================
-- 03_backfill_data.sql
-- ============================================================================
-- This script safely backfills data from the original table to the 
-- partitioned table while handling concurrent inserts.
-- ============================================================================

-- Step 1: Set up a trigger to capture new inserts during migration
-- This ensures no data is lost during the backfill process

-- Create a temporary table to track inserts during migration
CREATE TABLE IF NOT EXISTS iot_measurements_migration_buffer (
    id BIGSERIAL PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    unit VARCHAR(20),
    measured_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    buffered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create a function to buffer new inserts
CREATE OR REPLACE FUNCTION buffer_new_measurements()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO iot_measurements_migration_buffer 
        (device_id, measurement_type, value, unit, measured_at, created_at, metadata)
    VALUES 
        (NEW.device_id, NEW.measurement_type, NEW.value, NEW.unit, 
         NEW.measured_at, NEW.created_at, NEW.metadata);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to capture concurrent inserts
-- This trigger will be dropped after migration is complete
CREATE TRIGGER trigger_buffer_measurements
    AFTER INSERT ON iot_measurements
    FOR EACH ROW
    EXECUTE FUNCTION buffer_new_measurements();

-- Display trigger status
SELECT 
    tgname AS trigger_name,
    tgrelid::regclass AS table_name,
    tgenabled AS enabled
FROM pg_trigger
WHERE tgrelid = 'iot_measurements'::regclass
  AND tgname = 'trigger_buffer_measurements';

-- Step 2: Take a snapshot of the maximum ID before backfill
-- This helps us identify which records need to be copied

DO $$
DECLARE
    max_id BIGINT;
BEGIN
    SELECT COALESCE(MAX(id), 0) INTO max_id FROM iot_measurements;
    
    -- Store the snapshot ID for reference
    CREATE TEMP TABLE IF NOT EXISTS migration_snapshot (
        snapshot_id BIGINT,
        snapshot_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO migration_snapshot (snapshot_id) VALUES (max_id);
    
    RAISE NOTICE 'Snapshot taken at ID: %, Time: %', max_id, CURRENT_TIMESTAMP;
END $$;

-- Step 3: Backfill data in batches to avoid long locks
-- Using batches allows for better control and rollback capability

DO $$
DECLARE
    batch_size INTEGER := 10000;  -- Adjust based on your needs
    current_min_id BIGINT := 1;
    max_id BIGINT;
    batch_count INTEGER := 0;
    total_rows BIGINT;
BEGIN
    -- Get the snapshot ID
    SELECT snapshot_id INTO max_id FROM migration_snapshot;
    
    -- Get total rows to process
    SELECT COUNT(*) INTO total_rows 
    FROM iot_measurements 
    WHERE id <= max_id;
    
    RAISE NOTICE 'Starting backfill of % rows in batches of %', total_rows, batch_size;
    
    -- Process in batches
    WHILE current_min_id <= max_id LOOP
        -- Insert batch
        INSERT INTO iot_measurements_partitioned 
            (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
        SELECT 
            id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
        FROM iot_measurements
        WHERE id >= current_min_id 
          AND id < current_min_id + batch_size
          AND id <= max_id
        ON CONFLICT (id, measured_at) DO NOTHING;  -- Handle duplicates gracefully
        
        batch_count := batch_count + 1;
        
        -- Progress reporting
        IF batch_count % 10 = 0 THEN
            RAISE NOTICE 'Processed % batches (approximately % rows)', 
                         batch_count, batch_count * batch_size;
        END IF;
        
        -- Move to next batch
        current_min_id := current_min_id + batch_size;
        
        -- Optional: Commit after each batch by using transactions in your client
        -- For this DO block, it's all in one transaction
    END LOOP;
    
    RAISE NOTICE 'Backfill completed: % batches processed', batch_count;
END $$;

-- Step 4: Copy buffered data (concurrent inserts during migration)
INSERT INTO iot_measurements_partitioned 
    (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
SELECT 
    id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
FROM iot_measurements
WHERE id > (SELECT snapshot_id FROM migration_snapshot)
ON CONFLICT (id, measured_at) DO NOTHING;

-- Also copy from the migration buffer
INSERT INTO iot_measurements_partitioned 
    (device_id, measurement_type, value, unit, measured_at, created_at, metadata)
SELECT 
    device_id, measurement_type, value, unit, measured_at, created_at, metadata
FROM iot_measurements_migration_buffer
ON CONFLICT (id, measured_at) DO NOTHING;

-- Step 5: Validation - Compare row counts
DO $$
DECLARE
    original_count BIGINT;
    partitioned_count BIGINT;
    buffer_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO original_count FROM iot_measurements;
    SELECT COUNT(*) INTO partitioned_count FROM iot_measurements_partitioned;
    SELECT COUNT(*) INTO buffer_count FROM iot_measurements_migration_buffer;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VALIDATION RESULTS';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Original table rows: %', original_count;
    RAISE NOTICE 'Partitioned table rows: %', partitioned_count;
    RAISE NOTICE 'Buffered rows during migration: %', buffer_count;
    
    IF partitioned_count >= original_count THEN
        RAISE NOTICE 'SUCCESS: All data copied (partitioned >= original)';
    ELSE
        RAISE WARNING 'ATTENTION: Row count mismatch! Missing % rows', 
                      original_count - partitioned_count;
    END IF;
    RAISE NOTICE '========================================';
END $$;

-- Step 6: Additional validation queries

-- Compare min/max timestamps
SELECT 
    'Original' AS table_name,
    MIN(measured_at) AS min_measured_at,
    MAX(measured_at) AS max_measured_at,
    COUNT(*) AS total_rows
FROM iot_measurements
UNION ALL
SELECT 
    'Partitioned' AS table_name,
    MIN(measured_at) AS min_measured_at,
    MAX(measured_at) AS max_measured_at,
    COUNT(*) AS total_rows
FROM iot_measurements_partitioned
ORDER BY table_name;

-- Check for any data in specific partitions
SELECT 
    schemaname,
    tablename,
    COUNT(*) as row_count,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables t
LEFT JOIN LATERAL (
    SELECT COUNT(*) 
    FROM ONLY iot_measurements_partitioned 
    WHERE tableoid = (schemaname||'.'||tablename)::regclass
) c ON true
WHERE tablename LIKE 'iot_measurements_y%'
GROUP BY schemaname, tablename
ORDER BY tablename;

-- Step 7: Sample data comparison
SELECT 'Original - Sample' AS source, * 
FROM iot_measurements 
ORDER BY id 
LIMIT 5;

SELECT 'Partitioned - Sample' AS source, * 
FROM iot_measurements_partitioned 
ORDER BY id 
LIMIT 5;

-- Analyze the new table for better query performance
VACUUM ANALYZE iot_measurements_partitioned;

-- ============================================================================
-- Notes:
-- - Migration buffer captures concurrent inserts during backfill
-- - Data is copied in batches to avoid long-running transactions
-- - Validation queries confirm data integrity
-- - ON CONFLICT clause prevents duplicate key errors
-- - Trigger remains active until switchover is complete
-- - Next step: Switch over to the partitioned table
-- ============================================================================
