# OpenCode Agent Stack - OmO Delivery Profile

Think in English. Answer in the user's language by default. If the user writes in Russian, answer in Russian and address them informally, as a colleague. Preserve original spelling for code, commands, paths, package names, APIs, library names, and error messages.

This file documents only the capabilities enabled by `/root/.config/opencode/opencode.json`. Do not assume extra machine-local tooling, local models, or project-specific agents are available unless the active project config says so.

## General Working Style

- First understand the task goal and the local repository constraints from files that are already available.
- Keep the default tool surface small. Use core file/code tools first, then call specialized agents or MCP tools only when their domain is actually needed.
- Do not make broad refactors without a clear reason.
- After code changes, run the closest available check: typecheck, lint, tests, build, or a targeted smoke check.
- If a check cannot run because of missing dependencies, environment, credentials, or hardware access, state the blocker clearly.
- Delegate narrowly: one or two focused specialists are preferred over a broad orchestra unless the user explicitly asks for parallel agent work.

## Configured Models

- Default model: `opencode/deepseek-v4-flash-free`.
- Small model: `opencode/north-mini-code-free`.
- OmO fallback is hosted-only: `opencode/north-mini-code-free`, then `opencode/mimo-v2.5-free` where configured.
- Do not assume local model providers exist on target machines.

## Configured LSPs

- TypeScript/JavaScript: `typescript-language-server --stdio` through `npx` for `.ts`, `.tsx`, `.js`, `.jsx`, `.mts`, `.cts`.
- HTML: `vscode-html-language-server --stdio` from `vscode-langservers-extracted` through `npx` for `.html`, `.htm`, `.htmldjango`, `.handlebars`.
- CSS: `vscode-css-language-server --stdio` from `vscode-langservers-extracted` through `npx` for `.css`, `.scss`, `.less`.
- JSON/JSONC: `vscode-json-language-server --stdio` from `vscode-langservers-extracted` through `npx` for `.json`, `.jsonc`.
- Python: `pyright-langserver --stdio` from `pyright` through `npx` for `.py`, `.pyi`.
- PHP: `npx -y intelephense --stdio` for `.php`, `.phtml`, `.module`, `.inc`.

## Configured MCP

- `playwright`: local Playwright MCP through `npx -y @playwright/mcp@0.0.75` in headless Chrome, isolated, viewport `800x600`.
- Use Playwright MCP for browser automation and visual validation when UI behavior or screenshots matter.
- Do not assume other MCP servers exist unless `/config` shows them for the current project.

## Configured OpenCode Agents

- Built-in agents intentionally kept available in `opencode.json`: `build`, `plan`, `general`.
- With OmO 4.11.1 active, `plan` and `general` remain primary, while the literal built-in `build` is kept as a subagent by the plugin.
- OmO's primary builder replacement is `OpenCode-Builder`.
- `title` is disabled to avoid wasting model calls on session title generation.
- Custom subagents from `opencode.json`: `wsl-interop`, `powershell-agent`.

## OmO Agent Roles

- `sisyphus`: heavy agentic work and persistence loops.
- `hephaestus`: deep implementation and engineering assembly.
- `prometheus`: planning, decomposition, and pre-implementation analysis.
- `atlas`: approved plan execution and coordination.
- `oracle`: validation, review, risk analysis, contradiction checks.
- `librarian`: documentation, references, and research tasks.
- `explore`: read-only codebase exploration.
- `multimodal-looker`: screenshots, UI, and image inspection.
- `metis`: architecture and alternative approaches.
- `momus`: critique, weak-spot finding, false-assumption checks.
- `sisyphus-junior`: small isolated tasks.

## Windows and WSL Interop

- Windows files are available through `/mnt/c/` and other mounted drives when present.
- Use the `wsl-interop` subagent for WSL/Linux to Windows interop, cross-platform path issues, and safe Windows binary checks.
- Use the `powershell-agent` subagent for PowerShell 5/7 scripting and compatibility concerns.
- Windows PATH is not appended inside WSL; invoke Windows tools by explicit `/mnt/c/...` paths and do not assume optional cross-compilers, Wine, PowerShell 7, or PSScriptAnalyzer are installed.
- Be careful before writing to `/mnt/c/` or `/mnt/d/`: these are external directories relative to the Linux worktree.

## Language Notes

- Node.js projects: inspect `package.json` and lockfiles before choosing npm/yarn/pnpm commands.
- Frontend projects: validate layout, interactivity, accessibility, and the main user workflows when the task changes UI.
- Python projects: prefer targeted `pyright`, `ruff`, tests, or import checks when configured.
- PHP projects: inspect composer scripts and framework conventions before running broad checks.

## Change Report

When finishing work, report:

- What changed.
- Which checks ran.
- Any checks that could not run and why.
- Remaining risks or follow-up items that matter to the user's next action.
