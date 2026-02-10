-- ============================================================================
-- 02_create_partitioned_table.sql
-- ============================================================================
-- This script creates the new partitioned table structure and partitions.
-- The table is partitioned by measurement timestamp (monthly partitions).
-- ============================================================================

-- Step 1: Create the partitioned table
-- Note: We use a different name to avoid conflicts with the existing table
CREATE TABLE iot_measurements_partitioned (
    id BIGSERIAL,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    unit VARCHAR(20),
    measured_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    
    -- The partition key MUST be part of the PRIMARY KEY
    PRIMARY KEY (id, measured_at)
) PARTITION BY RANGE (measured_at);

-- Add the same check constraint as the original table
ALTER TABLE iot_measurements_partitioned 
    ADD CONSTRAINT chk_measured_at_not_future_partitioned
    CHECK (measured_at <= CURRENT_TIMESTAMP);

-- Step 2: Create partitions for historical data
-- These cover the date range of existing data (adjust based on your data)

-- 2024 partitions
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

-- 2025 partitions (for ongoing data)
CREATE TABLE iot_measurements_y2025m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE iot_measurements_y2025m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

CREATE TABLE iot_measurements_y2025m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');

-- 2026 partitions (for future data)
CREATE TABLE iot_measurements_y2026m01 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE iot_measurements_y2026m02 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE iot_measurements_y2026m03 PARTITION OF iot_measurements_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- Step 3: Create indexes on the partitioned table
-- These will automatically be created on each partition

CREATE INDEX idx_iot_measurements_part_device_id 
    ON iot_measurements_partitioned(device_id);

CREATE INDEX idx_iot_measurements_part_measured_at 
    ON iot_measurements_partitioned(measured_at DESC);

CREATE INDEX idx_iot_measurements_part_device_time 
    ON iot_measurements_partitioned(device_id, measured_at DESC);

CREATE INDEX idx_iot_measurements_part_metadata 
    ON iot_measurements_partitioned USING gin(metadata);

-- Step 4: Create a function to automatically create new partitions
-- This is useful for ongoing operations to avoid manual partition creation
CREATE OR REPLACE FUNCTION create_partition_if_not_exists(
    partition_date DATE
) RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Calculate partition boundaries (monthly)
    start_date := DATE_TRUNC('month', partition_date)::DATE;
    end_date := (start_date + INTERVAL '1 month')::DATE;
    
    -- Generate partition name
    partition_name := 'iot_measurements_y' || 
                      TO_CHAR(start_date, 'YYYY') || 'm' || 
                      TO_CHAR(start_date, 'MM');
    
    -- Check if partition exists
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
    ) THEN
        -- Create the partition
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF iot_measurements_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            start_date,
            end_date
        );
        
        RAISE NOTICE 'Created partition: %', partition_name;
    ELSE
        RAISE NOTICE 'Partition already exists: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create a trigger function to auto-create partitions on insert
CREATE OR REPLACE FUNCTION auto_create_partition() 
RETURNS TRIGGER AS $$
BEGIN
    PERFORM create_partition_if_not_exists(NEW.measured_at::DATE);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger (will be activated after switchover)
-- Commented out for now - will be enabled in step 4
-- CREATE TRIGGER trigger_auto_create_partition
--     BEFORE INSERT ON iot_measurements_partitioned
--     FOR EACH ROW EXECUTE FUNCTION auto_create_partition();

-- Display created partitions
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements_y%'
ORDER BY tablename;

-- ============================================================================
-- Notes:
-- - Partitioned table created with monthly partitions
-- - Indexes will be automatically created on all partitions
-- - Auto-partition creation function ready for future use
-- - Partitions cover historical, current, and future dates
-- - Primary key includes the partition key (measured_at) as required
-- - Next step: Backfill data from the original table
-- ============================================================================
