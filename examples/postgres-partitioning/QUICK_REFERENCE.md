# Quick Reference: PostgreSQL Partitioning Migration

This is a quick reference for the PostgreSQL partitioning migration process. For detailed explanations, see [GUIDE.md](GUIDE.md).

## Prerequisites

- PostgreSQL 10+ (for declarative partitioning)
- Sufficient disk space (~2x table size during migration)
- Database backup taken
- Low-traffic period scheduled for switchover

## Quick Commands

### Option 1: Run Complete Migration (All-in-One)

```bash
psql -U your_user -d your_database -f complete_migration.sql
```

This runs all steps in sequence. **Best for**: Small to medium tables or test environments.

### Option 2: Run Step-by-Step (Recommended for Production)

```bash
# Step 1: Create original table (if testing)
psql -U your_user -d your_database -f 01_original_table.sql

# Step 2: Create partitioned structure
psql -U your_user -d your_database -f 02_create_partitioned_table.sql

# Step 3: Backfill data (this takes the most time)
psql -U your_user -d your_database -f 03_backfill_data.sql

# Step 4: Switchover (< 1 second downtime)
psql -U your_user -d your_database -f 04_switchover.sql

# Step 5: Cleanup (after 7+ days verification)
psql -U your_user -d your_database -f 05_cleanup.sql
```

**Best for**: Production environments where you want control over timing.

## Timeline

| Phase | Duration | Downtime | Description |
|-------|----------|----------|-------------|
| 1. Setup | 5-10 min | None | Create partitioned table |
| 2. Backfill | Hours* | None | Copy historical data |
| 3. Switchover | < 1 sec | Minimal | Rename tables |
| 4. Cleanup | 5-10 min | None | Remove old table |

\* Depends on data volume. Estimate: ~1 hour per 10 million rows.

## Key SQL Snippets

### Check Migration Progress

```sql
-- Compare row counts
SELECT 
    'original' AS table_name, 
    COUNT(*) AS rows 
FROM iot_measurements
UNION ALL
SELECT 
    'partitioned' AS table_name, 
    COUNT(*) AS rows 
FROM iot_measurements_partitioned;
```

### Monitor Table Sizes

```sql
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements%'
ORDER BY tablename;
```

### List All Partitions

```sql
SELECT 
    schemaname,
    tablename AS partition_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE tablename LIKE 'iot_measurements_y%'
ORDER BY tablename;
```

### Create New Partition Manually

```sql
SELECT create_partition_if_not_exists('2026-04-01'::DATE);
```

### Test Partition Pruning

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM iot_measurements
WHERE measured_at >= '2024-06-01' 
  AND measured_at < '2024-07-01';
```

Expected: Should only scan `iot_measurements_y2024m06` partition.

### Drop Old Partition

```sql
-- Archive data first if needed
DROP TABLE iot_measurements_y2024m01;
```

## Critical Safety Checks

### Before Switchover

```sql
-- Ensure row counts match (or partitioned >= original)
DO $$
DECLARE
    orig BIGINT;
    part BIGINT;
BEGIN
    SELECT COUNT(*) INTO orig FROM iot_measurements;
    SELECT COUNT(*) INTO part FROM iot_measurements_partitioned;
    
    IF part < orig THEN
        RAISE EXCEPTION 'Data missing! Original: %, Partitioned: %', orig, part;
    END IF;
    
    RAISE NOTICE 'Ready for switchover. Original: %, Partitioned: %', orig, part;
END $$;
```

### After Switchover

```sql
-- Test insert
INSERT INTO iot_measurements 
    (device_id, measurement_type, value, unit, measured_at)
VALUES 
    ('TEST_001', 'temperature', 25.5, 'celsius', CURRENT_TIMESTAMP);

-- Verify it went to correct partition
SELECT tableoid::regclass, * 
FROM iot_measurements 
WHERE device_id = 'TEST_001';

