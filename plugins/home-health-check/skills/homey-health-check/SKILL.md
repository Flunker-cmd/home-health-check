---
name: homey-health-check
description: Read-only health check of a Homey Pro smart-home hub over its local API (firmware and apps, restarts and outages, memory and power, unavailable or stale devices, low batteries, broken flows, Zigbee and Z-Wave, backup notices, tidiness), ending in a prioritized fix list. Use when the user asks to check, review or "health check" their Homey, or asks why Homey devices are offline or flows do not run.
summary: Read-only health check of your Homey Pro with a prioritized fix list, using a read-only API key you create yourself.
version: 0.6.3
tags: [homey, smart-home, health-check, zigbee, z-wave, backup]
keywords: [homey pro, athom, flows, zigbee, z-wave, batteries, smart home hub]
use_cases:
  - Check whether my Homey is healthy and up to date
  - Find devices that are offline, stale or low on battery
  - See which flows or apps are broken and whether my Homey has restarted or dropped off the network
docs_url: https://github.com/Flunker-cmd/home-health-check
---

# Homey health check

Check a Homey Pro on the user's network, explain what is good and what is not, and hand the user a prioritized list of fixes. Answer in the user's language.

`<data dir>` below is the folder for the inventory and findings; it is defined in `references/findings-format.md`.

**Supported:** Homey Pro (Early 2023) is supported and tested. Other Homey Pro models (2016-2019) run the same calls but are untested: the collector says so, and anything it cannot read is printed as `not checked: <area>: <reason> (untested model)`, never treated as a fault. **Homey Bridge and Homey Cloud are not supported:** they have no local API, so there is nothing on the network to read. If your agent has a Homey connector, it can show a few things (devices and flows), but not availability, last seen, apps, firmware, Zigbee or Z-Wave, and it is rate limited; use it only for that and list the rest as not checked.

## Ground rules

- **Read-only.** The collector only reads (GET). Never take a backup, restart the Homey, update apps or firmware, or enable flows yourself: these are steps in the fix list that the user does in the Homey app.
- **The API key is a secret.** Never ask the user to paste it in the chat, never put it on a command line, in a file in `<data dir>`, in findings or in a report, and never read it from an environment variable. It is only read from a text file the user names.
- **The collector prints only what the check needs.** It never prints device values other than battery level, alarm state and last-updated time, nor variables, locations, the Wi-Fi name or whole API responses. Do not try to fetch more from the Homey yourself.
- **Say what cannot be known.** Short network drops and restarts cannot be seen afterwards (see step 2). Do not guess.

## 1. Collect

**The key.** Ask the user to create a read-only API key in the Homey web app (my.homey.app, open the Homey, then Settings > API Keys > New API Key), tick only the read permissions ("View" for each area, nothing else), and save the key as a text file, one line, somewhere outside any shared or synced folder. They give you the file's path, never the key. The key can be deleted in the same place when the check is done.

**The Homey's address.** If `<data dir>/inventory.md` exists, use the row whose vendor is Athom. If there is none, or several, ask the user for the Homey's IP address or name.

**Run the collector** from this skill's folder. Windows has `collect.ps1` (with `render.ps1` next to it), macOS and Linux have `collect.sh` (needs bash and perl with HTTP::Tiny and JSON::PP, which stock macOS and most Linux have).

```bash
bash "<path-to-this-skill>/scripts/collect.sh" --host <ip> --key-file <key file>
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-this-skill>\scripts\collect.ps1" -Homey <ip> -KeyFile <key file>
```

If your agent gave you this skill without a folder on disk: `collect.sh` is a single file, so write its text unchanged to a temporary file and run that. `collect.ps1` loads `render.ps1` from its own folder, so write **both** `collect.ps1` and `render.ps1` unchanged into the same new temporary folder, run `collect.ps1` there, and delete the folder afterwards.

Exit codes: 0 report printed, 1 the report could not be rendered (`collect.ps1` only; run it again, and if it repeats, check the Homey in the app), 2 bad options or key file problem, 3 the Homey cannot be reached (wrong address, Homey off, or not on this network), 4 perl lacks HTTP::Tiny or JSON::PP (`collect.sh` only; use `collect.ps1` on Windows).

Read the whole output. Sections are `## Homey`, `## Stability`, `## Backup`, `## Apps`, `## Devices`, `## Batteries`, `## Flows`, `## Radio`, `## Notifications (14 days)` and `## Tidiness`. Lines starting with `not checked:` name what could not be read and why: `key lacks permission` (the key is missing that read permission; offer to make a new key with it), `not available` and `timed out`; on a model that has not been tested the reason ends in `(untested model)`. When **every** area says `key lacks permission`, the key is most likely wrong, mistyped or revoked: have the user check the key file or make a new key. Carry them into the report and into `not_checked` in the findings.

