<#
.SYNOPSIS
    Reports all O365 mailbox delegation permissions across the tenant.

.DESCRIPTION
    Connects to Exchange Online and pulls three types of mailbox delegation
    for every mailbox in the tenant: Full Access, Send As, and Send on Behalf.
    System accounts (NT AUTHORITY\*) and self-permissions are excluded.

    Exports a single flat CSV with one row per permission entry, making it
    easy to filter in Excel or import into a ticketing system.

.EXAMPLE
    .\Get-O365DelegationReport.ps1

    Connects to Exchange Online interactively and exports the full delegation
    report to C:\Temp\MailboxDelegationReport.csv.

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : Exchange Online / O365

    Requirements:
      - ExchangeOnlineManagement module
        Install-Module ExchangeOnlineManagement

    Output columns:
      Mailbox          - Primary SMTP of the mailbox being accessed
      UserWhoHasAccess - Account that has the permission
      PermissionType   - FullAccess | SendAs | SendOnBehalf

    Output path: C:\Temp\MailboxDelegationReport.csv

    Note: Runtime scales with mailbox count. For large tenants (1000+
    mailboxes), expect this to run for several minutes.
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
# PULL DELEGATION ACROSS ALL MAILBOXES
# ============================================================

Write-Host "`nPulling all mailboxes. This may take a while on large tenants..." -ForegroundColor Cyan

$mailboxes = Get-Mailbox -ResultSize Unlimited
$results   = @()
$count     = 0

foreach ($mb in $mailboxes) {
    $count++
    Write-Progress -Activity "Checking mailbox permissions" `
                   -Status "$count of $($mailboxes.Count): $($mb.PrimarySmtpAddress)" `
                   -PercentComplete (($count / $mailboxes.Count) * 100)

    # --- Full Access ---
    # Excludes inherited permissions and system accounts so we're only
    # looking at explicitly granted human-to-human delegation.
    $fullAccess = Get-MailboxPermission -Identity $mb.Identity |
        Where-Object {
            $_.User -notlike "NT AUTHORITY\*" -and
            $_.User -ne "SELF" -and
            $_.IsInherited -eq $false
        }

    foreach ($perm in $fullAccess) {
        $results += [PSCustomObject]@{
            Mailbox          = $mb.PrimarySmtpAddress
            UserWhoHasAccess = $perm.User
            PermissionType   = "FullAccess"
        }
    }

    # --- Send As ---
    # NT AUTHORITY\SELF is the mailbox owner acting as themselves, not
    # a delegation entry, so we filter it out.
    $sendAs = Get-RecipientPermission $mb.Identity |
        Where-Object { $_.Trustee -ne "NT AUTHORITY\SELF" }

    foreach ($perm in $sendAs) {
        $results += [PSCustomObject]@{
            Mailbox          = $mb.PrimarySmtpAddress
            UserWhoHasAccess = $perm.Trustee
            PermissionType   = "SendAs"
        }
    }

    # --- Send on Behalf ---
    # This one lives directly on the mailbox object rather than a
    # separate permission cmdlet, so we just iterate the property.
    if ($mb.GrantSendOnBehalfTo) {
        foreach ($user in $mb.GrantSendOnBehalfTo) {
            $results += [PSCustomObject]@{
                Mailbox          = $mb.PrimarySmtpAddress
                UserWhoHasAccess = $user.Name
                PermissionType   = "SendOnBehalf"
            }
        }
    }
}

# ============================================================
# EXPORT
# ============================================================

$results | Export-Csv "C:\Temp\MailboxDelegationReport.csv" -NoTypeInformation
Write-Host "`nReport saved to C:\Temp\MailboxDelegationReport.csv" -ForegroundColor Green
Write-Host "Total permission entries found: $($results.Count)" -ForegroundColor Cyan

Disconnect-ExchangeOnline -Confirm:$false
