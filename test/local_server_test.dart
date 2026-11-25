// Regression tests for LocalServer's URL -> file mapping.
//
// Ported from Tilawa Pro's local_server_test.dart (TASMEE Phase 2,
// item 2.2). Written after the poc-12 phone failure: the engine never
// became ready (120 s timeout, no error) because the /ort/ branch built
// File('<dir>ort/...') — the '/' missing — so every WASM request 404'd
// while the disk-side check (ModelManager.ortWasmReady) passed. These
// tests fetch the files over HTTP exactly as the WebView does, so a
// broken mapping fails here instead of hanging a phone.
//
// NOTE: the asset routes (/ and /bundle.js) are NOT tested here — they go
// through rootBundle, and bundle.js is built in CI only (absent locally
// by design). The file routes below cover the bug.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_poc/local_server.dart';

Future<(int, String, HttpHeaders)> _get(LocalServer s, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('${s.baseUrl}${path.startsWith('/') ? path.substring(1) : path}'),
    );
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (res.statusCode, body, res.headers);
  } finally {
    client.close();
  }
}

/// Test-only mirror of the pre-flight check in
/// `WebViewEngine._checkServed` (lib/webview_engine.dart): fetch [url]
/// over HTTP and demand 200 + a non-empty body — or, when [expectedBytes]
/// is given, 200 + exactly that many bytes. A failure names the URL, the
/// expected size and the actual status/size, exactly like the production
/// check. Kept in the test because _checkServed is private to an engine
/// that needs a live WebViewController and cannot be called from a unit
/// test; the contract is what matters, and it is exercised here against
/// the real LocalServer, so a broken mapping fails here exactly as it
/// would fail the pre-flight on a phone.
class CheckFailed implements Exception {
  CheckFailed(this.message);
  final String message;
  @override
  String toString() => 'CheckFailed: $message';
}

Future<void> checkServed(String url, String label,
    {int? expectedBytes}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw CheckFailed(
          '$label غير متاح من الخادم المحلي — الرابط: $url — '
          'الحالة الفعلية: HTTP ${res.statusCode}'
          '${expectedBytes == null ? '' : ' (المتوقع: 200 وحجم $expectedBytes بايت)'}');
    }
    var bytes = 0;
    await for (final chunk in res) {
      bytes += chunk.length;
    }
    if (expectedBytes != null && bytes != expectedBytes) {
      throw CheckFailed(
          '$label وصل بحجم خاطئ من الخادم المحلي — الرابط: $url — '
          'المتوقع: $expectedBytes بايت، الفعلي: $bytes بايت');
    }
    if (bytes == 0) {
      throw CheckFailed('$label وصل فارغاً من الخادم المحلي — الرابط: $url');
    }
  } finally {
    client.close();
  }
}

