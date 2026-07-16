#!/bin/bash

# ============================================================================
# macOS FileVault Status Check
# ============================================================================
#
# Purpose:
#   Reports whether FileVault disk encryption is enabled, pushes the status
#   to a NinjaOne custom field when the agent CLI is present, and exits 1
#   when encryption is off so an RMM condition can flag the device.
#
# Use Cases:
#   - Encryption compliance reporting (the macOS side of BitLocker checks)
#   - Alert when a device ships or reimages without FileVault turned on
#
# Custom field (create as text field in Ninja):
#   - filevaultStatus
# ============================================================================

# fdesetup needs root to answer reliably
if [ "$EUID" -ne 0 ]; then
    echo "Run as root (sudo or via RMM)."
    exit 1
fi

STATUS=$(fdesetup status | head -1)
echo "$STATUS"

# push to Ninja if the CLI is around
NINJA_CLI="/Applications/NinjaRMMAgent/programdata/ninjarmm-cli"
if [ -x "$NINJA_CLI" ]; then
    "$NINJA_CLI" set filevaultStatus "$STATUS"
    echo "Custom field updated."
fi

# "FileVault is On." is the only good answer
if echo "$STATUS" | grep -q "FileVault is On"; then
    exit 0
fi

echo "DEVICE NOT ENCRYPTED."
exit 1
