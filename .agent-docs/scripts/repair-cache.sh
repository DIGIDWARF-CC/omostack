#!/usr/bin/env bash
# repair-cache.sh — чистка кэша провайдеров OpenCode
# Использование: .agent-docs/scripts/repair-cache.sh [--dry-run] [--ConfirmRepair]
set -uo pipefail

DRY_RUN=true
CONFIRM=false
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --ConfirmRepair|-y) CONFIRM=true; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

cache_path="$HOME/.cache/opencode"

emit() { printf '{"check":"repair-cache","status":"%s","detail":"%s"}\n' "$1" "$2"; }

if [ ! -d "$cache_path" ]; then
    emit "missing" "cache not found: $cache_path"
    exit 0
fi

if [ "$DRY_RUN" = true ] && [ "$CONFIRM" = false ]; then
    emit "planned" "dry-run only; remove with --ConfirmRepair: $cache_path"
    echo "Dry run — would remove: $cache_path"
    exit 0
fi

rm -rf "$cache_path"
emit "removed" "$cache_path"
echo "Cache removed at: $cache_path"
exit 0
