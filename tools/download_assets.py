#!/usr/bin/env python3
"""Download Tilawa PoC assets with SHA-256 verification.

Downloads, into --out (default assets/models):
  - model-lite.onnx (24,650,054 bytes) or model-full.onnx (67,759,744 bytes)
  - manifest-lite.json / manifest-full.json (the per-model manifest;
    loadNodeModel(dir) reads dir/manifest.json, so the Node smoke test
    needs it next to the .onnx file)
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
        # Per-model manifest (models/<id>/<version>/manifest.json) — the
        # file loadNodeModel(dir) reads as dir/manifest.json, then loads
        # dir/<manifest.file>. Verified 2026-11-25 against the live
        # https://tilawa.dev/v1/manifest.json file list.
        "manifest_bytes": 8534,
        "manifest_sha256": "3f77f6368421a13ba8b0ca8e1610bd4a84ef3ac7407965d5c3cb9e322479cb30",
    },
    "full": {
        "id": "spliced-clean",
        "version": "1-int8",
        "bytes": 67759744,
        "sha256": "714e98addee73b1b8781ad7d99b6d3c745acd9116638baf4e12891f53a15af1b",
        "manifest_bytes": 11045,
        "manifest_sha256": "eb017b76cdca4261451ef5071acc637b57c5b62ed7ddb36f5daca1a2fc08d2b1",
    },
}
ORT_VERSION = "1.30.0"  # must match web/package.json + lib/model_manager.dart
# onnxruntime-web files needed by the bundle. VERIFIED 2026-11-26 against
# the jsDelivr source itself (downloaded from
# https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist/ and checked
# byte-identical against web/node_modules/onnxruntime-web/dist/): the
# 1.30.0 "all" build loads ONLY the JSEP pair — the filename is hardcoded
# in onnxruntime-web/lib/wasm/wasm-utils-import.ts:284 — and NEVER requests
# the non-JSEP pair (0 occurrences in assets/web/bundle.js). The non-JSEP
# pair was downloaded, verified and served for poc-9…pro-build-28 while
# the loader 404'd on the JSEP pair, so the JSEP pair REPLACES it here.
# Keep in sync with lib/model_manager.dart (kOrtWasmFiles/kOrtWasmAssets).
ORT_WASM_FILES = [
    "ort-wasm-simd-threaded.jsep.mjs",
    "ort-wasm-simd-threaded.jsep.wasm",
]
# Pinned JSEP identity (2026-11-26, jsDelivr-verified — see above).
ORT_WASM = {
    "ort-wasm-simd-threaded.jsep.mjs": {
        "bytes": 46851,
        "sha256": "709853412fd1ffc34247af1e73569227b5b79629c5ca3f59cc39cf7e500e4947",
    },
    "ort-wasm-simd-threaded.jsep.wasm": {
        "bytes": 28312028,
        "sha256": "3ad23231b5bd6d9dda55a7f84606315e0bf35b6750c28ee993c987c54cacab0f",
    },
}


def check_ort_file(path: Path, name: str) -> bool:
    """True only when the JSEP file exists with its pinned size + SHA-256."""
    spec = ORT_WASM[name]
    if not path.exists():
        print(f"MISSING {path}")
        return False
    size = path.stat().st_size
    if size != spec["bytes"]:
        print(f"SIZE MISMATCH {path}: {size} != {spec['bytes']}")
        return False
    digest = sha256_of(path)
    if digest != spec["sha256"]:
        print(f"SHA MISMATCH {path}: {digest} != {spec['sha256']}")
        return False
    print(f"OK {path} ({size} bytes, sha256 {digest[:12]}...)")
    return True


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


def check_manifest(out: Path, tier: str) -> bool:
    spec = MODELS[tier]
    dest = out / f"manifest-{tier}.json"
    if not dest.exists():
        print(f"MISSING {dest}")
        return False
    size = dest.stat().st_size
    if size != spec["manifest_bytes"]:
        print(f"SIZE MISMATCH {dest}: {size} != {spec['manifest_bytes']}")
        return False
    digest = sha256_of(dest)
    if digest != spec["manifest_sha256"]:
        print(f"SHA MISMATCH {dest}: {digest} != {spec['manifest_sha256']}")
        return False
    data = json.loads(dest.read_text(encoding="utf-8"))
    if data.get("file") != "model.onnx" or data.get("id") != spec["id"]:
        print(f"MANIFEST CONTENT MISMATCH {dest}: "
              f"id={data.get('id')} file={data.get('file')}")
        return False
    print(f"OK {dest} ({size} bytes, sha256 {digest[:12]}..., "
          f"id={data['id']}, file={data['file']})")
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
        ok = (check_model(out, args.tier)
              and check_manifest(out, args.tier)
              and check_reference(out))
        return 0 if ok else 1

    dest = out / f"model-{args.tier}.onnx"
    if not (dest.exists() and check_model(out, args.tier)):
        url = f"{BASE}/models/{spec['id']}/{spec['version']}/model.onnx"
        print(f"Downloading {url} ...")
        download(url, dest)
        if not check_model(out, args.tier):
            return 1

    manifest = out / f"manifest-{args.tier}.json"
    if not (manifest.exists() and check_manifest(out, args.tier)):
        url = f"{BASE}/models/{spec['id']}/{spec['version']}/manifest.json"
        print(f"Downloading {url} ...")
        download(url, manifest)
        if not check_manifest(out, args.tier):
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
        if target.exists() and check_ort_file(target, name):
            continue
        if target.exists():
            # Present but wrong size/SHA: never trust a stale file —
            # re-download it instead of reporting "cached".
            print(f"Re-downloading {target} (failed size/SHA check) ...")
        url = (
            f"https://cdn.jsdelivr.net/npm/onnxruntime-web@{ORT_VERSION}"
            f"/dist/{name}"
        )
        print(f"Downloading {url} ...")
        try:
            download(url, target)
            if not check_ort_file(target, name):
                return 1
        except Exception as exc:  # noqa: BLE001 - fail the build loudly
            # A missing WASM file MUST fail CI: the old WARN-only behaviour
            # let the poc-9 404 (ort-wasm-simd.wasm does not exist in
            # onnxruntime-web 1.30.0) slip through to the user's phone.
            print(f"ERROR: could not download {name}: {exc}")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
