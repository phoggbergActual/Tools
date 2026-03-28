#!/bin/bash
# =============================================================================
# usbguard_helper.sh
# Interactive helper for authorizing blocked USB devices
# Repository: https://github.com/phoggbergActual/Tools/tree/main/USBGuard
# =============================================================================
#
# PURPOSE:
#   Makes it easy to authorize a new legitimate USB device that USBGuard
#   has blocked. Shows blocked devices in a readable format, prompts for
#   which one to authorize, and whether to make it permanent.
#
# USAGE:
#   sudo usbguard_helper.sh
#   -- or if alias is set --
#   usb-allow
#
# WHEN TO USE:
#   When you plug in a new USB device (thumb drive, keyboard, etc.) and
#   it does not work — USBGuard has blocked it. Run this script to
#   authorize it.
#
# =============================================================================

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root: sudo usbguard_helper.sh"
    echo "Or use the alias: usb-allow"
    exit 1
fi

echo ""
echo "========================================================"
echo "  USBGuard Device Authorization"
echo "========================================================"
echo ""

# Show blocked devices
echo "Blocked devices:"
echo ""

BLOCKED=$(usbguard list-devices --blocked 2>/dev/null || echo "")

if [[ -z "$BLOCKED" ]]; then
    echo "  No devices currently blocked."
    echo ""
    echo "  If a device is not working, check:"
    echo "    sudo systemctl status usbguard"
    echo "    sudo journalctl -u usbguard -n 20"
    exit 0
fi

echo "$BLOCKED"
echo ""

# Show all devices for context
echo "All connected devices (for reference):"
usbguard list-devices 2>/dev/null || true
echo ""

read -rp "Enter device ID to authorize (or q to quit): " DEVICE_ID

if [[ "$DEVICE_ID" == "q" || -z "$DEVICE_ID" ]]; then
    echo "No changes made."
    exit 0
fi

# Validate it looks like a device ID (number)
if ! [[ "$DEVICE_ID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Device ID should be a number. Check 'sudo usbguard list-devices'."
    exit 1
fi

echo ""
echo "Device $DEVICE_ID selected."
echo ""
read -rp "Make this authorization permanent (survives reboot)? (yes/no): " PERMANENT

if [[ "$PERMANENT" == "yes" ]]; then
    if usbguard allow-device -p "$DEVICE_ID" 2>/dev/null; then
        echo ""
        echo "Device $DEVICE_ID authorized permanently."
        echo "It will be allowed on all future connections."
    else
        echo ""
        echo "ERROR: Could not authorize device $DEVICE_ID."
        echo "Check: sudo usbguard list-devices"
    fi
else
    if usbguard allow-device "$DEVICE_ID" 2>/dev/null; then
        echo ""
        echo "Device $DEVICE_ID authorized for this session only."
        echo "It will be blocked again after reboot."
        echo "Run 'usb-allow' again after reboot to re-authorize, or use permanent option."
    else
        echo ""
        echo "ERROR: Could not authorize device $DEVICE_ID."
        echo "Check: sudo usbguard list-devices"
    fi
fi

echo ""
echo "Current device status:"
usbguard list-devices 2>/dev/null || true
echo ""
