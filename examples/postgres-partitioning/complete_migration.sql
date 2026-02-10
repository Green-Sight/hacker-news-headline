-- ============================================================================
-- complete_migration.sql
-- ============================================================================
-- Complete PostgreSQL partitioning migration script for IoT measurements
-- This script combines all steps into one comprehensive migration process
-- 
-- IMPORTANT: Review and adjust parameters before running in production!
-- - Adjust batch_size based on your data volume
-- - Modify partition date ranges for your data
-- - Test on a copy of production data first
-- ============================================================================

\echo '============================================'
\echo 'PostgreSQL Partitioning Migration'
\echo 'IoT Measurements Table'
\echo '============================================'
\echo ''

-- Set client encoding and error handling
\set ON_ERROR_STOP on
\timing on

-- ============================================================================
-- STEP 1: Verify the existing table
-- ============================================================================
\echo 'Step 1: Verifying existing table...'

DO $$
DECLARE
    row_count BIGINT;
    table_size TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'iot_measurements') THEN
        RAISE EXCEPTION 'Table iot_measurements does not exist!';
    END IF;
    
    SELECT COUNT(*) INTO row_count FROM iot_measurements;
    SELECT pg_size_pretty(pg_total_relation_size('iot_measurements')) INTO table_size;
    
    RAISE NOTICE 'Existing table found:';
    RAISE NOTICE '  Rows: %', row_count;
    RAISE NOTICE '  Size: %', table_size;
END $$;

-- ============================================================================
-- STEP 2: Create partitioned table structure
-- ============================================================================
\echo 'Step 2: Creating partitioned table structure...'

CREATE TABLE iot_measurements_partitioned (
    id BIGSERIAL,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    unit VARCHAR(20),
    measured_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    PRIMARY KEY (id, measured_at)
) PARTITION BY RANGE (measured_at);

ALTER TABLE iot_measurements_partitioned 
    ADD CONSTRAINT chk_measured_at_not_future_partitioned
    CHECK (measured_at <= CURRENT_TIMESTAMP);

-- ============================================================================
-- STEP 3: Create partitions
-- ============================================================================
\echo 'Step 3: Creating partitions...'

-- Create partitions for 2024
CREATE TABLE iot_measurements_y2024m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE iot_measurements_y2024m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE iot_measurements_y2024m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE iot_measurements_y2024m04 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE iot_measurements_y2024m05 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE iot_measurements_y2024m06 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE iot_measurements_y2024m07 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE iot_measurements_y2024m08 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE iot_measurements_y2024m09 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE iot_measurements_y2024m10 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE iot_measurements_y2024m11 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE iot_measurements_y2024m12 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

-- Create partitions for 2025-2026
CREATE TABLE iot_measurements_y2025m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE iot_measurements_y2025m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE iot_measurements_y2025m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE iot_measurements_y2026m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE iot_measurements_y2026m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE iot_measurements_y2026m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- ============================================================================
-- STEP 4: Create indexes
-- ============================================================================
\echo 'Step 4: Creating indexes on partitioned table...'

CREATE INDEX idx_iot_measurements_part_device_id 
    ON iot_measurements_partitioned(device_id);
CREATE INDEX idx_iot_measurements_part_measured_at 
    ON iot_measurements_partitioned(measured_at DESC);
CREATE INDEX idx_iot_measurements_part_device_time 
    ON iot_measurements_partitioned(device_id, measured_at DESC);
CREATE INDEX idx_iot_measurements_part_metadata 
    ON iot_measurements_partitioned USING gin(metadata);

-- ============================================================================
-- STEP 5: Create partition management functions
-- ============================================================================
\echo 'Step 5: Creating partition management functions...'

CREATE OR REPLACE FUNCTION create_partition_if_not_exists(
    partition_date DATE
) RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := DATE_TRUNC('month', partition_date)::DATE;
    end_date := (start_date + INTERVAL '1 month')::DATE;
    partition_name := 'iot_measurements_y' || 
                      TO_CHAR(start_date, 'YYYY') || 'm' || 
                      TO_CHAR(start_date, 'MM');
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF iot_measurements_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION auto_create_partition() 
RETURNS TRIGGER AS $$
BEGIN
    PERFORM create_partition_if_not_exists(NEW.measured_at::DATE);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 6: Setup migration buffer for concurrent inserts
-- ============================================================================
\echo 'Step 6: Setting up migration buffer...'

