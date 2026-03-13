#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
SERVICE_NAME="webcamwebsite"
LABEL="com.$SERVICE_NAME"

# ── helpers ────────────────────────────────────────────────────────────────────

setup_venv() {
    if [ ! -d "$VENV" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV"
    fi
    echo "Installing dependencies..."
    "$VENV/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
}

# ── macOS (launchd) ────────────────────────────────────────────────────────────

install_macos() {
    local plist="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$VENV/bin/python</string>
        <string>$SCRIPT_DIR/app.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StandardOutPath</key>
    <string>/tmp/$SERVICE_NAME.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$SERVICE_NAME.err</string>
</dict>
</plist>
EOF

    launchctl load "$plist"
    echo "Installed and started."
    echo "  Status : launchctl list | grep $LABEL"
    echo "  Logs   : /tmp/$SERVICE_NAME.log  /tmp/$SERVICE_NAME.err"
    echo "  Stop   : launchctl unload $plist"
}

uninstall_macos() {
    local plist="$HOME/Library/LaunchAgents/$LABEL.plist"
    if [ ! -f "$plist" ]; then
        echo "Service not found at $plist"
        exit 1
    fi
    launchctl unload "$plist" 2>/dev/null || true
    rm "$plist"
    echo "Uninstalled."
}

# ── Linux (systemd) ────────────────────────────────────────────────────────────

install_linux() {
    local service="/etc/systemd/system/$SERVICE_NAME.service"
    local run_user
    run_user="$(whoami)"

    # Write to tmp first so we can sudo-move it without a heredoc sudo issue
    cat > "/tmp/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Webcam LAN Streaming Website
After=network.target

[Service]
Type=simple
ExecStart=$VENV/bin/python $SCRIPT_DIR/app.py
WorkingDirectory=$SCRIPT_DIR
Restart=always
User=$run_user

[Install]
WantedBy=multi-user.target
EOF

    sudo mv "/tmp/$SERVICE_NAME.service" "$service"
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"
    echo "Installed and started."
    echo "  Status : sudo systemctl status $SERVICE_NAME"
    echo "  Logs   : journalctl -u $SERVICE_NAME -f"
    echo "  Stop   : sudo systemctl stop $SERVICE_NAME"
}

uninstall_linux() {
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^$SERVICE_NAME.service"; then
        echo "Service not found."
        exit 1
    fi
    sudo systemctl disable --now "$SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    sudo systemctl daemon-reload
    echo "Uninstalled."
}

# ── main ───────────────────────────────────────────────────────────────────────

UNINSTALL=false
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=true ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--uninstall]"; exit 1 ;;
    esac
done

OS="$(uname -s)"

if $UNINSTALL; then
    case "$OS" in
        Darwin) uninstall_macos ;;
        Linux)  uninstall_linux ;;
        *) echo "Unsupported OS: $OS"; exit 1 ;;
    esac
else
    setup_venv
    case "$OS" in
        Darwin) install_macos ;;
        Linux)  install_linux ;;
        *) echo "Unsupported OS: $OS"; exit 1 ;;
    esac
fi
