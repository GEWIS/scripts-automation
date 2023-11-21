# Script created to compute and store recursive membership. Needed for various applications
# Runs every five minutes on DC03
# You probably think it is ugly, but at that point in time no better way to do this was found
# 2022-01-08. Rink

#Requires -Modules GEWIS-Mail

# We pick one domain controller for the whole script
$dom = Get-ADDomain
$server = $dom.PDCEmulator

# We need to update only those members who are (indirectly) in a group that has been changed recently
# The problem is that you don't know who have been removed

$settings = Get-Content -Raw -Path "C:\GEWISScripts\output\memberOfSettings.json" | ConvertFrom-Json
$lastRun = (Get-Date $settings.lastRun).AddMinutes(-3) # Add 3 minutes margin

if ($lastRun -eq $null) {
    $settings = New-Object -TypeName psobject
    Add-Member -InputObject $settings -MemberType NoteProperty -Name lastRun -Value (Get-Date "1970-01-01").ToString()
    $lastRun = Get-Date "1970-01-01"
}

$settings.lastRun = (Get-Date).ToString()
$settings | ConvertTo-Json -Compress | Out-File "C:\GEWISScripts\output\memberOfSettings.json"

$diff = (Get-Date) - $lastRun
echo "Last run was $($diff.TotalMinutes) minutes ago" 

$recently_changed_groups = Get-ADGroup -Filter {whenchanged -gt $lastRun} -Properties memberFlattened -Server $server
#echo $recently_changed_groups | foreach {$_.DistinguishedName}

# We check what groups can have updated members
$impactedGroups = $recently_changed_groups
foreach ($recently_changed_group in $recently_changed_groups) {
    $impactedGroups = @($impactedGroups) +  (Get-ADGroup -LDAPFilter ("(member:1.2.840.113556.1.4.1941:={0})" -f $recently_changed_group) -Properties memberFlattened -Server $server)
}
# Make the set of groups unique
$impactedGroups = $impactedGroups | Where-Object { $_.objectClass -eq 'group' } | Sort-Object | Select-Object distinguishedName, memberFlattened -unique
echo $impactedGroups | foreach {$_.DistinguishedName}

# We make sure all groups are updated in AD, and we also keep track of users we have updated
$impactedUserDNs = New-Object -TypeName 'System.Collections.ArrayList';
foreach ($impactedGroup in $impactedGroups) {
    if ($impactedGroup.DistinguishedName -eq $null) {continue}
    echo "Considering group $($impactedGroup.DistinguishedName): "
    
    #Current member flattened
    $current = $impactedGroup.memberFlattened

    #New member flattened
    $new = Get-ADGroupMember -Identity $impactedGroup.DistinguishedName -Recursive -Server $server
    $new = $new | Foreach {"$($_.DistinguishedName)"}

    echo "Differences:"
    $different = Compare-Object -ReferenceObject @($current | Select-Object) -DifferenceObject @($new | Select-Object) #-PassThru #| Select SideIndicator, name, distinguishedName
    echo $different | Format-Table
    $different | Foreach {$impactedUserDNs.Add($_.InputObject)} | Out-Null

    if ($new -eq $null) { 
        echo "Clearing attribute"
        Set-ADGroup $impactedGroup.distinguishedName -Clear "memberFlattened" -Server $server -WarningAction Inquire -ErrorAction Inquire
    } elseif ($different -ne $null) {
        echo "Saving changes"
        Set-ADGroup $impactedGroup.distinguishedName -Replace @{memberFlattened=$new} -Server $server -WarningAction Inquire -ErrorAction Inquire
    }
}
#echo $impactedUserDNs
#$impactedUsers = $impactedUsers | Sort-Object | Select-Object distinguishedName -unique  | Format-Table
$impactedUserDNs = $impactedUserDNs | Sort-Object | Get-Unique
echo "Number of impacted users: $($impactedUserDNs.Count)"

