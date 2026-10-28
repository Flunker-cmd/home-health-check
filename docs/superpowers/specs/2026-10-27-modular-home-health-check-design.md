# Modular home-health-check and Agensi launch: design

Date: 2026-10-27. Status: approved by the author 2026-10-27.

## Intent

home-health-check is a Claude Code plugin with four skills: `home-inventory`, `pi-health-check`, `router-health-check` and `windows-health-check`. Each check runs a read-only collector script, assesses what it finds, and ends with a ranked list of fixes. The repo is public under the MIT license.

The marketplace Agensi.io asked to list the skills. The author's goals, in order:

1. **More people use what he built.** This is the main goal.
2. **It earns its first dollar.** This is a nice-to-have, not the point.

While planning that, the author decided how the project should be shaped. **Every skill is an independent module that also feeds one shared picture of the home.** You can run any skill on its own and get a full answer. When the shared core is present, every module also adds its findings to it. A report skill then combines all findings into one prioritized report for the whole home. New modules, such as macOS, Homey and later NAS or Home Assistant, plug in without changing the report.

## Goals

- A shared **core**: a data directory, the existing inventory, and a documented, versioned **findings format**. That format is the contract between the modules and the report.
- Every existing skill and every new skill keeps working on its own, and writes findings in the shared format when it can.
- New modules:
  - `macos-health-check`
  - `homey-health-check`
  - `home-network-report`, which combines all findings into one report
- macOS and Linux support for `home-inventory` and `router-health-check`. Today they need Windows to run their scripts.
- The skills work when installed as a Claude Code plugin **and** when delivered through Agensi to other agents such as Cursor, Copilot and Codex.
- A launch on Agensi: `home-inventory` free, and a paid pack of all modules.

## Non-goals

- Making the repo private, or keeping a separate paid code base. The GitHub repo stays public, MIT and complete. Agensi is an extra storefront for the same code.
- Promising third parties a stable module API. The format is designed so that others *could* build modules, with docs and a version number, but we don't announce it as a standard yet.
- Writing to or changing any device. Every collector stays read-only.
- Python or any other runtime the user has to install.

## Anti-goals

These would make the work a failure even if everything technically works:

- A module that is useless without the core or the report.
- A findings format so heavy that a module author, or an agent, can't follow it from one short reference page.
- Two copies of a skill that drift apart, such as a "plugin version" and an "Agensi version".
- Personal data in the repo or in Agensi listings. That covers IPs, MACs, hostnames, device names, family names and account details. The repo's existing rule still applies.
- A script that prompts the user, needs admin or root, or triggers an OS permission dialog.

## Constraints

From the repo's `CLAUDE.md`, and these still apply:

- Skills and scripts are in English. The agent answers in the user's language.
- Collectors are read-only and never prompt. Linux uses `sudo -n` only. Windows needs no admin. Checks that need more rights are marked as such.
- PowerShell runs on Windows PowerShell 5.1 (no `??`, `?.` or ternary) and stays ASCII.
- Bump `version` in `plugins/home-health-check/.claude-plugin/plugin.json` whenever skills change.

New constraints:

- **Shell scripts for macOS run on the stock `/bin/bash` 3.2.** That means no associative arrays, no `mapfile`, and no `${var,,}`. They use only tools that ship with macOS. On Linux they also run with bash and the standard Debian tools.
- **macOS collectors must not trigger TCC prompts.** These are the dialogs for Full Disk Access, Automation, contacts and so on. If a fact can only be read with Full Disk Access, the collector skips it and marks it "needs Full Disk Access". Example: some `tmutil` details.

Agensi platform facts, as checked on 2026-10-27 at agensi.io/docs/packaging, /security, /sell and /docs/what-you-can-sell:

- Only `SKILL.md` and other text files reach buyers. Plugins, `plugin.json`, hooks and slash commands are ignored.
- Upload a ZIP:
  - Every `SKILL.md` at any depth becomes a skill. Two or more make a "skill pack".
  - A `README.md` heading names the pack.
  - A `shared/` folder outside the skill folders goes to every skill in that pack.
