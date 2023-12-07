# Script that grants permission to a specific group on a specific folder
# 2021-10-17. Rink

$server = "gewisdc03"

$folderName = Read-Host -Prompt 'Enter folder name'
$folderItem = Get-Item -Path ("\\gewisfiles01.gewiswg.gewis.nl\datas\" + $folderName) -ErrorAction Stop
$folderAcl = Get-Acl $folderItem

$option_view = New-Object System.Management.Automation.Host.ChoiceDescription '&View', 'View permissions'
$option_add = New-Object System.Management.Automation.Host.ChoiceDescription '&Add', 'Add permissions'
$option_remove = New-Object System.Management.Automation.Host.ChoiceDescription '&Remove', 'Remove permissions'
$option_exit = New-Object System.Management.Automation.Host.ChoiceDescription '&Exit', 'Exit'
$options = [System.Management.Automation.Host.ChoiceDescription[]]($option_view, $option_add, $option_remove, $option_exit)

$aclRights = [Security.AccessControl.FileSystemRights]::AppendData + [Security.AccessControl.FileSystemRights]::CreateFiles + [Security.AccessControl.FileSystemRights]::ReadAndExecute
$aclInheritance = [Security.AccessControl.InheritanceFlags]::None
$aclPropagation = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType = [Security.AccessControl.AccessControlType]::Allow

$aclRights2 = [Security.AccessControl.FileSystemRights]"Modify"
$aclInheritance2 = [Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$aclPropagation2 = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType2 = [Security.AccessControl.AccessControlType]::Allow

while ($true) {
    $result = $host.ui.PromptForChoice("Action", "What do you want to do?", $options, 0)
    switch ($result)
    {
        0 {
            echo $folderAcl.Access | Format-Table
        }
        1 {
            $userName = Read-Host -Prompt 'Enter user name'
            $user = Get-ADUser $userName -ErrorAction Ignore
            If (!$?) {
                $user = Get-ADGroup $userName -ErrorAction Ignore
            }
            If (!$?) {
                Write-Host "User not found"
                break;
            }


            # Only allow appends to the main folder
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SID, $aclRights, $aclInheritance, $aclPropagation, $aclType) 
            $folderAcl.AddAccessRule($accessRule)
            # Allow read/write access to subfolders/files
            $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SID, $aclRights2, $aclInheritance2, $aclPropagation2, $aclType2) 
            $folderAcl.AddAccessRule($accessRule2)

        }
        2 {
            $userName = Read-Host -Prompt 'Enter user name'
            $user = Get-ADUser $userName -ErrorAction Ignore
            If (!$?) {
                $user = Get-ADGroup $userName -ErrorAction Ignore
            }
            If (!$?) {
                Write-Host "User not found"
                break;
            }

            foreach ($access in $folderAcl.Access) {
                foreach ($value in $access.IdentityReference.Value) {
                    if ($value -eq ("GEWISWG\" + $user.SamAccountName)) {
                        $folderAcl.RemoveAccessRule($access) | Out-Null
                    }
                }
            }
        }
        3 {
            Set-Acl -Path $folderAcl.Path -AclObject $folderAcl -ea Stop
            Exit
        }
    }
}