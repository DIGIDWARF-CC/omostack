#!/usr/bin/env bash
# omo_bootstrap.sh - root-only Ubuntu WSL bootstrap for OmO.
set -Eeuo pipefail
IFS=$'\n\t'

DEFAULT_REPO_URL="https://github.com/DIGIDWARF-CC/omostack.git"
DEFAULT_PORT="4096"
DEFAULT_TARGET="/mnt/c/AI/omostack"

YES=0
DRY_RUN=0
TARGET_PATH="${OMO_TARGET_PATH:-}"
REPO_URL="${OMO_REPO_URL:-$DEFAULT_REPO_URL}"
PORT="${OMO_PORT:-$DEFAULT_PORT}"

STATE_DIR="/root/.local/state/omo-bootstrap"
OMO_STATE_DIR="/root/.local/state/omo"
BACKUP_DIR=""
LOG_FILE=""
STATE_FILE=""
RESTART_REQUIRED=0
WINDOWS_BUILD="unknown"
WINDOWS_VERSION="unknown"
WINDOWS_NETWORK_MODE="unknown"

WIN_SYSTEM32="/mnt/c/Windows/System32"
CMD_EXE="$WIN_SYSTEM32/cmd.exe"
CURL_EXE="$WIN_SYSTEM32/curl.exe"
NETSH_EXE="$WIN_SYSTEM32/netsh.exe"

usage() {
    cat <<EOF
Usage: sudo bash bootstrap-for-human/omo_bootstrap.sh [options]

Options:
  --target PATH    OmO checkout path inside WSL, default: $DEFAULT_TARGET
  --repo URL       Git repository URL, default: $DEFAULT_REPO_URL
  --port PORT      OpenCode serve port, default: $DEFAULT_PORT
  --yes, -y        Use defaults without interactive prompts
  --dry-run        Print planned actions without mutating system files
  --help, -h       Show this help

This bootstrap is intentionally root-only and Ubuntu WSL-only. It expects a
pre-created Ubuntu WSL distro with /etc/wsl.conf present, then configures the
Ubuntu side plus Windows WSL networking through WSL interop.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
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

if ! printf '%s' "$PORT" | grep -Eq '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Invalid --port value: $PORT" >&2
    exit 2
fi

if [ "$DRY_RUN" -eq 1 ]; then
    STATE_DIR="${TMPDIR:-/tmp}/omo-bootstrap-dry-run"
fi
BACKUP_DIR="$STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$STATE_DIR/bootstrap.log"
STATE_FILE="$STATE_DIR/state.json"
mkdir -p "$STATE_DIR"

log() {
    printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE"
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

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Run this bootstrap as root inside Ubuntu WSL: sudo bash bootstrap-for-human/omo_bootstrap.sh"
    fi
}

require_ubuntu_wsl_marker() {
    if [ ! -f /etc/wsl.conf ]; then
        die "This bootstrap is only for an already provisioned Ubuntu WSL install. /etc/wsl.conf is missing; install Ubuntu under WSL first, create /etc/wsl.conf, restart WSL, then rerun."
    fi

    if [ ! -r /etc/os-release ]; then
        die "/etc/os-release is missing; cannot verify Ubuntu."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        die "This bootstrap supports Ubuntu WSL only. Detected ID=${ID:-unknown}."
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
    [ -x "$CMD_EXE" ] || return 1
    "$CMD_EXE" /d /c ver >/dev/null 2>&1
}

require_interop() {
    if interop_available; then
        log "Windows interop is available."
        return 0
    fi

    warn "Windows interop is not available yet. /etc/wsl.conf has been configured with interop enabled."
    warn "Run this from Windows, then start Ubuntu again and rerun this bootstrap:"
    warn "  wsl.exe --shutdown"
    exit 20
}

windows_cmd() {
    "$CMD_EXE" /d /c "$*" 2>/dev/null | tr -d '\r'
}

detect_windows() {
    local ver_line
    ver_line="$(windows_cmd ver | sed '/^[[:space:]]*$/d' | sed -n '1p' || true)"
    WINDOWS_VERSION="$(printf '%s\n' "$ver_line" | grep -Eo '[0-9]+([.][0-9]+)+' | head -1)"
    [ -n "$WINDOWS_VERSION" ] || WINDOWS_VERSION="unknown"
    WINDOWS_BUILD="$(printf '%s' "$WINDOWS_VERSION" | awk -F. '{ if (NF >= 3) print $3; else print $NF }')"
    if ! printf '%s' "$WINDOWS_BUILD" | grep -Eq '^[0-9]+$'; then
        WINDOWS_BUILD="0"
    fi

    if [ "$WINDOWS_BUILD" -ge 22621 ]; then
        WINDOWS_NETWORK_MODE="mirrored"
    else
        WINDOWS_NETWORK_MODE="best-effort"
    fi
    log "Windows version: $WINDOWS_VERSION (build $WINDOWS_BUILD); WSL networking mode: $WINDOWS_NETWORK_MODE"
}

update_wslconfig_content() {
    local source_file="$1"
    local dest_file="$2"
    local mode="$3"
    local desired remove_re

    remove_re='^(localhostforwarding|dnstunneling|autoproxy|networkingmode|firewall)$'
    if [ "$mode" = "mirrored" ]; then
        desired=$'dnsTunneling=true\nautoProxy=true\nnetworkingMode=mirrored\nfirewall=true'
    else
        desired=$'localhostForwarding=true'
    fi

    awk -v desired="$desired" -v remove_re="$remove_re" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function emit_desired() {
            if (in_wsl2 && !emitted) {
                print desired
                emitted = 1
            }
        }
        BEGIN {
            in_wsl2 = 0
            found_wsl2 = 0
            emitted = 0
        }
        /^[ \t]*\[[^]]+\][ \t]*$/ {
            if (in_wsl2) emit_desired()
            section = tolower($0)
            gsub(/^[ \t]*\[/, "", section)
            gsub(/\][ \t]*$/, "", section)
            in_wsl2 = (section == "wsl2")
            if (in_wsl2) {
                found_wsl2 = 1
                emitted = 0
            }
            print
            next
        }
        in_wsl2 && /^[ \t]*[^#;][^=]*=/ {
            key = $0
            sub(/=.*/, "", key)
            key = tolower(trim(key))
            if (key ~ remove_re) next
        }
        { print }
        END {
            if (in_wsl2) emit_desired()
            if (!found_wsl2) {
                if (NR > 0) print ""
                print "[wsl2]"
                print desired
            }
        }
    ' "$source_file" > "$dest_file"
}

