#!/usr/bin/env python3
"""Verify ref-v2.json schema: the source of passage text in the PoC UI.

Verified schema (inspected 2026-11-25 from the live file):
  top keys: version, text, profile, inventory, ayahs
  ayahs: list of 6236, each {"s": surah, "a": ayah,
                             "w": [display words, Uthmani, with diacritics],
                             "p": phoneme string, "o": offsets, "iso": [...]}
  profile.rewaya == "hafs"

The PoC UI reads passage words from ayahs[].w — the engine's own
reference, never text typed from memory. If this script fails, the
build must fail: the UI text source is not what the code expects.

Usage: python3 tools/check_ref_schema.py [path/to/ref-v2.json]
"""

import json
import sys
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/models/ref-v2.json")
    if not path.exists():
        print(f"MISSING {path}")
        return 1
    data = json.loads(path.read_text(encoding="utf-8"))
    errors = []
    if data.get("version") != "ref-v2":
        errors.append(f"version={data.get('version')!r} (expected 'ref-v2')")
    if (data.get("profile") or {}).get("rewaya") != "hafs":
        errors.append("profile.rewaya is not 'hafs'")
    ayahs = data.get("ayahs")
    if not isinstance(ayahs, list) or len(ayahs) != 6236:
        errors.append(f"ayahs count={len(ayahs) if isinstance(ayahs, list) else 'not-a-list'}")
        print("\n".join(errors))
        return 1
    for i, a in enumerate(ayahs):
        w = a.get("w")
        if not isinstance(w, list) or not w or not all(
            isinstance(x, str) and x for x in w
        ):
            errors.append(f"ayah index {i} (s={a.get('s')} a={a.get('a')}): bad 'w'")
            if len(errors) > 5:
                break
    # Spot checks on known structure (counts only — never assert text content
    # from memory; the reference itself is the authority).
    first = ayahs[0]
    if (first.get("s"), first.get("a")) != (1, 1):
        errors.append("first ayah is not 1:1")
    if len(first.get("w", [])) != 4:
        errors.append(f"1:1 has {len(first.get('w', []))} words, expected 4")
    last = ayahs[-1]
    if (last.get("s"), last.get("a")) != (114, 6):
        errors.append(f"last ayah is {last.get('s')}:{last.get('a')}, expected 114:6")
    if errors:
        print("REF SCHEMA FAILED:")
        print("\n".join(errors))
        return 1
    print(f"OK {path}: ref-v2, hafs, 6236 ayahs, all with non-empty word lists")
    return 0


if __name__ == "__main__":
    sys.exit(main())
