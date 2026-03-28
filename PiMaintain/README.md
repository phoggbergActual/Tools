# PiMaintain

Biweekly automated maintenance for Raspberry Pi — system updates, virus scan, and email report.

Runs automatically on the 1st and 15th of each month at 2am. Updates the OS, updates ClamAV virus definitions, scans all filesystems, and emails a plain-text report to your address.

## Installation

On your Raspberry Pi, open a terminal and run:

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/PiMaintain/setup_pimaintain.sh
cat setup_pimaintain.sh
sudo bash setup_pimaintain.sh your.email@gmail.com
```

Replace `your.email@gmail.com` with your actual email address.

**Always read a script before running it with sudo. Even this one.**

## Gmail App Password

You need a Google App Password — not your main Gmail password.

1. Go to myaccount.google.com
2. Security → 2-Step Verification → App Passwords
3. Create one for Mail on Linux device
4. You will be prompted for it during setup

## What the Report Contains

- List of packages updated
- ClamAV definition update result
- Full filesystem scan results
- Summary: files scanned, threats found
- Reboot required notice (if kernel was updated)

Subject line is prefixed with `*** SECURITY ALERT ***` if any threats are found.

## Files

| File | Purpose |
|------|---------|
| `setup_pimaintain.sh` | One-time setup — run this with your email address as $1 |
| `maintenance.sh` | Maintenance script — called by cron, takes email as $1 |

## Running Manually

```bash
sudo /usr/local/bin/maintenance.sh your.email@gmail.com
```

## Logs

```bash
ls ~/logs/                           # maintenance reports
cat /var/log/maintenance.log         # system summary log
```

## Requirements

- Raspberry Pi OS (tested on Pi 5)
- Internet connection
- Gmail account with App Password enabled
- ClamAV (installed automatically)
- msmtp (installed automatically)
