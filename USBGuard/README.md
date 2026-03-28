# USBGuard

USB device authorization for Raspberry Pi — blocks unauthorized USB devices at the kernel level before they can do anything.

Defends against BadUSB and RubberDucky style attacks where a malicious device presents itself as a keyboard or other trusted device type and injects commands or installs malware.

## The Problem

A Raspberry Pi Zero, a RubberDucky, or any number of inexpensive devices can be configured to present themselves to a computer as a keyboard. When plugged in they are immediately trusted by the OS and can begin typing commands — installing malware, opening backdoors, exfiltrating data — faster than you can unplug them.

Logging the insertion (as USBsentry does) is not enough. By the time the log entry is written the attack may already be complete.

## The Solution

USBGuard intercepts every USB device insertion at the kernel level **before** the OS allows it to function. Devices not on the authorized list are blocked entirely — they cannot type, cannot mount, cannot do anything. A Pi Zero presenting as a keyboard after setup is blocked before it can send a single keystroke.

## How Authorization Works

At setup time USBGuard scans currently connected devices and generates an authorization policy — your whitelist. Every device connected at that moment is authorized. Everything else is blocked by default.

When you plug in a new legitimate device (a new thumb drive, a keyboard) it appears as blocked. You authorize it explicitly with one command. You can make that authorization permanent or one-time.

## Installation

On your Raspberry Pi, open a terminal and run:

```bash
wget https://raw.githubusercontent.com/phoggbergActual/Tools/main/USBGuard/setup_usbguard.sh
cat setup_usbguard.sh
sudo bash setup_usbguard.sh
```

**Always read a script before running it with sudo. Even this one.**

## Managing New Devices

When you plug in a new USB device after setup and it does not work:

```bash
# See what is blocked
sudo usbguard list-devices

# Allow a device temporarily (this session only)
sudo usbguard allow-device DEVICE_ID

# Allow a device permanently (survives reboot)
sudo usbguard allow-device -p DEVICE_ID
```

The setup script installs a helper alias so you can just type:

```bash
usb-allow          # lists blocked devices and lets you authorize one
```

## Works Best With USBsentry

USBGuard blocks unauthorized devices. USBsentry scans authorized mass storage devices for infected files. Together they cover both attack vectors:

- Malicious device pretending to be a keyboard → USBGuard blocks it
- Legitimate thumb drive with infected files → USBsentry catches it

## Files

| File | Purpose |
|------|---------|
| `setup_usbguard.sh` | One-time setup — run this |
| `usbguard_helper.sh` | Helper script for managing device authorization |

## Requirements

- Raspberry Pi OS (tested on Pi 5)
- Internet connection for package installation
- Run setup when all your normal USB devices are connected
