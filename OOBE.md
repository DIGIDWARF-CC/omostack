# OOBE Setup - Windows Host to Ubuntu WSL to OpenCode

## Purpose

OOBE has two self-contained delivery profiles:

- `bootstrap-for-human-light`: standard OpenCode with Build/Plan, built-in General/Explore/Scout, LSP, and Playwright.
- `bootstrap-for-human`: the same base plus Oh My OpenAgent agents, config, TUI plugin, and instruction file.

Each profile contains the same two components:

1. Windows host bootstrap: `omo_host_bootstrap.cmd`.
2. Ubuntu WSL stage: `omo_bootstrap.sh`.

The Windows component owns Windows-only work: WSL feature setup, generic Ubuntu install/default selection, Ubuntu Insights registry opt-out, `.wslconfig`, WSL shutdown, and loopback-only `netsh portproxy`. The Ubuntu component is root-only and owns only Ubuntu/OpenCode/systemd work.

No PowerShell bootstrap path is active.

## Human Entry Points

Run one package from an elevated Windows Command Prompt.

Full OmOStack:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

Light OpenCode:

```cmd
bootstrap-for-human-light\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
```

Useful non-mutating commands:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode status
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /dry-run
```

Useful repair command:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode repair /target C:\AI\omostack /port 4096
```

The selected folder supplies the default profile. `/profile light|full` is accepted for diagnostics and controlled packaging, but users should normally select the matching folder.

## Profile Transitions

The Ubuntu stage records an installer-managed profile in `/root/.local/state/omo-bootstrap/install-profile`.

- Fresh light and fresh full installs are supported.
- Running full over a managed light install backs up the active light config, replaces it with the canonical full template, installs OmO files, records `full`, and restarts the same service.
- Running light over full is refused before profile, config, or service changes.
- Existing OpenCode config without the installer marker is preserved and is not claimed as installer-managed.

## What The Host Bootstrapper Does

1. Requires administrator rights for real `install` and `repair`; `/dry-run` and `status` do not mutate the host.
2. Uses only `cmd.exe`, Windows Script Host (`cscript.exe`/`wscript.exe`), `dism.exe`, `reg.exe`, `wsl.exe`, `netsh.exe`, and `curl.exe`; it does not invoke PowerShell.
3. Enables WSL optional features and sets WSL2 as the default version.
4. Installs or reuses generic `Ubuntu`, then sets it as the default WSL distro.
5. Sets Ubuntu Insights registry default to opt-out.
6. Backs up and minimally overwrites `%USERPROFILE%\.wslconfig`:
   - Windows 11 22H2+: `dnsTunneling=true`, `autoProxy=true`, `networkingMode=mirrored`, `firewall=true`.
   - Windows 10 and older builds: `localhostForwarding=true`.
7. Runs the Ubuntu stage with the selected profile through `wsl.exe -d Ubuntu -u root -- bash ...`.
8. Reads Ubuntu machine-readable status JSON, then configures `127.0.0.1:4096` portproxy to the reported WSL IP.
9. Registers a hidden per-user Scheduled Task that keeps Ubuntu alive, refreshes the loopback portproxy after WSL IP changes, and starts `opencode-serve.service`.

The host bootstrapper does not create a broad inbound firewall rule.

On fresh Windows 10 hosts, enabling WSL optional features can require a reboot before
the `Ubuntu` distro becomes available. In that case the host bootstrapper stops
after the install attempt with a rerun/reboot instruction instead of continuing
into the Ubuntu stage or creating a bogus portproxy.

## What The Ubuntu Stage Does

1. Refuses to run outside Ubuntu WSL or when `/etc/wsl.conf` is missing.
2. Keeps the install root-only: `/etc/wsl.conf` sets `default=root`; OpenCode config/state live under `/root`.
3. Installs Ubuntu base packages, clones `https://github.com/DIGIDWARF-CC/omostack.git` when needed, and installs OpenCode through the official installer.
4. Creates `/usr/local/bin/opencode` as a managed symlink.
5. Installs the selected managed config without overwriting unmarked user config.
6. Starts `opencode serve --hostname 0.0.0.0 --port 4096` through systemd or a one-shot fallback.
7. Writes `/root/.local/state/omo-bootstrap/host-status.json` with requested/installed profile, port, WSL IP, listener status, service mode, OpenCode version, and interop availability.

## Agent Stage-2

After the human bootstrap succeeds, an agent inside WSL can run:

```bash
cd /mnt/c/AI/omostack
.agent-docs/scripts/OOBE-setup.sh --auto
.agent-docs/scripts/check-scaffold.sh --all
```

`OOBE-setup.sh` is not the human installer. It detects the installed profile, checks only tools required by that profile, creates missing managed files from matching templates, writes install state only during real runs, and sets up systemd only when it already has root rights.

## Release Packages

Build both folders and ZIP files with:

```bash
.agent-docs/scripts/build-bootstrap-packages.sh
```

The static scaffold check verifies Bash/JScript/JSON syntax, CRLF/LF line endings, that full/light script pairs differ only by their default profile, and that both ZIP payloads exactly match current scripts. It does not execute OOBE.

## Diagnostics

```bash
.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json
python3 -m json.tool .my-omo/diagnostic.json
```

The diagnostic file is valid JSON and redacts obvious token/secret fields from safe config snippets.
