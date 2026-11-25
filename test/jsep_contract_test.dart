// Contract tests for the JSEP runtime pins (2026-11-26 JSEP/WASM repair).
//
// The 1.30.0 "all" build loads ONLY the JSEP pair — the filenames are
// hardcoded in onnxruntime-web/lib/wasm/wasm-utils-import.ts:284 — and
// the loader 404'd on pro-build-28 while every gate checked the
// non-JSEP pair instead. These tests pin the contract in one place:
// the Dart download/status lists (lib/model_manager.dart) must name
// exactly the two JSEP files, with the sizes + SHA-256 verified against
// the jsDelivr source itself (downloaded 2026-11-26 from
// https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist/ and checked
// byte-identical against web/node_modules/onnxruntime-web/dist/).
// tools/download_assets.py carries the same pins — keep both lists in
// sync; if jsDelivr ever serves different bytes for 1.30.0, this test
// (not a phone) is where it must fail.
//
// No WebView, no network, no disk I/O: pure constant assertions.

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_poc/model_manager.dart';

void main() {
  test('kOrtWasmFiles names exactly the JSEP pair (nothing else)', () {
    expect(kOrtWasmFiles, [
      'ort-wasm-simd-threaded.jsep.mjs',
      'ort-wasm-simd-threaded.jsep.wasm',
    ]);
    // The non-JSEP pair must NOT be listed: the 1.30.0 loader never
    // requests it (0 occurrences in assets/web/bundle.js), so listing
    // it would re-introduce the pro-build-28 failure mode — gates
    // passing while the loader 404s.
    expect(kOrtWasmFiles, isNot(contains('ort-wasm-simd-threaded.mjs')));
    expect(kOrtWasmFiles, isNot(contains('ort-wasm-simd-threaded.wasm')));
  });

  test('kOrtWasmAssets pins the jsDelivr-verified JSEP sizes + SHA-256',
      () {
    expect(kOrtWasmAssets.length, 2);
    final byName = {for (final a in kOrtWasmAssets) a.name: a};
    final mjs = byName['ort-wasm-simd-threaded.jsep.mjs']!;
    expect(mjs.bytes, 46851);
    expect(mjs.sha256,
        '709853412fd1ffc34247af1e73569227b5b79629c5ca3f59cc39cf7e500e4947');
    final wasm = byName['ort-wasm-simd-threaded.jsep.wasm']!;
    expect(wasm.bytes, 28312028);
    expect(wasm.sha256,
        '3ad23231b5bd6d9dda55a7f84606315e0bf35b6750c28ee993c987c54cacab0f');
  });

  test('kOrtWasmTotalBytes is the JSEP pair total (~28.4 MB)', () {
    expect(kOrtWasmTotalBytes, 46851 + 28312028);
    expect(kOrtWasmTotalBytes, 28358879);
  });

  test('ORT version matches the web bundle (1.30.0)', () {
    expect(kOrtWebVersion, '1.30.0');
    expect(kOrtBaseUrl,
        'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist');
  });
}
