# home-health-check

A Claude Code plugin that lets Claude health-check the devices in your home: a Raspberry Pi or Linux server, your router or mesh Wi-Fi, and your Windows PC. Claude collects facts with read-only scripts, explains what is good and what isn't, and gives you a prioritized fix list. Nothing is changed without your yes, and Claude never handles your passwords.

| Skill | Checks |
|---|---|
| `pi-health-check` | Raspberry Pi / Debian-based Linux over SSH: OS support status, updates, SD card and power health, SSH and sudo, services and ports, static IP, Pi-hole, unbound/cloudflared, backups |
| `router-health-check` | Home router or mesh from a PC on the LAN: model and firmware, open ports, UPnP mappings, Wi-Fi security, DHCP and DNS path (incl. Pi-hole bypass), IPv6, double NAT, latency, devices |
| `windows-health-check` | Windows 10/11: updates, BIOS, Defender, firewall, Secure Boot, BitLocker, disks, crashes and log errors, backup, startup programs, outdated apps |

## Requirements

- [Claude Code](https://code.claude.com) in a terminal or the Code tab of the Claude desktop app. It has to run on a computer on your home network. Claude in a browser can't reach your devices.
- For the Pi check: SSH key login to the Pi.
- The router and Windows probes are PowerShell scripts. On macOS/Linux, Claude runs equivalent commands instead.

## Install

```bash
claude plugin marketplace add Flunker-cmd/home-health-check
claude plugin install home-health-check@flunker
```

Then start Claude Code and ask, for example:

- "Do a health check of my Raspberry Pi at 192.168.1.10"
- "Check my router and Wi-Fi settings"
- "Health check this PC"

or call a skill directly: `/home-health-check:pi-health-check`.

## How a check works

1. **Collect:** a read-only script gathers facts (no admin, `sudo -n` only, no password prompts).
2. **Assess:** Claude goes through each area and looks up current versions, support dates and security advisories online.
3. **Report:** facts, assessment, what Claude needs from you (e.g. screenshots from a router app), and a prioritized action list with exact steps.
4. **Fix (optional):** Claude carries out the fixes you approve, one at a time, and verifies each one.

The reports describe your network and devices. Keep them to yourself.

## Repository layout

```
.claude-plugin/marketplace.json        marketplace "flunker"
plugins/home-health-check/
  .claude-plugin/plugin.json
  skills/<skill>/SKILL.md              instructions for Claude
  skills/<skill>/scripts/              read-only collectors
```

Validate after changes:

```bash
claude plugin validate .
```

## License

[MIT](LICENSE)
