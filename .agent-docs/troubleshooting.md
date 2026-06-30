# Troubleshooting Reference (WSL/Linux)

This file summarizes common OpenCode / oh-my-openagent failure modes on WSL/Linux. Prefer the scripts in `scripts/` for local checks and use upstream docs for deeper investigation.

## Quick Fixes

When an agent encounters a problem, run:

```bash
# Full diagnostic JSON -> save to .my-omo/diagnostic.json
.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json
python3 -m json.tool .my-omo/diagnostic.json >/dev/null

# Interactive troubleshooting menu
.agent-docs/recipes/troubleshoot.sh
```

## Git Issues

### `fatal: detected dubious ownership in repository`

WSL mounts Windows drives as root, so git considers the repo "owned by someone else."

**Fix:** Add safe directories globally:
```bash
git config --global --add safe.directory /mnt/s/your-project-path
# For all subdirectories under mount point:
git config --global --add safe.directory "/mnt/s/*"
```

Verify: `git status` should work without errors.

### Git not found in PATH on WSL

WSL may have git installed for Windows but not exposed in the Linux PATH.

**Fix:** Add `/mnt/c/Program Files/Git/cmd` to PATH (Windows git) or install via apt (`apt-get install git`).

| Symptom | Likely State | First Check | Repair Path |
|---------|--------------|-------------|-------------|
| `opencode` is not found | missing | `check-health.sh --dry-run` | Repair PATH or install OpenCode |
| `ProviderInitError` (stale provider cache) | unhealthy | `opencode --print-logs` | Run cache repair dry-run, then repair with approval |
| `ProviderModelNotFoundError` | unhealthy | `check-config.sh --dry-run` | Verify provider id, model id, and auth |
| Desktop connection failure | unhealthy | Check OpenCode config for custom server settings | Remove or fix server override after backup |
| Auth provider missing | missing auth | `opencode auth list` | Login through OpenCode provider flow |

## oh-my-openagent Issues

| Symptom | Likely State | First Check | Repair Path |
|---------|--------------|-------------|-------------|
| Binary not found in PATH | missing | `check-health.sh --dry-run` | Global install: `npm install -g oh-my-openagent@4.11.1` |
| Legacy package warning | unhealthy config | `check-config.sh --dry-run` | Prefer `oh-my-openagent`; remove legacy collision after backup |
| Both `oh-my-opencode` and `oh-my-openagent` config files exist | unhealthy config | `check-config.sh --dry-run` | Choose current name and archive legacy file |
| Provider-specific agent cannot start | unhealthy auth/model | `provider-auth.md` checks | Fix provider auth or model override |
| Runtime diagnostics needed | unknown | `.my-omo/diagnostic.json` when available | Preserve logs before cleanup

**Fix:**
```bash
mkdir -p ~/.config/opencode/
printf '{\n  "plugin": ["oh-my-openagent/tui"]\n}\n' > ~/.config/opencode/tui.json
```

Also verify the active `opencode.json` (or compatible JSONC) has `"plugin": ["oh-my-openagent@4.11.1"]`.

### Config collision (legacy vs current)

Both `oh-my-opencode` and `oh-my-openagent` config files exist in the same directory.

**Fix:** Archive legacy, keep current:
```bash
mv ~/.config/opencode/oh-my-opencode.jsonc ~/.config/opencode/oh-my-opencode.jsonc.bak
# Then verify with check-config.sh
.agent-docs/scripts/check-config.sh --dry-run
```

## systemd Service Issues (Linux)

### Service won't start / fails on boot

**Check:**
```bash
systemctl status opencode-serve.service
journalctl -u opencode-serve.service --no-pager -n 30
```

**Fix — Rebuild service file:**
1. Find opencode binary: `which opencode` or `find ~/.opencode -name opencode`
2. Edit `/etc/systemd/system/opencode-serve.service`:
   ```ini
   ExecStart=/path/to/opencode serve --hostname 0.0.0.0 --port 4096 --log-level INFO
   ```
3. Reload and restart only after the service file is valid: `systemctl daemon-reload && systemctl restart opencode-serve.service`

### Port 4096 already in use

**Find the process:**
```bash
ss -tlnp | grep ':4096'
# or
lsof -i :4096
```

**Kill it:** `kill <PID>` (or `kill -9 <PID>`)

Then restart opencode.

## Provider Auth Issues

### Model resolution fails for custom provider

Custom providers need explicit model configuration in `opencode.json` (or compatible JSONC).

**Check:**
1. Verify the provider endpoint is reachable.
2. Check model ID matches exactly what the provider reports
3. Run `opencode auth list` and `opencode --print-logs`

**Fix:** Update the active OpenCode config with the correct base URL, API key, and model ID. See `provider-auth.md` for details.

## Diagnostic Workflow (for agents)

When stuck on an unknown problem:

1. **Capture state:** `.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json`
2. **Read the JSON** — it has OS, PATH, tool versions, sanitized config metadata, systemd status, listening ports
3. **Match symptom** against this troubleshooting table
4. **Apply minimal fix** from the Repair Path column
5. **Verify:** `.agent-docs/scripts/check-health.sh` and `oh-my-openagent doctor`

This workflow lets even a weak agent diagnose and resolve most issues autonomously.

## Escalation

Ask Oracle/review agents when:
- a repair would rewrite global config;
- auth and doctor output disagree;
- cache repair does not change the symptom;
- migration finds private filename conflicts;
- repeated attempts fail.

## Source Links

- OpenCode docs: https://opencode.ai/docs
- OpenCode troubleshooting: https://dev.opencode.ai/docs/troubleshooting/
- oh-my-openagent: https://github.com/code-yeongyu/oh-my-openagent
