# Home Health Check Pack

Let your AI agent map and health-check your home: the devices on your network, a Raspberry Pi or Linux server, your router or mesh Wi-Fi, your Windows PC and your Mac. Each check runs a read-only script, explains what is fine and what is not, and ends with a prioritized fix list. Nothing is changed without your yes, and the agent never handles your passwords.

| Skill | Does |
|---|---|
| `home-inventory` | Finds the devices on your network, keeps a private inventory on your computer, tells you what is new or gone since last time |
| `pi-health-check` | Raspberry Pi / Debian-based Linux over SSH: OS support, updates, SD card and power health, SSH and sudo, services, Pi-hole, backups |
| `router-health-check` | Router or mesh from a PC on the LAN: firmware, open ports, UPnP, Wi-Fi security, DNS path, double NAT, latency |
| `windows-health-check` | Windows 10/11: updates, BIOS, Defender, firewall, Secure Boot, BitLocker, disks, crashes, backup, startup programs |
| `macos-health-check` | macOS: version and support, updates, FileVault, SIP, Gatekeeper, firewall, XProtect, sharing, Time Machine, disk, battery, startup items, crashes and panics. No sudo, no permission dialogs |
| `home-network-report` | One prioritized report for the whole home from the inventory and every check's findings: what to fix first, a red/yellow/green overview per device, what changed |

The skills work on their own and share one private data folder on your computer (inventory and findings). Everything stays on your machine. Details are in each skill's `references/findings-format.md`.

Open source (MIT): https://github.com/Flunker-cmd/home-health-check
