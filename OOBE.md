# OOBE Setup - Windows Host to Ubuntu WSL to OmO

## Purpose

OmO OOBE is split into two components:

1. Windows host bootstrap: `bootstrap-for-human/omo_host_bootstrap.cmd`.
2. Ubuntu WSL stage: `bootstrap-for-human/omo_bootstrap.sh`.

The Windows component owns Windows-only work: WSL feature setup, generic Ubuntu install/default selection, Ubuntu Insights registry opt-out, `.wslconfig`, WSL shutdown, and loopback-only `netsh portproxy`. The Ubuntu component is root-only and owns only Ubuntu/OpenCode/systemd work.

No PowerShell bootstrap path is active.

## Human Entry Point

Run from an elevated Windows Command Prompt:

```cmd
bootstrap-for-human\omo_host_bootstrap.cmd /mode install /target C:\AI\omostack /port 4096
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

## What The Host Bootstrapper Does

1. Requires administrator rights for real `install` and `repair`; `/dry-run` and `status` do not mutate the host.
2. Uses only `cmd.exe`, Windows Script Host (`cscript.exe`/`wscript.exe`), `dism.exe`, `reg.exe`, `wsl.exe`, `netsh.exe`, and `curl.exe`; it does not invoke PowerShell.
3. Enables WSL optional features and sets WSL2 as the default version.
4. Installs or reuses generic `Ubuntu`, then sets it as the default WSL distro.
5. Sets Ubuntu Insights registry default to opt-out.
6. Backs up and minimally overwrites `%USERPROFILE%\.wslconfig`:
   - Windows 11 22H2+: `dnsTunneling=true`, `autoProxy=true`, `networkingMode=mirrored`, `firewall=true`.
   - Windows 10 and older builds: `localhostForwarding=true`.
7. Runs the Ubuntu stage through `wsl.exe -d Ubuntu -u root -- bash ...`.
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
5. Starts `opencode serve --hostname 0.0.0.0 --port 4096` through systemd or a one-shot fallback.
6. Writes `/root/.local/state/omo-bootstrap/host-status.json` with port, WSL IP, listener status, service mode, OpenCode version, and interop availability.

## Agent Stage-2

After the human bootstrap succeeds, an agent inside WSL can run:

```bash
cd /mnt/c/AI/omostack
.agent-docs/scripts/OOBE-setup.sh --auto
.agent-docs/scripts/check-scaffold.sh --all
```

`OOBE-setup.sh` is not the human installer. It is stage-2 maintenance for WSL/Linux agents: it checks tools, creates missing config from sanitized templates, writes install state only during real runs, and sets up systemd only when it already has root rights.

## Diagnostics

```bash
.agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json
python3 -m json.tool .my-omo/diagnostic.json
```

The diagnostic file is valid JSON and redacts obvious token/secret fields from safe config snippets.
