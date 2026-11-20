"""Adapted from Azeroth Accord (tools/fetch_libs.py), same owner, GPL-3.0.

Downloads the libraries pinned in .pkgmeta into FinlandDragonCreditPoints/Libs/ for local development and CI.

.pkgmeta is the single source of truth: every entry under `externals:` is a GitHub repository at a tag, extracted
whole into the folder named by the entry. Releases use the BigWigs packager, which reads the same file.
Usage: python -I -X utf8 tools/fetch_libs.py [--force]
"""
import io
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKGMETA = os.path.join(ROOT, ".pkgmeta")
GITHUB = re.compile(r"^https://github\.com/([\w.-]+/[\w.-]+?)(?:\.git)?/?$")


def parse_externals(text):
    """Returns {path: (url, tag)} from the `externals:` block (a deliberately tiny YAML subset)."""
    result, in_block, path = {}, False, None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line.startswith(" "):
            in_block = line.strip() == "externals:"
            path = None
            continue
        if not in_block:
            continue
        m = re.match(r"^\s{2}(\S.*):$", line)
        if m:
            path = m.group(1).strip()
            result[path] = {}
            continue
        m = re.match(r"^\s{4}(url|tag):\s*(\S+)$", line)
        if m and path:
            result[path][m.group(1)] = m.group(2)
    out = {}
    for p, v in result.items():
        if "url" not in v or "tag" not in v:
            raise ValueError(f".pkgmeta external {p!r} needs both url and tag")
        out[p] = (v["url"], v["tag"])
    return out


RETRY_STATUS = (429, 500, 502, 503, 504)
ATTEMPTS = 5
BACKOFF = 2.0  # seconds before the second attempt, doubled after each failure


def fetch_bytes(zip_url, attempts=ATTEMPTS, backoff=BACKOFF, opener=None, sleep=time.sleep):
    """Reads a URL, retrying with exponential backoff on 429, 5xx and network errors (shared CI runners get rate limited)."""
    opener = opener or (lambda u: urllib.request.urlopen(u, timeout=60))
    for attempt in range(1, attempts + 1):
        try:
            with opener(zip_url) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code not in RETRY_STATUS or attempt == attempts:
                raise
            wait = backoff * 2 ** (attempt - 1)
            retry_after = e.headers.get("Retry-After") if e.headers else None
            if retry_after and retry_after.isdigit():
                wait = max(wait, min(int(retry_after), 60))
            reason = f"HTTP {e.code}"
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt == attempts:
                raise
            wait = backoff * 2 ** (attempt - 1)
            reason = str(e)
        print(f"  {reason}, retrying in {wait:g}s (attempt {attempt}/{attempts})")
        sleep(wait)


def download(url, tag, target):
    m = GITHUB.match(url)
    if not m:
        raise ValueError(f"only github.com URLs are supported: {url}")
    zip_url = f"https://codeload.github.com/{m.group(1)}/zip/refs/tags/{tag}"
    data = fetch_bytes(zip_url)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        top = z.namelist()[0].split("/", 1)[0] + "/"
        for name in z.namelist():
            rel = name[len(top):] if name.startswith(top) else name
            if not rel or rel.endswith("/"):
                continue
            dest = os.path.normpath(os.path.join(target, rel))
            if not dest.startswith(os.path.normpath(target) + os.sep):
                raise ValueError(f"unsafe path in archive: {name}")
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(name) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)


def main():
    force = "--force" in sys.argv
    with open(PKGMETA, encoding="utf-8") as f:
        externals = parse_externals(f.read())
    if not externals:
        print("No externals found in .pkgmeta.")
        return 1
    for path, (url, tag) in externals.items():
        target = os.path.join(ROOT, *path.split("/"))
        stamp = os.path.join(target, ".fetched")
        wanted = f"{url} {tag}"
        if not force and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == wanted:
            print(f"{path}: {tag} already present")
            continue
        if os.path.isdir(target):
            shutil.rmtree(target)
        print(f"{path}: fetching {tag} from {url}")
        download(url, tag, target)
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(wanted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
