-- ============================================================================
-- 01_original_table.sql
-- ============================================================================
-- This script creates the original (non-partitioned) IoT measurements table
-- with sample data to demonstrate the partitioning migration process.
-- ============================================================================

-- Create the original table structure
-- This represents a typical IoT measurements table before partitioning
CREATE TABLE IF NOT EXISTS iot_measurements (
    id BIGSERIAL PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    measurement_type VARCHAR(50) NOT NULL,
    value NUMERIC(10, 2) NOT NULL,
    unit VARCHAR(20),
    measured_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Create indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_iot_measurements_device_id 
    ON iot_measurements(device_id);

CREATE INDEX IF NOT EXISTS idx_iot_measurements_measured_at 
    ON iot_measurements(measured_at DESC);

CREATE INDEX IF NOT EXISTS idx_iot_measurements_device_time 
    ON iot_measurements(device_id, measured_at DESC);

-- Create index on metadata JSONB field for better query performance
CREATE INDEX IF NOT EXISTS idx_iot_measurements_metadata 
    ON iot_measurements USING gin(metadata);

-- Add check constraint to ensure data quality
ALTER TABLE iot_measurements 
    ADD CONSTRAINT chk_measured_at_not_future 
    CHECK (measured_at <= CURRENT_TIMESTAMP);

-- Insert sample data for demonstration
-- This simulates historical IoT data over several months
INSERT INTO iot_measurements (device_id, measurement_type, value, unit, measured_at, metadata)
SELECT 
    'DEVICE_' || LPAD((id % 100)::TEXT, 3, '0') AS device_id,
    CASE (id % 4)
        WHEN 0 THEN 'temperature'
        WHEN 1 THEN 'humidity'
        WHEN 2 THEN 'pressure'
        ELSE 'voltage'
    END AS measurement_type,
    ROUND((RANDOM() * 100)::NUMERIC, 2) AS value,
    CASE (id % 4)
        WHEN 0 THEN 'celsius'
        WHEN 1 THEN 'percent'
        WHEN 2 THEN 'hPa'
        ELSE 'volts'
    END AS unit,
    TIMESTAMP '2024-01-01 00:00:00' + 
        (id * INTERVAL '5 minutes') AS measured_at,
    jsonb_build_object(
        'location', 
        CASE (id % 3)
            WHEN 0 THEN 'warehouse_a'
            WHEN 1 THEN 'warehouse_b'
            ELSE 'warehouse_c'
        END,
        'sensor_status', 'active'
    ) AS metadata
FROM generate_series(1, 100000) AS id
WHERE NOT EXISTS (
    SELECT 1 FROM iot_measurements LIMIT 1
);

-- Display table statistics
SELECT 
    'iot_measurements' AS table_name,
    COUNT(*) AS total_rows,
    MIN(measured_at) AS earliest_measurement,
    MAX(measured_at) AS latest_measurement,
    pg_size_pretty(pg_total_relation_size('iot_measurements')) AS total_size
FROM iot_measurements;

-- Display sample data
SELECT * FROM iot_measurements 
ORDER BY measured_at DESC 
LIMIT 10;

VACUUM ANALYZE iot_measurements;

-- ============================================================================
-- Notes:
-- - This creates a table with sample data spanning several months
-- - The table uses a simple BIGSERIAL primary key
-- - Indexes are created for typical IoT query patterns
-- - Sample data includes various measurement types from multiple devices
-- - The table is now ready for the partitioning migration process
-- ============================================================================
