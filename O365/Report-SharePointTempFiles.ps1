# ==============================
#  SharePoint "~$" Temp File Report
# ==============================

# Update these site URLs
$Sites = @(
    "https://hunt.sharepoint.com/sites/Z"
)

# Output path for the CSV
$ReportPath = "C:\Temp\SharePoint_TempFiles_Report.csv"

# Array to store results
$AllResults = @()

foreach ($Site in $Sites) {
    Write-Host "Connecting to $Site..." -ForegroundColor Cyan
    try {
        Connect-PnPOnline -Url $Site -PnPManagementShell -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to connect to $Site. Skipping..."
        continue
    }

    # Get all document libraries on the site
    $Libraries = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 -and -not $_.Hidden }

    foreach ($Lib in $Libraries) {
        Write-Host "  Scanning library: $($Lib.Title)" -ForegroundColor Yellow

        $Query = "<View><Query><Where><BeginsWith><FieldRef Name='FileLeafRef'/><Value Type='Text'>~$</Value></BeginsWith></Where></Query></View>"
        $Items = Get-PnPListItem -List $Lib.Title -Query $Query -PageSize 200 -ErrorAction SilentlyContinue

        foreach ($Item in $Items) {
            $AllResults += [PSCustomObject]@{
                SiteURL  = $Site
                Library  = $Lib.Title
                FileName = $Item.FieldValues["FileLeafRef"]
                FileURL  = "https://algr.sharepoint.com$($Item.FieldValues['FileRef'])"
            }
        }
    }

    Disconnect-PnPOnline
}

# Export results
if ($AllResults.Count -gt 0) {
    $AllResults | Export-Csv -Path $ReportPath -NoTypeInformation -Force
    Write-Host "`nReport saved to $ReportPath" -ForegroundColor Green
}
else {
    Write-Host "`nNo '~$' temporary files found on the specified sites." -ForegroundColor Green
}
