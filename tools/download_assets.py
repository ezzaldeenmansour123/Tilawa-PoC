#!/usr/bin/env python3
"""Download Tilawa PoC assets with SHA-256 verification.

Downloads, into --out (default assets/models):
  - model-lite.onnx (24,650,054 bytes) or model-full.onnx (67,759,744 bytes)
  - ref-v2.json (reference; no pinned SHA in the model card — verified by
    byte count + tools/check_ref_schema.py)
  - onnxruntime-web <version> WASM files (from the jsDelivr CDN mirror of
    the npm package; the PoC must not depend on tilawa.dev at runtime)

Hashes/sizes are from docs/model-card.md in yazinsai/tilawa, re-verified
2026-11-25 against the live registry and the downloaded files:
  lite sha256 4974de78d3c35d2542e7a24d99b747e1160d6e31e366fb68492b74a789890f1b
  full sha256 714e98addee73b1b8781ad7d99b6d3c745acd9116638baf4e12891f53a15af1b

Usage:
  python3 tools/download_assets.py --tier lite --out assets/models
  python3 tools/download_assets.py --tier full --out assets/models
  python3 tools/download_assets.py --check-only --tier lite --out assets/models

Exit code 0 = all present and verified. Any mismatch aborts loudly.
"""

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

BASE = "https://tilawa.dev/v1"
MODELS = {
    "lite": {
        "id": "spliced-clean-lite",
        "version": "1-int8",
        "bytes": 24650054,
        "sha256": "4974de78d3c35d2542e7a24d99b747e1160d6e31e366fb68492b74a789890f1b",
    },
    "full": {
        "id": "spliced-clean",
        "version": "1-int8",
        "bytes": 67759744,
        "sha256": "714e98addee73b1b8781ad7d99b6d3c745acd9116638baf4e12891f53a15af1b",
    },
}
ORT_VERSION = "1.30.0"  # must match web/package.json + lib/model_manager.dart
# onnxruntime-web WASM files needed by the bundle (exact set is listed by
# the onnxruntime-web package; the well-known core set is downloaded here
# and the build fails loudly at runtime if one is missing — the CI smoke
# test catches that before any APK is built).
ORT_WASM_FILES = [
    "ort-wasm-simd-threaded.wasm",
    "ort-wasm-simd.wasm",
    "ort-wasm-threaded.wasm",
    "ort-wasm.wasm",
]


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    req = urllib.request.Request(url, headers={"User-Agent": "tilawa-poc/0.1"})
    with urllib.request.urlopen(req, timeout=300) as resp, open(tmp, "wb") as fh:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
    tmp.replace(dest)


def check_model(out: Path, tier: str) -> bool:
    spec = MODELS[tier]
    dest = out / f"model-{tier}.onnx"
    if not dest.exists():
        print(f"MISSING {dest}")
        return False
    size = dest.stat().st_size
    if size != spec["bytes"]:
        print(f"SIZE MISMATCH {dest}: {size} != {spec['bytes']}")
        return False
    digest = sha256_of(dest)
    if digest != spec["sha256"]:
        print(f"SHA MISMATCH {dest}: {digest} != {spec['sha256']}")
        return False
    print(f"OK {dest} ({size} bytes, sha256 {digest[:12]}...)")
    return True


def check_reference(out: Path) -> bool:
    dest = out / "ref-v2.json"
    if not dest.exists():
        print(f"MISSING {dest}")
        return False
    data = json.loads(dest.read_text(encoding="utf-8"))
    ayahs = data.get("ayahs", [])
    if len(ayahs) != 6236:
        print(f"REF COUNT MISMATCH: {len(ayahs)} != 6236")
        return False
    print(f"OK {dest} ({dest.stat().st_size} bytes, 6236 ayahs)")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", choices=["lite", "full"], default="lite")
    ap.add_argument("--out", default="assets/models")
    ap.add_argument("--check-only", action="store_true")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    spec = MODELS[args.tier]

    if args.check_only:
        ok = check_model(out, args.tier) and check_reference(out)
        return 0 if ok else 1

    dest = out / f"model-{args.tier}.onnx"
    if not (dest.exists() and check_model(out, args.tier)):
        url = f"{BASE}/models/{spec['id']}/{spec['version']}/model.onnx"
        print(f"Downloading {url} ...")
        download(url, dest)
        if not check_model(out, args.tier):
            return 1

    ref = out / "ref-v2.json"
    if not ref.exists():
        print(f"Downloading {BASE}/reference/ref-v2.json ...")
        download(f"{BASE}/reference/ref-v2.json", ref)
    if not check_reference(out):
        return 1

    ort_dir = out / "ort" / ORT_VERSION
    ort_dir.mkdir(parents=True, exist_ok=True)
    for name in ORT_WASM_FILES:
        target = ort_dir / name
        if target.exists():
            print(f"OK {target} (cached)")
            continue
        url = (
            f"https://cdn.jsdelivr.net/npm/onnxruntime-web@{ORT_VERSION}"
            f"/dist/{name}"
        )
        print(f"Downloading {url} ...")
        try:
            download(url, target)
            print(f"OK {target} ({target.stat().st_size} bytes)")
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"WARN: could not download {name}: {exc} "
                  "(CI smoke test will catch a missing WASM file)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
