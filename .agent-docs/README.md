# .agent-docs - Omostack Home Documentation

This directory is the public, tracked knowledge base for the omostack home — an operations base for OpenCode and oh-my-openagent on **WSL/Linux**. Human OOBE starts from generic Ubuntu WSL with `bootstrap-for-human/omo_bootstrap.sh`; this folder contains the agent-facing stage-2 docs and scripts.

This is not application documentation. It is an operations base for agent-driven maintenance of the local agent environment.

## Start Here

| Need | Open |
|------|------|
| **New install / OOBE** | `../OOBE.md` and `../bootstrap-for-human/omo_bootstrap.sh` |
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
| Public docs | `.agent-docs/` | YES | Instructions, runbooks, sanitized templates, maintenance scripts |
| Private runtime state | `.my-omo/` | NO | Real keys, backups, downloads, temp files, private install state |
| OpenCode runtime | `.omo/` | NO | Plans, evidence, continuation JSON, local execution artifacts |

Gitignore policy:
- `.my-omo/` is ignored completely.
- `.omo/` is ignored completely.
- `.agent-docs/templates/`, `.agent-docs/scripts/`, and `.agent-docs/recipes/` must remain trackable.

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
| `scripts/` | Bash scripts with dry-run behavior for risky operations |
| `recipes/` | Interactive troubleshooting menus and multi-step fix workflows |

PowerShell scripts are not part of the active OOBE path.

## Operating Rules

1. Read `self-bootstrap-checklist.md` before changing anything.
2. Use scripts in `--dry-run` mode first when the script supports it.
3. Back up before touching global OpenCode config, caches, auth data, or existing private state.
4. Do not track placeholders under `.my-omo/`; place sanitized templates under `templates/`.
5. Run `scripts/check-scaffold.sh --all` after scaffold changes.
