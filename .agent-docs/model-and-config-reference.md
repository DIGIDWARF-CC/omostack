# Model and Config Reference

## OpenCode Config Locations

Typical user config:
- Windows: `%APPDATA%\opencode\opencode.json` or `.jsonc`
- Linux/macOS: `~/.config/opencode/opencode.json` or `.jsonc`

Project-local config may exist in the opened project, but this repository should not carry real provider secrets.

## Oh My Openagent Config Locations

Current names:
- `.opencode/oh-my-openagent.json`
- `.opencode/oh-my-openagent.jsonc`
- `%APPDATA%\opencode\oh-my-openagent.json`
- `%APPDATA%\opencode\oh-my-openagent.jsonc`

Legacy names:
- `oh-my-opencode.json`
- `oh-my-opencode.jsonc`

If legacy and current files exist in the same config directory, treat this as an unhealthy config collision. Prefer current `oh-my-openagent` naming after backup.

## Plugin Naming

Prefer:

```json
"plugin": ["oh-my-openagent"]
```

Legacy `oh-my-opencode` entries should be migrated only after config backup.

## Model Resolution

Keep model overrides explicit and documented. If an agent behaves badly after model changes:
1. Run `bunx oh-my-openagent doctor`.
2. Run `bunx oh-my-opencode doctor --verbose`.
3. Check provider auth.
4. Check config collision.
5. Revert to the previous backed-up config if needed.
