<#
	.Synopsis
	Creates a new shared mailbox interactively
#>

Import-Module .\GEWIS-Mail.psm1
Import-Module ..\AD\GEWISWG-AD.psm1 -DisableNameChecking

$server = (Get-ADDomain).PDCEmulator
if ($server -ne (Get-ADDomain -Server $server).PDCEmulator) { exit 1 }
Write-Host "Connected to $server"

Write-Host "You are going to create a _shared_ mailbox. This is different from a service account or a personal mailbox."
$displayName = Read-Host -Prompt "Display name / Common name"
# Force the user to provide a valid email and let PowerShell do the validation
while ($email -notlike "*@gewis.nl") {
    $email = [MailAddress] (Read-Host -Prompt "Email address (must end in @gewis.nl)")
}
$samAccountName = $email.User
$email = $email.Address
$ticket = Read-Host -Prompt "Ticket number (e.g. #CBC-$(Get-Date -Format "yyMM")-123)"
$password = (New-GEWISWGrandomPassword) + (New-GEWISWGrandomPassword) + (New-GEWISWGrandomPassword)

New-ADUser -AllowReversiblePasswordEncryption $False `
    -CannotChangePassword $False `
    -ChangePasswordAtLogon $True `
    -DisplayName $displayName `
    -EmailAddress $email `
    -Name $displayName `
    -SamAccountName $samAccountName `
    -UserPrincipalName $email `
    -Enabled $False `
    -Server $server `
    -OtherAttributes @{'info'="$(Get-Date -Format "yyyy-MM-dd"): Created using createMailbox.ps1 for ticket $ticket"} `
    -Path "OU=Mailboxes,OU=Special accounts,DC=gewiswg,DC=gewis,DC=nl" `
    -KerberosEncryptionType "AES256" `
    -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
    -ea Stop `
    -Confirm:$True #Require the user to confirm

Write-Host "Setting up account..."
# Add to mailcow mailbox
Add-ADGroupMember -Identity "S-1-5-21-3053190190-970261712-1328217982-2713" -Members $samAccountName -ea Stop -Server $server
# Add to MAIL-shared
Add-ADGroupMember -Identity "S-1-5-21-3053190190-970261712-1328217982-7121" -Members $samAccountName -ea Stop -Server $server
# Add to PRIV_NOLOGIN
Add-ADGroupMember -Identity "S-1-5-21-3053190190-970261712-1328217982-7236" -Members $samAccountName -ea Stop -Server $server

# Only enable when succesfull
Set-ADUser -Identity $samAccountName -Enabled $True -Server $server

# Now also create the permission groups
Write-Host "Creating new permission groups..."
Start-ScheduledTask -CimSession GEWISAPP01 -TaskPath \GEWIS\ -TaskName "AD-Mailpermissions"