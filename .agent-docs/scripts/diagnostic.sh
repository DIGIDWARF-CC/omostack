#!/usr/bin/env bash
# Emit sanitized JSON diagnostic state for OmO agents.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
export OMO_REPO_ROOT="$repo_root"

if ! command -v python3 >/dev/null 2>&1; then
    printf '{"generated_at":"","error":"python3 is required for JSON diagnostic output"}\n'
    exit 1
fi

python3 <<'PY'
import json
import os
import platform
import re
import shutil
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path

repo = Path(os.environ["OMO_REPO_ROOT"])
home = Path.home()
xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
opencode_dir = xdg_config / "opencode"
secret_re = re.compile(r"(?i)(api[_-]?key|token|secret|password|authorization|bearer)\s*[:=]\s*[\"']?[^\"',\s}]+")


def run(args, cwd=None, timeout=8):
    try:
        proc = subprocess.run(
            args,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        return {
            "ok": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
        }
    except Exception as exc:
        return {"ok": False, "exit_code": None, "stdout": "", "stderr": str(exc)}


def tool(name):
    path = shutil.which(name)
    result = {"present": bool(path), "path": path}
    if path:
        version = run([name, "--version"])
        result["version"] = (version["stdout"] or version["stderr"]).splitlines()[:3]
    return result


def sanitize(text):
    return secret_re.sub(lambda m: m.group(1) + ": <redacted>", text)


def file_meta(path, include_content=False):
    item = {"path": str(path), "present": path.exists()}
    if not path.exists():
        return item
    stat = path.stat()
    item.update({"size": stat.st_size, "mtime": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat()})
    if include_content and stat.st_size <= 65536:
        item["sanitized_content"] = sanitize(path.read_text(errors="replace"))
    return item


def port_state():
    if shutil.which("ss"):
        return run(["ss", "-tlnp"])
    if shutil.which("netstat"):
        return run(["netstat", "-tlnp"])
    return {"ok": False, "exit_code": None, "stdout": "", "stderr": "ss/netstat not found"}


config_files = [
    opencode_dir / "opencode.jsonc",
    opencode_dir / "opencode.json",
    opencode_dir / "oh-my-openagent.json",
    opencode_dir / "oh-my-openagent.jsonc",
    opencode_dir / "tui.json",
]

data = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "os": {
        "platform": platform.platform(),
        "uname": list(platform.uname()),
        "wsl_distro": os.environ.get("WSL_DISTRO_NAME", ""),
        "hostname": socket.gethostname(),
    },
    "env": {
        "home": str(home),
        "shell": os.environ.get("SHELL", ""),
        "xdg_config_home": str(xdg_config),
        "xdg_cache_home": os.environ.get("XDG_CACHE_HOME", ""),
        "xdg_data_home": os.environ.get("XDG_DATA_HOME", ""),
    },
    "path": os.environ.get("PATH", "").split(os.pathsep),
    "tools": {name: tool(name) for name in ["opencode", "oh-my-openagent", "comment-checker", "node", "npm", "npx", "bun", "bunx", "gh", "git", "systemctl"]},
    "opencode": {
        "config_dir": str(opencode_dir),
        "config": [file_meta(path, include_content=True) for path in config_files],
    },
    "systemd": {
        "opencode_serve_status": run(["systemctl", "status", "opencode-serve.service"]) if shutil.which("systemctl") else {"ok": False, "stderr": "systemctl not found"},
        "opencode_serve_active": run(["systemctl", "is-active", "opencode-serve.service"]) if shutil.which("systemctl") else {"ok": False, "stderr": "systemctl not found"},
    },
    "ports": {"listening": port_state()},
    "git": {
        "version": run(["git", "--version"]) if shutil.which("git") else {"ok": False, "stderr": "git not found"},
        "status": run(["git", "status", "--short"], cwd=repo) if (repo / ".git").exists() else {"ok": False, "stderr": "not a git repo"},
        "remote": run(["git", "remote", "-v"], cwd=repo) if (repo / ".git").exists() else {"ok": False, "stderr": "not a git repo"},
    },
    "npm_global": run(["npm", "list", "-g", "--depth=0"]) if shutil.which("npm") else {"ok": False, "stderr": "npm not found"},
    "repo": {
        "root": str(repo),
        "my_omo": file_meta(repo / ".my-omo"),
        "omo_runtime": file_meta(repo / ".omo"),
    },
}

json.dump(data, fp=os.sys.stdout, ensure_ascii=False, indent=2)
print()
PY