- Limits:
  - Each script under 20 KB.
  - The buyer receives at most 200 text files and 6 million characters.
  - Executables and binaries are blocked.
  - Bundled dependencies are not allowed.
- **Scripts are not installed on disk.** The buyer's agent writes the script to a temp file, runs it, and deletes it.
- The upload form reads the frontmatter fields `name`, `description`, `summary`, `version`, `tags`, `keywords`, `use_cases` and `docs_url`.
- Every upload goes through:
  - An 8-point automated scan: file structure, file types, dangerous command patterns (including privilege escalation), secrets, environment-variable harvesting, a network access audit, obfuscation, and prompt injection.
  - An AI intent check.
  - A human review, which takes 24–48 h.
- Scoring: a failed check costs 20 points and a warning costs 5. Any failed check means human review before the skill goes live.
- Revenue: the creator keeps 70%. Payouts go through Stripe or USDC and require KYC.

## Architecture

```
            ┌──────────── core (data directory) ────────────┐
            │ inventory.md      findings/       reports/    │
            └───────▲───────────────▲───────────────▲───────┘
 home-inventory ────┘               │               │
 pi / router / windows / macos / homey ─ write ─────┘ (findings)
 home-network-report ── reads inventory + findings ─┘ writes reports/
```

### Data directory

- The location is `$HOME_HEALTH_CHECK_DIR` when set. Otherwise it is `~/.home-health-check`, which on Windows is `%USERPROFILE%\.home-health-check`. Every skill resolves it the same way, and the shared reference describes it once.
- Layout:
  - `inventory.md`: unchanged format, owned by `home-inventory`.
  - `findings/`: one file per module run, written by modules.
  - `reports/`: written by `home-network-report`.
  - `cache/`: for example the OUI vendor list, which today sits at the top level.
- On first run with the new layout, migrate quietly: move a top-level vendor list into `cache/`.
- Everything here is private. Skills never copy it into a repo, an artifact or anything shared, which is the existing rule. A folder the user syncs between their own computers is fine; see below.
- Moving the author's own data is **not part of the build**. It is done with the author as a separate local step after release. That path is personal and does not go in the repo.

### Several computers (decided: synced folder or copy)

Windows and macOS checks only read the machine they run on, so their findings are written on that machine. Two supported ways bring them together on the machine that runs the report:

1. **Synced data directory.** `HOME_HEALTH_CHECK_DIR` may point at a folder the user syncs between their computers, such as a cloud drive folder. SKILL.md and README mention the privacy trade-off in one line: the inventory and findings then sit in that cloud. This is safe by design for three reasons:
   - Findings file names are unique per run, module and device, so two machines never write the same file.
   - `inventory.md` write-back re-reads the file just before writing and changes only the rows that module owns.
   - If the report sees sync-conflict copies of `inventory.md`, such as `inventory (1).md`, it says so instead of picking one.
2. **Copy by hand.** When a module runs on a machine whose data directory has no `inventory.md`, it writes its findings file anyway. It then tells the user which file to copy into the `findings/` folder on the computer where they keep the inventory.

In both cases `home-network-report` lists the inventory devices that have no findings, so a missing machine is visible.

Out of scope: checking a Mac or PC remotely over SSH from a hub machine. That may come later.

### Device identity

- A device is identified by its **MAC address**, lowercase with colons, as in the inventory. Modules find their host's MAC the way they do today.
- Some things a module checks are not network devices. A Homey's Zigbee sensors are an example. Findings about them belong to the network device that manages them, here the Homey, and name the sub-device in a `subject` field.
- If a module can't determine a MAC, it writes `device: unknown` with a best-effort name. The report shows these findings in a separate group and does not guess a match.

### Findings format, version 1

