# Agensi listings

Texts for the Agensi upload form. This file is not shipped in the ZIPs. Every listing links to the GitHub repo. Only describe what is built: macOS, the home report and Homey go under "Coming" and nowhere else.

Repo: https://github.com/Flunker-cmd/home-health-check

## Listing 1: home-inventory (free)

- **Title:** Home Network Inventory
- **Summary:** Find every device on your home network and keep a private list of what is new or gone.
- **Description:** Sweeps your local network (no admin rights; the only download is the public MAC vendor list, and no device data leaves your LAN), identifies devices by vendor, open services and what they announce about themselves, and keeps a private inventory on your own computer. On every run it tells you which devices are new, which disappeared and which changed address. The other Home Health Check skills read this inventory. Open source (MIT): the repo link above. Windows, macOS and Linux.
- **Tags:** home-network, inventory, network-scan, security, home-lab
- **Price note:** Free. Entry point to the pack.

## Listing 2: Home Health Check Pack (paid)

- **Title:** Home Health Check Pack
- **Summary:** Read-only health checks for your Raspberry Pi or Linux box, router or mesh Wi-Fi, Windows PC and Mac, each with a prioritized fix list.
- **Description:** Five skills that work alone and share one private data folder. `home-inventory` maps your network. `pi-health-check` checks a Raspberry Pi or Debian-based server over SSH, Pi-hole aware. `router-health-check` checks your router or mesh from the LAN: firmware, open ports, UPnP, Wi-Fi security, DNS path, double NAT. `windows-health-check` checks a Windows 10/11 PC without admin rights. `macos-health-check` checks a Mac without sudo and without permission dialogs. The inventory and router checks run on Windows, macOS and Linux. Every check ends with a prioritized fix list with exact steps, and every script is read-only. Each skill lists the network calls and permissions it uses. Open source (MIT): the repo link above.
- **Tags:** home-lab, raspberry-pi, router, windows, macos, security, health-check
- **Price note:** one-time, 3-5 USD. The author sets the final price on Agensi.

## Coming (do not put in a listing until built)

- A home report that combines all findings into one ranked list
- A Homey Pro health check
