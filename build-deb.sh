#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Huy Pham
# Build a .deb package:   ./build-deb.sh        -> dist/jonsbo-th_<version>_all.deb
set -e
umask 022
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^VERSION = "\(.*\)"$/\1/p' jonsbo_th_common.py)
[ -n "$VERSION" ] || { echo "VERSION not found in jonsbo_th_common.py" >&2; exit 1; }
PKG=jonsbo-th
MAINTAINER="${DEBFULLNAME:-Huy Pham} <${DEBEMAIL:-10974153+huysien@users.noreply.github.com}>"

BUILD=build/deb
rm -rf "$BUILD"
LIB=/usr/lib/$PKG

d() { mkdir -p "$BUILD$1"; }

# ---- program files
d "$LIB/icons"
install -m 0644 jonsbo_th_common.py "$BUILD$LIB/"
install -m 0755 jonsbo-th-daemon jonsbo-th-gui jonsbo-th-tray "$BUILD$LIB/"
install -m 0644 icons/jonsbo-th-tray-symbolic.svg "$BUILD$LIB/icons/"

d /usr/bin
for p in jonsbo-th-daemon jonsbo-th-gui jonsbo-th-tray; do
    ln -s "$LIB/$p" "$BUILD/usr/bin/$p"
done

# ---- desktop integration
d /usr/share/applications
cat > "$BUILD/usr/share/applications/io.github.jonsbo_th.Control.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Jonsbo TH
Comment=Màn hình nhiệt độ tản nước Jonsbo TH
Exec=jonsbo-th-gui
Icon=io.github.jonsbo_th.Control
Categories=System;Monitor;
Keywords=jonsbo;aio;cooler;temperature;nhiệt độ;tản;
EOF
d /usr/share/icons/hicolor/scalable/apps
install -m 0644 jonsbo-th.svg "$BUILD/usr/share/icons/hicolor/scalable/apps/io.github.jonsbo_th.Control.svg"

# ---- device permission: the logged-in desktop user (uaccess) and the plugdev group
d /usr/lib/udev/rules.d
cat > "$BUILD/usr/lib/udev/rules.d/60-jonsbo-th.rules" <<'EOF'
# Jonsbo TH-series AIO temperature display (enumerates as a "Mini HID magnetic card reader")
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="5131", ATTRS{idProduct}=="2007", GROUP="plugdev", MODE="0660", TAG+="uaccess"
EOF

# ---- systemd user services (enabled for every user by postinst)
d /usr/lib/systemd/user
cat > "$BUILD/usr/lib/systemd/user/jonsbo-th.service" <<EOF
[Unit]
Description=Jonsbo TH AIO temperature display

[Service]
ExecStart=/usr/bin/python3 $LIB/jonsbo-th-daemon
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
cat > "$BUILD/usr/lib/systemd/user/jonsbo-th-tray.service" <<EOF
[Unit]
Description=Jonsbo TH top-bar icon
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 $LIB/jonsbo-th-tray
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# ---- docs
d /usr/share/doc/$PKG
cat > "$BUILD/usr/share/doc/$PKG/README" <<'EOF'
Jonsbo TH — hiển thị nhiệt độ lên màn hình tản nước Jonsbo TH-series (USB 5131:2007) trên Ubuntu.

  jonsbo-th-gui            cửa sổ cài đặt (menu ứng dụng: "Jonsbo TH")
  jonsbo-th-daemon         dịch vụ nền  (systemctl --user status jonsbo-th)
  jonsbo-th-tray           biểu tượng thanh trên cùng (systemctl --user status jonsbo-th-tray)
  jonsbo-th-daemon --test 42   gửi thử số 42 lên màn hình

Cấu hình: ~/.config/jonsbo-th/config.json
Biểu tượng cần phần mở rộng GNOME "Ubuntu AppIndicators" (ubuntu-appindicators@ubuntu.com).
EOF

# Debian machine-readable copyright file
cat > "$BUILD/usr/share/doc/$PKG/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: jonsbo-th
Source: https://github.com/huysien/jonsbo-th-display-linux
Comment: Unofficial; not affiliated with or endorsed by Jonsbo. "Jonsbo" and
 product names are trademarks of their respective owners. The USB protocol
 is community reverse-engineered (credit: htkhiem/jonsbo-th-linux) and use is
 at your own risk.

Files: *
Copyright: 2026 Huy Pham
License: GPL-3.0+

License: GPL-3.0+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 .
 On Debian systems, the complete text of the GNU General Public
 License version 3 can be found in "/usr/share/common-licenses/GPL-3".
EOF

# ---- maintainer scripts
d /DEBIAN
SIZE=$(du -sk --exclude=DEBIAN "$BUILD" | cut -f1)
cat > "$BUILD/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
Installed-Size: $SIZE
Depends: python3 (>= 3.10), python3-gi, gir1.2-gtk-4.0 (>= 4.14), gir1.2-adw-1 (>= 1.5), systemd, udev
Recommends: gnome-shell-ubuntu-extensions | gnome-shell-extension-appindicator
Section: utils
Homepage: https://github.com/huysien/jonsbo-th-display-linux
Priority: optional
Description: Temperature display driver for Jonsbo TH-series AIO coolers
 Sends the CPU (or GPU/SSD/board) temperature to the two-digit display on
 Jonsbo TH-240/TH-360 AIO pumps (USB 5131:2007) on Linux. Includes a
 background service, a GTK4 settings window with a live display preview,
 and a top-bar icon. Choose highest, average or lowest of selected sensors.
EOF

cat > "$BUILD/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
UNITS="jonsbo-th.service jonsbo-th-tray.service"
if [ "$1" = "configure" ]; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=hidraw --action=change 2>/dev/null || true
    systemctl --global enable $UNITS >/dev/null 2>&1 || true
    # Start (or restart after an upgrade) for users who are logged in right now.
    for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
        user=$(id -nu "$uid" 2>/dev/null) || continue
        systemctl --user -M "$user@" daemon-reload >/dev/null 2>&1 || continue
        for u in $UNITS; do
            if [ "$(systemctl --user -M "$user@" is-enabled "$u" 2>/dev/null)" = "enabled" ]; then
                systemctl --user -M "$user@" restart "$u" >/dev/null 2>&1 || true
            fi
        done
    done
    gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true
    update-desktop-database -q 2>/dev/null || true
fi
exit 0
EOF

cat > "$BUILD/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
UNITS="jonsbo-th.service jonsbo-th-tray.service"
if [ "$1" = "remove" ]; then
    for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
        user=$(id -nu "$uid" 2>/dev/null) || continue
        systemctl --user -M "$user@" stop $UNITS >/dev/null 2>&1 || true
    done
    systemctl --global disable $UNITS >/dev/null 2>&1 || true
fi
exit 0
EOF

cat > "$BUILD/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    udevadm control --reload-rules 2>/dev/null || true
    gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true
    update-desktop-database -q 2>/dev/null || true
fi
exit 0
EOF
chmod 0755 "$BUILD/DEBIAN/postinst" "$BUILD/DEBIAN/prerm" "$BUILD/DEBIAN/postrm"

find "$BUILD" -name __pycache__ -prune -exec rm -rf {} +
mkdir -p dist
OUT="dist/${PKG}_${VERSION}_all.deb"
dpkg-deb --root-owner-group -Zxz --build "$BUILD" "$OUT" >/dev/null
echo "Built $OUT"
