# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Huy Pham
"""Shared code for the Jonsbo TH display daemon and GUI: sensors, config, status, USB packet."""

import glob
import json
import os
import tempfile
import time

VERSION = "1.0.0"
HOMEPAGE = "https://github.com/huysien/jonsbo-th-display-linux"

VID, PID = 0x5131, 0x2007
PACKET_SIZE = 64

MODES = ("max", "avg", "min")

APP_NAME = "jonsbo-th"
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), APP_NAME)
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
RUNTIME_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir(), APP_NAME)
STATUS_PATH = os.path.join(RUNTIME_DIR, "status.json")

# hwmon driver name -> (category key, label prefix)
DRIVER_INFO = {
    "k10temp": ("cpu", "CPU"),
    "zenpower": ("cpu", "CPU"),
    "coretemp": ("cpu", "CPU"),
    "amdgpu": ("gpu", "GPU"),
    "nouveau": ("gpu", "GPU"),
    "radeon": ("gpu", "GPU"),
    "i915": ("gpu", "GPU"),
    "xe": ("gpu", "GPU"),
    "nvme": ("disk", "SSD"),
    "drivetemp": ("disk", "Ổ cứng"),
    "gigabyte_wmi": ("board", "Bo mạch chủ"),
    "asus_wmi_sensors": ("board", "Bo mạch chủ"),
    "acpitz": ("other", "ACPI"),
}
CATEGORIES = [("cpu", "CPU"), ("gpu", "GPU"), ("disk", "Ổ cứng"), ("board", "Bo mạch chủ"), ("other", "Khác")]

# Sensors selected when there is no config yet: first match wins.
DEFAULT_SENSORS = ["k10temp/Tctl", "zenpower/Tdie", "coretemp/Package id 0"]

DEFAULT_CONFIG = {"sensors": None, "mode": "max", "offset": 0, "interval": 0.5, "tray_label": True}


# ---------------------------------------------------------------- sensors

class Sensor:
    __slots__ = ("id", "name", "category", "path")

    def __init__(self, id, name, category, path):
        self.id, self.name, self.category, self.path = id, name, category, path

    def read(self):
        """Temperature in °C, or None if unreadable."""
        try:
            with open(self.path) as f:
                return int(f.read().strip()) / 1000.0
        except (OSError, ValueError):
            return None


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def list_sensors():
    """All hwmon temperature inputs. IDs are 'driver[#n]/label' so they survive hwmonN renumbering."""
    sensors = []
    seen = {}
    for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*"), key=lambda p: int(p.rsplit("hwmon", 1)[1])):
        driver = _read(os.path.join(hw, "name"))
        if not driver:
            continue
        seen[driver] = seen.get(driver, 0) + 1
        dev_key = driver if seen[driver] == 1 else f"{driver}#{seen[driver]}"
        category, prefix = DRIVER_INFO.get(driver) or (
            ("other", "Card mạng") if driver.startswith(("r8169", "igc", "e1000e", "iwlwifi", "mt7921")) else ("other", driver))
        if seen[driver] > 1:
            prefix = f"{prefix} {seen[driver]}"
        inputs = sorted(glob.glob(os.path.join(hw, "temp*_input")),
                        key=lambda p: int(os.path.basename(p)[4:-6]))
        for inp in inputs:
            chan = os.path.basename(inp)[:-6]  # "temp1"
            label = _read(inp[:-6] + "_label") or chan
            sensors.append(Sensor(f"{dev_key}/{label}", f"{prefix} · {label}", category, inp))
    return sensors


def default_sensor_ids(sensors):
    ids = {s.id for s in sensors}
    for cand in DEFAULT_SENSORS:
        if cand in ids:
            return [cand]
    cpu = [s.id for s in sensors if s.category == "cpu"]
    return cpu[:1] or [s.id for s in sensors[:1]]


def aggregate(values, mode):
    values = [v for v in values if v is not None]
    if not values:
        return None
    if mode == "min":
        return min(values)
    if mode == "avg":
        return sum(values) / len(values)
    return max(values)


def compute(config, sensors):
    """Returns (value_to_show or None, {sensor_id: reading})."""
    readings = {s.id: s.read() for s in sensors}
    chosen = config["sensors"] if config["sensors"] is not None else default_sensor_ids(sensors)
    value = aggregate([readings.get(i) for i in chosen], config["mode"])
    if value is not None:
        value += config["offset"]
    return value, readings


def display_digits(value):
    """What the 2-digit display actually shows."""
    return max(0, min(99, int(round(value))))


# ---------------------------------------------------------------- config / status files

def _atomic_write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH) as f:
            data = json.load(f)
        if isinstance(data, dict):
            cfg.update({k: v for k, v in data.items() if k in DEFAULT_CONFIG})
    except (OSError, ValueError):
        pass
    if cfg["mode"] not in MODES:
        cfg["mode"] = "max"
    cfg["tray_label"] = bool(cfg["tray_label"])
    if cfg["sensors"] is not None and not isinstance(cfg["sensors"], list):
        cfg["sensors"] = None
    try:
        cfg["offset"] = float(cfg["offset"])
    except (TypeError, ValueError):
        cfg["offset"] = 0.0
    try:
        cfg["interval"] = min(10.0, max(0.2, float(cfg["interval"])))
    except (TypeError, ValueError):
        cfg["interval"] = 0.5
    return cfg


def config_mtime():
    try:
        return os.stat(CONFIG_PATH).st_mtime_ns
    except OSError:
        return None


def save_config(cfg):
    _atomic_write_json(CONFIG_PATH, cfg)


def write_status(status):
    status["time"] = time.time()
    status["pid"] = os.getpid()
    _atomic_write_json(STATUS_PATH, status)


def read_status(max_age=3.0):
    """Daemon status dict if the daemon wrote it recently, else None."""
    try:
        with open(STATUS_PATH) as f:
            st = json.load(f)
    except (OSError, ValueError):
        return None
    if time.time() - st.get("time", 0) > max_age:
        return None
    return st


# ---------------------------------------------------------------- device

def find_hidraw():
    want = f"{VID:08X}:{PID:08X}"
    for node in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = _read(os.path.join(node, "device/uevent")) or ""
        for line in uevent.splitlines():
            if line.startswith("HID_ID=") and line.upper().endswith(want):
                return "/dev/" + os.path.basename(node)
    return None


def make_packet(value):
    """64-byte report: 01 02 00 <°C> 00... (descriptor has no report ID, so byte 0 goes on the wire)."""
    buf = bytearray(PACKET_SIZE)
    buf[0] = 0x01
    buf[1] = 0x02
    buf[3] = display_digits(value)
    return bytes(buf)
