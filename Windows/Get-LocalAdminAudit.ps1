<#
.SYNOPSIS
    Audits local Administrators membership and local account hygiene.

.DESCRIPTION
    Lists everyone in the local Administrators group, then all local user accounts
    with enabled state, last logon, and password age. Enabled accounts with a
    password older than a year get flagged. Read-only -- reports, doesn't touch.

.NOTES
    Author: Amanda Hunt
    Run elevated for complete results.
    Get-LocalGroupMember chokes on orphaned SIDs (leftovers from deleted domain
    accounts), so there's an ADSI fallback that doesn't care about those.
#>

Write-Host "=== Local Administrators ==="
try {
    Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop |
        Select-Object Name, ObjectClass, PrincipalSource |
        Format-Table -AutoSize
}
catch {
    # the cmdlet dies on orphaned SIDs - ADSI just lists what's there
    Write-Host "(Get-LocalGroupMember failed - likely an orphaned SID. Using ADSI fallback.)"
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
    @($group.Invoke("Members")) | ForEach-Object {
        ([ADSI]$_).Path -replace '^WinNT://', '' -replace '/', '\'
    }
}

Write-Host ""
Write-Host "=== Local User Accounts ==="
$cutoff = (Get-Date).AddDays(-365)

Get-LocalUser | ForEach-Object {
    $flag = ""
    if ($_.Enabled -and $_.PasswordLastSet -and $_.PasswordLastSet -lt $cutoff) {
        $flag = "PW > 1 year"
    }
    [PSCustomObject]@{
        Name            = $_.Name
        Enabled         = $_.Enabled
        LastLogon       = $_.LastLogon
        PasswordLastSet = $_.PasswordLastSet
        Flag            = $flag
    }
} | Format-Table -AutoSize