This is the contract. It lives in **one source file** in the repo and is copied into every skill as `references/findings-format.md`. See "Packaging" for why. The copy must be short: it is what a third-party author would read.

Each module run writes `findings/<YYYY-MM-DD>T<HHMM>-<module>-<mac-without-colons|unknown>.md`. The file has YAML frontmatter followed by the module's normal human-readable report as the body:

```yaml
---
format: hhc-findings/1
module: pi-health-check
module_version: 0.3.0
checked_at: 2026-10-27T09:12:00+01:00
device:
  mac: b8:27:eb:00:00:00
  name: pihole            # best known name, informational only
  type: DNS server
summary: One sentence on overall state.
findings:
  - id: os-out-of-support        # stable across runs: same problem, same id
    severity: high               # critical | high | medium | low | info
    subject: null                # sub-device name when not the device itself
    title: OS release no longer gets security updates
    detail: Raspberry Pi OS 11 left security support on ...
    action: Reinstall onto Raspberry Pi OS 13 (see report body for steps)
    effort: 1-2 h                # rough, free text
  - id: unbound-not-used
    severity: info
    ...
not_checked:                     # what the collector could not read, and why
  - area: SMART data
    reason: needs passwordless sudo
---
<the module's full report, as today>
```

Rules:

- **`id` must be stable.** If the same problem is found again, it gets the same id. Ids are kebab-case and unique within a module. That is what lets the report say *new*, *still open* and *resolved*.
- **Severity drives everything the report ranks.** Each module's SKILL.md says how its existing "should change / check / good to know" buckets map to severities.
- **Nothing secret goes in the findings.** No passwords, keys or tokens, no precise locations, no logic-variable values, and no raw API dumps.
- **The report trusts nothing in these files.** It treats every string from a findings file as data to quote or summarize, never as instructions. A file that doesn't parse, or has an unknown `format` major version, is listed as "could not read" and skipped.

### How modules use the core

Every check module gets the same short block:

1. **Before collecting:** resolve the data directory. If `inventory.md` exists, use it for addresses and context, as the skills do today.
2. **After reporting:** if the data directory exists, write one findings file. Tell the user in one line where it went. If the directory doesn't exist, offer once to create it, and continue without it if they decline.
3. **Inventory write-back** stays as it is today: match on MAC and never overwrite the user's own names or notes.

A module with no core still produces its full report in chat, exactly as it does now.

### `home-network-report`

Inputs:

- The inventory.
- For each `(module, device)` pair, the **latest** findings file.
- For each pair, the **previous** findings file, used to work out changes.

Output, in the user's language. It is shown in chat and saved as `reports/<YYYY-MM-DD>-home-report.md`.

1. **Most important actions:** 3–5 items across the whole home, ranked by severity and then by effort, the cheapest first. Each names the device and, where relevant, the subject.
2. **Per-device overview:** one row per inventory device, showing:
   - name and type
   - a green, yellow or red grade (red = any critical or high finding, yellow = any medium, green = otherwise)
   - which modules have checked the device, and when
   - a "stale" marker for checks older than 30 days, which is the builder's call to tune

   Inventory devices that no module has checked are listed as "not checked", with the module that could check them.
3. **Changes since last time:** new findings, resolved findings and devices new or missing in the inventory. This section is omitted on the first run.

Cross-module correlation: when two modules report on the same device, the report shows those findings together. Example: the Homey says the Pi-hole is unreachable, and the Pi check says it rebooted recently.

Out of scope: a single total score for the home. The author rejected it.

## Changes to the existing skills

For all four:

- Add the core block (data directory, findings write, severity mapping) and `references/findings-format.md`.
- **Make script invocation work in both modes.** As a plugin, the script sits next to SKILL.md. Via Agensi, the agent materializes it to a temp file. The instruction should name the script by its path relative to the skill (`scripts/collect.ps1`) and say: "run it from this skill's folder, or, if your agent delivers skill files without a folder, write it to a temporary file and run that". The builder picks the exact wording. Both modes must work.
- **Agent-neutral wording.** Remove the assumptions about "Claude Code session" and "Claude desktop app's built-in browser / Claude in Chrome". For example, the router skill's browser mode becomes "if your agent can control a browser". The README can stay Claude-first.
- **A "Network and permissions" section in every SKILL.md.** It lists every outbound endpoint, every use of elevated rights and every file written, and why each is needed. This is meant to turn scanner findings into disclosed behavior. Known items:
  - `discover.ps1`: downloads the Wireshark `manuf` list from wireshark.org, optional with `-Oui`; makes HTTP GET requests to local devices' UPnP description URLs; does reverse DNS lookups.
  - `probe.ps1`: pings and runs a 3-hop traceroute to 1.1.1.1, 9.9.9.9 and 8.8.8.8; looks up `doubleclick.net` to test DNS filtering; sends a UPnP SOAP read to the gateway.
  - `collect.sh` (Pi): uses `sudo -n` only, never with a password, and skips what it can't read.
  - `collect.ps1` (Windows): runs `winget upgrade` as a list-only call, which can be skipped with `-SkipWinget`.
  - All Windows invocations: use `-ExecutionPolicy Bypass` for this process only, so an unsigned local script can run.
- **Scanner policy (decided):**
  - The same scripts ship in both channels. There are no Agensi-only variants.
  - Behavior that may trip the scan is **disclosed**, not hidden or removed. Examples: `-ExecutionPolicy Bypass`, `sudo -n`, the vendor-list download and the UPnP read.
  - If the scan fails a check, the listing goes through Agensi's human review, and that is accepted.
  - A script is changed only when the change is just as good for GitHub users. For example, secrets are read from files, never from environment variables.
  - The author has asked Agensi how the scan treats read-only local scripts. If the answer changes this policy, it is updated before the first upload.
- **Frontmatter:** add `summary`, `version`, `tags`, `keywords`, `use_cases` and `docs_url`, pointing at the GitHub repo. **The builder must first check** that `claude plugin validate .` and Claude Code's skill loader accept the extra fields. If they don't, keep the plugin frontmatter minimal and have the packaging step add the Agensi fields to the zipped copies.
- **Severity mapping:** each skill's existing report structure stays. The SKILL.md adds the mapping to severities.

`home-inventory`:

- Add `scripts/discover.sh` for macOS and Linux. It produces the same text and `-Json`-equivalent output as `discover.ps1`, so the identify and save steps don't care which script ran. It uses only built-in tools:
  - ping sweep
  - `arp -an`
  - `dns-sd` or `avahi-browse` if present
  - `nc -z` for ports
  - `curl` for the UPnP description and the OUI list
- It does not write findings. It owns the inventory. Its listing on Agensi is the free entry point.

`router-health-check`:

- Add `scripts/probe.sh` for macOS and Linux, with the same sections and output as `probe.ps1`.

## New modules

### `macos-health-check`

Read-only health check of the Mac it runs on. It has no sudo, no prompts and no TCC dialogs. Areas, which the builder may refine:

- **OS:** macOS version, and whether it is still supported, looked up online as the other skills do.
- **Updates:** pending software updates (`softwareupdate -l`, which is slow and may need a timeout).
- **Security:** FileVault, SIP, Gatekeeper, firewall and XProtect version.
- **Backup:** Time Machine destination and last backup, where readable without Full Disk Access.
- **Disk:** free space and SMART status.
- **Startup:** login items and background items, from the user-level LaunchAgents and the system ones that are listable.
- **Apps:** outdated Homebrew packages, if Homebrew is installed, and apps from unidentified developers, where cheaply readable.
- **Crashes and panics:** in the last 30 days, from the user-readable DiagnosticReports.

Collector: `scripts/collect.sh`, under the bash 3.2 rules above. It is tested on the author's own Mac, through SSH or run locally.

