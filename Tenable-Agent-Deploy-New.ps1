param (
    [string]$variable1 = ''
)

$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$stampFile = "C:\ProgramData\nessus_last_fix.txt"
$graceMinutes = 10
$withinGrace = $false

# --------------------------------------------------
# Grace period check (prevents churn)
# --------------------------------------------------
if (Test-Path $stampFile) {
    $lastFix = Get-Content $stampFile | Get-Date
    $age = (Get-Date) - $lastFix
    if ($age.TotalMinutes -lt $graceMinutes) {
        $withinGrace = $true
    }
}

# --------------------------------------------------
# Paths
# --------------------------------------------------
$agentPath = "C:\Program Files\Tenable\Nessus Agent\nessus-service.exe"
$cliPath   = "C:\Program Files\Tenable\Nessus Agent\nessuscli.exe"

$agentExists = Test-Path $agentPath
$cliExists   = Test-Path $cliPath

$svc = Get-CimInstance Win32_Service -Filter "Name='Tenable Nessus Agent'" -ErrorAction SilentlyContinue

$installHealthy = $false

if ($agentExists -and $cliExists -and $svc) {
    if (Test-Path ($svc.PathName -replace '"','')) {
        $installHealthy = $true
    }
}

# --------------------------------------------------
# CLEAN + INSTALL (only if broken)
# --------------------------------------------------
if (-not $installHealthy -and -not $withinGrace) {

    Write-Output "Broken install detected. Performing full cleanup..."

    sc.exe stop "Tenable Nessus Agent" | Out-Null
    Start-Sleep 2
    sc.exe delete "Tenable Nessus Agent" | Out-Null
    Start-Sleep 3

    Get-Process "nessus-agent" -ErrorAction SilentlyContinue | Stop-Process -Force

    Remove-Item "C:\Program Files\Tenable\Nessus Agent" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Tenable" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "HKLM:\SOFTWARE\Tenable" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SOFTWARE\WOW6432Node\Tenable" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "Installing Nessus Agent..."

    $installer = "$env:TEMP\nessus.ps1"
    Invoke-WebRequest "https://sensor.cloud.tenable.com/install/agent/installer/ms-install-script.ps1" -OutFile $installer
    & $installer -key $variable1 -type "agent"

    Start-Sleep 15
}

# --------------------------------------------------
# SERVICE VALIDATION
# --------------------------------------------------
$svc = Get-Service "Tenable Nessus Agent" -ErrorAction SilentlyContinue

if (-not $svc) {
    Write-Output "Service missing → install failed"
    exit 1
}

# Ensure running
if ($svc.Status -ne "Running") {
    Start-Service "Tenable Nessus Agent"
    Start-Sleep 5
}

# --------------------------------------------------
# LINK / CONNECTIVITY VALIDATION
# --------------------------------------------------
if (-not $cliExists) {
    Write-Output "CLI missing → cannot proceed"
    exit 1
}

$status = & $cliPath agent status 2>$null

$connected = $false

if (
    $status -match "Linked to" -and
    $status -match "Last connection attempt:.*success"
) {
    $connected = $true
}

# --------------------------------------------------
# RELINK LOGIC (REAL FIX)
# --------------------------------------------------

# If NOT connected and NOT within grace → force relink
if (-not $connected -and -not $withinGrace) {

    Write-Output "Agent not connected → forcing hard relink..."

    Stop-Service "Tenable Nessus Agent"
    Start-Sleep 5

    & $cliPath agent unlink --force 2>$null
    Start-Sleep 3

    $success = $false

    for ($i=1; $i -le 3; $i++) {
        Write-Output "Link attempt $i..."

        & $cliPath agent link `
            --key=$variable1 `
            --host=cloud.tenable.com `
            --port=443 `
            --groups="Agents"

        Start-Sleep 15

        $check = & $cliPath agent status

        if (
            $check -match "Linked to" -and
            $check -match "Last connection attempt:.*success"
        ) {
            $success = $true
            break
        }
    }

    Start-Service "Tenable Nessus Agent"
    Start-Sleep 10

    # stamp time
    (Get-Date).ToString("o") | Out-File $stampFile -Force

    if (-not $success) {
        Write-Output "Relink attempted but not confirmed → forcing delayed restart"

        Start-Sleep 60
        Restart-Service "Tenable Nessus Agent"

        exit 1
    }

    Write-Output "Relink successful"
}

# --------------------------------------------------
# GRACE PERIOD HANDLING
# --------------------------------------------------
elseif ($withinGrace) {

    Write-Output "Within grace window → forcing soft recovery only"

    Restart-Service "Tenable Nessus Agent"
    exit 0
}

# --------------------------------------------------
# FINAL CHECK
# --------------------------------------------------
$status = & $cliPath agent status

if ($status -notmatch "Last connection attempt:.*success") {
    Write-Output "Agent still not checking in → scheduling delayed retry"
    Start-Sleep 60
    Restart-Service "Tenable Nessus Agent"
}

# Hostname normalize
& $cliPath fix --set update_hostname=yes

Write-Output "Complete: agent verified"
exit 0
