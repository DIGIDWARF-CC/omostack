#!/usr/bin/env bash
# Build the self-contained full and light Windows bootstrap packages.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
full_dir="$repo_root/bootstrap-for-human"
light_dir="$repo_root/bootstrap-for-human-light"

python3 - "$full_dir" "$light_dir" <<'PY'
import sys
import zipfile
from pathlib import Path

full_dir = Path(sys.argv[1])
light_dir = Path(sys.argv[2])
light_dir.mkdir(parents=True, exist_ok=True)

cmd_name = "omo_host_bootstrap.cmd"
shell_name = "omo_bootstrap.sh"

full_cmd = (full_dir / cmd_name).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
full_shell = (full_dir / shell_name).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")

if full_cmd.count('set "PROFILE=full"') != 1:
    raise SystemExit("full CMD must contain exactly one full profile default")
if full_shell.count('DEFAULT_PROFILE="full"') != 1:
    raise SystemExit("full shell stage must contain exactly one full profile default")

light_cmd = full_cmd.replace('set "PROFILE=full"', 'set "PROFILE=light"')
light_shell = full_shell.replace('DEFAULT_PROFILE="full"', 'DEFAULT_PROFILE="light"')

(full_dir / cmd_name).write_bytes(full_cmd.replace("\n", "\r\n").encode("utf-8"))
(light_dir / cmd_name).write_bytes(light_cmd.replace("\n", "\r\n").encode("utf-8"))
(light_dir / shell_name).write_text(light_shell, encoding="utf-8", newline="\n")
(light_dir / shell_name).chmod(0o755)


def write_zip(directory: Path, archive_name: str) -> None:
    archive = directory / archive_name
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name, mode in ((cmd_name, 0o644), (shell_name, 0o755)):
            payload = (directory / name).read_bytes()
            # ZIP's 1980 epoch makes release archives reproducible across checkouts.
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (mode & 0xFFFF) << 16
            info.create_system = 3
            zf.writestr(info, payload)


write_zip(full_dir, "Opencode-wsl-setup.zip")
write_zip(light_dir, "Opencode-wsl-light-setup.zip")
PY

printf 'Built full package: %s\n' "$full_dir/Opencode-wsl-setup.zip"
printf 'Built light package: %s\n' "$light_dir/Opencode-wsl-light-setup.zip"
