#!/usr/bin/env bash
# check-scaffold.sh — проверка структуры репозитория omostack home
# Использование: .agent-docs/scripts/check-scaffold.sh [--all|--scope|--remote-access|--templates|--script-safety|--setup-directives|--troubleshooting|--gitignore|--links]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=()

git_safe() {
    git -c "safe.directory=${repo_root}" -C "$repo_root" "$@"
}

assert_file() {
    if [ -f "${repo_root}/$1" ]; then echo "PASS file exists: $1"; else failures+=("file missing: $1"); fi
}
assert_contains() {
    local file="${repo_root}/$1" pattern="$2"
    if grep -q "$pattern" "$file" 2>/dev/null; then echo "PASS $1 contains '$pattern'"; else failures+=("$1 missing pattern '$pattern'"); fi
}
assert_not_contains() {
    local file="${repo_root}/$1" pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then echo "PASS $1 does not contain '$pattern'"; else failures+=("$1 contains forbidden pattern '$pattern'"); fi
}

run_scope() {
    assert_contains "AGENTS.md" "omostack home"
    assert_contains "AGENTS.md" "not an application"
    assert_contains ".agent-docs/README.md" "omostack home"
    assert_contains ".agent-docs/agent-instructions.md" "not an application"
    assert_contains ".agent-docs/agent-instructions.md" ".my-omo/"
    assert_contains ".agent-docs/agent-instructions.md" ".omo/"
}

run_remote_access() {
    assert_contains ".agent-docs/agent-remote-access.md" ".my-omo/remote-access/"
    assert_contains ".agent-docs/agent-remote-access.md" "Do not add .gitkeep"
}

run_templates() {
    for f in ".agent-docs/templates/README.md" \
             ".agent-docs/templates/remote-access.example.jsonc" \
             ".agent-docs/templates/opencode-global.example.jsonc" \
             ".agent-docs/templates/opencode-light.example.jsonc" \
             ".agent-docs/templates/oh-my-openagent.example.jsonc" \
             ".agent-docs/templates/opencode-agent-stack.md" \
             ".agent-docs/templates/install-state.example.json"; do
        assert_file "$f"
    done
    assert_not_contains ".agent-docs/templates/oh-my-openagent.example.jsonc" "ghp_"
    assert_not_contains ".agent-docs/templates/opencode-agent-stack.md" "## OmO Agent Roles"
    assert_not_contains ".agent-docs/templates/opencode-agent-stack.md" "heavy agentic work"
}

run_script_safety() {
    assert_file "bootstrap-for-human/omo_host_bootstrap.cmd"
    assert_file "bootstrap-for-human/omo_bootstrap.sh"
    assert_file "bootstrap-for-human/omo_cleanup.cmd"
    assert_file "bootstrap-for-human/Opencode-wsl-setup.zip"
    assert_file "bootstrap-for-human-light/omo_host_bootstrap.cmd"
    assert_file "bootstrap-for-human-light/omo_bootstrap.sh"
    assert_file "bootstrap-for-human-light/omo_cleanup.cmd"
    assert_file "bootstrap-for-human-light/Opencode-wsl-light-setup.zip"
    assert_contains "bootstrap-for-human/omo_host_bootstrap.cmd" "cscript.exe"
    assert_contains "bootstrap-for-human/omo_host_bootstrap.cmd" "wscript.exe"
    assert_contains "bootstrap-for-human/omo_host_bootstrap.cmd" "start-opencode-wsl-hidden.vbs"
    assert_contains "bootstrap-for-human/omo_host_bootstrap.cmd" "ExecutionTimeLimit = \"PT0S\""
    assert_contains "bootstrap-for-human/omo_host_bootstrap.cmd" "netsh.exe interface portproxy"
    assert_contains "bootstrap-for-human/omo_bootstrap.sh" "oh-my-openagent.example.jsonc"
    for f in check-health.sh check-config.sh backup-omostack.sh cleanup-temp.sh \
             repair-cache.sh check-scaffold.sh OOBE-setup.sh diagnostic.sh \
             build-bootstrap-packages.sh; do
        assert_file ".agent-docs/scripts/$f"
    done
    local shell_file
    for shell_file in \
        "${repo_root}/bootstrap-for-human/omo_bootstrap.sh" \
        "${repo_root}/bootstrap-for-human-light/omo_bootstrap.sh" \
        "${repo_root}"/.agent-docs/scripts/*.sh; do
        if bash -n "$shell_file"; then
            echo "PASS Bash parses: ${shell_file#"$repo_root/"}"
        else
            failures+=("Bash parse failed: ${shell_file#"$repo_root/"}")
        fi
    done
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck \
            "${repo_root}/bootstrap-for-human/omo_bootstrap.sh" \
            "${repo_root}/bootstrap-for-human-light/omo_bootstrap.sh" \
            "${repo_root}"/.agent-docs/scripts/*.sh; then
            echo "PASS ShellCheck"
        else
            failures+=("ShellCheck reported errors")
        fi
    else
        echo "SKIP ShellCheck: shellcheck is unavailable"
    fi

    local cmd_file jscript_tmp
    for cmd_file in \
        "${repo_root}/bootstrap-for-human/omo_host_bootstrap.cmd" \
        "${repo_root}/bootstrap-for-human-light/omo_host_bootstrap.cmd" \
        "${repo_root}/bootstrap-for-human/omo_cleanup.cmd" \
        "${repo_root}/bootstrap-for-human-light/omo_cleanup.cmd"; do
        jscript_tmp="$(mktemp --suffix=.js)"
        awk '{
            sub(/\r$/, "")
            if (found) print
            if ($0 == "*/") found = 1
        }' "$cmd_file" > "$jscript_tmp"
        if command -v node >/dev/null 2>&1 && node --check "$jscript_tmp" >/dev/null; then
            echo "PASS embedded JScript parses: ${cmd_file#"$repo_root/"}"
        elif ! command -v node >/dev/null 2>&1; then
            echo "SKIP embedded JScript parse check: node is unavailable"
        else
            failures+=("embedded JScript failed parse check: ${cmd_file#"$repo_root/"}")
        fi
        rm -f "$jscript_tmp"
    done

    for template in opencode-global.example.jsonc opencode-light.example.jsonc oh-my-openagent.example.jsonc; do
        if python3 -m json.tool "${repo_root}/.agent-docs/templates/$template" >/dev/null; then
            echo "PASS $template parses as JSON"
        else
            failures+=("$template failed JSON parse check")
        fi
    done
    if python3 - "$repo_root" <<'PY'
