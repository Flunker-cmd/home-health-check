---
format: hhc-findings/1
module: windows-health-check
module_version: 0.4.0
checked_at: @TODAY@T@CLOCK@:00+01:00
device:
  mac: unknown
  name: LAPTOP-2
  type: Windows PC
summary: Real-time protection is off.
findings:
  - id: defender-off
    severity: high
    subject: null
    title: Defender real-time protection is off
    detail: No other antivirus is registered.
    action: Turn real-time protection back on
    effort: 15 min
not_checked: []
---
# Windows PC health check: LAPTOP-2
