---
format: hhc-findings/1
module: router-health-check
module_version: 0.4.0
checked_at: @TODAY@T@CLOCK@:00+01:00
device:
  mac: 30:68:93:00:00:00
  name: deco-main
  type: Router (mesh)
summary: Firmware is current; WPS is on and the line is double NATed.
findings:
  - id: wps-on
    severity: medium
    subject: null
    title: WPS is enabled
    detail: The app shows WPS on for the main network.
    action: Turn WPS off in the app
    effort: 5 min
  - id: double-nat
    severity: low
    subject: null
    title: Double NAT
    detail: The second hop is a private address.
    action: Put the ISP modem in bridge mode if port forwarding is needed
    effort: 1 h
not_checked: []
---
# Router health check: deco-main