ensure_windows_wslconfig() {
    local user_profile user_profile_wsl wslconfig tmp source
    user_profile="$(windows_cmd 'echo %USERPROFILE%' | sed -n '1p')"
    if [ -z "$user_profile" ]; then
        warn "Cannot resolve Windows USERPROFILE; skipping .wslconfig update."
        return 0
    fi

    if ! user_profile_wsl="$(win_to_wsl_path "$user_profile")"; then
        warn "Cannot convert Windows USERPROFILE to WSL path: $user_profile"
        return 0
    fi

    wslconfig="$user_profile_wsl/.wslconfig"
    tmp="$(mktemp)"
    source="$(mktemp)"
    if [ -f "$wslconfig" ]; then
        cp "$wslconfig" "$source"
    else
        : > "$source"
    fi

    update_wslconfig_content "$source" "$tmp" "$WINDOWS_NETWORK_MODE"
    rm -f "$source"

    if [ -f "$wslconfig" ] && cmp -s "$tmp" "$wslconfig"; then
        log "Windows .wslconfig already matches OmO networking keys."
        rm -f "$tmp"
        return 0
    fi

    backup_file "$wslconfig"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] write $wslconfig"
        rm -f "$tmp"
        return 0
    fi

    mkdir -p "$(dirname "$wslconfig")"
    install -m 0644 "$tmp" "$wslconfig"
    rm -f "$tmp"
    RESTART_REQUIRED=1
    log "Updated Windows .wslconfig: $wslconfig"
}

ensure_apt_packages() {
    run "Update apt package index" apt-get update
    run "Install base Ubuntu packages" apt-get install -y \
        ca-certificates curl git nodejs npm procps iproute2 tar coreutils
}

