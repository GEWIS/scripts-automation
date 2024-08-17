###Requires -RunAsAdministrator
# This script contains all secrets

$date = get-date -Format "yyyy-MM-dd\\HH.mm"
Start-Transcript -Path "C:\GEWISscripts\output\$date - flatten.txt" -Append

Install-Module -Name Mailozaurr -Scope CurrentUser -AllowClobber -Force

.\connectMailScript.ps1
.\memberOfFlattened.ps1
Stop-Transcript