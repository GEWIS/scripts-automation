Import-Module ..\..\General\specialChars.psm1

# Global state
$server = $null
$organOU = "OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"
$groupWithAllOrgans = "S-1-5-21-3053190190-970261712-1328217982-4970"
$runDate = Get-Date -Format "yyyy-MM-dd HH:mm"

# The goal of this module is to allow AD functionality specific to GEWIS to be easily used

<#
	.Synopsis
	Connects to the GEWISDB Api

	.Parameter domain
	Optionally, the domain you want to connect to. To obtain a maximum sync state, the module only uses the primary domain controller
#>
function Connect-GEWISWG {
	param(
		[Parameter()][string][AllowNull()] $domain = $null
	)

	if ($domain -eq $null -or $domain -eq "") {$dom = Get-ADDomain}
	else {$dom = Get-ADDomain -Identity $domain}
	$Script:server = $dom.PDCEmulator
}
Export-ModuleMember -Function Connect-GEWISWG

function New-GEWISWGOrgan([string]$organName) {
	if ($server -eq $null) {Connect-GEWISWG}

    $simplename = Remove-StringDiacritic (Remove-StringSpecialCharacter $organName -SpecialCharacterToKeep "-")

	New-ADGroup -Confirm:$true -Name "Organ - $organName" -GroupCategory Security -GroupScope Global -SamAccountName "ORGAN_$simplename" -Description "GEWISDB Sync: Automatically created organ" -Path $organOU -OtherAttributes @{'info'="$($runDate): Created by Sync Script"} -Server $server -ErrorAction Inquire
	Add-ADGroupMember -Identity $groupWithAllOrgans -Members "ORGAN_$simplename" -ErrorAction Inquire -Server $server
}
Export-ModuleMember -Function New-GEWISWGOrgan

function Get-GEWISWGOrgans() {
	if ($server -eq $null) {Connect-GEWISWG}

	Get-ADGroup -Filter "(name -like 'Organ - *')" -Properties info -SearchBase $organOU -Server $server
}
Export-ModuleMember -Function Get-GEWISWGOrgans

function Get-GEWISWGOrgan([string]$organName) {
	if ($server -eq $null) {Connect-GEWISWG}

	Get-ADGroup -Filter "(name -like 'Organ - $organName')" -Properties info -SearchBase $organOU -Server $server
}
Export-ModuleMember -Function Get-GEWISWGOrgan


Function Archive-GEWISWGOrgan([string]$organName) {
	if ($server -eq $null) {Connect-GEWISWG}

    $group = Get-GEWISWGOrgan($organName)
    if ($group -eq $null) { Return }

	Remove-ADGroupMember -Identity $groupWithAllOrgans -Confirm:$true -Members $group.SID -ErrorAction Inquire -Server $server

	$otherGroupMemberships = Get-ADPrincipalGroupMembership -Identity $group.SID -Server $server -ErrorAction Inquire 
	foreach ($otherGroupMembership in $otherGroupMemberships) {
		Remove-ADGroupMember -Identity $otherGroupMembership.SID.Value -Members $group.SID.Value -ErrorAction Inquire -Server $server -WhatIf
	}

	Set-ADGroup -Identity $group.SID -Confirm -Replace @{info = $group.info + "`r`n$($runDate): Archived by sync script"} -Server $server
	#In some cases, the rename makes the object temporarily unavailable 
	Get-ADGroup -Identity $group.SID | Rename-ADObject -NewName "Abrogated Organ - $organName" -Server $server
}
Export-ModuleMember -Function Archive-GEWISWGOrgan
