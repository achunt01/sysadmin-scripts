param (
    [string]$url = ""
)

# Paths for Chrome policy keys used in the scripts
$policyexists = Test-Path HKLM:\SOFTWARE\Policies\Google\Chrome
$policyexistshome = Test-Path HKLM:\SOFTWARE\Policies\Google\Chrome\RestoreOnStartupURLs
$regKeysetup = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$regKeyhome = "HKLM:\SOFTWARE\Policies\Google\Chrome\RestoreOnStartupURLs"

# Setup policy directories in registry if needed and set pwd manager
# Else sets them to the correct values if they exist
if ($policyexists -eq $false) {
    New-Item -path HKLM:\SOFTWARE\Policies\Google -Force
    New-Item -path HKLM:\SOFTWARE\Policies\Google\Chrome -Force
    New-ItemProperty -path $regKeysetup -Name RestoreOnStartup -PropertyType Dword -Value 4
    New-ItemProperty -path $regKeysetup -Name HomepageLocation -PropertyType String -Value $url
    New-ItemProperty -path $regKeysetup -Name HomepageIsNewTabPage -PropertyType DWord -Value 0
} else {
    Set-ItemProperty -Path $regKeysetup -Name RestoreOnStartup -Value 4
    Set-ItemProperty -Path $regKeysetup -Name HomepageLocation -Value $url
    Set-ItemProperty -Path $regKeysetup -Name HomepageIsNewTabPage -Value 0
}

# This entry requires a subfolder in the registry
# For more than one page create another New-Item and Set-Item line with the name -2 and the new URL
if ($policyexistshome -eq $false) {
    New-Item -path HKLM:\SOFTWARE\Policies\Google\Chrome\RestoreOnStartupURLs -Force
    New-ItemProperty -path $regKey\\DDC1912\Users\sfadmin\Downloadshome -Name 1 -PropertyType String -Value $url
} else {
    Set-ItemProperty -Path $regKeyhome -Name 1 -Value $url
}