-- Clean up
DELETE FROM iot_measurements WHERE device_id = 'TEST_001';
```

## Troubleshooting

### Error: No partition found for row

**Cause:** Missing partition for the date range.

**Solution:**
```sql
-- Create missing partition
SELECT create_partition_if_not_exists('2026-05-01'::DATE);
```

### Error: Unique constraint must include partitioning columns

**Cause:** Primary key doesn't include partition key.

**Solution:** Include partition key in PRIMARY KEY:
```sql
PRIMARY KEY (id, measured_at)
```

### Migration too slow

**Solutions:**
1. Increase batch size in backfill script (line 99 in `03_backfill_data.sql`)
2. Drop indexes before backfill, recreate after
3. Increase PostgreSQL memory:
   ```sql
   SET maintenance_work_mem = '2GB';
   ```

### Out of disk space

**Check space:**
```bash
df -h
```

```sql
SELECT 
    pg_size_pretty(pg_database_size(current_database())) AS db_size,
    pg_size_pretty(pg_total_relation_size('iot_measurements')) AS old_table,
    pg_size_pretty(pg_total_relation_size('iot_measurements_partitioned')) AS new_table;
```

**Solution:** Free up space or use separate tablespace.

## Rollback Procedures

### Before Switchover

Simply drop the partitioned table:
```sql
DROP TABLE iot_measurements_partitioned CASCADE;
DROP TRIGGER trigger_buffer_measurements ON iot_measurements;
DROP TABLE iot_measurements_migration_buffer;
```

### After Switchover

Rename tables back:
```sql
BEGIN;
ALTER TABLE iot_measurements RENAME TO iot_measurements_partitioned;
ALTER TABLE iot_measurements_old_backup RENAME TO iot_measurements;
COMMIT;
```

## Performance Tuning

### Before Migration

```sql
-- Analyze tables
VACUUM ANALYZE iot_measurements;

-- Check table stats
SELECT 
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE tablename = 'iot_measurements';
```

### During Backfill

```sql
-- Monitor progress (in another session)
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query,
    query_start,
    state_change
FROM pg_stat_activity
WHERE query LIKE '%iot_measurements%'
  AND state != 'idle';
```

### After Migration

```sql
-- Update statistics
VACUUM ANALYZE iot_measurements;

-- Check partition sizes
SELECT 
    tablename,
    n_live_tup AS rows,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_stat_user_tables
WHERE tablename LIKE 'iot_measurements_y%'
ORDER BY tablename;
```

## Best Practices

1. **Test First**: Always test on a copy of production data
2. **Backup**: Take a full backup before starting
3. **Monitor**: Watch disk space, CPU, and I/O during migration
4. **Off-Peak**: Run during low-traffic hours
5. **Verify**: Compare checksums and row counts at each step
6. **Keep Backup**: Don't drop old table for at least 7 days
7. **Document**: Note any custom indexes or constraints
8. **Plan Ahead**: Create partitions for next 3 months in advance

## Maintenance Schedule

### Weekly
- Monitor partition sizes
- Check for missing partitions

### Monthly
- Create next month's partition
- Archive old partitions (if applicable)
- Review query performance

### Quarterly
- Drop archived partitions (after backup)
- Analyze partitioning strategy effectiveness
- Review and optimize indexes

## Validation Checklist

- [ ] Backup completed
- [ ] Row counts match (partitioned >= original)
- [ ] Sample queries return correct results
- [ ] Insert/Update/Delete operations work
- [ ] Application tests pass
- [ ] Partition pruning verified with EXPLAIN
- [ ] No missing partitions for current/future dates
- [ ] Indexes created on all partitions
- [ ] Triggers working (auto-partition creation)
- [ ] Old table backed up as `_old_backup`
- [ ] Migration buffer can be dropped

## Support

- **Documentation**: [GUIDE.md](GUIDE.md) - Detailed guide with examples
- **README**: [README.md](README.md) - Overview and file descriptions
- **PostgreSQL Docs**: https://www.postgresql.org/docs/current/ddl-partitioning.html

## Quick Links

- [Complete Migration Script](complete_migration.sql) - All-in-one migration
- [Validation Script](validate.sh) - Syntax and content validation
- [Practical Guide](GUIDE.md) - In-depth explanations and examples
