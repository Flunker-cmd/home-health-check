---
name: windows-health-check
description: Read-only health check of a Windows 10/11 PC (updates, BIOS, Defender, firewall, Secure Boot, BitLocker, disks, crashes and event log errors, backup, startup programs, outdated apps), ending in a prioritized fix list. Use when the user asks to check, review, clean up or "health check" their Windows computer.
---

# Windows PC health check

Check the PC this session runs on, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

**Several PCs:** the collector only reads the machine it runs on, so each Windows PC is checked in its own Claude Code session on that PC. If the user wants an overview, ask them to save each report and combine them in one session into a single ranked list, with the PC named in every action.

## Ground rules

- **Read-only until the user says otherwise.** Every change (installing updates, uninstalling apps, BIOS updates, enabling BitLocker, deleting files, editing firewall rules or autostart) needs the user's explicit yes for that specific change.
- **Admin rights:** run the collector without admin. When a fix needs admin, start it with `Start-Process powershell -Verb RunAs` so the user approves the UAC prompt themselves, and log the elevated output to a file you read afterwards.
- **Never handle passwords, PINs or recovery keys.** BitLocker recovery keys and backup passwords go into the user's own password manager or Microsoft account, typed by the user.
- **Back up before anything risky** (firewall rules: `netsh advfirewall export`; autostart: export the Run keys; files: confirm a backup exists).
- **Look up current versions** (latest BIOS for the exact board, Windows release health, driver versions) on the vendor's site and cite them. Don't guess.

## 1. Collect

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill's directory>/scripts/collect.ps1"
```

`-SkipWinget` skips the app update list (slow on some machines). Read the whole output, then look closer where something stands out (e.g. `Get-WinEvent` for a specific error, `Get-CimInstance` for a device).

If `~/.home-health-check/inventory.md` exists (from the home-inventory skill), use it for context, e.g. which DNS server the network intends this PC to use.

Ask the user only for what you can't read: what the PC is used for, whether there is any backup they know of, and anything that has felt slow or broken.

## 2. Assess

| Area | What to look at |
|---|---|
| **Windows version** | Still supported (check Microsoft's release information for the version), latest monthly update installed, reboot pending, Insider builds |
| **BIOS / firmware** | Version and date versus the vendor's latest for that exact board; security fixes in between. RAM running at JEDEC speed on a kit sold as faster = XMP/EXPO off (free performance, but a stability trade-off: let the user decide) |
| **Protection** | Defender (real-time, tamper protection, PUA, fresh signatures) or another antivirus, firewall on in all profiles, Secure Boot, VBS/memory integrity, TPM |
| **Encryption** | BitLocker on the system drive (essential for laptops, recommended for desktops). Dynamic disks can't be encrypted with BitLocker |
| **Exposure** | Remote Desktop on, SMB1 installed, extra shares beyond the admin `$` shares, unexpected local administrators |
| **Disks** | Health status, free space (warn below ~15 % on the system drive), disk errors in the log: check *which* disk (USB card readers and sticks often cause them) |
| **Stability** | Unexpected shutdowns, blue screens, WHEA hardware errors, repeating errors from one driver or service (name the device or app) |
| **Network** | Link speed as expected, DNS servers (a DNS filter on the network is bypassed if a browser or VPN app uses its own DNS-over-HTTPS) |
| **Backup** | Is anything backing up personal files and projects? OneDrive folder backup, File History, restic/other tools. "Synced to cloud" is not the same as a versioned backup |
| **Clutter** | Startup programs nobody needs, firewall rules for programs that no longer exist, crashing helper apps (vendor "hubs" and updaters), outdated apps from winget |

## 3. Report

1. **Facts:** a short table of the hardware and system.
2. **Assessment per area**, with the evidence.
3. **Prioritized actions:**
   - *Good as it is.*
   - *Should change:* numbered, most important first (missing backup, missing encryption and outdated firmware usually lead). For each: what, why, and exactly how.
   - *Check / good to know.*
4. **Sources** for versions and advisories.

Offer to do the fixes with the user, one approved step at a time, and verify each one afterwards.

## Fixing: notes from practice

- **App updates:** `winget upgrade --all --accept-package-agreements --accept-source-agreements` updates most apps. Some apps (banking ID apps, games launchers) must be updated from within the app.
- **BIOS updates:** the user flashes it (vendor's tool or the BIOS's own updater from a USB stick). Before flashing, suspend BitLocker (`manage-bde -protectors -disable C: -RebootCount 1`, admin) or have the recovery key at hand; after flashing, check that Secure Boot, virtualization and XMP/EXPO settings survived.
- **BitLocker:** `manage-bde -on C: -RecoveryPassword -UsedSpaceOnly` (admin), then the user saves the recovery key themselves before rebooting.
- **Backup of project folders:** a scheduled `restic` job to a cloud-synced or external drive works well. The repository password goes in the user's password manager, never in a script in plain text you write for them unless they choose to store it in a protected file.
- **Freeing space on C:** npm/pip caches, `%TEMP%`, old game update packages, `DISM /Online /Cleanup-Image /StartComponentCleanup` (admin). Show sizes and get a yes before deleting.
- **Stale firewall rules:** export first, then remove only rules whose program path no longer exists.