#
#foreach ($recently_changed_group in $recently_changed_groups) {
#    $impactedUsers = @($impactedUsers) + (Get-ADGroupMember $recently_changed_group.DistinguishedName -Recursive)
#}


#$allusers = Get-ADUser
#echo $allusers.Count

echo "== Start: $(Date) =="
#$users = Get-ADUser -Filter 'enabled -eq $true' -Server $server
# $users = Get-ADUser -Filter 'samaccountname -eq "m9093"' -Server $server
$users = $impactedUserDNs
#$users = Get-ADGroupMember -Identity wiki---organ-intro -Recursive -Server $server | Get-ADUser -Server $server
$i = 0
foreach ($user in $users) {
    $groups = {}
    
    # If we are using a group of users:
    #$dn = $user.DistinguishedName.Replace("(", "\28").Replace(")", "\29").Replace("\\", "\5C").Replace("*", "\2A")

    # If we are using a list of DNs:
    $dn = $user.Replace("(", "\28").Replace(")", "\29").Replace("\\", "\5C").Replace("*", "\2A")
    
    #This is slow:
    #$groups = Get-AdPrincipalGroupMembership $user.DistinguishedName -Server $server #Note the limitation here where the primary group is never expanded
    #$groups = @($groups) + (Get-ADGroup -LDAPFilter ("(member:1.2.840.113556.1.4.1941:={0})" -f $dn) -Server $server)
    #$memberOfRecursive = $groups | Sort-Object | Get-Unique | Foreach {"$($_.DistinguishedName)"} 

    # This disregards the primary group, but is quicker:
    $groups = Get-ADGroup -LDAPFilter ("(member:1.2.840.113556.1.4.1941:={0})" -f $dn) -Server $server
    $new = $groups | Foreach {"$($_.DistinguishedName)"}
    if ($new.Count -eq 0) { $new = "CN=Domain Users,CN=Users,DC=gewiswg,DC=gewis,DC=nl" }

    $ADUser = Get-Aduser -Properties memberOfFlattened,mail,Name,SamAccountName $user
    if ($ADUser.mail -ne "") { $mail = $ADUser.mail }
    else { $mail = "adflattennofemail@gewis.nl" }
    $current = $ADUser.memberOfFlattened
    $different = Compare-Object -ReferenceObject $current -DifferenceObject $new #-PassThru #| Select SideIndicator, name, distinguishedName

    if ($different -ne $null) {
        try {
            $addedGroups = ""
            $removedGroups = ""
            Set-ADUser $dn -Replace @{memberOfFlattened=$new} -Server $server -WarningAction Inquire -ErrorAction Inquire
            $different | Foreach {
                if ($_.SideIndicator -eq "<=") { $removedGroups += ("<li>" + $_.InputObject + "</li>") }
                elseif ($_.SideIndicator -eq "=>") { $addedGroups += ("<li>" + $_.InputObject + "</li>") }
            }

            $message = Get-Content -Path "$PSScriptRoot/updatedPermissionsMessage.txt" -RAW
            $message = $message -replace '#USER#', $ADUser.Name -replace '#ADDED#', $addedGroups -replace '#REMOVED#', $removedGroups
            Send-SimpleMail `
                -message $message `
                -replyTo "$($ADUser.Name) <$mail>" `
                -to "Computer Beheer Commissie <cbcissues@gewis.nl>" `
                -mainTitle "Notification from CBC" `
                -subject "Account permissions updated for $($ADUser.SamAccountName)" `
                -heading "Updated account permissions" `
                -oneLiner "Permissions for your account have been updated" `
                -footer "This message was sent to you because you have an account in the GEWIS systems."

            Write-Host "Added" $addedGroups
            Write-Host "Removed" $removedGroups
        } catch {
            echo "Failed to set $dn. This may not be a user object. $($_.Exception) $($_.ErrorDetails)"
        }
    }

    $i = $i + 1
    echo $i
}
echo "== End: $(Date) =="
