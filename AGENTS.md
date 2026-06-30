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

Choose one self-contained package:

- `bootstrap-for-human-light`: standard OpenCode with Build/Plan and built-in subagents.
- `bootstrap-for-human`: full OpenCode + Oh My OpenAgent orchestration.

A human starts the selected Windows host bootstrap from an elevated Command Prompt:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

The light package uses the same command name from its own folder:

```cmd
bootstrap-for-human-light\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

After the host bootstrap has prepared Windows WSL settings, Ubuntu/OpenCode, and Windows loopback access, an agent can continue inside WSL:

```bash
chmod +x .agent-docs/scripts/OOBE-setup.sh
.agent-docs/scripts/OOBE-setup.sh --auto
```

The Windows host bootstrapper is the human-facing installer. `OOBE-setup.sh` is profile-aware stage-2 agent maintenance inside WSL/Linux. A managed light installation can be upgraded in place by running the full package; full-to-light downgrade is intentionally refused. See `OOBE.md`.

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
| `bootstrap-for-human/omo_host_bootstrap.cmd` | Windows host bootstrapper for humans |
| `bootstrap-for-human/omo_bootstrap.sh` | Root-only Ubuntu WSL stage called by the host bootstrapper |
| `bootstrap-for-human-light/` | Self-contained light package with the same entry points |
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
