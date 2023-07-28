Import-Module ..\..\General\specialChars.psm1

#Requires -Modules GEWIS-Mail

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

function Get-RandomCharacters($length, $characters) {
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs=""
    return [String]$characters[$random]
}

function Scramble-String([string]$inputString){
    $characterArray = $inputString.ToCharArray()
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length
    $outputString = -join $scrambledStringArray
    return $outputString
}

function Get-Password {
	# We need at least 12 characters of which one capital letter and one number
	$password = Get-RandomCharacters -length 9 -characters 'abcdefghikmnoprstuvwxyz'
	$password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
	$password += Get-RandomCharacters -length 1 -characters '1234567890'
	$password = Scramble-String $password
	return $password
}

function Get-ExpiryDate {
	# Accounts expire on the last day of the month
	$expiryDate = (Get-Date).AddMonths(12)
	$expiryDate = $expiryDate.addDays(-($expiryDate.Day) + 1)
	$expiryDate = $expiryDate.addHours(-($expiryDate.Hour))
	$expiryDate = $expiryDate.addMinutes(-($expiryDate.Minute))
	$expiryDate = $expiryDate.addSeconds(-($expiryDate.Second) - 1)
	return $expiryDate
}

function New-GEWISWGMemberAccount {
	param(
		[Parameter(Mandatory=$true)][int][ValidateNotNullOrEmpty()] $membershipNumber,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $firstName,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $initials,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $lastName,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $personalEmail
	)

	if ($server -eq $null) {Connect-GEWISWG}

	$username = "m" + $membershipNumber
	$password = Get-Password
	$expiryDate = Get-ExpiryDate

	$existingAccount = Get-ADUser $username -ErrorAction Ignore
	if ($existingAccount -ne $null) {
		$existingAccount | Set-ADUser -Enabled $True
		$password = "Previously set by user"
	} else {
		New-ADUser -AllowReversiblePasswordEncryption $False `
			-CannotChangePassword $False `
			-ChangePasswordAtLogon $False `
			-DisplayName "$firstName $lastName" `
			-EmailAddress "$username@gewis.nl" `
			-EmployeeNumber $membershipNumber `
			-GivenName $firstName `
			-Initials $initials `
			-Name "$firstName $lastName ($username)" `
			-SamAccountName $username `
			-Surname $lastName `
			-Server $server `
			-UserPrincipalName "$username@gewiswg.gewis.nl" `
			-Enabled $True `
			-Path "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl" `
			-AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
			-AccountExpirationDate $expiryDate.AddSeconds(1) # We expire 1 second after our last validity date
	}

	# Add to Mailcow Mailbox
	Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-2713"
	# Add to Leden and make it the primary group
	Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-4116"
	$primaryGroupToken = (get-adgroup "S-1-5-21-3053190190-970261712-1328217982-4116" -properties @("primaryGroupToken")).primaryGroupToken
	set-aduser -Identity $username -replace @{primaryGroupID=$primaryGroupToken} -Server $server
	# Add to "PRIV - ROaming profile"
	Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-4678"
	# Add to "MEMBER - Ordinary"
	Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-5293"

	$message = Get-Content -Path "$PSScriptRoot/newAccountMessage.txt" -RAW
	$message = $message -replace '#FIRSTNAME#', $firstName -replace '#USERNAME#', $username -replace '#PASSWORD#', $password

	Send-GEWISMail -message $message -to $personalEmail -mainTitle "Notification from CBC" -subject "Member account for $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email contains your GEWIS member account details" -footer "This message was sent to you because you have a member account in the GEWIS systems."
	Send-GEWISMail -message $message -replyTo "$firstName $lastName <$username@gewis.nl>" -to "Computer Beheer Commissie <cbc@gewis.nl>" -mainTitle "Notification from CBC" -subject "Member account for $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email contains your GEWIS member account details" -footer "This message was sent to you because you have a member account in the GEWIS systems."

}
Export-ModuleMember -Function New-GEWISWGMemberAccount

function New-GEWISWGOrganMember {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $organName,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $member
	)
	# If this exists in AD, we use this
	$organ = Get-GEWISWGOrgan ($organName + " (active members)")
	if ($organ -eq $null) {$organ = Get-GEWISWGOrgan $organName}
	if ($organ -eq $null) { return} 

	Add-ADGroupMember -Members $member -Server $server -Identity $organ.SID
}
Export-ModuleMember -Function New-GEWISWGOrganMember

function Remove-GEWISWGOrganMember {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $organName,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $member
	)
	# If this exists in AD, we use this
	$organ = Get-GEWISWGOrgan ($organName + " (active members)")
	if ($organ -eq $null) {$organ = Get-GEWISWGOrgan $organName}
	if ($organ -eq $null) { return} 

	Remove-ADGroupMember -Members $member -Server $server -Identity $organ.SID
}
Export-ModuleMember -Function Remove-GEWISWGOrganMember