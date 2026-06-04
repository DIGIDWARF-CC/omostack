#!/usr/bin/env bash
# check-scaffold.sh — проверка структуры репозитория omostack home
# Использование: .agent-docs/scripts/check-scaffold.sh [--all|--scope|--remote-access|--templates|--script-safety|--setup-directives|--troubleshooting|--gitignore|--links]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=()

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
             ".agent-docs/templates/oh-my-openagent.example.jsonc" \
             ".agent-docs/templates/install-state.example.json"; do
        assert_file "$f"
    done
    assert_not_contains ".agent-docs/templates/oh-my-openagent.example.jsonc" "ghp_"
}

run_script_safety() {
    assert_file "bootstrap-for-human/omo_bootstrap.sh"
    for f in check-health.sh check-config.sh backup-omostack.sh cleanup-temp.sh \
             repair-cache.sh check-scaffold.sh OOBE-setup.sh diagnostic.sh; do
        assert_file ".agent-docs/scripts/$f"
    done
    if bash -n "${repo_root}/bootstrap-for-human/omo_bootstrap.sh"; then
        echo "PASS omo_bootstrap.sh parses as Bash"
    else
        failures+=("omo_bootstrap.sh failed Bash parse check")
    fi
    assert_contains ".agent-docs/scripts/repair-cache.sh" "ConfirmRepair"
    if find "${repo_root}/.agent-docs/scripts" -maxdepth 1 -name '*.ps1' | grep -q .; then
        failures+=("legacy .ps1 scripts found under .agent-docs/scripts")
    else
        echo "PASS no legacy .ps1 scripts under .agent-docs/scripts"
    fi

    local diag_tmp
    diag_tmp="$(mktemp)"
    if "${repo_root}/.agent-docs/scripts/diagnostic.sh" > "$diag_tmp" && python3 -m json.tool "$diag_tmp" >/dev/null; then
        echo "PASS diagnostic.sh emits valid JSON"
    else
        failures+=("diagnostic.sh output is not valid JSON")
    fi
    rm -f "$diag_tmp"

    local dry_home dry_xdg before after
    dry_home="$(mktemp -d)"
    dry_xdg="$(mktemp -d)"
    before="$(find "$dry_home" "$dry_xdg" -mindepth 1 -print | sort)"
    HOME="$dry_home" XDG_CONFIG_HOME="$dry_xdg" "${repo_root}/.agent-docs/scripts/OOBE-setup.sh" --dry-run >/tmp/omo-oobe-dry-run.log
    after="$(find "$dry_home" "$dry_xdg" -mindepth 1 -print | sort)"
    if [ "$before" = "$after" ]; then
        echo "PASS OOBE-setup.sh --dry-run did not create HOME/XDG files"
    else
        failures+=("OOBE-setup.sh --dry-run created files under temp HOME/XDG")
    fi
    rm -rf "$dry_home" "$dry_xdg" /tmp/omo-oobe-dry-run.log
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
        git -C "$repo_root" check-ignore -q -- ".my-omo/remote-access/example.local.jsonc" 2>/dev/null || ignored=false
        git -C "$repo_root" check-ignore -q -- ".omo/boulder.json" 2>/dev/null || ignored=false
        git -C "$repo_root" ls-files -- ".agent-docs/templates/README.md" &>/dev/null && tracked=true || tracked=false
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
    if rg -n --glob '!check-scaffold.sh' "config-audit.sh|Windows \\(pwsh fallback\\)|daemon-reload \\+ restart|создаётся автоматически" \
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
