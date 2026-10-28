---
format: hhc-findings/1
module: pi-health-check
module_version: 0.4.0
checked_at: 2026-02-01T10:00:00+01:00
device:
  mac: b8:27:eb:00:00:00
  name: pihole
  type: DNS server
summary: The OS is out of support and updates are pending.
findings:
  - id: os-out-of-support
    severity: high
    subject: null
    title: OS release no longer gets security updates
    detail: Raspberry Pi OS 11 has left security support.
    action: Reinstall onto the current Raspberry Pi OS release
    effort: 1-2 h
  - id: updates-pending
    severity: medium
    subject: null
    title: 8 package updates pending
    detail: apt lists 8 upgradable packages.
    action: Install the updates
    effort: 10 min
not_checked: []
---
# Raspberry Pi health check: pihole (February)
