# ================================
# CONFIG
# ================================
$GpoName = "Approved Applications - Firewall"

# ================================
# CHECK FOR EXISTING GPO
# ================================
Import-Module GroupPolicy

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if (-not $gpo) {
    Write-Host "GPO '$GpoName' not found. Creating it..."
    $gpo = New-GPO -Name $GpoName -Comment "WFAS Firewall rules for approved applications"
    Write-Host "GPO '$GpoName' created successfully."
} else {
    Write-Host "GPO '$GpoName' already exists. Using existing GPO."
}

# ================================
# PROMPTS
# ================================

# Ask for rule name
$RuleName = Read-Host "Enter the firewall rule name"

# Ask for program path
$ProgramPath = Read-Host "Enter the full program path (e.g. C:\Program Files\App\App.exe)"

# Ask for direction (default = Inbound)
$Direction = Read-Host "Direction? (Inbound/Outbound) [Default: Inbound]"
if ([string]::IsNullOrWhiteSpace($Direction)) {
    $Direction = "Inbound"
}

# Confirm Domain-only profile (default = Yes)
$DomainOnly = Read-Host "Apply to DOMAIN profile only? (Y/n) [Default: Y]"
if ([string]::IsNullOrWhiteSpace($DomainOnly) -or $DomainOnly -eq "Y" -or $DomainOnly -eq "y") {
    $Profile = "Domain"
} else {
    # If not domain-only, allow user to specify the profile set
    $Profile = Read-Host "Enter profile name(s) (Domain, Private, Public, Any)"
}

# ================================
# BUILD POLICY STORE
# ================================
$domain = (Get-ADDomain).DNSRoot
$PolicyStorePath = "$domain\$GpoName"

Write-Host "`nAdding rule to GPO: $GpoName"
Write-Host "Rule: $RuleName"
Write-Host "Program: $ProgramPath"
Write-Host "Direction: $Direction"
Write-Host "Profile: $Profile"
Write-Host "Policy Store: $PolicyStorePath"
Write-Host ""

# ================================
# CREATE WFAS FIREWALL RULE
# ================================
New-NetFirewallRule `
    -DisplayName $RuleName `
    -Program $ProgramPath `
    -Direction $Direction `
    -Action Allow `
    -Enabled True `
    -Profile $Profile `
    -PolicyStore $PolicyStorePath

Write-Host "`n✅ Firewall rule '$RuleName' added to GPO '$GpoName' successfully."