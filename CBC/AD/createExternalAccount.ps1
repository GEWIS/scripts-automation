Import-Module .\GEWISWG-AD.psm1 -DisableNameChecking

# Connect to the server
$dom = Get-ADDomain
$server = $dom.PDCEmulator
Write-Host "Connected to $server for $($dom.NetBIOSName)"

# Checking what the next available username is
$lastId = [int]((Get-ADUser -SearchBase "OU=External,OU=Member accounts,DC=GEWISWG,DC=GEWIS,DC=nl" -Filter * -Server $server | Sort-Object SamAccountName -Descending)[0].SamAccountName -replace "^e", "")
if ($lastId -lt 200) { $lastId = 199 }
$nextUsername = "e" + ($lastId + 1)
$nextUpn = "$nextUsername@gewis.nl" #We can do @gewis.nl as a trial


Write-Host "Using this script you can create an external account for various purposes. If you make a typo, you have to start over by using CTRL+C."
Write-Warning "Only use this script to create accounts for 1 person, not for service accounts"
Write-Host "Setting details for user $nextUsername"

$firstName = Read-Host "First name"
$lastName = Read-Host "Last name"
Write-Host "Username: $nextUsername"
$password = New-GEWISWGrandomPassword
$desc = Read-Host "Description"
$ticket = Read-Host "Ticket number (e.g. #CBC-$(Get-Date -Format "yyMM")-123)"
$expiry = Get-Date (Read-Host "Expiry date (max. 18 months)")

if ($expiry -gt (Get-Date).AddMonths(18)) {
    Write-Warning "Expiry date is too large, set to default of 1 year from now"
    $expiry = (Get-Date).AddMonths(12)
}

try {
    New-ADUser -AllowReversiblePasswordEncryption $False `
        -CannotChangePassword $False `
        -ChangePasswordAtLogon $True `
        -DisplayName "$firstName $lastName (EXTERN)" `
        -EmailAddress "$nextUsername@gewis.nl" `
        -GivenName $firstName `
        -Initials $initials `
        -Name "$firstName $lastName ($nextUsername)" `
        -SamAccountName $nextUsername `
        -Surname $lastName `
        -Server $server `
        -UserPrincipalName "$nextUpn" `
        -Enabled $True `
        -Description $desc `
        -OtherAttributes @{'info'="$(Get-Date -Format "yyyy-MM-dd"): Created using createExternalAccount.ps1 for ticket $ticket"} `
        -Path "OU=External,OU=Member accounts,DC=GEWISWG,DC=GEWIS,DC=nl" `
        -KerberosEncryptionType "AES256" `
        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
        -AccountExpirationDate $expiry
} catch [Microsoft.ActiveDirectory.Management.ADPasswordComplexityException] {
    Write-Warning "This password does not match minimum requirements... Please confirm removing user..."
    Get-ADUser -Filter "userPrincipalName -eq '$nextUpn'" -SearchBase "OU=External,OU=Member accounts,DC=GEWISWG,DC=GEWIS,DC=nl" -Server $server | Remove-ADUser -Confirm -Server $server
    Exit 1
}
$existingAccount = Get-ADUser -Filter "userPrincipalName -eq '$nextUpn'" -SearchBase "OU=External,OU=Member accounts,DC=GEWISWG,DC=GEWIS,DC=nl" -Server $server -ErrorAction Ignore

if ($existingAccount.UserPrincipalName -eq $nextUpn) {
    # Set primary group to "Externen"
    Add-ADGroupMember -Members $nextUsername -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-1210"
    $primaryGroupToken = (get-adgroup "S-1-5-21-3053190190-970261712-1328217982-1210" -properties @("primaryGroupToken")).primaryGroupToken
    Set-ADUser -Identity $nextUsername -replace @{primaryGroupID=$primaryGroupToken} -Server $server

    # This is an external account for which we don't use autorenew rules
    Add-ADGroupMember -Members $nextUsername -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-6510"

    Write-Host "====== Created user, please use following output in ticket $ticket ======"
    Write-Host "Dear $firstName,`n"
    Write-Host "You, or someone on your behalf, requested an account for GEWISWG Active Directory. Since you are not a member of GEWIS, an external account has been created. For details on the services you have access to, please refer to ticket $ticket.`n"
    Write-Host "Username: $nextUsername"
    Write-Host "Password: $password"
    Write-Host "Expiry date: $(Get-Date -Format "yyyy-MM-dd" $expiry)"
    Write-Host "Name: $($existingAccount.Name)`n"
    Write-Host "NOTE: By using this account you agree to the latest version of the ICT Policy of GEWIS. If you do not have a copy, you can request a copy from the board.`n"
    Write-Host "To use this account, please change your password first through https://auth.gewis.nl."
    Write-Host "This account will be automatically disabled on $(Get-Date -Format "dddd dd MMMM yyyy" $expiry) and will not be renewed automatically. If you want to keep using the account after that, please let us know."

    Write-Warning "This user does not have permissions to do anything yet. Please refer to https://wiki.gewis.nl/books/cbc/page/member-accounts-and-other-personal-accounts to ensure proper group membership"
}