# sysadmin-scripts

A collection of PowerShell utilities for Windows system administration and
security engineering work. Covers event log querying, GPO management, firewall
configuration, and other tools that are faster to run than to click through.

All scripts are interactive and prompt for input — no parameters required.
Run as Administrator unless noted otherwise.

---

## Scripts

| Script | Description | Requirements |
|--------|-------------|--------------|
| `Get-EventLogLookup.ps1` | Lists readable event logs and queries by Event ID interactively | None |
| `Add-GPOFirewallRule.ps1` | Adds a WFAS application allow rule to a GPO | RSAT (GroupPolicy, AD DS) |

---

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- RSAT installed for scripts that touch Group Policy or Active Directory
- Domain-joined machine with appropriate permissions for GPO work

---

## Notes

Scripts are designed to run locally and interactively. No `-ComputerName`
support unless specified. Each script has a comment block header with
`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, and `.NOTES` — run `Get-Help
.\ScriptName.ps1` for detail without opening the file.
