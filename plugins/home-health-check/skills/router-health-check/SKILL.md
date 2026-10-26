---
name: router-health-check
description: Read-only health check of a home router or mesh Wi-Fi system (TP-Link Deco, Eero, Google/Nest Wifi, Asus, Netgear, Ubiquiti and others) from a computer on the LAN - model and firmware, open ports, UPnP, Wi-Fi security, DHCP/DNS path, IPv6, double NAT, latency - ending in a prioritized fix list. Use when the user asks to check or review their router, mesh, Wi-Fi or home network settings.
---

# Router / mesh health check

Measure what can be measured from a computer on the LAN, ask the user for the rest (many mesh systems are app-only), and hand over a prioritized fix list. Answer in the user's language.

## Ground rules

- **Read-only.** Do not change router settings. Most consumer routers are configured in a phone app, so the user makes every change themselves. Give exact menu paths.
- **Never handle passwords.** Do not log in to the router's web UI with the user's password, and do not ask for it.
- **No scanning outside the user's own LAN**, and nothing aggressive on it: a handful of TCP ports on the gateway and its mesh nodes, no brute force, no exploits.
- **Firmware versions and CVEs change.** Look up the vendor's download page and security advisories for the exact model and hardware version, and cite them. If the version cannot be read, say what you inferred it from and how sure you are.

## 1. Probe from the LAN

On Windows run the bundled probe (PowerShell 5.1+, no admin needed):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill's directory>/scripts/probe.ps1"
```

It reports: gateway and DHCP info (DNS handed out, lease time), latency and packet loss, open TCP ports on the gateway, the model and manufacturer from the router's UPnP description, UPnP port mappings, nearby Wi-Fi networks with their security, the first hops (double NAT / CGNAT), whether the gateway's own DNS filters ads, and the devices in the ARP table.

On macOS or Linux, gather the same with: `ip route` / `netstat -rn`, `ping -c 50`, `nc -zv -w2 <gw> 22 23 53 80 443 8080 8443`, `traceroute -n -m 3 1.1.1.1`, `arp -a`, `dig @<gw> doubleclick.net`, and the Wi-Fi tool of the OS (`nmcli dev wifi list`, or *Option-click* the Wi-Fi icon on macOS).

If a DNS filter such as **Pi-hole** is in use, also check which clients it sees (see the pi-health-check skill). If it only ever sees the router's IP, the router is forwarding DNS and per-device stats and rules are lost.

## 2. Ask for what can't be read

Give the user one numbered list of screenshots or values to fetch from the router app or web UI. Typical items:

1. Firmware version per unit, and whether automatic updates are on.
2. Hardware version (on the label or in device info), because firmware support differs per hardware version.
3. Network map: each unit, wired or wireless backhaul, signal quality, where it stands in the home.
4. Wi-Fi security mode (WPA2 / WPA2+WPA3 / WPA3) for each network.
5. Guest and IoT networks: on or off.
6. IPv6: on or off, and which DNS it hands out.
7. DHCP: address pool, DNS servers, reservations.
8. Port forwarding, UPnP, DMZ.
9. WPS.
10. Built-in security features (e.g. TP-Link HomeShield, Eero Plus) and QoS.
11. Account security for the router's cloud account: strong unique password, two-factor authentication, list of managers/admins.
12. Names of unknown devices from the client list.

## 3. Assess

| Area | Good | Needs attention |
|---|---|---|
| **Firmware** | Recent, auto-update on | Old, known CVEs, or hardware version out of support (say so: it won't get fixes) |
| **Admin / cloud account** | Strong unique password, 2FA, only known managers | Default or reused password, no 2FA, remote admin open to the internet |
| **Wi-Fi security** | WPA2/WPA3 mixed or WPA3 | WPA/TKIP, open, or WEP. Note that old IoT gear may need WPA2 |
| **Separation** | Guest network for guests, IoT network for simple smart devices | Everything on one network and the main password shared with guests |
| **WPS** | Off | On |
| **UPnP / port forwarding** | Off, or on with only expected mappings | Unknown mappings, DMZ, forwards nobody remembers |
| **Open ports (LAN side)** | Only web UI/DNS/app service | Telnet, FTP, SMB on the router |
| **DNS path** | DHCP hands out the intended DNS (e.g. Pi-hole) directly, no public "secondary" next to it | A public secondary DNS (clients bypass the filter), router DNS used instead of the filter, IPv6 DNS that bypasses an IPv4-only filter |
| **IPv6** | Off, or on with DNS pointed correctly | On with the router (or ISP) as IPv6 DNS while the user relies on a DNS filter |
| **WAN** | Public IP on the router, no double NAT | Double NAT (second hop is private) or CGNAT (100.64.0.0/10); matters for gaming, VPN and port forwarding |
| **Performance** | Low latency, 0 % loss, good backhaul | Loss, high jitter, a mesh node with weak backhaul |
| **Address reservations** | Servers with static IPs (e.g. Pi-hole) have a reservation or sit outside the DHCP pool | Static IPs inside the pool without a reservation |

## 4. Report

1. **Facts:** a table of what you measured.
2. **Assessment per area**, with the evidence.
3. **What I need from you:** the numbered list from step 2.
4. **Prioritized actions:**
   - *Good as it is.*
   - *Should change:* numbered, most important first (firmware and account security usually top the list). For each: what, why, and how (menu path in the app).
   - *Check / good to know.*
5. **Sources** for firmware versions, advisories and CVEs.

When the user returns with screenshots, update the report rather than starting over.
