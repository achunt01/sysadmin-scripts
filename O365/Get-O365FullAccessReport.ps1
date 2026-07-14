<#
.SYNOPSIS
    Reports all explicitly granted Full Access permissions across O365 mailboxes.

.DESCRIPTION
    Connects to Exchange Online and pulls Full Access mailbox permissions for
    every mailbox in the tenant. Filters out inherited permissions and system
    accounts (NT AUTHORITY\*) so results reflect only explicit human-to-human
    grants.

    Use Get-O365DelegationReport.ps1 if you also need Send As and Send on
    Behalf in the same output. This script is scoped to Full Access only,
    which makes it faster for targeted audits.

.EXAMPLE
    .\Get-O365FullAccessReport.ps1

    Connects to Exchange Online interactively and exports Full Access
    permissions to C:\Temp\MailboxFullAccessReport.csv.

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : Exchange Online / O365

    Requirements:
      - ExchangeOnlineManagement module
        Install-Module ExchangeOnlineManagement

    Output columns:
      Mailbox      - Primary SMTP of the mailbox being accessed
      User         - Account that has Full Access
      AccessRights - Access rights value from the permission entry

    Output path: C:\Temp\MailboxFullAccessReport.csv
#>

# ============================================================
# MODULE CHECK
# ============================================================

if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "ExchangeOnlineManagement module not found. Run: Install-Module ExchangeOnlineManagement" -ForegroundColor Red
    return
}

# ============================================================
# CONNECT
# ============================================================

Connect-ExchangeOnline

# ============================================================
# PULL FULL ACCESS PERMISSIONS
# ============================================================

Write-Host "`nPulling all mailboxes. This may take a while on large tenants..." -ForegroundColor Cyan

Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    $mailbox = $_

    # Filter out inherited permissions and system accounts.
    # What's left is only explicitly granted Full Access entries.
    Get-MailboxPermission -Identity $mailbox.Identity |
        Where-Object {
            $_.User -notlike "NT AUTHORITY\*" -and
            $_.User -ne "SELF" -and
            $_.IsInherited -eq $false
        } |
        Select-Object @{
            Name       = "Mailbox"
            Expression = { $mailbox.PrimarySmtpAddress }
        }, User, AccessRights

} | Export-Csv "C:\Temp\MailboxFullAccessReport.csv" -NoTypeInformation

Write-Host "`nReport saved to C:\Temp\MailboxFullAccessReport.csv" -ForegroundColor Green

Disconnect-ExchangeOnline -Confirm:$false
