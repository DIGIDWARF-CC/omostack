# Templates

This directory contains sanitized examples for OpenCode / oh-my-openagent setup. They are safe to track.

Rules:
- Use fake tokens, fake hosts, and example domains only.
- Do not copy real `.my-omo/` files here.
- Real remote-access data belongs in ignored `.my-omo/remote-access/`.
- Real private install state belongs in ignored `.my-omo/install-state.json`.

Files:
- `remote-access.example.jsonc`: local endpoint pseudoconfig shape.
- `opencode-global.example.jsonc`: global OpenCode config shape.
- `oh-my-openagent.example.jsonc`: oh-my-openagent config shape.
- `install-state.example.json`: private install-state schema example (includes WSL/global_install fields).

## Scripts Directory

| Script | Purpose |
|--------|---------|
| `OOBE-setup.sh` | Stage-2 WSL/Linux agent setup after the host bootstrap |
| `check-health.sh` | Non-destructive tool availability check (`--dry-run`) |
| `check-config.sh` | Config collision and plugin naming audit (`--dry-run`) |
| `check-scaffold.sh` | Repo structure verification (`--all` or specific checks) |
| `backup-omostack.sh` | Backup private state + global configs |
| `repair-cache.sh` | Clean OpenCode provider cache (`--ConfirmRepair`) |
| `cleanup-temp.sh` | Remove old temp files from ignored dirs |
| `diagnostic.sh` | Sanitized JSON diagnostic for agent troubleshooting |
