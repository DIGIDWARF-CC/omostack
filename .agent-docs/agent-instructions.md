# Agent Instructions - Core Behavior Rules

This file defines how AI agents operate inside this omostack home. The repository is an operations base for OpenCode / oh-my-openagent configuration, diagnostics, repair, backup, rollback, and self-bootstrap on this machine. It is not an application repository.

## 0. Folder Ownership

| Role | Path | Tracked? | Purpose |
|------|------|----------|---------|
| Public docs | `.agent-docs/` | YES | Instructions, runbooks, sanitized templates, maintenance scripts |
| Private runtime state | `.my-omo/` | NO | Real keys, backups, downloads, temp files, private install state |
| OpenCode runtime state | `.omo/` | NO | Plans, evidence, continuation JSON, transient execution state |

Rules:
- Never commit `.my-omo/` or `.omo/`.
- Never read secret material unless the task explicitly requires it.
- Back up before modifying private state or global OpenCode / oh-my-openagent files.
- Prefer dry-run scripts (`--dry-run`) before any repair.

## 0.5 WSL/Linux Environment

This project targets **Ubuntu WSL bootstrap -> WSL/Linux operations**. The human-facing bootstrap script is `bootstrap-for-human/omo_bootstrap.sh`; agent maintenance scripts are Bash (`.sh`).

Key paths:
- Config: `~/.config/opencode/` or `$XDG_CONFIG_HOME/opencode/`
- Cache: `~/.cache/opencode/` or `$XDG_CACHE_HOME/opencode/`
- Data: `~/.local/share/opencode/` or `$XDG_DATA_HOME/opencode/`
- Scripts: `.agent-docs/scripts/*.sh` (bash)

Do not add active maintenance `.ps1` scripts under `.agent-docs/scripts/`. The active human bootstrap path is the root-only Ubuntu WSL shell script in `bootstrap-for-human/omo_bootstrap.sh`.

## 1. Intent Gate

Before acting, classify the request.

| Surface Form | True Intent | Routing |
|---|---|---|
| "explain", "how does this work" | Research | explore -> synthesize -> answer |
| "implement", "add", "create" | Change requested | inspect -> edit -> verify |
| "look into", "check", "investigate" | Investigation | inspect -> report findings |
| "what do you think" | Evaluation | evaluate -> propose -> wait |
| "error", "broken", "fails" | Repair | diagnose -> backup if needed -> minimal fix |
| "refactor", "improve", "clean up" | Open-ended maintenance | assess first -> propose bounded work |

## 2. Maintenance Protocol

1. Read `self-bootstrap-checklist.md` and `setup-directives.md`.
2. Inspect current state with non-destructive commands (`--dry-run`).
3. Classify tools as `missing`, `present`, or `unhealthy`.
4. Use `--dry-run` before destructive actions.
5. Back up before editing config, auth, cache, or private runtime state.
6. Keep public examples sanitized.
7. Run `scripts/check-scaffold.sh --all` after scaffold edits.

## 3. Verification Checklist

- `git ls-files -- .my-omo` prints no output.
- `git status --short -- .my-omo` prints no output.
- `.agent-docs/scripts/check-scaffold.sh --all` exits 0.
- Risky scripts support dry-run behavior and explicit confirmation flags.
- Documents contain no unfinished draft markers or vague placeholder text.

## 4. Failure Recovery

1. Stop after repeated failures and inspect root cause.
2. Stop after repeated same-intent attempts that yields no result to rethink and change the approach.
3. Do not keep retrying destructive commands.
4. Restore from backup when a repair changes global config or private state incorrectly.
5. Consult Oracle/review agents with full failure context for high-risk repairs.
6. Ask the user before touching secrets, deleting caches, or migrating real private files.

## 5. Agent Diagnostic Workflow (NEW)

When an agent encounters a problem:

1. Run `.agent-docs/scripts/diagnostic.sh` and save output to `.my-omo/diagnostic.json`.
2. Read the diagnostic JSON — it contains OS, PATH, tool versions, sanitized config metadata, systemd status, listening ports.
3. Cross-reference with `troubleshooting.md` for known fixes.
4. Apply minimal fix, then re-run health check: `.agent-docs/scripts/check-health.sh`.

This workflow lets even a weak agent diagnose and resolve most issues autonomously.
