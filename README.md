# Tools

A collection of security and maintenance scripts for Raspberry Pi.

Each tool is self-contained in its own directory with a setup script, documentation, and all required files. Read every script before running it.

---

## USBsentry

Automatic USB device scanning using ClamAV. Scans any USB mass storage device before the OS mounts it. If a threat is found the device is mounted read-only and you are notified.

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBsentry/setup_usbsentry.sh
cat setup_usbsentry.sh
sudo bash setup_usbsentry.sh
```

[USBsentry documentation](USBsentry/README.md)

---

## USBGuard

USB device authorization at the kernel level. Blocks any device not on your authorized list before it can function — defends against BadUSB and RubberDucky style attacks where a malicious device presents as a keyboard and injects commands.

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBGuard/setup_usbguard.sh
cat setup_usbguard.sh
sudo bash setup_usbguard.sh
```

[USBGuard documentation](USBGuard/README.md)

---

## PiMaintain

Biweekly automated maintenance. Updates the OS, updates ClamAV virus definitions, scans all filesystems, and emails a plain-text report to your address. Runs automatically on the 1st and 15th of each month at 2am.

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/PiMaintain/setup_pimaintain.sh
cat setup_pimaintain.sh
sudo bash setup_pimaintain.sh your.email@gmail.com
```

[PiMaintain documentation](PiMaintain/README.md)

---

## Recommended Setup Order

1. **USBGuard** first — blocks unauthorized devices before anything else runs
2. **USBsentry** second — scans authorized drives for infected files
3. **PiMaintain** third — keeps everything current and reports to you

## Requirements

- Raspberry Pi OS (developed and tested on Pi 5)
- Internet connection for package installation
- Gmail account with App Password for PiMaintain report delivery

## Note

These scripts have been syntax-checked. Full functional testing requires a Raspberry Pi. Read all scripts before running. All setup scripts require root — run with sudo.
