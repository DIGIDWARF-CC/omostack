#!/usr/bin/env bash
# troubleshoot.sh — интерактивное меню проблем и решений
# Использование: .agent-docs/recipes/troubleshoot.sh
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

active_opencode_config() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    if [ -f "$config_dir/opencode.json" ]; then
        printf '%s\n' "$config_dir/opencode.json"
    elif [ -f "$config_dir/opencode.jsonc" ]; then
        printf '%s\n' "$config_dir/opencode.jsonc"
    fi
}

show_menu() {
    echo "=== Omostack Troubleshooter ==="
    echo ""
    echo "Выберите проблему:"
    echo "  1) Git dubious ownership"
    echo "  2) opencode: command not found"
    echo "  3) oh-my-openagent doctor fails"
    echo "  4) Config collision (legacy vs current)"
    echo "  5) Port already in use (4096)"
    echo "  6) TUI plugin missing"
    echo "  7) Provider auth / model resolution error"
    echo "  8) systemd service won't start"
    echo "  9) Run full diagnostic dump"
    echo "  0) Exit"
    echo ""
    read -rp "Ваш выбор: " choice
}

fix_git_dubious_ownership() {
    echo ""
    echo "--- Git dubious ownership ---"
    local repo_dir
    repo_dir="$(pwd)"

    # Check if already fixed
    if git config --global --get safe.directory 2>/dev/null | grep -q "$repo_dir"; then
        echo "✓ Already configured: $repo_dir is a safe directory"
        return
    fi

    read -rp "Fix: add '$repo_dir' as safe directory? [Y/n] " confirm
    if [[ "${confirm:-Y}" != [Nn]* ]]; then
        git config --global --add safe.directory "$repo_dir"
        echo "✓ Added $repo_dir to safe directories"

        # Also try the mount point (WSL common pattern)
        local mount_point
        mount_point=$(df . 2>/dev/null | awk 'NR==2{print $1}' | sed 's|/dev/sd[a-z][0-9]*||' || true)
        if [ -n "$mount_point" ] && [ "$mount_point" != "/" ]; then
            echo "ℹ Mount point detected: $mount_point — also adding..."
            git config --global --add safe.directory "$mount_point/*" 2>/dev/null || true
        fi

        # Verify
        if git status &>/dev/null; then
            echo "✓ Git now works!"
        else
            echo "⚠ Git still has issues — check output above"
        fi
    fi
}

fix_opencode_not_in_path() {
    echo ""
    echo "--- opencode: command not found ---"
    local bin=""
    for candidate in ~/.opencode/bin/opencode /usr/local/bin/opencode; do
        [ -x "$candidate" ] && bin="$candidate" && break
    done

    if [ -z "$bin" ]; then
        echo "❌ opencode binary not found at common locations"
        echo "   Check: find ~/.opencode -name opencode 2>/dev/null"
        return
    fi

    read -rp "Create symlink /usr/local/bin/opencode -> $bin? [Y/n] " confirm
    if [[ "${confirm:-Y}" != [Nn]* ]]; then
        ln -sf "$bin" /usr/local/bin/opencode 2>&1
        if command -v opencode &>/dev/null; then
            echo "✓ Symlink created, opencode now in PATH"
        else
            echo "⚠ /usr/local/bin not writable or not in PATH"
            read -rp "Or add to your ~/.bashrc? [Y/n] " confirm2
            if [[ "${confirm2:-Y}" != [Nn]* ]]; then
                echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> "$HOME/.bashrc"
                echo "✓ Added to .bashrc — run: source ~/.bashrc"
            fi
        fi
    fi
}

fix_ohmyopenagent_fails() {
    echo ""
    echo "--- oh-my-openagent doctor fails ---"
    # Check global install
    if ! command -v oh-my-openagent &>/dev/null; then
        echo "❌ oh-my-openagent not globally installed"
        read -rp "Run: npm install -g oh-my-openagent@4.11.1? [Y/n] " confirm
        if [[ "${confirm:-Y}" != [Nn]* ]]; then
            npm install -g oh-my-openagent@4.11.1 2>&1 | tail -5
        fi
    fi

    # Check tui.json
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    if [ ! -f "$xdg/tui.json" ]; then
        echo "❌ tui.json missing at $xdg/"
        read -rp "Create it? [Y/n] " confirm
        if [[ "${confirm:-Y}" != [Nn]* ]]; then
            mkdir -p "$xdg"
            printf '{\n  "plugin": ["oh-my-openagent/tui"]\n}\n' > "$xdg/tui.json"
            echo "✓ Created tui.json"
        fi
    fi

    # Check opencode config plugin entry
    local opencode_config
    opencode_config="$(active_opencode_config)"
    if [ -n "$opencode_config" ] && ! grep -q '"oh-my-openagent"' "$opencode_config"; then
        echo "⚠ Plugin entry missing from $opencode_config"
    fi

    echo ""
    echo "Re-run: oh-my-openagent doctor"
}

