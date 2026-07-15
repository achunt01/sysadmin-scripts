<#
.SYNOPSIS
    Completely removes Zoom from every system and user-profile location.

.DESCRIPTION
    Rips out Zoom across all system and per-user paths without relying on %APPDATA%,
    so it works when run as SYSTEM from an RMM. Logs to stdout and a timestamped file.
    Do a fresh Zoom install afterward if the machine still needs it.

.NOTES
    Author: Amanda Hunt
    Run elevated (SYSTEM via RMM is fine).
#>

# Remove-ZoomCompletely.ps1
# Performs a complete Zoom removal across all system and user-profile paths.
# Designed to run as SYSTEM (e.g. via NinjaRMM) -- doesn't rely on %APPDATA%.
# Logs to both stdout and a timestamped file under C:\ProgramData\Dataprise\Logs.
# Run elevated. Do a fresh Zoom install after this completes.

$ErrorActionPreference = "SilentlyContinue"

# -------------------------------------------------------
# Logging setup -- file + stdout so Ninja captures it too
# -------------------------------------------------------
$logDir = "C:\support"
if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\zoomcleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "Starting Zoom cleanup. Log: $logFile"

# -------------------------------------------------------
# 1. Kill Zoom processes -- can't clean what's open
# -------------------------------------------------------
$zoomProcs = Get-Process | Where-Object { $_.Name -like "*Zoom*" }
if ($zoomProcs) {
    Write-Log "Killing running Zoom processes..."
    $zoomProcs | Stop-Process -Force
} else {
    Write-Log "No Zoom processes running."
}

# -------------------------------------------------------
# 2. Stop and delete Zoom services if present
# -------------------------------------------------------
$zoomServices = Get-Service | Where-Object { $_.Name -like "*Zoom*" }
foreach ($svc in $zoomServices) {
    Write-Log "Stopping service: $($svc.Name)"
    Stop-Service $svc.Name -Force
    Write-Log "Deleting service: $($svc.Name)"
    sc.exe delete $svc.Name | Out-Null
}
if (-not $zoomServices) { Write-Log "No Zoom services found." }

# -------------------------------------------------------
# 3. Filesystem -- system-level paths
# -------------------------------------------------------
$systemPaths = @(
    "C:\Program Files\Zoom",
    "C:\Program Files (x86)\Zoom",
    "C:\ProgramData\Zoom"
)

foreach ($path in $systemPaths) {
    if (Test-Path $path) {
        Write-Log "Removing: $path"
        Remove-Item $path -Recurse -Force
    } else {
        Write-Log "Not found (skipping): $path"
    }
}

# -------------------------------------------------------
# 4. Per-user profile paths -- walk C:\Users explicitly
#    since SYSTEM context won't resolve %APPDATA%
# -------------------------------------------------------
$userProfiles = Get-ChildItem "C:\Users" -Directory

foreach ($profile in $userProfiles) {
    $userPaths = @(
        "$($profile.FullName)\AppData\Roaming\Zoom",
        "$($profile.FullName)\AppData\Local\Zoom",
        "$($profile.FullName)\AppData\LocalLow\Zoom"
    )
    foreach ($path in $userPaths) {
        if (Test-Path $path) {
            Write-Log "Removing: $path"
            Remove-Item $path -Recurse -Force
        }
    }
}

# -------------------------------------------------------
# 5. Start Menu shortcuts and Desktop shortcuts (all users)
# -------------------------------------------------------
$shortcutPaths = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu",
    "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu",
    "C:\Users\*\Desktop",
    "C:\Users\Public\Desktop"
)

foreach ($pattern in $shortcutPaths) {
    Get-ChildItem $pattern -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*Zoom*" } |
        ForEach-Object {
            Write-Log "Removing shortcut: $($_.FullName)"
            Remove-Item $_.FullName -Force
        }
}

# -------------------------------------------------------
# 6. HKLM uninstall keys (both 64-bit and 32-bit hives)
# -------------------------------------------------------
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($regPath in $uninstallPaths) {
    Get-ChildItem $regPath -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue("DisplayName") -like "*Zoom*" } |
        ForEach-Object {
            Write-Log "Removing uninstall key: $($_.PSPath)"
            Remove-Item $_.PSPath -Recurse -Force
        }
}

# -------------------------------------------------------
# 7. HKLM Zoom software keys
# -------------------------------------------------------
$hklmKeys = @(
    "HKLM:\SOFTWARE\Zoom",
    "HKLM:\SOFTWARE\WOW6432Node\Zoom",
    "HKLM:\SOFTWARE\ZoomVideoConferencing"
)

foreach ($key in $hklmKeys) {
    if (Test-Path $key) {
        Write-Log "Removing: $key"
        Remove-Item $key -Recurse -Force
    }
}

# -------------------------------------------------------
# 8. Per-user HKCU registry -- load NTUSER.DAT for each
#    profile since SYSTEM has no HKCU for other users.
#    Warns if load fails (user likely logged in).
# -------------------------------------------------------
foreach ($profile in $userProfiles) {
    $hivePath = "$($profile.FullName)\NTUSER.DAT"
    $mountName = "TempHive_$($profile.Name)"
    $mountPoint = "HKLM:\$mountName"

    if (-not (Test-Path $hivePath)) { continue }

    $loadResult = reg load "HKLM\$mountName" $hivePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Could not load hive for $($profile.Name) -- user may be logged in. HKCU keys skipped for this profile. Re-run after logoff or clean manually." "WARN"
        continue
    }

    $userKeys = @(
        "$mountPoint\SOFTWARE\Zoom",
        "$mountPoint\SOFTWARE\ZoomVideoConferencing",
        "$mountPoint\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ZoomUMX"
    )

    foreach ($key in $userKeys) {
        if (Test-Path $key) {
            Write-Log "Removing user hive key ($($profile.Name)): $key"
            Remove-Item $key -Recurse -Force
        }
    }

    # GC flush before unload -- otherwise the hive stays locked
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $unloadResult = reg unload "HKLM\$mountName" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Could not unload hive for $($profile.Name) -- may still be in use." "WARN"
    }
}

# -------------------------------------------------------
# 9. Windows Installer cache -- match by product code,
#    not filename. Only remove entries confirmed as Zoom.
#    NOTE: this is intentional for reinstall-from-scratch.
#    Do not run this if you plan to repair rather than reinstall.
# -------------------------------------------------------
Write-Log "Scanning Windows Installer cache for Zoom product entries..."

$installerRegBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData"

if (Test-Path $installerRegBase) {
    Get-ChildItem "$installerRegBase\*\Products" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $installProps = "$($_.PSPath)\InstallProperties"
            if (Test-Path $installProps) {
                $props = Get-ItemProperty $installProps -ErrorAction SilentlyContinue
                if ($props.DisplayName -like "*Zoom*") {
                    # Only delete the cached MSI if we're sure it's Zoom
                    if ($props.LocalPackage -and (Test-Path $props.LocalPackage)) {
                        Write-Log "Removing cached MSI: $($props.LocalPackage)"
                        Remove-Item $props.LocalPackage -Force
                    }
                    Write-Log "Removing installer product key: $($_.PSPath)"
                    Remove-Item $_.PSPath -Recurse -Force
                }
            }
        }
}

Write-Log "Zoom cleanup complete. Proceed with fresh install."
Write-Log "Log saved to: $logFile"
