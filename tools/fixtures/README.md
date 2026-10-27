# Test fixtures

Anonymized samples of command output, used by the shell tests in `tools/tests/` (run `bash tools/test-sh.sh`). Every value is a placeholder: MACs end in `00:00:00`, IPs are `192.168.1.x`, names are generic, serial numbers and UUIDs are `XXXX`. Do not add raw captures; anonymize them first. `tools/check-skills.ps1` scans this folder for personal data.

The shapes come from real runs on a MacBook Pro with macOS 26 and on a Raspberry Pi, except the synthetic files below, which follow the real formats:

- `macos/`: `softwareupdate-none`, `sp-power-desktop`, `netstat-listen` (loopback-only sharing port added), `codesign-appstore`, `codesign-adhoc`, `codesign-unsigned`, `tmutil-latest`, `dnssd-ptr` (a successful lookup added), `arp-an` (extra lines for incomplete, broadcast, other interface)
- `linux/`: `arp-an` (net-tools is not installed on a stock Pi OS), `nmcli-dhcp4`, and the `FAILED`, `INCOMPLETE`, `DELAY`, `PROBE` and `PERMANENT` rows of `ip-neigh`
- `upnp/`: all four files (standard UPnP IGD, SOAP and Sonos shapes)
- `manuf-sample.txt`: four lines in the Wireshark `manuf` format
