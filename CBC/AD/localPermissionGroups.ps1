Import-Module ..\..\General\readEnv.psm1

Import-Environment ..\general.env

$computers = Get-ADComputer -Filter {enabled -eq $True -and operatingSystem -like "*Windows*"} -Properties OperatingSystem

# For performance reasons we do a local comparison to check if the group exists
$existingGroups = (Get-ADGroup -SearchBase $env:GEWIS_OU_LOCALPERMISSIONS -Filter *).SamAccountName

$listPermissions = @{
    "Local login" = "login";
    "Administrator" = "admin";
    "Network login" = "network";
    "Batch login" = "batch";
    "Remote Desktop" = "rdp";
    "Shutdown" = "shutdown";
}

$computers.Count

foreach ($computer in $computers) {
    $name = $computer.Name
    $prefix = "CP"
    if ($computer.OperatingSystem -like "*Server*") { $prefix = "SP" }
    foreach ($perm in $listPermissions.Keys) {
        $long = "${prefix} - $name - $perm"
        $short = "${prefix}_${name}_$($listPermissions.$perm)"
        if ($short -inotin $existingGroups) {
            New-ADGroup `
                -Name $long `
                -SamAccountName $short `
                -GroupCategory Security `
                -GroupScope DomainLocal `
                -Path $env:GEWIS_OU_LOCALPERMISSIONS `
                -ErrorAction Ignore
        }
    }
}
