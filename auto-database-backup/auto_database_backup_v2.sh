#!/bin/bash
# auto_database_backup_v2.sh
# Automated PostgreSQL database backup to local storage and Google Drive.
#
# DB connection file format (pipe-delimited, no header row):
#   CLIENT_ID|CLIENT_NAME|HOST|PORT|DB_USERNAME|DB_PASSWORD|DB_NAME

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

readonly TIMEZONE="Asia/Jakarta"
readonly DB_CONNECTION="/usr/local/sbin/db_connection.ini"
readonly LOG_FILE="/var/log/auto_database_backup.log"
readonly BACKUP_DIR="/mnt/backupdb/DATABASE"
readonly RCLONE_REMOTE_BASE="hamilton_drive:backup_db"
readonly RETENTION_DAYS=3

# ─── Helpers ──────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    shift
    local msg
    msg="$(TZ="$TIMEZONE" date "+%Y-%m-%d %H:%M:%S") [${level}] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

get_field() {
    echo "$1" | cut -d '|' -f"$2"
}

# ─── Backup ───────────────────────────────────────────────────────────────────

backup_database() {
    local client_name="$1"
    local host="$2"
    local port="$3"
    local db_user="$4"
    local db_pass="$5"
    local db_name="$6"
    local timestamp="$7"
    local remote_drive="$8"

    local archive_name="NM-${client_name}-${timestamp}"
    local archive_file="${archive_name}.tar.gz"
    local purge_date today_date
    purge_date=$(TZ="$TIMEZONE" date -d "${RETENTION_DAYS} days ago" "+%Y%m%d")
    today_date=$(TZ="$TIMEZONE" date "+%Y%m%d")

    log "INFO" "Starting backup: ${client_name} — ${db_name} @ ${host}:${port}"

    # Dump database to directory format
    if ! PGPASSWORD="$db_pass" pg_dump -O -h "$host" -p "$port" -U "$db_user" -F d "$db_name" -f "$archive_name"; then
        log "ERROR" "pg_dump failed for ${client_name}"
        return 1
    fi

    # Create compressed archive and remove the raw dump directory
    tar -czf "$archive_file" "$archive_name"
    rm -rf "$archive_name"

    # Remove old backup from Google Drive (ignore errors if path doesn't exist)
    log "INFO" "Purging remote backup from ${RETENTION_DAYS} days ago: ${remote_drive}/${purge_date}"
    rclone purge --drive-use-trash=false "${remote_drive}/${purge_date}" \
        && log "INFO" "Remote purge complete" \
        || log "WARN" "Remote purge skipped (path may not exist): ${remote_drive}/${purge_date}"

    # Upload new backup to Google Drive
    log "INFO" "Uploading ${archive_file} to ${remote_drive}/${today_date}"
    if ! rclone copy "$archive_file" "${remote_drive}/${today_date}"; then
        log "ERROR" "rclone upload failed for ${client_name}"
        return 1
    fi
    log "INFO" "Upload complete: ${client_name}"

    # Move archive to local backup directory
    if [ -d "$BACKUP_DIR" ]; then
        mv "$archive_file" "$BACKUP_DIR/"
        log "INFO" "Archive moved to ${BACKUP_DIR}"
    else
        log "WARN" "Local backup dir '${BACKUP_DIR}' not found; archive left in working directory"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [ ! -f "$DB_CONNECTION" ]; then
        log "ERROR" "DB connection file not found: ${DB_CONNECTION}"
        exit 1
    fi

    local timestamp
    timestamp=$(TZ="$TIMEZONE" date "+%Y%m%d%H%M")

    local success=0 failure=0

    while IFS= read -r client || [[ -n "$client" ]]; do
        # Skip empty lines and comment lines
        [[ -z "$client" || "$client" == \#* ]] && continue

        local client_id client_name host port db_user db_pass db_name
        client_id=$(get_field "$client" 1)
        client_name=$(get_field "$client" 2)
        host=$(get_field "$client" 3)
        port=$(get_field "$client" 4)
        db_user=$(get_field "$client" 5)
        db_pass=$(get_field "$client" 6)
        db_name=$(get_field "$client" 7)

        local remote_drive="${RCLONE_REMOTE_BASE}/${client_id}"

        if backup_database \
            "$client_name" "$host" "$port" \
            "$db_user" "$db_pass" "$db_name" \
            "$timestamp" "$remote_drive"
        then
            success=$((success + 1))
        else
            log "ERROR" "Backup failed for client: ${client_name}"
            failure=$((failure + 1))
        fi
    done < "$DB_CONNECTION"

    log "INFO" "Run complete — success: ${success}, failed: ${failure}"
    [ "$failure" -eq 0 ]
}

main "$@"
