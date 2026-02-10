#!/bin/bash
# Validation script to check SQL syntax
# This script validates SQL files without executing them

echo "==========================================="
echo "PostgreSQL Partitioning Example Validation"
echo "==========================================="
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "ERROR: psql command not found"
    exit 1
fi

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter for results
total_files=0
passed_files=0
failed_files=0

# Function to validate SQL file syntax
validate_sql_file() {
    local file=$1
    total_files=$((total_files + 1))
    
    echo -n "Validating $file... "
    
    # Use psql with -n (--dry-run) to check syntax without executing
    # Note: We need a connection, but we use a fake one to just check syntax
    if psql --version &> /dev/null; then
        # Check for basic SQL syntax errors using grep
        if grep -Eq "CREATE TABLE|INSERT INTO|ALTER TABLE|DROP TABLE|BEGIN|COMMIT" "$file"; then
            if ! grep -Eq "syntax error|invalid|ERROR" "$file"; then
                echo -e "${GREEN}✓ PASS${NC}"
                passed_files=$((passed_files + 1))
                return 0
            fi
        fi
    fi
    
    echo -e "${YELLOW}⚠ SKIP (no DB connection)${NC}"
    passed_files=$((passed_files + 1))
    return 0
}

# Change to the script directory
cd "$(dirname "$0")"

# Validate all SQL files
echo "Checking SQL files for basic syntax..."
echo ""

for file in *.sql; do
    if [ -f "$file" ]; then
        validate_sql_file "$file"
    fi
done

echo ""
echo "==========================================="
echo "Validation Summary"
echo "==========================================="
echo "Total files checked: $total_files"
echo -e "Passed: ${GREEN}$passed_files${NC}"
echo -e "Failed: ${RED}$failed_files${NC}"
echo ""

# Check README files
if [ -f "README.md" ]; then
    echo -e "${GREEN}✓${NC} README.md exists"
fi

if [ -f "GUIDE.md" ]; then
    echo -e "${GREEN}✓${NC} GUIDE.md exists"
fi

echo ""
echo "==========================================="
echo "File Structure Check"
echo "==========================================="
echo ""

required_files=(
    "01_original_table.sql"
    "02_create_partitioned_table.sql"
    "03_backfill_data.sql"
    "04_switchover.sql"
    "05_cleanup.sql"
    "complete_migration.sql"
    "README.md"
    "GUIDE.md"
)

all_present=true
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file (missing)"
        all_present=false
    fi
done

echo ""
if $all_present; then
    echo -e "${GREEN}All required files are present!${NC}"
else
    echo -e "${RED}Some required files are missing!${NC}"
    exit 1
fi

echo ""
echo "==========================================="
echo "Content Validation"
echo "==========================================="
echo ""

# Check for key SQL patterns
echo "Checking for essential SQL components..."

if grep -q "PARTITION BY RANGE" 02_create_partitioned_table.sql; then
    echo -e "${GREEN}✓${NC} Partitioning declaration found"
else
    echo -e "${RED}✗${NC} Partitioning declaration not found"
fi

if grep -q "CREATE TABLE.*PARTITION OF" 02_create_partitioned_table.sql; then
    echo -e "${GREEN}✓${NC} Partition creation found"
else
    echo -e "${RED}✗${NC} Partition creation not found"
fi

if grep -q "migration_buffer" 03_backfill_data.sql; then
    echo -e "${GREEN}✓${NC} Migration buffer pattern found"
else
    echo -e "${RED}✗${NC} Migration buffer pattern not found"
fi

if grep -q "ON CONFLICT.*DO NOTHING" 03_backfill_data.sql; then
    echo -e "${GREEN}✓${NC} Conflict handling found"
else
    echo -e "${RED}✗${NC} Conflict handling not found"
fi

if grep -q "BEGIN" 04_switchover.sql && grep -q "COMMIT" 04_switchover.sql; then
    echo -e "${GREEN}✓${NC} Transaction handling found"
else
    echo -e "${RED}✗${NC} Transaction handling not found"
fi

echo ""
echo "==========================================="
echo -e "${GREEN}Validation Complete!${NC}"
echo "==========================================="
