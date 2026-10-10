<#
.SYNOPSIS
    Pulls license expirations from a single Palo Alto firewall.

.DESCRIPTION
    Hits one firewall's XML API directly for its license info, then writes every
    license with its expiration date and days remaining to the
    firewallLicenseExpiration NinjaOne custom field, and the soonest expiration
    (in days) to firewallLicenseExpiringSoon for alerting.
    For a fleet behind Panorama, use Get-PanoramaLicenseExpiration.ps1 instead.

.NOTES
    Author: Amanda Hunt
    Fill in $firewallIP and $apiKey before running - don't commit the real key.
    curl -k skips cert validation, since the firewall usually has a self-signed cert.
#>

# Edit these
$firewallIP = "y"
$apiKey = "x=="

# Define the XML command string to request license information from the firewall API
$xmlCmd = "<request><license><info></info></license></request>"

# URL-encode the XML command to safely include it in the API request URL
$encodedCmd = [uri]::EscapeDataString($xmlCmd)

# Construct the full API request URL with the firewall IP, encoded command, and API key
$url = "https://$firewallIP/api/?type=op&cmd=$encodedCmd&key=$apiKey"

# Execute the curl command to send the request to the firewall API and capture the output
$curlOutput = & curl.exe -k $url

# Parse the XML response string into an XML object for easy navigation
[xml]$responseXml = $curlOutput

# Extract the entry elements containing license info from the response
$entries = $responseXml.response.result.licenses.entry

$today = Get-Date
$licenseInfo = ""
$allExpirations = @()

# Loop through each license entry in the response
foreach ($entry in $entries) {
    # Parse license expiration date string into a DateTime object
    $expiresDate = [datetime]::ParseExact($entry.expires, 'MMMM dd, yyyy', $null)

    # Round the total days instead of truncating to whole number
    $daysUntilExpiration = [math]::Round(($expiresDate - $today).TotalDays)

    # Add license info to string
    $licenseInfo += "$($entry.feature) | Expires On: $($entry.expires) | Expired?: $($entry.expired) | Days Until Expiration: $daysUntilExpiration`n"

    # Track expiration days
    $allExpirations += $daysUntilExpiration
}

# Set full license info as a string property
Ninja-Property-Set firewallLicenseExpiration $licenseInfo

# Set the soonest license expiration as an integer for alerting
if ($allExpirations.Count -gt 0) {
    $minExpiration = ($allExpirations | Measure-Object -Minimum).Minimum
    Ninja-Property-Set firewallLicenseExpiringSoon $minExpiration
}
