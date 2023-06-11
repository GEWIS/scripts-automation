$date = get-date -Format "yyyy-MM-dd"
Start-Transcript -Path "C:\GEWISscripts\output\$date - wsus.txt" -Append
Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -DeclineExpiredUpdates -DeclineSupersededUpdates -CompressUpdates