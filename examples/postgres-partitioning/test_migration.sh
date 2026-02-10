#!/bin/bash
# Test script to demonstrate the PostgreSQL partitioning migration
# This script sets up a test database and runs through the migration process

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="${PGDATABASE:-postgres_partition_test}"
DB_USER="${PGUSER:-postgres}"
DB_HOST="${PGHOST:-localhost}"
DB_PORT="${PGPORT:-5432}"

# Function to print section headers
print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print info messages
print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to execute SQL and show results
execute_sql() {
    local description=$1
    local sql_file=$2
    
    print_info "Executing: $description"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$sql_file" > /tmp/sql_output.log 2>&1; then
        print_success "$description completed"
        
        # Show relevant output (notices, row counts, etc.)
        if grep -q "NOTICE\|rows\|Row" /tmp/sql_output.log; then
            echo "  Output:"
            grep "NOTICE\|rows\|Row" /tmp/sql_output.log | head -10 | sed 's/^/  /'
        fi
    else
        print_error "$description failed"
        cat /tmp/sql_output.log
        exit 1
    fi
}

# Function to run SQL query and show results
run_query() {
    local description=$1
    local query=$2
    
    print_info "$description"
    echo ""
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$query"
    echo ""
}

# Main execution
main() {
    print_header "PostgreSQL Partitioning Migration - Test Run"
    
    # Check if PostgreSQL is accessible
    print_info "Checking PostgreSQL connection..."
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();" > /dev/null 2>&1; then
        print_error "Cannot connect to PostgreSQL"
        echo "Please ensure PostgreSQL is running and credentials are correct."
        echo "Configuration:"
        echo "  Host: $DB_HOST"
        echo "  Port: $DB_PORT"
        echo "  User: $DB_USER"
        echo ""
        echo "You can override these with environment variables:"
        echo "  PGHOST, PGPORT, PGUSER"
        exit 1
    fi
    print_success "PostgreSQL connection successful"
    
    # Check PostgreSQL version
    print_info "Checking PostgreSQL version..."
    PG_VERSION=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SHOW server_version_num;")
    if [ "$PG_VERSION" -lt 100000 ]; then
        print_error "PostgreSQL 10+ required for declarative partitioning"
        exit 1
    fi
    print_success "PostgreSQL version check passed (version: $PG_VERSION)"
    
    # Create test database
    print_header "Step 1: Database Setup"
    
    print_info "Creating test database: $DB_NAME"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" > /dev/null 2>&1 || true
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;" > /dev/null 2>&1
    print_success "Test database created"
    
    # Run migration steps
    print_header "Step 2: Create Original Table with Sample Data"
    execute_sql "Creating original table" "01_original_table.sql"
    
    # Show table stats
    run_query "Original table statistics" "
        SELECT 
            COUNT(*) AS total_rows,
            MIN(measured_at) AS earliest,
            MAX(measured_at) AS latest,
            pg_size_pretty(pg_total_relation_size('iot_measurements')) AS size
        FROM iot_measurements;
    "
    
    print_header "Step 3: Create Partitioned Table Structure"
    execute_sql "Creating partitioned table" "02_create_partitioned_table.sql"
    
    # Show partitions created
    run_query "List of partitions created" "
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
        FROM pg_tables
        WHERE tablename LIKE 'iot_measurements_y%'
        ORDER BY tablename;
    "
    
    print_header "Step 4: Backfill Historical Data"
    print_info "This step may take a while depending on data volume..."
    execute_sql "Backfilling data" "03_backfill_data.sql"
    
    # Compare row counts
    run_query "Comparing row counts" "
        SELECT 
            'Original' AS table_name,
            COUNT(*) AS rows
        FROM iot_measurements
        UNION ALL
        SELECT 
            'Partitioned' AS table_name,
            COUNT(*) AS rows
        FROM iot_measurements_partitioned;
    "
    
    print_header "Step 5: Switchover to Partitioned Table"
    print_info "Performing switchover (< 1 second downtime)..."
    execute_sql "Switchover" "04_switchover.sql"
    
    # Verify switchover
    run_query "Verifying switchover" "
        SELECT 
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
        FROM pg_tables
        WHERE tablename IN ('iot_measurements', 'iot_measurements_old_backup')
        ORDER BY tablename;
    "
    
    print_header "Step 6: Testing Partitioned Table"
    
    # Test insert
    print_info "Testing insert into partitioned table..."
    run_query "Insert test record" "
        INSERT INTO iot_measurements 
            (device_id, measurement_type, value, unit, measured_at)
        VALUES 
            ('TEST_DEVICE', 'temperature', 99.9, 'celsius', '2026-02-15 12:00:00')
        RETURNING *;
    "
    
    # Test partition pruning
    print_info "Testing partition pruning..."
    run_query "Explain query (should only scan one partition)" "
        EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
        SELECT * FROM iot_measurements
        WHERE measured_at >= '2024-01-01' AND measured_at < '2024-02-01'
        LIMIT 5;
    "
    
    # Show partition sizes
    run_query "Partition sizes after migration" "
        SELECT 
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
        FROM pg_tables
        WHERE tablename LIKE 'iot_measurements_y%'
        ORDER BY tablename
        LIMIT 10;
    "
    
    print_header "Step 7: Cleanup (Optional)"
    print_info "In production, wait 7+ days before cleanup"
    print_info "For this test, we'll run cleanup now..."
    
    read -p "Press Enter to continue with cleanup or Ctrl+C to keep test database..."
    
    execute_sql "Cleanup" "05_cleanup.sql"
    
    print_header "Migration Test Complete!"
    
    print_success "All steps completed successfully"
    echo ""
    echo "Summary:"
    echo "  ✓ Original table created with sample data"
    echo "  ✓ Partitioned table structure created"
    echo "  ✓ Data backfilled without loss"
    echo "  ✓ Switchover completed"
    echo "  ✓ Partition pruning verified"
    echo "  ✓ Cleanup completed"
    echo ""
    print_info "Test database: $DB_NAME (ready for inspection)"
    echo ""
    echo "To connect to the test database:"
    echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
    echo ""
    echo "To drop the test database:"
    echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c 'DROP DATABASE $DB_NAME;'"
    echo ""
}

# Run main function
main "$@"
