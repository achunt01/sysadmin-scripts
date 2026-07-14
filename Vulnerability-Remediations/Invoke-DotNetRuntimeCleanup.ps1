# =====================================================================
# .NET Runtime Cleanup Script
#
# Purpose:
# - Keep ONLY the latest released patch per installed runtime family
# - Remove superseded .NET / ASP.NET / Hosting Bundle versions
# - Prevent uninstall if processes are actively using old runtimes
# - Clean orphaned shared runtime folders
#
# Safe for mixed LTS / STS environments
# =====================================================================

# ─── CONFIG ───────────────────────────────────────────────────────────

$ExcludedHosts = @(
    "REWARDS"
)

# ─── STEP 0: Host exclusion ───────────────────────────────────────────

if ($ExcludedHosts -contains $env:COMPUTERNAME.ToUpper()) {
    Write-Output "Hostname excluded from execution. Exiting."
    exit 0
}

# ─── STEP 1: Ensure dotnet-core-uninstall exists ─────────────────────

$uninstallExe = "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe"

if (-not (Test-Path $uninstallExe)) {

    $msiUrl  = "https://github.com/dotnet/cli-lab/releases/download/1.7.618124/dotnet-core-uninstall.msi"
    $msiPath = Join-Path $env:TEMP "dotnet-core-uninstall.msi"

    Write-Output "Downloading dotnet-core-uninstall..."

    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
    }
    catch {
        Write-Error "Failed downloading uninstall tool."
        exit 1
    }

    Write-Output "Installing dotnet-core-uninstall..."

    $proc = Start-Process `
        -FilePath "msiexec.exe" `
        -ArgumentList "/i `"$msiPath`" /quiet /norestart" `
        -Wait `
        -PassThru

    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        Write-Error "MSI install failed with exit code $($proc.ExitCode)"
        exit 1
    }
}

if (-not (Test-Path $uninstallExe)) {
    Write-Error "dotnet-core-uninstall not found."
    exit 1
}

Write-Output "Uninstall tool located:"
Write-Output "  $uninstallExe"

# ─── STEP 2: Inventory installed runtimes ────────────────────────────

Write-Output ""
Write-Output "Querying installed runtimes..."

$runtimeLines = & dotnet --list-runtimes 2>$null

if (-not $runtimeLines) {
    Write-Error "No runtimes detected."
    exit 1
}

$installedRuntimes = $runtimeLines |
    ForEach-Object {

        $parts = ($_ -split '\s+')

        if ($parts.Count -lt 2) {
            return
        }

        $runtimeName = $parts[0]
        $version     = $parts[1]

        if ($version -notmatch '^\d+\.\d+\.\d+$') {
            return
        }

        [PSCustomObject]@{
            Runtime     = $runtimeName
            Version     = $version
            MajorMinor  = ($version -split '\.')[0..1] -join '.'
        }
    } |
    Sort-Object Runtime, { [version]$_.Version } -Unique

if (-not $installedRuntimes) {
    Write-Error "No valid runtimes discovered."
    exit 1
}

Write-Output ""
Write-Output "Installed runtimes:"
$installedRuntimes | Format-Table -AutoSize

# ─── STEP 3: Query Microsoft release metadata ────────────────────────

Write-Output ""
Write-Output "Querying Microsoft release metadata..."

$releaseIndexUrl = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

try {
    $releaseIndex = Invoke-RestMethod -Uri $releaseIndexUrl
}
catch {
    Write-Error "Failed retrieving Microsoft release index."
    exit 1
}

$keeperVersions = @()

$families = $installedRuntimes.MajorMinor | Sort-Object -Unique

foreach ($family in $families) {

    Write-Output ""
    Write-Output "Checking runtime family: $family"

    $channel = $releaseIndex.'releases-index' |
        Where-Object {
            $_.'channel-version' -eq $family
        }

    if (-not $channel) {
        Write-Warning "No release channel metadata found for $family"
        continue
    }

    try {

        $releaseData = Invoke-RestMethod -Uri $channel.'releases.json'

        $latestRelease = $releaseData.releases |
            Select-Object -First 1

        $latestRuntime = $latestRelease.runtime.version

        if ($latestRuntime) {

            Write-Output "Latest released runtime for $family = $latestRuntime"

            $keeperVersions += $latestRuntime
        }
    }
    catch {
        Write-Warning "Failed querying release data for $family"
    }
}

$keeperVersions = $keeperVersions | Sort-Object -Unique

if (-not $keeperVersions) {
    Write-Error "No keeper versions determined."
    exit 1
}

Write-Output ""
Write-Output "Keeper versions:"
$keeperVersions | ForEach-Object {
    Write-Output "  $_"
}

# ─── STEP 4: Determine removable versions ────────────────────────────

$installedVersions = $installedRuntimes.Version | Sort-Object -Unique

$oldVersions = $installedVersions |
    Where-Object {
        $keeperVersions -notcontains $_
    }

Write-Output ""
Write-Output "Installed versions:"
$installedVersions | ForEach-Object {
    Write-Output "  $_"
}

Write-Output ""
Write-Output "Outdated versions targeted for removal:"
$oldVersions | ForEach-Object {
    Write-Output "  $_"
}

if (-not $oldVersions) {
    Write-Output ""
    Write-Output "No outdated runtimes detected."
    exit 0
}

# ─── STEP 5: Detect running processes using old runtimes ─────────────

Write-Output ""
Write-Output "Scanning running processes..."

$blockedProcesses = @()

$sharedBase = "C:\Program Files\dotnet\shared"

Get-Process | ForEach-Object {

    $proc = $_

    try {

        $modules = $proc.Modules | Where-Object {
            $_.FileName -like "$sharedBase\*"
        }

        foreach ($mod in $modules) {

            $parts = $mod.FileName -split '\\'

            $versionSegment = $parts |
                Where-Object {
                    $_ -match '^\d+\.\d+\.\d+$'
                } |
                Select-Object -First 1

            if (-not $versionSegment) {
                continue
            }

            $versionIndex = [Array]::IndexOf($parts, $versionSegment)

            if ($versionIndex -lt 1) {
                continue
            }

            $runtimeType = $parts[$versionIndex - 1]

            if ($oldVersions -contains $versionSegment) {

                $blockedProcesses += [PSCustomObject]@{
                    Name        = $proc.Name
                    PID         = $proc.Id
                    Version     = $versionSegment
                    RuntimeType = $runtimeType
                    Path        = $proc.Path
                }

                break
            }
        }
    }
    catch {
        # Protected process or access denied
    }
}

$blockedProcesses = $blockedProcesses |
    Sort-Object PID -Unique

if ($blockedProcesses.Count -gt 0) {

    Write-Output ""
    Write-Output "BLOCKED:"
    Write-Output "Processes currently using outdated runtimes:"
    Write-Output ""

    $blockedProcesses |
        Format-Table -AutoSize Name, PID, Version, RuntimeType, Path

    Write-Output ""
    Write-Output "Stop or migrate these processes before cleanup."

    exit 1
}

Write-Output ""
Write-Output "No active processes using outdated runtimes."

# ─── STEP 6: Remove outdated runtimes ────────────────────────────────

foreach ($version in $oldVersions) {

    Write-Output ""
    Write-Output "Removing runtime version: $version"

    & "$uninstallExe" remove `
        --runtime `
        $version `
        --yes `
        --verbosity minimal

    & "$uninstallExe" remove `
        --aspnet-runtime `
        $version `
        --yes `
        --verbosity minimal

    & "$uninstallExe" remove `
        --hosting-bundle `
        $version `
        --yes `
        --verbosity minimal
}


# ─── STEP 7: Strict filesystem enforcement vs latest released patches ─────

$sharedPaths = @(
    "C:\Program Files\dotnet\shared\Microsoft.NETCore.App",
    "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App",
    "C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App"
)

foreach ($basePath in $sharedPaths) {

    if (-not (Test-Path $basePath)) { continue }

    Write-Output ""
    Write-Output "Scanning: $basePath"

    Get-ChildItem -Path $basePath -Directory | ForEach-Object {

        $folder = $_.Name
        $full   = $_.FullName

        if ($folder -notmatch '^\d+\.\d+\.\d+$') {
            return
        }

        $folderVersion = [version]$folder
        $majorMinor = "$($folderVersion.Major).$($folderVersion.Minor)"

        # find latest keeper for this family (from Microsoft feed result)
        $keeper = $keeperVersions |
            Where-Object { $_ -like "$majorMinor.*" } |
            ForEach-Object { [version]$_ } |
            Sort-Object |
            Select-Object -Last 1

        if (-not $keeper) {
            Write-Output "SKIP (no keeper for family): $folder"
            return
        }

        if ($folderVersion -lt $keeper) {

            Write-Output "REMOVE (outdated patch): $folder vs keeper $keeper"

            try {
                Remove-Item -Path $full -Recurse -Force -ErrorAction Stop
                Write-Output "Removed: $folder"
            }
            catch {
                Write-Warning "Failed removing $folder : $_"
            }

            return
        }

        Write-Output "KEEP: $folder"
    }
}
# ─── STEP 8: Final verification ──────────────────────────────────────

Write-Output ""
Write-Output "────────────────────────────────────"
Write-Output "Remaining registered runtimes"
Write-Output "────────────────────────────────────"

& dotnet --list-runtimes 2>$null

Write-Output ""
Write-Output "────────────────────────────────────"
Write-Output "Remaining shared runtime folders"
Write-Output "────────────────────────────────────"

foreach ($basePath in $sharedPaths) {

    if (-not (Test-Path $basePath)) {
        continue
    }

    Write-Output ""
    Write-Output $basePath

    Get-ChildItem -Path $basePath -Directory |
        Select-Object Name
}

Write-Output ""
Write-Output "Cleanup complete."
