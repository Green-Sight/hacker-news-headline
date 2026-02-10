# PostgreSQL Partitioning - Quick Reference Guide

## Quick Start Checklist

Use this checklist when implementing table partitioning:

- [ ] **Backup your database** before starting
- [ ] **Test on staging** environment first
- [ ] **Identify partition key** (usually timestamp for time-series data)
- [ ] **Calculate partition size** (aim for 10-100 GB per partition)
- [ ] **Create partitioned table structure**
- [ ] **Create initial partitions** (historical + current + 6 months future)
- [ ] **Enable dual-write trigger** to route new data
- [ ] **Backfill historical data** in batches
- [ ] **Verify data integrity** (row counts, checksums)
- [ ] **Monitor application** for errors
- [ ] **Perform cutover** (rename tables)
- [ ] **Keep backup table** for 30+ days
- [ ] **Schedule partition maintenance** (create future, drop old)

## Command Cheat Sheet

### 1. Check Current Table Size
```sql
SELECT 
    pg_size_pretty(pg_total_relation_size('iot_measurements')) as size,
    COUNT(*) as rows
FROM iot_measurements;
```

### 2. Identify Date Range
```sql
SELECT 
    MIN(timestamp) as earliest,
    MAX(timestamp) as latest,
    MAX(timestamp) - MIN(timestamp) as span
FROM iot_measurements;
```

### 3. Create Partitioned Table
```sql
CREATE TABLE iot_measurements_new (
    -- same columns as original
) PARTITION BY RANGE (timestamp);
```

### 4. Create Monthly Partition
```sql
CREATE TABLE iot_measurements_y2024m01 
PARTITION OF iot_measurements_new
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### 5. Enable Routing Trigger
```sql
CREATE TRIGGER route_inserts
    BEFORE INSERT ON iot_measurements
    FOR EACH ROW EXECUTE FUNCTION route_to_partitioned();

ALTER TABLE iot_measurements ENABLE TRIGGER route_inserts;
```

### 6. Backfill in Batches
```sql
-- Record checkpoint
INSERT INTO migration_checkpoint VALUES ('max_id', (SELECT MAX(id) FROM iot_measurements));

-- Backfill (in DO block or loop)
INSERT INTO iot_measurements_new
SELECT * FROM iot_measurements
WHERE id BETWEEN ? AND ?;  -- batch range
```

### 7. Verify Migration
```sql
-- Compare counts
SELECT COUNT(*) FROM iot_measurements;
SELECT COUNT(*) FROM iot_measurements_new;

-- Compare checksums
SELECT SUM(value), MIN(timestamp), MAX(timestamp) FROM iot_measurements;
SELECT SUM(value), MIN(timestamp), MAX(timestamp) FROM iot_measurements_new;
```

### 8. Perform Cutover
```sql
BEGIN;
ALTER TABLE iot_measurements RENAME TO iot_measurements_backup;
ALTER TABLE iot_measurements_new RENAME TO iot_measurements;
COMMIT;
```

### 9. Test After Cutover
```sql
-- Insert test record
INSERT INTO iot_measurements VALUES (...);

-- Verify it went to correct partition
EXPLAIN SELECT * FROM iot_measurements 
WHERE timestamp = '2024-01-15';
```

### 10. Create Future Partitions
```sql
-- Automated approach
SELECT create_partition_for_month(CURRENT_DATE + interval '1 month');
SELECT create_partition_for_month(CURRENT_DATE + interval '2 months');
-- ... up to 6 months ahead
```

## Common Partition Strategies

### By Time (Range Partitioning)

**Daily Partitions** - Very high volume
```sql
CREATE TABLE measurements_20240115 PARTITION OF measurements
FOR VALUES FROM ('2024-01-15') TO ('2024-01-16');
```

**Weekly Partitions** - High volume
```sql
CREATE TABLE measurements_2024w03 PARTITION OF measurements
FOR VALUES FROM ('2024-01-15') TO ('2024-01-22');
```

**Monthly Partitions** - Medium volume (Recommended for IoT)
```sql
CREATE TABLE measurements_2024m01 PARTITION OF measurements
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

