# AGENTS.md - OhMyOpenCode Omostack Home (WSL/Linux)

## Purpose

This repository is the omostack home folder. It is used to configure, reconfigure, diagnose, repair, back up, roll back, and self-bootstrap OpenCode and oh-my-openagent on **WSL/Linux**.

This is not an application or software-development project. Agents should treat it as an operations base for maintaining the local agent environment.

---

## Environment

| Setting | Value |
|---------|-------|
| Timezone | Europe/Moscow |
| Locale | en-US |
| OS | WSL/Linux (Bash scripts, XDG paths) |

Adjust these values only when cloning this omostack home to another machine.

---

## Quick Start - OOBE Setup

For a fresh clone of this repository:

1. A human starts from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1
```

2. After Windows bootstrap has prepared WSL/Ubuntu/OpenCode, an agent continues inside WSL:

```bash
chmod +x .agent-docs/scripts/OOBE-setup.sh
.agent-docs/scripts/OOBE-setup.sh --auto
```

The PowerShell bootstrapper is the only human-facing installer. `OOBE-setup.sh` is stage-2 agent maintenance inside WSL/Linux. See `OOBE.md` for details.

---

## User Preferences

### Style Guide

- Be concise, but give progress updates during longer work.
- Be evidence-based: back claims with tool output, file references, or explicit observations.
- Delegate when a specialized OpenCode agent is useful, but keep the final result coherent.
- Avoid AI slop: no vague placeholders, no fake checks, no hidden destructive behavior.

### Git Conventions

- Commit messages use imperative English and no trailing period.
- Branch names use an issue-like code when available; otherwise choose a concise maintenance code.
- Keep commits atomic.
- Never commit secrets or machine-local private state.

---

## Folder Ownership

| Role | Path | Tracked? | Purpose |
|------|------|----------|---------|
| Public agent docs | `.agent-docs/` | YES | Instructions, runbooks, sanitized templates, and maintenance scripts |
| Private runtime state | `.my-omo/` | NO | Real keys, backups, downloads, temp files, private install state |
| OpenCode runtime state | `.omo/` | NO | Local plans, evidence, continuation JSON, transient execution state |

Rules:
- Never track `.my-omo/` contents.
- Never inspect or move real secret files unless the task explicitly requires it.
- Back up private state before cache repair, config rewrite, or rollback.
- Keep examples and templates sanitized under `.agent-docs/templates/`.

---

## Project Structure Reference

See `.agent-docs/README.md` for the complete navigation map.

| Path | Purpose |
|------|---------|
| `OOBE.md` (root) | Out-of-Box Experience guide — first file for new installs |
| `.agent-docs/README.md` | Entry point and document index |
| `.agent-docs/self-bootstrap-checklist.md` | First file a future agent should open |
| `.agent-docs/setup-directives.md` | Primary operations runbook (WSL/Linux) |
| `.agent-docs/scripts/` | Bash scripts for maintenance, verification, and repair |
| `bootstrap-for-human/omo_bootstrap.ps1` | Windows PowerShell bootstrapper for humans |
| `.agent-docs/recipes/troubleshoot.sh` | Interactive troubleshooting menu |
| `.agent-docs/templates/` | Sanitized OpenCode / oh-my-openagent examples |
| `.my-omo/remote-access/` | Canonical ignored folder for real remote-access keys and local pseudoconfigs |

---

## Quick Commands (Bash)

```bash
# Stage-2 OOBE setup inside WSL
.agent-docs/scripts/OOBE-setup.sh --auto

# Verify the scaffold itself
.agent-docs/scripts/check-scaffold.sh --all

# Safe health-check dry run
.agent-docs/scripts/check-health.sh --dry-run

# Config audit
.agent-docs/scripts/check-config.sh --dry-run

# Interactive troubleshooting menu
.agent-docs/recipes/troubleshoot.sh

# Full diagnostic dump (for agents)
.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json
```

## Remote Access

Real remote-access material belongs only in `.my-omo/remote-access/`. Sanitized examples belong in `.agent-docs/templates/remote-access.example.jsonc`. See `.agent-docs/agent-remote-access.md`.
