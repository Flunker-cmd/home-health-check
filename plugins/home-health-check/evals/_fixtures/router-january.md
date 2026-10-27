---
format: hhc-findings/1
module: router-health-check
module_version: 0.4.0
checked_at: 2026-01-05T10:00:00+01:00
device:
  mac: 30:68:93:00:00:00
  name: deco-main
  type: Router (mesh)
summary: Firmware is current; WPS is on.
findings:
  - id: wps-on
    severity: medium
    subject: null
    title: WPS is enabled
    detail: The app shows WPS on for the main network.
    action: Turn WPS off in the app
    effort: 5 min
not_checked: []
---
# Router health check: deco-main
