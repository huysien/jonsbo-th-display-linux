# jonsbo-th

Linux driver and control panel for the two-digit temperature display on **Jonsbo TH-series AIO coolers** (TH-240, TH-360). Jonsbo only ships Windows software. This project shows your CPU, GPU, SSD or motherboard temperature on the pump display under Ubuntu and other systemd-based distros.

> **Unofficial project.** It is not affiliated with, endorsed by, or supported by Jonsbo. See [Disclaimer](#disclaimer).

*[Tiếng Việt bên dưới](#tiếng-việt)*

![Architecture overview](docs/architecture-overview.svg)

## Features

- **Background service** (systemd user unit) that updates the display twice a second and reconnects after unplug or suspend.
- **Settings window** (GTK4 / libadwaita) with a live 7-segment preview of what the pump is showing.
- **Pick your sensors:** CPU (`k10temp`, `zenpower`, `coretemp`), GPU, NVMe/SSD, motherboard and others from `hwmon`.
- **Highest / average / lowest** of the selected sensors, plus an adjustable offset.
- **Top-bar icon** with the current temperature, using the GNOME *Ubuntu AppIndicators* extension, the same one Steam uses.
- Pure Python standard library + PyGObject. It needs no compiled code and no `hidapi`.

## Supported hardware

| Device | USB ID | Status |
|---|---|---|
| Jonsbo TH-240 | `5131:2007` | Tested by the author |
| Jonsbo TH-360 | `5131:2007` | Protocol from [htkhiem/jonsbo-th-linux](https://github.com/htkhiem/jonsbo-th-linux); not tested here |

Tried it on another model? Please report the result in an [issue](https://github.com/huysien/jonsbo-th-display-linux/issues).

The display identifies itself as a *"MSR-101U Mini HID magnetic card reader"* in `lsusb`. That is normal: the vendor reused a generic chip ID. Other products, such as some GameMax and ID-Cooling coolers and the Jonsbo D34 case, use the same ID **with different protocols**. Do not assume they are compatible.

## Install

### Debian / Ubuntu package

Download the `.deb` from [Releases](https://github.com/huysien/jonsbo-th-display-linux/releases), or build it yourself:

```sh
git clone https://github.com/huysien/jonsbo-th-display-linux.git
cd jonsbo-th-display-linux
./build-deb.sh
sudo apt install ./dist/jonsbo-th_*_all.deb
```

The package:
- installs a udev rule that gives the logged-in user access to the display;
- enables the background service and the top-bar icon for every user;
- adds **Jonsbo TH** to the application menu.

Remove it with `sudo apt remove jonsbo-th`. Settings in `~/.config/jonsbo-th/` are kept.

### Per-user install without a package

```sh
./install.sh             # asks for sudo once, only for the udev rule
./install.sh --uninstall
```

### Requirements

Python ≥ 3.10, `python3-gi`, `gir1.2-gtk-4.0` (≥ 4.14) and `gir1.2-adw-1` (≥ 1.5), all preinstalled on Ubuntu 24.04+. The top-bar icon also needs GNOME's **Ubuntu AppIndicators** extension (`ubuntu-appindicators@ubuntu.com`) or another StatusNotifierItem host.

## Usage

| Command | Purpose |
|---|---|
| `jonsbo-th-gui` | Settings window |
| `jonsbo-th-daemon --test 42` | Send `42` once to check the display responds |
| `systemctl --user status jonsbo-th` | Background service status |
| `systemctl --user status jonsbo-th-tray` | Top-bar icon status |

Configuration lives in `~/.config/jonsbo-th/config.json`. The GUI and the tray menu edit it, and the service reloads it automatically.

## How it works

The display is a USB HID device with 64-byte reports and no report ID. Every update is one write to `/dev/hidrawN`:

```
byte:  0    1    2    3     4 … 63
       01   02   00   <°C>  00 … 00
```

The display has two digits, so values are clamped to 0–99. This protocol was **reverse-engineered by the community**, not published by Jonsbo. Credit goes to [htkhiem/jonsbo-th-linux](https://github.com/htkhiem/jonsbo-th-linux) (GPL-3.0). This project is an independent Python implementation of the same protocol.

Architecture overview (Vietnamese, with diagrams): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Disclaimer

- **Not affiliated with Jonsbo.** "Jonsbo" and product names such as "TH-240" are trademarks of their respective owners. They are used here only to say which hardware this software works with.
- **Reverse-engineered protocol, use at your own risk.** The protocol is undocumented. Units and production batches may behave differently. Sending data to the device could cause it to malfunction, and in the worst case it could permanently damage the display. Using this software may affect your manufacturer warranty.
- **Not a safety or monitoring tool.** The number on the pump is for convenience only and may be stale, offset, or wrong, for example from sensor offsets such as AMD `Tctl`, a stopped service, or an unreadable sensor. Do not rely on it to protect your hardware. Use your BIOS/firmware thermal protection and proper monitoring tools.
- **No warranty.** This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**, without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. The authors are not liable for any damage to hardware, data loss, or other harm arising from its use. See sections 15–17 of the [GPL-3.0](LICENSE).

## License

Copyright © 2026 Huy Pham

This program is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License** as published by the Free Software Foundation, either **version 3** of the License, or (at your option) any later version. See [LICENSE](LICENSE).

---

## Tiếng Việt

Phần mềm cho Linux (Ubuntu) để hiển thị nhiệt độ lên màn hình 2 chữ số của tản nước **Jonsbo TH-240 / TH-360**. Hãng chỉ có phần mềm cho Windows.

**Tính năng:**
- Dịch vụ chạy nền.
- Cửa sổ cài đặt có mô phỏng màn hình tản.
- Chọn cảm biến (CPU, GPU, SSD, bo mạch chủ).
- Hiển thị nhiệt độ cao nhất, trung bình hoặc thấp nhất của các cảm biến đã chọn.
- Biểu tượng trên thanh trên cùng giống Steam.

**Cài đặt:** tải file `.deb` ở mục [Releases](https://github.com/huysien/jonsbo-th-display-linux/releases), hoặc tự build:

```sh
git clone https://github.com/huysien/jonsbo-th-display-linux.git
cd jonsbo-th-display-linux
./build-deb.sh && sudo apt install ./dist/jonsbo-th_*_all.deb
```

Gặp lỗi hoặc đã thử trên mẫu tản khác? Hãy mở [issue](https://github.com/huysien/jonsbo-th-display-linux/issues).

**Miễn trừ trách nhiệm:**
- Đây là dự án **không chính thức**, không liên quan, không được Jonsbo xác nhận hay hỗ trợ. "Jonsbo" và "TH-240" là nhãn hiệu của chủ sở hữu tương ứng, chỉ được nhắc tới để cho biết phần mềm dùng được với phần cứng nào.
- Giao thức USB được cộng đồng **tự dò ra (reverse-engineering)**, không có tài liệu chính thức. Mỗi lô sản xuất có thể khác nhau. Phần mềm có thể làm màn hình chạy sai hoặc **hỏng vĩnh viễn**, và có thể ảnh hưởng tới bảo hành. **Bạn tự chịu rủi ro khi sử dụng.**
- Con số trên tản chỉ để tham khảo. Nó có thể chậm, lệch hoặc sai, nên **không dùng nó để bảo vệ phần cứng**. Hãy dựa vào cơ chế bảo vệ nhiệt của BIOS và các công cụ giám sát chuyên dụng.
- Phần mềm được cung cấp **"nguyên trạng", KHÔNG CÓ BẤT KỲ BẢO ĐẢM NÀO**. Tác giả không chịu trách nhiệm về bất kỳ hư hỏng phần cứng, mất dữ liệu hay thiệt hại nào phát sinh (xem điều 15–17 của GPL-3.0).

**Giấy phép:** GNU GPL phiên bản 3 hoặc mới hơn (GPL-3.0-or-later). Xem [LICENSE](LICENSE).

Kiến trúc và sơ đồ hoạt động: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Cảm ơn [htkhiem/jonsbo-th-linux](https://github.com/htkhiem/jonsbo-th-linux) đã tìm ra giao thức.
