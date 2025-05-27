#Run this script with psexec -s -i .\localBackupPhotos.ps1
# 2024, Juul adapted from 2022, Rink

# Prerequisites: poshprivilege is installed
# The system user has access to the network share (either net use /persistent:yes /savecred OR you run this with network service and the computer account has access)

get-module poshprivilege
Enable-Privilege -Privilege SeBackupPrivilege

#To consider: not keeping old versions of this folder as there is no use for it. You can already look back a month

rclone sync --config "C:\Program Files\rclone\rclone.conf" --progress --local-no-check-updated --create-empty-src-dirs --fast-list --links --local-nounc=false "D:\datas\Photos - local backup only" gewis-win-ssh://mnt/zfs-backup/gewisfiles01/backup --backup-dir "gewis-win-ssh://mnt/zfs-backup/gewisfiles01/deleted/backup.$(date -Format "yyyy-MM-dd")" > "C:\GEWISScripts\daily_log.txt"
rclone delete --rmdirs --min-age 3y --config "C:\Program Files\rclone\rclone.conf" "gewis-win-ssh://mnt/zfs-backup/gewisfiles01/deleted/"
#rclone rmdirs --config "C:\Program Files\rclone\rclone.conf" "gewis-win-ssh://mnt/zfs-backup/gewisfiles01/deleted/"