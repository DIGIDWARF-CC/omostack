# Troubleshooting Reference

This file summarizes common OpenCode / Oh My Openagent failure modes. Prefer the scripts in `scripts/` for local checks and use upstream docs for deeper investigation.

## OpenCode

| Symptom | Likely State | First Check | Repair Path |
|---------|--------------|-------------|-------------|
| `opencode` is not found | missing | `health-check.ps1 -WhatIf` | Repair PATH or install OpenCode |
| `ProviderInitError` | unhealthy | `opencode --print-logs` | Run cache repair dry-run, then repair with approval |
| `ProviderModelNotFoundError` | unhealthy | `config-audit.ps1 -WhatIf` | Verify provider id, model id, and auth |
| Desktop connection failure | unhealthy | Check OpenCode config for custom server settings | Remove or fix server override after backup |
| Auth provider missing | missing auth | `opencode auth list` | Login through OpenCode provider flow |

## Oh My Openagent

| Symptom | Likely State | First Check | Repair Path |
|---------|--------------|-------------|-------------|
| `bunx oh-my-openagent doctor` fails to launch | missing | `health-check.ps1 -WhatIf` | Install or repair Bun/Node/package access |
| Legacy package warning | unhealthy config | `config-audit.ps1 -WhatIf` | Prefer `oh-my-openagent`; remove legacy collision after backup |
| Both `oh-my-opencode` and `oh-my-openagent` config files exist | unhealthy config | `config-audit.ps1 -WhatIf` | Choose current name and archive legacy file |
| Provider-specific agent cannot start | unhealthy auth/model | `provider-auth.md` checks | Fix provider auth or model override |
| Runtime diagnostics needed | unknown | `/tmp/oh-my-opencode.log` when available | Preserve logs before cleanup |

## Escalation

Ask Oracle/review agents when:
- a repair would rewrite global config;
- auth and doctor output disagree;
- cache repair does not change the symptom;
- migration finds private filename conflicts;
- repeated attempts fail.

Source links:
- OpenCode docs: https://opencode.ai/docs
- OpenCode troubleshooting: https://dev.opencode.ai/docs/troubleshooting/
- Oh My Openagent: https://github.com/code-yeongyu/oh-my-openagent
