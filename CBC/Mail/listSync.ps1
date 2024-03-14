# Imports module and connects (using credentials)
./listConnect.ps1

$OU = "OU=Lists,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"
$hybridFilter = "*@gewis.nl"

Get-ADGroup -Filter 'cn -like "* - member" -or cn -like "* - owner" -or cn -like "* - moderator"' -SearchBase $OU -Properties Description | ForEach-Object {
    $listId = ($_.Name -split " - " )[1]
    $role = ($_.Name -split " - " )[2]
    # For hybrid lists, we only control @gewis.nl addresses that are on the list (usually legacy)
    $hybrid = ($_.Description -like "HYBRID*")
    Write-Host "== Processing $role of $listId (Hybrid: $hybrid) =="

    $subscribers = Get-MailmanListMembers -listId $listId -role $role
    $emailsList = ($subscribers | ForEach-Object { $_.email })
    if ($emailsList -eq $null) { $emailsList = @()} 
    $emailsAD = (Get-ADGroupMember $_ -Recursive | Get-ADObject -Properties Mail | Select-Object Mail).Mail
    if ($emailsAD -eq $null) { $emailsAD = @()} 
    $differences = Compare-Object -ReferenceObject $emailsList -DifferenceObject $emailsAD
    $addEmails = ($differences | Where-Object -Property SideIndicator -eq "=>").InputObject
    Write-Host "Adding $addEmails"
    $removeEmails = ($differences | Where-Object -Property SideIndicator -eq "<=").InputObject
    
    if ($hybrid) { $removeEmails = $removeEmails | Where {$_ -like $hybridFilter} }
    Write-Host "Removing $removeEmails"

    # 41 or more additions/deletions? Suggests a mistake
    if ($addEmails.Count -gt 40 -or $removeEmails.Count -gt 40) {
        exit
    }

    if ($addEmails.Count -gt 0) {
        $addEmails | Foreach-Object {
            # We are guaranteed to get at least one object, the above. Do the list cast and then get the first one
            $name = @((Get-ADObject -Filter {mail -eq $_}))[0].Name
            Add-MailmanListMember -listId $listId -subscriberEmail $_ -subscriberName $name -role $role
        }
    }

    if ($removeEmails.Count -gt 0) {
        $removeEmails | Foreach-Object {
            Remove-MailmanListMember -listId $listId -subscriberEmail $_ -role $role
        }
    }
}

