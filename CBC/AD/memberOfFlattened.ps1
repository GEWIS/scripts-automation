# Script created to compute and store recursive membership. Needed for various applications
# Runs every five minutes on DC03
# You probably think it is ugly, but at that point in time no better way to do this was found
# 2022-01-08. Rink

$server = "gewisdc03"

# We need to update only those members who are (indirectly) in a group that has been changed recently
# The problem is that you don't know who have been removed

$settings = Get-Content -Raw -Path "memberOfSettings.json" | ConvertFrom-Json

$lastRun = (Get-Date $settings.lastRun.value).AddMinutes(-3) #This is a todo, give it 3 minutes margin
$settings.lastRun.value = (Get-Date).ToString()
$settings | ConvertTo-Json -Compress | Out-File "memberOfSettings.json"

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
    $different = Compare-Object -ReferenceObject $current -DifferenceObject $new #-PassThru #| Select SideIndicator, name, distinguishedName
    echo $different | Format-Table
    $different | Foreach {$impactedUserDNs.Add($_.InputObject)} | Out-Null

    if ($new -eq $null) { $new = "" }

    if ($different -ne $null) {
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
#$users = Get-ADUser -Filter 'samaccountname -eq "m9093"' -Server $server
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
    $memberOfFlattened = $groups | Foreach {"$($_.DistinguishedName)"}

    
    
    #$user.memberOfFlattened.Add("CN=PRIV - Wiki Logon,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl")
    #$memberOfFlattened = {"CN=PRIV - Wiki Logon,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"; "CN=COMPUTERS Virtual Workstations,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"}
    if ($memberOfFlattened.Count -eq 0) { $memberOfFlattened = "CN=Domain Users,CN=Users,DC=gewiswg,DC=gewis,DC=nl" }
    try {
        Set-ADUser $dn -Replace @{memberOfFlattened=$memberOfFlattened} -Server $server -WarningAction Inquire -ErrorAction Inquire
    } catch {
        echo "Failed to set $dn. This may not be a user object"
    }
    $i = $i + 1
    echo $i
    #echo $user
    #echo $memberOfFlattened
}
echo "== End: $(Date) =="
