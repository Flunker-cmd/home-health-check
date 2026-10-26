---
name: pi-health-check
description: Read-only health check of a Raspberry Pi or other Debian-based Linux box reachable over SSH (OS support status, updates, SD card and disk health, security, services, Pi-hole/unbound/cloudflared DNS setup), ending in a prioritized fix list. Use when the user asks to check, review or "health check" their Pi, Pi-hole, home server or a Linux machine on their network.
---

# Raspberry Pi / Linux health check

Check one or more Linux hosts over SSH, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

**Several hosts:** if the inventory (or the user) lists more than one Pi or Linux machine, show them with name and address and ask whether to check one or all. For all: connect to and collect from each in turn (each may have its own SSH user), write one report per host, and end with a combined summary that ranks every host's actions in a single priority order, e.g. "update the OS on pi2 and pi3 before anything else". Name the host in every finding so nothing gets mixed up.

## Ground rules

- **Read-only until the user says otherwise.** Collect and report first. Every change (updates, config edits, reboots, reinstalls, deletions) needs the user's explicit yes for that specific change.
- **Never handle passwords.** Do not ask for, type or store passwords, tokens or keys. When something needs a password (sudo, a web UI password), give the user a single command to run themselves, e.g. `ssh -t user@host "sudo <command>"`.
- **Back up before anything risky**, and verify the backup (size, checksum, archive test) before relying on it.
- **Verify after every change** and report the real result, including failures.
- **Do not guess dates or versions.** Support status, latest versions and CVEs change. Look them up (vendor/distro pages) and cite the source.

## 1. Connect

1. If `~/.home-health-check/inventory.md` exists (from the home-inventory skill), take the host from there. Otherwise ask for the host (IP or name) and user, or find candidates with `ssh -G <host>`, `~/.ssh/config`, or the ARP table (Raspberry Pi MAC prefixes include `b8:27:eb`, `dc:a6:32`, `e4:5f:01`, `d8:3a:dd`, `2c:cf:67`).
2. Test non-interactively: `ssh -o BatchMode=yes -o ConnectTimeout=5 user@host "hostname"`.
   - If key login is not set up, tell the user how to set it up (`ssh-keygen -t ed25519`, then copy the public key to `~/.ssh/authorized_keys` on the host) and let them do it. Do not work around it with passwords.

## 2. Collect

Run the bundled collector. It only reads, uses `sudo -n` (never prompts), and skips what it can't access:

```bash
ssh -o BatchMode=yes user@host 'bash -s' < "<this skill's directory>/scripts/collect.sh"
```

Read the whole output. Follow up with your own read-only commands where something needs a closer look.

## 3. Assess

Go through each area. For each finding, say what you saw, why it matters and how sure you are.

