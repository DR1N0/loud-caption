"""Fetch the pinned sherpa-onnx SenseVoice + Silero VAD model files."""

from pathlib import Path
from urllib.request import urlopen
import hashlib
import os
import tarfile

BASE = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
SENSE_VOICE_ARCHIVE = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
MODELS = {
    SENSE_VOICE_ARCHIVE: "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e",
    "silero_vad.onnx": "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6",
}

# The SenseVoice archive itself is not a bundled asset; only the two files
# extracted from it are. It is downloaded into a scratch cache directory
# rather than under assets/models/.
CACHE_DIR = Path("build_cache")

SENSE_VOICE_DEST = Path("assets/models/sense-voice")
SENSE_VOICE_MEMBERS = {"model.int8.onnx", "tokens.txt"}
SILERO_VAD_DEST = Path("assets/models/silero-vad/silero_vad.onnx")


def matches_sha256(data: bytes, expected: str) -> bool:
    """Return whether data matches the pinned catalog SHA-256 digest."""
    return hashlib.sha256(data).hexdigest() == expected


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str, expected: str, dest: Path) -> None:
    """Download a pinned file, verify it, and atomically publish it to dest."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and _file_sha256(dest) == expected:
        return

    part = dest.with_name(dest.name + ".part")
    digest = hashlib.sha256()
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


def extract_sense_voice(archive_path: Path) -> None:
    """Extract model.int8.onnx and tokens.txt from the SenseVoice tarball."""
    remaining = set(SENSE_VOICE_MEMBERS)
    SENSE_VOICE_DEST.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:bz2") as tar:
        for member in tar:
            basename = Path(member.name).name
            if basename not in remaining:
                continue
            extracted = tar.extractfile(member)
            if extracted is None:
                continue
            dest = SENSE_VOICE_DEST / basename
            part = dest.with_name(dest.name + ".part")
            with extracted as source, part.open("wb") as out:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    out.write(block)
            os.replace(part, dest)
            remaining.discard(basename)
            if not remaining:
                break
    if remaining:
        missing = ", ".join(sorted(remaining))
        raise ValueError(f"archive missing expected members: {missing}")


if __name__ == "__main__":
    archive_path = CACHE_DIR / SENSE_VOICE_ARCHIVE
    fetch(SENSE_VOICE_ARCHIVE, MODELS[SENSE_VOICE_ARCHIVE], archive_path)
    extract_sense_voice(archive_path)

    fetch("silero_vad.onnx", MODELS["silero_vad.onnx"], SILERO_VAD_DEST)
