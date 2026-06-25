# sysadmin-scripts

A collection of PowerShell utilities for Windows and O365 administration and
security engineering work. Covers event log querying, GPO management, firewall
configuration, Exchange Online reporting, and SharePoint file management.

All scripts are interactive and prompt for input where applicable — no parameters
required unless noted. Run as Administrator for scripts that touch Group Policy,
Active Directory, or restricted event logs.

---

## Scripts

### Windows / Active Directory

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Get-EventLogLookup.ps1` | Lists readable event logs and queries by Event ID interactively | None (run elevated for restricted logs) |
| `Add-GPOFirewallRule.ps1` | Adds a WFAS application allow rule to a GPO | RSAT (GroupPolicy, AD DS) |

### O365 / Exchange Online

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Get-O365ForwardingReport.ps1` | Reports all mailboxes with forwarding configured, resolved to SMTP | ExchangeOnlineManagement |
| `Get-O365FullAccessReport.ps1` | Reports explicitly granted Full Access permissions across all mailboxes | ExchangeOnlineManagement |
| `Get-O365DelegationReport.ps1` | Reports Full Access, Send As, and Send on Behalf across all mailboxes | ExchangeOnlineManagement |

### SharePoint Online

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Remove-SharePointFilesFromCSV.ps1` | Bulk recycles SharePoint files from a CSV of full URLs, grouped by site collection | PnP.PowerShell, Entra ID app registration |

---

## Requirements

### Modules

```powershell
# Exchange Online reporting scripts
Install-Module ExchangeOnlineManagement

# SharePoint / PnP script
Install-Module PnP.PowerShell

# GPO firewall script — install via Windows Features instead
# Settings > Optional Features > RSAT: Group Policy Management Tools
# Settings > Optional Features > RSAT: Active Directory DS Tools
```

### Permissions

| Script | Minimum Permission |
|--------|--------------------|
| `Get-EventLogLookup.ps1` | Local user (elevated for Security/Sysmon logs) |
| `Add-GPOFirewallRule.ps1` | Domain account with GPO edit rights |
| `Get-O365ForwardingReport.ps1` | Exchange Online: View-Only Recipients |
| `Get-O365FullAccessReport.ps1` | Exchange Online: View-Only Recipients |
| `Get-O365DelegationReport.ps1` | Exchange Online: View-Only Recipients |
| `Remove-SharePointFilesFromCSV.ps1` | SharePoint: Contribute or above on target sites |

---

## Notes

- All scripts run locally and interactively. No `-ComputerName` support unless specified.
- O365 scripts call `Disconnect-ExchangeOnline` or `Disconnect-PnPOnline` on completion.
- The SharePoint deletion script recycles files rather than permanently deleting them. Recovery is possible from the site recycle bin.
- Each script has a `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, and `.NOTES` block — run `Get-Help .\ScriptName.ps1` for detail without opening the file.

---

## Common Event IDs (for Get-EventLogLookup.ps1)

| Log | Event ID | Description |
|-----|----------|-------------|
| Directory Service | 2889 | Unsigned LDAP bind attempted |
| Directory Service | 3074 | Channel binding audit warning (would fail at "Always") |
| Directory Service | 3075 | Channel binding rejection |
| Security | 4625 | Failed logon |
| Security | 4740 | Account lockout |
| Security | 4726 | User account deleted |
| Security | 4728 / 4732 | Member added to privileged group |
| System | 7036 | Service started / stopped |
