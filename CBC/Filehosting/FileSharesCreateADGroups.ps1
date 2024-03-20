function Remove-StringSpecialCharacter
{
<#
.SYNOPSIS
  This function will remove the special character from a string.
  
.DESCRIPTION
  This function will remove the special character from a string.
  I'm using Unicode Regular Expressions with the following categories
  \p{L} : any kind of letter from any language.
  \p{Nd} : a digit zero through nine in any script except ideographic 
  
  http://www.regular-expressions.info/unicode.html
  http://unicode.org/reports/tr18/

.PARAMETER String
  Specifies the String on which the special character will be removed

.SpecialCharacterToKeep
  Specifies the special character to keep in the output

.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "^&*@wow*(&(*&@"
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*"
  
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*" -SpecialCharacterToKeep "*","_","-"
  wow-_*

.NOTES
  Francois-Xavier Cat
  @lazywinadmin
  www.lazywinadmin.com
  github.com/lazywinadmin
#>
  [CmdletBinding()]
  param
  (
    [Parameter(ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [Alias('Text')]
    [System.String[]]$String,
    
    [Alias("Keep")]
    #[ValidateNotNullOrEmpty()]
    [String[]]$SpecialCharacterToKeep
  )
  PROCESS
  {
    IF ($PSBoundParameters["SpecialCharacterToKeep"])
    {
      $Regex = "[^\p{L}\p{Nd}"
      Foreach ($Character in $SpecialCharacterToKeep)
      {
        IF ($Character -eq "-"){
          $Regex +="-"
        } else {
          $Regex += [Regex]::Escape($Character)
        }
        #$Regex += "/$character"
      }
      
      $Regex += "]+"
    } #IF($PSBoundParameters["SpecialCharacterToKeep"])
    ELSE { $Regex = "[^\p{L}\p{Nd}]+" }
    
    FOREACH ($Str in $string)
    {
      Write-Verbose -Message "Original String: $Str"
      $Str -replace $regex, ""
    }
  } #PROCESS
}

$server = "gewisdc02"
$ou = "OU=Fileshares,OU=Groups,DC=gewiswg,DC=gewis,DC=nl"

$runDate = Get-Date -Format "yyyy-MM-dd HH:mm"

$types = @{ "RO" = "read-only permission on the fileshare";
            "RW" = "read+write permission on the fileshare"}

$result = get-childitem -path \\gewisfiles01\datas | where-object name -NotLike ZZ* | where-object name -NotLike _*

$aclRights = [Security.AccessControl.FileSystemRights]::AppendData + [Security.AccessControl.FileSystemRights]::CreateFiles + [Security.AccessControl.FileSystemRights]::ReadAndExecute
$aclInheritance = [Security.AccessControl.InheritanceFlags]::None
$aclPropagation = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType = [Security.AccessControl.AccessControlType]::Allow

$aclRights2 = [Security.AccessControl.FileSystemRights]"Modify"
$aclInheritance2 = [Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$aclPropagation2 = [Security.AccessControl.PropagationFlags]::InheritOnly
$aclType2 = [Security.AccessControl.AccessControlType]::Allow

$aclRights3 = [Security.AccessControl.FileSystemRights]::ReadAndExecute
$aclInheritance3 = [Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$aclPropagation3 = [Security.AccessControl.PropagationFlags]::None
$aclType3 = [Security.AccessControl.AccessControlType]::Allow


foreach ($share in $result) {
    $name = Remove-StringSpecialCharacter $share.Name -SpecialCharacterToKeep "-", "_"
    try {
        Get-ADGroup "FILES-datas-$name-RW" -Server $server
        continue
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Warning “Object already existed, so we skip this one”
    }

    $folderItem = Get-Item -Path ("\\gewisfiles01\datas\" + $share.Name)
    $folderAcl = Get-Acl $folderItem
    $types.GetEnumerator() | ForEach-Object {
        $type = $_.Key
        $string = $_.Value

        try {
            New-ADGroup -Name "FILES-datas-$name-$type" -DisplayName "SHARE: $name - $type" -GroupScope DomainLocal -Description "Members of this group get $string of $($share.Name)" -Path $ou -ErrorAction Stop -Server $server
            Write-Host "Created group, continuing"
            Set-ADGroup "FILES-datas-$name-$type" -Replace @{info = "$($runDate): Created by fileShareGroups script`r`n"} -Server $server  

            $user = Get-ADGroup "FILES-datas-$name-$type" -ErrorAction Ignore -Server $server
            
            If ("RO" -eq $type) {
                #Only allow read access to all folders
                $accessRule3 = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SID, $aclRights3, "3", $aclPropagation3, $aclType3)
                $folderAcl.AddAccessRule($accessRule3) 
            }
            If ("RW" -eq $type) {
                # Only allow appends to the main folder
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SID, $aclRights, $aclInheritance, $aclPropagation, $aclType) 
                $folderAcl.AddAccessRule($accessRule)
                # Allow read/write access to subfolders/files
                $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SID, $aclRights2, $aclInheritance2, $aclPropagation2, $aclType2) 
                $folderAcl.AddAccessRule($accessRule2)
            }
        } catch [Microsoft.ActiveDirectory.Management.ADException] {
            Write-Warning “Object already existed, so we skip this one”
        }
    }
    Set-Acl -Path $folderAcl.Path -AclObject $folderAcl -ea Stop
}
