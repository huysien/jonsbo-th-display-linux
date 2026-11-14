# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Huy Pham
"""Update check against GitHub Releases, and verified download of the .deb asset.

Network access happens only when the user asks for it (menu: "Check for updates…").
Nothing personal is sent: a plain GET to the public GitHub API with a generic User-Agent.
"""

import hashlib
import json
import os
import re
import urllib.error
import urllib.request

import jonsbo_th_common as jt

API_LATEST = f"https://api.github.com/repos/{jt.GITHUB_REPO}/releases/latest"
USER_AGENT = f"jonsbo-th/{jt.VERSION} (update check)"
TIMEOUT = 15
DEB_INSTALL_DIR = "/usr/lib/jonsbo-th"
ALLOWED_DOWNLOAD_HOSTS = ("https://github.com/", "https://objects.githubusercontent.com/",
                          "https://release-assets.githubusercontent.com/")


class UpdateError(Exception):
    pass


class Release:
    def __init__(self, version, tag, page_url, notes, deb_url, deb_name, deb_sha256):
        self.version, self.tag, self.page_url, self.notes = version, tag, page_url, notes
        self.deb_url, self.deb_name, self.deb_sha256 = deb_url, deb_name, deb_sha256


def parse_version(text):
    """'v1.2.3' / '1.2.3' -> (1, 2, 3); None if it is not a plain dotted version."""
    m = re.fullmatch(r"v?(\d+(?:\.\d+)*)", (text or "").strip())
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def is_newer(candidate, current=jt.VERSION):
    a, b = parse_version(candidate), parse_version(current)
    if a is None or b is None:
        return False
    n = max(len(a), len(b))
    return a + (0,) * (n - len(a)) > b + (0,) * (n - len(b))


def installed_from_deb():
    return os.path.realpath(__file__).startswith(DEB_INSTALL_DIR + "/")


def parse_release(data):
    tag = data.get("tag_name") or ""
    version = tag[1:] if tag.startswith("v") else tag
    deb_url = deb_name = deb_sha = None
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        if re.fullmatch(r"jonsbo-th_[\w.+~-]+_all\.deb", name):
            deb_url, deb_name = asset.get("browser_download_url"), name
            digest = asset.get("digest") or ""
            deb_sha = digest[7:].lower() if digest.startswith("sha256:") else None
            break
    return Release(version, tag, data.get("html_url") or jt.HOMEPAGE + "/releases",
                   (data.get("body") or "").strip(), deb_url, deb_name, deb_sha)


def plain_notes(markdown, max_lines=8):
    """Turn GitHub release notes (Markdown) into a few plain-text lines for a dialog."""
    lines = []
    for line in markdown.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "Full Changelog" in line:
            continue
        line = re.sub(r"\*\*|__|`", "", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)        # [text](url) -> text
        line = re.sub(r" by @[\w-]+ in https?://\S+$", "", line)       # generated-notes suffix
        line = re.sub(r"^[*-]\s+", "• ", line)
        lines.append(line)
    if len(lines) > max_lines:
        lines = lines[:max_lines] + ["…"]
    return "\n".join(lines)


def fetch_latest():
    """Latest published release, or None if the project has no release yet."""
    req = urllib.request.Request(API_LATEST, headers={
        "Accept": "application/vnd.github+json", "User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code == 403:
            raise UpdateError("GitHub rate limit reached, try again later.") from e
        raise UpdateError(f"GitHub returned HTTP {e.code}.") from e
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        reason = getattr(e, "reason", e)
        raise UpdateError(f"Cannot reach GitHub: {reason}") from e
    except ValueError as e:
        raise UpdateError("Unexpected response from GitHub.") from e
    return parse_release(data)


def download_deb(release, dest_dir=None):
    """Download the release's .deb, verify its SHA-256 if GitHub published one. Returns the path."""
    if not release.deb_url:
        raise UpdateError("This release has no .deb package attached.")
    if not release.deb_url.startswith(ALLOWED_DOWNLOAD_HOSTS):
        raise UpdateError("Refusing to download from an unexpected address.")
    dest_dir = dest_dir or os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), jt.APP_NAME)
    os.makedirs(dest_dir, exist_ok=True)
    path = os.path.join(dest_dir, os.path.basename(release.deb_name))
    tmp = path + ".part"
    sha = hashlib.sha256()
    req = urllib.request.Request(release.deb_url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp, open(tmp, "wb") as f:
            while chunk := resp.read(65536):
                sha.update(chunk)
                f.write(chunk)
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise UpdateError(f"Download failed: {getattr(e, 'reason', e)}") from e
    if release.deb_sha256 and sha.hexdigest() != release.deb_sha256:
        os.unlink(tmp)
        raise UpdateError("Downloaded file does not match the published checksum.")
    os.replace(tmp, path)
    os.chmod(path, 0o644)  # apt's sandbox user must be able to read it
    return path


def install_command(deb_path):
    """Command that installs the package with a graphical password prompt (polkit)."""
    return ["pkexec", "/usr/bin/apt-get", "install", "-y", deb_path]