CREATE TABLE iot_measurements_migration_buffer (
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

CREATE TRIGGER trigger_buffer_measurements
    AFTER INSERT ON iot_measurements
    FOR EACH ROW
    EXECUTE FUNCTION buffer_new_measurements();

-- ============================================================================
-- STEP 7: Take snapshot and backfill data
-- ============================================================================
\echo 'Step 7: Taking snapshot and backfilling data...'

DO $$
DECLARE
    batch_size INTEGER := 10000;
    current_min_id BIGINT := 1;
    max_id BIGINT;
    batch_count INTEGER := 0;
    total_rows BIGINT;
    snapshot_time TIMESTAMP := CURRENT_TIMESTAMP;
BEGIN
    -- Take snapshot
    SELECT COALESCE(MAX(id), 0) INTO max_id FROM iot_measurements;
    CREATE TEMP TABLE migration_snapshot (
        snapshot_id BIGINT,
        snapshot_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO migration_snapshot (snapshot_id) VALUES (max_id);
    
    SELECT COUNT(*) INTO total_rows FROM iot_measurements WHERE id <= max_id;
    RAISE NOTICE 'Snapshot taken at ID: %, Rows to migrate: %', max_id, total_rows;
    
    -- Backfill in batches
    WHILE current_min_id <= max_id LOOP
        INSERT INTO iot_measurements_partitioned 
            (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
        SELECT 
            id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
        FROM iot_measurements
        WHERE id >= current_min_id 
          AND id < current_min_id + batch_size
          AND id <= max_id
        ON CONFLICT (id, measured_at) DO NOTHING;
        
        batch_count := batch_count + 1;
        IF batch_count % 10 = 0 THEN
            RAISE NOTICE 'Processed % batches (% rows)', batch_count, batch_count * batch_size;
        END IF;
        
        current_min_id := current_min_id + batch_size;
    END LOOP;
    
    RAISE NOTICE 'Backfill completed: % batches', batch_count;
    
    -- Copy buffered data
    INSERT INTO iot_measurements_partitioned 
        (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
    SELECT 
        id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
    FROM iot_measurements
    WHERE id > max_id
    ON CONFLICT (id, measured_at) DO NOTHING;
END $$;

-- ============================================================================
-- STEP 8: Validation
-- ============================================================================
\echo 'Step 8: Validating data migration...'

DO $$
DECLARE
    original_count BIGINT;
    partitioned_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO original_count FROM iot_measurements;
    SELECT COUNT(*) INTO partitioned_count FROM iot_measurements_partitioned;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'VALIDATION RESULTS';
    RAISE NOTICE 'Original: % rows', original_count;
    RAISE NOTICE 'Partitioned: % rows', partitioned_count;
    
    IF partitioned_count >= original_count THEN
        RAISE NOTICE 'SUCCESS: Data migration validated';
    ELSE
        RAISE EXCEPTION 'FAILED: Missing % rows', original_count - partitioned_count;
    END IF;
    RAISE NOTICE '========================================';
END $$;

VACUUM ANALYZE iot_measurements_partitioned;

-- ============================================================================
-- STEP 9: Switchover (Critical section)
-- ============================================================================
\echo 'Step 9: Performing switchover...'
\echo 'WARNING: This is the critical section with brief downtime'

BEGIN;

-- Final sync
INSERT INTO iot_measurements_partitioned 
    (id, device_id, measurement_type, value, unit, measured_at, created_at, metadata)
SELECT 
    id, device_id, measurement_type, value, unit, measured_at, created_at, metadata
FROM iot_measurements
WHERE id > (SELECT snapshot_id FROM migration_snapshot)
ON CONFLICT (id, measured_at) DO NOTHING;

-- Remove migration trigger
DROP TRIGGER IF EXISTS trigger_buffer_measurements ON iot_measurements;

-- Rename tables
ALTER TABLE iot_measurements RENAME TO iot_measurements_old_backup;
ALTER TABLE iot_measurements_partitioned RENAME TO iot_measurements;

-- Update sequence ownership
ALTER SEQUENCE iot_measurements_id_seq OWNED BY iot_measurements.id;

-- Rename indexes
ALTER INDEX idx_iot_measurements_part_device_id 
    RENAME TO idx_iot_measurements_device_id;
ALTER INDEX idx_iot_measurements_part_measured_at 
    RENAME TO idx_iot_measurements_measured_at;
ALTER INDEX idx_iot_measurements_part_device_time 
    RENAME TO idx_iot_measurements_device_time;
ALTER INDEX idx_iot_measurements_part_metadata 
    RENAME TO idx_iot_measurements_metadata;

COMMIT;

-- Enable auto-partition trigger
CREATE TRIGGER trigger_auto_create_partition
    BEFORE INSERT ON iot_measurements
    FOR EACH ROW EXECUTE FUNCTION auto_create_partition();

-- ============================================================================
-- STEP 10: Final verification
-- ============================================================================
\echo 'Step 10: Final verification...'

SELECT 
    'iot_measurements (NOW PARTITIONED)' AS table_name,
    COUNT(*) AS rows,
    pg_size_pretty(pg_total_relation_size('iot_measurements')) AS size
FROM iot_measurements;

\echo ''
\echo '============================================'
\echo 'MIGRATION COMPLETED SUCCESSFULLY!'
\echo '============================================'
\echo 'The table iot_measurements is now partitioned'
\echo 'Old table backed up as: iot_measurements_old_backup'
\echo ''
\echo 'Next steps:'
\echo '1. Monitor the application for any issues'
\echo '2. Verify queries are working correctly'
\echo '3. After 7 days of stable operation, run 05_cleanup.sql'
\echo '============================================'

-- ============================================================================
-- End of migration script
-- ============================================================================
