#!/bin/bash

DB_CONNECTION="./db_connection.ini"
OUTPUT_LOG="./auto_db_size_logger.log"
CURRENT_DATETIME=$(date  '+%Y%m%d %H:%M:%S')
ACTUAL_SIZE_DB=$(PGPASSWORD=REDACTED_PASSWORD psql -U user_admin -h localhost -p 6432 -d HAMILTON-APP-PRD -c "SELECT pg_size_pretty(pg_database_size('HAMILTON-APP-QM1'));")
ACTUAL_SIZE_DB=$(echo $ACTUAL_SIZE_DB | cut -d " " -f3,4)

echo "HSI_PRD - $CURRENT_DATETIME - $ACTUAL_SIZE_DB"

log() {
    local level="$1"
    shift
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*"
    echo "$msg" | tee -a "$OUTPUT_LOG"
}

get_field() {
    echo "$1" | cut -d '|' -f"$2"
}

main() {
    while IFS='|' read -r client || [ -n "$client" ]; do
        # Skip empty lines and comments
        [[ -z "$client" || "$client" == \#* ]] && continue

        local env_name host port username password db_name query size

        env_name=$(get_field "$client" 1)
        host=$(get_field "$client" 3)
        port=$(get_field "$client" 4)
        username=$(get_field "$client" 5)
        password=$(get_field "$client" 6)
        db_name=$(get_field "$client" 7)
        query=$(create_query "$db_name")

        size=$(PGPASSWORD="$password" psql -U "$username" -h "$host" -p "$port" -d "$db_name" -t -c "$query" | xargs)
        log "INFO" "$env_name - $db_name: $size"
    done < "$DB_CONNECTION"
}