import json
import sys
from pathlib import Path

templates = Path(sys.argv[1]) / ".agent-docs" / "templates"
full = json.loads((templates / "opencode-global.example.jsonc").read_text())
light = json.loads((templates / "opencode-light.example.jsonc").read_text())

assert light["model"] == full["model"] == "opencode/deepseek-v4-flash-free"
assert light["small_model"] == full["small_model"] == "opencode/north-mini-code-free"
assert light["lsp"] == full["lsp"]
assert light["mcp"] == full["mcp"]
assert light["shell"] == full["shell"]
assert light["agent"] == {"title": {"disable": True}}
assert "plugin" not in light
assert "instructions" not in light
assert any(item.startswith("oh-my-openagent@") for item in full["plugin"])
PY
    then
        echo "PASS light template retains common models/LSP/MCP and excludes OmO overrides"
    else
        failures+=("light/full template profile invariants failed")
    fi
    assert_not_contains ".agent-docs/templates/oh-my-openagent.example.jsonc" "lmstudio"
    assert_contains ".agent-docs/scripts/repair-cache.sh" "ConfirmRepair"
    if find "${repo_root}/.agent-docs/scripts" -maxdepth 1 -name '*.ps1' | grep -q .; then
        failures+=("legacy .ps1 scripts found under .agent-docs/scripts")
    else
        echo "PASS no legacy .ps1 scripts under .agent-docs/scripts"
    fi
    if find "${repo_root}/bootstrap-for-human" -maxdepth 1 -name '*.ps1' | grep -q .; then
        failures+=("PowerShell bootstrap files found under bootstrap-for-human")
    else
        echo "PASS no PowerShell bootstrap files under bootstrap-for-human"
    fi
    if find "${repo_root}/bootstrap-for-human-light" -maxdepth 1 -name '*.ps1' | grep -q .; then
        failures+=("PowerShell bootstrap files found under bootstrap-for-human-light")
    else
        echo "PASS no PowerShell bootstrap files under bootstrap-for-human-light"
    fi

    if python3 - "$repo_root" <<'PY'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
full = root / "bootstrap-for-human"
light = root / "bootstrap-for-human-light"

full_cmd = (full / "omo_host_bootstrap.cmd").read_bytes()
light_cmd = (light / "omo_host_bootstrap.cmd").read_bytes()
full_cleanup = (full / "omo_cleanup.cmd").read_bytes()
light_cleanup = (light / "omo_cleanup.cmd").read_bytes()
full_sh = (full / "omo_bootstrap.sh").read_text()
light_sh = (light / "omo_bootstrap.sh").read_text()

assert b"\n" not in full_cmd.replace(b"\r\n", b"")
assert b"\n" not in light_cmd.replace(b"\r\n", b"")
assert b"\n" not in full_cleanup.replace(b"\r\n", b"")
assert b"\n" not in light_cleanup.replace(b"\r\n", b"")
assert "\r" not in full_sh
assert "\r" not in light_sh
assert full_cleanup == light_cleanup
full_cleanup.decode("utf-8")
assert not full_cleanup.startswith(b"\xef\xbb\xbf")
assert b"chcp 65001" in full_cleanup
assert "I AGREE TO DELETE MY WSL COMPLETELY".encode() in full_cleanup
assert "ВНИМАНИЕ".encode("utf-8") in full_cleanup

normalized_full_cmd = full_cmd.replace(b'set "PROFILE=full"', b'set "PROFILE=PROFILE"')
normalized_light_cmd = light_cmd.replace(b'set "PROFILE=light"', b'set "PROFILE=PROFILE"')
assert normalized_full_cmd == normalized_light_cmd

