#!/usr/bin/env bash
# omo_bootstrap.sh - root-only Ubuntu WSL stage for OmO.
set -Eeuo pipefail
IFS=$'\n\t'

DEFAULT_REPO_URL="https://github.com/DIGIDWARF-CC/omostack.git"
DEFAULT_PORT="4096"
DEFAULT_TARGET="/mnt/c/AI/omostack"
DEFAULT_PROFILE="full"

MODE="install"
PROFILE="${OMO_INSTALL_PROFILE:-$DEFAULT_PROFILE}"
YES=0
DRY_RUN=0
HOST_MANAGED=0
PROFILE_MANAGED=0
TARGET_PATH="${OMO_TARGET_PATH:-}"
REPO_URL="${OMO_REPO_URL:-$DEFAULT_REPO_URL}"
PORT="${OMO_PORT:-$DEFAULT_PORT}"

STATE_DIR="/root/.local/state/omo-bootstrap"
OMO_STATE_DIR="/root/.local/state/omo"
INSTALLED_PROFILE_FILE="/root/.local/state/omo-bootstrap/install-profile"
STATUS_JSON="$STATE_DIR/host-status.json"
LOG_FILE="$STATE_DIR/bootstrap.log"
BACKUP_DIR="$STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)"
PROFILE_FILE="$STATE_DIR/install-profile"

usage() {
    cat <<EOF
Usage: sudo bash bootstrap-for-human/omo_bootstrap.sh [options]

Options:
  --mode MODE      install, repair, or status. Default: install
  --profile NAME   Installation profile: light or full. Default: $DEFAULT_PROFILE
  --target PATH    OmO checkout path inside WSL. Default: $DEFAULT_TARGET
  --repo URL       Git repository URL. Default: $DEFAULT_REPO_URL
  --port PORT      OpenCode serve port. Default: $DEFAULT_PORT
  --status-json P  Status JSON path for the Windows host component
  --host-managed   Called by omo_host_bootstrap.cmd
  --yes, -y        Use defaults without interactive prompts
  --dry-run        Print planned Ubuntu actions without mutating Ubuntu
  --help, -h       Show this help

This is the Ubuntu-side stage only. Windows WSL setup, .wslconfig, registry,
and portproxy are owned by omo_host_bootstrap.cmd.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        --target)
            TARGET_PATH="${2:-}"
            shift 2
            ;;
        --repo)
            REPO_URL="${2:-}"
            shift 2
            ;;
        --port)
            PORT="${2:-}"
            shift 2
            ;;
        --status-json)
            STATUS_JSON="${2:-}"
            shift 2
            ;;
        --host-managed)
            HOST_MANAGED=1
            shift
            ;;
        --yes|-y)
            YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$MODE" in
    install|repair|status) ;;
    *) echo "Invalid --mode value: $MODE" >&2; exit 2 ;;
esac

case "$PROFILE" in
    light|full) ;;
    *) echo "Invalid --profile value: $PROFILE" >&2; exit 2 ;;
esac

if ! printf '%s' "$PORT" | grep -Eq '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Invalid --port value: $PORT" >&2
    exit 2
fi

if [ "$MODE" = "status" ]; then
    LOG_FILE="/dev/null"
elif [ "$DRY_RUN" -eq 1 ]; then
    STATE_DIR="${TMPDIR:-/tmp}/omo-bootstrap-dry-run"
    OMO_STATE_DIR="${TMPDIR:-/tmp}/omo-dry-run"
    STATUS_JSON="$STATE_DIR/host-status.json"
    LOG_FILE="$STATE_DIR/bootstrap.log"
    BACKUP_DIR="$STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)"
    PROFILE_FILE="$STATE_DIR/install-profile"
    mkdir -p "$STATE_DIR"
else
    mkdir -p "$STATE_DIR"
fi

log() {
    local line
    line="$(printf '%s %s\n' "$(date -Iseconds)" "$*")"
    if [ "$MODE" = "status" ]; then
        printf '%s\n' "$line" >&2
    else
        printf '%s\n' "$line" | tee -a "$LOG_FILE"
    fi
}

warn() {
    log "WARN: $*"
}

