#Requires -Version 5.1

# The goal of this module is to allow connectivity to lists.gewis.nl

$baseURL = "https://rest-api.lists.gewis.nl"
$cred = ""

# Specific object types
class MailmanList
{
	[ValidateNotNull()][boolean]$advertised
	[ValidateNotNullOrEmpty()][string]$display_name
	[ValidateNotNullOrEmpty()][mailaddress]$fqdn_listname
	[ValidateNotNullOrEmpty()][string]$list_id
	[ValidateNotNullOrEmpty()][string]$list_name
	[ValidateNotNullOrEmpty()][string]$mail_host
	[int]$member_count
	[int]$volume
	[ValidateNotNull()][string]$description
	[ValidateNotNullOrEmpty()][string]$self_link
	[ValidateNotNullOrEmpty()][string]$http_etag
}

class ListSubscriber
{
	[ValidateNotNullOrEmpty()][string]$address
	[int]$bounce_score
	[AllowNull()][DateTime]$last_bounce_received = "0001-01-01T00:00:00"
	[ValidateNotNullOrEmpty()][DateTime]$last_warning_sent
	[int]$total_warnings_sent
	[ValidateSet('regular','mime_digests','plaintext_digests','summary_digests')][string]$delivery_mode
	[AllowNull()][ValidateSet('enabled','by_user','by_bounces','by_moderator')][string]$delivery_status
	[ValidateNotNullOrEmpty()][mailaddress]$email
	[ValidateNotNullOrEmpty()][string]$list_id
	[ValidateSet('as_address','as_user')][string]$subscription_mode
	[ValidateSet('owner','moderator','member','nonmember')][string]$role
	[AllowNull()][ValidateSet('', 'accept','hold','reject','discard','defer')][string]$moderation_action
	[ValidateNotNullOrEmpty()][string]$user
	[ValidateNotNull()][string]$display_name
	[ValidateNotNullOrEmpty()][string]$self_link
	[ValidateNotNullOrEmpty()][string]$member_id
	[ValidateNotNullOrEmpty()][string]$http_etag
}

<#
	.Synopsis
	Stores GEWISMail Credentials
#>
function Connect-MailmanAPI {
	param(
		[Parameter()][string][AllowNull()] $username = $null,
		[Parameter()][string][AllowNull()] $password = $null
	)

    $Script:cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($username + ":" + $password))
}
Export-ModuleMember -Function Connect-MailmanAPI

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

function Invoke-MailmanAPIRequest {
param(
    [Parameter(Mandatory=$true)][string][AllowEmptyString()] $endPoint,
    [PSCustomObject][AllowNull()] $data,
	[string][AllowNull()] $method = 'GET'
    )
	
	try
	{
		$headers = @{Authorization = "Basic $Script:cred"}
		$Response = Invoke-RestMethod -Uri ($Script:baseURL + $endPoint) -Headers $headers -MaximumRedirection 0 -ErrorAction Ignore -Body $data -Method $method
	} catch {
		Write-Host $_.Exception.Response.Body
        $ResponseBody = ParseErrorForResponseBody($_)
		if ($_.Exception.Response.StatusCode.value__ -eq 403) {
			Write-Error -Category AuthenticationError $responseBody -ErrorAction Stop
		}
		#Write-Verbose $ResponseBody -ErrorAction Ignore
		Write-Error -Category ConnectionError ("An error occured. API returned unexpected status code" + [string]$_.Exception.Response.StatusCode.value__) -ErrorAction Stop
	}
	
	$Response
}

<#
	.Synopsis
	Get status
#>
function Get-MailmanHealth {
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/system/versions"
	$Response.api_version -eq "3.1"
}
Export-ModuleMember -Function Get-MailmanHealth

<#
	.Synopsis
	Get lists
#>
function Get-MailmanLists {
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/lists"
	[MailmanList[]]($Response.entries)
}
Export-ModuleMember -Function Get-MailmanLists

<#
	.Synopsis
	Get lists by email and role. This is subtly different then Get-MailmanSubscriptionsByAddress which does not consider as_user subscriptions
#>
function Search-MailmanListsByEmail {
	param(
		[Parameter(Mandatory=$true)][mailaddress] $subscriberEmail,
		[string][ValidateSet('owner','moderator','member','nonmember')] $role = 'member'
	)
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/lists/find" -data "subscriber=$subscriberEmail&role=$role" -method 'POST'
	[MailmanList[]]($Response.entries)
}
Export-ModuleMember -Function Search-MailmanListsByEmail

<#
	.Synopsis
	Get lists by email. Also check Search-MailmanListsByEmail
#>
function Get-MailmanSubscriptionsByAddress {
	param(
		[Parameter(Mandatory=$true)][mailaddress] $subscriberEmail
	)
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/addresses/$subscriberEmail/memberships"
	[ListSubscriber[]]($Response.entries)
}
Export-ModuleMember -Function Get-MailmanSubscriptionsByAddress

<#
	.Synopsis
	Get members by mailing list and role
#>
function Get-MailmanListMembers {
	param(
		[Parameter(Mandatory=$true)][string] $listId,
		[string][ValidateSet('owner','moderator','member','nonmember')] $role = 'member'
	)
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/lists/$listId/roster/$role"
	[ListSubscriber[]]($Response.entries)
}
Export-ModuleMember -Function Get-MailmanListMembers

<#
	.Synopsis
	Add members to mailing list with role
#>
function Add-MailmanListMember {
	param(
		[Parameter(Mandatory=$true)][string] $listId,
		[Parameter(Mandatory=$true)][mailaddress] $subscriberEmail,
		[Parameter(Mandatory=$true)][string] $subscriberName,
		[string][ValidateSet('owner','moderator','member','nonmember')] $role = 'member'
	)
	$data = @{
		list_id=$listId
		subscriber=$subscriberEmail
		display_name=$subscriberName
		role=$role
		pre_verified=$True
		pre_confirmed=$True
		pre_approved=$True
		send_welcome_message=$True
		delivery_mode="regular"
		delivery_status="enabled"
	}
	$Response = Invoke-MailmanAPIRequest -endPoint "/3.1/members" -data $data -method 'POST'
	$Response
}
Export-ModuleMember -Function Add-MailmanListMember

<#
	.Synopsis
	Remove members to mailing list with role, if not on list, does nothing
#>
function Remove-MailmanListMember {
	param(
		[Parameter(Mandatory=$true)][string] $listId,
		[Parameter(Mandatory=$true)][mailaddress] $subscriberEmail,
		[string][ValidateSet('owner','moderator','member','nonmember')] $role = 'member'
	)
	$Response = Get-MailmanSubscriptionsByAddress -subscriberEmail $subscriberEmail | Where-Object role -eq $role | Where-Object list_id -eq $listId
	if ($Response.Count -eq 1) {
		$Response = Invoke-MailmanAPIRequest -endPoint ("/" + $Response[0].self_link.Split("/",4)[3] + "?pre_approved=true&pre_confirmed=true") -method 'DELETE'
	}
}
Export-ModuleMember -Function Remove-MailmanListMember
