# Test fixtures

Anonymized samples of command output, used by the shell tests in `tools/tests/` (run `bash tools/test-sh.sh`). Every value is a placeholder: MACs end in `00:00:00`, IPs are `192.168.1.x`, names are generic, serial numbers and UUIDs are `XXXX`. Do not add raw captures; anonymize them first. `tools/check-skills.ps1` scans this folder for personal data.

The shapes come from real runs on a MacBook Pro with macOS 26 and on a Raspberry Pi, except the synthetic files below, which follow the real formats:

- `macos/`: `softwareupdate-none`, `sp-power-desktop`, `netstat-listen` (loopback-only sharing port added), `codesign-appstore`, `codesign-adhoc`, `codesign-unsigned`, `tmutil-latest`, `dnssd-ptr` (a successful lookup added), `arp-an` (extra lines for incomplete, broadcast, other interface)
- `linux/`: `arp-an` (net-tools is not installed on a stock Pi OS), `nmcli-dhcp4`, and the `FAILED`, `INCOMPLETE`, `DELAY`, `PROBE` and `PERMANENT` rows of `ip-neigh`
- `upnp/`: all four files (standard UPnP IGD, SOAP and Sonos shapes)
- `manuf-sample.txt`: four lines in the Wireshark `manuf` format

## homey/

Saved Homey Pro (Early 2023) API responses, in the layout `--from-dir`/`-FromDir` reads (see the file list in the collector's `--help`). The shapes and field names come from a real Homey Pro; every value is synthetic: names are generic, IDs are made-up UUIDs, `cloudId` and `hostname` are `REDACTED`, lists are cut to a handful of items that cover each output rule. Timestamps are relative to the fixed clock `--now 2026-10-28T12:00Z`. `expected.txt` is the collector output for this folder at that clock, written by hand from the rules; both collectors must produce it byte for byte.

Synthetic wording (real wording unknown): the successful backup notice, and the app states `crashed` and `stopped`. The failed backup notice is the real wording.

Canaries that must never appear in output: `CANARY-KEY` (a presence notice that also says `offline`), `CANARY-LASTVALUE` (`lastValue` of a logic log in `insights-logs.json`), `CANARY-SSID` (`wifiSsid`), `CANARY-ZWAVE` (`zw_state.expandedNetworkKeys` in `zwave.json`).

Radio fields the collectors read (exact names from the real Homey):

- `zigbee.json`: `zigbee_ready` (bool), `zigbee_error` (null or text), `nodes` (object keyed by IEEE address; each node has `type`: `router`, `enddevice` or `coordinator`). Node count = entries whose `type` is not `coordinator`.
- `zwave.json`: `zw_ready`, `zw_error`, and under `zw_state`: `nodes` (array of node ids, includes the controller), `nodeId` (the controller's own id), `noAckNodes` (array of node ids). Node count = `zw_state.nodes` without `zw_state.nodeId`; no_ack = length of `zw_state.noAckNodes`.
