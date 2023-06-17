#Requires -Version 5.1
#Requires -Modules @{ ModuleName="Mailozaurr"; ModuleVersion="0.9" }

# Global state
$server = "smtp.gewis.nl"
$from = '"Computer Beheer Commissie | GEWIS" <cbc@gewis.nl>'
$username = $null
$password = $null
$locale = New-Object System.Globalization.CultureInfo('en-GB')
$sendcopy = $True

# The goal of this module is to allow AD functionality specific to GEWIS to be easily used

<#
	.Synopsis
	Stores GEWISMail Credentials
#>
function Connect-GEWISMail {
	param(
		[Parameter()][string][AllowNull()] $from = $null,
		[Parameter()][string][AllowNull()] $username = $null,
		[Parameter()][string][AllowNull()] $password = $null
	)

	$Script:from = $from
	$Script:username = $username
	$Script:password = $password
}
Export-ModuleMember -Function Connect-GEWISMail

function Send-GEWISMail {
	param(
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $message,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $mainTitle,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $heading,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $to,
		[Parameter(Mandatory=$true)][string][ValidateNotNullOrEmpty()] $subject,
		[Parameter()][string][AllowNull()] $oneLiner = $null,
		[Parameter()][string][AllowNull()] $footer = $null
	)

	if ($oneLiner -eq $null) {$oneLiner = $mainTitle}

	$body = Get-Content -Path "$PSScriptRoot/template.html" -RAW
	$from = $Script:from -replace '(?:.*)<(.*)>', '$1'
	$body = $body -replace '#HEADING#', $heading -replace '#FOOTER#', $footer -replace '#ONELINER#', $oneLiner -replace '#MESSAGE#', $message -replace '#MAINTITLE#', $mainTitle -replace '#DATE1#', (Get-Date).ToString("dddd", $locale) -replace '#DATE2#', (Get-Date).ToString("dd MMMM yyyy", $locale) -replace '#FROM', $from
	Send-EmailMessage -Server $Script:server -Username $Script:username -From $Script:from -Port 465 -SecureSocketOptions SslOnConnect -Password $Script:password -To $to -Subject $subject  -HTML $body -Verbose

	if ($sendcopy) {
		Send-EmailMessage -Server $Script:server -Username $Script:username -From $Script:from -Port 465 -SecureSocketOptions SslOnConnect -Password $Script:password -To $from -ReplyTo $to -Subject $subject  -HTML $body -Verbose
	}

}
Export-ModuleMember -Function Send-GEWISMail