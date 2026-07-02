# Setup Directives - Omostack Operations Runbook (WSL/Linux)

This is the primary runbook for maintaining the OpenCode / optional oh-my-openagent omostack home on **WSL/Linux**. Human bootstrap starts on Windows with `bootstrap-for-human/omo_host_bootstrap.cmd` (full) or `bootstrap-for-human-light/omo_host_bootstrap.cmd` (light); this runbook covers shared stage-2 operations.

## 1. Status Detection

Base install compatibility marker:
- `.my-omo/omostack-base-install-done` means the base omostack was installed at least once.
- The marker may be 0 bytes for backward compatibility.
- Detailed private install state, when available, belongs in ignored `.my-omo/install-state.json`.
- `/root/.local/state/omo-bootstrap/install-profile` contains `light` or `full` for installer-managed global config.
- A missing profile marker means the active OpenCode config is not installer-managed and must be preserved.

Tool health classification:
- `missing`: command or expected file is absent.
- `present`: command or file exists and basic invocation succeeds.
- `unhealthy`: command or file exists but reports errors, conflicting config, failed auth, or broken cache.

## 2. First Pass for Any Agent

For a fresh machine, confirm the human chose one bootstrap:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
bootstrap-for-human-light\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

Then inside WSL:

```bash
.agent-docs/scripts/OOBE-setup.sh --auto
.agent-docs/scripts/check-scaffold.sh --all
.agent-docs/scripts/check-health.sh --dry-run
.agent-docs/scripts/check-config.sh --dry-run
```

If scaffold verification fails, fix tracked docs/scripts/templates first. If health checks report missing or unhealthy runtime tools, diagnose with the relevant section below before changing global config.

## 3. Health Check

Use `check-health.sh` for a non-destructive inventory of:
- OpenCode command availability and version.
- installed profile and marker.
- oh-my-openagent doctor command availability for full only.
- Node.js and Bun availability.
- OpenCode auth/config/log/cache path presence (XDG paths).
- Runtime marker compatibility.

Run:

```bash
.agent-docs/scripts/check-health.sh --dry-run
```

Do not treat `missing` as the same as `unhealthy`. Missing tools need installation or PATH repair; unhealthy tools need config/auth/cache diagnosis.

## 4. Config Audit

Use `check-config.sh` to inspect:
- profile/plugin consistency.
- `$XDG_CONFIG_HOME/opencode/opencode.json` and `.jsonc`.
- `$XDG_CONFIG_HOME/opencode/oh-my-openagent.json` and `.jsonc`.
- legacy `oh-my-opencode` config collision.
- plugin naming in OpenCode config.

Run:

```bash
.agent-docs/scripts/check-config.sh --dry-run
```

If both legacy and current oh-my-openagent config names exist in the same location, prefer the current `oh-my-openagent` name and document the migration before changing files.

## 5. Provider Auth Check

Use OpenCode first:

```bash
opencode auth list
opencode --print-logs
```

For the full profile, use oh-my-openagent diagnostics:

```bash
oh-my-openagent doctor
```

See `provider-auth.md` for provider-specific missing/unhealthy interpretation.

## 6. Global Installation (WSL) — CRITICAL

**Full profile only:** oh-my-openagent must be globally installed via npm:

```bash
npm install -g oh-my-openagent@4.11.1
npm install -g @code-yeongyu/comment-checker
```

Verify:
```bash
which oh-my-openagent   # should return /usr/bin/oh-my-openagent or similar path
oh-my-openagent doctor  # should pass without missing binary errors
```

**Why global?** The `doctor` command, TUI installer, and systemd integration all require the binary to be in PATH. Using `npx oh-my-openagent` works for one-off commands but breaks when other tools (like OpenCode itself) try to invoke it.

If `bunx` is not available globally, the direct `oh-my-openagent` binary still works — global installation ensures both paths are covered.

The light profile must not install OmO, comment-checker, OmO config, `opencode-agent-stack.md`, or the OmO TUI plugin.

## 7. Backup and Rollback

Before cache repair, config rewrite, private-folder migration, auth cleanup, or upgrade:

```bash
.agent-docs/scripts/backup-omostack.sh --destination .my-omo/backups/manual-$(date +%Y%m%d-%H%M%S) --dry-run
```

Then rerun without `--dry-run` only when the user approves the target. Rollback means restoring the backed-up files or directories, then rerunning health and config audits.

## 8. Cache Repair

Use cache repair only for provider package corruption, `ProviderInitError`, stale provider packages, or known cache-related startup failures.

```bash
.agent-docs/scripts/repair-cache.sh --dry-run
```

Actual cache deletion requires `--ConfirmRepair`. Back up first if logs or cache contents are needed for diagnosis.

## 9. Temp Cleanup

Only clean ignored temp/runtime locations:

```bash
.agent-docs/scripts/cleanup-temp.sh --dry-run --OlderThanDays 7
```

This must not touch `.my-omo/remote-access/`, `.my-omo/backups/`, auth files, or global configs.

## 10. Remote-Access Initialization

Canonical private folder: `.my-omo/remote-access/`.

Procedure:
1. Create `.my-omo/remote-access/` when remote credentials or local endpoint pseudoconfigs are needed.
2. Keep real keys, tokens, and local endpoints only in that ignored folder.
3. Keep sanitized examples in `.agent-docs/templates/remote-access.example.jsonc`.
4. Verify ignored status before adding real material.

Use:

```bash
git check-ignore -v .my-omo/remote-access/example.local.jsonc
.agent-docs/scripts/check-scaffold.sh --remote-access
```

## 11. Upgrade Flow

1. Run health and config audits (`check-health.sh`, `check-config.sh`).
2. Back up global OpenCode config, auth metadata, and `.my-omo`.
3. To promote a managed light install, run the full Windows bootstrap over the same Ubuntu/target/port.
4. Never run light as a downgrade over full; the installer refuses it.
5. Check upstream release notes when changing OpenCode or oh-my-openagent versions.
6. Rerun `check-health.sh --dry-run`, `check-config.sh --dry-run`, and the relevant full-profile doctor commands.

The host installer force-synchronizes the tracked checkout to the remote default branch on every install/repair run. Repository-managed instructions are delivery-owned; keep machine-private state only in ignored `.my-omo` and runtime state in `.omo`.

## 12. Destructive Uninstall

`bootstrap-for-human/omo_cleanup.cmd` and its identical light-package copy remove all WSL distributions, WSL components, OmOStack host state, and the checkout. This is intentionally broader than a profile rollback.

The operator must back up important Linux files/services and enter `I AGREE TO DELETE MY WSL COMPLETELY` exactly. Never bypass this confirmation.

## 13. Escalation

Consult Oracle/review agents when:
- a repair would delete or rewrite global config;
- cache repair does not fix provider startup;
- provider auth status conflicts with doctor output;
- private state contains unexpected files or naming conflicts;
- three attempts fail with the same symptom.
