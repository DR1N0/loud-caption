"""Fetch the pinned Vosk model archives used by the Android offline MVP."""

from pathlib import Path
from urllib.request import urlopen
import hashlib
import os

BASE = "https://alphacephei.com/vosk/models/"
MODELS = {
    "vosk-model-small-en-us-0.15.zip": "09ab50ccd62b674cbaa231b825f9c1cb",
    "vosk-model-small-cn-0.22.zip": "d1a8e82933dcc7632667c036b0bb3dbb",
}


def matches_md5(data: bytes, expected: str) -> bool:
    """Return whether data matches the pinned catalog MD5 digest."""
    return hashlib.md5(data).hexdigest() == expected


def _file_md5(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str, expected: str) -> None:
    """Download a pinned archive, verify it, and atomically publish it."""
    dest = Path("assets/models") / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and _file_md5(dest) == expected:
        return

    part = dest.with_name(name + ".part")
    digest = hashlib.md5()
    try:
        with urlopen(BASE + name, timeout=120) as response, part.open("wb") as out:
            for block in iter(lambda: response.read(1024 * 1024), b""):
                out.write(block)
                digest.update(block)
        if digest.hexdigest() != expected:
            raise ValueError(f"checksum mismatch: {name}")
        os.replace(part, dest)
    finally:
        part.unlink(missing_ok=True)


if __name__ == "__main__":
    for filename, md5 in MODELS.items():
        fetch(filename, md5)
