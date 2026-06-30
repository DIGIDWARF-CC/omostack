#!/usr/bin/env bash
# check-config.sh — аудит конфигураций OpenCode и oh-my-openagent
# Использование: .agent-docs/scripts/check-config.sh [--dry-run]
set -uo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=true; fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
config_root="$xdg_config/opencode"
project_config="$repo_root/.opencode"
profile_file="${XDG_STATE_HOME:-$HOME/.local/state}/omo-bootstrap/install-profile"

emit() { printf '{"check":"%s","status":"%s","detail":"%s"}\n' "$1" "$2" "$3"; }

detect_profile() {
    local value=""
    if [ -r "$profile_file" ]; then
        IFS= read -r value < "$profile_file" || true
        case "$value" in
            light|full) printf '%s\n' "$value"; return ;;
        esac
    fi
    if grep -Rqs '"oh-my-openagent' \
        "$config_root/opencode.json" \
        "$config_root/opencode.jsonc" 2>/dev/null; then
        printf 'full\n'
    else
        printf 'unknown\n'
    fi
}

install_profile="$(detect_profile)"

is_json_readable() {
    local file="$1"
    # Strip // comments (jsonc-lite) and try parse
    sed 's|^//.*$||' "$file" 2>/dev/null | python3 -m json.tool &>/dev/null && return 0 || return 1
}

echo "=== Config Audit ==="
if [ "$DRY_RUN" = true ]; then
    echo "(dry-run mode)"
fi
if [ ! -r "$profile_file" ]; then
    emit "install-profile" "missing" "no valid installer profile marker at $profile_file; inferred $install_profile"
elif [ "$install_profile" = unknown ]; then
    emit "install-profile" "missing" "no valid installer profile marker at $profile_file"
else
    emit "install-profile" "present" "$install_profile"
fi

# Check all candidate config files
candidates=(
    "${config_root}/opencode.json"
    "${config_root}/opencode.jsonc"
    "${config_root}/oh-my-openagent.json"
    "${config_root}/oh-my-openagent.jsonc"
    "${config_root}/oh-my-opencode.json"
    "${config_root}/oh-my-opencode.jsonc"
    "${project_config}/oh-my-openagent.json"
    "${project_config}/oh-my-openagent.jsonc"
    "${project_config}/oh-my-opencode.json"
    "${project_config}/oh-my-opencode.jsonc"
)

for path in "${candidates[@]}"; do
    if [ -f "$path" ]; then
        if is_json_readable "$path"; then
            emit "config-file" "present" "$path"
        else
            emit "config-file" "unhealthy" "not readable as JSON/JSONC: $path"
        fi
    fi
done

# Check legacy/current collision
has_current=false
has_legacy=false
for p in "${config_root}/oh-my-openagent.json" "${config_root}/oh-my-openagent.jsonc" \
         "${project_config}/oh-my-openagent.json" "${project_config}/oh-my-openagent.jsonc"; do
    [ -f "$p" ] && has_current=true
done
for p in "${config_root}/oh-my-opencode.json" "${config_root}/oh-my-opencode.jsonc" \
         "${project_config}/oh-my-opencode.json" "${project_config}/oh-my-opencode.jsonc"; do
    [ -f "$p" ] && has_legacy=true
done

if $has_current && $has_legacy; then
    emit "oh-my-openagent-name-collision" "unhealthy" "current and legacy config names both exist — archive legacy, keep current"
elif $has_legacy; then
    emit "oh-my-openagent-name-collision" "unhealthy" "legacy oh-my-opencode config exists without current name — migrate to oh-my-openagent"
else
    emit "oh-my-openagent-name-collision" "present" "no legacy/current collision detected"
fi

opencode_json="${config_root}/opencode.json"
opencode_jsonc="${config_root}/opencode.jsonc"

if [ -f "$opencode_json" ] && [ -f "$opencode_jsonc" ]; then
    emit "opencode-config-collision" "unhealthy" "opencode.json and opencode.jsonc both exist — archive opencode.jsonc and keep opencode.json"
elif [ -f "$opencode_json" ]; then
    emit "opencode-config-collision" "present" "canonical opencode.json is active"
elif [ -f "$opencode_jsonc" ]; then
    emit "opencode-config-collision" "present" "compatible opencode.jsonc is active"
else
    emit "opencode-config-collision" "missing" "no OpenCode config found"
fi

plugin_found=false
if [ -f "$opencode_json" ]; then
    if grep -q '"oh-my-opencode"' "$opencode_json"; then
        emit "plugin-name" "unhealthy" "legacy plugin name 'oh-my-opencode' found in opencode.json — change to 'oh-my-openagent'"
        plugin_found=true
    elif grep -q '"oh-my-openagent' "$opencode_json"; then
        emit "plugin-name" "present" "current plugin name 'oh-my-openagent' found in opencode.json"
        plugin_found=true
    fi
fi

if [ "$plugin_found" = false ] && [ -f "$opencode_jsonc" ]; then
    if grep -q '"oh-my-opencode"' "$opencode_jsonc"; then
        emit "plugin-name" "unhealthy" "legacy plugin name 'oh-my-opencode' found in opencode.jsonc — change to 'oh-my-openagent'"
        plugin_found=true
    elif grep -q '"oh-my-openagent' "$opencode_jsonc"; then
        emit "plugin-name" "present" "current plugin name 'oh-my-openagent' found in opencode.jsonc"
        plugin_found=true
    else
        if [ "$install_profile" = light ]; then
            emit "plugin-name" "present" "OmO plugin is intentionally absent in the light profile"
        else
            emit "plugin-name" "missing" "no oh-my plugin entry found in OpenCode config"
        fi
    fi
elif [ "$plugin_found" = false ]; then
    if [ "$install_profile" = light ] && { [ -f "$opencode_json" ] || [ -f "$opencode_jsonc" ]; }; then
        emit "plugin-name" "present" "OmO plugin is intentionally absent in the light profile"
    else
        emit "plugin-name" "missing" "OpenCode config not found at $opencode_json or $opencode_jsonc"
    fi
fi

if [ "$install_profile" = light ] && [ "$plugin_found" = true ]; then
    emit "profile-plugin-consistency" "unhealthy" "OmO plugin is present while the installer profile is light"
fi

echo ""
echo "=== End Config Audit ==="
exit 0
