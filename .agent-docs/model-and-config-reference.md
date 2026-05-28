# Model and Config Reference (WSL/Linux)

## OpenCode Config Locations

**Primary (XDG-compliant):**
- `~/.config/opencode/opencode.json` or `.jsonc` ($XDG_CONFIG_HOME/opencode/)
- `~/.cache/opencode/` — provider cache ($XDG_CACHE_HOME/opencode/)

Legacy Windows paths (`%APPDATA%\opencode\`) are not used on WSL/Linux.

Project-local config may exist in the opened project, but this repository should not carry real provider secrets.

## oh-my-openagent Config Locations

Current names (in order of precedence):
1. `~/.config/opencode/oh-my-openagent.json` or `.jsonc`
2. Project-local: `./.opencode/oh-my-openagent.json` or `.jsonc`

Legacy names:
- `oh-my-opencode.json` / `.jsonc` — migrate to current name after backup

If legacy and current files exist in the same config directory, treat this as an **unhealthy config collision**. Prefer current `oh-my-openagent` naming.

## Plugin Naming

OpenCode config (`opencode.jsonc`) must include:
```json
{
  "plugin": ["oh-my-openagent"]
}
```

TUI config (`~/.config/opencode/tui.json`) must include:
```json
{
  "plugin": ["oh-my-openagent/tui"]
}
```

Legacy `oh-my-opencode` entries should be migrated only after config backup.

## Global Installation (CRITICAL)

**oh-my-openagent MUST be globally installed for full functionality:**

```bash
npm install -g oh-my-openagent
npm install -g @code-yeongyu/comment-checker
```

Verify:
```bash
which oh-my-openagent   # should return /usr/bin/oh-my-openagent or similar
oh-my-openagent doctor  # all checks should pass
```

**Why global?** The OpenCode server, TUI installer, and systemd integration all invoke the `oh-my-openagent` binary directly. Using `npx oh-my-openagent` works for one-off commands but breaks when other tools call it without npx.

## Model Resolution

Keep model overrides explicit and documented. If an agent behaves badly after model changes:
1. Run `oh-my-openagent doctor`.
2. Check provider auth: `opencode auth list`.
3. Check config collision (legacy vs current names).
4. Verify the model ID matches what the provider actually reports (check `/v1/models` endpoint for custom providers).
5. Revert to the previous backed-up config if needed.

## Model Resolution for Custom Providers (e.g., LM Studio)

Custom providers use OpenAI-compatible API format:
```jsonc
{
  "provider": {
    "lmstudio": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LM Studio",
      "options": {
        "baseURL": "http://<host>:1235/v1",
        "apiKey": "lm-studio"
      },
      "models": {
        "<model-id>": {
          "name": "Display Name",
          "family": "qwen",
          "limit": { "context": 131072, "output": 32768 }
        }
      }
    }
  },
  "model": "lmstudio/<model-id>"
}
```

The `model` field at the top level must match `<provider>/<model-id>` format. Verify with: `curl http://<host>:1235/v1/models`
