---
format: hhc-findings/1
module: windows-health-check
module_version: 0.4.0
checked_at: @TODAY@T@CLOCK@:00+01:00
device:
  mac: bc:fc:e7:00:00:00
  name: desktop
  type: Windows PC
summary: Up to date, but the system drive is not encrypted.
findings:
  - id: bitlocker-off
    severity: high
    subject: null
    title: System drive is not encrypted
    detail: BitLocker is off on C:.
    action: Turn on BitLocker and save the recovery key
    effort: 20 min
  - id: apps-outdated
    severity: low
    subject: null
    title: 4 apps have updates
    detail: winget lists 4 upgrades.
    action: Update the apps
    effort: 15 min
not_checked:
  - area: BitLocker recovery key backup
    reason: needs admin
---
# Windows PC health check: desktop
