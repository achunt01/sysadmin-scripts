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
