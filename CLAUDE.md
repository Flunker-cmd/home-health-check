# home-health-check

Claude Code plugin (and its own marketplace, `flunker`) with a network inventory skill and three health-check skills: Pi/Linux, router/mesh, Windows. The inventory lives in `~/.home-health-check/` on the user's machine and is read by the other skills. Built from real checks of a home setup in October 2026 (a Raspberry Pi running Pi-hole, a mesh router, a Windows desktop). The repo is public.

## Conventions

- Skills and scripts are in English so others can use them. Claude answers in the user's language.
- Collector scripts must stay **read-only** and must not prompt: `sudo -n` on Linux, no admin on Windows, mark checks that need more rights.
- PowerShell scripts must run on Windows PowerShell 5.1 (no `??`, `?.`, ternary) and stay ASCII.
- Nothing personal in the repo: no IPs, MACs, hostnames, names of family members or account details from the real checks.
- Bump `version` in `plugins/home-health-check/.claude-plugin/plugin.json` when skills change, so installed copies update.

## Test

- `claude plugin validate .`
- Pi collector: `ssh pi@<host> 'bash -s' < plugins/home-health-check/skills/pi-health-check/scripts/collect.sh`
- Windows scripts: `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`
