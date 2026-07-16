<#
.SYNOPSIS
    Reports free space on all fixed drives and flags anything running low.

.DESCRIPTION
    Pulls every fixed disk, works out free space and percent free, and prints a
    table. Any drive under the threshold gets called out and flips the exit code
    to 1 so an RMM condition can alert on it.

.PARAMETER MinimumPercentFree
    Percent free below which a drive counts as low. Defaults to 15.

.NOTES
    Author: Amanda Hunt
    exit 0 = all drives fine, exit 1 = at least one drive low.
#>
param (
    [int]$MinimumPercentFree = 15
)

# DriveType 3 = local fixed disk. Skips USB sticks, optical, mapped drives.
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"

$low = @()
$report = foreach ($d in $disks) {
    # a card reader with no media reports size 0 - skip those
    if (-not $d.Size) { continue }

    $pctFree = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
    if ($pctFree -lt $MinimumPercentFree) { $low += $d.DeviceID }

    [PSCustomObject]@{
        Drive      = $d.DeviceID
        'Size(GB)' = [math]::Round($d.Size / 1GB, 1)
        'Free(GB)' = [math]::Round($d.FreeSpace / 1GB, 1)
        'Free(%)'  = $pctFree
        Status     = if ($pctFree -lt $MinimumPercentFree) { "LOW" } else { "OK" }
    }
}

$report | Format-Table -AutoSize

if ($low.Count -gt 0) {
    Write-Host "Low disk space on: $($low -join ', ') (threshold $MinimumPercentFree%)"
    exit 1
}

Write-Host "All drives above $MinimumPercentFree% free."
exit 0