normalized_full_sh = full_sh.replace('DEFAULT_PROFILE="full"', 'DEFAULT_PROFILE="PROFILE"')
normalized_light_sh = light_sh.replace('DEFAULT_PROFILE="light"', 'DEFAULT_PROFILE="PROFILE"')
assert normalized_full_sh == normalized_light_sh

packages = (
    (full, "Opencode-wsl-setup.zip"),
    (light, "Opencode-wsl-light-setup.zip"),
)
for directory, archive_name in packages:
    with zipfile.ZipFile(directory / archive_name) as zf:
        assert zf.namelist() == ["omo_host_bootstrap.cmd", "omo_bootstrap.sh", "omo_cleanup.cmd"]
        for name in zf.namelist():
            assert zf.read(name) == (directory / name).read_bytes()
PY
    then
        echo "PASS full/light scripts differ only by profile and ZIP payloads are current"
    else
        failures+=("full/light parity, line endings, or ZIP payload validation failed")
    fi
}

run_setup_directives() {
    assert_file ".agent-docs/setup-directives.md"
    local file="${repo_root}/.agent-docs/setup-directives.md"
    for token in "Status Detection" "Health Check" "Config Audit" "Provider Auth" \
                 "Backup and Rollback" "Cache Repair" "Temp Cleanup" \
                 "Remote-Access Initialization" "Upgrade Flow" "Escalation"; do
        assert_contains ".agent-docs/setup-directives.md" "$token"
    done
}

run_troubleshooting() {
    for f in ".agent-docs/troubleshooting.md" ".agent-docs/provider-auth.md" \
             ".agent-docs/model-and-config-reference.md"; do
        assert_file "$f"
    done
    for token in "ProviderInitError" "ProviderModelNotFoundError" "oh-my-openagent" \
                 "missing" "unhealthy" "doctor"; do
        assert_contains ".agent-docs/troubleshooting.md" "$token"
    done
}

run_gitignore() {
    if command -v git &>/dev/null; then
        local ignored=true tracked=true
        git_safe check-ignore -q -- ".my-omo/remote-access/example.local.jsonc" 2>/dev/null || ignored=false
        git_safe check-ignore -q -- ".omo/boulder.json" 2>/dev/null || ignored=false
        git_safe ls-files -- ".agent-docs/templates/README.md" &>/dev/null && tracked=true || tracked=false
        if $ignored; then echo "PASS .my-omo private paths are ignored"; else failures+=(".my-omo not properly ignored"); fi
        if $tracked; then echo "PASS templates are tracked by git"; else failures+=("templates not tracked by git"); fi
    else
        # Fallback: check .gitignore text directly
        assert_contains ".gitignore" "/.my-omo/"
        assert_contains ".gitignore" "/.omo/"
    fi
}

run_links() {
    assert_file ".agent-docs/self-bootstrap-checklist.md"
    for token in "setup-directives.md" "agent-remote-access.md" "troubleshooting.md" \
                 "provider-auth.md" "model-and-config-reference.md" "self-bootstrap-checklist.md" \
                 "scripts/" "templates/"; do
        assert_contains ".agent-docs/README.md" "$token"
    done
    if rg -n --glob '!check-scaffold.sh' "config-audit.sh|Windows \\(pwsh fallback\\)|daemon-reload \\+ restart|создаётся автоматически|/mnt/s/FastNeuros/omo" \
        "${repo_root}/OOBE.md" "${repo_root}/.agent-docs" >/tmp/omo-forbidden-docs.log 2>/dev/null; then
        failures+=("active docs contain forbidden legacy/OOBE promises; see /tmp/omo-forbidden-docs.log")
    else
        echo "PASS active docs avoid legacy OOBE promises"
        rm -f /tmp/omo-forbidden-docs.log
    fi
}

# Parse args
checks=()
case "${1:-all}" in
    all|--all) checks=(scope remote_access templates script_safety setup_directives troubleshooting gitignore links) ;;
    scope) checks=(scope) ;;
    remote-access) checks=(remote_access) ;;
    templates) checks=(templates) ;;
    script-safety) checks=(script_safety) ;;
    setup-directives) checks=(setup_directives) ;;
    troubleshooting) checks=(troubleshooting) ;;
    gitignore) checks=(gitignore) ;;
    links) checks=(links) ;;
    *) echo "Unknown check: $1. Use --all or specific name."; exit 1 ;;
esac

for check in "${checks[@]}"; do
    echo "== $check =="
    case "$check" in
        scope) run_scope ;;
        remote_access) run_remote_access ;;
        templates) run_templates ;;
        script_safety) run_script_safety ;;
        setup_directives) run_setup_directives ;;
        troubleshooting) run_troubleshooting ;;
        gitignore) run_gitignore ;;
        links) run_links ;;
    esac
done

if [ ${#failures[@]} -gt 0 ]; then
    echo ""
    echo "FAILED ${#failures[@]} scaffold checks:"
    for f in "${failures[@]}"; do echo "  ❌ $f"; done
    exit 1
fi

echo ""
echo "OK all scaffold checks passed"
exit 0
