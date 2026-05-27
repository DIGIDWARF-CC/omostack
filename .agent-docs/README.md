# .agent-docs - Omostack Home Documentation

This directory is the public, tracked knowledge base for the omostack home. Future agents read it to bootstrap, diagnose, repair, and safely maintain OpenCode and oh-my-openagent on this machine.

This is not application documentation. It is an operations base for the local agent environment.

## Start Here

| Need | Open |
|------|------|
| New agent orientation | `self-bootstrap-checklist.md` |
| Main maintenance runbook | `setup-directives.md` |
| Remote-access policy | `agent-remote-access.md` |
| OpenCode / oh-my-openagent failures | `troubleshooting.md` |
| Provider authentication | `provider-auth.md` |
| Models and config precedence | `model-and-config-reference.md` |
| Scripted checks | `scripts/` |
| Sanitized examples | `templates/` |

## Folder Roles

| Role | Path | Tracked? | Description |
|------|------|----------|-------------|
| Public docs | `.agent-docs/` | YES | Instructions, runbooks, templates, scripts |
| Private state | `.my-omo/` | NO | Real keys, backups, downloads, temp files, private install state |
| OpenCode runtime | `.omo/` | NO | Plans, evidence, continuation JSON, local execution artifacts |

Gitignore policy:
- `.my-omo/` is ignored completely.
- `.omo/` is ignored completely.
- `.agent-docs/templates/`, `.agent-docs/scripts/`, and `.agent-docs/runbooks/` must remain trackable.

## Files

| File | Purpose |
|------|---------|
| `agent-instructions.md` | Behavior rules for agents operating in this omostack home |
| `setup-directives.md` | Main runbook for bootstrap, diagnostics, backup, rollback, cleanup, and repair |
| `agent-remote-access.md` | Security model and canonical private remote-access folder |
| `provider-auth.md` | Provider authentication checks and missing/unhealthy classifications |
| `troubleshooting.md` | Common OpenCode / oh-my-openagent failure modes and repair paths |
| `model-and-config-reference.md` | Config locations, precedence, naming, and model-resolution notes |
| `self-bootstrap-checklist.md` | First-pass checklist for future agents |
| `agent-worklog.md` | Human-maintained activity log |

## Tracked Artifacts

| Path | Description |
|------|-------------|
| `templates/` | Sanitized examples only; real values live under ignored private state |
| `scripts/` | PowerShell 5.1 scripts with dry-run behavior for risky operations |

## Operating Rules

1. Read `self-bootstrap-checklist.md` before changing anything.
2. Use scripts in `-WhatIf` mode first when the script supports it.
3. Back up before touching global OpenCode config, caches, auth data, or existing private state.
4. Do not track placeholders under `.my-omo/`; place sanitized templates under `templates/`.
5. Run `scripts/verify-scaffold.ps1 -Check All` after scaffold changes.
