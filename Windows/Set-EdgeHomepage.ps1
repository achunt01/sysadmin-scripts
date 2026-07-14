param (
    [string]$HomeButtonPage = "https://www.google.com/"
)

# Define the registry paths
$regPaths = @(
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Edge\Main",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Edge\Customization",
    "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main"
)

# Define the registry values for each path
$regValues = @{
    "HomeButtonEnabled" = 1
    "HomeButtonPage"    = $HomeButtonPage
    "NewTabPageLocation" = $HomeButtonPage
    "StartupPage"       = $HomeButtonPage
}

# Create the registry paths if they don't exist and set the values
foreach ($regPath in $regPaths) {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | OuAdd the following widgets
Vulnerability Priority Rating (VPR)
Vulnerability Aging: Managing SLAs
CVSS to VPR Heat Map
Outstanding Remediations - Time since Patch Publication
Outstanding Microsoft Remediations - Time since Patch Publication
Top Exploitable Windows Hostst-Null
    }

    foreach ($name in $regValues.Keys) {
        Set-ItemProperty -Path $regPath -Name $name -Value $regValues[$name]
    }
}

Write-Host "Registry keys and values for Edge have been added successfully."


