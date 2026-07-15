<#
.SYNOPSIS
    Deep registry sweep for McAfee remnants across every hive, logged to file.

.DESCRIPTION
    Walks the standard uninstall hives (64-bit, 32-bit, per-user), loads each local
    user's NTUSER.DAT to catch per-user installs, and checks the MSI Installer
    Products and UserData hives for leftover product codes. Read-only discovery —
    it reports what's still registered so removal can be verified. Logs everything
    to C:\Windows\Temp\McAfeeDeepSweep.log.

.NOTES
    Author: Amanda Hunt
    Run elevated. Loads and unloads user hives via reg.exe.
#>

$LogFile = "C:\Windows\Temp\McAfeeDeepSweep.log"

function Write-Log {
    param([string]$Message)
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line  = "[$Stamp] $Message"
    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
}

Write-Log "===== McAfee Deep Registry Sweep ====="

# Every uninstall hive we know about -- 64-bit, 32-bit, and per-user
$UninstallPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Also check all user hives -- Ninja may be reading a per-user install
# that only shows up when that user's hive is loaded
Write-Log "`n[Checking all local user hives]"
$UserProfiles = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" |
    Where-Object { $_.ProfileImagePath -match "C:\\Users\\" } |
    Select-Object -ExpandProperty ProfileImagePath

foreach ($Profile in $UserProfiles) {
    $NtUser = "$Profile\NTUSER.DAT"
    if (-not (Test-Path $NtUser)) { continue }

    $Username = Split-Path $Profile -Leaf
    $HiveName = "TempHive_$Username"

    # Load the hive so we can query it
    reg.exe load "HKU\$HiveName" $NtUser 2>&1 | Out-Null

    $HivePath = "Registry::HKU\$HiveName\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    if (Test-Path $HivePath) {
        Get-ChildItem $HivePath -ErrorAction SilentlyContinue |
            ForEach-Object {
                $Props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($Props.DisplayName -match "McAfee" -or $Props.Publisher -match "McAfee") {
                    Write-Log "  [User: $Username] $($Props.DisplayName) $($Props.DisplayVersion) | Key: $($_.PSPath)"
                }
            }
    }

    reg.exe unload "HKU\$HiveName" 2>&1 | Out-Null
}

Write-Log "`n[Standard uninstall hives]"
foreach ($BasePath in $UninstallPaths) {
    if (-not (Test-Path $BasePath)) { continue }
    Get-ChildItem $BasePath -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            # Match on name, publisher, or any value containing mcafee
            $AllValues = ($Props.PSObject.Properties.Value -join " ")
            if ($AllValues -match "McAfee" -or $Props.DisplayName -match "McAfee" -or $Props.Publisher -match "McAfee") {
                Write-Log "  PATH:      $($_.PSPath)"
                Write-Log "  Name:      $($Props.DisplayName)"
                Write-Log "  Version:   $($Props.DisplayVersion)"
                Write-Log "  Publisher: $($Props.Publisher)"
                Write-Log "  Uninstall: $($Props.UninstallString)"
                Write-Log "  InstallDate: $($Props.InstallDate)"
                Write-Log "  ---"
            }
        }
}

# Also check the Classes hive for MSI product codes
Write-Log "`n[HKLM Classes - MSI Installer Products]"
$InstallerPath = "HKLM:\Software\Classes\Installer\Products"
if (Test-Path $InstallerPath) {
    Get-ChildItem $InstallerPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($Props.ProductName -match "McAfee") {
                Write-Log "  GUID: $($_.PSChildName)"
                Write-Log "  Name: $($Props.ProductName)"
                Write-Log "  ---"
            }
        }
}

# Check the Installer\UserData hive too -- per-user MSI installs land here
Write-Log "`n[HKLM Installer UserData]"
$UserDataPath = "HKLM:\Software\Classes\Installer\UserData"
if (Test-Path $UserDataPath) {
    Get-ChildItem $UserDataPath -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -eq "InstallProperties" } |
        ForEach-Object {
            $Props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($Props.DisplayName -match "McAfee" -or $Props.Publisher -match "McAfee") {
                Write-Log "  PATH:    $($_.PSPath)"
                Write-Log "  Name:    $($Props.DisplayName)"
                Write-Log "  Version: $($Props.DisplayVersion)"
                Write-Log "  ---"
            }
        }
}

Write-Log "`n===== Deep Sweep Complete ====="
Write-Log "Log: $LogFile"