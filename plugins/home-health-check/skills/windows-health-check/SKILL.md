---
name: windows-health-check
description: Read-only health check of a Windows 10/11 PC (updates, BIOS, Defender, firewall, Secure Boot, BitLocker, disks, crashes and event log errors, backup, startup programs, outdated apps), ending in a prioritized fix list. Use when the user asks to check, review, clean up or "health check" their Windows computer.
summary: Read-only health check of a Windows 10/11 PC with a prioritized fix list, no admin rights needed.
version: 0.4.0
tags: [windows, health-check, security, bitlocker, defender, maintenance]
keywords: [windows 11, windows 10, bios, secure boot, event log, backup, winget, startup programs]
use_cases:
  - Check whether my PC is secure and up to date
  - Find out why Windows crashes or feels slow
  - Clean up startup programs and outdated apps
docs_url: https://github.com/Flunker-cmd/home-health-check
---

# Windows PC health check

Check the PC this session runs on, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

`<data dir>` below is the folder for the inventory and findings; it is defined in `references/findings-format.md`.

**Several PCs:** the collector only reads the machine it runs on, so each Windows PC is checked by running this skill on that PC. For an overview of several PCs, see *Several computers* in `references/findings-format.md`: the findings of every PC can end up in one data directory, where a report skill can combine them into a single ranked list with the PC named in every action.

## Ground rules

- **Read-only until the user says otherwise.** Every change (installing updates, uninstalling apps, BIOS updates, enabling BitLocker, deleting files, editing firewall rules or autostart) needs the user's explicit yes for that specific change.
- **Admin rights:** run the collector without admin. When a fix needs admin, start it with `Start-Process powershell -Verb RunAs` so the user approves the UAC prompt themselves, and log the elevated output to a file you read afterwards.
- **Never handle passwords, PINs or recovery keys.** BitLocker recovery keys and backup passwords go into the user's own password manager or Microsoft account, typed by the user.
- **Back up before anything risky** (firewall rules: `netsh advfirewall export`; autostart: export the Run keys; files: confirm a backup exists).
- **Look up current versions** (latest BIOS for the exact board, Windows release health, driver versions) on the vendor's site and cite them. Don't guess.

## 1. Collect

Run the bundled script `scripts/collect.ps1` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-this-skill>/scripts/collect.ps1"
```

`-SkipWinget` skips the app update list (slow on some machines). Read the whole output, then look closer where something stands out (e.g. `Get-WinEvent` for a specific error, `Get-CimInstance` for a device).

If `<data dir>/inventory.md` exists (from the home-inventory skill), use it for context, e.g. which DNS server the network intends this PC to use.

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

If `<data dir>/inventory.md` exists, update this PC's row (matched by MAC): computer name, "Windows PC" in *Type*, and model and Windows version in *Notes*. Never overwrite a name or note the user set without asking.

## Save findings

After the report, write the findings so other skills can use them. The format is `hhc-findings/1`, described in `references/findings-format.md`.

1. If `<data dir>` exists, write one findings file for this PC, named as the format describes. The collector prints one `adapter:` line per network adapter, virtual ones included: take `device.mac` from the physical adapter that carries the default route, or the one that matches a row in the inventory.
2. If `<data dir>` does not exist, offer once to create it, and carry on without it if the user declines.
3. If there is no `inventory.md` on this computer, say which file to copy where (see *Several computers* in the format file).
4. Map the report to severities: items under *Should change* are `critical` or `high` by the format's definitions, otherwise `medium`; *Check* items are `low`; *Good to know* items are `info`. *Good as it is* writes nothing. Put what could not be read without admin rights in `not_checked`.
5. Tell the user the path of the file in one line.

### Standard finding ids

| id | usual severity | when |
|---|---|---|
| `os-out-of-support` | high | Windows version no longer gets security updates |
| `updates-pending` | medium | the latest monthly update is not installed |
| `reboot-pending` | low | a reboot is pending |
| `bios-outdated` | medium | BIOS is behind the vendor's latest for this board |
| `defender-off` | high | no active antivirus, or real-time protection off |
| `firewall-off` | high | firewall off in a profile |
| `secure-boot-off` | medium | Secure Boot disabled |
| `bitlocker-off` | high | system drive not encrypted (medium on a desktop) |
| `rdp-on` | high | Remote Desktop enabled |
| `smb1-installed` | high | SMB1 installed |
| `disk-health` | high | a disk reports a bad health status or errors |
| `low-disk-space` | medium | under about 15 % free on the system drive |
| `crashes` | medium | blue screens, unexpected shutdowns or WHEA errors |
| `no-backup` | high | nothing versioned backs up personal files and projects |
| `apps-outdated` | low | apps with updates available (winget) |
| `startup-clutter` | low | startup programs or firewall rules nobody needs |

Use a standard id when it fits. Otherwise make a new kebab-case id, and keep using it.

## Network and permissions

- **Network:** the collector reads the local machine. The one network call is `winget upgrade` (list only, nothing is installed), which contacts Microsoft's winget package sources to list available app updates; `-SkipWinget` skips it. Versions, BIOS releases and advisories are looked up on public web pages by the agent; nothing from the PC is sent there.
- **Rights:** no admin rights. It reads Defender, firewall, Secure Boot, BitLocker, TPM and disk state, the event log, startup entries, scheduled tasks and installed updates where Windows lets a normal user read them, and marks what needs admin. `-ExecutionPolicy Bypass` applies to that one PowerShell process only, so the local unsigned script can run; it changes no system setting. When a fix needs admin, the user approves the UAC prompt.
- **Files:** the collector writes nothing. The skill writes the findings file and updates the inventory row in `<data dir>`. Every fix is a separate step that needs the user's yes.

## Fixing: notes from practice

- **App updates:** `winget upgrade --all --accept-package-agreements --accept-source-agreements` updates most apps. Some apps (banking ID apps, games launchers) must be updated from within the app.
- **BIOS updates:** the user flashes it (vendor's tool or the BIOS's own updater from a USB stick). Before flashing, suspend BitLocker (`manage-bde -protectors -disable C: -RebootCount 1`, admin) or have the recovery key at hand; after flashing, check that Secure Boot, virtualization and XMP/EXPO settings survived.
- **BitLocker:** `manage-bde -on C: -RecoveryPassword -UsedSpaceOnly` (admin), then the user saves the recovery key themselves before rebooting.
- **Backup of project folders:** a scheduled `restic` job to a cloud-synced or external drive works well. The repository password goes in the user's password manager, never in a script in plain text you write for them unless they choose to store it in a protected file.
- **Freeing space on C:** npm/pip caches, `%TEMP%`, old game update packages, `DISM /Online /Cleanup-Image /StartComponentCleanup` (admin). Show sizes and get a yes before deleting.
- **Stale firewall rules:** export first, then remove only rules whose program path no longer exists.
