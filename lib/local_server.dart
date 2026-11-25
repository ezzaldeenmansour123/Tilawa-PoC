// Localhost server that gives the WebView a SECURE CONTEXT.
//
// Why: `tilawa.listen()` needs a secure context (https or localhost).
// Files loaded from Flutter assets (`loadFlutterAsset`) are NOT a secure
// context, so `getUserMedia` would reject with MicrophoneError
// ("insecure-context"). Serving the same files from http://127.0.0.1:<port>/
// IS a secure context (localhost is a potentially trustworthy origin).
//
// The server binds 127.0.0.1 only (never 0.0.0.0), serves only the PoC web
// directory + the downloaded model files, and stops with the engine.
// No audio ever goes through this server — the microphone goes straight
// from the WebView's getUserMedia into the engine.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class LocalServer {
  LocalServer._(this._server, this._modelDir);
  final HttpServer _server;
  final Directory _modelDir;

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port/';

  static Future<LocalServer> start(Directory modelDir) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = LocalServer._(server, modelDir);
    server.listen(s._handle);
    return s;
  }

  Future<void> stop() => _server.close(force: true);

  static const _mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.wasm': 'application/wasm',
    '.onnx': 'application/octet-stream',
    '.css': 'text/css; charset=utf-8',
  };

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/' || path == '/tilawa.html') {
        await _serveAsset(req, 'assets/web/tilawa.html');
      } else if (path == '/bundle.js') {
        await _serveAsset(req, 'assets/web/bundle.js');
      } else if (path.startsWith('/models/')) {
        await _serveFile(req, File('${_modelDir.path}/${path.substring(8)}'));
      } else if (path.startsWith('/ort/')) {
        // onnxruntime-web WASM files, downloaded by tools/download_assets.py
        // into <modelDir>/ort/<version>/.
        await _serveFile(req, File('${_modelDir.path}${path.substring(1)}'));
      } else {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('not found');
        await req.response.close();
      }
    } catch (e) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('server error: $e');
      await req.response.close();
    }
  }

  Future<void> _serveAsset(HttpRequest req, String asset) async {
    final data = await rootBundle.load(asset);
    final ext = asset.substring(asset.lastIndexOf('.'));
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    req.response.headers.add('Cache-Control', 'no-store');
    // COOP/COEP are NOT set: Android WebView has no SharedArrayBuffer, so
    // cross-origin isolation is impossible here — WASM runs single-threaded.
    // (This is a measured PoC limitation, not a bug: see docs/MEASUREMENT_PLAN.md.)
    req.response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    await req.response.close();
  }

  Future<void> _serveFile(HttpRequest req, File file) async {
    if (!await file.exists()) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('model file not found');
      await req.response.close();
      return;
    }
    final ext = file.path.substring(file.path.lastIndexOf('.'));
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    req.response.headers.add('Cache-Control', 'no-store');
    req.response.headers.contentLength = await file.length();
    await req.response.addStream(file.openRead());
    await req.response.close();
  }
}
