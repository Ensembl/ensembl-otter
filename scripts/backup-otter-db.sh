#!/bin/sh

############################################################
## ./backup-otter-db.sh

## DESCRIPTION

## Script to backup the otter database
## Runs a quick mysqldump on the database

## Only allows one backup a day (controlled by $backup_date)

## USEAGE

## ./backup-otter-db.sh [/directory/path-to-dump-to]

## Edit these variables as required

user="root"
host="humsrv1"
dbname="otter_human"

#############################################################
## Shouldn't need to change below here...

backup_dir=''

if [ $# -eq 0 ]; then
    backup_dir='.'
else
    backup_dir=$1
fi

backup_date=`date +%Y%m%d`
backup_file="$backup_dir/otter-backup-$backup_date.sql"
tables_file="dump_these.tbl"

if [ -e $backup_file ]; then
    echo "$0 : already backed up today"
    echo "$0 : delete/move backup < rm -f $backup_file > to backup again"
    exit 1
else
    if [ -e $tables_file ]; then
#	mysqldump --opt -u $user -p -h $host $dbname `cat $tables_file` > $backup_file
#       should flush logs and lock tables
	mysqldump --opt --flush-logs --lock-tables -u $user -p -h $host $dbname `cat $tables_file` > $backup_file
	echo "$0 : backup should now be found @ $backup_file"
    else
	echo "$0 : ERROR, can't find tables file <$tables_file>"
	echo "$0 : create one by running" 
	echo "-->  echo \"show tables;\" | mysql -u $user -p -h $host -D $dbname --skip-column-names | grep -v dna\$ > $tables_file "
    fi
fi


