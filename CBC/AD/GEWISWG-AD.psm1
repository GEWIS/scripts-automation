Import-Module ..\..\General\specialChars.psm1
Import-Module ..\..\General\readEnv.psm1

#Requires -Modules GEWIS-Mail

Import-Environment ..\general.env

# Global state
$server = $null
$rootDN = $null
$organOU = "OU=Organs,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"
$memberOU = "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl"
$groupWithAllOrgans = "S-1-5-21-3053190190-970261712-1328217982-4970"
$groupKeyholders = "S-1-5-21-3053190190-970261712-1328217982-4120"
$dateFormat = "yyyy-MM-dd HH:mm"
$runDate = Get-Date -Format $dateFormat

# The goal of this module is to allow AD functionality specific to GEWIS to be easily used

<#
	.Synopsis
	Connects to the GEWISWG DC

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
	$Script:rootDN = $dom.DistinguishedName
}
Export-ModuleMember -Function Connect-GEWISWG

function New-GEWISWGOrgan([string]$organName) {
	if ($server -eq $null) {Connect-GEWISWG}

    $simplename = Remove-StringDiacritic (Remove-StringSpecialCharacter $organName -SpecialCharacterToKeep "-")

	New-ADGroup -Confirm:$false -Name "Organ - $organName" -GroupCategory Security -GroupScope Global -SamAccountName "ORGAN_$simplename" -Description "GEWISDB Sync: Automatically created organ" -Path $organOU -OtherAttributes @{'info'="$($runDate): Created by Sync Script"} -Server $server -ErrorAction Inquire
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

	Get-ADGroup -Filter "(name -like 'Organ - $organName')" -Properties info, description -SearchBase $organOU -Server $server
}
Export-ModuleMember -Function Get-GEWISWGOrgan


