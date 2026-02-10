-- ============================================================================
-- 05_cleanup.sql
-- ============================================================================
-- This script cleans up temporary resources after successful migration.
-- ONLY run this after verifying the partitioned table is working correctly
-- for several days in production.
-- ============================================================================

-- SAFETY WARNING: This script drops the old table and migration artifacts.
-- Make sure you have:
-- 1. Verified data integrity in the partitioned table
-- 2. Tested all application queries against the partitioned table
-- 3. Taken a final backup of the old table
-- 4. Run this during a maintenance window

-- Step 1: Final verification before cleanup
DO $$
DECLARE
    new_count BIGINT;
    old_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO new_count FROM iot_measurements;
    SELECT COUNT(*) INTO old_count FROM iot_measurements_old_backup;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'PRE-CLEANUP VERIFICATION';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Current partitioned table rows: %', new_count;
    RAISE NOTICE 'Old backup table rows: %', old_count;
    
    IF new_count < old_count THEN
        RAISE EXCEPTION 'New table has fewer rows than backup! Aborting cleanup.';
    ELSE
        RAISE NOTICE 'Row count check passed.';
    END IF;
    RAISE NOTICE '========================================';
END $$;

-- Step 2: Display table sizes before cleanup
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE tablename IN ('iot_measurements', 'iot_measurements_old_backup', 
                    'iot_measurements_migration_buffer')
ORDER BY tablename;

-- Step 3: Optional - Create a final backup dump before dropping
-- This is a safety measure you can run manually:
-- pg_dump -U your_user -d your_database -t iot_measurements_old_backup -F c -f iot_measurements_old_backup.dump

-- Step 4: Drop the old table and its indexes
DO $$
BEGIN
    DROP TABLE IF EXISTS iot_measurements_old_backup CASCADE;
    RAISE NOTICE 'Dropped old backup table: iot_measurements_old_backup';
END $$;

-- Step 5: Drop the migration buffer table
DO $$
BEGIN
    DROP TABLE IF EXISTS iot_measurements_migration_buffer CASCADE;
    RAISE NOTICE 'Dropped migration buffer table: iot_measurements_migration_buffer';
END $$;

-- Step 6: Drop the buffer function (no longer needed)
DO $$
BEGIN
    DROP FUNCTION IF EXISTS buffer_new_measurements() CASCADE;
    RAISE NOTICE 'Dropped migration buffer function';
END $$;

-- Step 7: Drop the temporary snapshot table
DO $$
BEGIN
    DROP TABLE IF EXISTS migration_snapshot;
    RAISE NOTICE 'Dropped migration snapshot table';
END $$;

-- Step 8: Vacuum to reclaim disk space
VACUUM FULL iot_measurements;

DO $$
BEGIN
    RAISE NOTICE 'Vacuum completed on iot_measurements';
END $$;

-- Step 9: Verify remaining objects
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements%'
ORDER BY tablename;

-- List all functions related to iot_measurements
SELECT 
    n.nspname AS schema,
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname LIKE '%partition%'
   OR p.proname LIKE '%measurement%'
ORDER BY p.proname;

-- List all triggers on iot_measurements
SELECT 
    tgname AS trigger_name,
    tgrelid::regclass AS table_name,
    tgenabled AS enabled,
    pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE tgrelid::regclass::text LIKE '%iot_measurements%'
  AND tgisinternal = false;

-- Step 10: Final statistics
DO $$
DECLARE
    total_rows BIGINT;
    partition_count INTEGER;
    total_size TEXT;
BEGIN
    SELECT COUNT(*) INTO total_rows FROM iot_measurements;
    
    SELECT COUNT(*) INTO partition_count
    FROM pg_tables
    WHERE tablename LIKE 'iot_measurements_y%';
    
    SELECT pg_size_pretty(pg_total_relation_size('iot_measurements')) 
    INTO total_size;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'CLEANUP COMPLETED SUCCESSFULLY';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Final statistics:';
    RAISE NOTICE '  - Total rows: %', total_rows;
    RAISE NOTICE '  - Number of partitions: %', partition_count;
    RAISE NOTICE '  - Total size: %', total_size;
    RAISE NOTICE '';
    RAISE NOTICE 'Migration artifacts cleaned up:';
    RAISE NOTICE '  - Old backup table: DROPPED';
    RAISE NOTICE '  - Migration buffer: DROPPED';
    RAISE NOTICE '  - Temporary functions: DROPPED';
    RAISE NOTICE '';
    RAISE NOTICE 'Retained resources:';
    RAISE NOTICE '  - create_partition_if_not_exists() function';
    RAISE NOTICE '  - auto_create_partition() function';
    RAISE NOTICE '  - trigger_auto_create_partition trigger';
    RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- Notes:
-- - Old table and migration artifacts have been removed
-- - Disk space reclaimed through VACUUM FULL
-- - Auto-partition functions and triggers remain active
-- - Monitor the database for a few days to ensure everything works correctly
-- - Set up automated partition creation for future months
-- - Consider creating a cron job or scheduled task to create partitions ahead
-- 
-- Recommended next steps:
-- 1. Update application documentation
-- 2. Update database backup procedures
-- 3. Set up monitoring for partition usage
-- 4. Create alerts for when partitions are getting full
-- 5. Schedule regular partition maintenance
-- ============================================================================
