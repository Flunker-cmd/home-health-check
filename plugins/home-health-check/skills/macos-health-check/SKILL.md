---
name: macos-health-check
description: Read-only health check of the Mac it runs on (macOS version and support, updates, FileVault, SIP, Gatekeeper, firewall, XProtect, sharing services, Time Machine, disk, battery, startup items, Homebrew and unsigned apps, crashes and panics), ending in a prioritized fix list. Use when the user asks to check, review, clean up or "health check" their Mac, MacBook or iMac.
summary: Read-only health check of your Mac with a prioritized fix list, no sudo and no permission dialogs.
version: 0.6.4
tags: [macos, mac, health-check, security, filevault, time-machine]
keywords: [macbook, imac, mac mini, sip, gatekeeper, xprotect, homebrew, launch agents]
use_cases:
  - Check whether my Mac is secure and up to date
  - Find out whether my Mac is backed up and encrypted
  - See why my Mac crashes or which startup items run
docs_url: https://github.com/Flunker-cmd/home-health-check
---

# macOS health check

Check the Mac this session runs on, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

`<data dir>` below is the folder for the inventory and findings; it is defined in `references/findings-format.md`.

**Several Macs:** the collector only reads the machine it runs on, so each Mac is checked by running this skill on that Mac (or over SSH, see step 1). For an overview of several computers, see *Several computers* in `references/findings-format.md`: the findings of every computer can end up in one data directory, where the home-network-report skill can combine them into a single ranked list with the computer named in every action.

## Ground rules

- **Read-only until the user says otherwise.** Every change (installing updates, turning on FileVault or the firewall, changing backup settings, removing login items or launch agents, uninstalling apps) needs the user's explicit yes for that specific change.
- **No sudo and no permission dialogs.** The collector never asks for a password and never touches the folders macOS guards with a permission dialog. Anything that would need Full Disk Access or admin rights is printed as `not checked: <area>: <reason>` and skipped. Do not work around that; tell the user where they can look it up themselves in System Settings.
- **Never handle passwords, the FileVault recovery key or Apple Account details.** The user stores recovery keys in their own password manager, typed by the user.
- **Back up before anything risky.** Confirm a Time Machine or other versioned backup exists before system or disk changes.
- **Look up current versions** (which macOS release still gets security updates, the latest XProtect and macOS versions) on Apple's security releases page and macOS release notes, and cite them. Do not guess.

## 1. Collect

Run the bundled script `scripts/collect.sh` from this skill's folder. If your agent gave you this skill without a folder on disk, write the script's text unchanged to a temporary file, run that file the same way, and delete it afterwards.

```bash
bash "<path-to-this-skill>/scripts/collect.sh"
```

`--skip-updates` skips the update list (`softwareupdate -l`), which contacts Apple and can take a minute or two. To check a Mac from another computer: `ssh <user>@<mac> 'bash -s' < scripts/collect.sh` (the user has to turn on Remote Login and set up key login themselves).

Read the whole output, then look closer where something stands out. Lines starting with `not checked:` name what the collector could not read and why. The reasons are: `needs Full Disk Access`, `needs admin`, `timed out`, `not available` and `skipped`. Carry them into the report and into `not_checked` in the findings.

If `<data dir>/inventory.md` exists (from the home-inventory skill), use it for context, for example which DNS server the network intends this Mac to use.

Ask the user only for what you cannot read: what the Mac is used for, whether they have a backup outside Time Machine, and anything that has felt slow or broken.

## 2. Assess

| Area | What to look at |
|---|---|
| **macOS version** | Still gets security updates (Apple supports the current and the two previous major releases in practice; check the security releases page), and the latest point release is installed |
| **Updates** | `pending updates` from the collector. Automatic updates: a key printed as `unset` has the macOS default (on); `0` means off. App Store `AutoUpdate: 0` means app updates are manual |
| **Encryption** | FileVault on. Essential for laptops, recommended for desktops |
| **System protection** | System Integrity Protection enabled, Gatekeeper assessments enabled, XProtect version recent (a date older than about 60 days is worth a look) |
| **Firewall** | The application firewall is off by default on macOS. Worth turning on for a laptop that joins other networks. Stealth mode is optional |
| **Sharing** | `listening:` shows Remote Login (SSH), Screen Sharing, File Sharing, Remote Management that are reachable from the network. `airplay-receiver` is on by default and only worth a mention |
| **Backup** | A Time Machine destination with a backup from the last 14 days, or another versioned backup the user can name. iCloud Drive sync is not a versioned backup. `last backup` often needs Full Disk Access and then shows as not checked: ask the user to look at System Settings > General > Time Machine |
| **Disk** | SMART status `Verified`; under about 15 % free on the system volume is a problem |
| **Battery** | Condition `Normal`. Apple silicon Macs also report a maximum capacity (under 80 % means service); Intel Macs print `not reported`, so use the condition and the cycle count |
| **Startup** | Third-party launch agents and daemons nobody remembers installing. Login items need admin to list; point the user to System Settings > General > Login Items |
| **Apps** | Outdated Homebrew packages if Homebrew is installed; apps that are unsigned or only ad-hoc signed are worth asking about, a signature from the App Store or a Developer ID is normal |
| **Crashes and panics** | Any kernel panic in the last 30 days; the same app crashing three or more times. Name the app. Repeated panics point to hardware, a kernel extension or a driver |

