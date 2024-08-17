Get-Module GEWIS* | Remove-Module
Import-Module ..\Mail\GEWIS-Mail.psm1

Connect-GEWISMail -username $env:GEWIS_ADDBMAIL_USERNAME -from $env:GEWIS_ADDBMAIL_EMAIL -password $env:GEWIS_ADDBMAIL_PASSWORD
