$server = "gewisdc02"
$ou = "OU=Mailpermissions,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"
$sharedMailGroup = "MAIL-Shared"

$runDate = Get-Date -Format "yyyy-MM-dd HH:mm"

$types = @{"ROInbox" = "read-only permission on the inbox folder";
            "ROSent" = "read-only permission on the sent items folder";
            "RO" = "read-only permission to the entire mailbox";
            "RW" = "read+write permission on the entire mailbox";
            "SOB" = "permission to send on behalf"}

$result = Get-ADGroupMember -Recursive $sharedMailGroup -Server $server | Get-ADUser -Properties SamAccountName, mail -Server $server

foreach ($user in $result) {
    $email = $user.mail
    $sam = $user.SamAccountName

    $types.GetEnumerator() | ForEach-Object {
        $type = $_.Key
        $string = $_.Value

        try {
            New-ADGroup -Name "MAIL-$sam-mailPerm$type" -DisplayName "MAIL: $email - $type" -GroupScope DomainLocal -Description "Members of this group get $string of $email" -Path $ou -ErrorAction Stop -Server $server
            Write-Information "Created group, continuing"
            Set-ADGroup "MAIL-$sam-mailPerm$type" -Replace @{info = "$($runDate): Created by mailboxGroups script`r`n"} -Server $server
            Set-ADUser $sam -Replace @{"mailPerm$type" = "CN=MAIL-$sam-mailPerm$type,$ou"} -Server $server
        } catch [Microsoft.ActiveDirectory.Management.ADException] {
            Write-Warning “Object already existed, so we skip this one”
        }
    }
}