## 3. Report

1. **Facts:** a short table of the hardware and system (model, chip, memory, macOS version, uptime).
2. **Assessment per area**, with the evidence.
3. **Prioritized actions:**
   - *Good as it is.*
   - *Should change:* numbered, most important first (missing backup, FileVault off and missing security updates usually lead). For each: what, why, and exactly how (System Settings path).
   - *Check / good to know.*
4. **Sources** for versions and advisories.

Offer to do the fixes with the user, one approved step at a time, and verify each one afterwards.

If `<data dir>/inventory.md` exists, update this Mac's row (matched by MAC): computer name, "Mac" in *Type*, and model and macOS version in *Notes*. The Wi-Fi address of a Mac is usually a private (randomized) address that can differ per network, so if no row matches, match on name and type and ask. Never overwrite a name or note the user set without asking.

## Save findings

After the report, write the findings so other skills can use them. The format is `hhc-findings/1`, described in `references/findings-format.md`.

1. If `<data dir>` exists, write one findings file for this Mac, named as the format describes. Take `device.mac` from the collector's `mac:` line.
2. If `<data dir>` does not exist, offer once to create it, and carry on without it if the user declines.
3. If there is no `inventory.md` on this computer, say which file to copy where (see *Several computers* in the format file).
4. Map the report to severities: items under *Should change* are `critical` or `high` by the format's definitions, otherwise `medium`; *Check* items are `low`; *Good to know* items are `info`. *Good as it is* writes nothing. Every `not checked:` line becomes an entry in `not_checked` with its area and reason.
5. Tell the user the path of the file in one line.
6. If a findings file was written, add one line: the home-network-report skill, if it is installed, combines the saved findings of every check into one report for the whole home. Run it only if the user asks.

### Standard finding ids

| id | usual severity | when |
|---|---|---|
| `os-out-of-support` | high | this macOS version no longer gets security updates |
| `updates-pending` | medium | `softwareupdate` lists updates, security updates first |
| `auto-updates-off` | medium | automatic security or macOS updates are off |
| `filevault-off` | high | FileVault is off (medium on a desktop) |
| `sip-off` | high | System Integrity Protection is disabled |
| `gatekeeper-off` | high | Gatekeeper assessments are disabled |
| `firewall-off` | medium | the application firewall is off |
| `xprotect-stale` | low | XProtect is older than about 60 days |
| `sharing-on` | medium | Remote Login, Screen Sharing, Remote Management or File Sharing is reachable from the network |
| `no-backup` | high | no Time Machine destination and no other versioned backup the user can name |
| `backup-stale` | medium | the last backup is older than 14 days |
| `disk-health` | high | SMART status is not `Verified` |
| `low-disk-space` | medium | under about 15 % free on the system volume |
| `battery-service` | low | battery condition is not Normal, or maximum capacity is under 80 % |
| `kernel-panics` | medium | any panic in the last 30 days |
| `crashes` | low | the same app crashed 3 or more times in 30 days |
| `startup-clutter` | low | third-party launch agents or daemons nobody needs |
| `apps-outdated` | low | Homebrew packages are outdated |
| `apps-unidentified` | low | unsigned or ad-hoc signed apps in /Applications |

Use a standard id when it fits. Otherwise make a new kebab-case id, and keep using it.

## Network and permissions

- **Network:** the collector makes no connections to other devices on the local network, so macOS does not ask for Local Network access. The one network call is `softwareupdate -l` (list only, nothing is installed), which contacts Apple's update servers to list available updates; `--skip-updates` skips it. If Homebrew is installed, `brew outdated` runs with `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ANALYTICS=1`, so it does not update Homebrew itself and sends no analytics. Versions, release notes and advisories are looked up on public web pages by the agent; nothing from the Mac is sent there.
- **Rights:** no sudo and no admin rights. It reads only what a normal user may read: `sw_vers`, `sysctl`, `system_profiler` (hardware and power, with the serial number, hardware UUID and activation state filtered out before anything is printed), `defaults read` of system update preferences, `fdesetup status`, `csrutil status`, `spctl --status`, the firewall state, `netstat` for listening ports, `tmutil`, `diskutil`, `pmset`, `launchctl list`, `codesign -dv` on the apps in /Applications, and file names (never contents) in the DiagnosticReports folders. It never uses AppleScript or Automation and does not open Desktop, Documents, Downloads, iCloud Drive, Mail, Messages, Safari data or external volumes, so no permission dialog appears. Where a fact would need Full Disk Access or admin rights, it is marked as not checked.
- **Files:** the collector writes only a temporary folder, which it deletes when it ends. The skill writes the findings file and updates the inventory row in `<data dir>`. Every fix is a separate step that needs the user's yes.

## Fixing: notes from practice

- **Updates:** System Settings > General > Software Update, or `softwareupdate -ia` in Terminal, which the user runs and which may ask for their password. A restart may be needed.
- **FileVault:** System Settings > Privacy & Security > FileVault. The user saves the recovery key themselves before continuing.
- **Firewall:** System Settings > Network > Firewall.
- **Time Machine:** System Settings > General > Time Machine, with an external disk or a network destination.
- **Homebrew:** `brew upgrade` after the user's yes; look at `brew outdated` first.
- **Removing a launch agent:** unload it with `launchctl bootout gui/$(id -u) <plist path>` and move the plist to a backup folder instead of deleting it, only with the user's yes.
