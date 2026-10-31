# Agensi listings

Texts for the Agensi upload form. This file is not shipped in the ZIPs. Every listing links to the GitHub repo. Only describe what is built: modules that are not built yet go under "Coming" and nowhere else.

Repo: https://github.com/Flunker-cmd/home-health-check

## Listing 1: home-inventory (free)

- **Title:** Home Network Inventory
- **Summary:** Find every device on your home network and keep a private list of what is new or gone.
- **Description:** Actively scans your local network with pings and checks of well-known ports (no admin rights), and changes nothing on any device. On first use it downloads Wireshark's public MAC vendor list from wireshark.org and refreshes it every 90 days; no device data leaves your LAN. It identifies devices by vendor, open services and what they announce about themselves, and keeps a private inventory on your own computer. On every run it tells you which devices are new, which disappeared and which changed address. The other Home Health Check skills read this inventory. Open source (MIT): the repo link above. Windows, macOS and Linux.
- **Tags:** home-network, inventory, network-scan, security, home-lab
- **Price note:** Free. Entry point to the pack.

## Listing 2: Home Health Check Pack (paid)

- **Title:** Home Health Check Pack
- **Summary:** Read-only health checks for your Raspberry Pi or Linux box, router or mesh Wi-Fi, Windows PC, Mac and Homey Pro, each with a prioritized fix list.
- **Description:** Seven skills that share one private data folder. The six checks work alone; the report combines what they found. `home-inventory` maps your network. `pi-health-check` checks a Raspberry Pi or Debian-based server over SSH, Pi-hole aware. `router-health-check` checks your router or mesh from the LAN: firmware, open ports, UPnP, Wi-Fi security, DNS path, double NAT. `windows-health-check` checks a Windows 10/11 PC without admin rights. `macos-health-check` checks a Mac without sudo and without permission dialogs. `homey-health-check` checks a Homey Pro through its local API with a read-only key you create: firmware, apps, restarts and outages, offline or stale devices, batteries, broken flows, Zigbee and Z-Wave, backup notices; tested on Homey Pro (Early 2023), Homey Bridge and Homey Cloud are not supported. The inventory and router checks run on Windows, macOS and Linux. `home-network-report` combines the inventory and every check into one prioritized report for the whole home, with what changed since last time. Every check ends with a prioritized fix list with exact steps, and every script is read-only: the inventory and router checks actively ping and port-check your LAN, but change nothing. Each skill lists the network calls and permissions it uses. Open source (MIT): the repo link above.
- **Tags:** home-lab, raspberry-pi, router, windows, macos, homey, smart-home, security, health-check, report
- **Price note:** one-time, 3-5 USD. The author sets the final price on Agensi.

## Coming (do not put in a listing until built)

- Nothing at the moment.
