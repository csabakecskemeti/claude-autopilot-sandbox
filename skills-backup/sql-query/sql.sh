#!/usr/bin/env bash
# SQL Query tool for SQLite and PostgreSQL

set -e

DB_TYPE="$1"
CONNECTION="$2"
QUERY="$3"
FORMAT=""
WRITE_MODE=false

# Parse optional arguments
shift 3 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --csv) FORMAT="csv"; shift ;;
        --json) FORMAT="json"; shift ;;
        --write) WRITE_MODE=true; shift ;;
        *) shift ;;
    esac
done

if [[ -z "$DB_TYPE" ]] || [[ -z "$CONNECTION" ]] || [[ -z "$QUERY" ]]; then
    echo "Usage: $0 <sqlite|postgres> <connection> <query> [--csv|--json] [--write]"
    echo ""
    echo "SQLite:   $0 sqlite /path/to/db.sqlite 'SELECT * FROM table'"
    echo "Postgres: $0 postgres 'postgresql://user:pass@host/db' 'SELECT * FROM table'"
    exit 1
fi

# Check for write operations
is_write_query() {
    echo "$1" | grep -iE "^(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE)" > /dev/null
}

if is_write_query "$QUERY" && [[ "$WRITE_MODE" != "true" ]]; then
    echo "Error: Write operations require --write flag"
    echo "Query appears to modify data: $QUERY"
    exit 1
fi

case "$DB_TYPE" in
    sqlite)
        if [[ ! -f "$CONNECTION" ]]; then
            echo "Database file not found: $CONNECTION"
            exit 1
        fi

        case "$FORMAT" in
            csv)
                sqlite3 -header -csv "$CONNECTION" "$QUERY"
                ;;
            json)
                sqlite3 -json "$CONNECTION" "$QUERY"
                ;;
            *)
                sqlite3 -header -column "$CONNECTION" "$QUERY"
                ;;
        esac
        ;;
    postgres|postgresql)
        case "$FORMAT" in
            csv)
                psql "$CONNECTION" -c "COPY ($QUERY) TO STDOUT WITH CSV HEADER"
                ;;
            json)
                psql "$CONNECTION" -t -c "SELECT json_agg(t) FROM ($QUERY) t"
                ;;
            *)
                psql "$CONNECTION" -c "$QUERY"
                ;;
        esac
        ;;
    *)
        echo "Unknown database type: $DB_TYPE"
        echo "Supported: sqlite, postgres"
        exit 1
        ;;
esac
