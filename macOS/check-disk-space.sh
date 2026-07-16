#!/bin/bash

# ============================================================================
# macOS Disk Space Monitoring Script
# ============================================================================
#
# Purpose:
#   Checks free space on the boot volume, reports free GB and percent used,
#   and pushes the values to NinjaOne custom fields when the agent CLI is
#   present. Exits 1 when free space drops below the threshold so an RMM
#   condition can alert on it.
#
# Use Cases:
#   - Catch full disks before users notice
#   - Feed dashboards / reports with per-device free space
#
# Custom fields (create as integer fields in Ninja):
#   - diskFreeGB
#   - diskUsedPercent
# ============================================================================

THRESHOLD_GB=20

# df -g gives 1GB blocks; line 2 is the boot volume
FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
USED_PCT=$(df -g / | awk 'NR==2 {gsub("%","",$5); print $5}')

echo "Boot volume: ${FREE_GB} GB free (${USED_PCT}% used)"

# hand the numbers to Ninja if the CLI is around
NINJA_CLI="/Applications/NinjaRMMAgent/programdata/ninjarmm-cli"
if [ -x "$NINJA_CLI" ]; then
    "$NINJA_CLI" set diskFreeGB "$FREE_GB"
    "$NINJA_CLI" set diskUsedPercent "$USED_PCT"
    echo "Custom fields updated."
else
    echo "Ninja CLI not found - skipping custom field update."
fi

if [ "$FREE_GB" -lt "$THRESHOLD_GB" ]; then
    echo "LOW DISK: below ${THRESHOLD_GB} GB free."
    exit 1
fi

exit 0
