$results = ""

#Requires -Modules GEWISWG-AD
#Requires -Modules GEWIS-Mail
#Requires -Modules GEWISDB-PS

$memberOU = "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl"

$usersDB = Get-GEWISDBActiveMembers -includeInactive $True
$usersDBNr = $usersDB.lidnr

$usersAD = Get-ADuser -Properties "Initials", "memberOf" -SearchBase $memberOU -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
$usersADNr = $usersAD.SamAccountName -replace "^m", ""

$comparison = Compare-Object -ReferenceObject $usersDBNr -DifferenceObject $usersADNr
$newUsers = ($comparison | Where-Object -Property SideIndicator -eq "<=").InputObject
$manualCheckUsers = ($comparison | Where-Object -Property SideIndicator -eq "=>").InputObject
Write-Host "No AD account yet:" $newUsers
Write-Host "Manual check needed:" $manualCheckUsers

# We also compare the active organs in the DB and in AD
# New organs get automatically created, old ones automatically archived
$organsDB = ($usersDB.organs.organ.abbreviation | Select -Unique)
$organsAD = (Get-GEWISWGOrgans).Name -replace " \((in)?active members\)$", "" -replace "^Organ - ", ""  | Select -Unique
$comparison =Compare-Object -ReferenceObject $organsDB -DifferenceObject $organsAD
$newOrgans = ($comparison | Where-Object -Property SideIndicator -eq "<=").InputObject
$archiveOrgans = ($comparison | Where-Object -Property SideIndicator -eq "=>").InputObject
Write-Host "Organs to create:" $newOrgans.Count
Write-Host "Organs to archive:" $archiveOrgans.Count

$newOrgans | Foreach-Object {
    If ($_ -eq $null) {return}
    New-GEWISWGOrgan($_)
    $results += "<li>Adding ${_}: <i>Please create necessary objects</i></li>"
}
$archiveOrgans | Foreach-Object {
    If ($_ -eq $null) {return}
    Archive-GEWISWGOrgan($_)
    $results += "<li>Archiving ${_}: <i>Please update former organ permissions</i></li>"
}

# Get accounts that expire in the next 30 days but should be renewed (this is to prevent issues where the check below does not work properly)
$accountsToRenew = Get-ADUser -LDAPFilter "(|((memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Active members,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))((memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Fraternity Inactive Members,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))((memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Lifetime Mailbox,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))((memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Board requested accounts,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))((memberOf:1.2.840.113556.1.4.1941:=CN=Board - Boards,OU=Board,OU=Groups,DC=gewiswg,DC=gewis,DC=nl)))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU | Where-Object AccountExpirationDate -lt (Get-Date).AddDays(30)
$accountsToRenew | Foreach-Object {
    # $results += ("<li>Renewed $($_.employeeNumber): now expires $newExpiry (was $($_.AccountExpirationDate))</li>")
    Renew-GEWISWGMemberAccount -membershipNumber $($_.employeeNumber)
}

# Get accounts that do not expire in the next 14 days but no longer have a reason for being enabled
$accountsToExpire = Get-ADUser -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Active members,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))(!(memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Fraternity Inactive Members,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))(!(memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Lifetime Mailbox,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))(!(memberOf:1.2.840.113556.1.4.1941:=CN=Permissions - Board requested accounts,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(memberOf:1.2.840.113556.1.4.1941:=CN=Board - Boards,OU=Board,OU=Groups,DC=gewiswg,DC=gewis,DC=nl)))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU | Where-Object AccountExpirationDate -gt (Get-Date).AddDays(14)
$accountsToExpire | Foreach-Object {
    $results += ("<li>Expired $($_.employeeNumber): now expires $((Get-Date).AddDays(14)) (was $($_.AccountExpirationDate))</li>")
    $member = Get-GEWISDBMember $($_.employeeNumber)
    $ln = ($member.middleName + " " + $member.lastName).Trim()
    Expire-GEWISWGMemberAccount -membershipNumber $($_.employeeNumber) -days 14 -firstName $member.firstName -lastName $ln -personalEmail $member.email
}

# Disable accounts that have expired for 24 hours (this causes the account to be disabled in lots of other systems)
# We ignore timezone differences here so the range is 25-26 hours depending on daylight savings time
$current18bit = ([int64] (get-date -Millisecond 0 -UFormat %s) + 11644473600) * 10000000
$dayago18bit = [int64] ($current18bit - 86400 * 10000000)
$accountsToDisable =  Get-ADUser -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(accountExpires=9223372036854775807))(!(accountExpires=0))(accountExpires<=$dayago18bit))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU
$accountsToDisable | Foreach-Object {
    $results += ("<li>Disabled $($_.employeeNumber): expired $($_.AccountExpirationDate), last logon $($_.LastLogonDate)</li>")
    $_ | Set-ADUser -Enabled $False
}


