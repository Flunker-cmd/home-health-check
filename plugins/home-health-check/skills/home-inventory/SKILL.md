---
name: home-inventory
description: Discover and keep a local inventory of the devices on the user's home network (IP, MAC, vendor, name, type, open services), and report new, missing or changed devices since the last scan. Use when the user asks what is on their network, wants an inventory or device list, asks about an unknown device, or before another health check needs to know which devices exist.
summary: Finds every device on your home network, keeps a private inventory, and tells you what is new or gone.
version: 0.5.2
tags: [home-network, inventory, network-scan, security, home-lab]
keywords: [network devices, ip scanner, mac vendor, arp, unknown device, home lab, macos, linux]
use_cases:
  - See what is connected to my home network
  - Spot a device I do not recognize
  - Keep a device list the other health checks can use
docs_url: https://github.com/Flunker-cmd/home-health-check
---

# Home network inventory

Find the devices on the local network, identify them as far as possible, and keep the result in a local inventory file so later checks can compare. Answer in the user's language.

## Ground rules

- **Only the user's own LAN.** A ping sweep of the local subnet and a handful of well-known TCP ports per device is fine. No scanning of other networks, no aggressive or broad port scans, no login attempts.
- **The inventory is private.** It lives only on the user's computer in `<data dir>/inventory.md`. `<data dir>` is defined in `references/findings-format.md` (the `HOME_HEALTH_CHECK_DIR` environment variable, or the default folder in the user's home directory named there). Never put it in a git repository, an artifact or anything shared.
- **Don't guess identities as facts.** Mark what is inferred ("probably a phone: private MAC, no open ports") and ask the user to name what you can't tell.

## 1. Discover

On Windows (no admin needed):

Run the bundled script `scripts/discover.ps1` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-this-skill>/scripts/discover.ps1" -Ports -Oui
```

On macOS or Linux (no sudo needed):

Run the bundled script `scripts/discover.sh` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards.

```bash
bash "<path-to-this-skill>/scripts/discover.sh" --ports --oui
```

It prints the same table, or the same JSON, as the Windows script, so steps 2 and 3 do not care which one ran. It needs only tools that ship with macOS and Debian-based Linux (`ping`, `arp` or `ip neigh`, `curl`, `nc` and `perl` for the UPnP discovery); anything missing is skipped. On macOS 15 and later, if your agent runs inside an app (an editor or a desktop app) instead of Terminal, macOS asks once whether that app may find devices on the local network. Tell the user before the first scan, and ask them to allow it; running in Terminal or over SSH needs no permission. If no device replies on macOS, the dialog was probably refused: the script prints a hint (on stderr with `--json`). The dialog can also appear while the scan is already running, and the pings sent before the user clicks Allow fail, so run the scan again after they allowed it.

- `-Ports` / `--ports` checks ~18 well-known ports per device (ssh, http, smb, printer, Sonos, Chromecast, Home Assistant, Plex ...) and reads the device description from Sonos and Chromecast devices.
- `-Oui` / `--oui` maps MAC addresses to vendors with Wireshark's public vendor list (downloaded once, refreshed every 90 days). Ask before the first download if the user is sensitive about network access; only the list is fetched, no device data is sent.
- `-Json` / `--json` gives machine-readable output.

If a Raspberry Pi or Linux server with SSH is on the network, it can add more: `avahi-browse -artp` there (if `avahi-utils` is installed) lists mDNS names that Windows can't see, and **Pi-hole** knows which clients make DNS queries:
`sudo pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db "select client, count(*) from queries where timestamp > strftime('%s','now')-86400 group by client"`.

## 2. Identify

For each device, combine the evidence into a type and a best-guess name:

- **Vendor** (Espressif = ESP32/ESP8266 smart plug or sensor, Raspberry Pi Foundation, Sonos, Google = Chromecast/Nest, TP-Link = router/mesh node/plug, Athom = Homey, Seiko Epson = printer ...).
- **Private MAC** (`rnd` = yes): almost always a phone, tablet or laptop with MAC randomization. It can change per network or over time, so track these loosely.
- **Open ports and UPnP description**, which often give the exact model and the name the user gave the device.
- **The router's client list** (the user can screenshot it from the router app) has the names devices announce over DHCP.

Ask the user about anything still unknown, in one short list.

## 3. Save and compare

Read the existing inventory first if there is one. Then write it back in this format, keeping the user's own names and notes:

```markdown
# Home network inventory

