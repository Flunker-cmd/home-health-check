# homey-health-check: design

Date: 2026-10-28. Status: draft for the author's review.

This replaces the `homey-health-check` section of `2026-10-27-modular-home-health-check-design.md`. Everything else in that spec (goals, anti-goals, constraints, the findings contract, Agensi packaging) still applies. Where the two disagree, this document wins.

## Intent

A read-only health check of an Athom Homey Pro that ends in a prioritized fix list, like the other modules, and writes findings so the home report includes the Homey.

It should catch what a Homey owner otherwise only notices once something has already stopped working: a leak sensor with a dead battery, a motion sensor that went quiet weeks ago, broken flows, an app that keeps crashing, Zigbee or Z-Wave nodes that no longer answer, and the Homey itself restarting or dropping off the network.

The author's own trigger: their Homey Pro used to show as offline in the phone app now and then, and they never knew whether it had restarted or only lost the network. It is stable now, but this is the kind of thing the check should help explain.

## Goals

- Everything in the original spec's check list (system, devices, staleness, batteries, flows, apps, Zigbee, Z-Wave, notifications, tidiness), with the changes below.
- A **stability** check that tells restarts apart from longer outages, as far as the Homey's own data allows.
- A **backup** check that respects a deliberate choice not to pay for automatic backups.
- Works as a Claude Code plugin skill and as an Agensi skill, run from Windows, macOS or Linux.

## Non-goals

- Changing anything on the Homey. That includes taking a backup, restarting, updating apps or firmware, or enabling flows. These become steps in the fix list that the user does in the Homey app.
- Supporting Homey Bridge (Homey Cloud). It has no local API.
- Explaining short network drops after the fact. The data to do so does not exist on the Homey (see Stability).

## Anti-goals

- Anything personal from the Homey leaving the collector: variable values, vehicle or phone locations, health data, notification text beyond keyword excerpts, Z-Wave network keys.
- The API key showing up anywhere: chat, command line, process list, logs, findings, the data directory.
- A red "no backup" finding on every run for a user who chose not to subscribe.
- Promising support for Homey models nobody has tested.

## Decided

### Supported models (author's choice, on the builder's recommendation)

- **Homey Pro (Early 2023): supported and tested.** The author has one (firmware 13.5 at the time of the spike on 2026-10-27).
- **Older Homey Pro (2016-2019):** the skill reads the model from `/api/manager/system/`. For any model other than Homey Pro (Early 2023) it runs the same calls, says once that this model is untested and some checks may be missing, and reports missing fields as "could not check", never as a fault.
- **Homey Bridge / Homey Cloud:** not supported. The skill says so up front and why. If the agent has the Homey MCP connector, it may mention that a few things are visible there, nothing more.
- The Agensi listing says "tested on Homey Pro (Early 2023)".

### Data source

The **local Web API** with an API key the user creates in the Homey web app with **read-only permissions**. The spike found these endpoints answering over plain HTTP on the LAN: `/api/manager/system/`, `devices/device/`, `flow/flow/`, `flow/advancedflow/`, `apps/app/`, `zones/zone/`, `zigbee/state`, `zwave/state`, `updates/update/`, `notifications/notification/` (all under `/api/manager/`). `/api/manager/backup/` returned 404.

The Homey MCP connector stays a limited fallback, as in the original spec: no availability, no last-seen, no app or firmware state, no Zigbee or Z-Wave state, rate-limited after about 10 calls. When it is the only source, the skill lists what it could not check.

Plain HTTP means the read-only key crosses the LAN unencrypted. The SKILL.md discloses this in *Network and permissions*. If the Homey also answers over local HTTPS, the builder may prefer that.

### Collection: scripts, not agent calls (builder's call)

A `collect.ps1` (Windows) and a `collect.sh` (macOS and Linux) do the work:

