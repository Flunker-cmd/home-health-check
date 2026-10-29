# homey-health-check: implementation plan (4 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `homey-health-check` skill: a read-only check of a Homey Pro over its local Web API, run from Windows, macOS or Linux, that ends in a prioritized fix list and writes `hhc-findings/1` findings.

**Architecture:**
- Two collectors with **identical output**: `scripts/collect.ps1` (Windows PowerShell 5.1) and `scripts/collect.sh` (bash 3.2 wrapper around an embedded perl program that uses the core modules `HTTP::Tiny` and `JSON::PP`; the repo's `mac-safe` rule forbids `osascript`, and perl ships with macOS and Debian).
- Each collector has two layers: **fetch** (HTTP with the key, or read saved responses from a folder with `--from-dir`/`-FromDir`) and **render** (pure: parsed responses + a fixed "now" -> report lines). Picking fields happens in render, so no raw response ever reaches stdout.
- One set of anonymized JSON fixtures in `tools/fixtures/homey/` and one expected output file. The shell test and a new PowerShell test both run their collector on the fixtures and compare with that file, which keeps the two collectors in step.

**Tech Stack:** bash 3.2, perl 5 core modules (`HTTP::Tiny`, `JSON::PP`), Windows PowerShell 5.1 (`Invoke-WebRequest`, `ConvertFrom-Json`), Markdown SKILL.md.

**Spec:** `docs/superpowers/specs/2026-10-28-homey-health-check-design.md` (wins where it differs from) `docs/superpowers/specs/2026-10-27-modular-home-health-check-design.md`. Read both, especially *Spike results*.

Work on branch `homey` (already created off `main`, holds the design commit). No eval suite in this plan: the collectors carry the logic and are tested on fixtures; the spec leaves evals optional.

## Global Constraints

- Everything from plans 1 and 2 still applies: English skills, read-only collectors that never prompt, privacy placeholders in the repo (MACs ending in `00:00:00`, IPs in `192.168.1.x`), scripts under 20480 bytes, PowerShell 5.1 and ASCII, bash 3.2 rules and the `sh-portable`/`mac-safe` checker rules, stdin-safe shell scripts whose last line is `main "$@"`, build output outside the repo.
- **The key** is read only from the file passed as `--key-file`/`-KeyFile` (first line, trimmed). Never from an environment variable, never as an argument value, never printed, never in an error message, never written to disk. In perl it stays inside the perl process (`HTTP::Tiny` header); in PowerShell inside a variable used only for the `Authorization: Bearer` header.
- **Never print:** the key, `lastValue` from the Insights log list, any Insights log outside `homey:manager:system:*` and `homey:manager:apps:*-mem`, logic variables, the Z-Wave state beyond the two counts, `wifiSsid`, locations, `cloudId`, notification text from owners other than the keyword match rule (below), whole responses.
- **HTTP only** (`http://<host>`): the spike found no local HTTPS. Timeout 15 s per call, 200 ms pause between calls. A 401/403 prints `not checked: <area>: key lacks permission`; a connection failure on the first call prints `error: cannot reach the Homey at <host>` and exits 3.
- **Collector options:** `--host <ip or name>` (required), `--key-file <path>` (required unless `--from-dir`), `--from-dir <dir>` and `--now <ISO 8601 UTC>` (documented in `--help` as "offline: read saved API responses, for testing"), `--help` (exit 0), unknown option -> usage on stderr, exit 2. PowerShell: `-Homey`, `-KeyFile`, `-FromDir`, `-Now`.
- **Fixture folder layout** (also what `--from-dir` reads): `system.json`, `devices.json`, `flows.json`, `advancedflows.json`, `apps.json`, `zones.json`, `zigbee.json`, `zwave.json`, `updates.json`, `notifications.json`, `backup-state.json`, `insights-logs.json`, `memory-24h.json`, `memory-7d.json`, `memory-31d.json`, `undervoltage-31d.json`, and `app-mem/<app id>.json` (31-day series). A missing file behaves like a 404 for that call.
- **Insights entries:** `GET /api/manager/insights/log/number/<log id>/entry?resolution=last24Hours|last7Days|last31Days`; `values: [{t, v}]`, an outage is `v: null` (spike results).
- **Version:** `plugin.json` and every SKILL.md go to `0.6.0`.

## Output format (both collectors, byte for byte)

Sections start with `## <name>`; facts are `key: value`; list items are indented two spaces; anything not readable is `not checked: <area>: <reason>` with reason `key lacks permission`, `not available`, `untested model` or `timed out`. Dates are UTC `YYYY-MM-DDTHH:MMZ`. Sections and keys, in order:

```
## Homey
model: <homeyModelName>
model_tested: yes|no
firmware: <homeyVersion>
firmware_update: none|<version> (<channel>)
booted: <bootDate>
uptime_days: <1 decimal>
reboot_reason: <rebootReason or unknown>
memory: <used MB> MB used of <total MB> MB
loadavg: <3 values, 2 decimals>
power: undervoltage_now=<yes|no> undervoltage_seen=<yes|no> throttled_seen=<yes|no>
network: wifi|ethernet
wifi_signal: <wifiStrength> dBm, <wifiFrequency> MHz        (only when on Wi-Fi)
mac: <MAC of the connected interface, lowercase, colons>
address: <wifiAddress or ethernetAddress>
## Stability
outages_24h: none|<n>
  <start> <minutes> min
outages_7d: ...  outages_31d: ...                           (same shape; hours for 7d/31d)
memory_trend_31d: <first-week mean> MB -> <last-week mean> MB (<+/-n>%)
undervoltage_31d_max: <percent>
  app_memory: <app name> <first-week mean> -> <last-week mean> MB   (top 3, only when the trend is >= 20 %)
## Backup
backup_state: <backupStateString>
backup_error: none|<backupError>
backup_notices: <n> since <oldest notification date>
  <date> <failed|succeeded|other>: <excerpt, max 120 chars>
## Apps
apps: <n> (<n running>)
  <name> <version>: <crashed N times|not running (<state>)|disabled|update <version>|origin <origin>>
## Devices
devices: <n>
  unavailable: <name> [<class>] <zone>: <unavailableMessage>
  warning: <name> [<class>]: <warningMessage>
  firmware: <name>: <current> -> <new><, needs wake if requiresWake>
  stale: <name> [<class>] last <date> (<n> days)
## Batteries
  low: <name> <level>%<, alarm>
  alarm: <name> alarm_battery on
  no_battery_report: <name> [<capability that makes it safety-critical>]
## Flows
flows: <n> (<n enabled>), advanced: <n> (<n enabled>)
  broken: <name>
  disabled: <name>
## Radio
zigbee: ready=<yes|no> error=<none|text> nodes=<n>
zwave: nodes=<n> no_ack=<n>
## Notifications (14 days)
  <ownerName>: <count>
  match <date> <ownerName>: <excerpt, max 120 chars>
## Tidiness
  no_zone: <name>        (device in the top-level zone)
  empty_zone: <zone name>
  name_spaces: <name>
```

Rules the format fixes:
- **Stale** = class `sensor` or `thermostat`, newest of `lastSeenAt` and every `capabilitiesObj.*.lastUpdated` (ISO string or epoch ms) older than 3 days before "now"; a device with neither prints `last never`.
- **Low battery** = `measure_battery` <= 20.
- **Safety-critical** = has `alarm_water`, `alarm_smoke`, `alarm_co` or `alarm_heat`, and has neither `measure_battery` nor `alarm_battery`.
- **Outages:** consecutive `v: null` buckets form one outage; the last bucket is ignored when null (it is the bucket in progress).
- **Memory trend:** means of the non-null values in the first and last 7 days of the 31-day series; `app_memory` only when the trend is >= +20 %, reading `app-mem/` (one call per app memory log found in the log list).
- **Notification keyword match** (case-insensitive): `backup`, `offline`, `disconnect`, `connection lost`, `lost connection`, `unreachable`, `failed`, `error`, `crash`, `sync.*disabled`, `battery`. Owners `homey:manager:presence` and `homey:manager:security` are counted, never matched or quoted.
- **Backup notice kind:** owner `homey:manager:backup`; `failed` if the excerpt matches `(?i)problem|fail|error`, `succeeded` if it matches `(?i)success|complete|created`, else `other`. All notices in the window are listed (no 14-day limit for this owner).
- **Model tested** = `homeyModelName` contains `(Early 2023)`. When `no`, every unreadable field prints `not checked: <area>: untested model` instead of an error.
- Lists are sorted by name (ordinal, case-insensitive) so both collectors agree.

## Review Focus

1. **A secret slips into output.** The key in an error message (PowerShell exceptions can echo request headers), a logic variable's `lastValue` from the log list, the SSID, or Z-Wave keys. Expected: none of them ever printed. Covered in Task 1, Step 3 (fixtures carry canary values), and Tasks 2 and 3, Step 1 (`no canary in output` tests).
2. **Notification text from presence or security owners** names family members ("<name> came home"). Expected: counted per owner, never quoted, even when it contains a keyword. Covered in Tasks 2 and 3, Step 1 (`presence notice not quoted`).
3. **The two collectors drift apart** (one rounds differently, sorts differently, or formats dates in local time). Expected: identical output on the fixtures. Covered by both tests comparing with the one `expected.txt` (Tasks 2 and 3).
4. **PowerShell 5.1 and big responses:** `ConvertFrom-Json` in 5.1 fails above about 2 MB, and a Homey with many devices returns a large `devices.json`. Expected: it still works. Covered in Task 3, Step 1 (`devices.json` padded to 3 MB in a test-only copy) and the real run in Task 5.
5. **A key without some read permission, or an older Homey Pro.** Expected: `not checked: <area>: key lacks permission` / `untested model` for that area, everything else still reported, exit 0. Covered in Tasks 2 and 3, Step 1 (fixture folder without `zwave.json`, and a `system.json` copy with another model name).

---

### Task 1: Fixtures from the author's Homey and a PowerShell test harness

**Files:**
- Create: `tools/fixtures/homey/*.json` (layout in Global Constraints), `tools/fixtures/homey/expected.txt`, a section in `tools/fixtures/README.md`
- Create: `tools/test-ps.ps1`, `tools/tests/test-harness.ps1`
- Modify: `CLAUDE.md` (Test section: the PowerShell test command and the Homey collector commands)

**Interfaces:**
- Produces: `tools/test-ps.ps1 [<test file>...]`, default every `tools/tests/test-*.ps1`. Test files are dot-sourced and get `Assert-Eq <name> <expected> <actual>`, `Assert-Match <name> <regex> <actual>`, `Get-Fixture <relative path>`, `$HhcTmp` (removed at exit), `$HhcRoot`. Prints `ok <name>`/`FAIL <name>` lines like `test-sh.sh`, then `OK <n> tests` (exit 0) or `<k> failures` (exit 1).
- Produces: the fixture folder, consumed by Tasks 2 and 3.

- [ ] **Step 1: Write `tools/tests/test-harness.ps1`** asserting that `Assert-Eq` passes on equal strings, `Assert-Match` on a match, and `Get-Fixture 'homey/system.json'` returns an existing path.
- [ ] **Step 2: Run it:** `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-ps.ps1` -> fails (harness missing).
- [ ] **Step 3: Implement `tools/test-ps.ps1`**, then capture fixtures. Write a throwaway capture script in `D:\dev\tmp\` (never the repo) that saves every response in the layout above from the author's Homey, using the key file the author names (the spike used `D:\dev\.secrets\homey-api-key.txt`). Anonymize into `tools/fixtures/homey/`:
  - Keep the structure and field names; cut lists to a handful of items that cover every rule in *Output format*: one unavailable device, one with `warningMessage`, one firmware update, one stale sensor, one sensor with lastUpdated as epoch ms and one as ISO string, one low battery, one battery alarm, one leak sensor without battery capabilities, one broken flow, one disabled flow, one advanced flow, one crashed app, one disabled app, one non-appstore app, one device in the top-level zone, one empty zone, one name with a trailing space.
  - Replace every name with a generic one (`Leak sensor 1`, `Hallway`), IDs with new UUIDs, IPs and MACs with placeholders, and `wifiSsid`, `cloudId`, `hostname` with `REDACTED`.
  - **Canaries:** put `CANARY-KEY` in a notification from `homey:manager:presence` whose excerpt also contains `offline`; `CANARY-LASTVALUE` as `lastValue` of a `homey:manager:logic:*` log in `insights-logs.json`; `CANARY-SSID` as `wifiSsid`; `CANARY-ZWAVE` in a key-like field of `zwave.json`.
  - Insights: `memory-24h.json` gets one run of three null buckets and a null last bucket; `memory-31d.json` a +25 % trend; two files in `app-mem/`.
  - Notifications: one backup failure notice (the real wording from the spike), one `homey:manager:security` notice with `error` in it.
  - Record the real field names of `zigbee.json` (ready, error, node count) and `zwave.json` (node count, `noAckNodes`) in the fixtures README; Tasks 2 and 3 read exactly those.
  - Raw captures stay in `D:\dev\tmp\`; delete them when Task 5 is done.
- [ ] **Step 4: Write `expected.txt` by hand** from the fixtures and the *Output format* rules, with `--now 2026-10-28T12:00Z`. This file is the spec for both collectors; derive every line from the rules, not from a collector's output.
- [ ] **Step 5: Run** `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-ps.ps1` -> `OK 3 tests`; `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-skills.ps1` -> OK (privacy rule scans `tools/`).
- [ ] **Step 6: Commit** `Add Homey fixtures and a PowerShell test harness`.

### Task 2: `homey-health-check/scripts/collect.sh`

**Files:**
- Create: `plugins/home-health-check/skills/homey-health-check/scripts/collect.sh`
- Create: `tools/tests/test-collect-homey.sh`

**Interfaces:**
- Consumes: fixtures and `expected.txt` from Task 1; `load_script`, `assert_eq`, `assert_match`, `fixture`, `$HHC_TMP` from `tools/test-sh.sh`.
- Produces: `bash collect.sh --host <h> --key-file <f>` prints the report in *Output format*. Shell functions: `usage`, `check_perl` (prints `error: needs perl with HTTP::Tiny and JSON::PP` and exits 4 when missing), `homey_perl` (prints the perl program on stdout), `main`.

- [ ] **Step 1: Write `tools/tests/test-collect-homey.sh`:**
  - `collect.sh on fixtures matches expected.txt`: `bash "$COLLECT" --host 192.168.1.50 --from-dir "$(fixture homey)" --now 2026-10-28T12:00Z` equals the file's content.
  - `no canary in output`: the output does not match `CANARY`.
  - `presence notice not quoted`: no `match` line names the presence owner.
  - `missing zwave.json`: copy the fixtures to `$HHC_TMP` without `zwave.json`; output contains `not checked: zwave: not available` and still the `## Flows` section; exit 0.
  - `untested model`: copy with `homeyModelName` `Homey Pro (2019)`; `model_tested: no`.
  - `--help` exits 0, `--bogus` exits 2, missing `--host` exits 2; all three also via `bash -s -- <args> < collect.sh`.
- [ ] **Step 2: Run** `bash tools/test-sh.sh tools/tests/test-collect-homey.sh` -> FAIL (script missing).
- [ ] **Step 3: Implement `collect.sh`.** bash parses options and calls `perl -e "$(homey_perl)" -- <args>` (the program goes in as an argument, so it never competes with a script read from stdin; it holds no secret). `homey_perl` prints the program from a quoted heredoc. The perl program holds fetch and render. `HTTP::Tiny->new(timeout => 15)`; the key is read from the file inside perl. Write the perl so that no line matches the `sh-bash32`, `sh-portable` or `mac-safe` patterns (no `$0`, no `[@]`); the checker must pass without new exceptions.
- [ ] **Step 4: Run** `bash tools/test-sh.sh` -> all pass, and `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-skills.ps1` -> OK.
- [ ] **Step 5: Commit** `Add Homey collector for macOS and Linux`.

### Task 3: `homey-health-check/scripts/collect.ps1`

**Files:**
- Create: `plugins/home-health-check/skills/homey-health-check/scripts/collect.ps1`
- Create: `tools/tests/test-collect-homey.ps1`

**Interfaces:**
- Consumes: fixtures, `expected.txt`, the harness from Task 1.
- Produces: `powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -Homey <h> -KeyFile <f>` with the same output and exit codes as `collect.sh`.

- [ ] **Step 1: Write `tools/tests/test-collect-homey.ps1`** with the same six tests as Task 2 (run the script as a child `powershell -File` process with `-FromDir` and `-Now`), plus `large devices.json`: a copy whose `devices.json` is padded to over 3 MB with extra generic devices still renders the `## Devices` section.
- [ ] **Step 2: Run** `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-ps.ps1` -> FAIL.
- [ ] **Step 3: Implement `collect.ps1`.** PowerShell 5.1, ASCII. Parse JSON with `System.Web.Script.Serialization.JavaScriptSerializer` with `MaxJsonLength` raised (or another 5.1-safe way) so large responses work. On a web error print only the status code and the area, never `$_.Exception` text. Format numbers with the invariant culture so decimals match `collect.sh` on a Swedish Windows.
- [ ] **Step 4: Run** both harnesses and the checker -> all pass.
- [ ] **Step 5: Commit** `Add Homey collector for Windows`.

### Task 4: SKILL.md, checker, version 0.6.0, docs

**Files:**
- Create: `plugins/home-health-check/skills/homey-health-check/SKILL.md`, `references/findings-format.md` (via `tools/sync-contract.ps1`)
- Modify: `tools/check-skills.ps1` (`Test-FindingsSection` list gets `homey-health-check`)
- Modify: `plugin.json` and every SKILL.md to `0.6.0`; `home-network-report/SKILL.md:64` (name homey-health-check for a Homey); `home-inventory/SKILL.md:83` (inventory readers); `README.md`, `agensi/README.md`, `agensi/listings.md` (move Homey from *Coming* into the pack listing, "tested on Homey Pro (Early 2023)"); `CLAUDE.md` (the skill count in the first line)

**Interfaces:**
- Consumes: the collectors' option names and output format.

- [ ] **Step 1: Run the checker** after adding `homey-health-check` to `Test-FindingsSection` and creating an empty skill folder with only frontmatter -> it fails on `findings-section` and `network-section`.
- [ ] **Step 2: Write SKILL.md** following `macos-health-check/SKILL.md`'s shape (frontmatter with all checker keys, ground rules, 1 Collect, 2 Assess, 3 Report, Save findings, Standard finding ids, Network and permissions, Fixing). It must say:
  - Supported: Homey Pro (Early 2023), tested; other Homey Pro models untested; Homey Bridge / Homey Cloud not supported (no local API), with the reason, and the agent's Homey connector, if it has one, only for the few things it shows.
  - **Key:** how to create it in the web app (Settings > API Keys, only the read/"View" permissions), save it as a text file, give the path; never paste it in chat; it can be deleted afterwards. Never read from an environment variable.
  - Finding the Homey: inventory row with vendor Athom, else ask. If the collector's `address:` differs from the inventory IP, suggest a DHCP reservation (`ip-changed`).
  - Assess table per section; the stability text says plainly that short drops cannot be seen afterwards; on Wi-Fi with outages or weak signal (below -70 dBm) suggest Ethernet or a closer mesh node.
  - Backup: never take a backup; failed notice -> `backup-failed` (say it may be about the Homey Backups service, look in the app); no backup notices -> `no-auto-backup` (info, wording from the spec); last good backup date is `not_checked` with the manual backup steps.
  - Device = the `mac:` line; sub-devices in `subject`.
  - Standard ids (severity): `firmware-update` (low), `app-crashed` (medium), `app-not-running` (medium), `app-update` (low), `app-sideloaded` (info), `device-unavailable` (medium), `device-warning` (low), `device-firmware` (low), `sensor-stale` (medium), `battery-low` (medium; high for a safety-critical sensor), `safety-no-battery-report` (low), `flow-broken` (medium), `flows-disabled` (info), `zigbee-down` (high), `zwave-no-ack` (medium), `unplanned-reboot` (medium), `outage` (medium), `memory-trend` (low), `undervoltage` (medium), `wifi-weak` (low), `ip-changed` (low), `backup-failed` (high), `no-auto-backup` (info), `untested-model` (info), `tidiness` (info).
  - Network and permissions: HTTP to the Homey only, plain HTTP (no local HTTPS), key read from a file, the list of endpoints, no other calls, nothing written except findings and the inventory row.
- [ ] **Step 3: Run** `tools/sync-contract.ps1`, the checker, `bash tools/test-sh.sh`, `tools/test-ps.ps1`, `claude plugin validate .`, and `tools/test-package.ps1 -OutDir D:\dev\tmp\agensi-check` -> all OK, 8 ZIPs.
- [ ] **Step 4: Commit** `Add homey-health-check skill (0.6.0)`.

### Task 5: Real runs on the author's Homey

- [ ] **Step 1:** Run `collect.ps1` on Windows against the author's Homey with the real key file. Read the output for anything in *Never print*; check exit 0 and that every section has content or a `not checked:` line.
- [ ] **Step 2:** Run `collect.sh` the same way: in Git Bash on Windows, and on the Mac with `/bin/bash` if the author makes it reachable (CLAUDE.md, Test). Diff the two outputs with the PowerShell output; they must be identical apart from the moving clock.
- [ ] **Step 3:** Run the whole skill once in an agent session with the plugin, writing a findings file to the author's data dir. Check the file against the contract and that `home-network-report` lists the Homey.
- [ ] **Step 4:** Run the skill once in a session where no key file is given and the user declines to make one. Expected: it explains the key, and if the agent has a Homey connector it lists what that cannot show instead of presenting a partial check as complete.
- [ ] **Step 5:** Delete the raw captures in `D:\dev\tmp\`, run every check from Task 4 Step 3 again, commit fixes if any, and record the results in the plan's progress notes. Do not push.
