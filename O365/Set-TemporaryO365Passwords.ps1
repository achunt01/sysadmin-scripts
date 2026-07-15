<#
.SYNOPSIS
    Sets temporary passwords for Microsoft 365 users via Microsoft Graph.

.DESCRIPTION
    Ensures the Microsoft.Graph module is available, connects to Graph, and resets
    the specified users' passwords to a temporary value (forcing a change at next
    sign-in). Handy for bulk onboarding or after a suspected account compromise.

.NOTES
    Author: Amanda Hunt
    Requires Microsoft.Graph and an admin account with User Administrator rights.
#>
Write-Host "Checking for MSGraph module..."

$Module = Get-Module -Name "Microsoft.Graph.Users.Actionst" -ListAvailable

if ($Module -eq $null) {
    
        Write-Host "MSGraph module not found, installing MSGraph"
        Install-Module -name Microsoft.Graph.Users.Actions
    
    }
Connect-MgGraph

#Enter Admin credentials

############# Define CSV path of Users and Group ##################

$users = Import-Csv "C:\passwordchange.csv"

$users | ForEach-Object {
    $passwordProfile = @{
        Password = $_.Password
        ForceChangePasswordNextSignIn = $true
    }

    Write-Host "Updating $($_.UserPrincipalName)..." -ForegroundColor Yellow

    Update-MgUser -UserId $_.UserPrincipalName -PasswordProfile $passwordProfile
}
