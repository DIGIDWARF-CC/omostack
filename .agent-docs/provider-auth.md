# Provider Auth Guide

Provider auth checks must distinguish `missing` from `unhealthy`.

## Classification

| State | Meaning | Example |
|-------|---------|---------|
| missing | Provider or token is absent | `opencode auth list` does not show a needed provider |
| present | Provider is configured and basic checks pass | Provider appears and doctor reports usable model |
| unhealthy | Provider exists but fails calls, model lookup, or doctor checks | Auth listed but model calls fail |

## Checks

```powershell
opencode auth list
opencode --print-logs
bunx oh-my-openagent doctor
bunx oh-my-opencode doctor --verbose
```

## Provider Notes

| Provider | Missing Signal | Unhealthy Signal | Next Step |
|----------|----------------|------------------|-----------|
| OpenAI | No OpenAI auth in OpenCode | model not found or API call error | Re-auth or fix model id |
| Anthropic / Claude | No Anthropic auth | Claude model resolution fails | Re-auth and rerun doctor |
| Gemini | No Google/Gemini auth | provider init or model lookup error | Fix provider config and auth |
| Copilot | No Copilot auth | token present but rejected | Refresh auth through OpenCode |
| Custom provider | Provider absent from config | provider id/model id mismatch | Audit `opencode.json` and schema |

Do not paste tokens into tracked files. If a token must be stored locally, place it under ignored `.my-omo/remote-access/` or the provider's official auth store.
