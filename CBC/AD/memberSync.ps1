$results = ""

#Requires -Modules GEWISWG-AD
#Requires -Modules GEWIS-Mail
#Requires -Modules GEWISDB-PS

$memberOU = "OU=Member accounts,DC=gewiswg,DC=gewis,DC=nl"

$usersDB = Get-GEWISDBActiveMembers -includeInactive $True

# Force created accounts
$requestedAccounts = (Get-Content "\\gewisfiles01\datas\99_Digital Affairs\manual_accounts.txt") -split "\r\n"
Write-Host "Forcing account creation for:" $requestedAccounts
# We retrieve details for users that are specified by the secretary
$usersDBForced = $requestedAccounts | Foreach-Object {
    if ($usersDB.lidnr -notcontains $_) {
        Get-GEWISDBMember $_ -ErrorAction SilentlyContinue
        Add-ADGroupMember -Identity PERM_ManualAccountsTxt -Members ("m" + $_) -ErrorAction SilentlyContinue
    }
}
if ($usersDBForced.length -gt 0) {
    $usersDB += $usersDBForced
}

# Only consider a member active if there is a contact email address in GEWISDB
# If we already have an account, we will add it again as a manual check user and then disable the account
$usersDB = $usersDB | Where-Object { $_.email.Length -gt 0 }

# We only need membership numbers for comparison
$usersDBNr = $usersDB.lidnr

$usersAD = Get-ADuser -Properties "Initials", "memberOf" -SearchBase $memberOU -SearchScope OneLevel -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
$usersADNr = $usersAD.SamAccountName -replace "^m", ""

$comparison = Compare-Object -ReferenceObject $usersDBNr -DifferenceObject $usersADNr
$newUsers = ($comparison | Where-Object -Property SideIndicator -eq "<=").InputObject
$manualCheckUsers = ($comparison | Where-Object -Property SideIndicator -eq "=>").InputObject
Write-Host "No AD account yet:" $newUsers
Write-Host "Manual check needed:" $manualCheckUsers

If ($newUsers.Count -gt 50) {
    Write-Warning "Creating more than 50 users, not continuing"
    Send-GEWISMail -message "Attempting to create more than 50 users, assuming failure!" -to "cbc@gewis.nl" -replyTo "CBC AD-team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Error" -heading "AD Sync Error"
    exit
}

# We also compare the active organs in the DB and in AD
# New organs get automatically created, old ones automatically archived
$organsDB = ($usersDB.organs.organ.abbreviation | Select -Unique)
$organsAD = (Get-GEWISWGOrgans).Name -replace " \((in)?active members\)$", "" -replace "^Organ - ", ""  | Select -Unique
$comparison = Compare-Object -ReferenceObject $organsDB -DifferenceObject $organsAD
$newOrgans = ($comparison | Where-Object -Property SideIndicator -eq "<=").InputObject
$archiveOrgans = ($comparison | Where-Object -Property SideIndicator -eq "=>").InputObject
Write-Host "Organs to create:" $newOrgans.Count
Write-Host "Organs to archive:" $archiveOrgans.Count

If ($newOrgans.Count -gt 10) {
    Write-Warning "Creating more than 10 organs, not continuing"
    Send-GEWISMail -message "Attempting to create more than 10 organs, assuming failure!" -to "cbc@gewis.nl" -replyTo "CBC AD-team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Error" -heading "AD Sync Error"
    exit
}

If ($archiveOrgans.Count -gt 5) {
    Write-Warning "Deleting more than 5 organs, not continuing"
    Send-GEWISMail -message "Attempting to delete more than 5 organs, assuming failure!" -to "cbc@gewis.nl" -replyTo "CBC AD-team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Error" -heading "AD Sync Error"
    exit
}

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

# Get accounts that expire in the next 60 days but should be renewed (this is to prevent issues where the check below does not work properly)
$accountsToRenew = Get-ADUser -LDAPFilter "(memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Autorenew accounts,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl)" -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU | Where-Object AccountExpirationDate -lt (Get-Date).AddDays(60)
$accountsToRenew | Foreach-Object {
    # $results += ("<li>Renewed $($_.employeeNumber): now expires $newExpiry (was $($_.AccountExpirationDate))</li>")
    Renew-GEWISWGMemberAccount -username $($_.SamAccountName)
}

