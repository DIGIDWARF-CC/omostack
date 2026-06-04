# OOBE Setup - Ubuntu WSL to OmO

## Purpose

OmO OOBE now starts inside a generic Ubuntu WSL distro. The human prepares Ubuntu manually, then downloads and runs one root-only Bash bootstrapper. The script configures Ubuntu, installs OpenCode, and uses WSL interop to adjust the host Windows WSL networking needed for `opencode serve`.

There is no active PowerShell bootstrap path.

## Human Entry Point

On Windows, install and start generic Ubuntu under WSL first. The distro must be runnable, must have `/etc/wsl.conf`, and must allow Windows interop. Then run inside Ubuntu:

```bash
wget -O /tmp/omo_bootstrap.sh https://raw.githubusercontent.com/DIGIDWARF-CC/omostack/main/bootstrap-for-human/omo_bootstrap.sh
sudo bash /tmp/omo_bootstrap.sh --target /mnt/s/FastNeuros/omo
```

Useful local options:

```bash
sudo bash bootstrap-for-human/omo_bootstrap.sh --help
sudo bash bootstrap-for-human/omo_bootstrap.sh --dry-run --yes --target /mnt/s/FastNeuros/omo
sudo bash bootstrap-for-human/omo_bootstrap.sh --target /mnt/c/AI/omostack --port 4096
```

## What The Bootstrapper Does

1. Refuses to run outside Ubuntu WSL or when `/etc/wsl.conf` is missing.
2. Keeps the install root-only: `/etc/wsl.conf` sets `default=root`, OpenCode config/state live under `/root`.
3. Ensures WSL systemd, `/mnt` automount, and Windows interop are enabled; if interop needs a restart, it asks the human to run `wsl.exe --shutdown`.
4. Detects the Windows build through `cmd.exe /c ver`.
5. Updates only OmO-owned Windows `.wslconfig` networking keys through interop:
   - Windows 11 22H2+ uses mirrored networking keys: `dnsTunneling`, `autoProxy`, `networkingMode=mirrored`, `firewall`.
   - Older Windows builds use best-effort localhost forwarding only.
6. Installs Ubuntu base packages, clones `https://github.com/DIGIDWARF-CC/omostack.git` when the target path is empty, and installs OpenCode through the official installer.
7. Creates `/usr/local/bin/opencode` as a managed symlink and starts `opencode serve` as root through systemd or a one-shot fallback.
8. Exposes the web UI to Windows at `http://127.0.0.1:4096/`, using loopback-only `netsh interface portproxy` when Windows loopback does not work directly.

The bootstrapper backs up changed WSL config files under `/root/.local/state/omo-bootstrap/backups/` and writes logs/state under `/root/.local/state/omo-bootstrap/`.

## Agent Stage-2

After the human bootstrap succeeds, an agent inside WSL can run:

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
