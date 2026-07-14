param (
    [string]$variable1 = ''
)

# Define possible installation paths
$possiblePaths = @(
    "C:\Program Files\Tenable\Nessus Agent\nessus-service.exe",
    "C:\Program Files (x86)\Tenable\Nessus Agent\nessus-service.exe"
)

# Find the first path that exists
$nessusCli = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($nessusCli) {
    Write-Output "Nessus Agent already installed at $(Split-Path $nessusCli). Skipping installation."
} else {
    Write-Output "Nessus Agent not found. Installing..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://sensor.cloud.tenable.com/install/agent/installer/ms-install-script.ps1" -OutFile "./ms-install-script.ps1"
    & "./ms-install-script.ps1" -key $variable1 -type "agent" -groups 'Agents'
    Remove-Item -Path "./ms-install-script.ps1"

    # Update CLI path after install
    $nessusCli = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($nessusCli) {
    & $nessusCli fix --set update_hostname=yes
    Write-Output "Nessus hostname update command executed."
    net stop "Tenable Nessus Agent"
    net start "Tenable Nessus Agent"
} else {
    Write-Output "Nessus CLI not found after installation attempt."
    exit 1
}
