---
format: hhc-findings/1
module: macos-health-check
module_version: 0.4.0
checked_at: @TODAY@T@CLOCK@:00+01:00
device:
  mac: 6e:11:22:00:00:00
  name: macbook
  type: Mac
summary: FileVault is on; the firewall is off and two updates are pending.
findings:
  - id: firewall-off
    severity: medium
    subject: null
    title: The application firewall is off
    detail: socketfilterfw reports state 0.
    action: Turn on the firewall in System Settings > Network > Firewall
    effort: 5 min
  - id: updates-pending
    severity: medium
    subject: null
    title: 2 updates pending
    detail: softwareupdate lists Safari and a macOS point release.
    action: Install the updates
    effort: 20 min
not_checked:
  - area: login items
    reason: needs admin
---
# macOS health check: macbook
