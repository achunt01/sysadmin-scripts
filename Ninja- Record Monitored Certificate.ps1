param ( 
    [string]$url  # URL/FQDN to monitor for SSL certificate expiration (example: https://example.com)
)

<#
.SYNOPSIS
    Retrieves SSL certificate details for a monitored URL and writes expiration data
    to NinjaOne custom properties.

.DESCRIPTION
    This script is designed for use with NinjaOne/RMM monitoring. It connects to a
    provided HTTPS URL, retrieves the SSL certificate presented by the remote server,
    calculates the remaining validity period, and stores the results in NinjaOne
    custom fields.

    Recommended use cases:
    - Monitor customer-facing websites
    - Track SSL certificate expiration dates
    - Create alerts or automation based on certificateDaysUntilExpiration

.REQUIREMENTS
    - HTTPS endpoint must be accessible from the device running the script
    - NinjaOne custom fields must exist:
        monitoredCertificateDetails
        certificateDaysUntilExpiration

.PARAMETER url
    The HTTPS URL to check for SSL certificate information.

.EXAMPLE
    .\Monitor-SSLCertificate.ps1 -url "https://example.com"
#>

# Allow the script to execute regardless of local execution policy restrictions.
# Scope is limited to this PowerShell process and does not make permanent system changes.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force

# Force TLS 1.2 to ensure compatibility with modern HTTPS endpoints.
# Prevents failures when connecting to servers that disable older TLS protocols.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Validate that a URL was provided before continuing.
# A missing URL would prevent the script from determining which certificate to check.
if (-not $url) {
    Write-Host "Error: Please provide a URL."
    exit 1
}

# Create an HTTPS request to the target URL.
# The request is used only to retrieve the SSL certificate presented by the server.
$request = [System.Net.HttpWebRequest]::Create($url)
$request.Method = "GET"

try {
    # Connect to the remote endpoint and retrieve the server certificate.
    # The certificate is pulled from the SSL/TLS session established during the request.
    $response = $request.GetResponse()
    $certificate = $request.ServicePoint.Certificate

    # Close the response to release network resources.
    $response.Close()
}
catch {
    # Exit with an error if the URL cannot be reached or certificate retrieval fails.
    Write-Host "Error retrieving SSL certificate for $url : $($_.Exception.Message)"
    exit 1
}

# Extract the certificate expiration date.
# Used to calculate how many days remain before certificate renewal is required.
$expirationDate = [datetime]::Parse($certificate.GetExpirationDateString())

# Calculate remaining certificate validity in days.
$daysUntilExpiration = [math]::Round(($expirationDate - (Get-Date)).TotalDays)

# Store certificate information in an object for reporting and NinjaOne updates.
$certificateDetails = @{
    MonitoredUrl          = $url
    Subject               = $certificate.GetName()
    Issuer                = $certificate.GetIssuerName()
    ExpirationDate        = $expirationDate
    DaysUntilExpiration   = $daysUntilExpiration
}

# Display certificate information locally for troubleshooting and script testing.
Write-Host "Certificate Details for URL: $url"
Write-Host "---------------------------------------"
Write-Host "Subject: $($certificateDetails.Subject)"
Write-Host "Issuer: $($certificateDetails.Issuer)"
Write-Host "Expiration Date: $($certificateDetails.ExpirationDate)"
Write-Host "Days Until Expiration: $($certificateDetails.DaysUntilExpiration)"

# Format certificate details into a single string for NinjaOne documentation.
# This allows technicians to view certificate status directly from the device record.
$monitoredDetails = "URL: $($certificateDetails.MonitoredUrl) | Subject: $($certificateDetails.Subject) | Issuer: $($certificateDetails.Issuer) | Expiration: $($certificateDetails.ExpirationDate) | Days Until Expiration: $($certificateDetails.DaysUntilExpiration)"

# Store certificate information in NinjaOne custom fields.
# These fields can be used for dashboard reporting, automation, or alerting.
Ninja-Property-Set monitoredCertificateDetails $monitoredDetails
Ninja-Property-Set certificateDaysUntilExpiration $daysUntilExpiration
