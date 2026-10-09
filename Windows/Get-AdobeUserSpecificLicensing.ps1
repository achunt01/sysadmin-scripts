<#
.SYNOPSIS
    Checks whether Adobe user-specific licensing / identity is turned on.

.DESCRIPTION
    Looks at the two Adobe registry keys that control user-specific licensing
    and identity, and reports the 'Enabled' value on each - or whether the key
    is there with nothing set, or not there at all.

.NOTES
    Author: Amanda Hunt
    Read-only - just reports, doesn't change anything.
#>

$paths = @(
    "HKLM:\SOFTWARE\Adobe\Licensing\UserSpecificLicensing",
    "HKLM:\SOFTWARE\Adobe\Identity\UserSpecificIdentity"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        # key exists - now see if the Enabled value is actually set on it
        $val = (Get-ItemProperty -Path $p -Name Enabled -ErrorAction SilentlyContinue).Enabled
        if ($null -ne $val) {
            Write-Host "$p -> Enabled = $val"
        } else {
            Write-Host "$p -> exists but no 'Enabled' value set"
        }
    } else {
        Write-Host "$p -> no"
    }
}
