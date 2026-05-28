#!/usr/bin/env bash
# cleanup-temp.sh — очистка старых temp-файлов в ignored папках
# Использование: .agent-docs/scripts/cleanup-temp.sh [--dry-run] [--OlderThanDays 7]
set -uo pipefail

DRY_RUN=false
OLDER_THAN=7
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --OlderThanDays|-d) OLDER_THAN="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cutoff=$(date -d "-${OLDER_THAN} days" +%s 2>/dev/null || date -v-${OLDER_THAN}d +%s 2>/dev/null)

targets=(
    "${repo_root}/.my-omo/temp"
    "${repo_root}/.omo/evidence"
)

for target in "${targets[@]}"; do
    [ ! -d "$target" ] && continue

    find "$target" -type f -mtime +${OLDER_THAN} 2>/dev/null | while read -r file; do
        if [ "$DRY_RUN" = true ]; then
            echo "[dry-run] would remove: $file"
        else
            rm -f "$file"
            echo "removed: $file"
        fi
    done
done

[ "$DRY_RUN" = true ] && echo "(dry-run complete)" || echo "Cleanup complete"
exit 0
