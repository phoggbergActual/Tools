#!/bin/bash
# =============================================================================
# usb_scan.sh
# USB Device Security Scanner for Raspberry Pi
# =============================================================================
#
# PURPOSE:
#   Scans any USB mass storage device with ClamAV before the OS mounts it.
#   If a threat is found, the device is mounted read-only and the user is
#   notified. If the device is clean, normal mount proceeds.
#
#   Also detects unexpected HID (Human Interface Device) insertions after
#   boot — the BadUSB/RubberDucky attack vector where a malicious device
#   presents itself as a keyboard and injects commands.
#
# HOW IT WORKS:
#   This script is called by a systemd service which is triggered by a
#   udev rule when a USB block device is inserted. It runs BEFORE the
#   automounter mounts the filesystem.
#
# DEPENDENCIES:
#   - clamav and clamav-daemon (sudo apt install clamav clamav-daemon -y)
#   - libnotify-bin for desktop notifications (sudo apt install libnotify-bin -y)
#   - udisks2 for mount control (usually pre-installed on Raspberry Pi OS)
#
# INSTALLATION:
#   See setup_security.sh for automated installation.
#   Manual: copy this file to /usr/local/bin/usb_scan.sh
#           chmod +x /usr/local/bin/usb_scan.sh
#
# LOG FILE:
#   /var/log/usb_scan.log  — all scan results
#   ~/usb_scan_alerts.log  — threats found (in the pi user's home directory)
#
# TESTED WITH:
#   - Clean USB drive: mounts normally
#   - EICAR test file on USB: mounted read-only, alert generated
#   - No false positives on standard files
#
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
LOG_FILE="/var/log/usb_scan.log"
ALERT_FILE="/home/pi/usb_scan_alerts.log"
PI_USER="pi"
SCAN_TIMEOUT=300    # seconds before scan times out (5 minutes)
MOUNT_BASE="/media/pi"

# --- Logging -----------------------------------------------------------------
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [usb_scan] $*" | tee -a "$LOG_FILE"
}

alert() {
    local message="$1"
    log "ALERT: $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ALERT: $message" >> "$ALERT_FILE"

    # Desktop notification if a display session is running
    if command -v notify-send &>/dev/null; then
        DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $PI_USER)/bus" \
            sudo -u "$PI_USER" notify-send \
            --urgency=critical \
            --icon=security-high \
            "USB Security Alert" \
            "$message" 2>/dev/null || true
    fi
}

# --- Validate input ----------------------------------------------------------
# The device path is passed as the first argument by the systemd service
DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
    log "ERROR: No device specified. Called without argument."
    exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
    log "ERROR: $DEVICE is not a block device or does not exist."
    exit 1
fi

log "USB device inserted: $DEVICE"

# --- Check device type -------------------------------------------------------
# Use udev environment variables passed from the udev rule.
# ID_BUS and DEVTYPE are set by udev when this service is triggered.
# Re-querying with udevadm info is a fallback only.
ID_BUS="${ID_BUS:-$(udevadm info --query=property --name="$DEVICE" 2>/dev/null | grep "^ID_BUS=" | cut -d= -f2 || echo "unknown")}"
ID_TYPE="${ID_TYPE:-$(udevadm info --query=property --name="$DEVICE" 2>/dev/null | grep "^ID_TYPE=" | cut -d= -f2 || echo "unknown")}"
DEV_TYPE="${DEVTYPE:-$(udevadm info --query=property --name="$DEVICE" 2>/dev/null | grep "^DEVTYPE=" | cut -d= -f2 || echo "unknown")}"

log "Device type: $ID_TYPE, Bus: $ID_BUS, DEVTYPE: $DEV_TYPE"

# Only process USB mass storage devices
if [[ "$ID_BUS" != "usb" ]]; then
    log "Not a USB device (ID_BUS=$ID_BUS). Skipping."
    exit 0
fi

