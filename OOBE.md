# OOBE Setup - Windows to WSL to OmO

## Purpose

OmO OOBE starts on Windows. A human runs one PowerShell 5.1-compatible bootstrapper, confirms UAC when Windows needs it, and the script prepares WSL/Ubuntu/OpenCode enough for an agent to finish stage-2 setup inside WSL.

## Human Entry Point

Run from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1
```

Useful non-mutating modes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1 -Mode Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1 -Mode Plan -TargetPath S:\FastNeuros\omo
```

## What The Bootstrapper Does

1. Asks where to install OmO and clones `https://gitlab.kokoc.com/kg/crmbitrix-bitrix-crm/omo.git`.
2. Checks Windows PowerShell, Windows build, Git, WSL availability, and Ubuntu 24.04.
3. Enables WSL features and installs `Ubuntu-24.04` when needed.
4. Makes `Ubuntu-24.04` the default WSL distro.
5. Writes Windows `.wslconfig` and WSL `/etc/wsl.conf` for systemd, interop, `/mnt` automount, and best available VPN-aware networking.
6. Installs WSL base packages and OpenCode silently.
7. Starts `opencode serve` in WSL with the OmO repository as the working project.
8. Exposes the web UI to Windows at `http://127.0.0.1:4096/` through local portproxy/firewall rules.

Windows 11 22H2+ can use WSL mirrored networking, DNS tunneling, and auto proxy. Windows 10 is treated as best-effort: the bootstrapper keeps localhost forwarding and uses portproxy for Windows access to the WSL OpenCode web UI.

## Agent Stage-2

After Windows bootstrap succeeds, an agent inside WSL can run:

```bash
cd /mnt/s/FastNeuros/omo
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
