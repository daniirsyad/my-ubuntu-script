# auto-database-size-logger

Logs the on-disk size of one or more PostgreSQL databases, using connections
listed in `db_connection.ini`.

## Files

- `auto_db_size_logger.sh` — reads each connection from `db_connection.ini`,
  runs `SELECT pg_size_pretty(pg_database_size('<db_name>'))` via `psql`, and
  appends a timestamped line per database to `auto_db_size_logger.log`.
- `db_connection.ini` — one line per database to check.

## db_connection.ini format

Pipe-delimited, no header row, `#` for comments:

```
CLIENT_ID|CLIENT_NAME|HOST|PORT|DB_USERNAME|DB_PASSWORD|DB_NAME
```

Example:

```
acme|ACME_PROD|db.acme.com|5432|backup_user|s3cr3t|acme_db
```

## Requirements

- `psql` (PostgreSQL client)

## Usage

Fill in `db_connection.ini`, then:

```bash
./auto_db_size_logger.sh
```

Output is appended to `auto_db_size_logger.log` in the same directory, one
line per database, e.g.:

```
2026-09-13 10:00:00 [INFO] ACME_PROD - acme_db: 128 MB
```

## Notes

- `db_connection.ini` contains plaintext DB passwords — keep it out of
  version control / restrict permissions (`chmod 600`).
- Run on a schedule (cron) to track size growth over time.
