#!/bin/sh

get_part () {
    echo $1 | cut -d "|" -f$2
}

backup_database () {
    PGPASSWORD=$1 pg_dump -O -h $2 -p $3 -U $4 -F d $5 -f NM-$6-$7
    tar -czf NM-$6-$7.tar.gz NM-$6-$7
    rm -r NM-$6-$7
    echo "-info- -delete- delete backup 3 days ago in google drive" >> $LOG_BACKUP
    rclone purge --drive-use-trash=false $REMOTE_DRIVE/$THREEDAYSAGO
    echo "-info- -upload- ${today_datetime} Backup in google drive is Ok" >> $LOG_BACKUP
    rclone copy NM-$6-$7.tar.gz $REMOTE_DRIVE/$TODAYDATE
    echo "-info- ${today_datetime} Backup of ${mandt}-${envi} Ok" >> $LOG_BACKUP
    echo "-info- ${7} Backup of ${6} Ok" >> $LOG_BACKUP

    if [ ! -d $BACKUP_DIR ]; then
        echo "-info- Storage ${BACKUP_DIR} doesn't Exist, move ${6} to temp_backup" >> $LOG_BACKUP
    else
        mv NM-$6-$7.tar.gz $BACKUP_DIR/.
    fi

}

main () {
    local DATE_CURRENT=$(TZ="Asia/Jakarta" date "+%Y%m%d%H%M")
    local DB_CONNECTION="/home/hamilton/script/db_connection_daily"
    local LOG_BACKUP="/home/hamilton/script/backup_log.txt"
    local BACKUP_DIR="/mnt/backupdb/DATABASE"
    local SCRIPT_PATH=$(pwd)
    local THREEDAYSAGO=$(TZ="Asia/Jakarta" date -d "3 days ago" "+%Y%m%d")
    local TODAYDATE=$(TZ="Asia/Jakarta" date "+%Y%m%d")
    local TODAYDATETIME=$(TZ="Asia/Jakarta" date "+%Y%m%d%H%M")

    while read client; do
        local REMOTE_DRIVE="hamilton_drive:backup_db/$(get_part $client 1)"
        backup_database $(get_part $client 6) $(get_part $client 3) $(get_part $client 4) $(get_part $client 5) $(get_part $client 7) $(get_part $client 2) $DATE_CURRENT
    done < $DB_CONNECTION
}

main