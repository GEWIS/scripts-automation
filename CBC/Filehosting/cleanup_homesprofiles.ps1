
# Please fill these settings carefully
$paths = @("\\gewisfiles01\profiles", "\\gewisfiles01\homes")
$months = -6
$deleteFromGroups = @("S-1-5-21-3053190190-970261712-1328217982-4678")

$toBeDeleted = [System.Collections.ArrayList]@()
$ownerToBeCleared = [System.Collections.Generic.HashSet[string]]@()
foreach ($path in $paths) {
    Write-Host "Working on $path"
    $profiles = (Get-ChildItem $path).Name | Where-Object { $_ -notlike "DELETE*" }
    $deleteBefore = (Get-Date).AddMonths($months)
    foreach ($profile in $profiles) {
        try {
            $owner = Get-ADUser $profile -Properties AccountExpirationDate, ProfilePath, HomeDirectory
            if ($owner.enabled -eq $False -and $owner.AccountExpirationDate -lt $deleteBefore) {
                Write-Host "$profile is disabled since $(Get-Date -format "yyyy-MM-dd" $owner.AccountExpirationDate), will be deleted"
                if ($owner.ProfilePath.Length -gt 0) {
                    Write-Warning "Deleting ProfilePath for $profile"
                    $ownerToBeCleared.Add($owner.SID) > $null
                }
                if ($owner.HomeDirectory.Length -gt 0) {
                    Write-Warning "Deleting HomeDirectory and HomeDrive for $profile"
                    $ownerToBeCleared.Add($owner.SID) > $null
                }
                $toBeDeleted.Add($path + "\" + $profile) > $null
            } elseif ($owner.enabled -eq $False) {
                #Write-Host "$profile is disabled since $(Get-Date -format "yyyy-MM-dd" $owner.AccountExpirationDate)"
            }
        } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Warning "Deleting $profile because account does not exist"
            $toBeDeleted.Add($path + "\" + $profile) > $null
        }
    }
}

Write-Warning "Do you want to delete the following folders:"
$toBeDeleted -join ", "
$secretphrase = "DELETE $($toBeDeleted.Count) folders and clear $($ownerToBeCleared.Count) users"

$answer = Read-Host -Prompt "Type '$secretphrase' to confirm deletion"
if ($answer -ne $secretphrase) {
    Write-Error "Please confirm by typing the attention phrase exactly"
    exit
}

foreach ($deleteFolder in $toBeDeleted) {
    $newName = "DELETE-" + (Get-Date -Format "yyyyMMdd") + "-" + ($deleteFolder -replace '.*\\')
    Rename-Item -Path $deleteFolder -NewName $newName
}

foreach ($clearAccount in $ownerToBeCleared) {
    Set-ADUser -Identity $clearAccount -ProfilePath $null -HomeDirectory $null -HomeDrive $null
    foreach ($group in $deleteFromGroups) {
        Remove-ADGroupMember -Identity $group -Members $clearAccount -Confirm:$False
    }
}