fix_config_collision() {
    echo ""
    echo "--- Config collision (legacy vs current) ---"
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

    if [ -f "$xdg/oh-my-opencode.jsonc" ] && [ ! -f "$xdg/oh-my-openagent.json" ]; then
        echo "Found legacy: oh-my-opencode.jsonc"
        read -rp "Archive and create new oh-my-openagent config? [Y/n] " confirm
        if [[ "${confirm:-Y}" != [Nn]* ]]; then
            mv "$xdg/oh-my-opencode.jsonc" "$xdg/oh-my-opencode.jsonc.bak"
            cp "$(cd "$(dirname "$0")/../.." && pwd)/.agent-docs/templates/oh-my-openagent.example.jsonc" \
               "$xdg/oh-my-openagent.json"
            echo "✓ Legacy archived, new config created"
        fi
    elif [ -f "$xdg/oh-my-opencode.json" ] && [ ! -f "$xdg/oh-my-openagent.json" ]; then
        echo "Found legacy: oh-my-opencode.json"
        read -rp "Archive and create new? [Y/n] " confirm
        if [[ "${confirm:-Y}" != [Nn]* ]]; then
            mv "$xdg/oh-my-opencode.json" "$xdg/oh-my-opencode.json.bak"
            cp "$(cd "$(dirname "$0")/../.." && pwd)/.agent-docs/templates/oh-my-openagent.example.jsonc" \
               "$xdg/oh-my-openagent.json"
            echo "✓ Legacy archived, new config created"
        fi
    else
        echo "No collision detected"
    fi
}

fix_port_in_use() {
    echo ""
    echo "--- Port 4096 already in use ---"
    local pid=""
    if command -v ss &>/dev/null; then
        pid=$(ss -tlnp 2>/dev/null | grep ':4096' | awk '{print $5}' | grep -oP 'pid=\K[0-9]+' | head -1)
    elif command -v lsof &>/dev/null; then
        pid=$(lsof -i :4096 2>/dev/null | awk 'NR==2{print $2}')
    fi

    if [ -n "$pid" ]; then
        echo "Process on port 4096: PID=$pid"
        ps -p "$pid" -o comm= 2>/dev/null || true
        read -rp "Kill process? [Y/n] " confirm
        if [[ "${confirm:-Y}" != [Nn]* ]]; then
            kill "$pid" 2>&1 && echo "✓ Process killed" || echo "⚠ Kill failed — try: kill -9 $pid"
        fi
    else
        echo "No process found on port 4096"
    fi
}

fix_tui_missing() {
    echo ""
    echo "--- TUI plugin missing ---"
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    mkdir -p "$xdg"

    if [ ! -f "$xdg/tui.json" ]; then
        printf '{\n  "plugin": ["oh-my-openagent/tui"]\n}\n' > "$xdg/tui.json"
        echo "✓ Created tui.json with oh-my-openagent/tui entry"
    else
        if ! grep -q '"oh-my-openagent/tui"' "$xdg/tui.json"; then
            printf '{\n  "plugin": ["oh-my-openagent/tui"]\n}\n' > "$xdg/tui.json"
            echo "✓ Updated tui.json with oh-my-openagent/tui entry"
        else
            echo "✓ tui.json already has correct entry"
        fi
    fi

    # Also check the active OpenCode config for the plugin entry.
    local opencode_config
    opencode_config="$(active_opencode_config)"
    if [ -n "$opencode_config" ] && ! grep -q '"oh-my-openagent"' "$opencode_config"; then
        echo "⚠ Also add to $opencode_config:"
        echo '   "plugin": ["oh-my-openagent"]'
    fi
}

fix_provider_auth() {
    echo ""
    echo "--- Provider auth / model resolution error ---"
    echo ""
    echo "Step 1: Check provider auth"
    if command -v opencode &>/dev/null; then
        opencode auth list 2>&1 || true
    fi
    echo ""
    echo "Step 2: Check logs"
    opencode --print-logs 2>&1 | tail -20 || true
    echo ""
    echo "Common fixes:"
    echo "  • Re-authenticate through OpenCode desktop: opencode auth login <provider>"
    echo "  • Verify the model id in opencode.json (or compatible JSONC) matches the provider"
    echo ""
    echo "For detailed guide: .agent-docs/provider-auth.md"
}

fix_systemd_service() {
    echo ""
    echo "--- systemd service won't start ---"
    if ! command -v systemctl &>/dev/null; then
        echo "systemctl not found — are you on Linux/WSL?"
        return
    fi

    echo "Service status:"
    systemctl status opencode-serve.service 2>&1 | head -20 || true

    echo ""
    echo "Journal logs (last 30 lines):"
    journalctl -u opencode-serve.service --no-pager -n 30 2>/dev/null || echo "(journalctl not available)"

    echo ""
    echo "Common fixes:"
    echo "  • Check ExecStart path: which opencode"
    echo "  • Verify config dir permissions: ls -la ~/.config/opencode/"
    echo "  • Reload after config changes: systemctl daemon-reload && systemctl restart opencode-serve.service"
}

# Main loop
while true; do
    show_menu
    case "$choice" in
        1) fix_git_dubious_ownership ;;
        2) fix_opencode_not_in_path ;;
        3) fix_ohmyopenagent_fails ;;
        4) fix_config_collision ;;
        5) fix_port_in_use ;;
        6) fix_tui_missing ;;
        7) fix_provider_auth ;;
        8) fix_systemd_service ;;
        9)
            echo ""
            echo "=== Full Diagnostic Dump ==="
            "$repo_root/.agent-docs/scripts/diagnostic.sh"
            ;;
        0|q|Q)
            echo "Done."
            exit 0
            ;;
        *)
            echo "Invalid choice. Try again."
            ;;
    esac
    echo ""
    read -rp "Continue troubleshooting? [Y/n] " cont
    [[ "${cont:-Y}" == [Nn]* ]] && break
    echo ""
done