$newUsers | Foreach-Object {
    If ($_ -eq $null) {return}
	$user = $usersDB | Where-Object lidnr -eq $_
	$ln = ($user.middleName + " " + $user.lastName).Trim()
	New-GEWISWGMemberAccount -membershipNumber $user.lidnr -firstName $user.firstName -lastName $ln -initials $user.initials -personalEmail $user.email
    $results += ("<li>Creating user account and sending credentials for " + $user.lidnr + "</li>")
}

# We retrieve details for users known in AD but not active (anymore)
$usersDBManual = $manualCheckUsers | Foreach-Object {
    Get-GEWISDBMember $_ -ErrorAction SilentlyContinue
}
if ($usersDBManual.length -gt 0) {
    $usersDB += $usersDBManual
}

# Get a new copy of AD users
$usersAD = Get-ADuser -Properties "Initials", "memberOf" -SearchBase $memberOU -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
$usersDB | Foreach-Object {
    $userDB = $_
    $userAD = $usersAD | Where-Object SamAccountName -eq ("m" + $userDB.lidnr)
    if ($userAD -eq $null) {
        return
    }
    $initials = $userDB.initials.subString(0, [System.Math]::Min(6, $userDB.initials.Length)) 
    if ($initials -ne $userAD.initials) {
        $userAD | Set-ADuser -Initials $initials
        $results += ("<li>Updating initials for $($userDB.lidnr): $($userAD.initials) ==> ${initials}</li>")
    }
    if ($userDB.firstName -ne $userAD.GivenName) {
        $userAD | Set-ADuser -GivenName $userDB.firstName -DisplayName $userDB.fullName
        $userAD | Rename-ADObject -NewName "$($userDB.fullName) (m$($userDB.lidnr))"
        $results += ("<li>Updating given name for $($userDB.lidnr): $($userAD.givenName) ==> $($userDB.firstName)</li>")
    }
    $ln = ($userDB.middleName + " " + $userDB.lastName).Trim()
    if ($ln -ne $userAD.Surname) {
        $userAD | Set-ADuser -Surname $ln -DisplayName $userDB.fullName
        $userAD | Rename-ADObject -NewName "$($userDB.fullName) (m$($userDB.lidnr))"
        $results += ("<li>Updating surname for $($userDB.lidnr): $($userAD.Surname) ==> ${ln}</li>")
    }

    $userOrgansAD = @()
    $userOrgansDB = @()
    $userOrgansDBInactive = @()

    $userOrgansAD = $userAD.memberOf -like 'CN=Organ - *,OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl'| Foreach-Object {(Get-AdGroup $_).Name -replace 'Organ - ','' -replace ' \(active members\)', ''}
    $userOrgansDB = ($userDB.organs | Where-Object current -eq $True | Where-Object function -eq "Lid").organ.abbreviation
    if ($userOrgansDB -eq $null) {$userOrgansDB = @()}
    $userOrgansDBInactive = ($userDB.organs | Where-Object current -eq $True | Where-Object function -eq "Inactief Lid").organ.abbreviation
    if ($userOrgansDBInactive -ne $null) {$userOrgansDBInactive | Foreach-object {$userOrgansDB = @($userOrgansDB) + "${_} (inactive members)"}}

    if ($userOrgansAD -eq $null) {$userOrgansAD = @()}
    $userOrgansDiff = Compare-Object -ReferenceObject $userOrgansAD -DifferenceObject $userOrgansDB
    $userOrgansAdd = ($userOrgansDiff | Where-Object -Property SideIndicator -eq "=>").InputObject
    $userOrgansRemove = ($userOrgansDiff | Where-Object -Property SideIndicator -eq "<=").InputObject
    
    if ($userOrgansAdd -ne $null) {
        $results += ("<li>Adding organs to $($userDB.lidnr): $userOrgansAdd</li>")
        $userOrgansAdd | Foreach-Object {
            New-GEWISWGOrganMember -organName $_ -member $userAD.SID
        }
    }

    if ($userOrgansRemove -ne $null) {
        $results += ("<li>Removing organs from $($userDB.lidnr): $userOrgansRemove</li>")
        $userOrgansRemove | Foreach-Object {
            Remove-GEWISWGOrganMember -organName $_ -member $userAD.SID
        }
    }

    if ($userDB.keyholder -eq $False -and ($userAD.memberOf -eq "CN=PRIV - Openhouders (huidige sleutelhouders),OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -ge 1) {
        $results += ("<li>Removing keyholder permissions from $($userDB.lidnr)</li>")
        Remove-GEWISWGKeyholder $userAD
    }

    if ($userDB.keyholder -eq $True -and ($userAD.memberOf -eq "CN=PRIV - Openhouders (huidige sleutelhouders),OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -lt 1) {
        $results += ("<li>Adding keyholder permissions to $($userDB.lidnr)</li>")
        Add-GEWISWGKeyholder $userAD
    }

}

# Fix not having account expiry dates
Get-ADUser -Filter * -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU | Where-Object AccountExpirationDate -eq $null | Set-ADUser -AccountExpirationDate (Get-Date)

if ($results -ne "") {
    $message = "<ul>$results</ul>"
    Send-GEWISMail -message $message -to "cbc@gewis.nl" -replyTo "CBC AD Team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Results" -heading "AD Sync Results"
}