die() {
    log "ERROR: $*"
    exit 1
}

try_run() {
    local desc="$1"
    shift
    local command_line
    printf -v command_line '%q ' "$@"
    log "[run] $desc"
    log "Command: ${command_line% }"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] skipped"
        return 0
    fi

    local status
    set +e
    "$@" 2>&1 | tee -a "$LOG_FILE"
    status=${PIPESTATUS[0]}
    set -e
    log "Command exit code: $status"
    return "$status"
}

run() {
    local desc="$1"
    shift
    try_run "$desc" "$@" || die "$desc failed"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

installed_profile() {
    local value=""
    if [ -r "$INSTALLED_PROFILE_FILE" ]; then
        IFS= read -r value < "$INSTALLED_PROFILE_FILE" || true
        case "$value" in
            light|full)
                printf '%s\n' "$value"
                return
                ;;
        esac
    fi

    if grep -Rqs '"oh-my-openagent' \
        /root/.config/opencode/opencode.json \
        /root/.config/opencode/opencode.jsonc 2>/dev/null; then
        printf 'full\n'
    else
        printf 'unknown\n'
    fi
}

write_profile_marker() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] write install profile '$PROFILE' to $PROFILE_FILE"
        return
    fi
    mkdir -p "$(dirname "$PROFILE_FILE")"
    printf '%s\n' "$PROFILE" > "$PROFILE_FILE"
    log "Install profile recorded: $PROFILE"
}

guard_profile_transition() {
    local current
    current="$(installed_profile)"
    if [ "$PROFILE" = "light" ] && [ "$current" = "full" ]; then
        die "Refusing full -> light downgrade. The existing full OmOStack installation was not changed."
    fi
}

backup_file() {
    local path="$1"
    [ -e "$path" ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] backup $path -> $BACKUP_DIR/"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    cp -a "$path" "$BACKUP_DIR/$(basename "$path")"
    log "Backup saved: $BACKUP_DIR/$(basename "$path")"
}

install_text_file() {
    local path="$1"
    local mode="$2"
    local owner="${3:-root:root}"
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp"

    if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
        log "$path already matches desired content."
        rm -f "$tmp"
        return 0
    fi

    backup_file "$path"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] write $path"
        rm -f "$tmp"
        return 0
    fi

    mkdir -p "$(dirname "$path")"
    install -o "${owner%%:*}" -g "${owner#*:}" -m "$mode" "$tmp" "$path"
    rm -f "$tmp"
    log "Updated $path"
}

write_generated_file() {
    local path="$1"
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] write $path"
        rm -f "$tmp"
        return 0
    fi

    mkdir -p "$(dirname "$path")"
    install -m 0644 "$tmp" "$path"
    rm -f "$tmp"
    log "Updated $path"
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Run this stage as root inside Ubuntu WSL."
    fi
}

require_ubuntu_wsl() {
    if [ ! -f /etc/wsl.conf ]; then
        die "This stage is only for an already provisioned Ubuntu WSL install. /etc/wsl.conf is missing."
    fi

    if [ ! -r /etc/os-release ]; then
        die "/etc/os-release is missing; cannot verify Ubuntu."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        die "This stage supports Ubuntu WSL only. Detected ID=${ID:-unknown}."
    fi

    if ! grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null && [ -z "${WSL_DISTRO_NAME:-}" ]; then
        die "This does not look like WSL. Refusing to run on non-WSL Ubuntu."
    fi
}

