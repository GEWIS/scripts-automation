#Run this script with psexec -s -i .\localBackupPhotos.ps1
# 2024, Juul adapted from 2022, Rink

# Prerequisites: poshprivilege is installed
# The system user has access to the network share (either net use /persistent:yes /savecred OR you run this with network service and the computer account has access)

get-module poshprivilege
Enable-Privilege -Privilege SeBackupPrivilege

#To consider: not keeping old versions of this folder as there is no use for it. You can already look back a month

rclone copy --config "C:\Program Files\rclone\rclone.conf" "gewis-win-ssh://mnt/zfs-backup/gewisfiles01/deleted/backup.2025-04-08" "D:\datas\Photos - local backup only" > "C:\GEWISScripts\retrieve_log.txt"