- They read the key from a file whose path the user gives. Never from an environment variable (Agensi's scan flags environment harvesting).
- The key never appears on a command line, in output or in an error message. With curl that means passing the header from a file or stdin, not as an argument.
- They pick fields explicitly and print one compact, human-readable summary. The agent never sees a raw API response. This puts the privacy rules in code instead of relying on the agent to follow instructions.
- They take the Homey's address as an argument (from the inventory or the user).

Constraints from the original spec still hold: no installs, PowerShell 5.1 and ASCII, stock bash 3.2 on macOS, no permission dialogs, read-only, no prompts. JSON must be parsed without `jq` on a stock Mac. How is left to the builder; it must ship with the OS (for example `osascript -l JavaScript` on macOS, or `python3`/`jq` on Linux when present, saying clearly what to do when neither is).

### Privacy, tightened

On top of the original spec's rules:

- The collector reads **only the Homey's own system logs** from Insights (`homey:manager:system:*`, such as memory, load, temperature, undervoltage). It never requests the Insights log list's other entries: user variables (`homey:manager:logic:*`) can hold health data, and device logs can hold vehicle and location data. Asking for the list of logs is fine; fetching entries outside `homey:manager:system:*` is not.
- Device findings name the device by its Homey name in `subject`, and never include capability values other than the ones a check needs (battery level, alarm state, last-updated time).

### Stability (new)

The spike looked at the author's Insights data through the MCP connector. Findings:

- The Homey keeps its own system logs. Over 31 days they come in 6-hour buckets, over 7 days in 1-hour buckets. A gap in buckets means the Homey was not recording, so it was down for at least that long.
- Short restarts or Wi-Fi drops do not show. The offline notice on the phone most likely comes from Athom's cloud, not from the Homey, and is not readable afterwards.
- A sudden drop in memory after a climb may mean a restart, but averages cannot prove it.

So the check reports:

- **Last restart and its reason** (`uptime`, `rebootReason` from the system endpoint). A restart reason that points at a crash, out-of-memory or power is a finding; a planned update is info.
- **Outages:** runs of null values in the system memory log over the last 24 hours, 7 days and 31 days, with start and length (see *Spike results*: the series has no missing timestamps).
- **Memory trend:** a steady climb over the 31 days is a low finding (possible leak in an app; the app memory logs `homey:manager:apps:*-mem` may name the app, if cheap).
- **Undervoltage ratio** above 0 is a finding (power supply or cable).
- **Wi-Fi or cable:** if the Homey is on Wi-Fi and there are outages or the user reports offline notices, the action suggests the Ethernet adapter or moving it closer to a mesh node.
- **Address changes (builder's call):** compare the inventory row's IP with the address that answered now. If they differ, mention a DHCP reservation. No IP history is added to the inventory or the findings.
- The report says plainly that short drops cannot be seen after the fact.

### Backup (changed)

The original spec read backup status only from "Backups" notifications and called "no backup notice for a long time" high. Without a subscription there are no such notices, so that rule would flag a deliberate choice on every run. Instead:

- **A failed automatic backup** (a "Backups" notification saying so): high.
- **No automatic backups in use:** one `info` finding, neutral wording, no sales pitch. Same id every run so the report shows it as "still open", not new.
- **Last manual backup**, if its date can be read: a reminder (`medium`) when it is old. Builder's call on "old": more than 90 days, or a firmware update since the backup, whichever the data supports.
- **Date not readable:** say so under `not_checked`, and give the steps to take a manual backup in the app. No severity guess.
- The skill never takes a backup. Taking one is a fix step the user does in the Homey app or web app.

**How "no automatic backups" is decided (builder's call):** from the data alone. The skill does not ask the user and keeps no state between runs. If an endpoint shows whether automatic backups are on, use it. Otherwise, no "Backups" notification in the period the Homey keeps gives the `info` finding, worded so a subscriber is not misled ("no automatic backup seen in the notifications; if you have Homey Backups, its notices may have expired").

The spike found no date (see *Spike results*), so the backup check is: `backup/state` error, failure notices, and `not_checked` for the last good backup's date.

### Findings

- Device = the Homey's MAC from the inventory row (vendor Athom). If the system endpoint gives a MAC, use it to confirm the row.
- Sub-device problems use `subject` with the Homey device name.
- Standard ids are listed in the SKILL.md, like the other modules. Builder picks them; they must cover at least: firmware or app update available, app crashed or not running, device unavailable, sensor stale, battery low, safety sensor without battery reporting, flow broken, Zigbee or Z-Wave problem, restart reason, outage, memory trend, undervoltage, backup failed, no automatic backup, manual backup old.

## Spike results (2026-10-28)

Run on the author's Homey Pro (Early 2023) with the key from the first spike, which the author confirmed was created with read permissions only. The scripts printed status codes, field names and counts only.

1. **Endpoints:** all endpoints in *Data source* and `/api/manager/insights/log` answer 200 with that key. The SKILL.md tells the user to tick only the read ("View") permissions; the exact names of the boxes were not checked in the web app.
2. **Insights works locally.** Entries are at `GET /api/manager/insights/log/number/<log id>/entry?resolution=<r>` (the log id unescaped or URL-encoded, e.g. `homey:manager:system:memory`; boolean logs presumably under `/log/boolean/`). The response has `start`, `end`, `step` (ms) and `values: [{t, v}]`. Buckets: `last24Hours` 5 min (288), `last7Days` 1 h (169), `last31Days` 6 h (125). `last2Years` returned only null values, so the system logs keep about a month.
   - **An outage shows as buckets with `v: null`, not as missing timestamps.** The time series is always complete. The outage check counts runs of null values. None in the author's data.
   - Five system logs exist: `clock`, `loadavg`, `memory`, `temperature`, `undervoltageratio`. 24 per-app memory logs exist (`homey:manager:apps:<app id>-mem`).
   - **Privacy:** the log list carries a `lastValue` for every log, including user variables. The collector may read the list only to find ids, and must never print `lastValue` or anything else from logs outside `homey:manager:system:*` and the app memory logs.
3. **Backup:** `GET /api/manager/backup/state` answers with `backupState`, `backupStateString` and `backupError` (here `idle`, no error). It gives no date and no kind. The notifications (250 kept, back about 40 days here, owner `homey:manager:backup`) held one notice on 2026-10-15: "Homey encountered a problem while creating a backup". So the Homey does attempt backups on this account even though the author does not pay for Homey Backups; why is unknown.
   - Consequence for the design: a "Backups" failure notice is real data, but it can come from an account with no subscription. The finding says what the notice says and that it may be about the Homey Backups service, and the action is "open Backups in the Homey app and look". No date of the last good backup is available locally, so "manual backup old" becomes a `not_checked` entry with the steps to take one, unless a notice of a successful backup is found within the notification window.
4. **Network:** the system endpoint has `wifiConnected`, `wifiMac`, `wifiStrength`, `wifiFrequency`, `wifiSsid` and `ethernetConnected`, `ethernetMac`, plus `bootDate`, `uptime`, `rebootReason` and `videoCoreUnderVoltage*` / `videoCoreThrottle*` flags. The author's Homey is on Wi-Fi. Use the MAC of the connected interface as the device identity; never print the SSID.
5. **No local HTTPS** on the IP (TLS handshake fails) or on the `homeylocal.com` name (does not resolve). Plain HTTP it is, disclosed in the SKILL.md.

The Homey Wi-Fi check in *Stability* can now use `wifiStrength` and `wifiFrequency` directly.

## Left to the builder

- Field names and exact JSON paths beyond those named here (verify against the author's Homey).
- How JSON is parsed in `collect.sh`, within the constraints.
- Staleness thresholds per device class, and which classes count as "reports on its own".
- The exact gap size that counts as an outage in each bucket size.
- Severity for each standard id, following the contract's definitions.
- Evals: follow the home-network-report suite's pattern if the builder adds them; anonymized fixtures only.

## Testing

- Collectors run against the author's Homey Pro from Windows and from the Mac (`collect.ps1`, `collect.sh`), and the output is checked by hand for any key, variable value, location or raw dump.
- Shell parser tests against anonymized fixtures in `tools/fixtures/`, run with bash 3.2 on the Mac as well.
- `tools/check-skills.ps1` and `tools/test-package.ps1` pass with the new skill included.
- A run with the MCP connector only, to check the fallback says what it could not check.
