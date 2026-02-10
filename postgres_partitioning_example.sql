-- =====================================================================
-- Complete PostgreSQL Partitioning Example for IoT Device Measurements
-- =====================================================================
-- This example demonstrates how to safely convert an existing table
-- to a partitioned table while backfilling data without losing
-- incoming current data.
-- =====================================================================

-- STEP 1: Create the original table (existing scenario)
-- =====================================================================
-- This represents your existing table with IoT device measurements

CREATE TABLE IF NOT EXISTS iot_measurements (
    id BIGSERIAL,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    temperature NUMERIC(5, 2),
    humidity NUMERIC(5, 2),
    timestamp TIMESTAMPTZ NOT NULL,
    metadata JSONB,
    PRIMARY KEY (id, timestamp)
);

-- Create an index on timestamp for query performance
CREATE INDEX IF NOT EXISTS idx_iot_measurements_timestamp 
    ON iot_measurements (timestamp);

-- Create an index on device_id for filtering
CREATE INDEX IF NOT EXISTS idx_iot_measurements_device_id 
    ON iot_measurements (device_id);

-- =====================================================================
-- STEP 2: Insert sample data to simulate existing measurements
-- =====================================================================

INSERT INTO iot_measurements (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
SELECT 
    'DEVICE_' || (random() * 100)::int,
    CASE (random() * 3)::int
        WHEN 0 THEN 'temperature'
        WHEN 1 THEN 'humidity'
        ELSE 'pressure'
    END,
    (random() * 100)::numeric(10,2),
    (random() * 40 - 10)::numeric(5,2),
    (random() * 100)::numeric(5,2),
    timestamp '2023-01-01 00:00:00' + (random() * interval '730 days'),
    jsonb_build_object('location', 'Building A', 'floor', (random() * 5)::int)
FROM generate_series(1, 10000);

-- Verify initial data count
SELECT COUNT(*) as total_records FROM iot_measurements;

-- =====================================================================
-- STEP 3: Create the new partitioned table structure
-- =====================================================================
-- We'll partition by month using RANGE partitioning on timestamp

CREATE TABLE iot_measurements_partitioned (
    id BIGSERIAL,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    temperature NUMERIC(5, 2),
    humidity NUMERIC(5, 2),
    timestamp TIMESTAMPTZ NOT NULL,
    metadata JSONB,
    PRIMARY KEY (id, timestamp)
) PARTITION BY RANGE (timestamp);

-- =====================================================================
-- STEP 4: Create partitions for historical data
-- =====================================================================
-- Create partitions for 2023 (monthly partitions)

CREATE TABLE iot_measurements_y2023m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2023-02-01');

CREATE TABLE iot_measurements_y2023m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-02-01') TO ('2023-03-01');

CREATE TABLE iot_measurements_y2023m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-03-01') TO ('2023-04-01');

CREATE TABLE iot_measurements_y2023m04 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-04-01') TO ('2023-05-01');

CREATE TABLE iot_measurements_y2023m05 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-05-01') TO ('2023-06-01');

CREATE TABLE iot_measurements_y2023m06 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-06-01') TO ('2023-07-01');

CREATE TABLE iot_measurements_y2023m07 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-07-01') TO ('2023-08-01');

CREATE TABLE iot_measurements_y2023m08 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-08-01') TO ('2023-09-01');

CREATE TABLE iot_measurements_y2023m09 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-09-01') TO ('2023-10-01');

CREATE TABLE iot_measurements_y2023m10 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-10-01') TO ('2023-11-01');

CREATE TABLE iot_measurements_y2023m11 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-11-01') TO ('2023-12-01');

CREATE TABLE iot_measurements_y2023m12 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2023-12-01') TO ('2024-01-01');

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

-- Create partitions for 2025 and beyond

CREATE TABLE iot_measurements_y2025m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE iot_measurements_y2025m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

CREATE TABLE iot_measurements_y2025m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');

-- Default partition for future data (recommended for safety)
CREATE TABLE iot_measurements_default PARTITION OF iot_measurements_partitioned DEFAULT;

-- =====================================================================
-- STEP 5: Create indexes on the partitioned table
-- =====================================================================
-- Indexes are automatically inherited by partitions

CREATE INDEX idx_iot_measurements_partitioned_timestamp 
    ON iot_measurements_partitioned (timestamp);

CREATE INDEX idx_iot_measurements_partitioned_device_id 
    ON iot_measurements_partitioned (device_id);

CREATE INDEX idx_iot_measurements_partitioned_device_timestamp 
    ON iot_measurements_partitioned (device_id, timestamp);

-- =====================================================================
-- STEP 6: Create a trigger-based routing mechanism
-- =====================================================================
-- This ensures new data goes to the partitioned table during migration

-- Create a tracking table to monitor migration progress
CREATE TABLE IF NOT EXISTS migration_status (
    id SERIAL PRIMARY KEY,
    batch_number INT NOT NULL,
    start_timestamp TIMESTAMPTZ,
    end_timestamp TIMESTAMPTZ,
    rows_migrated BIGINT,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'in_progress'
);

-- Create a function to route new inserts to the partitioned table
CREATE OR REPLACE FUNCTION route_to_partitioned_table()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO iot_measurements_partitioned 
        (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
    VALUES 
        (NEW.device_id, NEW.measurement_type, NEW.value, NEW.temperature, NEW.humidity, NEW.timestamp, NEW.metadata);
    RETURN NULL; -- Don't insert into the original table
END;
$$ LANGUAGE plpgsql;

-- Create the trigger (we'll activate this during the migration)
CREATE TRIGGER route_inserts_to_partitioned
    BEFORE INSERT ON iot_measurements
    FOR EACH ROW
    EXECUTE FUNCTION route_to_partitioned_table();

-- Initially disable the trigger
ALTER TABLE iot_measurements DISABLE TRIGGER route_inserts_to_partitioned;

-- =====================================================================
-- STEP 7: Safe Migration Strategy
-- =====================================================================

-- 7.1: Take a snapshot of the current max ID before starting migration
CREATE TABLE IF NOT EXISTS migration_checkpoint (
    checkpoint_name VARCHAR(50) PRIMARY KEY,
    checkpoint_value BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO migration_checkpoint (checkpoint_name, checkpoint_value)
SELECT 'max_id_before_migration', COALESCE(MAX(id), 0)
FROM iot_measurements;

-- 7.2: Enable the routing trigger to send new data to partitioned table
ALTER TABLE iot_measurements ENABLE TRIGGER route_inserts_to_partitioned;

-- 7.3: Backfill historical data in batches
-- This is done in batches to avoid locking the table for too long

DO $$
DECLARE
    batch_size INT := 1000;
    current_id BIGINT := 0;
    max_id_to_migrate BIGINT;
    rows_affected BIGINT;
    batch_num INT := 0;
    start_ts TIMESTAMPTZ;
    end_ts TIMESTAMPTZ;
BEGIN
    -- Get the max ID to migrate (data that existed before migration started)
    SELECT checkpoint_value INTO max_id_to_migrate 
    FROM migration_checkpoint 
    WHERE checkpoint_name = 'max_id_before_migration';
    
    RAISE NOTICE 'Starting migration up to ID: %', max_id_to_migrate;
    
    LOOP
        batch_num := batch_num + 1;
        
        -- Get timestamp range for this batch
        SELECT MIN(timestamp), MAX(timestamp)
        INTO start_ts, end_ts
        FROM (
            SELECT timestamp 
            FROM iot_measurements 
            WHERE id > current_id AND id <= max_id_to_migrate
            ORDER BY id 
            LIMIT batch_size
        ) batch;
        
        EXIT WHEN start_ts IS NULL;
        
        -- Insert batch into partitioned table
        WITH batch_data AS (
            SELECT * 
            FROM iot_measurements 
            WHERE id > current_id AND id <= max_id_to_migrate
            ORDER BY id 
            LIMIT batch_size
        )
        INSERT INTO iot_measurements_partitioned 
            (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
        SELECT device_id, measurement_type, value, temperature, humidity, timestamp, metadata
        FROM batch_data;
        
        GET DIAGNOSTICS rows_affected = ROW_COUNT;
        
        -- Update current_id for next batch
        SELECT MAX(id) INTO current_id 
        FROM (
            SELECT id 
            FROM iot_measurements 
            WHERE id > current_id AND id <= max_id_to_migrate
            ORDER BY id 
            LIMIT batch_size
        ) batch;
        
        -- Log progress
        INSERT INTO migration_status 
            (batch_number, start_timestamp, end_timestamp, rows_migrated, completed_at, status)
        VALUES 
            (batch_num, start_ts, end_ts, rows_affected, NOW(), 'completed');
        
        RAISE NOTICE 'Batch % completed: % rows migrated (ID range up to %)', 
            batch_num, rows_affected, current_id;
        
        -- Small delay to allow other transactions (optional)
        PERFORM pg_sleep(0.1);
        
        EXIT WHEN current_id >= max_id_to_migrate OR current_id IS NULL;
    END LOOP;
    
    RAISE NOTICE 'Migration completed! Total batches: %', batch_num;
END $$;

-- =====================================================================
-- STEP 8: Verification
-- =====================================================================

-- 8.1: Compare row counts
SELECT 
    'Original Table' as table_name,
    COUNT(*) as row_count
FROM iot_measurements
WHERE id <= (SELECT checkpoint_value FROM migration_checkpoint WHERE checkpoint_name = 'max_id_before_migration')
UNION ALL
SELECT 
    'Partitioned Table' as table_name,
    COUNT(*) as row_count
FROM iot_measurements_partitioned;

-- 8.2: Verify data integrity with checksums
SELECT 
    'Original Table' as source,
    COUNT(*) as count,
    SUM(value) as sum_value,
    MIN(timestamp) as min_timestamp,
    MAX(timestamp) as max_timestamp
FROM iot_measurements
WHERE id <= (SELECT checkpoint_value FROM migration_checkpoint WHERE checkpoint_name = 'max_id_before_migration')
UNION ALL
SELECT 
    'Partitioned Table' as source,
    COUNT(*) as count,
    SUM(value) as sum_value,
    MIN(timestamp) as min_timestamp,
    MAX(timestamp) as max_timestamp
FROM iot_measurements_partitioned;

-- 8.3: View migration statistics
SELECT 
    batch_number,
    start_timestamp,
    end_timestamp,
    rows_migrated,
    completed_at - started_at as duration,
    status
FROM migration_status
ORDER BY batch_number;

-- 8.4: Check partition distribution
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements_y%' OR tablename = 'iot_measurements_default'
ORDER BY tablename;

-- =====================================================================
-- STEP 9: Test new inserts during migration
-- =====================================================================

-- Insert new data while migration is in progress
INSERT INTO iot_measurements (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
VALUES 
    ('DEVICE_TEST_001', 'temperature', 25.5, 25.5, 60.0, NOW(), '{"test": true}'),
    ('DEVICE_TEST_002', 'humidity', 65.0, 22.0, 65.0, NOW(), '{"test": true}');

-- Verify new data went to partitioned table
SELECT * FROM iot_measurements_partitioned 
WHERE device_id LIKE 'DEVICE_TEST_%'
ORDER BY timestamp DESC;

-- =====================================================================
-- STEP 10: Final Cutover
-- =====================================================================

-- Once verification is complete and you're confident:

-- 10.1: Rename tables to complete the migration
BEGIN;

-- Disable the trigger first
ALTER TABLE iot_measurements DISABLE TRIGGER route_inserts_to_partitioned;

-- Rename the original table to backup
ALTER TABLE iot_measurements RENAME TO iot_measurements_backup;

-- Rename the partitioned table to the original name
ALTER TABLE iot_measurements_partitioned RENAME TO iot_measurements;

-- Update the trigger function to work with the new table name
DROP TRIGGER IF EXISTS route_inserts_to_partitioned ON iot_measurements_backup;
DROP FUNCTION IF EXISTS route_to_partitioned_table();

COMMIT;

-- 10.2: Verify the switch
SELECT 
    tablename, 
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE tablename IN ('iot_measurements', 'iot_measurements_backup')
ORDER BY tablename;

-- 10.3: Test inserts work on the new partitioned table
INSERT INTO iot_measurements (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
VALUES 
    ('DEVICE_FINAL_TEST', 'temperature', 23.5, 23.5, 55.0, NOW(), '{"final_test": true}');

-- Verify insert
SELECT * FROM iot_measurements 
WHERE device_id = 'DEVICE_FINAL_TEST';

-- =====================================================================
-- STEP 11: Cleanup (After verification period)
-- =====================================================================

-- After confirming everything works for a few days/weeks:
-- DROP TABLE iot_measurements_backup;
-- DROP TABLE migration_status;
-- DROP TABLE migration_checkpoint;

-- =====================================================================
-- STEP 12: Automatic Partition Creation (Maintenance)
-- =====================================================================

-- Create a function to automatically create future partitions
CREATE OR REPLACE FUNCTION create_partition_for_month(target_date DATE)
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Calculate the first day of the month
    start_date := DATE_TRUNC('month', target_date);
    -- Calculate the first day of the next month
    end_date := start_date + INTERVAL '1 month';
    
    -- Generate partition name
    partition_name := 'iot_measurements_y' || 
                      TO_CHAR(start_date, 'YYYY') || 'm' || 
                      TO_CHAR(start_date, 'MM');
    
    -- Check if partition already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE tablename = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF iot_measurements FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            start_date,
            end_date
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    ELSE
        RAISE NOTICE 'Partition % already exists', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create partitions for the next 6 months
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..5 LOOP
        PERFORM create_partition_for_month(CURRENT_DATE + (i || ' months')::INTERVAL);
    END LOOP;
END $$;

-- =====================================================================
-- STEP 13: Partition Maintenance Scripts
-- =====================================================================

-- Drop old partitions (e.g., older than 2 years)
CREATE OR REPLACE FUNCTION drop_old_partitions(retention_months INT)
RETURNS void AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
BEGIN
    cutoff_date := DATE_TRUNC('month', CURRENT_DATE - (retention_months || ' months')::INTERVAL);
    
    FOR partition_record IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE tablename LIKE 'iot_measurements_y%'
        AND tablename != 'iot_measurements_default'
    LOOP
        -- Extract date from partition name and check if it's older than cutoff
        DECLARE
            partition_date DATE;
            year_part TEXT;
            month_part TEXT;
        BEGIN
            year_part := SUBSTRING(partition_record.tablename FROM 'y(\d{4})');
            month_part := SUBSTRING(partition_record.tablename FROM 'm(\d{2})');
            
            IF year_part IS NOT NULL AND month_part IS NOT NULL THEN
                partition_date := (year_part || '-' || month_part || '-01')::DATE;
                
                IF partition_date < cutoff_date THEN
                    EXECUTE format('DROP TABLE IF EXISTS %I', partition_record.tablename);
                    RAISE NOTICE 'Dropped old partition: %', partition_record.tablename;
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not process partition: %', partition_record.tablename;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Example: Drop partitions older than 24 months
-- SELECT drop_old_partitions(24);

-- =====================================================================
-- STEP 14: Useful Monitoring Queries
-- =====================================================================

-- View all partitions with their data ranges and sizes
SELECT 
    pt.relname AS partition_name,
    pg_get_expr(pt.relpartbound, pt.oid, true) AS partition_range,
    pg_size_pretty(pg_total_relation_size(pt.oid)) AS size,
    (SELECT COUNT(*) FROM ONLY pg_tables WHERE tablename = pt.relname) as exists
FROM pg_class base_tb
JOIN pg_inherits i ON i.inhparent = base_tb.oid
JOIN pg_class pt ON pt.oid = i.inhrelid
WHERE base_tb.relname = 'iot_measurements'
ORDER BY pt.relname;

-- Get partition constraint information
SELECT 
    nmsp_parent.nspname AS schema_name,
    parent.relname AS table_name,
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS partition_expression
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
WHERE parent.relname = 'iot_measurements'
ORDER BY partition_name;

-- =====================================================================
-- ROLLBACK PLAN (If something goes wrong)
-- =====================================================================

-- If you need to rollback the migration:
/*
BEGIN;

-- 1. Rename tables back
ALTER TABLE iot_measurements RENAME TO iot_measurements_partitioned;
ALTER TABLE iot_measurements_backup RENAME TO iot_measurements;

-- 2. Re-enable the routing trigger if needed
CREATE OR REPLACE FUNCTION route_to_partitioned_table()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO iot_measurements_partitioned 
        (device_id, measurement_type, value, temperature, humidity, timestamp, metadata)
    VALUES 
        (NEW.device_id, NEW.measurement_type, NEW.value, NEW.temperature, NEW.humidity, NEW.timestamp, NEW.metadata);
    RETURN NEW; -- Allow insert into original table too
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER route_inserts_to_partitioned
    AFTER INSERT ON iot_measurements
    FOR EACH ROW
    EXECUTE FUNCTION route_to_partitioned_table();

COMMIT;
*/

-- =====================================================================
-- NOTES AND BEST PRACTICES
-- =====================================================================

/*
1. LOCKING CONSIDERATIONS:
   - The trigger-based approach minimizes locking
   - Batched migration prevents long-running transactions
   - New data continues to flow during migration

2. PARTITION KEY SELECTION:
   - timestamp is ideal for time-series IoT data
   - Monthly partitions balance granularity and management overhead
   - Consider weekly partitions for extremely high-volume systems

3. PARTITION MAINTENANCE:
   - Automate partition creation for future dates
   - Implement partition pruning for old data
   - Monitor partition sizes and adjust strategy if needed

4. PERFORMANCE BENEFITS:
   - Queries with timestamp filters will scan fewer partitions
   - Partition pruning significantly improves query performance
   - Easier to drop old data (just drop old partitions)
   - Better vacuum and analyze performance on smaller partitions

5. MONITORING:
   - Track migration progress with migration_status table
   - Verify data integrity before final cutover
   - Keep backup table for safety period (e.g., 30 days)

6. TESTING:
   - Test the migration on a copy/staging environment first
   - Verify all application queries work with partitioned table
   - Test partition creation automation
   - Validate backup and restore procedures

7. APPLICATION CHANGES:
   - Most applications work without changes
   - Ensure timestamp is included in all WHERE clauses for best performance
   - Update any queries that rely on table structure

8. ALTERNATIVE APPROACHES:
   - Logical replication (for minimal downtime)
   - pg_partman extension (for automated partition management)
   - Foreign data wrappers (for external data sources)
*/
