#!/bin/bash
# =============================================================================
# maintenance.sh
# Biweekly System Maintenance for Raspberry Pi
# =============================================================================
#
# PURPOSE:
#   Runs every two weeks via cron. Performs:
#     1. System package update and upgrade (apt)
#     2. ClamAV virus definition update (freshclam)
#     3. Full filesystem scan with ClamAV
#     4. Generates a plain-text report
#     5. Emails the report to the configured Gmail address
#     6. Saves the report locally in ~/logs/
#
# DEPENDENCIES:
#   - clamav, clamav-daemon
#   - msmtp (sudo apt install msmtp -y) for Gmail sending
#   - msmtp configured with Gmail credentials (see setup_security.sh)
#
# INSTALLATION:
#   See setup_security.sh for automated installation and crontab setup.
#   Manual crontab entry (runs at 2am on the 1st and 15th of each month):
#     0 2 1,15 * * /usr/local/bin/maintenance.sh
#
# GMAIL SETUP:
#   Requires an App Password from your Google account (not your main password).
#   Google Account > Security > 2-Step Verification > App Passwords
#   Generate a password for "Mail" on "Linux device"
#   Enter it during setup_security.sh configuration.
#
# LOG FILES:
#   ~/logs/maintenance_YYYYMMDD.log  — full local log
#   /var/log/maintenance.log         — system-level summary
#
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
# Edit these values or set them via setup_security.sh
REPORT_EMAIL="${1:-}"                         # Email address passed as first argument
PI_USER="${SUDO_USER:-pi}"
LOG_DIR="/home/$PI_USER/logs"
SYSTEM_LOG="/var/log/maintenance.log"
DATE_STAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="$LOG_DIR/maintenance_${DATE_STAMP}.log"
REPORT_EMAIL_CONF="/etc/msmtprc"

# Directories to scan — add or remove as needed
SCAN_PATHS=(
    "/home/$PI_USER"
    "/tmp"
    "/var/tmp"
)

# --- Validate configuration --------------------------------------------------
if [[ -z "$REPORT_EMAIL" ]]; then
    echo "ERROR: Email address required."
    echo "Usage: sudo /usr/local/bin/maintenance.sh your.email@gmail.com"
    exit 1
fi

# --- Setup -------------------------------------------------------------------
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# --- Report header -----------------------------------------------------------
{
echo "========================================================"
echo "  Raspberry Pi Maintenance Report"
echo "  $(hostname) — $(date '+%A, %B %d, %Y at %H:%M')"
echo "========================================================"
echo ""
} > "$REPORT_FILE"

log_section() {
    echo "" >> "$REPORT_FILE"
    echo "--------------------------------------------------------" >> "$REPORT_FILE"
    echo "  $1" >> "$REPORT_FILE"
    echo "--------------------------------------------------------" >> "$REPORT_FILE"
}

log_line() {
    echo "$1" >> "$REPORT_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$SYSTEM_LOG"
}

log_line "Maintenance run started"

# --- Step 1: System update ---------------------------------------------------
log_section "SYSTEM UPDATE"

{
echo "Updating package list and installing available updates..."
echo ""
} >> "$REPORT_FILE"

# Capture what will be updated before upgrading
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." || echo "none")

if [[ "$UPGRADABLE" == "none" ]]; then
    echo "No packages available for upgrade. System is current." >> "$REPORT_FILE"
else
    echo "Packages to be updated:" >> "$REPORT_FILE"
    echo "$UPGRADABLE" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Run the update
APT_RESULT=0
{
    apt-get update -qq 2>&1
    apt-get dist-upgrade -y 2>&1
} >> "$REPORT_FILE" 2>&1 || APT_RESULT=$?

if [[ "$APT_RESULT" -eq 0 ]]; then
    echo "" >> "$REPORT_FILE"
    echo "System update completed successfully." >> "$REPORT_FILE"
    log_line "System update: SUCCESS"
else
    echo "" >> "$REPORT_FILE"
    echo "WARNING: System update completed with errors (exit code $APT_RESULT)." >> "$REPORT_FILE"
    log_line "System update: COMPLETED WITH ERRORS (exit $APT_RESULT)"
fi

# Check if reboot is required
if [[ -f /var/run/reboot-required ]]; then
    echo "" >> "$REPORT_FILE"
    echo "*** REBOOT REQUIRED: A kernel or critical package was updated." >> "$REPORT_FILE"
    echo "*** Please reboot your Pi when convenient: sudo reboot" >> "$REPORT_FILE"
    log_line "REBOOT REQUIRED after update"
fi

# --- Step 2: Update ClamAV definitions ---------------------------------------
log_section "CLAMAV DEFINITION UPDATE"

FRESHCLAM_RESULT=0
freshclam 2>&1 >> "$REPORT_FILE" || FRESHCLAM_RESULT=$?

if [[ "$FRESHCLAM_RESULT" -eq 0 ]]; then
    echo "" >> "$REPORT_FILE"
    echo "ClamAV definitions updated successfully." >> "$REPORT_FILE"
    log_line "freshclam: SUCCESS"
else
    echo "" >> "$REPORT_FILE"
    echo "WARNING: freshclam completed with code $FRESHCLAM_RESULT." >> "$REPORT_FILE"
    log_line "freshclam: COMPLETED WITH CODE $FRESHCLAM_RESULT"
