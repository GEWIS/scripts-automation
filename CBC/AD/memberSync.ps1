$results = ""

#Requires -Modules GEWISWG-AD
#Requires -Modules GEWIS-Mail
#Requires -Modules GEWISDB-PS

$usersDB = Get-GEWISDBActiveMembers -includeInactive $True
$usersDBNr = $usersDB.lidnr

$usersAD = Get-ADuser -Properties "Initials", "memberOf" -SearchBase "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl" -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
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
}
$archiveOrgans | Foreach-Object {
    If ($_ -eq $null) {return}
    Archive-GEWISWGOrgan($_)
    $results += "<li>Archiving ${_}: <i>Please update former organ permissions</i></li>"
}

$newUsers | Foreach-Object {
    If ($_ -eq $null) {return}
	$user = $usersDB | Where-Object lidnr -eq $_
	$ln = ($user.middleName + " " + $user.lastName).Trim()
	New-GEWISWGMemberAccount -membershipNumber $user.lidnr -firstName $user.firstName -lastName $ln -initials $user.initials -personalEmail $user.email
    $results += ("<li>Creating user account and sending credentials for " + $user.lidnr + "</li>")
}

$usersDB | Foreach-Object {
    $userDB = $_
    $userAD = $usersAD | Where-Object SamAccountName -eq ("m" + $userDB.lidnr)
    if ($userAD -eq $null) {
        return
    }
    if ($userDB.firstName -ne $userAD.GivenName) {
        $userAD | Set-ADuser -GivenName $userDB.firstName -DisplayName $userDB.fullName
        $userAD | Rename-ADObject -NewName "$($userDB.fullName) (m$($userDB.lidnr))"
        $results += ("<li>Updating given name for $($userDB.lidnr): $($userAD.givenName) ==> $($userDB.firstName)")
    }
    $ln = ($userDB.middleName + " " + $userDB.lastName).Trim()
    if ($ln -ne $userAD.Surname) {
        $userAD | Set-ADuser -Surname $ln -DisplayName $userDB.fullName
        $userAD | Rename-ADObject -NewName "$($userDB.fullName) (m$($userDB.lidnr))"
        $results += ("<li>Updating surname for $($userDB.lidnr): $($userAD.Surname) ==> ${ln}")
    }
    $initials = $userDB.initials.subString(0, [System.Math]::Min(6, $userDB.initials.Length)) 
    if ($initials -ne $userAD.initials) {
        $userAD | Set-ADuser -Initials $initials
        $results += ("<li>Updating initials for $($userDB.lidnr): $($userAD.initials) ==> ${initials}")
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
        $results += ("<li>Adding organs to $($userDB.lidnr): $userOrgansAdd")
        $userOrgansAdd | Foreach-Object {
            New-GEWISWGOrganMember -organName $_ -member $userAD.SID
        }
    }

    if ($userOrgansRemove -ne $null) {
        $results += ("<li>Removing organs from $($userDB.lidnr): $userOrgansRemove")
        $userOrgansRemove | Foreach-Object {
            Remove-GEWISWGOrganMember -organName $_ -member $userAD.SID
        }
    }

}

if ($results -ne "") {
    $message = "<ul>$results</ul>"
    Send-GEWISMail -message $message -to "cbc@gewis.nl" -replyTo "CBC AD Team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Results" -heading "AD Sync Results"
}