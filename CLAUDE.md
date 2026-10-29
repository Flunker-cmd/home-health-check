# home-health-check

Claude Code plugin (and its own marketplace, `flunker`) with a network inventory skill, five health-check skills (Pi/Linux, router/mesh, Windows, macOS, Homey Pro) and a report skill that combines their findings. The inventory lives in `~/.home-health-check/` on the user's machine and is read by the other skills. Built from real checks of a home setup in October 2026 (a Raspberry Pi running Pi-hole, a mesh router, a Windows desktop). The repo is public.

## Conventions

- Skills and scripts are in English so others can use them. Claude answers in the user's language.
- Collector scripts must stay **read-only** and must not prompt: `sudo -n` on Linux, no admin on Windows, mark checks that need more rights.
- PowerShell scripts must run on Windows PowerShell 5.1 (no `??`, `?.`, ternary) and stay ASCII.
- Nothing personal in the repo: no IPs, MACs, hostnames, names of family members or account details from the real checks.
- Bump `version` in `plugins/home-health-check/.claude-plugin/plugin.json` when skills change, so installed copies update. Every SKILL.md `version` must equal it.
- The findings contract source is `plugins/home-health-check/shared/findings-format.md`. After editing it run `tools/sync-contract.ps1`, which copies it into every skill's `references/`.
- SKILL.md files must be agent-neutral (no Claude-specific wording or tool names) and say `<data dir>`, never a literal data path. `tools/check-skills.ps1` enforces this.
- Shell scripts meant for macOS run on stock bash 3.2 (no associative arrays, `mapfile` or `${var,,}`) and never trigger permission dialogs.
- Skills and scripts are shipped unchanged to Claude Code and to Agensi. Agensi-only content lives in `agensi/`; build output goes outside the repo.

## Test

- `claude plugin validate .`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-skills.ps1` (contract copies, frontmatter, wording, sizes, privacy)
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-package.ps1 -OutDir <folder outside the repo>` (builds and checks the Agensi ZIPs)
- Pi collector: `ssh pi@<host> 'bash -s' < plugins/home-health-check/skills/pi-health-check/scripts/collect.sh`
- PowerShell tests: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-ps.ps1` (Homey collector against `tools/fixtures/homey/`, compared with its `expected.txt`)
- Homey collector: `bash plugins/home-health-check/skills/homey-health-check/scripts/collect.sh --host <homey> --key-file <file>` and `powershell -NoProfile -ExecutionPolicy Bypass -File plugins/home-health-check/skills/homey-health-check/scripts/collect.ps1 -Homey <homey> -KeyFile <file>`. The key file holds a read-only API key and stays outside the repo.
- Shell tests: `bash tools/test-sh.sh` (parsers against anonymized fixtures in `tools/fixtures/`). Also run it with `/bin/bash` on a Mac, because that is bash 3.2 with BSD awk and sed: copy `tools/` and `plugins/` over (`tar -c tools plugins | ssh <user>@<mac> 'mkdir -p /tmp/hhc-test && tar -x -C /tmp/hhc-test'`) and run `/bin/bash /tmp/hhc-test/tools/test-sh.sh`.
- Mac collector: `ssh <user>@<mac> 'bash -s' < plugins/home-health-check/skills/macos-health-check/scripts/collect.sh`. Permission dialogs never show over SSH: test them with a local run, in Terminal and inside the agent app.
- Windows scripts: `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`
- Report behavior: `claude plugin eval plugins/home-health-check --tag report --scaffold --allow-tools Write --trust-plugin --model sonnet --judge-model sonnet --no-publish` (7 cases in `plugins/home-health-check/evals/`). Each run is a real model session: while iterating add `--case <name> --runs 1 --ablation none`; the full run (3 runs, with and without the plugin) costs a few USD, so cap it with `--max-cost-usd`. Always pass `--no-publish`. `evals/results/` holds local transcripts and is never committed.
