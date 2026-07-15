<#
.SYNOPSIS
    Forcibly removes McAfee WPS when the official MCPR removal tool fails.

.DESCRIPTION
    A two-phase surgical removal. Phase 1 stops services, kills processes, strips
    registry keys (taking ownership where McAfee ACLs block deletion), queues locked
    files for deletion via PendingFileRenameOperations, removes AppX packages, and
    registers a one-time startup task — no forced reboot. Phase 2 runs once as SYSTEM
    on the next boot, finishes folder cleanup, validates, and removes itself.

.NOTES
    Author: Amanda Hunt
    Run elevated. Reboot manually after Phase 1; Phase 2 is automatic on next startup.
#>

# ============================================================
# Remove-McAfeeWPS.ps1
# Surgical removal of McAfee WPS when MCPR fails.
#
# Phase 1: stops services, kills processes, rips registry keys,
#   writes locked files to PendingFileRenameOperations so they
#   delete on next boot, removes AppX packages, registers a
#   one-time Phase 2 startup task.
#   No forced reboot -- we'll handle that manually.
#
# Phase 2: runs once automatically on next startup under SYSTEM,
#   finishes folder cleanup, validates, removes itself.
# ============================================================

#region --- Config ---

$RebootFlagKey  = "HKLM:\SOFTWARE\Dataprise\McAfeeRemoval"
$RebootFlagName = "Phase2Pending"
$LogFile        = "C:\Windows\Temp\McAfeeRemoval.log"
$Phase2Script   = "C:\Windows\Temp\Remove-McAfeeWPS.ps1"

$WpsServices = @(
    "mc-fw-host",
    "mc-wps-update",
    "mc-neo-host",
    "mc-update",
    "mc-inst-uihost",
    "mc-wps-secdashboardservice"
)

$WpsDrivers = @(
    "mfesec",
    "mfeelam"
)

$WpsProcesses = @(
    "mc-fw-host",
    "mc-neo-host",
    "mc-update",
    "mc-inst-uihost",
    "mcshield",
    "mcuicnt",
    "mcsplashtool",
    "mcapexe",
    "mfefire",
    "masvc"
)

$UninstallPattern = "McAfee"

$McAfeeFolders = @(
    "$env:ProgramFiles\McAfee",
    "$env:ProgramFiles\Common Files\McAfee"
)

$WpsTaskPaths = @(
    "\McAfee\"
)

#endregion

#region --- Logging ---

function Write-Log {
    param([string]$Message)
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line  = "[$Stamp] $Message"
    Write-Host $Line
    Add-Content -Path $LogFile -Value $Line -ErrorAction SilentlyContinue
}

#endregion

#region --- Helpers ---

function Stop-WpsProcesses {
    Write-Log "Stopping McAfee WPS processes..."

    foreach ($Name in $WpsProcesses) {
        $Procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
        foreach ($p in $Procs) {
            Write-Log "  Killing: $($p.Name) (PID $($p.Id))"
            try {
                $p | Stop-Process -Force -ErrorAction Stop
                Write-Log "  Killed: $($p.Name)"
            }
            catch {
                Write-Log "  PowerShell kill failed -- trying taskkill"
                taskkill.exe /PID $p.Id /F 2>&1 | ForEach-Object { Write-Log "    taskkill: $_" }
            }
        }
    }
}

function Stop-WpsServices {
    Write-Log "Stopping McAfee WPS services..."

    foreach ($SvcName in $WpsServices) {
        $Svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
        if ($Svc) {
            Write-Log "  Stopping: $SvcName (Status: $($Svc.Status))"
            try {
                Stop-Service -Name $SvcName -Force -ErrorAction Stop
                Write-Log "  Stopped: $SvcName"
            }
            catch {
                Write-Log "  PowerShell stop failed -- trying sc.exe"
                sc.exe stop $SvcName 2>&1 | ForEach-Object { Write-Log "    sc: $_" }
            }
        }
        else {
            Write-Log "  Not found: $SvcName"
        }
    }
}

