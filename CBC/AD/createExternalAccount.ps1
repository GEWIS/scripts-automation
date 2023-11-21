# Connect to the server
$dom = Get-ADDomain
$server = $dom.PDCEmulator
Write-Host "Connected to $server for $($dom.NetBIOSName)"

# Checking what the next available username is
$lastId = [int]((Get-ADUser -SearchBase "OU=External,OU=Member accounts,DC=GEWISWG,DC=GEWIS,DC=nl" -Filter * -Server $server | Sort-Object SamAccountName -Descending)[0].SamAccountName -replace "^e", "")
$nextUsername = "e" + ($lastId + 1)
$nextUpn = "$nextUsername@gewis.nl" #We can do @gewis.nl as a trial


Write-Host "Using this script you can create an external account for various purposes. If you make a typo, you have to start over by using CTRL+C."
Write-Warning "Only use this script to create accounts for 1 person, not for service accounts"
Write-Host "Setting details for user $nextUsername"

$firstName = Read-Host "First name"
$lastName = Read-Host "Last name"
Write-Host "Username: $nextUsername"
$password = Read-Host "Password (will be outputted in plaintext later)"
$expiry = Get-Date (Read-Host "Expiry date (max. 18 months)")

if ($expiry -gt (Get-Date).AddMonths(18)) {
    Write-Warning "Expiry date is too large, set to default of 1 year from now"
    $expiry = (Get-Date).AddMonths(12)
}

try {
    New-ADUser -AllowReversiblePasswordEncryption $False `
        -CannotChangePassword $False `
        -ChangePasswordAtLogon $True `
        -DisplayName "$firstName $lastName" `
        -EmailAddress "$nextUsername@gewis.nl" `
        -GivenName $firstName `
        -Initials $initials `
        -Name "$firstName $lastName ($nextUsername)" `
        -SamAccountName $nextUsername `
        -Surname $lastName `
        -Server $server `
        -UserPrincipalName "$nextUpn" `
        -Enabled $True `
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

    Write-Host "====== Created user ======"
    Write-Host "Username: $nextUsername"
    Write-Host "Password: $password"
    Write-Host "Expiry date: $expiry"
    Write-Host "Name: $($existingAccount.Name)"

    Write-Warning "This user does not have permissions to do anything yet. Please refer to https://wiki.gewis.nl/books/cbc/page/member-accounts-and-other-personal-accounts to ensure proper group membership"
}