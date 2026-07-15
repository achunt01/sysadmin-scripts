<#
.SYNOPSIS
    Installs the SentinelOne (S1) agent by pulling the package from the S1 API.

.DESCRIPTION
    Authenticates to the SentinelOne management console with a server hostname and
    API token, downloads the matching agent installer, and installs it against the
    supplied site token. Built to run unattended from an RMM as SYSTEM.

    Fill in $Server and $ApiToken before use, and pass the site token via -siteToken.

.PARAMETER siteToken
    The SentinelOne site token the agent should register against.

.NOTES
    Author: Amanda Hunt
    Run elevated. Keep the API token out of source control.
#>
param (
    [string]$siteToken=''
)

# Set the hostname of your server here.
$Server = ""

# Set your API Token here
$ApiToken = ""

#############################
#region RMMTemplate

$Global:nl = [System.Environment]::NewLine
$Global:ErrorCount = 0
$global:Output = '' 

#######

#######
function RMM-Msg {
    param ($Message)
    $global:Output += " $Message"+$Global:nl
}

#######
function RMM-Error {
    param ($Message)
    $Global:ErrorCount += 1
    $global:Output += "!$Message"+$Global:nl
}

#######
function RMM-Exit {  
    $Message = '----------'+$Global:nl+"ErrorCount : $Global:ErrorCount"
    $global:Output += $Message
    Ninja-Property-Set antivirusInstallationOutput $global:Output
    Write-Host -Object "$global:Output"
    Exit(0)
}

#endregion 
############################# 

# Force TLS 1.2. Not always necessary but Windows Version below 1903 will default to TLS 1.1 or worse and fail.
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Set headers
$headers = @{
    'Authorization'= "ApiToken $ApiToken"
    'Content-Type'= "application/json"
}

function Get-TimeStamp() {
    return Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
}

if (($null -eq $siteToken) -or ($siteToken.Length -eq 0)) {
    RMM-Error "$(Get-Timestamp) SentinelOne Site Token is empty in your documentation"
    RMM-Exit
}

if (($null -eq $ApiToken) -or ($ApiToken.Length -eq 0)) {
    RMM-Error "$(Get-Timestamp) SentinelOne API Token is empty in your documentation"
    RMM-Exit
}

if (($null -eq $Server) -or ($Server.Length -eq 0)) {
    RMM-Error "$(Get-Timestamp) Server parameter is not specified"
    RMM-Exit
}

# Check if software is installed. If key is present, terminate script
RMM-Msg "$(Get-Timestamp) Checking if SentinelOne is installed..."

$path= (get-childitem 'C:\Program Files\SentinelOne\' -ErrorAction SilentlyContinue).fullname + "\SentinelAgent.exe"
$architecture = if ([System.IntPtr]::Size -eq 8) { "64 bit" } else { "32 bit" }
$Apps = @($RegKeys | Get-ChildItem | Get-ItemProperty | Where-Object { $_.DisplayName -like "*Sentinel*" })

if (test-path $path)
{
    RMM-Error "$(Get-Timestamp) SentinelOne is already installed"
    RMM-Exit
}

# Download
RMM-Msg "$(Get-Timestamp) SentinelOne is not installed"

# Force TLS 1.2. Not always necessary but Windows Version below 1903 will default to TLS 1.1 or worse and fail.
RMM-Msg "$(Get-Timestamp) Forcing TLS 1.2"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  
# Get the details on the latest General Availability MSI installer available from your Sentinel One server instance.
try {
    # NOTE: sortBy=majorVersion + limit=1 is not safe here. S1's "majorVersion" is just the
    # leading number (e.g. "25"), so 25.1.x and 25.2.x tie on that field and the API's
    # tiebreak isn't guaranteed to hand back the newest one. Pulling osArches server-side
    # and grabbing a batch (limit=50) instead of trusting limit=1 fixes that.
    $uri = "https://" + $Server + ".sentinelone.net/web/api/v2.1/update/agent/packages?fileExtension=.msi&osTypes=windows&osArches=$architecture&status=ga&limit=50"
    $response = Invoke-RestMethod -Uri $uri -Method 'GET' -Headers $headers

    # Don't trust the API's ordering for this, sort on the real version string ourselves
    # and just take whatever comes out on top.
    $payload = $response.data | Where-Object { $_.osArch -eq "$architecture" } | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1
} catch {
    RMM-Error "$(Get-Timestamp) S1 Error; Unable to complete the API call."
    RMM-Error $_
    RMM-Exit
}

if (-not $payload) {
    RMM-Error "$(Get-Timestamp) S1 Error; No GA package matched osArch '$architecture'. Check the osArches value the API expects."
    RMM-Exit
}

# Set the filename and location for the downloaded installer
$file = "C:\windows\temp\SentinelAgent_windows.msi"

# Download the latest MSI Installer.
RMM-Msg "$(Get-Timestamp) Downloading last available SentinelOne package ($($payload.version))..."
try {
    Invoke-WebRequest -Uri $payload.link -Outfile $file -Headers $headers -UseBasicParsing
} Catch {
    RMM-Error "$(Get-Timestamp) S1 Error; Unable to download the installer."
    RMM-Error $_
    RMM-Exit
}
RMM-Msg "$(Get-Timestamp) Downloaded"

# Silently install the agent and set the site token. No restart.
if ($file) {
    RMM-Msg "$(Get-Timestamp) Starting the installation of SentinelOne..."
    Start-Process msiexec.exe -Wait -ArgumentList "/i $file SITE_TOKEN=$siteToken /q /norestart"
    
    RMM-Msg "$(Get-Timestamp) Installed"
    
    RMM-Exit
} else {
    RMM-Error "$(Get-Timestamp) Could not find $file; Did it fail to download?"
    RMM-Exit
}