**Yearly Partitions** - Low volume
```sql
CREATE TABLE measurements_2024 PARTITION OF measurements
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### By Category (List Partitioning)

**By Region**
```sql
CREATE TABLE measurements (
    ...
) PARTITION BY LIST (region);

CREATE TABLE measurements_us PARTITION OF measurements
FOR VALUES IN ('US', 'USA');

CREATE TABLE measurements_eu PARTITION OF measurements
FOR VALUES IN ('EU', 'UK', 'DE', 'FR');
```

**By Device Type**
```sql
CREATE TABLE measurements (
    ...
) PARTITION BY LIST (device_type);

CREATE TABLE measurements_sensors PARTITION OF measurements
FOR VALUES IN ('sensor', 'temperature_sensor', 'humidity_sensor');

CREATE TABLE measurements_cameras PARTITION OF measurements
FOR VALUES IN ('camera', 'webcam', 'security_cam');
```

### By Hash (Balanced Distribution)

**By Device ID**
```sql
CREATE TABLE measurements (
    ...
) PARTITION BY HASH (device_id);

CREATE TABLE measurements_p0 PARTITION OF measurements
FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE measurements_p1 PARTITION OF measurements
FOR VALUES WITH (MODULUS 4, REMAINDER 1);
-- ... p2, p3
```

## Performance Tips

### ✅ DO

1. **Always include partition key in WHERE clause**
   ```sql
   WHERE timestamp >= '2024-01-01' AND timestamp < '2024-02-01'
   ```

2. **Use EXPLAIN to verify partition pruning**
   ```sql
   EXPLAIN (ANALYZE, VERBOSE) SELECT ...
   ```

3. **Create appropriate indexes on partitioned table**
   ```sql
   CREATE INDEX ON iot_measurements (device_id);
   -- Automatically created on all partitions
   ```

4. **Use DEFAULT partition for safety**
   ```sql
   CREATE TABLE measurements_default PARTITION OF measurements DEFAULT;
   ```

5. **Monitor partition sizes regularly**
   ```sql
   SELECT tablename, pg_size_pretty(pg_total_relation_size(...))
   FROM pg_tables WHERE tablename LIKE 'measurements_%';
   ```

### ❌ DON'T

1. **Don't omit partition key from queries**
   ```sql
   -- BAD: Scans all partitions
   SELECT * FROM measurements WHERE device_id = 'X';
   
   -- GOOD: Uses partition pruning
   SELECT * FROM measurements 
   WHERE device_id = 'X' AND timestamp >= '2024-01-01';
   ```

2. **Don't create too many small partitions**
   - Overhead increases with partition count
   - Aim for 10-100 GB per partition

3. **Don't forget the DEFAULT partition**
   - Prevents errors for unexpected date ranges

4. **Don't skip verification**
   - Always verify data integrity after migration

5. **Don't drop backup immediately**
   - Keep for at least 30 days

## Troubleshooting

### Issue: "no partition of relation found for row"

**Cause:** Trying to insert data outside existing partition ranges

**Fix:**
```sql
-- Create missing partition
CREATE TABLE measurements_y2025m06 PARTITION OF measurements
FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');

-- Or use DEFAULT partition
CREATE TABLE measurements_default PARTITION OF measurements DEFAULT;
```

### Issue: Slow queries after partitioning

**Cause:** Not using partition key in WHERE clause

**Fix:**
```sql
-- Add timestamp filter
SELECT * FROM measurements
WHERE timestamp >= CURRENT_DATE - INTERVAL '7 days'
  AND device_id = 'X';
```

**Verify with EXPLAIN:**
```sql
EXPLAIN SELECT ...
-- Look for: "Partitions removed: X"
```

### Issue: Migration taking too long

**Fix:** Increase batch size or reduce delays
```sql
DO $$
DECLARE
    batch_size INT := 10000;  -- Increased from 1000
    -- Remove or reduce pg_sleep()