### `homey-health-check`

Read-only health check of an Athom Homey Pro. A throwaway spike on the author's Homey Pro (Early 2023, firmware 13.5) on 2026-10-27 established the following.

**Data source.** The primary source is the **local Web API** with a user-created API key that has **only read permissions**. All of these answered over plain HTTP on the LAN:

- `/api/manager/system/`
- `/api/manager/devices/device/`
- `/api/manager/flow/flow/`
- `/api/manager/flow/advancedflow/`
- `/api/manager/apps/app/`
- `/api/manager/zones/zone/`
- `/api/manager/zigbee/state`
- `/api/manager/zwave/state`
- `/api/manager/updates/update/`
- `/api/manager/notifications/notification/`

`/api/manager/backup/` returned 404. Backup status has to be read from notifications whose owner is "Backups".

The **Homey MCP connector** is a limited fallback for agents that have it. It has no device availability, no last-seen time, no app or firmware state and no Zigbee or Z-Wave state. It also needs one call per flow to see `broken`, and it rate-limited after about 10 calls. When only MCP is available, the skill says what it could not check.

**Finding the Homey.** Use the inventory row with vendor Athom. Otherwise ask the user.

**The API key.**

- The user creates the key in the Homey web app with read-only permissions. The SKILL.md explains how.
- The skill reads the key **only from a file** whose path the user gives. It never reads it from an environment variable, because Agensi's scan flags environment-variable harvesting.
- The key is never printed, never written to the data directory or the findings, and never put on a command line that the agent echoes back.
- The skill tells the user they can revoke the key afterwards.

**Checks, and which fields they use.** All of these were verified in the spike.

- **System:** model, `homeyVersion`, uptime, `rebootReason`, memory, `loadavg`, available updates, and the insights logs for undervoltage and memory trend, if cheap.
- **Backup:** the latest "Backups" notification. If it is a failure, or there is no backup notice for a long time, report it as **high**.
- **Devices:**
  - `available == false`, together with `unavailableMessage`.
  - `warningMessage`.
  - `firmwareUpdate.state == "available"`, with the versions and `requiresWake`.
- **Staleness.** The latest `capabilitiesObj.*.lastUpdated`, read as either an ISO string or epoch milliseconds, together with `lastSeenAt`. It is applied **only to devices that report on their own** (sensor-like classes), because lights and TVs only update when they change.
- **Batteries:**
  - `measure_battery` and `alarm_battery`, with `energyObj.batteries` showing the battery type.
  - **Safety-critical sensors** (water leak, smoke, CO) that have **no** battery capability get their own finding, because their health can't be monitored.
- **Flows:** all flows from both endpoints, with `broken` and `enabled`.
- **Apps:**
  - `crashed`, `crashedCount`, `state != running`, `enabled == false` and `updateAvailable`.
  - `origin != appstore`, shown as info only, because self-developed apps are normal.
- **Zigbee:** `zigbee_ready`, `zigbee_error` and the node count. **Z-Wave:** node count and the `noAckNodes` count.
- **Notifications in the last 14 days:** counts per owner, plus lines that match problem keywords such as integration sync disabled or connection lost. Show only matching excerpts, never the full notification feed.
- **Tidiness, at info level:** devices left in the top-level zone, empty zones, names with leading or trailing spaces, and disabled leftover flows.

**Privacy rules specific to Homey.** Homey data is very personal.

- Never output the raw Z-Wave state, which contains the network keys.
- Never output logic-variable values.
- Never output vehicle or phone locations.
- Never output notification text beyond keyword-matched excerpts.
- Pick fields explicitly. Never dump whole API responses.

**Collector.** It must run from Windows, macOS and Linux without installs. The builder chooses between:

- a `collect.ps1` plus `collect.sh` pair, where the `.sh` uses `curl` and must parse JSON without `jq` unless it is present, or
- having the agent call the endpoints itself with the instructions above.

