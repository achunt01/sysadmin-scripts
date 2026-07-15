# sysadmin-scripts

A collection of PowerShell (and a little Bash) utilities for Windows, Microsoft 365,
and endpoint administration and security engineering work. Covers software
deployment, Windows Update management, firewall and GPO configuration, Exchange
Online and SharePoint reporting, .NET vulnerability remediation, and cross-platform
patch-compliance monitoring.

Many of these are written to run unattended under an RMM (NinjaOne) as SYSTEM, so
several read parameters or write results back to RMM custom fields rather than
prompting interactively. Others are interactive and prompt for input where
applicable. Run elevated for anything that touches Group Policy, Active Directory,
the Windows Update Agent, restricted event logs, or protected file paths.

---

## Layout

```
Installs/                  Software and security-agent deployment
Uninstalls/                Full-removal / cleanup scripts
O365/                      Microsoft 365 — Exchange Online, SharePoint, Intune, Entra ID
Windows/                   Windows OS, Update, firewall, browser, and RMM condition scripts
Vulnerability-Remediations/ .NET runtime cleanup and related remediation
macOS/                     macOS monitoring
```

---

## Installs

| Script | Description |
|--------|-------------|
| `Install-SentinelOneAgent.ps1` | Installs the SentinelOne (S1) agent, pulling the package via the S1 API using a server hostname, API token, and site token |
| `Install-TenableAgent.ps1` | Installs / verifies the Tenable Nessus Agent, detecting existing installs across the standard Program Files paths |
| `Install-TenableAgentNew.ps1` | Newer self-healing Nessus Agent deployment with a grace-period stamp file to prevent repeated re-runs (churn) under RMM |

## Uninstalls

| Script | Description |
|--------|-------------|
| `Remove-ZoomCompletely.ps1` | Complete Zoom removal across all system and user-profile paths; built to run as SYSTEM and log to a timestamped file. Reinstall Zoom fresh afterward |
| `Get-McAfeeFootprint.ps1` | Read-only inventory of McAfee's presence — uninstall keys, AppX packages, services, processes, and folders. Run before/after a removal to confirm state |
| `Get-McAfeeRegistryRemnants.ps1` | Deep read-only registry sweep for McAfee remnants across all hives (including per-user `NTUSER.DAT` and MSI Installer products); logs findings to file |
| `Remove-McAfeeWPSCompletely.ps1` | Two-phase forced removal of McAfee WPS for when the official MCPR tool fails. Phase 1 strips services/keys/AppX and queues locked files; Phase 2 finishes cleanup on next boot as SYSTEM |

## O365 (Microsoft 365)

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Get-O365ForwardingReport.ps1` | Reports all mailboxes with forwarding configured, resolved to SMTP | ExchangeOnlineManagement |
| `Get-O365FullAccessReport.ps1` | Reports explicitly granted Full Access permissions across all mailboxes | ExchangeOnlineManagement |
| `Get-O365DelegationReport.ps1` | Reports Full Access, Send As, and Send on Behalf across all mailboxes | ExchangeOnlineManagement |
| `Report-SharePointTempFiles.ps1` | Reports orphaned SharePoint `~$` Office temp files across listed sites to a CSV | PnP.PowerShell |
| `Remove-SharePointFilesFromCSV.ps1` | Bulk recycles SharePoint files from a CSV of full URLs, grouped by site collection | PnP.PowerShell, Entra ID app registration |
| `Set-TemporaryO365Passwords.ps1` | Sets temporary passwords for users via Microsoft Graph | Microsoft.Graph |
| `Enroll-IntuneAzureADDevice.ps1` | Forces Intune (MDM) enrollment on an Entra ID joined Windows device by creating the MDM enrollment registry values and launching the built-in enrollment | Runs as SYSTEM; user signed in |

## Windows

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Get-EventLogLookup.ps1` | Lists readable event logs and queries by Event ID interactively | Elevated for restricted logs |
| `Get-MissingWindowsUpdates.ps1` | Queries the Windows Update Agent directly for missing updates and writes the list to an RMM custom field | Elevated |
| `Install-WindowsUpdatesNoReboot.ps1` | Installs pending updates via the Windows Update Agent, filtering out Preview updates, and suppresses reboot | Elevated |
| `Test-WindowsTargetRelease.ps1` | RMM condition script — compares the org's target Windows version custom field against the device's `TargetReleaseVersionInfo` registry value (exit 0 = match, exit 1 = mismatch) | NinjaOne custom field |
| `Add-FirewallApplicationToGPO.ps1` | Adds a Windows Firewall (WFAS) application allow rule to a GPO | RSAT: GroupPolicy, AD DS |
| `Check-FirewallLogPerms.ps1` | Verifies the firewall log folder exists and `NT SERVICE\MpsSvc` has Write/Modify access; creates and remediates if missing | Elevated (SYSTEM via RMM) |
| `Invoke-WindowsFirewallAudit.ps1` | Audits listening ports against staged inbound firewall rules and writes a report to `C:\Support` | Elevated |
| `Set-ChromeHomepage.ps1` | Sets the Chrome startup/homepage URL via policy registry keys | Elevated |
| `Set-EdgeHomepage.ps1` | Sets the Microsoft Edge home button / startup page via policy registry keys | Elevated |
| `Install-WingetUpgrade.ps1` | Installs winget (App Installer) if missing, otherwise upgrades it | Elevated |
| `Get-MonitoredCertificate.ps1` | Retrieves the SSL certificate for a given HTTPS URL and writes expiration data to NinjaOne custom fields | NinjaOne custom fields |