If the collector's `address:` differs from the inventory row's IP, say so (finding `ip-changed`) and suggest a DHCP reservation in the router so the Homey keeps its address.

## 2. Assess

| Area | What to look at |
|---|---|
| **Model and firmware** | `model_tested: no` gives one `untested-model` note. `firmware_update:` other than `none` is a pending update (low); updates are installed in the Homey app |
| **Restarts** | `booted`, `uptime_days` and `reboot_reason`. A planned update (`reboot-ota`) is fine. A crash, out-of-memory or power reason, or a restart nobody asked for, is `unplanned-reboot` |
| **Stability** | `outages_24h`, `outages_7d`, `outages_31d`: each line is a stretch when the Homey recorded nothing, so it was down or off the network for at least that long (24 h shows 5 minute steps, 7 d hours, 31 d 6-hour steps). Compare each outage with `booted` and `reboot_reason`: an outage that ends at the boot time of a planned update reboot is that update, not an `outage`, and gets no finding. **Be plain that short drops and quick restarts cannot be seen afterwards**: the Homey does not keep them, and the phone's offline notice most likely comes from Athom's cloud. On Wi-Fi with outages, or a weak signal (`wifi_signal` below 40 %), suggest the Ethernet adapter or a closer mesh node |
| **Memory** | `memory_trend_31d` of +20 % or more over the month is a low finding. The collector does not show which app is responsible, so say that and suggest looking at app memory in the Homey app or restarting suspect apps one by one. `loadavg` is context only |
| **Power** | `undervoltage_now=yes`, `undervoltage_seen=yes`, `throttled_seen=yes` or `undervoltage_31d_max` above 0 points to the power supply or cable (medium) |
| **Backup** | Never take a backup. Backup notices are listed under *Backup*, oldest first. The newest `succeeded` line is the date of the last good backup; only when there is none does the date go in `not_checked`, with the manual steps (create a backup in the Homey app under Settings, Backups). A `failed` one is `backup-failed`: high when no `succeeded` notice is newer than it, otherwise info (a later backup worked); say it may be about the Homey Backups service, and have the user open Backups in the Homey app and look. A `backup_error` other than `none` is `backup-failed` (high). No backup notices at all gives `no-auto-backup` (info, neutral): "no automatic backup seen in the notifications; if you have Homey Backups, its notices may have expired" |
| **Apps** | `crashed N times` or `not running` (medium), `update <version>` (low), `origin` other than the app store (info, a sideloaded or developer app), `disabled` is the user's choice (mention it only when other things depend on the app) |
| **Devices** | `unavailable` (medium, with the message and room), `warning` (low), `firmware` updates (low; "needs wake" means the device updates when it next wakes up), `stale` sensors and thermostats with no update for 3 days (medium; `last never` means it never reported) |
| **Batteries** | `low` is 20 % or less and `alarm` is the device's own battery alarm: medium, high when the device is a safety sensor. `no_battery_report` is a smoke, water, CO or heat sensor that never reports its battery: low, so the user can check it by hand |
| **Flows** | `broken` flows (medium) are the ones Homey itself marks broken; `disabled` flows are mostly the user's choice (info, do not nag) |
| **Radio** | Zigbee `ready=no` or an error (high: no Zigbee device works); Z-Wave `no_ack` above 0 means a node that does not answer (medium) |
| **Notifications** | Counts per sender over 14 days, and the lines that mention a problem (offline, connection lost, crash, sync disabled, battery). Use them as hints for the findings above. Presence and security notices, and notices that flows write (owner Flow or Notifications), are counted only: the collector never quotes them. A sync or connection that an app or integration reports as disabled is `integration-disabled` |
| **Tidiness** | Devices without a room, empty rooms, device names with stray spaces: info, one `tidiness` finding |

## 3. Report

1. **Facts:** a short table (model, firmware, uptime, last restart and reason, network and address, number of devices, apps and flows).
2. **Assessment per area**, with the evidence.
3. **Prioritized actions:**
   - *Good as it is.*
   - *Should change:* numbered, most important first (Zigbee down, failed backups, then unavailable devices, crashed apps and low batteries of safety sensors). For each: what, why, and exactly how in the Homey app.
   - *Check / good to know.*
4. **What the check cannot see:** short drops, the date of the last good backup when no `succeeded` notice shows it, and every `not checked:` line.

Offer to walk through the fixes with the user. The user makes each change in the Homey app; you can help find the screen and check the result by running the collector again.

If `<data dir>/inventory.md` exists, update the Homey's row (matched by the MAC from `mac:`): "Homey Pro" in *Type*, and model and firmware in *Notes*. If no row matches, match on vendor Athom and ask. Never overwrite a name or note the user set without asking.

## Save findings

