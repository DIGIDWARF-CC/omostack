# Setup Directives - Omostack Operations Runbook

This is the primary runbook for maintaining the OpenCode / oh-my-openagent omostack home.

## 1. Status Detection

Base install compatibility marker:
- `.my-omo/omostack-base-install-done` means the base omostack was installed at least once.
- The marker may be 0 bytes for backward compatibility.
- Detailed private install state, when available, belongs in ignored `.my-omo/install-state.json`.
- A sanitized example lives at `.agent-docs/templates/install-state.example.json`.

Tool health classification:
- `missing`: command or expected file is absent.
- `present`: command or file exists and basic invocation succeeds.
- `unhealthy`: command or file exists but reports errors, conflicting config, failed auth, or broken cache.

## 2. First Pass for Any Agent

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/verify-scaffold.ps1 -Check All
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/health-check.ps1 -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/config-audit.ps1 -WhatIf
```

If scaffold verification fails, fix tracked docs/scripts/templates first. If health checks report missing or unhealthy runtime tools, diagnose with the relevant section below before changing global config.

## 3. Health Check

Use `health-check.ps1` for a non-destructive inventory of:
- OpenCode command availability and version.
- oh-my-openagent doctor command availability.
- Node.js and Bun availability.
- OpenCode auth/config/log/cache path presence.
- Runtime marker compatibility.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/health-check.ps1 -WhatIf
```

Do not treat `missing` as the same as `unhealthy`. Missing tools need installation or PATH repair; unhealthy tools need config/auth/cache diagnosis.

## 4. Config Audit

Use `config-audit.ps1` to inspect:
- `%APPDATA%\opencode\opencode.json` and `.jsonc`.
- `%APPDATA%\opencode\oh-my-openagent.json` and `.jsonc`.
- legacy `oh-my-opencode` config collision.
- plugin naming in OpenCode config.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/config-audit.ps1 -WhatIf
```

If both legacy and current oh-my-openagent config names exist in the same location, prefer the current `oh-my-openagent` name and document the migration before changing files.

## 5. Provider Auth Check

Use OpenCode first:

```powershell
opencode auth list
opencode --print-logs
```

Then use oh-my-openagent diagnostics:

```powershell
bunx oh-my-openagent doctor
bunx oh-my-opencode doctor --verbose
```

See `provider-auth.md` for provider-specific missing/unhealthy interpretation.

## 6. Backup and Rollback

Before cache repair, config rewrite, private-folder migration, auth cleanup, or upgrade:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/backup-omostack.ps1 -Destination .my-omo/backups/manual-YYYYMMDD-HHMMSS -WhatIf
```

Then rerun without `-WhatIf` only when the user approves the target. Rollback means restoring the backed-up files or directories, then rerunning health and config audits.

## 7. Cache Repair

Use cache repair only for provider package corruption, `ProviderInitError`, stale provider packages, or known cache-related startup failures.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/repair-opencode-cache.ps1 -WhatIf
```

Actual cache deletion requires `-ConfirmRepair`. Back up first if logs or cache contents are needed for diagnosis.

## 8. Temp Cleanup

Only clean ignored temp/runtime locations:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/cleanup-temp.ps1 -WhatIf -OlderThanDays 7
```

This must not touch `.my-omo/remote-access/`, `.my-omo/backups/`, auth files, or global configs.

## 9. Remote-Access Initialization

Canonical private folder: `.my-omo/remote-access/`.

Procedure:
1. Create `.my-omo/remote-access/` when remote credentials or local endpoint pseudoconfigs are needed.
2. Keep real keys, tokens, and local endpoints only in that ignored folder.
3. Keep sanitized examples in `.agent-docs/templates/remote-access.example.jsonc`.
4. Verify ignored status before adding real material.

Use:

```powershell
git check-ignore -v .my-omo/remote-access/example.local.jsonc
powershell -NoProfile -ExecutionPolicy Bypass -File .agent-docs/scripts/verify-scaffold.ps1 -Check RemoteAccess
```

## 10. Upgrade Flow

1. Run health and config audits.
2. Back up global OpenCode config, auth metadata, and `.my-omo`.
3. Check upstream release notes when changing OpenCode or oh-my-openagent versions.
4. Upgrade one layer at a time.
5. Rerun `health-check.ps1 -WhatIf`, `config-audit.ps1 -WhatIf`, and the relevant doctor commands.

## 11. Escalation

Consult Oracle/review agents when:
- a repair would delete or rewrite global config;
- cache repair does not fix provider startup;
- provider auth status conflicts with doctor output;
- private state contains unexpected files or naming conflicts;
- three attempts fail with the same symptom.
