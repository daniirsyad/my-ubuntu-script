#!/bin/bash

# Installation script for auto_database_backup
# This script sets up the necessary files and permissions for the backup process.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="/usr/local/sbin"
readonly BACKUP_SCRIPT="${SCRIPT_DIR}/auto_database_backup.sh"
readonly DB_CONNECTION_FILE="${SCRIPT_DIR}/auto_backup_db_connection.ini"
readonly LOG_FILE="/var/log/auto_database_backup.log"
# ─── Installation Steps ───────────────────────────────────────────────────────
# 1. Create the backup script
create_backup_script() {
    cat << EOF > "$BACKUP_SCRIPT"
#!/bin/bash
set -euo pipefail

readonly TIMEZONE="Asia/Jakarta"
readonly DB_CONNECTION="$DB_CONNECTION_FILE"
readonly LOG_FILE="$LOG_FILE"
readonly BACKUP_DIR="$1"
readonly RCLONE_REMOTE_BASE="$2"
readonly RETENTION_DAYS=$3

log() {
    local level="\$1"
    shift
    local msg
    msg="\$(TZ="\$TIMEZONE" date "+%Y-%m-%d %H:%M:%S") [\${level}] \$*"
    echo "\$msg" | tee -a "\$LOG_FILE"
}

get_field() {
    echo "\$1" | cut -d '|' -f"\$2"
}

backup_database() {
    local client_name="\$1"
    local host="\$2"
    local port="\$3"
    local db_user="\$4"
    local db_pass="\$5"
    local db_name="\$6"
    local timestamp="\$7"
    local remote_drive="\$8"

    local archive_name="NM-\${client_name}-\${timestamp}"
    local archive_file="\${archive_name}.tar.gz"
    local purge_date today_date
    purge_date=$(TZ="\$TIMEZONE" date -d "\${RETENTION_DAYS} days ago" "+%Y%m%d")
    today_date=$(TZ="\$TIMEZONE" date "+%Y%m%d")

    log "INFO" "Starting backup: \${client_name} — \${db_name} @ \${host}:\${port}"

    # Dump database to directory format
    if ! PGPASSWORD="\$db_pass" pg_dump -O -h "\$host" -p "\$port" -U "\$db_user" -F d "\$db_name" -f "\$archive_name"; then
        log "ERROR" "pg_dump failed for \${client_name}"
        return 1
    fi

    # Create compressed archive and remove the raw dump directory
    tar -czf "\$archive_file" "\$archive_name"
    rm -rf "\$archive_name"

    # Remove old backup from Google Drive (ignore errors if path doesn't exist)
    log "INFO" "Purging remote backup from \${RETENTION_DAYS} days ago: \${remote_drive}/\${purge_date}"
    rclone purge --drive-use-trash=false "\${remote_drive}/\${purge_date}" \
        && log "INFO" "Remote purge complete" \
        || log "WARN" "Remote purge skipped (path may not exist): \${remote_drive}/\${purge_date}"

    # Upload new backup to Google Drive
    log "INFO" "Uploading \${archive_file} to \${remote_drive}/\${today_date}"
    if ! rclone copy "\$archive_file" "\${remote_drive}/\${today_date}"; then
        log "ERROR" "rclone upload failed for \${client_name}"
        return 1
    fi
    log "INFO" "Upload complete: \${client_name}"

    # Move archive to local backup directory
    if [ -d "\$BACKUP_DIR" ]; then
        mv "\$archive_file" "\$BACKUP_DIR/"
        log "INFO" "Archive moved to \${BACKUP_DIR}"
    else
        log "WARN" "Local backup dir '\${BACKUP_DIR}' not found; archive left in working directory"
    fi
}

main() {
    if [ ! -f "\$DB_CONNECTION" ]; then
        log "ERROR" "DB connection file not found: \${DB_CONNECTION}"
        exit 1
    fi

    local timestamp
    timestamp=$(TZ="\$TIMEZONE" date "+%Y%m%d%H%M")

    local success=0 failure=0

    while IFS= read -r client || [[ -n "\$client" ]]; do
        # Skip empty lines and comment lines
        [[ -z "\$client" || "\$client" == \#* ]] && continue

        local client_id client_name host port db_user db_pass db_name
        client_id=$(get_field "\$client" 1)
        client_name=$(get_field "\$client" 2)
        host=$(get_field "\$client" 3)
        port=$(get_field "\$client" 4)
        db_user=$(get_field "\$client" 5)
        db_pass=$(get_field "\$client" 6)
        db_name=$(get_field "\$client" 7)

        local remote_drive="\${RCLONE_REMOTE_BASE}/\${client_id}"

        if backup_database \
            "\$client_name" "\$host" "\$port" \
            "\$db_user" "\$db_pass" "\$db_name" \
            "\$timestamp" "\$remote_drive"
        then
            success=$((success + 1))
        else
            log "ERROR" "Backup failed for client: \${client_name}"
            failure=$((failure + 1))
        fi
    done < "\$DB_CONNECTION"

    log "INFO" "Run complete — success: \${success}, failed: \${failure}"
    [ "\$failure" -eq 0 ]
}

main "\$@"
EOF
    chmod +x "$BACKUP_SCRIPT"
}

# 2. Create the DB connection file with example content
create_db_connection_file() {
    cat << EOF > "$DB_CONNECTION_FILE"
# DB connection file — one entry per line (no header row in the actual data file)
# Format: CLIENT_ID|CLIENT_NAME|HOST|PORT|DB_USERNAME|DB_PASSWORD|DB_NAME
# Example:
# acme|ACME_PROD|db.acme.com|5432|backup_user|s3cr3t|acme_db
EOF
    chmod 600 "$DB_CONNECTION_FILE"
}

# 3. Create crontab entry to run the backup script daily at 2am
create_cron_job() {
    local cron_entry="0 $1 * * * /usr/bin/bash $BACKUP_SCRIPT $BACKUP_DIR $RCLONE_REMOTE_BASE $RETENTION_DAYS >> $LOG_FILE 2>&1"
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
}

# Menu
main_menu() {
    echo "Auto Database Backup Installation"
    echo "--------------------------------"
    read -p "Enter local backup directory (e.g. /mnt/backupdb/DATABASE): " backup_dir
    read -p "Enter rclone remote base path (e.g. drive_name:backup): " rclone_remote_base
    read -p "Enter retention period in days (e.g. 3): " retention_days
    read -p "Enter backup period in hours (e.g. 2 for daily at 2am): " backup_hour

    create_backup_script "$backup_dir" "$rclone_remote_base" "$retention_days"
    create_db_connection_file
    create_cron_job "$backup_hour"

    echo "Installation complete! Backup script will run daily at 2am."
}