After the report, write the findings so other skills can use them. The format is `hhc-findings/1`, described in `references/findings-format.md`.

1. If `<data dir>` exists, write one findings file for the Homey, named as the format describes. Take `device.mac` from the collector's `mac:` line. Sub-devices (a sensor, an app, a flow) go in `subject` by their Homey name.
2. If `<data dir>` does not exist, offer once to create it, and carry on without it if the user declines.
3. If there is no `inventory.md` on this computer, say which file to copy where (see *Several computers* in the format file).
4. Map the report to severities: items under *Should change* are `critical` or `high` by the format's definitions, otherwise `medium`; *Check* items are `low`; *Good to know* items are `info`. *Good as it is* writes nothing. Every `not checked:` line becomes an entry in `not_checked` with its area and reason, and so does the date of the last good backup when no `succeeded` notice shows it.
5. Tell the user the path of the file in one line.
6. If a findings file was written, add one line: the home-network-report skill, if it is installed, combines the saved findings of every check into one report for the whole home. Run it only if the user asks.

### Standard finding ids

| id | usual severity | when |
|---|---|---|
| `firmware-update` | low | a Homey firmware update is available |
| `app-crashed` | medium | an app has crashed repeatedly |
| `app-not-running` | medium | an enabled app is not running |
| `app-update` | low | an app update is available |
| `app-sideloaded` | info | an app installed from outside the app store |
| `device-unavailable` | medium | a device is marked unavailable |
| `device-warning` | low | a device reports a warning |
| `device-firmware` | low | a device has a firmware update waiting |
| `sensor-stale` | medium | a sensor or thermostat has not reported for 3 days |
| `battery-low` | medium | battery 20 % or less or a battery alarm (high for a safety-critical sensor) |
| `safety-no-battery-report` | low | a smoke, water, CO or heat sensor does not report its battery |
| `flow-broken` | medium | a flow is marked broken |
| `flows-disabled` | info | flows are disabled |
| `zigbee-down` | high | the Zigbee radio is not ready or reports an error |
| `zwave-no-ack` | medium | Z-Wave nodes that do not acknowledge |
| `unplanned-reboot` | medium | the last restart was a crash, out-of-memory or power loss |
| `outage` | medium | stretches where the Homey recorded nothing (not a planned update reboot) |
| `memory-trend` | low | memory use grew 20 % or more over 31 days |
| `undervoltage` | medium | undervoltage or throttling seen: power supply or cable |
| `wifi-weak` | low | on Wi-Fi with a signal under 40 % or with outages |
| `ip-changed` | low | the Homey answers on another address than the inventory row |
| `backup-failed` | high | a backup error, or a backup failure notice with no successful backup after it (info when a later backup succeeded) |
| `no-auto-backup` | info | no backup notices seen |
| `integration-disabled` | low | an app or integration reports that sync or a connection was disabled |
| `untested-model` | info | a Homey model that has not been tested |
| `tidiness` | info | devices without a room, empty rooms, odd device names |

Use a standard id when it fits. Otherwise make a new kebab-case id, and keep using it.

## Network and permissions

- **Network:** the collector talks only to the Homey you name, over plain HTTP, because the Homey has no local HTTPS. That means the read-only key crosses your home network unencrypted: do it on a network you trust, and delete the key afterwards. Calls are GET only, never through a proxy and never following a redirect, 15 seconds at most each with a short pause between them, to these paths under `/api/manager/`: `system/`, `devices/device/`, `flow/flow/`, `flow/advancedflow/`, `apps/app/`, `zones/zone/`, `zigbee/state`, `zwave/state`, `updates/update/`, `notifications/notification/`, `backup/state`, and `insights/log/number/<id>/entry` for the system memory and undervoltage logs only. No other calls, and nothing leaves your network. Versions and release notes, if needed, are looked up by the agent on public pages; nothing from the Homey is sent there.
- **Rights:** no admin rights and no sudo. The key is read from the file you name (first line), is only sent to the Homey as a request header and is never printed or written anywhere. It is not read from an environment variable.
- **Files:** the collector writes nothing. The skill writes the findings file and updates the Homey's row in `<data dir>`. Every fix is a step the user does in the Homey app.

## Fixing: notes from practice

- **Updates:** Homey firmware and apps are updated in the Homey app by the user.
- **Unavailable devices:** check the battery first, then move the device closer to the Homey or a repeater, or repeat the pairing from the device page.
- **Broken flows:** open the flow in the Homey app; a warning on a card usually points at a deleted device or app. Fix or delete it.
- **Crashing apps:** restart the app from its page in the Homey app, then update it or write to its developer.
- **Power:** use the original power supply and a short, good cable.
- **Backup:** create one in the Homey app under Settings, Backups, or use Homey Backups if the user subscribes. A manual backup before firmware updates is cheap.
