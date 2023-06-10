Remove-Module GEWISWG-AD; Import-Module .\GEWISWG-AD.psm1 -DisableNameChecking
Remove-Module GEWISDB-PS; Import-Module ..\..\ABC-Database\GEWISDB-PS.psm1

$usersDB = Get-GEWISDBActiveMembers -includeInactive $True
$usersDBNr = $usersDB.lidnr

$usersAD = Get-ADuser -SearchBase "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl" -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
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
}

Write-Host 