# auto-database-backup

Backs up one or more PostgreSQL databases (`pg_dump`), archives them, uploads
to a Google Drive remote via `rclone`, and prunes remote backups older than a
retention period. Runs across multiple DB connections listed in
`db_connection.ini`.

## Files

- `auto_database_backup_v2.sh` — current version. Hardcoded config at the top
  (`TIMEZONE`, `DB_CONNECTION`, `LOG_FILE`, `BACKUP_DIR`, `RCLONE_REMOTE_BASE`,
  `RETENTION_DAYS`). Logs to `LOG_FILE`, tracks success/failure counts, and
  exits non-zero if any client failed.
- `auto_database_backup.sh` — legacy/simple version (`sh`, no logging, no
  error handling). Kept for reference; prefer v2.
- `install.sh` — interactive installer. Prompts for backup dir, rclone remote,
  retention days, and backup hour, then writes a configured copy of the backup
  script to `/usr/local/sbin/auto_database_backup.sh`, creates
  `/usr/local/sbin/auto_backup_db_connection.ini`, and adds a daily crontab
  entry.
- `db_connection.ini` — one line per database to back up.

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

- `pg_dump` (PostgreSQL client tools)
- `rclone`, configured with a remote (e.g. `hamilton_drive:`)
- `tar`

## Usage

### Quick run (manual)

Edit the config constants at the top of `auto_database_backup_v2.sh`
(`DB_CONNECTION`, `LOG_FILE`, `BACKUP_DIR`, `RCLONE_REMOTE_BASE`,
`RETENTION_DAYS`), fill in `db_connection.ini`, then:

```bash
./auto_database_backup_v2.sh
```

### Installed (cron)

```bash
sudo ./install.sh
```

Follow the prompts. This deploys the script system-wide and schedules it via
cron; edit `/usr/local/sbin/auto_backup_db_connection.ini` afterward to add
real DB credentials.

## Notes

- `db_connection.ini` contains plaintext DB passwords — keep permissions
  restrictive (the installer sets `chmod 600` on the deployed copy).
- Remote purge failures (e.g. the 3-day-old path not existing) are logged as
  a warning, not a fatal error.
