# Agent Remote Access

This document defines where remote-access material belongs and how agents should handle it safely.

## Canonical Private Folder

Real keys, tokens, endpoint pseudoconfigs, and machine-local connection details belong only in ignored private state:

```text
.my-omo/remote-access/
```

The folder is intentionally not tracked. Do not add .gitkeep or tracked placeholders under .my-omo/.

Sanitized examples belong in:

```text
.agent-docs/templates/remote-access.example.jsonc
```

## Safe Handling Rules

1. Inventory filenames only unless content inspection is necessary and approved.
2. Back up `.my-omo` before moving or renaming anything.
3. Verify `.my-omo/remote-access/example.local.jsonc` is ignored by git.
4. Record rollback instructions next to any backup.

## Common Files

These filenames are examples only. Real files remain private and ignored.

| Private file | Purpose |
|--------------|---------|
| `.my-omo/remote-access/github-token` | GitHub token for local automation |
| `.my-omo/remote-access/ssh-key` | Private SSH key for Git or remote hosts |
| `.my-omo/remote-access/*.local.jsonc` | Machine-local endpoint pseudoconfigs |

## Verification

```bash
git check-ignore -v .my-omo/remote-access/example.local.jsonc
.agent-docs/scripts/check-scaffold.sh --remote-access
```