The choice must respect the "never echo the key" rule.

**Findings.** Device = the Homey's MAC from the inventory. Sub-device problems use `subject`.

## Packaging and distribution

- **One source of truth.** The skill folders in `plugins/home-health-check/skills/` are what both channels ship.
- **The contract file.**
  - The single source is `plugins/home-health-check/shared/findings-format.md`, or another spot the builder picks.
  - It is copied into each skill's `references/`, because Agensi delivers `shared/` only within one pack listing, and single-skill listings must carry it themselves.
  - A check fails when the copies differ from the source. It can run as part of validation, or as a small script run before release.
- **An `agensi/` folder in the repo** holds only what is specific to Agensi:
  - the pack `README.md` that names the pack
  - the listing texts (title, summary, description, tags, price notes) for each listing
  - the packaging script

  It never holds copies of the skills, and never holds anyone's inventory, findings or reports. The skills are taken from `plugins/home-health-check/skills/` when packaging. *(Builder's reading of the author's request to "keep what is published to Agensi apart from my own checks and data". To confirm with the author.)*
- **A packaging script in the repo** builds the Agensi ZIPs into an output directory given as an argument, never inside the repo:
  - One **pack** ZIP containing all skills and a `README.md` that names the pack.
  - One ZIP **per skill**, for single listings.
  - It strips anything Agensi rejects, and checks the per-script size (under 20 KB) and the total file count.
- The Claude Code plugin and the `flunker` marketplace keep working as today.

## Launch

1. **Agensi listings:**
   - **`home-inventory`: free.**
   - **The full pack:** all modules plus `home-network-report`, at a low one-time price. The author sets the final price, in the range of 3–5 USD.
   - Optionally, single paid modules later.
2. Every listing links to the GitHub repo. The repo stays public and MIT.
3. Before the first upload, the author sets up Stripe and KYC on Agensi.
4. The author follows up on Agensi's outreach email. That is outside the build.

**Scope and order:**

- **Before launch:**
  - the core, the contract and the four existing modules adapted
  - `macos-health-check`, plus the macOS/Linux scripts for inventory and router
  - `home-network-report`
- **First module after launch:** `homey-health-check`. It can join the launch if it is ready.
- **Later ideas, not designed here:** NAS (Synology, TrueNAS, Unraid), Home Assistant and a Docker host.

## Testing

- `claude plugin validate .`
- Real devices:
  - Pi over SSH
  - the Windows PC: PowerShell 5.1, `-NoProfile -ExecutionPolicy Bypass`
  - the author's Mac: stock `/bin/bash`, and confirm that no permission dialog appears
  - the author's Homey Pro, with a read-only key
- Agensi-style delivery: run each skill in a session where the skill's folder is **not** on disk. Only SKILL.md content and the script text are given, and the agent has to materialize the script. This confirms the dual-mode instructions.
- The report:
  - with zero findings
  - with one module
  - with all modules
  - with a second run, to check new/resolved detection by `id`
  - with one malformed findings file
  - with a findings file whose text tries to give instructions; the report must quote it, not obey it
- Before every commit, a privacy pass: no IPs, MACs, hostnames or names from real checks anywhere in the repo or the ZIPs. The examples in docs use placeholder values.

## Left to the builder

- Exact SKILL.md wording, including the dual-mode script instruction and the Network and permissions sections.
- Where the contract's single source lives, and how the copy check runs.
- Packaging script language: PowerShell 5.1 or bash, following the existing conventions.
- The Homey collector approach, within the constraints above.
- The thresholds:
  - stale-check age
  - sensor staleness days
  - low-battery percentage
  - how long without a backup notice counts as a problem
- The macOS area details beyond the list above.
- Splitting the work into releases and version bumps.
- Updating `README.md` and the repo's `CLAUDE.md` to describe the core, the findings contract, `HOME_HEALTH_CHECK_DIR` and the bash 3.2 rule.
