<#
.SYNOPSIS
    Clears stuck print jobs by bouncing the spooler and emptying the queue folder.

.DESCRIPTION
    The fix for "the printer says error and nothing prints": stop the Print
    Spooler, delete everything in the spool folder, start it back up. The restart
    lives in a finally block so the spooler comes back even if the cleanup hiccups.

.NOTES
    Author: Amanda Hunt
    Run elevated. Clears ALL queued jobs on the machine, not just one printer's.
#>

$spoolPath = Join-Path $env:SystemRoot "System32\spool\PRINTERS"

$jobs = @(Get-ChildItem $spoolPath -ErrorAction SilentlyContinue)
Write-Host "Jobs sitting in the queue: $($jobs.Count)"

if ($jobs.Count -eq 0) {
    Write-Host "Queue is already empty - nothing to do."
    exit 0
}

try {
    Write-Host "Stopping Print Spooler..."
    Stop-Service -Name Spooler -Force -ErrorAction Stop

    Write-Host "Clearing $spoolPath..."
    Remove-Item "$spoolPath\*" -Force -ErrorAction SilentlyContinue
}
finally {
    # whatever happened above, the spooler goes back on
    Write-Host "Starting Print Spooler..."
    Start-Service -Name Spooler
}

$left = @(Get-ChildItem $spoolPath -ErrorAction SilentlyContinue).Count
Write-Host "Done. Files remaining in spool folder: $left"