void main() {
  late Directory dir;
  late LocalServer server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('poc-local-server-test-');
    await Directory('${dir.path}/ort/1.30.0').create(recursive: true);
    // JSEP pair (2026-11-26): onnxruntime-web 1.30.0 requests ONLY these
    // two files — the non-JSEP pair the old fixtures used is never
    // requested by the loader (0 occurrences in bundle.js).
    await File('${dir.path}/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm')
        .writeAsString('fake-jsep-wasm-bytes');
    await File('${dir.path}/ort/1.30.0/ort-wasm-simd-threaded.jsep.mjs')
        .writeAsString('fake-jsep-mjs-glue');
    await File('${dir.path}/model-lite.onnx').writeAsString('fake-model');
    await File('${dir.path}/model-full.onnx').writeAsString('fake-model-full');
    await File('${dir.path}/ref-v2.json').writeAsString('{"ayahs":[]}');
    server = await LocalServer.start(dir);
  });

  tearDown(() async {
    await server.stop();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('serves the JSEP runtime from /ort/<version>/ (the pro-build-28 404)',
      () async {
    final (status, body, headers) = await _get(
      server,
      '/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm',
    );
    expect(status, 200);
    expect(body, 'fake-jsep-wasm-bytes');
    expect(headers.value('cross-origin-opener-policy'), 'same-origin');
    expect(headers.value('content-type'), contains('application/wasm'));
    final (mjsStatus, mjsBody, mjsHeaders) = await _get(
      server,
      '/ort/1.30.0/ort-wasm-simd-threaded.jsep.mjs',
    );
    expect(mjsStatus, 200);
    expect(mjsBody, 'fake-jsep-mjs-glue');
    expect(mjsHeaders.value('content-type'), contains('text/javascript'));
  });

  test('missing JSEP file 404s (a missing runtime is a clean 404, not a hang)',
      () async {
    final (wasmStatus, _, _) = await _get(
      server,
      '/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm',
    );
    expect(wasmStatus, 200);
    await File('${dir.path}/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm')
        .delete();
    final (goneStatus, _, _) = await _get(
      server,
      '/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm',
    );
    expect(goneStatus, 404);
    // The .mjs is served independently of the .wasm.
    final (mjsStatus, _, _) = await _get(
      server,
      '/ort/1.30.0/ort-wasm-simd-threaded.jsep.mjs',
    );
    expect(mjsStatus, 200);
  });

  test('serves model + reference from /models/', () async {
    final (modelStatus, modelBody, _) =
        await _get(server, '/models/model-lite.onnx');
    expect(modelStatus, 200);
    expect(modelBody, 'fake-model');
    final (refStatus, refBody, _) = await _get(server, '/models/ref-v2.json');
    expect(refStatus, 200);
    expect(refBody, '{"ayahs":[]}');
  });

  test('unknown paths 404 (missing WASM file is a clean 404)', () async {
    final (status, _, _) =
        await _get(server, '/ort/1.30.0/does-not-exist.wasm');
    expect(status, 404);
    final (otherStatus, _, _) = await _get(server, '/no-such-route');
    expect(otherStatus, 404);
  });

  // --- 2026-11-26 404 fix: registry-path mapping + pre-flight contract ---

  test('registry path serves the flat full model (the 2026-11-26 404)',
      () async {
    final (status, body, _) = await _get(
      server,
      '/models/spliced-clean/1-int8/model.onnx',
    );
    expect(status, 200);
    expect(body, 'fake-model-full');
  });

  test('registry path serves the flat lite model', () async {
    final (status, body, _) = await _get(
      server,
      '/models/spliced-clean-lite/1-int8/model.onnx',
    );
    expect(status, 200);
    expect(body, 'fake-model');
  });

  test('flat model URLs serve the right tier file', () async {
    final (fullStatus, fullBody, _) =
        await _get(server, '/models/model-full.onnx');
    expect(fullStatus, 200);
    expect(fullBody, 'fake-model-full');
    final (liteStatus, liteBody, _) =
        await _get(server, '/models/model-lite.onnx');
    expect(liteStatus, 200);
    expect(liteBody, 'fake-model');
    // The two tiers must never be confused: the registry full path and
    // the flat full path serve the same bytes, distinct from lite.
    expect(fullBody, isNot(liteBody));
  });

  test('unknown /models/ paths 404 (never serve a wrong file)', () async {
    final (unknownRegistry, _, _) = await _get(
      server,
      '/models/some-other-model/1-int8/model.onnx',
    );
    expect(unknownRegistry, 404);
    final (unknownFlat, _, _) =
        await _get(server, '/models/model-unknown.onnx');
    expect(unknownFlat, 404);
    final (unknownVersion, _, _) = await _get(
      server,
      '/models/spliced-clean/2-int8/model.onnx',
    );
    expect(unknownVersion, 404);
  });

  group('pre-flight contract (mirrors WebViewEngine._checkServed)', () {
    test('passes on a correct server with the exact expected size',
        () async {
      await checkServed(
        '${server.baseUrl}models/spliced-clean/1-int8/model.onnx',
        'full model (registry path)',
        expectedBytes: 'fake-model-full'.length,
      );
      await checkServed(
        '${server.baseUrl}models/model-lite.onnx',
        'lite model (flat path)',
        expectedBytes: 'fake-model'.length,
      );
      await checkServed(
        '${server.baseUrl}models/ref-v2.json',
        'reference',
        expectedBytes: '{"ayahs":[]}'.length,
      );
    });

    // JSEP pre-flight contract (2026-11-26): the engine's pre-flight
    // demands HTTP 200 + the EXACT pinned size of EACH JSEP file — a
    // truncated .wasm must fail here, not inside loadWebModel. The
    // fixtures are fake bytes, so the contract is exercised with their
    // real lengths; the pinned sizes themselves are asserted in
    // test/jsep_contract_test.dart.
    test('passes for both JSEP files with their exact served size',
        () async {
      await checkServed(
        '${server.baseUrl}ort/1.30.0/ort-wasm-simd-threaded.jsep.mjs',
        'JSEP loader glue',
        expectedBytes: 'fake-jsep-mjs-glue'.length,
      );
      await checkServed(
        '${server.baseUrl}ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm',
        'JSEP WASM binary',
        expectedBytes: 'fake-jsep-wasm-bytes'.length,
      );
    });

    test('fails naming URL + expected/actual on a wrong JSEP size',
        () async {
      const url = 'ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm';
      try {
        await checkServed(
          '${server.baseUrl}$url',
          'JSEP WASM binary',
          expectedBytes: 999,
        );
        fail('expected checkServed to throw on a size mismatch');
      } on CheckFailed catch (e) {
        expect(e.message, contains(url));
        expect(e.message, contains('999'));
        expect(e.message,
            contains('${'fake-jsep-wasm-bytes'.length}'));
      }
    });

    test('fails naming URL + HTTP status on a missing JSEP file',
        () async {
      const url = 'ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm';
      await File('${dir.path}/ort/1.30.0/ort-wasm-simd-threaded.jsep.wasm')
          .delete();
      try {
        await checkServed(
          '${server.baseUrl}$url',
          'JSEP WASM binary',
          expectedBytes: 10,
        );
        fail('expected checkServed to throw on a 404');
      } on CheckFailed catch (e) {
        expect(e.message, contains(url));
        expect(e.message, contains('404'));
      }
    });

    test('fails naming URL + expected/actual on a wrong size', () async {
      const url = 'models/spliced-clean/1-int8/model.onnx';
      try {
        await checkServed(
          '${server.baseUrl}$url',
          'full model (registry path)',
          expectedBytes: 999,
        );
        fail('expected checkServed to throw on a size mismatch');
      } on CheckFailed catch (e) {
        expect(e.message, contains(url));
        expect(e.message, contains('999'));
        expect(e.message, contains('${'fake-model-full'.length}'));
      }
    });

    test('fails naming URL + HTTP status on a 404', () async {
      const url = 'models/does-not-exist.onnx';
      try {
        await checkServed(
          '${server.baseUrl}$url',
          'missing model',
          expectedBytes: 10,
        );
        fail('expected checkServed to throw on a 404');
      } on CheckFailed catch (e) {
        expect(e.message, contains(url));
        expect(e.message, contains('404'));
      }
    });

    test('fails on an empty body even without an expected size', () async {
      await File('${dir.path}/empty.onnx').writeAsString('');
      try {
        await checkServed('${server.baseUrl}models/empty.onnx', 'empty file');
        fail('expected checkServed to throw on an empty body');
      } on CheckFailed catch (e) {
        expect(e.message, contains('models/empty.onnx'));
      }
    });
  });
}
