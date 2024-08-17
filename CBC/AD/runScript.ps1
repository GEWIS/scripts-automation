###Requires -RunAsAdministrator
# This script contains all secrets

$date = get-date -Format "yyyy-MM-dd\\HH.mm"
Start-Transcript -Path "C:\GEWISscripts\output\$date - addb.txt" -Append

Install-Module -Name Mailozaurr -Scope CurrentUser -AllowClobber

Get-Module GEWIS* | Remove-Module
Import-Module ..\Mail\GEWIS-Mail.psm1
Import-Module .\GEWISWG-AD.psm1 -DisableNameChecking
Import-Module ..\..\ABC-Database\GEWISDB-PS.psm1
Import-Module ..\..\General\readEnv.psm1

Import-Environment ..\addb.env

Connect-GEWISDB -apiToken $env:GEWIS_GEWISDB_APITOKEN
Connect-GEWISMail -username $env:GEWIS_ADDBMAIL_USERNAME -from $env:GEWIS_ADDBMAIL_EMAIL -password $env:GEWIS_ADDBMAIL_PASSWORD

.\memberSync.ps1