Function Archive-GEWISWGOrgan([string]$organName) {
	if ($server -eq $null) {Connect-GEWISWG}

    $group = Get-GEWISWGOrgan($organName)
    if ($group -eq $null) { Return }

	Remove-ADGroupMember -Identity $groupWithAllOrgans -Confirm:$false -Members $group.SID -ErrorAction SilentlyContinue -Server $server

	$otherGroupMemberships = Get-ADPrincipalGroupMembership -Identity $group.SID -Server $server -ErrorAction SilentlyContinue 
	foreach ($otherGroupMembership in $otherGroupMemberships) {
		Remove-ADGroupMember -Identity $otherGroupMembership.SID.Value -Confirm:$false -Members $group.SID.Value -ErrorAction SilentlyContinue -Server $server
	}

	Set-ADGroup -Identity $group.SID -Confirm:$false -Replace @{info = $group.info + "`r`n$($runDate): Archived by sync script"; description = "Archived $runDate / " + $group.description} -Server $server
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

function New-GEWISWGrandomPassword {
	# We need at least 12 characters of which one capital letter and one number
	$password = Get-RandomCharacters -length 9 -characters 'abcdefghikmnoprstuvwxyz'
	$password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
	$password += Get-RandomCharacters -length 1 -characters '1234567890'
	$password = Scramble-String $password
	return $password
}
Export-ModuleMember -Function New-GEWISWGrandomPassword


function Get-GEWISWGExpiryDate {
	# Accounts expire on the last day of the month
	$expiryDate = (Get-Date).AddMonths(3)
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
	$password = New-GEWISWGrandomPassword
	$expiryDate = Get-GEWISWGExpiryDate
	
	$initials = $initials.subString(0, [System.Math]::Min(6, $initials.Length)) 

	$existingAccount = Get-ADUser $username -Server $server -ErrorAction Ignore
	if ($existingAccount -ne $null) {
		$existingAccount | Set-ADUser -Enabled $True -AccountExpirationDate $expiryDate.AddSeconds(1) -ChangePasswordAtLogon $True
		$password = "Previously set by user"
	} else {
		New-ADUser -AllowReversiblePasswordEncryption $False `
			-CannotChangePassword $False `
			-ChangePasswordAtLogon $True `
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
			-Path $memberOU `
   			-KerberosEncryptionType "AES256" `
			-AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
			-AccountExpirationDate $expiryDate.AddSeconds(1) ` # We expire 1 second after our last validity date
			-ErrorAction Stop
		$existingAccount = Get-ADUser $username -Server $server -ErrorAction Ignore
	}
	
	
	if ($existingAccount -ne $null) { #Don't make it the users problem om failure
		# Add to Mailcow Mailbox (2023-10-11, inheritance based now)
		# Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-2713"
		# Add to Leden and make it the primary group
		Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-4116"
		$primaryGroupToken = (get-adgroup "S-1-5-21-3053190190-970261712-1328217982-4116" -properties @("primaryGroupToken")).primaryGroupToken
		Set-ADUser -Identity $username -replace @{primaryGroupID=$primaryGroupToken} -Server $server
		# Add to "PRIV - Roaming profile" (2023-10-11, inheritance based now)
		# Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-4678"
		# Add to "MEMBER - Ordinary"
		Add-ADGroupMember -Members $username -Server $server -Identity "S-1-5-21-3053190190-970261712-1328217982-5293"

		$message = Get-Content -Path "$PSScriptRoot/newAccountMessage.txt" -RAW
		$message = $message -replace '#FIRSTNAME#', $firstName -replace '#USERNAME#', $username -replace '#PASSWORD#', $password

		Send-GEWISMail -message $message -to "$firstName $lastName <$personalEmail>" -mainTitle "Notification from CBC" -subject "Member account for $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email contains your GEWIS member account details" -footer "This message was sent to you because you have a member account in the GEWIS systems."
		Send-GEWISMail -message $message -replyTo "$firstName $lastName <$username@gewis.nl>" -to $env:GEWIS_GEWISWG_COPY -mainTitle "Notification from CBC" -subject "Member account for $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email contains your GEWIS member account details" -footer "This message was sent to you because you have a member account in the GEWIS systems."
	}
}
Export-ModuleMember -Function New-GEWISWGMemberAccount

function Renew-GEWISWGMemberAccount {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $username
	)

	if ($server -eq $null) {Connect-GEWISWG}

	$expiryDate = Get-GEWISWGExpiryDate

	Get-ADUser -Identity $username | Set-ADUser -AccountExpirationDate $expiryDate.AddSeconds(1)
}
Export-ModuleMember -Function Renew-GEWISWGMemberAccount

function Expire-GEWISWGMemberAccount {
	param(
		[Parameter(Mandatory=$true)][int][ValidateNotNullOrEmpty()] $membershipNumber,
		[Parameter(Mandatory=$true)][int][ValidateNotNullOrEmpty()] $days,
		[Parameter(Mandatory=$true)][string][AllowEmptyString()] $firstName,
		[Parameter(Mandatory=$true)][string][AllowEmptyString()] $lastName,
		[string] $personalEmail
	)

	if ($server -eq $null) {Connect-GEWISWG}

	$username = "m" + $membershipNumber
	$expiryDate = (Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0).AddDays($days)

	Get-ADUser -Identity $username | Set-ADUser -AccountExpirationDate $expiryDate

	if ($firstname -ne $null -and $firstname -ne "") {
		$message = Get-Content -Path "$PSScriptRoot/accountExpiryMessage.txt" -RAW
		$message = $message -replace '#FIRSTNAME#', $firstName -replace '#USERNAME#', $username -replace '#DAYS#', $days -replace '#EXPIRYDATE#', $expiryDate.ToString($dateFormat)

		if ($personalEmail -ne $null) { Send-GEWISMail -message $message -to "$firstName $lastName <$personalEmail>" -mainTitle "Notification from CBC" -subject "Member account expiry $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email is to notify you about upcoming GEWIS member account expiry" -footer "This message was sent to you because you have a member account in the GEWIS systems which expires soon. A copy has been sent to your personal email address due to the importance of this message." }
		Send-GEWISMail -message $message -to "$firstName $lastName <$username@gewis.nl>" -mainTitle "Notification from CBC" -subject "Member account expiry $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email is to notify you about upcoming GEWIS member account expiry" -footer "This message was sent to you because you have a member account in the GEWIS systems which expires soon."
		Send-GEWISMail -message $message -replyTo "$firstName $lastName <$username@gewis.nl>" -to $env:GEWIS_GEWISWG_COPY -mainTitle "Notification from CBC" -subject "Member account expiry $firstName ($membershipNumber)" -heading "Your member account" -oneLiner "This email is to notify you about upcoming GEWIS member account expiry" -footer "This message was sent to you because you have a member account in the GEWIS systems which expires soon."
	}
}
Export-ModuleMember -Function Expire-GEWISWGMemberAccount

