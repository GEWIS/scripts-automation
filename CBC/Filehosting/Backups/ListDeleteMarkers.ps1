$bucket = "objectlock-test"
$prefix = "2025/"            # set a prefix if you only want part of the fileserver (e.g. "fileserver/")
$outCsv = "delete_markers.csv"

$allMarkers = @()
$keyMarker = $null
$versionIdMarker = $null

while ($true) {
    $args = @("--bucket",$bucket)
    if ($prefix) { $args += @("--prefix",$prefix) }
    if ($keyMarker)      { $args += @("--key-marker",$keyMarker) }
    if ($versionIdMarker){ $args += @("--version-id-marker",$versionIdMarker) }

    $json = aws s3api list-object-versions @args --output json | ConvertFrom-Json

    if ($null -ne $json.DeleteMarkers) {
        foreach ($dm in $json.DeleteMarkers) {
            $allMarkers += [PSCustomObject]@{
                Key = $dm.Key
                VersionId = $dm.VersionId
                IsLatest = $dm.IsLatest
                LastModified = $dm.LastModified
                OwnerId = $dm.Owner.Id
            }
        }
    }

    if ($json.IsTruncated -eq $true) {
        $keyMarker = $json.NextKeyMarker
        $versionIdMarker = $json.NextVersionIdMarker
    } else {
        break
    }
}

$allMarkers | Sort-Object Key,LastModified | Export-Csv -NoTypeInformation $outCsv
Write-Host "Found $($allMarkers.Count) delete markers. Exported to $outCsv"
