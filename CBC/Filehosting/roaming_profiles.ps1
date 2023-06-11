# Script created to ease the creation of member accounts
# Runs every five minutes on GEWISAPP01
# Service account: GEWISWG\svc-roamingprofiles
# 2021-10-17. Rink

$server = "gewisdc03"

# Rights that members should get on their own profile and home
$aclRights = [Security.AccessControl.FileSystemRights]::AppendData + [Security.AccessControl.FileSystemRights]::CreateFiles + [Security.AccessControl.FileSystemRights]::ReadAndExecute
$aclInheritance = [Security.AccessControl.InheritanceFlags]::None
$aclPropagation = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType = [Security.AccessControl.AccessControlType]::Allow

$aclRights2 = [Security.AccessControl.FileSystemRights]"Modify"
$aclInheritance2 = [Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$aclPropagation2 = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType2 = [Security.AccessControl.AccessControlType]::Allow

$members = Get-ADGroupMember -Identity S-1-5-21-3053190190-970261712-1328217982-4678 -Server $server
foreach ($member in $members) {
    $member_current = Get-ADUser -Identity $member.SID -Server $server -Properties ProfilePath
    If ($member_current.ProfilePath.Length -eq 0) {
        # The profile path has never been set. We create a profile and a home directory
        $homePath = "\\gewisfiles01.gewiswg.gewis.nl\homes\$($member.SamAccountName)"
        $homeShare = New-Item -path $homePath -ItemType Directory -Force -ea Stop
        $homeAcl = Get-Acl $homeShare
        $profilePath = "\\gewisfiles01.gewiswg.gewis.nl\profiles\$($member.SamAccountName)"
        $profileShare = New-Item -path $profilePath -ItemType Directory -Force -ea Stop
        $profileAcl = Get-Acl $profileShare

        # Only allow appends to the main folder
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($member.SID, $aclRights, $aclInheritance, $aclPropagation, $aclType) 
        $homeAcl.AddAccessRule($accessRule)
        $profileAcl.AddAccessRule($accessRule)
        # Allow read/write access to subfolders/files
        $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($member.SID, $aclRights2, $aclInheritance2, $aclPropagation2, $aclType2) 
        $homeAcl.AddAccessRule($accessRule2)
        $profileAcl.AddAccessRule($accessRule2)

        #$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($member.SID, $aclRights, $aclInheritance, $aclPropagation, $aclType)
        #$homeAcl.AddAccessRule($accessRule)
        #$homeAcl.SetOwner($member.SID)
        Set-Acl -Path $homeAcl.Path -AclObject $homeAcl -ea Stop
        #$profileAcl.AddAccessRule($accessRule)
        #$profileAcl.SetOwner($member.SID)
        Set-Acl -Path $profileAcl.Path -AclObject $profileAcl -ea Stop


        echo "Setting ProfilePath for $($member.SamAccountName)"
        Set-ADUser -Identity $member.SID -ProfilePath "$profilePath\userprofile" -Server $server
        #Set-ADUser -Identity $member.SID -ProfilePath "$profilePath\userprofile" -HomeDrive "H" -HomeDirectory $homePath -Server $server
    } Else {
        echo "ProfilePath for $($member_current.SamAccountName) was already set to $($member_current.ProfilePath)"
    }

}
