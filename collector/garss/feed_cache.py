"""Optional HTTP response cache, separate from published article history."""
import base64
import gzip
import json
import logging
import os
import re
import tempfile
import time
import zlib
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path

LOGGER = logging.getLogger(__name__)
MAX_PAYLOAD_BYTES = 5 * 1024 * 1024
MAX_RECORD_BYTES = 7 * 1024 * 1024


@dataclass(frozen=True)
class CachedFeed:
    payload: bytes
    etag: str = ""
    last_modified: str = ""


def safe_validator(value):
    return value if isinstance(value, str) and len(value) <= 2048 and not any(ord(c) < 32 for c in value) else ""


class FeedCache:
    def __init__(self, directory: Path):
        self.directory = directory

    def _path(self, url):
        return self.directory / (sha256(url.encode("utf-8")).hexdigest() + ".json.gz")

    def get(self, url):
        path = self._path(url)
        try:
            if time.time() - path.stat().st_mtime > 30 * 86400:
                return None
            with gzip.open(path, "rb") as file:
                raw = file.read(MAX_RECORD_BYTES + 1)
            if len(raw) > MAX_RECORD_BYTES:
                return None
            record = json.loads(raw)
            if record["url"] != url or record["version"] != 1:
                return None
            payload = base64.b64decode(record["payload"], validate=True)
            if len(payload) > MAX_PAYLOAD_BYTES:
                return None
            return CachedFeed(payload, safe_validator(record.get("etag")), safe_validator(record.get("last_modified")))
        except (OSError, ValueError, KeyError, TypeError, EOFError, zlib.error, RecursionError):
            return None

    def touch(self, url):
        """Refresh a validated 304 body without recompressing and rewriting it."""
        try:
            os.utime(self._path(url), None)
        except OSError:
            LOGGER.warning("HTTP response cache refresh skipped")

    def discard(self, url):
        try:
            self._path(url).unlink(missing_ok=True)
        except OSError:
            LOGGER.warning("HTTP response cache invalidation skipped")

    def put(self, url, entry):
        temporary = None
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            record = {"version": 1, "url": url, "payload": base64.b64encode(entry.payload).decode("ascii"),
                      "etag": safe_validator(entry.etag), "last_modified": safe_validator(entry.last_modified)}
            with tempfile.NamedTemporaryFile(dir=self.directory, prefix=".feed-", delete=False) as file:
                temporary = Path(file.name)
                file.write(gzip.compress(json.dumps(record).encode("utf-8"), compresslevel=3, mtime=0))
            os.replace(temporary, self._path(url))
        except OSError:
            LOGGER.warning("HTTP response cache write failed; fetched articles remain available")
        finally:
            if temporary is not None:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    LOGGER.warning("HTTP cache temporary-file cleanup skipped")

    def prune(self, active_urls, max_bytes=64 * 1024 * 1024):
        """Remove only generated cache files; never recurse into directories."""
        active = {self._path(url).name for url in active_urls}
        try:
            if not self.directory.exists():
                return
            files = [p for p in self.directory.iterdir() if not p.is_symlink() and p.is_file()
                     and re.fullmatch(r"[0-9a-f]{64}\.json\.gz", p.name)]
            files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
            size = 0
            for path in files:
                stat = path.stat()
                if path.name not in active or time.time() - stat.st_mtime > 30 * 86400 or size + stat.st_size > max_bytes:
                    path.unlink()
                else:
                    size += stat.st_size
        except OSError:
            LOGGER.warning("HTTP response cache cleanup skipped")
