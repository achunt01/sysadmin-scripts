<#
.SYNOPSIS
    Reports all O365 mailboxes with forwarding configured.

.DESCRIPTION
    Connects to Exchange Online and pulls all mailboxes with either
    ForwardingAddress or ForwardingSMTPAddress set. Resolves internal
    ForwardingAddress values to their primary SMTP address so the output
    is consistent regardless of how the forwarding was configured.

    Exports results to CSV including whether "deliver and forward" is
    enabled (i.e. whether the original mailbox also keeps a copy).

.EXAMPLE
    .\Get-O365ForwardingReport.ps1

    Connects to Exchange Online interactively, pulls all mailboxes,
    and exports the forwarding report to C:\Temp\ForwardingResolved.csv.

.NOTES
    Author  : Amanda Hunt
    Version : 1.0
    Tested  : Exchange Online / O365

    Requirements:
      - ExchangeOnlineManagement module
        Install-Module ExchangeOnlineManagement

    Output columns:
      User              - UPN of the mailbox
      ForwardTo         - Resolved SMTP address being forwarded to
      DeliverAndForward - Whether a copy is also kept in the original mailbox

    Output path: C:\Temp\ForwardingResolved.csv
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
# PULL AND RESOLVE FORWARDING
# ============================================================

Write-Host "`nPulling all mailboxes. This may take a while on large tenants..." -ForegroundColor Cyan

Get-Mailbox -ResultSize Unlimited | ForEach-Object {

    $fwd  = $_.ForwardingAddress
    $smtp = $_.ForwardingSMTPAddress
    $dest = $null

    # SMTP forwarding is already a clean address, use it directly.
    # Internal ForwardingAddress is a DN-style value, so we resolve
    # it to a primary SMTP via Get-Recipient.
    if ($smtp) {
        $dest = $smtp
    }
    elseif ($fwd) {
        $recipient = Get-Recipient $fwd -ErrorAction SilentlyContinue
        $dest = $recipient.PrimarySmtpAddress
    }

    # Only return mailboxes that actually have forwarding set.
    if ($dest) {
        [PSCustomObject]@{
            User              = $_.UserPrincipalName
            ForwardTo         = $dest
            DeliverAndForward = $_.DeliverToMailboxAndForward
        }
    }

} | Export-Csv C:\Temp\ForwardingResolved.csv -NoTypeInformation

Write-Host "`nReport saved to C:\Temp\ForwardingResolved.csv" -ForegroundColor Green

Disconnect-ExchangeOnline -Confirm:$false
