<#
.SYNOPSIS
    Installs winget (App Installer) if it's missing, otherwise upgrades it.

.DESCRIPTION
    Checks whether winget is available. If not, it bootstraps the install via the
    winget-install script from PSGallery (machine needs a restart afterward). If winget
    is already present, it just upgrades App Installer to the latest version.

.NOTES
    Author: Amanda Hunt
    Run elevated.
#>

#if winget is not installed, install winget:
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Winget not found. Installing winget..." -ForegroundColor Yellow

    #install winget
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    Install-Script -Name winget-install -Force 
    & "C:\Program Files\WindowsPowerShell\Scripts\winget-install.ps1" -Force 
    Write-Host "Winget installed. Restart machine" -ForegroundColor Yellow


    exit 0
}


# if installed, update winget:
Write-Host "Checking App Installer (winget) updates..." -ForegroundColor Cyan

winget upgrade --id Microsoft.AppInstaller `
    --source winget `
    --accept-source-agreements `
    --accept-package-agreements `
    --silent `
    --disable-interactivity