#!/usr/bin/env bash
# Targeted backup for OmO private state and high-value OpenCode configs.
set -euo pipefail

dest=""
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --destination|-d) dest="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Usage: backup-omostack.sh --destination <path> [--dry-run]"; exit 1 ;;
    esac
done

if [ -z "$dest" ]; then
    echo "Usage: backup-omostack.sh --destination <path> [--dry-run]"
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

includes=(
    "$repo_root/.my-omo"
    "$xdg_config/opencode/opencode.json"
    "$xdg_config/opencode/opencode.jsonc"
    "$xdg_config/opencode/oh-my-openagent.json"
    "$xdg_config/opencode/oh-my-openagent.jsonc"
    "$xdg_config/opencode/tui.json"
)

excludes=(
    "node_modules"
    ".cache"
    "cache"
    "logs"
    "tmp"
    "provider-cache"
    "providers/cache"
)

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

emit_manifest() {
    local destination="$1"
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_escape "$timestamp")"
    printf '  "destination": %s,\n' "$(json_escape "$destination")"
    printf '  "dry_run": %s,\n' "$([ "$DRY_RUN" = true ] && echo true || echo false)"
    printf '  "included": [\n'
    local first=true
    for src in "${includes[@]}"; do
        [ "$first" = true ] || printf ',\n'
        first=false
        printf '    {"path": %s, "exists": %s}' "$(json_escape "$src")" "$([ -e "$src" ] && echo true || echo false)"
    done
    printf '\n  ],\n'
    printf '  "skipped_patterns": [\n'
    first=true
    for pattern in "${excludes[@]}"; do
        [ "$first" = true ] || printf ',\n'
        first=false
        printf '    %s' "$(json_escape "$pattern")"
    done
    printf '\n  ]\n'
    printf '}\n'
}

if [ "$DRY_RUN" = true ]; then
    emit_manifest "$dest"
    exit 0
fi

mkdir -p "$dest/config" "$dest/private"

if [ -d "$repo_root/.my-omo" ]; then
    tar_args=()
    for pattern in "${excludes[@]}"; do
        tar_args+=("--exclude=$pattern")
    done
    tar -C "$repo_root" "${tar_args[@]}" -cf "$dest/private/my-omo.tar" ".my-omo"
fi

for cfg in "${includes[@]:1}"; do
    if [ -f "$cfg" ]; then
        cp -p "$cfg" "$dest/config/$(basename "$cfg")"
    fi
done

emit_manifest "$dest" > "$dest/backup-manifest.json"
echo "Backup complete: $dest"
