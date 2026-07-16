#!/bin/bash

# ============================================================================
# macOS Local Admin Audit
# ============================================================================
#
# Purpose:
#   Lists every member of the local admin group and pushes the list to a
#   NinjaOne custom field when the agent CLI is present. The macOS side of
#   the Windows Get-LocalAdminAudit.ps1 script.
#
# Use Cases:
#   - Spot users who ended up with admin rights and shouldn't have them
#   - Periodic least-privilege audits across the Mac fleet
#
# Custom field (create as text field in Ninja):
#   - localAdmins
# ============================================================================

# dscl output looks like "GroupMembership: root amanda ..." - drop the label
ADMINS=$(dscl . -read /Groups/admin GroupMembership | cut -d' ' -f2-)

echo "Local admins on $(hostname):"
for user in $ADMINS; do
    echo "  - $user"
done

COUNT=$(echo $ADMINS | wc -w | tr -d ' ')
echo ""
echo "Total: $COUNT"

# push to Ninja if the CLI is around
NINJA_CLI="/Applications/NinjaRMMAgent/programdata/ninjarmm-cli"
if [ -x "$NINJA_CLI" ]; then
    "$NINJA_CLI" set localAdmins "$ADMINS"
    echo "Custom field updated."
fi

exit 0
