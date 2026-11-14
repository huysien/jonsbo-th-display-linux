#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Huy Pham
# Install for the current user:   ./install.sh          (asks for sudo once, for the udev rule)
# Uninstall:                      ./install.sh --uninstall
set -e
cd "$(dirname "$0")"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user (not with sudo); the script calls sudo itself when needed." >&2
    exit 1
fi

PREFIX="$HOME/.local/share/jonsbo-th"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/jonsbo-th.service"
TRAY_UNIT="$UNIT_DIR/jonsbo-th-tray.service"
EXT=ubuntu-appindicators@ubuntu.com
DESKTOP="$HOME/.local/share/applications/io.github.jonsbo_th.Control.desktop"
ICON="$HOME/.local/share/icons/hicolor/scalable/apps/io.github.jonsbo_th.Control.svg"
RULE=/etc/udev/rules.d/60-jonsbo-th-display.rules
OLD_UNIT=/etc/systemd/system/jonsbo-th-display.service

if [ "$1" != "--uninstall" ] && dpkg -s jonsbo-th >/dev/null 2>&1; then
    echo "jonsbo-th is already installed from the .deb package; no need for this script." >&2
    exit 1
fi

if [ "$1" = "--uninstall" ]; then
    systemctl --user disable --now jonsbo-th.service jonsbo-th-tray.service 2>/dev/null || true
    rm -rf "$PREFIX" "$UNIT" "$TRAY_UNIT" "$DESKTOP" "$ICON"
    systemctl --user daemon-reload
    if [ -e "$RULE" ]; then sudo rm -f "$RULE" && sudo udevadm control --reload-rules; fi
    echo "Uninstalled (settings kept in ~/.config/jonsbo-th)."
    exit 0
fi

# 1. Program files
mkdir -p "$PREFIX" "$UNIT_DIR" "$(dirname "$DESKTOP")" "$(dirname "$ICON")"
install -m 0644 jonsbo_th_common.py jonsbo_th_update.py "$PREFIX/"
install -m 0755 jonsbo-th-daemon jonsbo-th-gui jonsbo-th-tray "$PREFIX/"
mkdir -p "$PREFIX/icons"
install -m 0644 icons/jonsbo-th-tray-symbolic.svg "$PREFIX/icons/"
install -m 0644 jonsbo-th.svg "$ICON"

# 2. Permission to write to the display: plugdev group + the logged-in desktop user.
RULE_TEXT='SUBSYSTEM=="hidraw", ATTRS{idVendor}=="5131", ATTRS{idProduct}=="2007", GROUP="plugdev", MODE="0660", TAG+="uaccess"'
if [ "$(cat "$RULE" 2>/dev/null)" != "$RULE_TEXT" ]; then
    echo "Installing udev rule (needs sudo)..."
    echo "$RULE_TEXT" | sudo tee "$RULE" >/dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=hidraw --action=change
fi

# Remove the system-wide service from the earlier version, if present.
if [ -e "$OLD_UNIT" ]; then
    sudo systemctl disable --now jonsbo-th-display.service || true
    sudo rm -f "$OLD_UNIT" /usr/local/bin/jonsbo-th-display
    sudo systemctl daemon-reload
fi

# 3. Background service (runs while you are logged in)
cat > "$UNIT" <<EOF
[Unit]
Description=Jonsbo TH AIO temperature display

[Service]
ExecStart=/usr/bin/python3 $PREFIX/jonsbo-th-daemon
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

# 4. Top-bar icon (needs GNOME's "Ubuntu AppIndicators" extension, shipped with Ubuntu)
cat > "$TRAY_UNIT" <<EOF
[Unit]
Description=Jonsbo TH top-bar icon
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 $PREFIX/jonsbo-th-tray
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

if command -v gnome-extensions >/dev/null && gnome-extensions info "$EXT" >/dev/null 2>&1; then
    if ! gnome-extensions info "$EXT" | grep -q "Enabled: Yes"; then
        echo "Enabling the Ubuntu AppIndicators extension (needed for top-bar icons)..."
        gnome-extensions enable "$EXT" || true
    fi
else
    echo "Note: GNOME extension $EXT not found; install gnome-shell-extension-appindicator for the top-bar icon."
fi

# 5. App launcher
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Jonsbo TH
Comment=Temperature display for Jonsbo TH AIO coolers
Comment[vi]=Màn hình nhiệt độ tản nước Jonsbo TH
Exec=/usr/bin/python3 $PREFIX/jonsbo-th-gui
Icon=io.github.jonsbo_th.Control
Categories=System;Monitor;
EOF

systemctl --user daemon-reload
systemctl --user enable jonsbo-th.service jonsbo-th-tray.service
systemctl --user restart jonsbo-th.service jonsbo-th-tray.service
sleep 1.5
systemctl --user --no-pager status jonsbo-th.service | head -n 8
echo
echo "Done. Open \"Jonsbo TH\" from the app menu."
