# Amanda Hunt - 9/18/2025

# Pulls the org custom field workstationTargetVersion 
# Reads the registry TargetReleaseVersionInfo on the device
# If the org custom field doesn’t exist, exit 0
# If it exists and matches the registry value, exit 0
#  If it exists but does not match, output a message and exit 1

# exit 0 - condition ends
# exit 1 - condition is matched

$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$RegistryName = 'TargetReleaseVersionInfo'

# Try getting the custom field
$orgTarget = $null
try {
    $orgTarget = Ninja-Property-Get workstationTargetVersion 2>$null
} catch {
    # If command fails (e.g. field not found or permissions), treat as non-existent
    $orgTarget = $null
}

if ([string]::IsNullOrWhiteSpace($orgTarget)) {
    # Org custom field not populated - exit 0 
    Write-Host "org custom target not entered. exiting 0"
    exit 0
}

# Get the device's registry value
$deviceTarget = $null
if (Test-Path $RegistryPath) {
    $deviceTarget = Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $RegistryName
}

if ([string]::IsNullOrWhiteSpace($deviceTarget)) {
    # Registry value missing => mismatch because org has a target version
    Write-Host "Device TargetReleaseVersionInfo is missing; Org target version is '$orgTarget'"
    exit 1
}

# Compare
if ($deviceTarget -eq $orgTarget) {
    # Match - exit 0
    Write-Host "Targeted versions match."
    exit 0
} else {
    # Mismatch - exit 1 so condition triggers
    Write-Host "Device target version '$deviceTarget' does not match Org target version '$orgTarget'"
    exit 1
}