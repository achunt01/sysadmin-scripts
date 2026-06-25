<#
.SYNOPSIS
    Adds a Windows Firewall application allow rule to a Group Policy Object.

.DESCRIPTION
    Creates or reuses a named GPO and adds a WFAS firewall allow rule for a
    specified application path. Prompts for rule name, program path, direction,
    and network profile. Useful for standardizing approved application firewall
    rules across a domain without touching local firewall policy directly.

    Requires the GroupPolicy and ActiveDirectory modules (RSAT).

.EXAMPLE
    .\Add-GPOFirewallRule.ps1

    Runs interactively. Creates the GPO if it doesn't exist, then prompts
    for rule details.

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : Windows Server 2019/2022 with RSAT installed

    Requirements:
      - Run as a user with GPO edit rights in the domain
      - GroupPolicy module (RSAT: Group Policy Management Tools)
      - ActiveDirectory module (RSAT: AD DS Tools)

    The GPO must be linked to an OU separately after creation.
#>

# ============================================================
# CONFIG — change this if you want a different target GPO name
# ============================================================

$GpoName = "Approved Applications - Firewall"

# ============================================================
# MODULE CHECK — fail early if RSAT isn't present
# ============================================================

foreach ($module in @('GroupPolicy', 'ActiveDirectory')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Required module '$module' is not available. Install RSAT and try again." -ForegroundColor Red
        return
    }
}

Import-Module GroupPolicy
Import-Module ActiveDirectory

# ============================================================
# GPO — create it if it doesn't exist, reuse it if it does
# ============================================================

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if (-not $gpo) {
    Write-Host "`nGPO '$GpoName' not found. Creating it..." -ForegroundColor Cyan
    $gpo = New-GPO -Name $GpoName -Comment "WFAS firewall rules for approved applications"
    Write-Host "GPO '$GpoName' created. Remember to link it to the appropriate OU." -ForegroundColor Yellow
}
else {
    Write-Host "`nGPO '$GpoName' already exists. Adding rule to existing GPO." -ForegroundColor Cyan
}

# ============================================================
# PROMPTS
# ============================================================

$RuleName = Read-Host "`nFirewall rule name"

$ProgramPath = Read-Host "Full program path (e.g. C:\Program Files\App\App.exe)"

# Validate the path looks reasonable — won't catch everything but
# catches obvious mistakes like a missing .exe extension.
if ($ProgramPath -notmatch '\.exe$') {
    Write-Host "  Path doesn't end in .exe — double check this before deploying." -ForegroundColor Yellow
}

$Direction = Read-Host "Direction (Inbound/Outbound) [Default: Inbound]"
if ([string]::IsNullOrWhiteSpace($Direction)) {
    $Direction = "Inbound"
}

# Normalize capitalization so New-NetFirewallRule doesn't complain.
$Direction = (Get-Culture).TextInfo.ToTitleCase($Direction.ToLower())

$DomainOnly = Read-Host "Apply to Domain profile only? (Y/n) [Default: Y]"
if ([string]::IsNullOrWhiteSpace($DomainOnly) -or $DomainOnly -match '^[Yy]$') {
    $Profile = "Domain"
}
else {
    $Profile = Read-Host "Profile(s) to apply (Domain, Private, Public, Any)"
}

# ============================================================
# SUMMARY — confirm before writing anything
# ============================================================

Write-Host "`n--- Rule Summary ---" -ForegroundColor Cyan
Write-Host "GPO       : $GpoName"
Write-Host "Rule name : $RuleName"
Write-Host "Program   : $ProgramPath"
Write-Host "Direction : $Direction"
Write-Host "Profile   : $Profile"
Write-Host "--------------------`n"

$confirm = Read-Host "Proceed? (Y/n) [Default: Y]"
if (-not [string]::IsNullOrWhiteSpace($confirm) -and $confirm -notmatch '^[Yy]$') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    return
}

# ============================================================
# CREATE THE RULE
# ============================================================

$domain = (Get-ADDomain).DNSRoot
$PolicyStorePath = "$domain\$GpoName"

try {
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Program $ProgramPath `
        -Direction $Direction `
        -Action Allow `
        -Enabled True `
        -Profile $Profile `
        -PolicyStore $PolicyStorePath `
        -ErrorAction Stop

    Write-Host "Firewall rule '$RuleName' added to GPO '$GpoName' successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to create firewall rule: $_" -ForegroundColor Red
}