win_to_wsl_path() {
    local path="$1"
    path="${path//$'\r'/}"
    path="${path//$'\n'/}"
    case "$path" in
        [A-Za-z]:\\*|[A-Za-z]:/*)
            local drive rest
            drive="$(printf '%s' "${path:0:1}" | tr '[:upper:]' '[:lower:]')"
            rest="${path:2}"
            rest="${rest//\\//}"
            printf '/mnt/%s%s\n' "$drive" "$rest"
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_target_path() {
    local path="$1"
    if win_to_wsl_path "$path" >/dev/null 2>&1; then
        win_to_wsl_path "$path"
    else
        printf '%s\n' "$path"
    fi
}

choose_target_path() {
    if [ -z "$TARGET_PATH" ]; then
        if [ "$YES" -eq 0 ] && [ -t 0 ]; then
            local answer
            printf 'OmO target path inside WSL [%s]: ' "$DEFAULT_TARGET"
            read -r answer
            TARGET_PATH="${answer:-$DEFAULT_TARGET}"
        else
            TARGET_PATH="$DEFAULT_TARGET"
        fi
    fi
    TARGET_PATH="$(normalize_target_path "$TARGET_PATH")"
}

write_wsl_conf() {
    install_text_file /etc/wsl.conf 0644 root:root <<'EOF'
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=false

[automount]
enabled=true
root=/mnt/

[user]
default=root
EOF
}

interop_available() {
    [ -x /mnt/c/Windows/System32/cmd.exe ] || return 1
    /mnt/c/Windows/System32/cmd.exe /d /c ver >/dev/null 2>&1
}

ensure_apt_packages() {
    run "Update apt package index" apt-get update
    run "Install base Ubuntu packages" apt-get install -y \
        ca-certificates curl git nodejs npm procps iproute2 tar coreutils
}

ensure_repo_install() {
    local parent
    parent="$(dirname "$TARGET_PATH")"
    if [ -d "$TARGET_PATH/.git" ]; then
        log "OmO repository already exists: $TARGET_PATH"
        sync_repo_checkout
        return 0
    fi
    if [ -e "$TARGET_PATH" ] && [ "$(find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        die "Target path exists and is not an empty git checkout: $TARGET_PATH"
    fi
    run "Create OmO parent directory" mkdir -p "$parent"
    run "Clone OmO repository" git clone "$REPO_URL" "$TARGET_PATH"
    sync_repo_checkout
}

require_repo_for_repair() {
    if [ ! -d "$TARGET_PATH/.git" ]; then
        die "Repair mode requires an existing OmO git checkout at $TARGET_PATH. Run install first."
    fi
    log "OmO repository present: $TARGET_PATH"
    sync_repo_checkout
}

sync_repo_checkout() {
    local remote_ref candidate
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] force-sync $TARGET_PATH to the default branch of $REPO_URL"
        log "[dry-run] preserve ignored/private .my-omo and runtime .omo directories"
        return 0
    fi
    [ -d "$TARGET_PATH/.git" ] || die "Cannot synchronize a non-git target: $TARGET_PATH"

    if git -C "$TARGET_PATH" remote get-url origin >/dev/null 2>&1; then
        run "Set OmO origin URL" git -C "$TARGET_PATH" remote set-url origin "$REPO_URL"
    else
        run "Add OmO origin URL" git -C "$TARGET_PATH" remote add origin "$REPO_URL"
    fi
    run "Fetch current OmO delivery" git -C "$TARGET_PATH" fetch --prune origin
    if ! try_run "Refresh OmO origin default branch" git -C "$TARGET_PATH" remote set-head origin --auto; then
        warn "Could not refresh origin/HEAD; using a verified remote branch."
    fi

    remote_ref="$(git -C "$TARGET_PATH" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -z "$remote_ref" ]; then
        for candidate in origin/main origin/master; do
            if git -C "$TARGET_PATH" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
                remote_ref="$candidate"
                break
            fi
        done
    fi
    [ -n "$remote_ref" ] || die "Cannot determine the remote default branch for $REPO_URL."

    run "Reset OmO checkout to $remote_ref" git -C "$TARGET_PATH" reset --hard "$remote_ref"
    run "Remove unmanaged checkout files" git -C "$TARGET_PATH" clean -fd -e .my-omo -e .omo
}

discover_opencode() {
    local candidate
    for candidate in \
        /usr/local/bin/opencode \
        /usr/local/lib/omo-opencode/opencode \
        /root/.opencode/bin/opencode \
        /root/.local/bin/opencode \
        /root/.local/share/opencode/bin/opencode; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v opencode >/dev/null 2>&1; then
        command -v opencode
        return 0
    fi
    find /root /usr/local /opt -maxdepth 7 \( -type f -o -type l \) -name opencode -perm -111 -print 2>/dev/null | head -1
}

ensure_opencode() {
    local opencode_src managed src_real
    opencode_src="$(discover_opencode || true)"
    if [ -z "$opencode_src" ]; then
        run "Install OpenCode through official installer" bash -c \
            'curl -fsSL https://opencode.ai/install | HOME=/root XDG_CONFIG_HOME=/root/.config bash -s -- --no-modify-path'
        opencode_src="$(discover_opencode || true)"
    fi
    [ -n "$opencode_src" ] || die "OpenCode binary was not found after installer finished."

    managed="/usr/local/lib/omo-opencode/opencode"
    src_real="$(readlink -f "$opencode_src" 2>/dev/null || printf '%s' "$opencode_src")"
    if [ "$src_real" != "$managed" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] install $opencode_src -> $managed"
        else
            mkdir -p "$(dirname "$managed")"
            install -m 0755 "$opencode_src" "$managed"
        fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] link /usr/local/bin/opencode -> $managed"
    else
        ln -sfn "$managed" /usr/local/bin/opencode
        chmod 0755 "$managed"
    fi

    install_text_file /etc/profile.d/omo-opencode.sh 0644 root:root <<'EOF'
export PATH=/usr/local/bin:$PATH
EOF

    run "Check OpenCode version" /usr/local/bin/opencode --version
}

ensure_opencode_config() {
    local config_dir template light_template stack_template omo_template
    local json jsonc omo_json omo_jsonc tui stamp current marker_present config_present upgrade
    config_dir="/root/.config/opencode"
    template="$TARGET_PATH/.agent-docs/templates/opencode-global.example.jsonc"
    light_template="$TARGET_PATH/.agent-docs/templates/opencode-light.example.jsonc"
    stack_template="$TARGET_PATH/.agent-docs/templates/opencode-agent-stack.md"
    omo_template="$TARGET_PATH/.agent-docs/templates/oh-my-openagent.example.jsonc"
    json="$config_dir/opencode.json"
    jsonc="$config_dir/opencode.jsonc"
    omo_json="$config_dir/oh-my-openagent.json"
    omo_jsonc="$config_dir/oh-my-openagent.jsonc"
    tui="$config_dir/tui.json"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    current="$(installed_profile)"
    marker_present=0
    config_present=0
    upgrade=0
    [ -r "$INSTALLED_PROFILE_FILE" ] && marker_present=1
    if [ -f "$json" ] || [ -f "$jsonc" ]; then
        config_present=1
    fi

    if [ "$marker_present" -eq 1 ] && [ "$current" = "light" ] && [ "$PROFILE" = "full" ]; then
        upgrade=1
        PROFILE_MANAGED=1
        log "Upgrading the installer-managed profile from light to full."
    elif [ "$marker_present" -eq 1 ] && [ "$current" = "$PROFILE" ]; then
        PROFILE_MANAGED=1
    elif [ "$marker_present" -eq 0 ] && [ "$config_present" -eq 0 ]; then
        PROFILE_MANAGED=1
        log "No existing OpenCode config was found; creating the $PROFILE profile."
    else
        warn "Existing OpenCode config is not marked as installer-managed; preserving it unchanged."
        warn "Profile-specific OpenCode and OmO files will not be installed automatically."
        return 0
    fi

    if [ "$PROFILE" = "full" ]; then
        [ -f "$template" ] || die "Full OpenCode config template is not available: $template"
        [ -f "$omo_template" ] || die "Oh My OpenAgent config template is not available: $omo_template"
        [ -f "$stack_template" ] || die "OpenCode agent instruction template is not available: $stack_template"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] ensure $config_dir"
    else
        mkdir -p "$config_dir"
    fi

    if [ "$upgrade" -eq 1 ]; then
        backup_file "$json"
        backup_file "$jsonc"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] replace active OpenCode config with $template"
        else
            rm -f "$json" "$jsonc"
            cp "$template" "$json"
        fi
    elif [ -f "$jsonc" ] && [ -f "$json" ]; then
        backup_file "$jsonc"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] archive conflicting $jsonc -> $jsonc.disabled-by-omo-$stamp"
        else
            mv "$jsonc" "$jsonc.disabled-by-omo-$stamp"
        fi
    elif [ ! -f "$json" ] && [ ! -f "$jsonc" ]; then
        if [ "$PROFILE" = "light" ]; then
            template="$light_template"
        fi
        [ -f "$template" ] || die "OpenCode config template is not available: $template"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] copy $template -> $json"
        else
            cp "$template" "$json"
        fi
    elif [ -f "$json" ]; then
        log "OpenCode config is present: $json"
    elif [ -f "$jsonc" ]; then
        log "OpenCode JSONC config is present: $jsonc"
    fi

    if [ "$PROFILE" = "light" ]; then
        log "Light profile selected; OmO plugin files are intentionally not installed."
        return 0
    fi

    if [ -f "$omo_json" ] && [ -f "$omo_jsonc" ]; then
        backup_file "$omo_jsonc"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] archive conflicting $omo_jsonc -> $omo_jsonc.disabled-by-omo-$stamp"
        else
            mv "$omo_jsonc" "$omo_jsonc.disabled-by-omo-$stamp"
        fi
    fi

    if [ ! -f "$omo_json" ] && [ ! -f "$omo_jsonc" ] && [ -f "$omo_template" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] copy $omo_template -> $omo_json"
        else
            cp "$omo_template" "$omo_json"
        fi
    elif [ -f "$omo_json" ]; then
        log "Oh My OpenAgent config is present: $omo_json"
    elif [ -f "$omo_jsonc" ]; then
        log "Oh My OpenAgent JSONC config is present: $omo_jsonc"
    else
        warn "Oh My OpenAgent config template is not available: $omo_template"
    fi

    if cmp -s "$stack_template" "$config_dir/opencode-agent-stack.md" 2>/dev/null; then
        log "OpenCode agent instructions already match the delivery template."
    else
        backup_file "$config_dir/opencode-agent-stack.md"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] synchronize $stack_template -> $config_dir/opencode-agent-stack.md"
        else
            cp "$stack_template" "$config_dir/opencode-agent-stack.md"
        fi
    fi

    if [ ! -f "$tui" ]; then
        write_generated_file "$tui" <<'EOF'
{
  "plugin": ["oh-my-openagent/tui"]
}
EOF
    fi
}

systemd_available() {
    [ -d /run/systemd/system ] || return 1
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl list-units >/dev/null 2>&1
}

stop_oneshot_on_port() {
    local pids pid cmdline
    pids="$(ss -H -tlnp 2>/dev/null | awk -v suffix=":$PORT" '$4 ~ suffix "$" { print }' | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | sort -u || true)"
    [ -n "$pids" ] || return 0
    for pid in $pids; do
        [ -r "/proc/$pid/cmdline" ] || continue
        cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
        if printf '%s' "$cmdline" | grep -q 'opencode'; then
            if [ "$DRY_RUN" -eq 1 ]; then
                log "[dry-run] kill old opencode process on port $PORT: pid $pid"
            else
                kill "$pid" 2>/dev/null || true
            fi
        fi
    done
}

start_opencode_oneshot() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] start opencode serve one-shot on port $PORT"
        return 0
    fi
    mkdir -p "$OMO_STATE_DIR"
    stop_oneshot_on_port
    nohup env HOME=/root XDG_CONFIG_HOME=/root/.config XDG_STATE_HOME=/root/.local/state \
        /usr/local/bin/opencode serve --hostname 0.0.0.0 --port "$PORT" \
        > "$OMO_STATE_DIR/opencode-serve.log" 2>&1 &
    sleep 2
}

ensure_opencode_service() {
    install_text_file /etc/systemd/system/opencode-serve.service 0644 root:root <<EOF
[Unit]
Description=OpenCode headless server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$TARGET_PATH
Environment=HOME=/root
Environment=XDG_CONFIG_HOME=/root/.config
Environment=XDG_STATE_HOME=/root/.local/state
ExecStart=/usr/local/bin/opencode serve --hostname 0.0.0.0 --port $PORT
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    if systemd_available; then
        run "Reload systemd units" systemctl daemon-reload
        run "Enable OpenCode service" systemctl enable opencode-serve.service
        if ! try_run "Restart OpenCode service" systemctl restart opencode-serve.service; then
            warn "systemd restart failed; falling back to one-shot OpenCode serve."
            start_opencode_oneshot
        fi
    else
        warn "systemd is not active in this WSL session; starting one-shot OpenCode serve."
        start_opencode_oneshot
    fi
}

listener_status() {
    if ss -H -tln 2>/dev/null | awk -v suffix=":$PORT" '$4 ~ suffix "$" { found = 1 } END { exit found ? 0 : 1 }'; then
        printf 'true'
    else
        printf 'false'
    fi
}

verify_linux_listener() {
    local _
    for _ in $(seq 1 20); do
        if [ "$(listener_status)" = "true" ]; then
            log "OpenCode is listening inside Ubuntu on port $PORT."
            return 0
        fi
        sleep 1
    done
    warn "OpenCode listener was not detected on port $PORT yet."
    return 1
}

service_mode() {
    if systemd_available && systemctl is-active --quiet opencode-serve.service 2>/dev/null; then
        printf 'systemd'
        return
    fi
    if pgrep -af 'opencode serve' >/dev/null 2>&1; then
        printf 'oneshot'
        return
    fi
    printf 'missing'
}

first_wsl_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

opencode_version() {
    if [ -x /usr/local/bin/opencode ]; then
        /usr/local/bin/opencode --version 2>/dev/null | head -1 || true
    elif command -v opencode >/dev/null 2>&1; then
        opencode --version 2>/dev/null | head -1 || true
    fi
}

status_json_text() {
    local wsl_ip listener svc version interop current
    wsl_ip="$(first_wsl_ip)"
    listener="$(listener_status)"
    svc="$(service_mode)"
    version="$(opencode_version)"
    current="$(installed_profile)"
    if interop_available; then interop="true"; else interop="false"; fi

    cat <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "$(json_escape "$MODE")",
  "profile": "$(json_escape "$current")",
  "requested_profile": "$(json_escape "$PROFILE")",
  "target_path": "$(json_escape "$TARGET_PATH")",
  "repo_url": "$(json_escape "$REPO_URL")",
  "port": $PORT,
  "wsl_ip": "$(json_escape "$wsl_ip")",
  "service_mode": "$(json_escape "$svc")",
  "listener": $listener,
  "opencode_version": "$(json_escape "$version")",
  "interop_available": $interop,
  "root_only": true
}
EOF
}

write_status_json() {
    local json
    json="$(status_json_text)"
    if [ "$MODE" = "status" ]; then
        printf '%s\n' "$json"
        return 0
    fi
    write_generated_file "$STATUS_JSON" <<EOF
$json
EOF
}

run_install() {
    guard_profile_transition
    write_wsl_conf
    ensure_apt_packages
    ensure_repo_install
    ensure_opencode
    ensure_opencode_config
    if [ "$PROFILE_MANAGED" -eq 1 ]; then
        write_profile_marker
    fi
    ensure_opencode_service
    verify_linux_listener || true
    write_status_json
}

run_repair() {
    guard_profile_transition
    write_wsl_conf
    require_repo_for_repair
    ensure_opencode
    ensure_opencode_config
    if [ "$PROFILE_MANAGED" -eq 1 ]; then
        write_profile_marker
    fi
    ensure_opencode_service
    verify_linux_listener || true
    write_status_json
}

main() {
    require_root
    choose_target_path
    require_ubuntu_wsl

    if [ "$MODE" = "status" ]; then
        write_status_json
        exit 0
    fi

    log "=== OmO Ubuntu WSL stage ==="
    log "Mode: $MODE"
    log "Requested profile: $PROFILE"
    log "Installed profile: $(installed_profile)"
    log "Target path: $TARGET_PATH"
    log "Repository: $REPO_URL"
    log "Port: $PORT"
    log "Host-managed: $HOST_MANAGED"
    log "Dry-run: $DRY_RUN"

    case "$MODE" in
        install) run_install ;;
        repair) run_repair ;;
    esac

    log "=== OmO Ubuntu WSL stage complete ==="
    log "Status JSON: $STATUS_JSON"
    log "Log file: $LOG_FILE"
}

main "$@"
