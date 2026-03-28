# USBsentry

Automatic USB device scanning for Raspberry Pi using ClamAV.

Scans any USB mass storage device **before** the OS mounts it. If a threat is found the device is mounted read-only and you are notified. Also detects unexpected HID device insertions after boot — the BadUSB/RubberDucky attack vector where a malicious device presents as a keyboard and injects commands.

## Installation

On your Raspberry Pi, open a terminal and run:

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBsentry/setup_usbsentry.sh
cat setup_usbsentry.sh
sudo bash setup_usbsentry.sh
```

**Always read a script before running it with sudo. Even this one.**

## What It Does

- Installs ClamAV and clamav-daemon
- Updates ClamAV virus definitions
- Installs a udev rule that fires when a USB block device is inserted
- Installs a systemd service that runs the scan before mount
- If **clean**: normal mount proceeds
- If **threat found**: device mounted read-only, desktop notification sent, alert logged
- If **unexpected HID device** (keyboard/input device inserted after boot): logs a warning — possible BadUSB/RubberDucky attack

## Files

| File | Purpose |
|------|---------|
| `setup_usbsentry.sh` | One-time setup — run this |
| `usb_scan.sh` | Scanner — called automatically by systemd |
| `99-usb-scan.rules` | udev rule — triggers scan on USB insertion |
| `usb-scan@.service` | systemd service — runs the scanner |

## Logs

```bash
cat /var/log/usb_scan.log        # all scan events
cat ~/usb_scan_alerts.log        # threats found
```

## Testing ClamAV

The setup script tests using the EICAR test file — a harmless 68-byte industry-standard string that every antivirus engine flags as a test virus. It contains no malware.

## Requirements

- Raspberry Pi OS (tested on Pi 5)
- Internet connection for package installation
- ClamAV (installed automatically by setup script)

## Note

These scripts have been syntax-checked but require a Raspberry Pi for full functional testing. Read all scripts before running. Run setup as root with sudo.
