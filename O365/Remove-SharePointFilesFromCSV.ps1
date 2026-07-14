<#
.SYNOPSIS
    Bulk deletes SharePoint Online files from a list of URLs provided via CSV.

.DESCRIPTION
    Reads a CSV of SharePoint file URLs, groups them by site collection to
    minimize reconnections, and deletes each file using PnP PowerShell.
    Deleted files are sent to the site recycle bin rather than permanently
    removed, so recovery is possible if needed.

    Logs each deletion result (success or failure) to an output CSV.

.EXAMPLE
    .\Remove-SharePointFilesFromCSV.ps1

    Reads file URLs from the configured $csvPath, connects to each site
    collection interactively, and logs results to $logPath.

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : SharePoint Online via PnP.PowerShell

    Requirements:
      - PnP.PowerShell module
        Install-Module PnP.PowerShell
      - An Entra ID app registration with delegated SharePoint permissions
        Update $clientId below with your app registration's client ID.

    CSV format:
      The input CSV must have a column named "FullUrl" containing the full
      SharePoint URL of each file to delete.
      Example: https://tenant.sharepoint.com/sites/SiteName/Shared Documents/file.docx

    Output columns (log CSV):
      File   - Full URL of the file
      Status - "Deleted" or "Failed"
      Error  - Error message if deletion failed, blank if successful

    Files are recycled, not permanently deleted. Check the site recycle bin
    if you need to recover anything.

    Update $csvPath and $logPath before running in a new environment.
#>

# ============================================================
# CONFIG — update these before running
# ============================================================

# Input CSV — must have a "FullUrl" column
$csvPath = "C:\Temp\SharePointFiles.csv"

# Output log — one row per file with success/failure status
$logPath = "C:\Temp\DeleteResults.csv"

# App registration client ID with delegated SharePoint permissions.
# This uses interactive auth, so the running user still needs access
# to the files being deleted.
$clientId = "YOUR-CLIENT-ID-HERE"

# ============================================================
# MODULE CHECK
# ============================================================

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Host "PnP.PowerShell module not found. Run: Install-Module PnP.PowerShell" -ForegroundColor Red
    return
}

Import-Module PnP.PowerShell -Force

# ============================================================
# VALIDATE INPUT
# ============================================================

if (-not (Test-Path $csvPath)) {
    Write-Host "Input CSV not found at: $csvPath" -ForegroundColor Red
    return
}

$files = Import-Csv -Path $csvPath

if (-not ($files | Get-Member -Name 'FullUrl')) {
    Write-Host "CSV must contain a 'FullUrl' column." -ForegroundColor Red
    return
}

Write-Host "`nLoaded $($files.Count) file(s) from CSV." -ForegroundColor Cyan

# ============================================================
# GROUP BY SITE COLLECTION
# ============================================================

# Grouping by site collection means we connect once per site
# instead of once per file, which is much faster at scale.
$groupedFiles = $files | Group-Object {
    if ($_.'FullUrl' -match "(https://[^/]+/sites/[^/]+)") {
        $matches[1]
    }
    else {
        $_.'FullUrl'
    }
}

# ============================================================
# PROCESS EACH SITE COLLECTION
# ============================================================

$results = @()

foreach ($group in $groupedFiles) {
    $siteUrl = $group.Name
    Write-Host "`nConnecting to: $siteUrl" -ForegroundColor Cyan

    try {
        Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to connect to $siteUrl : $_" -ForegroundColor Red

        # Log every file in this group as failed since we couldn't connect.
        foreach ($item in $group.Group) {
            $results += [PSCustomObject]@{
                File   = $item.FullUrl
                Status = "Failed"
                Error  = "Could not connect to site: $_"
            }
        }
        continue
    }

    foreach ($item in $group.Group) {
        $fileUrl = $item.FullUrl.Trim()

        try {
            $uri = [uri]$fileUrl

            # Strip the site collection prefix to get the site-relative path,
            # which is what Remove-PnPFile expects.
            $sitePath         = ($uri.AbsolutePath -replace "^/sites/[^/]+", "")
            $siteRelativePath = $sitePath.TrimStart("/")

            Write-Host "Deleting: $siteRelativePath"

            # -Recycle sends to the recycle bin instead of permanent delete.
            # Remove that flag only if you're absolutely sure you don't need recovery.
            Remove-PnPFile -SiteRelativeUrl $siteRelativePath -Recycle -Force -ErrorAction Stop

            Write-Host "  Deleted: $siteRelativePath" -ForegroundColor Green

            $results += [PSCustomObject]@{
                File   = $fileUrl
                Status = "Deleted"
                Error  = ""
            }
        }
        catch {
            Write-Warning "  Failed: $fileUrl - $($_.Exception.Message)"

            $results += [PSCustomObject]@{
                File   = $fileUrl
                Status = "Failed"
                Error  = $_.Exception.Message
            }
        }
    }

    Disconnect-PnPOnline
}

# ============================================================
# EXPORT LOG
# ============================================================

$results | Export-Csv -Path $logPath -NoTypeInformation

$deleted = ($results | Where-Object { $_.Status -eq "Deleted" }).Count
$failed  = ($results | Where-Object { $_.Status -eq "Failed" }).Count

Write-Host "`nDone. Deleted: $deleted | Failed: $failed" -ForegroundColor Cyan
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
