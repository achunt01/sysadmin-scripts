<#
.SYNOPSIS
    Forces Microsoft Intune (MDM) enrollment on an Entra ID joined Windows device.

.DESCRIPTION
    This script verifies that the device contains the required Cloud Domain Join
    tenant information, creates the Microsoft MDM enrollment registry values if
    they are missing, and launches the built-in Windows MDM enrollment process.

    This is intended for use with RMM tools (such as NinjaOne) running under the
    Local SYSTEM account.

.PREREQUISITES
    - User must be actively signed into Windows.
    - Device must already be Microsoft Entra ID (Azure AD) joined.
    - Script must run as Local SYSTEM.
    - Device must have internet connectivity to Microsoft enrollment services.

.POST-ENROLLMENT
    - Enrollment typically begins within 15 minutes.
    - Restart the device after enrollment is initiated.
    - Allow an additional 15 to 30 minutes for Intune policies, compliance
      policies, and applications to process.

.EXIT CODES
    0      Success
    1001   Enrollment prerequisites not met or enrollment failed
#>

# Registry location containing the Entra ID tenant information.
$key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'

# Locate the registered Entra ID tenant.
try {
    $keyinfo = Get-Item "HKLM:\$key"
}
catch {
    Write-Host "Cloud Domain Join tenant information was not found."
    exit 1001
}

# Extract the tenant identifier from the registry path.
$url = $keyinfo.Name
$url = $url.Split("\")[-1]

# Build the full tenant registry path.
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$url"

# Verify the tenant registry key exists.
if (!(Test-Path $path)) {
    Write-Host "Registry path not found: $path"
    exit 1001
}
else {

    # Check whether the MDM enrollment values already exist.
    try {
        Get-ItemProperty $path -Name MdmEnrollmentUrl -ErrorAction Stop | Out-Null
        Write-Host "MDM enrollment registry values already exist."
    }

    # Create the required Intune enrollment registry values if missing.
    catch {
        Write-Host "MDM enrollment registry values not found. Creating required entries..."

        New-ItemProperty `
            -LiteralPath $path `
            -Name 'MdmEnrollmentUrl' `
            -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' `
            -PropertyType String `
            -Force `
            -ErrorAction SilentlyContinue

        New-ItemProperty `
            -LiteralPath $path `
            -Name 'MdmTermsOfUseUrl' `
            -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' `
            -PropertyType String `
            -Force `
            -ErrorAction SilentlyContinue

        New-ItemProperty `
            -LiteralPath $path `
            -Name 'MdmComplianceUrl' `
            -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' `
            -PropertyType String `
            -Force `
            -ErrorAction SilentlyContinue
    }

    finally {

        # Launch the built-in Windows Device Enroller.
        # This initiates Intune MDM enrollment using the current user's
        # Entra ID credentials.
        try {
            C:\Windows\System32\deviceenroller.exe /c /AutoEnrollMDM

            Write-Host "MDM enrollment has been initiated successfully."
            Write-Host "Allow approximately 15 minutes for enrollment to complete."
            Write-Host "Restart the device and allow another 15-30 minutes for Intune policies to apply."

            exit 0
        }
        catch {
            Write-Host "Failed to start the Windows Device Enroller."
            exit 1001
        }
    }
}

exit 0
