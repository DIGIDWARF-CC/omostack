#!/usr/bin/env bash
# Stage-2 OOBE setup for agents running inside WSL/Linux.
# Human bootstrap starts from bootstrap-for-human/omo_host_bootstrap.cmd.
set -euo pipefail

AUTO=false
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --auto) AUTO=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Usage: OOBE-setup.sh [--auto] [--dry-run]"; exit 1 ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
opencode_config="$xdg_config/opencode"
state_dir="$repo_root/.my-omo"
state_file="$state_dir/install-state.json"
marker_file="$state_dir/omostack-base-install-done"

log() { printf '%s\n' "$*"; }
run_or_echo() {
    if [ "$DRY_RUN" = true ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}
write_file() {
    local path="$1"
    local content="$2"
    if [ "$DRY_RUN" = true ]; then
        printf '[dry-run] write %s\n' "$path"
    else
        mkdir -p "$(dirname "$path")"
        printf '%s\n' "$content" > "$path"
    fi
}
copy_if_missing() {
    local src="$1" dest="$2"
    if [ -f "$dest" ]; then
        log "  present: $dest"
        return
    fi
    if [ "$DRY_RUN" = true ]; then
        log "[dry-run] copy $src -> $dest"
    else
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    fi
}
tool_version() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        if [ "$DRY_RUN" = true ]; then
            printf 'present at %s' "$(command -v "$tool")"
            return
        fi
        "$tool" --version 2>&1 | head -1 || true
    else
        printf 'missing'
    fi
}

detect_os() {
    if [ "$(uname -s)" = "Linux" ] && [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "wsl-linux"
    elif [ "$(uname -s)" = "Linux" ]; then
        echo "linux"
    else
        echo "other"
    fi
}

log "=== OmO Stage-2 OOBE ==="
log "Repo root: $repo_root"
log "Mode: $([ "$DRY_RUN" = true ] && echo dry-run || echo real-run)"
log "OS: $(detect_os)"

log "[1/7] Tool inventory"
for cmd in opencode oh-my-openagent comment-checker node npm git curl systemctl; do
    log "  $cmd: $(tool_version "$cmd")"
done

log "[2/7] Optional agent tools"
if command -v npm >/dev/null 2>&1; then
    if command -v oh-my-openagent >/dev/null 2>&1; then
        log "  present: oh-my-openagent"
    elif [ "$AUTO" = true ]; then
        run_or_echo npm install -g oh-my-openagent
    else
        log "  missing: oh-my-openagent; run with --auto to install through npm"
    fi

    if command -v comment-checker >/dev/null 2>&1; then
        log "  present: comment-checker"
    elif [ "$AUTO" = true ]; then
        run_or_echo npm install -g @code-yeongyu/comment-checker
    else
        log "  missing: comment-checker; optional"
    fi
else
    log "  missing: npm; Ubuntu OOBE stage should install Node/npm first"
fi

log "[3/7] OpenCode config"
if [ "$DRY_RUN" = true ]; then
    log "[dry-run] ensure directory $opencode_config"
else
    mkdir -p "$opencode_config"
fi

if [ ! -f "$opencode_config/opencode.jsonc" ] && [ ! -f "$opencode_config/opencode.json" ]; then
    copy_if_missing "$repo_root/.agent-docs/templates/opencode-global.example.jsonc" "$opencode_config/opencode.jsonc"
else
    log "  present: OpenCode config"
    if ! grep -Rqs '"oh-my-openagent"' "$opencode_config"/opencode.json "$opencode_config"/opencode.jsonc 2>/dev/null; then
        log "  warning: config does not mention oh-my-openagent; add it manually if this stack needs the plugin"
    fi
fi

copy_if_missing "$repo_root/.agent-docs/templates/oh-my-openagent.example.jsonc" "$opencode_config/oh-my-openagent.json"
if [ ! -f "$opencode_config/tui.json" ]; then
    write_file "$opencode_config/tui.json" '{ "plugin": ["oh-my-openagent/tui"] }'
else
    log "  present: $opencode_config/tui.json"
fi

log "[4/7] Systemd service"
service_file="/etc/systemd/system/opencode-serve.service"
opencode_bin="$(command -v opencode 2>/dev/null || true)"
if [ -z "$opencode_bin" ] && [ -x "$HOME/.opencode/bin/opencode" ]; then
    opencode_bin="$HOME/.opencode/bin/opencode"
fi
if [ -z "$opencode_bin" ]; then
    log "  missing: opencode binary; skip service setup"
elif [ "$(id -u)" -ne 0 ]; then
    log "  missing permission: root is required to create $service_file"
    log "  action: run the Ubuntu OOBE stage through the Windows host bootstrap or rerun inside WSL as root"
elif [ "$DRY_RUN" = true ]; then
    log "[dry-run] write $service_file"
    log "[dry-run] systemctl daemon-reload && systemctl enable --now opencode-serve.service"
else
    cat > "$service_file" <<SVCEOF
[Unit]
Description=OpenCode headless server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$repo_root
Environment=HOME=$HOME
Environment=XDG_CONFIG_HOME=$xdg_config
ExecStart=$opencode_bin serve --hostname 0.0.0.0 --port 4096
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable --now opencode-serve.service
fi

log "[5/7] Health checks"
if [ "$DRY_RUN" = true ]; then
    log "[dry-run] skip runtime health scripts to avoid OpenCode cache/state creation"
else
    "$repo_root/.agent-docs/scripts/check-health.sh" --dry-run || true
    "$repo_root/.agent-docs/scripts/check-config.sh" --dry-run || true
fi

log "[6/7] Install state"
if [ "$DRY_RUN" = true ]; then
    log "[dry-run] write $marker_file"
    log "[dry-run] write $state_file"
else
    mkdir -p "$state_dir"
    touch "$marker_file"
    cat > "$state_file" <<JSON
{
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_root": "$repo_root",
  "stage": "wsl-agent-stage-2",
  "opencode": "$(command -v opencode 2>/dev/null || true)",
  "oh_my_openagent": "$(command -v oh-my-openagent 2>/dev/null || true)"
}
JSON
fi

log "[7/7] Next verification"
log "  .agent-docs/scripts/check-scaffold.sh --all"
log "  .agent-docs/scripts/diagnostic.sh > .my-omo/diagnostic.json"
log "=== Stage-2 OOBE complete ==="
