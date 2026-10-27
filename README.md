# home-health-check

A Claude Code plugin that lets Claude map and health-check the devices in your home: a Raspberry Pi or Linux server, your router or mesh Wi-Fi, and your Windows PC. Claude collects facts with read-only scripts, explains what is good and what isn't, and gives you a prioritized fix list. Nothing is changed without your yes, and Claude never handles your passwords.

| Skill | Does |
|---|---|
| `home-inventory` | Finds the devices on your network (IP, MAC, vendor, name, open services), keeps a private inventory on your computer, and tells you what is new or gone since last time |
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

- "What's on my network?"
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

**Inventory:** run `home-inventory` first and the other checks use its result, and add what they learn to it (names from the router's client list, firmware of mesh nodes, the role and OS of a Pi). Names you give devices yourself are kept. It is stored only on your computer, in your data folder (see *Shared data and findings* below).

**Router admin pages:** if your router has a web UI, the router check can read it in Claude's browser (the desktop app's built-in browser or Claude in Chrome). You sign in yourself, Claude only reads and never clicks save or apply. App-only mesh systems such as TP-Link Deco or Eero show little on the web, so there Claude asks for screenshots from the app instead.

## Shared data and findings

All skills share one private data folder on your computer: `~/.home-health-check` (Windows: `%USERPROFILE%\.home-health-check`), or the folder named by the `HOME_HEALTH_CHECK_DIR` environment variable.

```
inventory.md   the device list from home-inventory
findings/      one file per check run, in a documented format (hhc-findings/1)
reports/       reserved for a report skill
cache/         downloaded helper data, e.g. the MAC vendor list
```

Every check works alone and gives its full report in chat. When the data folder exists it also saves its findings there, so a report can combine several checks into one list. The format is described in [findings-format.md](plugins/home-health-check/shared/findings-format.md).

- **Several computers:** point `HOME_HEALTH_CHECK_DIR` at a folder you sync between your own computers and all checks land in one place. Mind that the inventory and findings then sit in that cloud. Or leave the folder local and copy a findings file by hand to the computer that keeps the inventory.
- **Privacy:** everything in the data folder describes your home. Never put it in a repository or share it.

## Other agents and Agensi

The skills are plain `SKILL.md` files with read-only scripts, so they also work in other agents that support skills (Cursor, Copilot, Codex and others) and when an agent delivers a skill as text without a folder: the agent writes the script to a temporary file, runs it and deletes it. Each skill lists the network calls and permissions it uses under *Network and permissions*.

`agensi/` holds what is specific to listing the skills on [Agensi](https://www.agensi.io): the listing texts and a script that builds the upload ZIPs from the same skill files (`agensi/package.ps1 -OutDir <folder outside the repo>`). There are no separate copies of the skills.

## Repository layout

```
.claude-plugin/marketplace.json        marketplace "flunker"
plugins/home-health-check/
  .claude-plugin/plugin.json
  shared/findings-format.md            the findings contract (source of the copies below)
  skills/<skill>/SKILL.md              instructions for the agent
  skills/<skill>/references/           copy of the findings contract
  skills/<skill>/scripts/              read-only collectors
tools/                                 check-skills.ps1, sync-contract.ps1, test-package.ps1
agensi/                                Agensi listing texts and packaging script
docs/superpowers/                      design and implementation plans
```

Validate after changes:

```bash
claude plugin validate .
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-skills.ps1
```

## License

[MIT](LICENSE)
