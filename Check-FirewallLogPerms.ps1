# Check-FirewallLogPerms.ps1
# Verifies %systemroot%\System32\LogFiles\Firewall exists and
# that NT SERVICE\MpsSvc has Write and Modify access.
# Creates folder and/or sets permissions if missing.
# Designed to run via RMM as SYSTEM.
#
# Exit codes:
#   0 = already correct, or remediated successfully
#   1 = remediation attempted and failed (ticket warranted)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$firewallLogPath = Join-Path $env:SystemRoot "System32\LogFiles\Firewall"
$account = "NT SERVICE\MpsSvc"
$requiredRights = [System.Security.AccessControl.FileSystemRights]"Modify, Write"
$inheritFlags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
$propagation = [System.Security.AccessControl.PropagationFlags]::None
$accessType = [System.Security.AccessControl.AccessControlType]::Allow

$results = @()
$exitCode = 0

# --- Step 1: Check/create folder ---
if (Test-Path $firewallLogPath) {
    $results += "[OK]    Folder exists: $firewallLogPath"
} else {
    try {
        New-Item -ItemType Directory -Path $firewallLogPath -Force | Out-Null
        $results += "[FIXED] Folder did not exist. Created: $firewallLogPath"
    } catch {
        $results += "[FAIL]  Could not create folder: $_"
        $results | ForEach-Object { Write-Output $_ }
        exit 1
    }
}

# --- Step 1b: Check/clear read-only attribute ---
$folderItem = Get-Item -Path $firewallLogPath
if ($folderItem.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
    try {
        $folderItem.Attributes = $folderItem.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        $results += "[FIXED] Read-only attribute was set. Cleared on: $firewallLogPath"
    } catch {
        $results += "[FAIL]  Could not clear read-only attribute: $_"
        $results | ForEach-Object { Write-Output $_ }
        exit 1
    }
} else {
    $results += "[OK]    Folder is not read-only: $firewallLogPath"
}

# --- Step 2: Check current ACL ---
$acl = Get-Acl -Path $firewallLogPath
$existingRule = $acl.Access | Where-Object {
    $_.IdentityReference -like "*MpsSvc*" -and
    $_.AccessControlType -eq "Allow" -and
    ($_.FileSystemRights -band $requiredRights) -eq $requiredRights
}

if ($existingRule) {
    $results += "[OK]    $account already has Modify/Write on $firewallLogPath"
    $results += "        Rights: $($existingRule.FileSystemRights)"
} else {
    $results += "[WARN]  $account missing required permissions. Applying..."
    try {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $account,
            $requiredRights,
            $inheritFlags,
            $propagation,
            $accessType
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $firewallLogPath -AclObject $acl
        $results += "[FIXED] Permissions applied: Modify, Write for $account"

        # Verify after applying
        $verifyAcl = Get-Acl -Path $firewallLogPath
        $verifyRule = $verifyAcl.Access | Where-Object {
            $_.IdentityReference -like "*MpsSvc*" -and
            $_.AccessControlType -eq "Allow"
        }
        if ($verifyRule) {
            $results += "[OK]    Verification passed. Current rights: $($verifyRule.FileSystemRights)"
        } else {
            $results += "[FAIL]  Verification failed — rule not found after apply."
            $exitCode = 1
        }
    } catch {
        $results += "[FAIL]  Could not apply permissions: $_"
        $exitCode = 1
    }
}

# --- Step 3: Output full ACL for reference ---
$results += ""
$results += "--- Current ACL on $firewallLogPath ---"
$acl = Get-Acl -Path $firewallLogPath
$acl.Access | ForEach-Object {
    $results += "  $($_.IdentityReference) | $($_.FileSystemRights) | $($_.AccessControlType)"
}

# --- Output ---
$results | ForEach-Object { Write-Output $_ }
Write-Output ""
Write-Output "Exit code: $exitCode"
exit $exitCode
