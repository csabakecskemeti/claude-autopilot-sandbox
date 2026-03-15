---
name: sql-query
description: Query SQLite and PostgreSQL databases. Use when asked to run SQL queries, analyze database data, or explore database tables.
allowed-tools: Bash
---

# SQL Query

Execute SQL queries against SQLite or PostgreSQL databases.

## Usage

### SQLite
```bash
~/.claude/skills/sql-query/sql.sh sqlite /path/to/db.sqlite "SELECT * FROM users LIMIT 10"
```

### PostgreSQL
```bash
~/.claude/skills/sql-query/sql.sh postgres "postgresql://user:pass@host/db" "SELECT * FROM users"
```

## Output Formats

```bash
# Default: formatted table
~/.claude/skills/sql-query/sql.sh sqlite db.sqlite "SELECT * FROM users"

# CSV output
~/.claude/skills/sql-query/sql.sh sqlite db.sqlite "SELECT * FROM users" --csv

# JSON output
~/.claude/skills/sql-query/sql.sh sqlite db.sqlite "SELECT * FROM users" --json
```

## Common Queries

```sql
-- List tables (SQLite)
SELECT name FROM sqlite_master WHERE type='table';

-- Show table schema
PRAGMA table_info(tablename);

-- Count rows
SELECT COUNT(*) FROM tablename;
```

## Safety

Read-only by default (SELECT only). Use `--write` flag to enable INSERT/UPDATE/DELETE.
