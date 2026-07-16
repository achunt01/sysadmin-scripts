<#
.SYNOPSIS
    Reports MFA registration status for every user in the tenant.

.DESCRIPTION
    Pulls the authentication method registration report from Microsoft Graph and
    exports per-user MFA state to CSV: registered or not, capable or not, default
    method, everything they've enrolled, and whether the account holds an admin
    role. Prints the two numbers that actually get asked about -- users without
    MFA, and admins without MFA -- at the end.

.PARAMETER ReportPath
    Where to write the CSV. Defaults to C:\Temp\MFA_Status_Report.csv.

.NOTES
    Author: Amanda Hunt
    Requires Microsoft.Graph.Reports and the AuditLog.Read.All scope
    (Reports Reader or Global Reader role works). Disconnects when finished.
#>
param (
    [string]$ReportPath = "C:\Temp\MFA_Status_Report.csv"
)

Write-Host "Checking for Microsoft.Graph.Reports module..."
if (-not (Get-Module -Name Microsoft.Graph.Reports -ListAvailable)) {
    Write-Host "Not found - installing."
    Install-Module Microsoft.Graph.Reports -Scope CurrentUser -Force
}

Connect-MgGraph -Scopes "AuditLog.Read.All" -NoWelcome

Write-Host "Pulling registration details for all users (can take a minute on big tenants)..."
$details = Get-MgReportAuthenticationMethodUserRegistrationDetail -All

$report = $details | ForEach-Object {
    [PSCustomObject]@{
        User              = $_.UserPrincipalName
        MfaRegistered     = $_.IsMfaRegistered
        MfaCapable        = $_.IsMfaCapable
        DefaultMethod     = $_.DefaultMfaMethod
        MethodsRegistered = ($_.MethodsRegistered -join ", ")
        IsAdmin           = $_.IsAdmin
    }
}

# make sure the output folder exists before exporting
$folder = Split-Path $ReportPath -Parent
if ($folder -and -not (Test-Path $folder)) {
    New-Item $folder -ItemType Directory -Force | Out-Null
}

$report | Sort-Object MfaRegistered, User | Export-Csv -Path $ReportPath -NoTypeInformation

# the two numbers anyone actually asks for
$noMfa      = @($report | Where-Object { -not $_.MfaRegistered })
$adminNoMfa = @($noMfa | Where-Object { $_.IsAdmin })

Write-Host ""
Write-Host "Total users:        $(@($report).Count)"
Write-Host "Without MFA:        $($noMfa.Count)"
Write-Host "Admins without MFA: $($adminNoMfa.Count)  <- fix these first"
Write-Host ""
Write-Host "Report: $ReportPath"

Disconnect-MgGraph | Out-Null
