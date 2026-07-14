#!/bin/bash

# ============================================================================
# macOS Update History Monitoring Script
# ============================================================================
#
# Purpose:
#   Retrieves the most recent macOS installation/update date and version,
#   calculates the number of days since the last macOS update, and reports
#   the information to NinjaOne custom fields.
#
# Use Cases:
#   - Monitor macOS patch compliance
#   - Identify devices that have not received recent macOS updates
#   - Provide visibility into current macOS version history from NinjaOne
#
# Requirements:
#   - macOS device with NinjaOne agent installed
#   - NinjaOne custom fields:
#       lastMacosInstallDateAndVersion
#       daysSinceLastInstall
#
# Notes:
#   The macOS softwareupdate command stores update history locally. This script
#   parses that history to identify the latest macOS installation event.
#
# ============================================================================

# Apple support reference for current macOS versions.
# Included in NinjaOne output to provide technicians with a reference link.
macOSVersionLink="https://support.apple.com/en-us/109033"


# Retrieve the most recent macOS installation/update version and date.
# softwareupdate --history displays installed updates. This filters for macOS
# entries, selects the latest record, and removes unnecessary formatting.
lastInstallDateAndVersion=$(softwareupdate --history | awk '/macOS/ {print $(NF-2), $(NF-1), $NF}' | tail -n1 | cut -d',' -f1)


# Extract only the installation date from the latest macOS update record.
# Output format from macOS is typically MM/DD/YYYY.
lastInstallDate=$(softwareupdate --history | awk '/macOS/ {print $(NF-1), $NF}' | tail -n1 | cut -d',' -f1)


# Convert the install date from MM/DD/YYYY to ISO format (YYYY-MM-DD).
# ISO formatting allows easier date comparison and reporting.
lastInstallDateISO=$(date -j -f "%m/%d/%Y" "$lastInstallDate" "+%Y-%m-%d")


# Get the current date in ISO format for comparison.
currentDateISO=$(date "+%Y-%m-%d")


# Calculate the number of days since the last macOS installation/update.
# Converts both dates to Unix timestamps and calculates the difference.
daysSinceInstall=$(echo $(( ( $(date -j -f "%Y-%m-%d" "$currentDateISO" "+%s") - $(date -j -f "%Y-%m-%d" "$lastInstallDateISO" "+%s") ) / 86400 )))


# Ensure the output value is stored as an integer.
# Prevents formatting issues when writing the value to NinjaOne.
daysSinceInstall=$(printf "%d" "$daysSinceInstall")


# Output the result locally for troubleshooting and validation.
echo "Days since last macOS install/update: $daysSinceInstall"


# Update NinjaOne custom fields.
#
# lastMacosInstallDateAndVersion:
#   Stores the most recent macOS update information and Apple reference link.
#
# daysSinceLastInstall:
#   Stores the number of days since the last macOS update.
#   Can be used for NinjaOne conditions, dashboards, or alerting.
#
/Applications/NinjaRMMAgent/programdata/ninjarmm-cli set lastMacosInstallDateAndVersion "$lastInstallDateAndVersion. Latest macOS versions: $macOSVersionLink"

/Applications/NinjaRMMAgent/programdata/ninjarmm-cli set daysSinceLastInstall "$daysSinceInstall"
