<#
.SYNOPSIS
    Installs pending Windows updates without rebooting, skipping Preview updates.

.DESCRIPTION
    Uses the Windows Update Agent (WUA) COM API directly (same reasoning as the missing-
    updates script — dodges the malformed-metadata ArgumentException). Searches for
    updates that aren't installed, filters out Preview releases, installs the rest, and
    suppresses the reboot so it can be scheduled separately.

.NOTES
    Author: Amanda Hunt
    Run elevated. A reboot is still required afterward to finish some updates.
#>

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# same deal - using WUA directly instead of PSWindowsUpdate
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServerSelection = 2

$results = $searcher.Search("IsInstalled=0")

# filter out Preview updates to match your -NotCategory Preview flag
$toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($update in $results.Updates) {
    if ($update.Title -notmatch "Preview") {
        $toInstall.Add($update) | Out-Null
    }
}

Write-Host "Queuing $($toInstall.Count) updates to download and install..." -ForegroundColor Cyan

# download first, then install - WUA does these as separate steps
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $toInstall
Write-Host "Downloading..." -ForegroundColor Yellow
$downloader.Download()

$installer = $session.CreateUpdateInstaller()
$installer.Updates = $toInstall
$installer.AllowSourcePrompts = $false
Write-Host "Installing..." -ForegroundColor Yellow
$installResult = $installer.Install()

Write-Host "Done. Reboot required: $($installResult.RebootRequired)" -ForegroundColor Green
