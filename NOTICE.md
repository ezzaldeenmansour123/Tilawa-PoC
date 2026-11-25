# Notices — Tilawa PoC

This PoC redistributes and uses the following third-party works. The
conditions below are quoted from the upstream sources as read on
2026-11-25 (yazinsai/tilawa, commit `a021377`, crawled 2026-11-25 02:45 UTC;
model card `docs/model-card.md`; `NOTICE.md`). If any upstream text
changes, this file must be updated before any release.

## 1. yazinsai/tilawa — engine code: MIT

> "This repository's code is MIT-licensed (`LICENSE`)."
> "The engine … is … released here under this repository's MIT licence."

The PoC uses `@tilawa/core` `1.0.0-rc.1` unmodified (npm). The MIT licence
text ships in the package (`node_modules/@tilawa/core/LICENSE`) and must be
included in any redistribution of the PoC that includes the engine code.

## 2. yazinsai/tilawa — listener model weights 1.x: CC BY 4.0

From `docs/model-card.md` ("Licence" section), verbatim:

> "The model weights are released under CC BY 4.0. Credit "Tilawa
> (tilawa.dev)" and the sources above when you redistribute them."
> "The SDK code is MIT."

From `NOTICE.md`, verbatim:

> "The `spliced-clean` and `spliced-clean-lite` weights themselves are
> released under **CC BY 4.0** (see `docs/model-card.md`)."

CC BY 4.0 permits commercial use; its material condition is
**attribution on redistribution**. The PoC therefore credits, in-app
(About/model screen) and in this file:

- **Tilawa (tilawa.dev)** — the listener model (`spliced-clean@1-int8`,
  `spliced-clean-lite@1-int8`).
- **tlog** (Tarteel, CC-BY) and **Quranic Universal Ayahs / QUD alignment
  benchmark** (QUD Technologies, CC-BY) — training and evaluation audio.
- **muaalem** (`obadx/muaalem-model-v3_2`, MIT) — the teacher model and its
  phoneme inventory.
- **quran-transcript** (`obadx/quran-transcript`, MIT) — phonemization.
- **k2-fsa icefall** (Apache-2.0) — architecture, recipe and ONNX export.
- **Tanzil** (tanzil.net) — the Uthmani Quran text: reproduced verbatim,
  with Tanzil credited as its source and a link to tanzil.net.
- **ONNX Runtime** (Microsoft, MIT) — inference (peer dependency).

Caveat recorded verbatim from the model card:

> "Some sources carry no licence tag. They were used for training at the
> project's own risk."

The training-data licence chain is therefore not 100% complete. This is a
documented residual risk, not a blocker for a free, non-commercial,
attribution-carrying PoC — but it must be re-checked before any production
release.

## 3. What is EXCLUDED — 0.x / Quran-Lab assets: NPL-1.2 (non-commercial)

From `NOTICE.md` ("Licensing of 0.x model artefacts"), verbatim:

> "These artefacts are **NPL-1.2 Derivatives** of Quran-Lab's Work. …
> NPL-1.2 §§3/5/9: you may not charge for the Work or any feature it
> powers; hosted use is free or cost recovery only. Every Derivative must
> be distributed under NPL-1.2 (or a later Quran-Lab version)."

The 0.x models (`zipformer_*`, `interp-gentle-a0.5`, `a0w-ep1-a0.5`), the
251-token vocabulary and the phoneme lexicon are **NOT used anywhere in
this PoC**. Only 1.x (`spliced-clean*`) is downloaded, verified by SHA-256
against the 1.x registry, and loaded. Any switch to a 0.x / Quran-Lab
asset flips this PoC to BLOCKED.

## 4. Conditions that apply to any future integration

From the audit (§6.1), all still binding:

1. 1.x only; 2. the feature stays completely free (no price, subscription
   or ads on it); 3. attribution as in §2 above, with the MIT notice and
   this NOTICE.md; 4. SHA-256 verification of the model files; 5. model +
   reference bundled/self-hosted locally (never loaded from tilawa.dev at
   runtime); 6. described as a memorization assistant only (tracking +
   memorization mistakes), with the limits stated: no tajweed/pronunciation,
   Hafs only, adults mainly, warnings may be false, preview release;
   7. audio on-device only; 8. PoC + on-device measurement before any
   commitment; 9. any paid feature, ads, or switch to a Quran-Lab/0.x
   asset = BLOCKED immediately.