## Vulnerability-Remediations

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Invoke-DotNetRuntimeCleanup.ps1` | Keeps only the latest patch per .NET / ASP.NET / Hosting Bundle family, removes superseded versions, and skips uninstall for runtimes in active use. Safe for mixed LTS/STS. Supports host exclusions | Elevated |
| `Uninstall-DotNetAllButLatest.ps1` | Installs the .NET Uninstall Tool if needed and removes all but the latest runtime, ASP.NET runtime, and hosting bundle, plus specified legacy versions. Supports host exclusions | Elevated |
| `Get-DotNetProcesses.ps1` | Lists running processes that have a specific .NET runtime (e.g. .NET 6) module loaded — useful before removing a runtime | None |

## macOS

| Script | Description |
|--------|-------------|
| `monitor-last-update.sh` | Retrieves the most recent macOS install/update date and version, calculates days since last update, and reports to NinjaOne custom fields |

---

## Requirements

### Modules

```powershell
# Exchange Online reporting scripts
Install-Module ExchangeOnlineManagement

# SharePoint / PnP scripts
Install-Module PnP.PowerShell

# Temporary password script
Install-Module Microsoft.Graph

# GPO firewall script — install via Windows Features instead
# Settings > Optional Features > RSAT: Group Policy Management Tools
# Settings > Optional Features > RSAT: Active Directory DS Tools
```

### Permissions

| Script | Minimum Permission |
|--------|--------------------|
| `Get-EventLogLookup.ps1` | Local user (elevated for Security/Sysmon logs) |
| `Add-FirewallApplicationToGPO.ps1` | Domain account with GPO edit rights |
| `Get-O365ForwardingReport.ps1` | Exchange Online: View-Only Recipients |
| `Get-O365FullAccessReport.ps1` | Exchange Online: View-Only Recipients |
| `Get-O365DelegationReport.ps1` | Exchange Online: View-Only Recipients |
| `Remove-SharePointFilesFromCSV.ps1` | SharePoint: Contribute or above on target sites |
| `Set-TemporaryO365Passwords.ps1` | Graph: User administrator |

---

## Notes

- RMM-oriented scripts (Ninja) run as SYSTEM and read/write custom fields instead of prompting; they aren't meant for interactive desktop use.
- Update-related scripts talk to the Windows Update Agent (WUA) COM API directly rather than PSWindowsUpdate, which avoids the `ArgumentException` that occurs when update metadata is malformed.
- The SharePoint deletion script recycles files rather than permanently deleting them — recovery is possible from the site recycle bin.
- The .NET remediation scripts refuse to uninstall runtimes that are actively in use, and honor a host-exclusion list.
- Every PowerShell script carries a comment-based help block — run `Get-Help .\ScriptName.ps1` for the synopsis, description, and parameters without opening the file.

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
