---
name: home-inventory
description: Discover and keep a local inventory of the devices on the user's home network (IP, MAC, vendor, name, type, open services), and report new, missing or changed devices since the last scan. Use when the user asks what is on their network, wants an inventory or device list, asks about an unknown device, or before another health check needs to know which devices exist.
summary: Finds every device on your home network, keeps a private inventory, and tells you what is new or gone.
version: 0.3.0
tags: [home-network, inventory, network-scan, security, home-lab]
keywords: [network devices, ip scanner, mac vendor, arp, unknown device, home lab]
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
- **The inventory is private.** It lives only on the user's computer in `~/.home-health-check/inventory.md` (Windows: `%USERPROFILE%\.home-health-check\inventory.md`). Never put it in a git repository, an artifact or anything shared.
- **Don't guess identities as facts.** Mark what is inferred ("probably a phone: private MAC, no open ports") and ask the user to name what you can't tell.

## 1. Discover

On Windows (no admin needed):

Run the bundled script `scripts/discover.ps1` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-this-skill>/scripts/discover.ps1" -Ports -Oui
```

- `-Ports` checks ~18 well-known ports per device (ssh, http, smb, printer, Sonos, Chromecast, Home Assistant, Plex ...) and reads the device description from Sonos and Chromecast devices.
- `-Oui` maps MAC addresses to vendors with Wireshark's public vendor list (downloaded once, refreshed every 90 days). Ask before the first download if the user is sensitive about network access; only the list is fetched, no device data is sent.
- `-Json` gives machine-readable output.

On macOS/Linux use what is available: `arp -a` after a ping sweep (`nmap -sn <subnet>` if nmap is installed), `avahi-browse -art` or `dns-sd -B _services._dns-sd._udp` for mDNS names, and `nc -zv -w1` for single ports.

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

The pi-health-check, router-health-check and windows-health-check skills read this file when it exists: to find the Pi's address, to judge whether every device uses the intended DNS server, and to spot devices that belong on a guest or IoT network.

They also write back what they learn: the router check adds client names, mesh node models and firmware, and reservations; the Pi and Windows checks fill in their own host's role, OS and model. All of them match on MAC and leave the user's own names and notes alone unless the user agrees. When you rescan, keep everything they added.