fi

# --- Step 3: ClamAV filesystem scan ------------------------------------------
log_section "VIRUS SCAN RESULTS"

THREATS_FOUND=0
TOTAL_SCANNED=0
SCAN_ERRORS=0

{
echo "Scanning the following locations:"
for path in "${SCAN_PATHS[@]}"; do
    echo "  - $path"
done
echo ""
} >> "$REPORT_FILE"

# Scan each configured path
SCAN_SUMMARY=""
for SCAN_PATH in "${SCAN_PATHS[@]}"; do
    if [[ ! -d "$SCAN_PATH" ]]; then
        echo "Skipping $SCAN_PATH — does not exist." >> "$REPORT_FILE"
        continue
    fi

    echo "Scanning $SCAN_PATH..." >> "$REPORT_FILE"

    PATH_RESULT=0
    PATH_OUTPUT=$(clamscan \
        --recursive \
        --infected \
        --suppress-ok-results \
        "$SCAN_PATH" 2>&1) || PATH_RESULT=$?

    echo "$PATH_OUTPUT" >> "$REPORT_FILE"

    # Parse summary line from clamscan output
    SCANNED=$(echo "$PATH_OUTPUT" | grep "Scanned files:" | grep -o '[0-9]*' || echo "0")
    INFECTED=$(echo "$PATH_OUTPUT" | grep "Infected files:" | grep -o '[0-9]*' || echo "0")

    TOTAL_SCANNED=$((TOTAL_SCANNED + SCANNED))
    THREATS_FOUND=$((THREATS_FOUND + INFECTED))

    if [[ "$PATH_RESULT" -eq 1 ]]; then
        SCAN_SUMMARY="${SCAN_SUMMARY}THREATS FOUND in $SCAN_PATH: $INFECTED file(s)\n"
    elif [[ "$PATH_RESULT" -gt 1 ]]; then
        SCAN_ERRORS=$((SCAN_ERRORS + 1))
    fi
done

# Scan any mounted USB drives
MOUNTED_USB=$(lsblk -o NAME,TRAN,MOUNTPOINT | grep usb | grep -v "^$" | awk '{print $3}' | grep -v "^$" || true)
if [[ -n "$MOUNTED_USB" ]]; then
    echo "" >> "$REPORT_FILE"
    echo "Scanning mounted USB devices:" >> "$REPORT_FILE"
    while IFS= read -r usb_mount; do
        echo "  Scanning $usb_mount..." >> "$REPORT_FILE"
        USB_RESULT=0
        clamscan --recursive --infected --suppress-ok-results "$usb_mount" 2>&1 >> "$REPORT_FILE" || USB_RESULT=$?
        if [[ "$USB_RESULT" -eq 1 ]]; then
            SCAN_SUMMARY="${SCAN_SUMMARY}THREATS FOUND on USB at $usb_mount\n"
            THREATS_FOUND=$((THREATS_FOUND + 1))
        fi
    done <<< "$MOUNTED_USB"
fi

# --- Step 4: Report summary --------------------------------------------------
log_section "SUMMARY"

{
echo "Files scanned:   $TOTAL_SCANNED"
echo "Threats found:   $THREATS_FOUND"
echo "Scan errors:     $SCAN_ERRORS"
echo ""
} >> "$REPORT_FILE"

if [[ "$THREATS_FOUND" -eq 0 ]]; then
    echo "STATUS: ALL CLEAR — No threats detected." >> "$REPORT_FILE"
    log_line "Virus scan: CLEAN ($TOTAL_SCANNED files scanned)"
else
    echo "STATUS: WARNING — $THREATS_FOUND THREAT(S) DETECTED." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Infected files were found. Do not open files from any flagged" >> "$REPORT_FILE"
    echo "location until you have reviewed the scan results above." >> "$REPORT_FILE"
    echo "Call if you need help." >> "$REPORT_FILE"
    printf "$SCAN_SUMMARY" >> "$REPORT_FILE"
    log_line "Virus scan: THREATS FOUND ($THREATS_FOUND threat(s) in $TOTAL_SCANNED files)"
fi

{
echo ""
echo "========================================================"
echo "  End of Report — $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
} >> "$REPORT_FILE"

# --- Step 5: Send email report -----------------------------------------------
if command -v msmtp &>/dev/null && [[ -f "$REPORT_EMAIL_CONF" ]]; then
    SUBJECT="Raspberry Pi Maintenance Report — $(hostname) — $(date '+%b %d, %Y')"

    if [[ "$THREATS_FOUND" -gt 0 ]]; then
        SUBJECT="*** SECURITY ALERT *** $SUBJECT"
    fi

    {
        echo "To: $REPORT_EMAIL"
        echo "From: pi@$(hostname)"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/plain; charset=utf-8"
        echo ""
        cat "$REPORT_FILE"
    } | msmtp "$REPORT_EMAIL" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_line "Report emailed to $REPORT_EMAIL"
    else
        log_line "WARNING: Email send failed. Report saved locally at $REPORT_FILE"
    fi
else
    log_line "Email not configured. Report saved locally at $REPORT_FILE"
fi

log_line "Maintenance run completed"
echo "Report saved: $REPORT_FILE"
