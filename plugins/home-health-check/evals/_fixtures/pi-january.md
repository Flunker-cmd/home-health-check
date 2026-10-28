---
format: hhc-findings/1
module: pi-health-check
module_version: 0.3.0
checked_at: 2026-01-05T10:00:00+01:00
device:
  mac: b8:27:eb:00:00:00
  name: pihole
  type: DNS server
summary: The OS is out of support and SSH accepts passwords.
findings:
  - id: os-out-of-support
    severity: high
    subject: null
    title: OS release no longer gets security updates
    detail: Raspberry Pi OS 11 has left security support.
    action: Reinstall onto the current Raspberry Pi OS release
    effort: 1-2 h
  - id: ssh-password-login
    severity: medium
    subject: null
    title: SSH accepts password logins
    detail: PasswordAuthentication is yes.
    action: Turn off password login after setting up keys
    effort: 15 min
not_checked: []
---
# Raspberry Pi health check: pihole (January)
