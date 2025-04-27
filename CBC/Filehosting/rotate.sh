#!/bin/bash

# This is a script that rotates the backups
# We keep 7 daily, 4 weekly and 12 monthly backups

while getopts h:p: flag
do
    case "${flag}" in
        h) hostname=${OPTARG};;
        p) period=${OPTARG};;
    esac
done
echo "Running rotate script with the following arguments:"
echo "  Hostname: $hostname";
echo "  Period: $period";

DST=/mnt/zfs-backup/$hostname

case "$period" in
  "daily")
  echo "Removing $DST/daily.6..."
  rm -rf $DST/daily.6

  for i in {5..1}
  do
      echo "Moving $DST/daily.$i to $DST/daily.$((i+1))"
      mv $DST/daily.$i $DST/daily.$((i+1))
  done
  echo "Hardlink-copying $DST/daily.0 to $DST/daily.1"
  cp -al $DST/daily.0 $DST/daily.1
  ;;

  "weekly")
  echo "Removing $DST/weekly.4..."
  rm -rf $DST/weekly.4

  for i in {3..0}
  do
      echo "Moving $DST/weekly.$i to $DST/weekly.$((i+1))"
      mv $DST/weekly.$i $DST/weekly.$((i+1))
  done
  echo "Hardlink-copying $DST/daily.0 to $DST/weekly.0"
  cp -al $DST/daily.0 $DST/weekly.0
  ;;

  "monthly")
  echo "Removing $DST/monthly.11..."
  rm -rf $DST/monthly.11

  for i in {10..0}
  do
      echo "Moving $DST/montly.$i to $DST/monthly.$((i+1))"
      mv $DST/monthly.$i $DST/monthly.$((i+1))
  done
  echo "Hardlink-copying $DST/daily.0 to $DST/monthly.0"
  cp -al $DST/daily.0 $DST/monthly.0
  ;;

  *)
    echo "That is not a valid period"
  ;;
esac