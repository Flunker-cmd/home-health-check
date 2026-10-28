---
format: hhc-findings/1
module: pi-health-check
module_version: 0.4.0
checked_at: @TODAY@T@CLOCK@:00+01:00
device:
  mac: b8:27:eb:00:00:00
  name: pihole
  type: DNS server
summary: Pi-hole works, but the OS is out of support and nothing is backed up.
findings:
  - id: os-out-of-support
    severity: high
    subject: null
    title: OS release no longer gets security updates
    detail: Raspberry Pi OS 11 has left security support.
    action: Reinstall onto the current Raspberry Pi OS release
    effort: 1-2 h
  - id: no-backup
    severity: high
    subject: null
    title: No backup of the Pi-hole configuration
    detail: No Teleporter export and no SD card image were found.
    action: Export a Teleporter backup and keep it off the Pi
    effort: 30 min
  - id: updates-pending
    severity: medium
    subject: null
    title: 12 package updates pending
    detail: apt lists 12 upgradable packages.
    action: Install the updates
    effort: 10 min
not_checked:
  - area: SMART data
    reason: needs passwordless sudo
---
# Raspberry Pi health check: pihole

Pi-hole answers DNS for the network. The OS release is out of support, there is no backup, and 12 updates are pending.
