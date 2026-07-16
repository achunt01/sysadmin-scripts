#!/bin/bash

# ============================================================================
# macOS Security Posture Check
# ============================================================================
#
# Purpose:
#   Quick pass over the three switches that should basically never be off:
#   Gatekeeper, System Integrity Protection, and the application firewall.
#   Prints each state and exits 1 if anything is disabled, so an RMM
#   condition can flag the device for a look.
#
# Use Cases:
#   - Baseline check on new or reimaged Macs
#   - Catch devices where someone "temporarily" disabled SIP and forgot
# ============================================================================

ISSUES=0

# Gatekeeper - spctl reports "assessments enabled" or "assessments disabled"
GATEKEEPER=$(spctl --status 2>/dev/null)
echo "Gatekeeper : $GATEKEEPER"
if ! echo "$GATEKEEPER" | grep -q "enabled"; then
    ISSUES=$((ISSUES+1))
fi

# SIP - csrutil works from a normal boot for reading status
SIP=$(csrutil status 2>/dev/null)
echo "SIP        : $SIP"
if ! echo "$SIP" | grep -q "enabled"; then
    ISSUES=$((ISSUES+1))
fi

# Application firewall global state
FIREWALL=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
echo "Firewall   : $FIREWALL"
if ! echo "$FIREWALL" | grep -qi "enabled"; then
    ISSUES=$((ISSUES+1))
fi

echo ""
if [ "$ISSUES" -gt 0 ]; then
    echo "$ISSUES security feature(s) disabled - needs attention."
    exit 1
fi

echo "All good."
exit 0
