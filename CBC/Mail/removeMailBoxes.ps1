Import-Module ..\..\General\readEnv.psm1
Import-Environment ..\general.env

$GroupName = "CLEANUP - To be deleted (disabled for 6 months)"
$SearchBase = "OU=Role Groups,DC=gewiswg,DC=gewis,DC=nl"
$apiURL = "https://mail.gewis.nl/api/v1/delete/mailbox"

# Get the full groupname from AD
$Group = Get-ADGroup -Filter "Name -eq '$Groupname'" -SearchBase $SearchBase

$Users = @{}

# Get all users in the group
Get-ADGroupMember -Identity $Group.DistinguishedName |
    Where-Object { $_.objectClass -eq "user"} |
    ForEach-Object {
        $Users[$_.name] = $_.SamAccountName + "@gewis.nl"
    }


Write-Host "Mailboxes to be deleted:" -ForeGroundColor Red
$Users


# let the user type conformation to delete the mailboxes
Write-Host "Make sure to double check the email-adresses you are deleting!" -ForeGroundColor Red
do {
    $input = Read-Host "Type 'delete mailboxes' to confirm and proceed"
    if ($input -ne "delete mailboxes") {
        Write-Host "Invalid, try again." -ForegroundColor Red
    }
} while ($input -ne "delete mailboxes")


# make api-call to delete the mailboxes
try {
    $EmailAdressesJson = $Users.Values | ConvertTo-Json -Depth 1
    $response = Invoke-RestMethod -Uri $ApiURL -Method Post -Body $EmailAdressesJson -ContentType "application/json" -Headers @{
        "accept" = "application/json"
        "X-API-Key" = "$env:MAILCOW_API_KEY"
    }

    echo "Mailboxes succesfull deleted!"
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    $statusDescription = $_.Exception.Response.StatusDescription
    echo "Request failed with status code: $statusCode ($statusDescription)"
}