# Get accounts that do not expire in the next 14 days but no longer have a reason for being enabled
# Based on the age of the account, they get some extra time of account usage
$accountsToExpire = Get-ADUser -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Autorenew accounts,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl))(!(memberOf:1.2.840.113556.1.4.1941:=CN=PRIV - Autorenew disabled,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl)))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber, SamAccountName, whenCreated -SearchBase $memberOU | Where-Object AccountExpirationDate -gt (Get-Date).AddDays(7)
If ($accountsToExpire.Count -gt 50) {
    Write-Warning "Deleting more than 50 users, not continuing"
    Send-GEWISMail -message "Attempting to expire more than 50 users, assuming failure!" -to "cbc@gewis.nl" -replyTo "CBC AD-team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Error" -heading "AD Sync Error"
    exit
}
$accountsToExpire | Foreach-Object {
    $expireDays = [int](($_.whenCreated - (Get-Date)).TotalDays/-25)
    if ($expireDays -lt 7) { $expireDays = 7 }
    if ($expireDays -gt 60) { $expireDays = 60 }
    $expiryDate = (Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0).AddDays($expireDays)
    if ($_.AccountExpirationDate -gt $expiryDate.AddHours(2)) {
        $results += ("<li>Expired $($_.SamAccountName): now expires $expiryDate (was $($_.AccountExpirationDate))</li>")
        if ($_.employeeNumber.length -gt 1) {
            $member = Get-GEWISDBMember $($_.employeeNumber)
            $ln = ($member.middle_name + " " + $member.family_name).Trim()
            Expire-GEWISWGMemberAccount -membershipNumber $($_.employeeNumber) -days $expireDays -firstName $member.given_name -lastName $ln -personalEmail $member.email
        }
        else {
            $_ | Set-ADUser -AccountExpirationDate $expiryDate
        }
    }
}

# Catch expiry dates > 18 months from now
$accountsToExpire = Get-ADUser -LDAPFilter "(!(userAccountControl:1.2.840.113556.1.4.803:=2))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber, SamAccountName -SearchBase $memberOU | Where-Object AccountExpirationDate -gt (Get-Date).AddMonths(18)
$accountsToExpire | Foreach-Object {
    $results += ("<li>Expired $($_.SamAccountName) <strong>because expiration date exceeded maximum of 18 months</strong>: now expires $((Get-Date).AddDays(30)) (was $($_.AccountExpirationDate))</li>")
    $_ | Set-ADUser -AccountExpirationDate (Get-Date).AddDays(30)
}

# Disable accounts that have expired for 24 hours (this causes the account to be disabled in lots of other systems)
# We ignore timezone differences here so the range is 25-26 hours depending on daylight savings time
$current18bit = ([int64] (get-date -Millisecond 0 -UFormat %s) + 11644473600) * 10000000
$dayago18bit = [int64] ($current18bit - 86400 * 10000000)
$accountsToDisable =  Get-ADUser -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(accountExpires=9223372036854775807))(!(accountExpires=0))(accountExpires<=$dayago18bit))" -Properties AccountExpirationDate, LastLogonDate, employeeNumber, description -SearchBase $memberOU
$accountsToDisable | Foreach-Object {
    $results += ("<li>Disabled $($_.SamAccountName): expired $($_.AccountExpirationDate), last logon $($_.LastLogonDate)</li>")
    $_ | Set-ADUser -Enabled $False -Description "Disabled $(get-date -Format "yyyy-MM-dd") / $($_.Description)"
}


