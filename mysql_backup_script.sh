#!/bin/bash

DATE=`date "+%y%m%d"`

BACKUP_DEST="/home/username/backups"
DB=""
DB_USER=""
DB_USER_PW=""
DB_BACK=$BACKUP_DEST/$DATE-db.sql.gz

/usr/bin/mysqldump --password=$DB_USER_PW -Ke -u $DB_USER $DB | gzip > $DB_BACK