Network: 192.168.1.0/24, gateway 192.168.1.1. Last scan: 2026-10-26 09:00.

| IP | MAC | Vendor | Name | Type | Services | First seen | Last seen | Notes |
|---|---|---|---|---|---|---|---|---|
| 192.168.1.10 | b8:27:eb:.. | Raspberry Pi Foundation | pihole | DNS server | ssh, dns, http(s) | 2026-10-26 | 2026-10-26 | static IP |
```

- Match devices by **MAC** (IP addresses change). For private MACs, match on name/type and accept some churn.
- Keep devices that weren't seen this time; just leave their *Last seen* date. Note devices that haven't been seen for a long time and ask whether to remove them.
- Report the changes since the last scan: **new devices** (the important part: does the user recognize them?), devices that disappeared, changed IPs, newly opened services.

## 4. Use by other checks

The pi-health-check, router-health-check, windows-health-check and macos-health-check skills read this file when it exists: to find the Pi's address, to judge whether every device uses the intended DNS server, and to spot devices that belong on a guest or IoT network.

They also write back what they learn: the router check adds client names, mesh node models and firmware, and reservations; the Pi, Windows and Mac checks fill in their own host's role, OS and model. All of them match on MAC and leave the user's own names and notes alone unless the user agrees. When you rescan, keep everything they added.

The checks also save their findings as files in `<data dir>/findings/` (format in `references/findings-format.md`). The home-network-report skill reads the inventory and those findings together and writes one prioritized report for the whole home to `<data dir>/reports/`. This skill does not write findings itself.

## Network and permissions

- **Network:** only the user's own LAN. A ping sweep of the local subnet (never more than 1024 addresses), reverse DNS lookups of local addresses, an SSDP discovery multicast, HTTP requests to the device descriptions that local devices announce (and to the well-known Sonos and Chromecast description URLs), and, with `-Ports`, TCP connections to about 18 well-known ports per device. With `-Oui` it downloads Wireshark's public MAC vendor list once from `https://www.wireshark.org/download/automated/data/manuf` and refreshes it after 90 days; no device data is sent. Ask the user first if they are sensitive about network access.
- **Network, macOS and Linux:** `discover.sh` makes the same kinds of requests as the Windows script: a ping sweep of the local subnet (never more than 1024 addresses), reverse DNS lookups (`host` or `getent`), mDNS name lookups (`dns-sd` on macOS, `avahi-resolve` on Linux if installed), an SSDP discovery multicast sent by `perl` if installed, HTTP requests to the device descriptions that local devices announce, TCP connections with `nc` or bash `/dev/tcp` with `--ports`, and with `--oui` the same single download of the Wireshark vendor list with `curl`. Local devices cannot make it fetch other hosts: it only requests a description from the address that announced it.
- **Rights:** no admin rights, and no sudo on macOS or Linux. `-ExecutionPolicy Bypass` applies to that one PowerShell process only, so the local unsigned script can run; it changes no system setting. On macOS 15 and later the first scan from inside an app asks for Local Network access for that app (an operating system dialog, once); Terminal and SSH are exempt.
- **Files:** the scripts write only `<data dir>/cache/manuf.txt` (with `-Oui` / `--oui`), plus a temporary folder that `discover.sh` deletes when it ends. The skill writes `<data dir>/inventory.md`.
