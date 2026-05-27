# Self-Bootstrap Checklist

Use this file first when an agent opens this omostack home.

## 1. Confirm Scope

- This is `S:\FastNeuros\omo`, an omostack home.
- This is not an application development repo.
- Public operational knowledge is tracked under `.agent-docs/`.
- Private runtime state is ignored under `.my-omo/`.
- OpenCode runtime state is ignored under `.omo/`.

## 2. Verify Scaffold

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/verify-scaffold.ps1 -Check All
```

Fix scaffold failures before attempting runtime repair.

## 3. Inspect Runtime Health

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/health-check.ps1 -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/config-audit.ps1 -WhatIf
```

Classify each issue as `missing`, `present`, or `unhealthy`.

## 4. Choose Runbook

| Situation | Next file |
|-----------|-----------|
| Broken OpenCode | `troubleshooting.md` |
| Broken Oh My Openagent | `troubleshooting.md` |
| Provider/auth issue | `provider-auth.md` |
| Config/model issue | `model-and-config-reference.md` |
| Backup/rollback/cache repair | `setup-directives.md` |

## 5. Before Risky Actions

- Run dry-run mode first.
- Back up private/global state.
- Ask the user before reading secrets, deleting caches, or migrating real private files.
- Record what changed and rerun verification.
