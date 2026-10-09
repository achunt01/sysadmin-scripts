<#
.SYNOPSIS
    Pulls license information for every connected firewall managed by
    Panorama and writes the aggregate to NinjaOne custom fields.

.DESCRIPTION
    Gets the managed device list from Panorama, then queries each connected
    firewall's licenses through Panorama's API proxy (target=<serial>), so
    only Panorama's IP and API key are needed - no per-firewall credentials.

    Sets two Ninja custom fields:
      - firewallLicenseExpiration  (string: per-firewall, per-feature detail)
      - firewallLicenseExpiringSoon (integer: soonest expiration across all
        firewalls, for alerting)

    Fill in $panoramaIP and $apiKey before running.

.NOTES
    Author: Amanda Hunt
#>

# Edit these
$panoramaIP = ""
$apiKey = ""

# -----------------------------------------------
# Step 1: Pull the list of managed firewalls from Panorama
# -----------------------------------------------
$deviceListCmd = "<show><devices><all></all></devices></show>"
$encodedDeviceCmd = [uri]::EscapeDataString($deviceListCmd)
$deviceListUrl = "https://$panoramaIP/api/?type=op&cmd=$encodedDeviceCmd&key=$apiKey"

$deviceListOutput = & curl.exe -s -k $deviceListUrl
[xml]$deviceListXml = $deviceListOutput

# Grab all connected devices - each has a serial and hostname
$devices = $deviceListXml.response.result.devices.entry

# We'll collect everything across all firewalls here
$allFirewallInfo = ""
$globalMinExpiration = [int]::MaxValue

# -----------------------------------------------
# Step 2: Loop each firewall and query its licenses via Panorama proxy
# -----------------------------------------------
foreach ($device in $devices) {
    $serial = $device.serial
    $hostname = $device.hostname

    # Skip devices that show as disconnected - no point querying them
    $connected = $device.connected
    if ($connected -ne "yes") {
        Write-Host "Skipping $hostname ($serial) - not connected"
        continue
    }

    # Panorama proxies API calls to managed devices using the 'target' param
    # This means you only need Panorama's IP and key - no individual FW creds needed
    $licenseCmd = "<request><license><info></info></license></request>"
    $encodedLicenseCmd = [uri]::EscapeDataString($licenseCmd)
    $licenseUrl = "https://$panoramaIP/api/?type=op&cmd=$encodedLicenseCmd&key=$apiKey&target=$serial"

    $licenseOutput = & curl.exe -s -k $licenseUrl
    [xml]$licenseXml = $licenseOutput

    $entries = $licenseXml.response.result.licenses.entry

    # If a firewall returns no license entries, note it and move on
    if (-not $entries) {
        $allFirewallInfo += "[$hostname ($serial)] No license data returned`n`n"
        continue
    }

    $today = Get-Date
    $firewallBlock = "=== $hostname ($serial) ===`n"

    foreach ($entry in $entries) {
        # Some licenses say "Never" for expiration - handle that so ParseExact doesn't choke
        if ($entry.expires -eq "Never") {
            $firewallBlock += "$($entry.feature) | Expires On: Never | Expired?: $($entry.expired) | Days Until Expiration: N/A`n"
            continue
        }

        $expiresDate = [datetime]::ParseExact($entry.expires, 'MMMM dd, yyyy', $null)
        $daysUntilExpiration = [math]::Round(($expiresDate - $today).TotalDays)

        $firewallBlock += "$($entry.feature) | Expires On: $($entry.expires) | Expired?: $($entry.expired) | Days Until Expiration: $daysUntilExpiration`n"

        # Track the global soonest expiration across ALL firewalls
        if ($daysUntilExpiration -lt $globalMinExpiration -and $daysUntilExpiration -gt -365) {
            $globalMinExpiration = $daysUntilExpiration
        }
    }

    $allFirewallInfo += $firewallBlock + "`n"
}

# -----------------------------------------------
# Step 3: Push to Ninja just like before
# -----------------------------------------------
Ninja-Property-Set firewallLicenseExpiration $allFirewallInfo

if ($globalMinExpiration -ne [int]::MaxValue) {
    Ninja-Property-Set firewallLicenseExpiringSoon $globalMinExpiration
}