$newUsers | Foreach-Object {
    If ($_ -eq $null) {return}
	$user = $usersDB | Where-Object lidnr -eq $_
    if ($user.expiration -lt (Get-Date)) { return }
    $ln = ($user.middle_name + " " + $user.family_name).Trim()
    New-GEWISWGMemberAccount -membershipNumber $user.lidnr -firstName $user.given_name -lastName $ln -initials $user.initials -personalEmail $user.email
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
$usersAD = Get-ADuser -Properties "Initials", "memberOf", "description" -SearchBase $memberOU -LDAPFilter "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"


# Immediately disable m-accounts for users who have been deleted in GEWISDB after June 1st, 2022
$notFoundinDB = (Compare-Object -ReferenceObject $usersDBManual.lidnr -DifferenceObject $manualCheckUsers | Where-Object -Property SideIndicator -eq "=>").InputObject
$exceptionVeryOld = (Get-ADGroupMember -Recursive TA_NOTINGEWISDB).SamAccountName -replace "^m", ""
$toDelete = $notFoundinDB | Where-Object { $_ -notin $exceptionVeryOld }

If ($toDelete.Count -gt 15) {
    Write-Warning "Deleting more than 15 members, not continuing"
    Send-GEWISMail -message "Attempting to delete more than 15 members, assuming failure!" -to "cbc@gewis.nl" -replyTo "CBC AD-team <cbc-adteam@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Error" -heading "AD Sync Error"
    exit
}

$toDelete | ForEach-Object {
    $userAD = $usersAD | Where-Object SamAccountName -eq ("m" + $_)

    $results += ("<li>Disabled $($userAD.SamAccountName): not in GEWISDB</li>")
    $userAD | Set-ADUser -Enabled $False -Description "Disabled $(get-date -Format "yyyy-MM-dd"): not in GEWISDB / $($userAD.Description)"
    Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -Confirm:$false -ErrorAction SilentlyContinue
}

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
    if ($userDB.given_name -ne $userAD.GivenName) {
        $userAD | Set-ADuser -GivenName $userDB.given_name -DisplayName $userDB.full_name
        $userAD | Rename-ADObject -NewName "$($userDB.full_name) (m$($userDB.lidnr))"
        $results += ("<li>Updating given name for $($userDB.lidnr): $($userAD.givenName) ==> $($userDB.given_name)</li>")
    }
    $ln = ($userDB.middle_name + " " + $userDB.family_name).Trim()
    if ($ln -ne $userAD.Surname) {
        $userAD | Set-ADuser -Surname $ln -DisplayName $userDB.full_name
        $userAD | Rename-ADObject -NewName "$($userDB.full_name) (m$($userDB.lidnr))"
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

    # If membership is at least another day
    $notExpired = $userDB.expiration -gt (Get-Date).AddDays(1)

    # Fixing membership type, ordinary
    if ($notExpired -and $userDB.membership_type -eq 'ordinary' -and ($userAD.memberOf -eq "CN=MEMBER - Ordinary,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -lt 1) {
        $results += ("<li>Setting membership type of $($userDB.lidnr): now ordinary</li>")
        Add-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Fixing membership type, external
    if ($notExpired -and $userDB.membership_type -eq 'external' -and ($userAD.memberOf -eq "CN=MEMBER - External,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -lt 1) {
        $results += ("<li>Setting membership type of $($userDB.lidnr): now external</li>")
        Add-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Fixing membership type, graduate
    if ($notExpired -and $userDB.membership_type -eq 'graduate' -and ($userAD.memberOf -eq "CN=MEMBER - Graduate (non-member),OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -lt 1) {
        $results += ("<li>Setting membership type of $($userDB.lidnr): now graduate</li>")
        Add-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Fixing membership type, honorary
    if ($notExpired -and $userDB.membership_type -eq 'honorary' -and ($userAD.memberOf -eq "CN=MEMBER - Honorary,OU=Privileges,OU=Groups,DC=gewiswg,DC=gewis,DC=nl").Count -lt 1) {
        $results += ("<li>Setting membership type of $($userDB.lidnr): now honorary</li>")
        Add-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Lock a member if they don't have a valid email address in GEWISDB anymore
    if ($userDB.email.Length -eq 0) {
        $results += ("<li>Disabled $($userAD.SamAccountName): no contact details in GEWISDB</li>")
        $userAD | Set-ADUser -Enabled $False -Description "Disabled $(get-date -Format "yyyy-MM-dd"): no contact details / $($userAD.Description)"
    }

    # If a member has expired, remove all membership types
    if ($userDB.expiration -lt (Get-Date)) {
        $results += ("<li>Setting membership type of $($userDB.lidnr): removed membership</li>")
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5295" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5293" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5294" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADGroupMember -Members ($userAD.SID) -Identity "S-1-5-21-3053190190-970261712-1328217982-5297" -Confirm:$false -ErrorAction SilentlyContinue
    }

    # If a member has expired for 24 hours, lock the account
    if ($userDB.expiration -lt (Get-Date).AddHours(-4)) {
        $results += ("<li>Disabled $($userAD.SamAccountName): expired in GEWISDB</li>")
        $userAD | Set-ADUser -Enabled $False -Description "Disabled $(get-date -Format "yyyy-MM-dd"): expired in GEWISDB / $($userAD.Description)"
    }

}

# Fix not having account expiry dates
Get-ADUser -Filter * -Properties AccountExpirationDate, LastLogonDate, employeeNumber -SearchBase $memberOU | Where-Object AccountExpirationDate -eq $null | Set-ADUser -AccountExpirationDate (Get-Date)

if ($results -ne "") {
    $message = "<ul>$results</ul>"
    Send-GEWISMail -message $message -to "cbc@gewis.nl" -replyTo "GEWIS Secretary <secr@gewis.nl>" -mainTitle "Notification from CBC" -subject "AD Sync Results" -heading "AD Sync Results"
}