function Remove-WpsServiceRegistryKeys {
    Write-Log "Removing McAfee service and driver registry keys..."

    $AllKeys = $WpsServices + $WpsDrivers

    foreach ($KeyName in $AllKeys) {
        $KeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$KeyName"
        if (-not (Test-Path $KeyPath)) {
            Write-Log "  Already gone: $KeyName"
            continue
        }

        Write-Log "  Removing: $KeyPath"
        try {
            # Take ownership first -- McAfee ACLs actively block deletion
            $Acl  = Get-Acl $KeyPath
            $Rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $Acl.SetAccessRule($Rule)
            Set-Acl -Path $KeyPath -AclObject $Acl -ErrorAction SilentlyContinue

            Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop
            Write-Log "  Removed: $KeyName"
        }
        catch {
            Write-Log "  PowerShell removal failed -- trying reg.exe"
            reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\$KeyName" /f 2>&1 |
                ForEach-Object { Write-Log "    reg: $_" }
        }
    }
}

function Remove-WpsUninstallKeys {
    Write-Log "Removing McAfee uninstall registry keys..."

    $Paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $Found = 0

    foreach ($BasePath in $Paths) {
        Get-ChildItem -Path $BasePath -ErrorAction SilentlyContinue |
            Where-Object {
                (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -match $UninstallPattern
            } |
            ForEach-Object {
                $Found++
                Write-Log "  Removing: $($_.PSPath)"
                try {
                    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
                    Write-Log "  Removed."
                }
                catch {
                    Write-Log "  Failed: $($_.Exception.Message)"
                }
            }
    }

    if ($Found -eq 0) {
        Write-Log "  No McAfee uninstall keys found."
    }
    else {
        Write-Log "  Total uninstall keys removed: $Found"
    }
}

function Remove-WpsScheduledTasks {
    Write-Log "Removing McAfee scheduled tasks..."

    $Found = 0
    foreach ($TaskPath in $WpsTaskPaths) {
        $Tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
        foreach ($Task in $Tasks) {
            $Found++
            Write-Log "  Removing task: $($Task.TaskPath)$($Task.TaskName)"
            Unregister-ScheduledTask `
                -TaskName $Task.TaskName `
                -TaskPath $Task.TaskPath `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        }
    }

    if ($Found -eq 0) {
        Write-Log "  No McAfee scheduled tasks found."
    }
}

function Remove-AppxPackages {
    Write-Log "Removing McAfee AppX packages..."

    $Packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "mcafee" }

    if ($Packages.Count -eq 0) {
        Write-Log "  No McAfee AppX packages found."
    }

    foreach ($pkg in $Packages) {
        Write-Log "  Removing: $($pkg.PackageFullName)"
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "  Removed: $($pkg.Name)"
        }
        catch {
            Write-Log "  Failed: $($_.Exception.Message)"
        }
    }

    $Provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match "mcafee" }

    if ($Provisioned.Count -eq 0) {
        Write-Log "  No McAfee provisioned packages found."
    }

    foreach ($pkg in $Provisioned) {
        Write-Log "  Removing provisioned: $($pkg.PackageName)"
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop
            Write-Log "  Removed provisioned: $($pkg.PackageName)"
        }
        catch {
            Write-Log "  Failed: $($_.Exception.Message)"
        }
    }
}

function Schedule-LockedFilesForDeletion {
    # MoveFileEx via API doesn't work in the Ninja execution context (error 3
    # on every file despite valid paths). Writing directly to
    # PendingFileRenameOperations in the registry is the reliable equivalent --
    # Windows processes this list before the filesystem fully mounts on next
    # boot, so locked files get deleted before anything can re-lock them.
    Write-Log "Scheduling locked McAfee files for deletion on next boot..."

    $SessionManagerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $Scheduled = 0
    $Entries   = [System.Collections.Generic.List[string]]::new()

    # Pull any existing entries so we don't wipe something Windows already queued
    $Existing = (Get-ItemProperty $SessionManagerKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($Existing) {
        $Entries.AddRange([string[]]$Existing)
    }

    foreach ($Folder in $McAfeeFolders) {
        if (-not (Test-Path $Folder)) {
            Write-Log "  Folder not found, skipping: $Folder"
            continue
        }

        # Take ownership so we can at least enumerate and later delete
        Write-Log "  Taking ownership of: $Folder"
        takeown.exe /F $Folder /R /A /D Y 2>&1 | Out-Null
        icacls.exe $Folder /grant "SYSTEM:(OI)(CI)F" /T /Q 2>&1 | Out-Null
        Write-Log "  Ownership granted."

        Get-ChildItem -Path $Folder -Recurse -Include "*.dll","*.exe","*.sys" -ErrorAction SilentlyContinue |
            ForEach-Object {
                # PendingFileRenameOperations uses \??\ kernel path prefix
                # and pairs: source path, empty string = delete on reboot
                $KernelPath = "\??\" + $_.FullName
                $Entries.Add($KernelPath)
                $Entries.Add("")
                $Scheduled++
                Write-Log "  Queued for deletion: $($_.FullName)"
            }
    }

    if ($Scheduled -eq 0) {
        Write-Log "  No files found to schedule."
        return
    }

    # Write the combined list back -- this is a REG_MULTI_SZ value
    Set-ItemProperty `
        -Path $SessionManagerKey `
        -Name "PendingFileRenameOperations" `
        -Value $Entries.ToArray() `
        -Type MultiString

    Write-Log "  Total files queued for deletion on next boot: $Scheduled"
}

function Register-Phase2StartupTask {
    # Runs once as SYSTEM on next boot, hidden, removes itself when done
    Write-Log "Registering one-time Phase 2 startup task..."

    $MyPath = $PSCommandPath
    if ($MyPath -and (Test-Path $MyPath) -and $MyPath -ne $Phase2Script) {
        Copy-Item -Path $MyPath -Destination $Phase2Script -Force
        Write-Log "  Script copied to: $Phase2Script"
    }
    elseif (-not (Test-Path $Phase2Script)) {
        Write-Log "  WARNING: Could not locate script to copy. Task will use: $Phase2Script"
        Write-Log "  Make sure the script exists at that path before rebooting."
    }

    $Action    = New-ScheduledTaskAction `
                    -Execute "powershell.exe" `
                    -Argument "-NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Phase2Script`""

    $Trigger   = New-ScheduledTaskTrigger -AtStartup

    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

    $Settings  = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
                    -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName "McAfeeWPSPhase2Cleanup" `
        -TaskPath "\" `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null

    Write-Log "Phase 2 startup task registered. Runs once on next boot then removes itself."
}

function Set-Phase2Flag {
    if (-not (Test-Path $RebootFlagKey)) {
        New-Item -Path $RebootFlagKey -Force | Out-Null
    }
    Set-ItemProperty -Path $RebootFlagKey -Name $RebootFlagName -Value 1 -Type DWord
    Write-Log "Phase 2 flag set at: $RebootFlagKey\$RebootFlagName"
}

function Clear-Phase2Flag {
    if (Test-Path $RebootFlagKey) {
        Remove-ItemProperty -Path $RebootFlagKey -Name $RebootFlagName -ErrorAction SilentlyContinue
    }
    Write-Log "Phase 2 flag cleared."
}

function Test-Phase2Pending {
    $Val = Get-ItemProperty -Path $RebootFlagKey -Name $RebootFlagName -ErrorAction SilentlyContinue
    return ($Val -and $Val.$RebootFlagName -eq 1)
}

function Remove-McAfeeFolders {
    Write-Log "Removing McAfee installation folders..."

    # Also catch the renamed folder from a previous partial run
    $AllFolders = $McAfeeFolders + @(
        "$env:ProgramFiles\McAfee_REMOVE_20260715",
        "$env:ProgramFiles\McAfee_REMOVE_$(Get-Date -Format 'yyyyMMdd')"
    ) | Select-Object -Unique

    foreach ($Folder in $AllFolders) {
        if (-not (Test-Path $Folder)) {
            Write-Log "  Already gone: $Folder"
            continue
        }

        # Take ownership before attempting removal
        Write-Log "  Taking ownership of: $Folder"
        takeown.exe /F $Folder /R /A /D Y 2>&1 | Out-Null
        icacls.exe $Folder /grant "SYSTEM:(OI)(CI)F" /T /Q 2>&1 | Out-Null

        Write-Log "  Removing: $Folder"
        try {
            Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
            Write-Log "  Removed."
        }
        catch {
            # If still locked, rename it out of the way
            $Renamed = "$Folder`_REMOVE_$(Get-Date -Format 'yyyyMMdd')"
            Write-Log "  Still locked -- renaming to: $Renamed"
            try {
                Rename-Item -Path $Folder -NewName $Renamed -Force -ErrorAction Stop
                Write-Log "  Renamed successfully."
            }
            catch {
                Write-Log "  Rename also failed: $($_.Exception.Message)"
            }
        }
    }
}

function Write-ValidationSummary {
    Write-Log "===== Validation Summary ====="

    $Win32 = Get-ItemProperty `
        HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
        HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $UninstallPattern }

    $Appx  = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "mcafee" }

    $Svcs  = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "McAfee|McAfeeFramework|mfefire|masvc|mc-fw|mc-wps|mc-neo|mc-update|mc-inst" }

    $Procs = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match "^(McAfee|mfe|masvc|mcshield|mcuicnt|mcsplashtool|mcapexe|mc-fw-host|mc-neo-host|mc-update|mc-inst-uihost)$" }

    $FolderRemains = $McAfeeFolders | Where-Object { Test-Path $_ }

    Write-Log "Win32 uninstall entries: $($Win32.Count)"
    Write-Log "AppX packages:           $($Appx.Count)"
    Write-Log "Services:                $(@($Svcs).Count)"
    Write-Log "Processes:               $($Procs.Count)"
    Write-Log "Folders remaining:       $($FolderRemains.Count)"

    $Win32          | ForEach-Object { Write-Log "  [Win32]   $($_.DisplayName) $($_.DisplayVersion)" }
    $Appx           | ForEach-Object { Write-Log "  [AppX]    $($_.Name)" }
    $Svcs           | ForEach-Object { Write-Log "  [Service] $($_.Name) ($($_.Status))" }
    $Procs          | ForEach-Object { Write-Log "  [Process] $($_.ProcessName) (PID $($_.Id))" }
    $FolderRemains  | ForEach-Object { Write-Log "  [Folder]  $_" }

    return ($Win32.Count -eq 0 -and $Appx.Count -eq 0 -and
            @($Svcs).Count -eq 0 -and $Procs.Count -eq 0 -and
            $FolderRemains.Count -eq 0)
}

#endregion

#region --- Phase 1 ---

function Invoke-Phase1 {
    Write-Log "===== McAfee WPS Removal - Phase 1 ====="
    Write-Log "No reboot will be triggered. Reboot manually when ready."

    Stop-WpsProcesses
    Stop-WpsServices
    Remove-WpsScheduledTasks
    Remove-WpsServiceRegistryKeys
    Remove-WpsUninstallKeys
    Remove-AppxPackages
    Schedule-LockedFilesForDeletion
    Set-Phase2Flag
    Register-Phase2StartupTask

    Write-Log "===== Phase 1 Complete ====="
    Write-Log "Machine is ready to reboot at your convenience."
    Write-Log "Phase 2 will run automatically on next startup."
    Write-Log "Log file: $LogFile"

    exit 0
}

#endregion

#region --- Phase 2 ---

function Invoke-Phase2 {
    Write-Log "===== McAfee WPS Removal - Phase 2 (Post-Reboot) ====="

    # Let boot settle before touching anything
    Start-Sleep -Seconds 20

    Stop-WpsProcesses
    Stop-WpsServices
    Remove-WpsServiceRegistryKeys
    Remove-WpsUninstallKeys
    Remove-McAfeeFolders

    # Remove the task before validation so it's guaranteed gone
    Unregister-ScheduledTask -TaskName "McAfeeWPSPhase2Cleanup" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Phase 2 scheduled task removed."

    Clear-Phase2Flag

    $Clean = Write-ValidationSummary

    if ($Clean) {
        Write-Log "McAfee WPS removal completed successfully."
        exit 0
    }

    Write-Log "Some components remain. Check log for details: $LogFile"
    exit 1
}

#endregion

#region --- Entry point ---

$CurrentPrincipal = New-Object System.Security.Principal.WindowsPrincipal(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $CurrentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Script must run as administrator."
    exit 1
}

if (Test-Phase2Pending) {
    Invoke-Phase2
}
else {
    Invoke-Phase1
}

#endregion