| Area | What to look at |
|---|---|
| **OS support** | Release and codename. Look up whether it still gets security updates (Debian: <https://www.debian.org/releases/> and <https://wiki.debian.org/LTS>; Raspberry Pi OS follows Debian). An out-of-support OS is usually the top finding. |
| **Updates** | Pending upgrades, age of the apt lists, `reboot-required`, whether unattended-upgrades or an update script exists. |
| **Storage** | Free space, root mounted read-only, kernel I/O/mmc/ext4 errors (an SD card dying), throttling or under-voltage (`get_throttled` not `0x0`) and temperature. |
| **Security** | SSH password login and root login, authorized keys, passwordless sudo (fine with key-only SSH, say so), listening ports and what they are, firewall, web UIs without a password. |
| **Services** | Failed units, services that look unused (old RetroPie, VNC, Samba, CUPS) and could be removed. |
| **Network** | Static IP config (`dhcpcd` on older releases, NetworkManager on newer), netmask and gateway matching what the router hands out, DNS used by the host itself. |
| **Pi-hole** | Version, blocking enabled, upstream DNS, gravity size, web password set (`webserver.api.pwhash` non-empty). |
| **Encrypted DNS** | `cloudflared` with `proxy-dns` **was removed in cloudflared 2026.2.0**. Hosts still on an older cloudflared work but run unmaintained code with known vulnerabilities, and upgrading cloudflared breaks DNS. Recommend unbound (see below). |
| **Backups** | Is there any? (Pi-hole Teleporter export, config copies, a full image.) |
| **Errors** | Repeating errors in the journal since boot. |

## 4. Report

Use this structure:

1. **Facts:** a short table of what the host is and runs.
2. **Assessment per area:** good / needs attention, with the evidence.
3. **What I need from you:** only if something could not be read.
4. **Prioritized actions:**
   - *Good as it is.*
   - *Should change:* numbered, most important first. For each: what, why, and exactly how (commands or menu path).
   - *Check / good to know.*
5. **Sources** for every external fact (support dates, versions, CVEs).

Offer to carry out the fixes, one approved step at a time.

## Fixing: proven playbooks

### Unattended update script
If the user wants one, write it with `set -euo pipefail`, an `ERR` trap that skips the reboot, `DEBIAN_FRONTEND=noninteractive` with `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`, `apt-get full-upgrade` (recommended on Raspberry Pi OS), a log file per run created *before* `exec > >(tee "$LOGFILE")`, and a `--no-reboot` flag. Run long jobs over SSH with `nohup ... &` so a dropped connection can't kill apt halfway.

### Replace cloudflared with unbound (DNS-over-TLS)
1. `apt-get install unbound`, then disable `unbound-resolvconf.service` and remove `/etc/unbound/unbound.conf.d/resolvconf_resolvers.conf` if present.
2. Config in `/etc/unbound/unbound.conf.d/pi-hole.conf`: listen on `127.0.0.1` port `5335`, `tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt`, and a `forward-zone` for `"."` with `forward-tls-upstream: yes` and e.g. `1.1.1.1@853#cloudflare-dns.com` and `9.9.9.9@853#dns.quad9.net`. Optionally run fully recursive instead (no third party, but unencrypted to authoritative servers): explain the trade-off and let the user choose.
3. `unbound-checkconf`, restart, then verify: `dig @127.0.0.1 -p 5335 example.com` answers, `dnssec-failed.org` gives `SERVFAIL`, and `ss -tn` shows connections to port 853.
4. Point Pi-hole at it: `sudo pihole-FTL --config dns.upstreams '["127.0.0.1#5335"]'`.

### Reinstall onto a new OS release
1. **Backups first:** Pi-hole Teleporter (`sudo pihole-FTL --teleporter` writes a zip in the current directory), `/etc/pihole/pihole.toml`, any other configs, home directory files, and a full compressed image streamed over SSH to the PC: `ssh user@host 'sync; sudo dd if=/dev/mmcblk0 bs=4M status=none | gzip -1' > host.img.gz`, then `gzip -t` and compare the uncompressed size with `blockdev --getsize64`.
2. **Keep DNS working:** if the host is the network's DNS server, have the user point the router's DNS at a public resolver for the duration.
3. **Prefer a new SD card** so the old one stays as an instant fallback. Test spare cards before use (sequential write/read and random 4K writes, and check the OS event/kernel log for I/O retries). Old cards that fail, stall for many seconds or turn read-only must not be used.
4. Flash with Raspberry Pi Imager (OS Lite, set hostname, user, SSH with the user's public key only). Newer Imager versions do not set up passwordless sudo: the user may add `/etc/sudoers.d/010_<user>-nopasswd` themselves.
5. After first boot: remove the old host key (`ssh-keygen -R <ip>`), compare the new fingerprint, `full-upgrade`, set the static IP (NetworkManager: `nmcli con mod ... ipv4.method manual ...`), install the services, seed Pi-hole with the old `pihole.toml` and run the installer with `--unattended`, import the Teleporter zip, then **re-set the upstream DNS** (the import restores the old value).
6. Reboot once and confirm everything comes back by itself before the user points the router's DNS back.
