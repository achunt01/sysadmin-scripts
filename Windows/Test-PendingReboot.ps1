<#
.SYNOPSIS
    RMM condition — checks whether the machine is sitting on a pending reboot.

.DESCRIPTION
    Checks the usual places Windows stashes its "please restart me" flags:
    Component Based Servicing, Windows Update's RebootRequired key, and a pending
    computer rename. Prints what it found plus current uptime, then exits 1 if a
    reboot is pending so an RMM condition can catch it, or 0 if the machine is clean.

.NOTES
    Author: Amanda Hunt
    exit 0 = no reboot pending, exit 1 = reboot pending.
    PendingFileRenameOperations is reported for context but doesn't trip the
    condition by itself -- installers leave entries there all the time and it
    would false-positive constantly.
#>

$reasons = @()

# CBS - servicing stack is waiting on a restart
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
    $reasons += "Component Based Servicing"
}

# Windows Update flagged one
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $reasons += "Windows Update"
}

# machine rename that hasn't taken effect yet
$activeName  = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
$pendingName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -ErrorAction SilentlyContinue).ComputerName
if ($activeName -and $pendingName -and ($activeName -ne $pendingName)) {
    $reasons += "Computer rename pending ($activeName -> $pendingName)"
}

# file renames queued for next boot - informational only, see notes
$pfro = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
$pfroCount = @($pfro | Where-Object { $_ }).Count

# uptime is useful context when deciding how hard to push the reboot
$lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptime   = (Get-Date) - $lastBoot

Write-Host "Computer : $env:COMPUTERNAME"
Write-Host "Uptime   : $([math]::Round($uptime.TotalDays, 1)) days (booted $($lastBoot.ToString('yyyy-MM-dd HH:mm')))"
Write-Host "Queued file renames: $pfroCount"
Write-Host ""

if ($reasons.Count -gt 0) {
    Write-Host "REBOOT PENDING:"
    $reasons | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "No reboot pending."
exit 0