```

### Issue: Disk space running low

**Fix:** Drop old partitions or use tablespaces
```sql
-- Drop old partitions
DROP TABLE measurements_2022m01;

-- Or create on different tablespace
CREATE TABLESPACE archive LOCATION '/mnt/archive';
CREATE TABLE measurements_2024m01 PARTITION OF measurements
FOR VALUES FROM (...) TO (...)
TABLESPACE archive;
```

### Issue: Duplicate data detected

**Fix:** Remove duplicates before finalizing
```sql
-- Find duplicates
SELECT device_id, timestamp, COUNT(*)
FROM iot_measurements_new
GROUP BY device_id, timestamp
HAVING COUNT(*) > 1;

-- Remove duplicates (keep first occurrence)
DELETE FROM iot_measurements_new a
USING iot_measurements_new b
WHERE a.id > b.id 
  AND a.device_id = b.device_id 
  AND a.timestamp = b.timestamp;
```

## Monitoring Queries

### Check Partition Pruning
```sql
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT * FROM measurements
WHERE timestamp >= '2024-01-01' AND timestamp < '2024-02-01';

-- Look for "Partitions removed by partition pruning"
```

### List All Partitions
```sql
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE tablename LIKE 'measurements_%'
ORDER BY tablename;
```

### Find Slow Queries
```sql
-- Enable extension first
CREATE EXTENSION pg_stat_statements;

-- Find slow queries
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
WHERE query LIKE '%measurements%'
ORDER BY mean_time DESC
LIMIT 10;
```

### Check Migration Progress
```sql
SELECT 
    batch_number,
    rows_migrated,
    completed_at - started_at as duration,
    status
FROM migration_status
ORDER BY batch_number DESC
LIMIT 10;
```

## Maintenance Schedule

### Daily
- Monitor partition sizes
- Check for failed inserts
- Verify DEFAULT partition is empty

### Weekly
- Create partitions for next month
- Check query performance
- Review slow query log

### Monthly
- Review partition strategy
- Drop old partitions (if retention policy)
- Vacuum and analyze partitioned table

### Quarterly
- Review and optimize indexes
- Update partition creation schedule
- Review disk space usage

## Partition Size Calculator

| Rows per Day | Rows per Month | Partition Type | Partition Size (est.) |
|--------------|----------------|----------------|-----------------------|
| 1,000        | 30,000         | Yearly         | ~5 MB                 |
| 10,000       | 300,000        | Quarterly      | ~50 MB                |
| 100,000      | 3,000,000      | Monthly        | ~500 MB               |
| 1,000,000    | 30,000,000     | Weekly         | ~5 GB                 |
| 10,000,000   | 300,000,000    | Daily          | ~50 GB                |

*Estimated based on ~170 bytes per row average*

## Best Practices Summary

1. ✅ **Partition by most common query filter** (usually timestamp)
2. ✅ **Create DEFAULT partition** for safety
3. ✅ **Automate future partition creation**
4. ✅ **Include partition key in all queries**
5. ✅ **Monitor partition sizes** regularly
6. ✅ **Test on staging** before production
7. ✅ **Verify data integrity** after migration
8. ✅ **Keep backups** for rollback
9. ✅ **Document the process** for your team
10. ✅ **Schedule regular maintenance**

## Resources

- Full Guide: [POSTGRES_PARTITIONING_GUIDE.md](POSTGRES_PARTITIONING_GUIDE.md)
- Complete SQL Example: [postgres_partitioning_example.sql](postgres_partitioning_example.sql)
- PostgreSQL Docs: https://www.postgresql.org/docs/current/ddl-partitioning.html
- pg_partman Extension: https://github.com/pgpartman/pg_partman

## Need Help?

Common scenarios:
- **IoT time-series data**: Monthly RANGE partitioning on timestamp
- **Multi-tenant**: HASH partitioning on tenant_id
- **Regional data**: LIST partitioning on region/country
- **High-volume logs**: Daily or Weekly RANGE partitioning
- **Mixed workload**: Multi-level partitioning (RANGE + LIST)

---

**Remember:** Always test in a non-production environment first!