ensure_repo() {
    local parent
    parent="$(dirname "$TARGET_PATH")"
    if [ -d "$TARGET_PATH/.git" ]; then
        log "OmO repository already exists: $TARGET_PATH"
        return 0
    fi
    if [ -e "$TARGET_PATH" ] && [ "$(find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        die "Target path exists and is not an empty git checkout: $TARGET_PATH"
    fi
    run "Create OmO parent directory" mkdir -p "$parent"
    run "Clone OmO repository" git clone "$REPO_URL" "$TARGET_PATH"
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
    local config_dir template
    config_dir="/root/.config/opencode"
    template="$TARGET_PATH/.agent-docs/templates/opencode-global.example.jsonc"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] ensure $config_dir"
    else
        mkdir -p "$config_dir"
    fi

    if [ ! -f "$config_dir/opencode.jsonc" ] && [ ! -f "$config_dir/opencode.json" ] && [ -f "$template" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[dry-run] copy $template -> $config_dir/opencode.jsonc"
        else
            cp "$template" "$config_dir/opencode.jsonc"
        fi
    else
        log "OpenCode config is present or no template is available yet."
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

verify_linux_listener() {
    for _ in $(seq 1 20); do
        if ss -H -tln 2>/dev/null | awk -v suffix=":$PORT" '$4 ~ suffix "$" { found = 1 } END { exit found ? 0 : 1 }'; then
            log "OpenCode is listening inside Ubuntu on port $PORT."
            return 0
        fi
        sleep 1
    done
    warn "OpenCode listener was not detected on port $PORT yet."
    return 1
}

windows_curl_ok() {
    [ -x "$CURL_EXE" ] || return 1
    "$CURL_EXE" -fsS --max-time 8 "http://127.0.0.1:$PORT/" >/dev/null 2>&1
}

configure_windows_portproxy() {
    local wsl_ip
    wsl_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    if [ -z "$wsl_ip" ]; then
        warn "Cannot determine WSL IP for Windows portproxy."
        return 1
    fi
    if [ ! -x "$NETSH_EXE" ]; then
        warn "netsh.exe is not available through interop; cannot configure portproxy."
        return 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] netsh portproxy 127.0.0.1:$PORT -> $wsl_ip:$PORT"
        return 0
    fi

    "$NETSH_EXE" interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport="$PORT" >/dev/null 2>&1 || true
    if "$NETSH_EXE" interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport="$PORT" connectaddress="$wsl_ip" connectport="$PORT" >/dev/null 2>&1; then
        log "Windows portproxy configured: 127.0.0.1:$PORT -> $wsl_ip:$PORT"
        return 0
    fi

    warn "Cannot configure Windows portproxy. Start Ubuntu as Administrator or add it manually with netsh."
    return 1
}

ensure_windows_access() {
    if windows_curl_ok; then
        log "Windows can reach OpenCode at http://127.0.0.1:$PORT/."
        return 0
    fi

    warn "Windows loopback test failed; trying loopback-only portproxy."
    configure_windows_portproxy || return 0

    if windows_curl_ok; then
        log "Windows can reach OpenCode through portproxy at http://127.0.0.1:$PORT/."
    else
        warn "Windows still cannot reach http://127.0.0.1:$PORT/. Check service logs and Windows networking."
    fi
}

write_state() {
    install_text_file "$STATE_FILE" 0644 root:root <<EOF
{
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_url": "$(json_escape "$REPO_URL")",
  "target_path": "$(json_escape "$TARGET_PATH")",
  "port": $PORT,
  "windows_version": "$(json_escape "$WINDOWS_VERSION")",
  "windows_build": "$(json_escape "$WINDOWS_BUILD")",
  "windows_network_mode": "$(json_escape "$WINDOWS_NETWORK_MODE")",
  "opencode": "/usr/local/bin/opencode",
  "root_only": true
}
EOF
}

main() {
    require_root
    choose_target_path

    log "=== OmO root-only Ubuntu WSL bootstrap ==="
    log "Target path: $TARGET_PATH"
    log "Repository: $REPO_URL"
    log "Port: $PORT"
    log "Mode: $([ "$DRY_RUN" -eq 1 ] && printf dry-run || printf real-run)"

    require_ubuntu_wsl_marker
    write_wsl_conf
    require_interop
    detect_windows
    ensure_windows_wslconfig
    ensure_apt_packages
    ensure_repo
    ensure_opencode
    ensure_opencode_config
    ensure_opencode_service
    verify_linux_listener || true
    ensure_windows_access
    write_state

    log "=== OmO bootstrap complete ==="
    log "OpenCode URL: http://127.0.0.1:$PORT/"
    log "Log file: $LOG_FILE"
    log "State file: $STATE_FILE"
    if [ "$RESTART_REQUIRED" -eq 1 ]; then
        warn "WSL config changed. If networking/systemd/interoperability behaves oddly, run from Windows: wsl.exe --shutdown"
    fi
}

main "$@"
