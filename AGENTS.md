# AGENTS.md - OhMyOpenCode Omostack Home

## Purpose

This repository is the omostack home folder. It is used to configure, reconfigure, diagnose, repair, back up, roll back, and self-bootstrap OpenCode and oh-my-openagent on this machine.

This is not an application or software-development project. Agents should treat it as an operations base for maintaining the local agent environment.

---

## Environment

| Setting | Value |
|---------|-------|
| Timezone | Europe/Moscow |
| Locale | en-US |
| OS | win32 (PowerShell 5.1) |

Adjust these values only when cloning this omostack home to another machine.

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
| `.agent-docs/README.md` | Entry point and document index |
| `.agent-docs/self-bootstrap-checklist.md` | First file a future agent should open |
| `.agent-docs/setup-directives.md` | Primary operations runbook |
| `.agent-docs/scripts/` | PowerShell 5.1 maintenance and verification scripts |
| `.agent-docs/templates/` | Sanitized OpenCode / oh-my-openagent examples |
| `.my-omo/remote-access/` | Canonical ignored folder for real remote-access keys and local pseudoconfigs |

---

## Quick Commands

```powershell
# Verify the scaffold itself
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/verify-scaffold.ps1 -Check All

# Safe health-check dry run
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/health-check.ps1 -WhatIf

# Read the main runbook
Get-Content .agent-docs/setup-directives.md
```

## Remote Access

Real remote-access material belongs only in `.my-omo/remote-access/`. Sanitized examples belong in `.agent-docs/templates/remote-access.example.jsonc`. See `.agent-docs/agent-remote-access.md`.