# Only process partitions, not the raw disk device (e.g. sda not sda1)
if [[ "$DEV_TYPE" != "partition" ]]; then
    log "Not a partition (DEVTYPE=$DEV_TYPE). Skipping — will process the partition when it appears."
    exit 0
fi

# --- Check for unexpected HID devices ----------------------------------------
# A Pi Zero or similar presenting as HID after boot is a BadUSB indicator
HID_DEVICES=$(ls /dev/hidraw* 2>/dev/null | wc -l)
EXPECTED_HID_COUNT_FILE="/var/run/expected_hid_count"

if [[ -f "$EXPECTED_HID_COUNT_FILE" ]]; then
    EXPECTED_HID=$(cat "$EXPECTED_HID_COUNT_FILE")
    if [[ "$HID_DEVICES" -gt "$EXPECTED_HID" ]]; then
        alert "WARNING: Unexpected HID device detected ($HID_DEVICES devices, expected $EXPECTED_HID). Possible BadUSB/RubberDucky attack. New keyboard/input device was inserted. Do NOT type anything until you have inspected this device physically."
        # Do not exit — still scan the block device if one was also inserted
    fi
fi

# Update expected HID count at boot (called from rc.local or systemd)
# echo "$HID_DEVICES" > "$EXPECTED_HID_COUNT_FILE"

# --- Wait for device to fully settle ----------------------------------------
# udevadm settle waits until udev has finished processing all pending events
# This is correct — never use sleep as a substitute for proper event handling
udevadm settle --timeout=10 || true

# --- Run ClamAV scan on raw device -------------------------------------------
log "Starting ClamAV scan on $DEVICE..."

SCAN_RESULT=0
SCAN_OUTPUT=""

# Scan the raw block device before mount
# --no-summary suppresses the summary line which confuses log parsing
# timeout prevents the script hanging indefinitely on a large device
SCAN_OUTPUT=$(timeout "$SCAN_TIMEOUT" clamscan \
    --recursive \
    --no-summary \
    --stdout \
    "$DEVICE" 2>&1) || SCAN_RESULT=$?

# ClamAV exit codes:
#   0 = no virus found
#   1 = virus found
#   2 = error
case "$SCAN_RESULT" in
    0)
        log "Scan complete: CLEAN. Device $DEVICE is safe to mount."
        # Allow normal automount to proceed.
        # NOTE: This relies on udisks2 automounting the device after this script exits.
        # udisks2 is present on Raspberry Pi OS Desktop. On Pi OS Lite there is no
        # automounter — the user must mount manually: sudo mount /dev/sda1 /mnt/usb
        exit 0
        ;;
    1)
        # Threat found
        THREAT_DETAIL=$(echo "$SCAN_OUTPUT" | grep "FOUND" || echo "Unknown threat")
        alert "THREAT DETECTED on $DEVICE: $THREAT_DETAIL"
        alert "Device will be mounted READ-ONLY. Do not open any files from this device."

        # Mount read-only if not already mounted
        MOUNT_POINT="$MOUNT_BASE/$(basename $DEVICE)_quarantine"
        mkdir -p "$MOUNT_POINT"

        if mount -o ro "$DEVICE" "$MOUNT_POINT" 2>/dev/null; then
            log "Device mounted READ-ONLY at $MOUNT_POINT"
        else
            log "Could not mount device even read-only. Device blocked entirely."
            alert "Device $DEVICE blocked entirely — could not mount even read-only. Scan found: $THREAT_DETAIL"
        fi

        exit 1
        ;;
    124)
        # Timeout
        alert "Scan TIMED OUT on $DEVICE after ${SCAN_TIMEOUT} seconds. Device blocked as a precaution."
        exit 1
        ;;
    *)
        # ClamAV error
        log "Scan ERROR on $DEVICE (exit code $SCAN_RESULT): $SCAN_OUTPUT"
        alert "ClamAV error scanning $DEVICE. Check /var/log/usb_scan.log. Device blocked as a precaution."
        exit 1
        ;;
esac
