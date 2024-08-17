Get-Module GEWIS* | Remove-Module
Import-Module ..\Mail\GEWIS-Mail.psm1

Import-Module ..\..\General\readEnv.psm1
Import-Environment ..\addb.env

Connect-GEWISMail -username $env:GEWIS_ADDBMAIL_USERNAME -from $env:GEWIS_ADDBMAIL_EMAIL -password $env:GEWIS_ADDBMAIL_PASSWORD