function New-GEWISWGOrganMember {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $organName,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $member
	)
	# If this exists in AD, we use this
	$organ = Get-GEWISWGOrgan ($organName + " (active members)")
	if ($organ -eq $null) {$organ = Get-GEWISWGOrgan $organName}
	if ($organ -eq $null) { return} 

	Add-ADGroupMember -Confirm:$false -Members $member -Server $server -Identity $organ.SID
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

	Remove-ADGroupMember -Confirm:$false -Members $member -Server $server -Identity $organ.SID
}
Export-ModuleMember -Function Remove-GEWISWGOrganMember

function Add-GEWISWGKeyholder {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $member
	)

	Add-ADGroupMember -Confirm:$false -Members $member -Server $server -Identity $groupKeyholders
}
Export-ModuleMember -Function Add-GEWISWGKeyholder

function Remove-GEWISWGKeyholder {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $member
	)

	Remove-ADGroupMember -Confirm:$false -Members $member -Server $server -Identity $groupKeyholders
}
Export-ModuleMember -Function Remove-GEWISWGKeyholder

<#
	.Synopsis
	Update the membership of a given group with the result of a given LDAP query
#>
function Set-ADGroupMembersFromLdapQuery {
	param(
		[Parameter()][string][ValidateNotNullOrEmpty()] $targetGroupSID,
		[Parameter()][string][ValidateNotNullOrEmpty()] $ldapQuery,
		[Parameter()][string][AllowNull()] $searchBase = $null,
		[switch] $executeAdditions = $False,
		[switch] $executeDeletions = $False
	)

	if ($server -eq $null) {Connect-GEWISWG}
	if ($searchBase.Length -eq 0) { $searchBase = $Script:rootDN  }

	$newMembers = (Get-ADObject -ldapFilter $ldapQuery -searchBase $searchBase -Server $server).DistinguishedName
	$currentMembers = Get-ADGroup -Identity $targetGroupSID -Server $server -Properties member | select-object -ExpandProperty member
	$comparison = Compare-Object -ReferenceObject @($currentMembers | Select-Object) -DifferenceObject @($newMembers | Select-Object)

	$add = ($comparison | Where-Object -Property SideIndicator -eq "=>") | Foreach-Object { "$($_.InputObject)" }
	#if ($add.Count -gt 0 -and $executeAdditions) { Add-ADGroupMember -Identity $env:GEWIS_ACTIVEACCOUNT_SID -Server $server -Members $add }
	if ($add.Count -gt 0 -and $executeAdditions) { Set-ADGroup -Identity $targetGroupSID -Server $server -Add @{Member=$add} }

	$remove = ($comparison | Where-Object -Property SideIndicator -eq "<=") | Foreach-Object { "$($_.InputObject)" }
	#if ($remove.Count -gt 0 -and $executeDeletions) { Remove-ADGroupMember -Identity $targetGroupSID -Members $remove -Server $server -Confirm:$False }
	if ($remove.Count -gt 0 -and $executeDeletions) { Set-ADGroup -Identity $targetGroupSID -Server $server -Remove @{Member=$remove} }

}
Export-ModuleMember -Function Set-ADGroupMembersFromLdapQuery