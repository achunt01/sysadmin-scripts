<#
.SYNOPSIS
    Interactive event log lookup tool for Windows.

.DESCRIPTION
    Lists all readable event logs on the local machine, prompts for a log
    name and one or more Event IDs, then returns matching events with a
    count summary and full message detail.

    Logs that require elevated access (Security, Sysmon, SMBServer, etc.)
    are skipped silently when running without elevation. Run as Administrator
    to include those logs.

.EXAMPLE
    .\Get-EventLogLookup.ps1

    Runs interactively. Lists available logs, prompts for a log name
    (defaults to "Directory Service"), then prompts for Event IDs one
    at a time. Enter a blank line when done.

.EXAMPLE
    # Checking for LDAP channel binding audit warnings on a domain controller:
    # Log name: Directory Service
    # Event ID: 3074

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : Windows Server 2019/2022, Windows 11

    Event ID reference for common use cases:
      2889  - Unsigned LDAP bind attempted (Directory Service)
      3074  - LDAP channel binding audit warning / would fail at "Always" (Directory Service)
      3075  - LDAP channel binding rejection at "Always" (Directory Service)
      4625  - Failed logon (Security) [requires elevation]
      4740  - Account lockout (Security) [requires elevation]
#>

# ============================================================
# Step 1: List available logs so you know what to type
# ============================================================

Write-Host "`nScanning available event logs...`n" -ForegroundColor Cyan

# -ListLog itself is fine unelevated. It's reading RecordCount on
# restricted logs that throws, so we wrap each one individually.
$logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

$logList = foreach ($log in $logs) {
    try {
        # RecordCount access is what trips the unauthorized error.
        # One try per log means a locked log skips cleanly instead
        # of spraying errors all over the console.
        if ($log.RecordCount -gt 0) {
            [PSCustomObject]@{
                LogName     = $log.LogName
                RecordCount = $log.RecordCount
            }
        }
    }
    catch {
        # Can't read this log at current elevation. Moving on.
        continue
    }
}

$logList |
    Sort-Object RecordCount -Descending |
    Format-Table -AutoSize

# ============================================================
# Step 2: Pick a log
# ============================================================

$logName = Read-Host "Log name [Directory Service]"
if ([string]::IsNullOrWhiteSpace($logName)) {
    $logName = "Directory Service"
}

# Sanity check: make sure the log they typed actually showed up
# in the list before we go hunting in it.
if ($logName -ne "Directory Service" -and $logList.LogName -notcontains $logName) {
    Write-Host "`n'$logName' wasn't in the available log list. It may not exist or may require elevation." -ForegroundColor Yellow
    Write-Host "Proceeding anyway - the query will fail cleanly if it's not accessible.`n" -ForegroundColor Yellow
}

# ============================================================
# Step 3: Collect Event IDs
# ============================================================

$eventIds = @()
Write-Host "`nEnter Event IDs one at a time. Blank line to finish.`n"

while ($true) {
    $entry = Read-Host "Event ID"

    # Blank line means done collecting.
    if ([string]::IsNullOrWhiteSpace($entry)) {
        break
    }

    # Numbers only. Anything else gets flagged and skipped.
    if ($entry -match '^\d+$') {
        $eventIds += [int]$entry
    }
    else {
        Write-Host "  '$entry' doesn't look like an Event ID, skipping." -ForegroundColor Yellow
    }
}

# Nothing collected? Exit cleanly.
if ($eventIds.Count -eq 0) {
    Write-Host "`nNo Event IDs entered, nothing to search." -ForegroundColor Yellow
    return
}

# ============================================================
# Step 4: Run the query
# ============================================================

Write-Host "`nSearching '$logName' for Event ID(s): $($eventIds -join ', ')`n" -ForegroundColor Cyan

$results = Get-WinEvent -FilterHashtable @{
    LogName = $logName
    Id      = $eventIds
} -ErrorAction SilentlyContinue

# ============================================================
# Step 5: Report
# ============================================================

if ($results) {
    Write-Host "Found $($results.Count) matching event(s).`n" -ForegroundColor Green

    # Count per ID first so you get the summary at a glance.
    $results |
        Group-Object Id |
        Select-Object @{N='Event ID'; E={$_.Name}}, Count |
        Format-Table -AutoSize

    # Then the full entries with timestamp and message.
    $results |
        Select-Object TimeCreated, Id, Message |
        Format-List
}
else {
    Write-Host "No matching events found in '$logName'." -ForegroundColor Green
}
