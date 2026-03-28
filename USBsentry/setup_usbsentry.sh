#!/bin/bash
# =============================================================================
# setup_usbsentry.sh
# One-time setup for USB device scanning on Raspberry Pi
# Repository: https://github.com/phoggbergActual/Tools/tree/main/USBsentry
# =============================================================================
#
# PURPOSE:
#   Installs and configures automatic USB device scanning using ClamAV.
#   Any USB mass storage device inserted after setup will be scanned
#   before the OS mounts it. Threats result in read-only mount and alert.
#   Also enables logging of unexpected HID (keyboard/input) device insertions
#   as a defense against BadUSB/RubberDucky style attacks.
#
# USAGE:
#   wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBsentry/setup_usbsentry.sh
#   cat setup_usbsentry.sh
#   sudo bash setup_usbsentry.sh
#
# =============================================================================

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root: sudo bash setup_usbsentry.sh"
    exit 1
fi

PI_USER="${SUDO_USER:-pi}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBsentry"

echo ""
echo "========================================================"
echo "  USBsentry Setup"
echo "========================================================"
echo ""

# --- Step 1: Install packages ------------------------------------------------
echo "Step 1: Installing required packages..."
apt-get update -qq
apt-get install -y clamav clamav-daemon libnotify-bin
echo "  Done."

# --- Step 2: Update ClamAV definitions --------------------------------------
echo "Step 2: Updating ClamAV virus definitions..."
systemctl stop clamav-freshclam 2>/dev/null || true
freshclam || echo "  Warning: freshclam had issues — will retry on next scheduled run."
systemctl enable clamav-freshclam
systemctl start clamav-freshclam
systemctl enable clamav-daemon
systemctl start clamav-daemon
echo "  Done."

# --- Step 3: Download and install scripts ------------------------------------
echo "Step 3: Installing USBsentry scripts..."

# Download usb_scan.sh if not already present locally
if [[ ! -f "$SCRIPT_DIR/usb_scan.sh" ]]; then
    wget -q "$BASE_URL/usb_scan.sh" -O /tmp/usb_scan.sh
    SCAN_SCRIPT="/tmp/usb_scan.sh"
else
    SCAN_SCRIPT="$SCRIPT_DIR/usb_scan.sh"
fi

if [[ ! -f "$SCRIPT_DIR/99-usb-scan.rules" ]]; then
    wget -q "$BASE_URL/99-usb-scan.rules" -O /tmp/99-usb-scan.rules
    RULES_FILE="/tmp/99-usb-scan.rules"
else
    RULES_FILE="$SCRIPT_DIR/99-usb-scan.rules"
fi

if [[ ! -f "$SCRIPT_DIR/usb-scan@.service" ]]; then
    wget -q "$BASE_URL/usb-scan@.service" -O /tmp/usb-scan@.service
    SERVICE_FILE="/tmp/usb-scan@.service"
else
    SERVICE_FILE="$SCRIPT_DIR/usb-scan@.service"
fi

# Install
cp "$SCAN_SCRIPT" /usr/local/bin/usb_scan.sh
chmod +x /usr/local/bin/usb_scan.sh
chown root:root /usr/local/bin/usb_scan.sh

cp "$RULES_FILE" /etc/udev/rules.d/99-usb-scan.rules
chmod 644 /etc/udev/rules.d/99-usb-scan.rules

cp "$SERVICE_FILE" /etc/systemd/system/usb-scan@.service
chmod 644 /etc/systemd/system/usb-scan@.service

# Create log files
touch /var/log/usb_scan.log
chmod 666 /var/log/usb_scan.log
touch "/home/$PI_USER/usb_scan_alerts.log"
chown "$PI_USER:$PI_USER" "/home/$PI_USER/usb_scan_alerts.log"

# Record current HID device count as baseline for BadUSB detection
ls /dev/hidraw* 2>/dev/null | wc -l > /var/run/expected_hid_count || echo "0" > /var/run/expected_hid_count

# Add HID baseline to boot sequence
if ! grep -q "expected_hid_count" /etc/rc.local 2>/dev/null; then
    if [[ ! -f /etc/rc.local ]]; then
        printf '#!/bin/bash\nexit 0\n' > /etc/rc.local
        chmod +x /etc/rc.local
    fi
    sed -i '/^exit 0/i # USBsentry: record expected HID count at boot\nls /dev/hidraw* 2>/dev/null | wc -l > /var/run/expected_hid_count || echo "0" > /var/run/expected_hid_count\n' /etc/rc.local
fi

# Reload udev and systemd
udevadm control --reload-rules
udevadm trigger
systemctl daemon-reload

echo "  Done."

# --- Step 4: Test with EICAR -------------------------------------------------
echo "Step 4: Testing ClamAV with EICAR test file..."
echo "  (EICAR is a harmless industry-standard test string, not real malware)"

EICAR_FILE="/tmp/eicar_test.txt"
printf 'X5O!P%%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$EICAR_FILE"

EICAR_RESULT=0
clamscan "$EICAR_FILE" 2>&1 | grep -E "FOUND|OK" || EICAR_RESULT=$?

if [[ "$EICAR_RESULT" -eq 1 ]]; then
    echo "  ClamAV test: PASSED"
else
    echo "  WARNING: ClamAV did not detect the EICAR test file."
    echo "  Check: sudo systemctl status clamav-daemon"
fi

rm -f "$EICAR_FILE"

# --- Done --------------------------------------------------------------------
echo ""
echo "========================================================"
echo "  USBsentry is active."
echo "========================================================"
echo ""
echo "  Any USB drive inserted will be scanned before mounting."
echo "  Threats result in read-only mount and an alert."
echo "  Unexpected keyboard/input devices are logged as warnings."
echo ""
echo "  Logs:"
echo "    /var/log/usb_scan.log"
echo "    ~/usb_scan_alerts.log"
echo ""
