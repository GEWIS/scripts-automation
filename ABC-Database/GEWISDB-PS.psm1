# Global state
$apiToken = $null
$url = $null

# Types
class Member
{
    [ValidateNotNullOrEmpty()][int]$lidnr
    [string]$email #For some members this unfortunately is null
    [ValidateNotNullOrEmpty()][string]$full_name
    [ValidateNotNullOrEmpty()][string]$initials
    [ValidateNotNullOrEmpty()][string]$given_name
    [ValidateNotNull()][string]$middle_name
    [ValidateNotNullOrEmpty()][string]$family_name
    [ValidateNotNullOrEmpty()][string]$membership_type
    [ValidateRange(1900,2200)][int]$generation
    [ValidateNotNull()][boolean]$hidden
    [ValidateNotNull()][boolean]$deleted
    [ValidateNotNull()][DateTime]$expiration
    [OrganInstallation[]]$organs
    [ValidateNotNull()][boolean]$keyholder
}

class Organ
{
	[ValidateNotNullOrEmpty()][int]$id
	[ValidateNotNullOrEmpty()][string]$abbreviation
}

class OrganInstallation
{
	[ValidateNotNull()][Organ]$organ
	[ValidateNotNullOrEmpty()][string]$function
	[ValidateNotNull()][DateTime]$installDate
	[AllowNull()]$dischargeDate
	[ValidateNotNull()][boolean]$current
}

<#
	.Synopsis
	Connects to the GEWISDB Api

	.Parameter apiToken
	The token used to connect with GEWISDB.
	
	.Parameter url
	GEWISDB API Url
#>
function Connect-GEWISDB {
param(
    [Parameter(Mandatory=$true)][string] $apiToken,
	[string] $url = "https://database.gewis.nl/api"
    )
	
	try
	{
		$headers = @{Authorization = "Bearer $Local:apiToken"}
		$Response = Invoke-WebRequest -Uri $Local:url -Headers $headers -MaximumRedirection 0 -ErrorAction Ignore
		# This will only execute if the Invoke-WebRequest is successful.
		$StatusCode = $Response.StatusCode
	} catch {
		$StatusCode = $_.Exception.Response.StatusCode.value__
	}
	
	if ($StatusCode -eq 200 -or $StatusCode -eq 403) {
		$Script:apiToken = $Local:apiToken
		$Script:url = $Local:url
		Write-Verbose -Message "Succesfully connected to GEWISDB Api"
	} else {
		Write-Error -Category ConnectionError -Message "Either the URL or the token is incorrect. Got status $StatusCode but expected 200 or 403" -ErrorAction Stop
	}
}
Export-ModuleMember -Function Connect-GEWISDB

# https://stackoverflow.com/a/48154663
function ParseErrorForResponseBody($Error) {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if ($Error.Exception.Response) {  
            $Reader = New-Object System.IO.StreamReader($Error.Exception.Response.GetResponseStream())
            $Reader.BaseStream.Position = 0
            $Reader.DiscardBufferedData()
            $ResponseBody = $Reader.ReadToEnd()
            if ($ResponseBody.StartsWith('{')) {
                $ResponseBody = $ResponseBody | ConvertFrom-Json
				$ResponseBody = $ResponseBody.error
            }
            return $ResponseBody
        }
    }
    else {
        return $Error.ErrorDetails.Message
    }
}

function Invoke-GEWISDBRequest {
param(
    [Parameter(Mandatory=$true)][string][AllowEmptyString()] $endPoint,
    [PSCustomObject][AllowNull()] $data
    )
	
	try
	{
		$headers = @{Authorization = "Bearer $Script:apiToken"}
		$Response = Invoke-RestMethod -Uri ($Script:url + $endPoint) -Headers $headers -MaximumRedirection 0 -ErrorAction Stop -Body $data
	} catch {
        $ResponseBody = ParseErrorForResponseBody($_)
		if ($_.Exception.Response.StatusCode.value__ -eq 403) {
			Write-Error -Category AuthenticationError $responseBody -ErrorAction Stop
			throw $_.Exception
		}
		#Write-Verbose $ResponseBody -ErrorAction Ignore
		Write-Error -Category ConnectionError ("An error occured. API returned unexpected status code" + [string]$_.Exception.Response.StatusCode.value__) -ErrorAction Stop
		throw $_.Exception
	}
	
	$Response
}

<#
	.Synopsis
	Get the status of the GEWISDB API, recommended to make sure the API is online
#>
function Test-GEWISDBHealth {
	if ($apiToken -eq $null) {Connect-GEWISDB}
	Invoke-GEWISDBRequest -endPoint "/health"
}
Export-ModuleMember -Function Test-GEWISDBHealth

<#
	.Synopsis
	Verify whether the database currently allows external applications to sync
#>
function Test-GEWISDBSyncAllowed {
	$h = Test-GEWISDBHealth
	return $h.healthy -and -not $h.sync_paused
}
Export-ModuleMember -Function Test-GEWISDBSyncAllowed

<#
	.Synopsis
	Assert sync is allowed or exit
#>
function Assert-GEWISDBSyncAllowed {
	if ((Test-GEWISDBSyncAllowed) -eq $False) {
		Write-Error "Sync is paused or API is not healthy"
		exit 1
	}
}
Export-ModuleMember -Function Assert-GEWISDBSyncAllowed

<#
	.Synopsis
	Get members (warning: paginated)
#>
function Get-GEWISDBMembers {
	if ($apiToken -eq $null) {Connect-GEWISDB}
	$Response = Invoke-GEWISDBRequest -endPoint "/members"
	$Response.data
}
Export-ModuleMember -Function Get-GEWISDBMembers

<#
	.Synopsis
	Get details of a single member
#>
function Get-GEWISDBMember {
param(
    [Parameter(Mandatory=$true)][int32][AllowEmptyString()] $membernumber
    )
	if ($apiToken -eq $null) {Connect-GEWISDB}
	$Response = Invoke-GEWISDBRequest -endPoint ("/members/" + $membernumber)
	# An empty response or a deleted user is still a succesful lookup
	# if there is an error during query, the databsae is expected to throw a 5xx
	# which will be caught and thrown by invoke-gewisdbrequest
    if ($null -eq $Response -or $Response.data.deleted -eq $True) {
        return $null
    }
	[Member]$Response.data
}
Export-ModuleMember -Function Get-GEWISDBMember

<#
	.Synopsis
	Get active members

	.Parameter includeInactive
	Whether to also include members who are inactive fraternity members, defaults to False
	Cast to int because PHP backend true == "False"
#>
function Get-GEWISDBActiveMembers {
param(
	[Parameter()][boolean] $includeInactive = $False
    )
	if ($apiToken -eq $null) {Connect-GEWISDB}
	$Response = Invoke-GEWISDBRequest -endPoint ("/members/active") -data @{"includeInactive" = [int]$includeInactive}
	[Member[]]$Response.data
}
Export-ModuleMember -Function Get-GEWISDBActiveMembers
