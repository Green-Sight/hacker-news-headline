# PostgreSQL Partitioning Example: IoT Device Measurements

This example demonstrates how to safely create partitions on an existing table containing IoT device measurements and backfill it without losing incoming current data.

## Overview

When dealing with large-scale IoT data, table partitioning is crucial for:
- **Performance**: Faster queries by scanning only relevant partitions
- **Maintenance**: Easier data archival and deletion
- **Scalability**: Better handling of time-series data growth

This example shows a safe, production-ready approach to:
1. Create a partitioned version of an existing table
2. Backfill historical data
3. Handle concurrent inserts during migration
4. Switch to the partitioned table without downtime

## Scenario

We have an existing table `iot_measurements` with millions of records from various IoT devices. We want to partition it by measurement timestamp (monthly partitions) without losing any incoming data.

## Files

- `01_original_table.sql` - Original table structure (with sample data for testing)
- `02_create_partitioned_table.sql` - Create partitioned table structure
- `03_backfill_data.sql` - Safely backfill historical data
- `04_switchover.sql` - Switch to partitioned table
- `05_cleanup.sql` - Clean up old table
- `complete_migration.sql` - Complete migration script with all steps
- `GUIDE.md` - Comprehensive practical guide with detailed examples
- `QUICK_REFERENCE.md` - Quick reference for common commands and troubleshooting
- `validate.sh` - Script to validate SQL syntax and file structure
- `test_migration.sh` - End-to-end test script (requires PostgreSQL running)

## Quick Start

Execute the scripts in order:

```bash
psql -U your_user -d your_database -f 01_original_table.sql
psql -U your_user -d your_database -f 02_create_partitioned_table.sql
psql -U your_user -d your_database -f 03_backfill_data.sql
psql -U your_user -d your_database -f 04_switchover.sql
psql -U your_user -d your_database -f 05_cleanup.sql
```

Or run the complete migration:

```bash
psql -U your_user -d your_database -f complete_migration.sql
```

For a quick reference of commands and troubleshooting, see [QUICK_REFERENCE.md](QUICK_REFERENCE.md).

## Testing

To test the migration on a local PostgreSQL instance:

```bash
# Make sure PostgreSQL is running and accessible
./test_migration.sh
```

The test script will:
1. Create a test database
2. Run through all migration steps
3. Validate the results
4. Show partition pruning in action

To validate the SQL files without executing them:

```bash
./validate.sh
```

## Safety Features

1. **No data loss**: Uses transaction isolation and triggers
2. **Concurrent writes**: Handles new inserts during migration
3. **Rollback capability**: Each step is reversible
4. **Monitoring**: Includes queries to verify data integrity
5. **Batch processing**: Prevents long-running locks

## Requirements

- PostgreSQL 10+ (declarative partitioning)
- Sufficient disk space (temporary duplication of data)
- Appropriate permissions (CREATE TABLE, CREATE TRIGGER, etc.)

## Best Practices

1. **Test first**: Always test on a copy of production data
2. **Backup**: Take a full backup before migration
3. **Monitor**: Watch for disk space and performance
4. **Schedule**: Run during low-traffic periods
5. **Validate**: Compare row counts and checksums before/after

## Performance Considerations

- Batch size affects commit frequency and rollback size
- Index creation time increases with data volume
- Foreign keys should be considered separately
- Partition pruning requires WHERE clauses on partition key

## Troubleshooting

### Migration is too slow
- Reduce batch size in backfill script
- Drop indexes before backfill, recreate after
- Increase `maintenance_work_mem`

### Running out of disk space
- Monitor with `SELECT pg_size_pretty(pg_total_relation_size('table_name'));`
- Consider archiving old partitions to separate tablespace

### Data mismatch after migration
- Use the validation queries in `03_backfill_data.sql`
- Check triggers are working: `SELECT * FROM pg_trigger WHERE tgrelid = 'iot_measurements'::regclass;`

## Support

For questions or issues, please refer to the PostgreSQL documentation:
- [Table Partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- [Declarative Partitioning](https://www.postgresql.org/docs/current/ddl-partition.html)
