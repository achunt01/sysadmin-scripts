<#
.SYNOPSIS
    Quick read-only inventory of everything McAfee left on a machine.

.DESCRIPTION
    Lists McAfee uninstall entries (32- and 64-bit), AppX packages, services,
    running processes, and the usual install folders. Nothing is changed — this is
    the "what's actually here" check I run before and after a removal.

.NOTES
    Author: Amanda Hunt
    Pairs with Get-McAfeeRegistryRemnants.ps1 and Remove-McAfeeWPSCompletely.ps1.
#>

# Win32 uninstall keys
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "McAfee" } | Select-Object DisplayName, DisplayVersion, UninstallString

# AppX packages
Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "mcafee" } | Select-Object Name, Version

# Services
Get-Service | Where-Object { $_.Name -match "mcafee|mfe|masvc|mc-fw|mc-wps" } | Select-Object Name, DisplayName, Status

# Processes
Get-Process | Where-Object { $_.ProcessName -match "mcafee|mfe|masvc|mcshield" } | Select-Object Name, Id

# Folders
"$env:ProgramFiles\McAfee","$env:ProgramFiles\Common Files\McAfee","$env:ProgramData\McAfee" | ForEach-Object { if (Test-Path $_) { "EXISTS: $_" } else { "Gone: $_" } }