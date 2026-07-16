<#
.SYNOPSIS
    Software inventory from the registry, with optional name filter and CSV export.

.DESCRIPTION
    Reads the uninstall keys (64-bit, 32-bit, and current user) and returns name,
    version, publisher, install date, and the uninstall string. Deliberately avoids
    Win32_Product, which makes Windows Installer re-validate every MSI on the box --
    slow at best, self-repair roulette at worst.

.PARAMETER Name
    Optional wildcard filter, e.g. -Name "*zoom*".

.PARAMETER CsvPath
    Optional path to export the results as CSV.

.EXAMPLE
    .\Get-InstalledSoftware.ps1 -Name "*chrome*"

.NOTES
    Author: Amanda Hunt
    Read-only.
#>
param (
    [string]$Name = "*",
    [string]$CsvPath = ""
)

$hives = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# entries without a DisplayName are updates/components - not interesting here
$apps = Get-ItemProperty $hives -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.DisplayName -like $Name } |
    Sort-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString

$apps | Format-Table DisplayName, DisplayVersion, Publisher, InstallDate -AutoSize

Write-Host "$(@($apps).Count) application(s) found."

if ($CsvPath) {
    $apps | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "Exported to $CsvPath"
}
