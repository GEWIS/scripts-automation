$bucket = "objectlock-test"
$prefix = "2025/"          # e.g. "fileserver/"
$dryRun = $false       # change to $false to actually delete
$batchSize = 1000

$markers = @()
$nextKeyMarker = $null
$nextVersionIdMarker = $null

Write-Host "Listing delete markers in bucket '$bucket'..."

do {
    $cmd = @(
        "s3api", "list-object-versions",
        "--bucket", $bucket,
        "--output", "json"
    )

    if ($prefix) { $cmd += @("--prefix", $prefix) }
    if ($nextKeyMarker) { $cmd += @("--key-marker", $nextKeyMarker) }
    if ($nextVersionIdMarker) { $cmd += @("--version-id-marker", $nextVersionIdMarker) }

    $result = aws @cmd | ConvertFrom-Json

    if ($result.DeleteMarkers) {
        $result.DeleteMarkers | ForEach-Object {
            $markers += [PSCustomObject]@{
                Key        = $_.Key
                VersionId  = $_.VersionId
                LastModified = $_.LastModified
            }
        }
    }

    $nextKeyMarker = $result.NextKeyMarker
    $nextVersionIdMarker = $result.NextVersionIdMarker
} while ($result.IsTruncated -eq $true)

Write-Host "Found $($markers.Count) delete markers.`n"

if ($dryRun) {
    Write-Host "Dry run: displaying found delete markers..."
    $markers | Format-Table Key, VersionId, LastModified
    Write-Host "`nTo actually delete, set `$dryRun = `$false."
    return
}

# Proceed with actual deletion
for ($i = 0; $i -lt $markers.Count; $i += $batchSize) {
    $batch = $markers[$i..([math]::Min($i + $batchSize - 1, $markers.Count - 1))]
    $deleteSpec = @{ Objects = @() }

    foreach ($m in $batch) {
        $deleteSpec.Objects += @{ Key = $m.Key; VersionId = $m.VersionId }
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    $deleteSpec | ConvertTo-Json -Compress | Out-File -FilePath $tempFile -Encoding ascii

    Write-Host "Deleting batch $($i / $batchSize + 1) with $($batch.Count) items..."
    aws s3api delete-objects --bucket $bucket --delete file://$tempFile --output json
    Remove-Item $tempFile
}
