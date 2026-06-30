# Self-Bootstrap Checklist (WSL/Linux)

Use this file first when an agent opens this omostack home.

## 1. Confirm Scope

- This folder is an omostack home folder.
- This is not an application development repo.
- Public operational knowledge is tracked under `.agent-docs/`.
- Private runtime state is ignored under `.my-omo/`.
- OpenCode runtime state is ignored under `.omo/`.
- **Target environment: WSL/Linux (Bash scripts, XDG paths).**

## 2. New Install? Confirm Host Bootstrap First

If this is a fresh clone, choose a profile:

- Light: standard OpenCode Build/Plan plus built-in General/Explore/Scout.
- Full: OpenCode plus Oh My OpenAgent orchestration.

Run the selected Windows host bootstrap from an elevated Command Prompt:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
bootstrap-for-human-light\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

Run only one command. A managed light install can later be upgraded by running the full command; the light installer never removes a full profile.

After that, agents may run profile-aware stage-2:

```bash
.agent-docs/scripts/OOBE-setup.sh --auto
```

Proceed to Step 3 after stage-2 completes.

## 3. Verify Scaffold

```bash
.agent-docs/scripts/check-scaffold.sh --all
```

Fix scaffold failures before attempting runtime repair.

## 4. Inspect Runtime Health

```bash
.agent-docs/scripts/check-health.sh --dry-run
.agent-docs/scripts/check-config.sh --dry-run
```

Classify each issue as `missing`, `present`, or `unhealthy`.

## 5. Choose Runbook

| Situation | Next file |
|-----------|-----------|
| Broken OpenCode | `troubleshooting.md` |
| Broken oh-my-openagent | `troubleshooting.md` |
| Provider/auth issue | `provider-auth.md` |
| Config/model issue | `model-and-config-reference.md` |
| Backup/rollback/cache repair | `setup-directives.md` |

## 6. Before Risky Actions

- Run dry-run mode first (`--dry-run`).
- Back up private/global state with `.agent-docs/scripts/backup-omostack.sh`.
- Ask the user before reading secrets, deleting caches, or migrating real private files.
- Record what changed and rerun verification.

## 7. When Agent Encounters Unknown Problem

1. Run `.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json` to capture full state dump.
2. Read the diagnostic JSON — it contains OS, PATH, tool versions, sanitized config metadata, systemd status, ports.
3. Cross-reference with `troubleshooting.md` for known fixes.
4. Apply minimal fix and verify with health check scripts.

This workflow enables even a weak agent to diagnose and resolve issues autonomously.
