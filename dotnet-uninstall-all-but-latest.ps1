<#
.SYNOPSIS
    Removes legacy .NET runtimes, ASP.NET runtimes, and hosting bundles.

.DESCRIPTION
    - Skips execution on the excluded host: CBHREWARDS
    - Installs the .NET Uninstall Tool if not already present
    - Removes all but the latest runtime, ASP.NET runtime, and hosting bundle
    - Explicitly removes specified legacy versions

.NOTES
    Requires administrative privileges.
#>


#region Variables

$UninstallTool = 'C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe'
$MsiUrl = 'https://github.com/dotnet/cli-lab/releases/download/1.7.618124/dotnet-core-uninstall.msi'
$MsiPath = Join-Path $env:TEMP 'dotnet-core-uninstall.msi'

# Versions to remove regardless of latest status
$LegacyVersions = @(
    '6.0.36'
    '7.0.20'
)

#endregion

#region Install .NET Uninstall Tool

if (-not (Test-Path $UninstallTool)) {

    Write-Output 'Downloading .NET Uninstall Tool...'

    try {
        Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -ErrorAction Stop

        Write-Output 'Installing .NET Uninstall Tool...'

        Start-Process `
            -FilePath 'msiexec.exe' `
            -ArgumentList "/i `"$MsiPath`" /quiet /norestart" `
            -Wait `
            -NoNewWindow

        Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Error "Failed to install .NET Uninstall Tool. $_"
        exit 1
    }
}

if (-not (Test-Path $UninstallTool)) {
    Write-Error "Uninstall tool not found: $UninstallTool"
    exit 1
}

Write-Output "Using uninstall tool: $UninstallTool"

#endregion

#region Remove All But Latest

Write-Output 'Removing all but the latest .NET runtimes...'
& $UninstallTool remove --runtime --all-but-latest --yes --verbosity diag

Write-Output 'Removing all but the latest ASP.NET runtimes...'
& $UninstallTool remove --aspnet-runtime --all-but-latest --yes --verbosity diag

Write-Output 'Removing all but the latest hosting bundles...'
& $UninstallTool remove --hosting-bundle --all-but-latest --yes --verbosity diag

#endregion

#region Remove Specific Legacy Versions

foreach ($Version in $LegacyVersions) {

    Write-Output "Removing .NET version $Version..."

    & $UninstallTool remove --runtime $Version --yes --verbosity diag
    & $UninstallTool remove --aspnet-runtime $Version --yes --verbosity diag
    & $UninstallTool remove --hosting-bundle $Version --yes --verbosity diag
}

#endregion

Write-Output ' .NET cleanup completed successfully.'
