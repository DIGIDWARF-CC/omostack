#!/usr/bin/env bash
# check-health.sh — не-деструктивная проверка доступности инструментов и путей
# Использование: .agent-docs/scripts/check-health.sh [--dry-run]
set -uo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=true; fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
profile_file="${XDG_STATE_HOME:-$HOME/.local/state}/omo-bootstrap/install-profile"

detect_profile() {
    local value=""
    if [ -r "$profile_file" ]; then
        IFS= read -r value < "$profile_file" || true
        case "$value" in
            light|full) printf '%s\n' "$value"; return ;;
        esac
    fi
    if grep -Rqs '"oh-my-openagent' \
        "$xdg_config/opencode/opencode.json" \
        "$xdg_config/opencode/opencode.jsonc" 2>/dev/null; then
        printf 'full\n'
    else
        printf 'unknown\n'
    fi
}

install_profile="$(detect_profile)"

emit() {
    # Emit: {"check":"name","status":"present|missing|unhealthy","detail":"..."}
    printf '{"check":"%s","status":"%s","detail":"%s"}\n' "$1" "$2" "$3"
}

cmd_exists() { command -v "$1" &>/dev/null; }

echo "=== Health Check ==="
if [ "$DRY_RUN" = true ]; then
    echo "(dry-run mode)"
fi
emit "mode" "present" "check-health is non-destructive; --dry-run accepted for operator safety"
if [ ! -r "$profile_file" ]; then
    emit "install-profile" "missing" "no valid installer profile marker at $profile_file; inferred $install_profile"
elif [ "$install_profile" = unknown ]; then
    emit "install-profile" "missing" "no valid installer profile marker at $profile_file"
else
    emit "install-profile" "present" "$install_profile"
fi

# --- opencode CLI ---
if cmd_exists opencode; then
    if ver=$(opencode --version 2>&1 | head -1); then
        emit "opencode" "present" "$ver"
    else
        emit "opencode" "unhealthy" "$ver"
    fi
else
    # Try common locations as fallback hint
    if [ -x ~/.opencode/bin/opencode ]; then
        emit "opencode" "missing" "binary found at ~/.opencode/bin/opencode but not in PATH; run: ln -sf ~/.opencode/bin/opencode /usr/local/bin/opencode"
    else
        emit "opencode" "missing" "command not found in PATH"
    fi
fi

# --- node/bun ---
for cmd in node bun; do
    if cmd_exists "$cmd"; then
        ver=$("$cmd" --version 2>&1 | head -1)
        emit "$cmd" "present" "$ver"
    else
        emit "$cmd" "missing" "command not found in PATH"
    fi
done

# --- oh-my-openagent doctor access (full profile only) ---
if [ "$install_profile" = light ]; then
    emit "oh-my-openagent-doctor" "present" "not required by the light profile"
elif cmd_exists bunx; then
    emit "oh-my-openagent-doctor" "present" "bunx available; run: oh-my-openagent doctor or bunx oh-my-openagent doctor"
elif cmd_exists bun; then
    emit "oh-my-openagent-doctor" "present" "bun available; bunx may be provided by bun on this system"
else
    if cmd_exists oh-my-openagent; then
        emit "oh-my-openagent-doctor" "present" "oh-my-openagent binary found in PATH (global install)"
    else
        emit "oh-my-openagent-doctor" "missing" "bun/bunx and oh-my-openagent not found — install globally: npm install -g oh-my-openagent@4.11.1"
    fi
fi

# --- Path checks (WSL/Linux) ---
paths=(
    "base-marker:${repo_root}/.my-omo/omostack-base-install-done"
    "private-install-state:${repo_root}/.my-omo/install-state.json"
    "private-remote-access:${repo_root}/.my-omo/remote-access"
    "opencode-cache:$HOME/.cache/opencode"
)

for entry in "${paths[@]}"; do
    name="${entry%%:*}"
    path="${entry#*:}"
    if [ -e "$path" ]; then
        emit "$name" "present" "$path"
    else
        emit "$name" "missing" "$path"
    fi
done

if [ -f "${xdg_config}/opencode/opencode.json" ]; then
    emit "opencode-user-config" "present" "${xdg_config}/opencode/opencode.json"
elif [ -f "${xdg_config}/opencode/opencode.jsonc" ]; then
    emit "opencode-user-config" "present" "${xdg_config}/opencode/opencode.jsonc (compatible JSONC)"
else
    emit "opencode-user-config" "missing" "${xdg_config}/opencode/opencode.json"
fi

echo ""
echo "=== End Health Check ==="
exit 0
