---
name: pi-health-check
description: Read-only health check of a Raspberry Pi or other Debian-based Linux box reachable over SSH (OS support status, updates, SD card and disk health, security, services, Pi-hole/unbound/cloudflared DNS setup), ending in a prioritized fix list. Use when the user asks to check, review or "health check" their Pi, Pi-hole, home server or a Linux machine on their network.
summary: Read-only SSH health check of a Raspberry Pi or Linux box with a prioritized fix list, Pi-hole aware.
version: 0.6.0
tags: [raspberry-pi, linux, pi-hole, ssh, security, health-check]
keywords: [raspberry pi, debian, pi-hole, unbound, cloudflared, sd card, home server]
use_cases:
  - Check whether my Pi still gets security updates
  - Review my Pi-hole and DNS setup
  - Find out why my home server feels unhealthy
docs_url: https://github.com/Flunker-cmd/home-health-check
---

# Raspberry Pi / Linux health check

Check one or more Linux hosts over SSH, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

`<data dir>` below is the folder for the inventory and findings; it is defined in `references/findings-format.md`.

**Several hosts:** if the inventory (or the user) lists more than one Pi or Linux machine, show them with name and address and ask whether to check one or all. For all: connect to and collect from each in turn (each may have its own SSH user), write one report per host, and end with a combined summary that ranks every host's actions in a single priority order, e.g. "update the OS on pi2 and pi3 before anything else". Name the host in every finding so nothing gets mixed up.

## Ground rules

- **Read-only until the user says otherwise.** Collect and report first. Every change (updates, config edits, reboots, reinstalls, deletions) needs the user's explicit yes for that specific change.
- **Never handle passwords.** Do not ask for, type or store passwords, tokens or keys. When something needs a password (sudo, a web UI password), give the user a single command to run themselves, e.g. `ssh -t user@host "sudo <command>"`.
- **Back up before anything risky**, and verify the backup (size, checksum, archive test) before relying on it.
- **Verify after every change** and report the real result, including failures.
- **Do not guess dates or versions.** Support status, latest versions and CVEs change. Look them up (vendor/distro pages) and cite the source.

## 1. Connect

1. If `<data dir>/inventory.md` exists (from the home-inventory skill), take the host from there. Otherwise ask for the host (IP or name) and user, or find candidates with `ssh -G <host>`, `~/.ssh/config`, or the ARP table (Raspberry Pi MAC prefixes include `b8:27:eb`, `dc:a6:32`, `e4:5f:01`, `d8:3a:dd`, `2c:cf:67`).
2. Test non-interactively: `ssh -o BatchMode=yes -o ConnectTimeout=5 user@host "hostname"`.
   - If key login is not set up, tell the user how to set it up (`ssh-keygen -t ed25519`, then copy the public key to `~/.ssh/authorized_keys` on the host) and let them do it. Do not work around it with passwords.
   - If the user does not want key login, offer that they run the collector themselves (step 2, *Run by the user*). They type the password into ssh in their own terminal, and you never see it.

## 2. Collect

Run the bundled script `scripts/collect.sh` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards. It only reads, uses `sudo -n` (never prompts), and skips what it can't access:

```bash
ssh -o BatchMode=yes user@host 'bash -s' < "<path-to-this-skill>/scripts/collect.sh"
```

Read the whole output. Follow up with your own read-only commands where something needs a closer look.

**Run by the user** (no key login): give the user one command that saves the output to a file in a temporary folder, with the script's full path filled in. In a macOS or Linux terminal, or in Windows cmd:

```bash
ssh user@host 'bash -s' < "<path-to-this-skill>/scripts/collect.sh" > "<temp folder>/pi-collect.txt"
```

Windows PowerShell has no `<` redirect, so there pass the line to cmd, with single quotes outside and double quotes inside:

```powershell
cmd /c 'ssh user@host "bash -s" < "<path-to-this-skill>\scripts\collect.sh" > "<temp folder>\pi-collect.txt"'
```

The user types the password when ssh asks. Then read the file, delete it once the findings are saved, and continue with step 3. You cannot run follow-up commands on the host in this mode: where you would have, say what you could not check, or give the user the read-only command to run and paste the output.

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

## 5. Update the inventory

If `<data dir>/inventory.md` exists, update each checked host's row (matched by MAC, from the `mac:` line of the collector output): hostname in *Name* if empty, role in *Type* (e.g. "DNS server (Pi-hole + unbound)"), open services, and model, OS release and static IP in *Notes*. Never overwrite a name or note the user set without asking, and tell the user in a line what you changed. Do it again after a reinstall or other big change, so the inventory stays true.

## Save findings

After the report, write the findings so other skills can use them. The format is `hhc-findings/1`, described in `references/findings-format.md`.

1. If `<data dir>` exists, write one findings file per checked host, named as the format describes. Take `device.mac` from the `mac:` line of that host's collector output.
2. If `<data dir>` does not exist, offer once to create it, and carry on without it if the user declines.
3. If there is no `inventory.md` on this computer, say which file to copy where (see *Several computers* in the format file).
4. Map the report to severities: items under *Should change* are `critical` or `high` by the format's definitions, otherwise `medium`; *Check* items are `low`; *Good to know* items are `info`. *Good as it is* writes nothing. Put what could not be read in `not_checked`.
5. Tell the user the path of each file in one line.

### Standard finding ids

| id | usual severity | when |
|---|---|---|
| `os-out-of-support` | high | OS release no longer gets security updates |
| `updates-pending` | medium | pending upgrades, security ones first |
| `reboot-required` | low | a reboot is needed to finish updates |
| `storage-errors` | high | kernel I/O, mmc or ext4 errors, or root mounted read-only (SD card dying) |
| `undervoltage` | medium | `get_throttled` is not `0x0` |
| `low-disk-space` | medium | root filesystem nearly full |
| `ssh-password-login` | medium | SSH accepts password login |
| `ssh-root-login` | medium | SSH accepts root login |
| `failed-units` | medium | failed systemd units |
| `unused-services` | low | services that look unused (VNC, Samba, CUPS, old RetroPie) |
| `no-static-ip` | low | a server whose address is not fixed |
| `pihole-no-password` | high | Pi-hole web UI has no password |
| `pihole-outdated` | low | Pi-hole core, FTL or web has an update |
| `cloudflared-deprecated` | medium | still on cloudflared `proxy-dns`, removed upstream in 2026.2.0 |
| `no-backup` | high | no backup of the Pi-hole or other configuration |

Use a standard id when it fits. Otherwise make a new kebab-case id, and keep using it.

## Network and permissions

- **Network:** SSH to the host the user names, with key login only (`BatchMode`, no passwords). Without key login the user runs the collector over ssh in their own terminal and types the password there; the agent only reads the saved output file and deletes it afterwards. The collector makes no outbound calls of its own; it reads the host's local state. `apt-get -s` is a simulation and installs nothing. Support dates, versions and advisories are looked up on public web pages by the agent; nothing from the host is sent there.
- **Rights:** runs as the normal SSH user. It uses `sudo -n` (passwordless sudo only, it never prompts) to read things such as the effective sshd configuration, firewall status, the kernel log, process names behind listening ports, and Pi-hole's settings and query database (a read-only count). Without passwordless sudo these are skipped and listed as needing sudo. It checks whether Pi-hole's web password is set and prints only yes or no, never the hash.
- **Files:** nothing is written on the host. On this computer the skill writes the findings files and updates the inventory row, both in `<data dir>`. Every fix is a separate step that needs the user's yes.

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
