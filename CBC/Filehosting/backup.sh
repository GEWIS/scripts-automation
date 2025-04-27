#!/bin/sh

RHOST=gewismail@gewisbackup
export RSYNC_RSH="ssh -o Compression=no"
RSYNC='rsync -a --numeric-ids --delete --delete-excluded -h' #--progress -v
DST=/mnt/zfs-backup/`hostname -s`/daily.0

case "$1" in
  "d"|"daily")
  # Rotate old backups using remote script
  ssh $RHOST /mnt/zfs-backup/bin/rotate.sh -h `hostname -s` -p daily;
  # Do Rsync of relevant folders
  for f in /var/lib/docker/volumes/mailcowdockerized_*;
  do
    echo "Backing up $f";
    $RSYNC $f $RHOST:$DST/volumes;
  done
  echo "Backing up /opt/mailman";
  $RSYNC /opt/mailman $RHOST:$DST/mailman;
  echo "Backing up /opt/mailcow-dockerized";
  $RSYNC /opt/mailcow-dockerized $RHOST:$DST/mailcow-dockerized;
  echo "Backing up /opt/backup_mailcow (mysql and crypt export)";
  $RSYNC /opt/backup_mailcow $RHOST:$DST/backup_mailcow;
  ;;
  "w"|"weekly")
  # Rotate old backups using remote script
  ssh $RHOST /mnt/zfs-backup/bin/rotate.sh -h `hostname -s` -p weekly;
  ;;
  "m"|"monthly")
  # Rotate old backups using remote script
  ssh $RHOST /mnt/zfs-backup/bin/rotate.sh -h `hostname -s` -p monthly;
  ;;
  *)
    echo "Usage: $0 period"
    echo "The period can be one of d(aily), w(eekly) or m(onthly)";;
esac