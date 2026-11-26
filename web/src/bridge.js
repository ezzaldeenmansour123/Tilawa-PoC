// WebView bridge: runs @tilawa/core/web inside the PoC WebView.
//
// Exposed to Dart as window.TilawaPoc:
//   init({assetBase, tier, modelUrl, referenceUrl, wasmPaths}) -> loads the
//     model + reference from the localhost server, reports capabilities.
//   startSession({mode, surah, fromAyah, toAyah})
//   stopSession()
//   dispose()
//
// Every engine event is forwarded to Dart through the `TilawaBridge`
// JavaScriptChannel as JSON:
//   {type:"ready", capabilities:{...}}
//   {type:"env-probe", probe:{...}} (posted BEFORE loadWebModel: the
//     pre-load environment — crossOriginIsolated, SharedArrayBuffer
//     typeof + live probe, navigator.gpu + requestAdapter result, the
//     provider list that will be tried, threads requested/applied, and
//     HTTP status of both JSEP files — so a failed load names its cause)
//   {type:"probe", result:"passed"} (the loader's warmup probe ran and
//     returned structurally valid output — explicit evidence, never
//     inferred from ready alone)
//   {type:"stage", stage:"load-onnx"|"create-session"} (load progress
//     inside init, so Dart can name the stage a hang or failure stopped
//     at instead of timing out on a generic "loading model")
//   {type:"position", event:{...}}   (position events, with timeMs audio clock)
//   {type:"checker", event:{...}}    (checker events, suspected/confirmed/...)
//   {type:"modelLoadMs", ms, backend}
//   {type:"error", message, reason}  (incl. MicrophoneError reasons:
//                                      denied | unavailable | insecure-context)
//
// Notes, from the upstream README (verified 2026-11-25):
// - `listen()` needs a secure context; the Dart localhost server provides it.
// - Default confirm policy is "next-word" (a mistake is confirmed once the
//   next word starts); the PoC keeps the upstream default (2.5 s delay is
//   the other option) so results are comparable with the upstream numbers.
// - minConfidence default is 0.6; the PoC keeps it and displays anything
//   below it as "uncertain" instead of a verdict.
// - The reference is loaded from the self-hosted ref-v2.json; the model from
//   the self-hosted .onnx file. Nothing is fetched from tilawa.dev at runtime.

import { createTilawa, loadWebModel } from '@tilawa/core/web';

function post(msg) {
  // webview_flutter JavaScriptChannel named "TilawaBridge".
  if (window.TilawaBridge) {
    window.TilawaBridge.postMessage(JSON.stringify(msg));
  } else {
    // Fallback for debugging the page in a desktop browser.
    console.log('[TilawaPoc]', JSON.stringify(msg));
  }
}

let tilawa = null;
let session = null;
let mic = null;

// JSEP file names onnxruntime-web 1.30.0 actually requests (hardcoded in
// lib/wasm/wasm-utils-import.ts:284, resolved against wasmPaths). The
// probe checks exactly these two files — the non-JSEP pair the app used
// to check is never requested by this build (0 occurrences in bundle.js).
const JSEP_FILES = [
  'ort-wasm-simd-threaded.jsep.mjs',
  'ort-wasm-simd-threaded.jsep.wasm',
];

// Provider list loadWebModel will use. DECISION 2026-11-26 (see
// ~/workspace/tilawa/JSEP_WASM_POC_IMPLEMENTATION_2026-11-26.md §1):
// keep the @tilawa/core default ["webgpu", "wasm"] — do NOT force
// ["wasm"]. A webgpu failure AFTER successful initializeWebAssembly does
// NOT poison the wasm attempt: initWasm's module-level `aborted` flag
// (proxy-wrapper.ts:81-92,156) is set only when initializeWebAssembly /
// initRuntime itself throws; once initialized, later initWasm calls
// return immediately, the per-backend-name abort cache
// (onnxruntime-common/lib/backend-impl.ts:74-101) is per name, and
// wasm's initEp has no JSEP/webgpu branch (wasm-core-impl.ts initEp
// calls initJsep only for 'webgpu'/'webnn'). The observed poisoning was
// a failure INSIDE initWasm (the missing .jsep.mjs import) — fixed by
// serving the JSEP pair, not by dropping WebGPU. WebGPU is therefore
// optional-by-design: tried first when navigator.gpu exists, wasm is
// the guaranteed fallback, and tasmee' must work with WebGPU absent.
// The bridge deliberately passes NO `providers` option, so the default
// above is what runs; the probe reports it so a failure log can say
// which order was in play.
const PROVIDERS = ['webgpu', 'wasm'];

// --- Early environment probe (2026-11-26 JSEP/WASM repair) -------------
// Runs BEFORE loadWebModel and posts {type:'env-probe', ...} to Dart, so
// a failed load names its cause (missing JSEP file? no SAB? no GPU
// adapter? not isolated?) instead of leaving Dart with one error string.
// Never blocks the load path when it succeeds (each sub-check is
// guarded with its own timeout; the JSEP fetches read headers only and
// cancel the body, so the 28 MB .wasm is never downloaded by the probe).
// If the probe itself fails, the failure is posted as the probe result
// and init() continues — a broken probe must never break a load.
function timeoutMs(ms, value) {
  return new Promise((resolve) => setTimeout(() => resolve(value), ms));
}

async function checkServedFile(url) {
  // Headers-only check: fetch resolves once headers arrive; cancel the
  // body immediately so a 28 MB file costs one round-trip, not a download.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const res = await fetch(url, { signal: controller.signal });
    const len = res.headers.get('content-length');
    try {
      if (res.body) await res.body.cancel();
    } catch (_) {
      /* body already consumed/closed — status + length are what matter */
    }
    return {
      status: res.status,
      contentLength: len === null ? null : Number(len),
    };
  } catch (e) {
    return {
      status: 0,
      error: e && e.name === 'AbortError'
        ? 'timeout'
        : (e && e.message ? e.message : String(e)),
    };
  } finally {
    clearTimeout(timer);
  }
}

async function probeEnvironment(opts) {
  const probe = {
    crossOriginIsolated: globalThis.crossOriginIsolated === true,
    sharedArrayBuffer: typeof SharedArrayBuffer,
    sabLive: false,
    webgpu: { inNavigator: false, available: false, adapter: 'skipped' },
    providers: PROVIDERS.slice(),
    jsep: {},
  };
  try {
    // Live SAB probe (same shape as ORT's isMultiThreadSupported,
    // wasm-factory.ts:13-38): construct one, post it through a
    // MessageChannel, AND validate a shared-memory WebAssembly module
    // (the third upstream step — added 2026-11-26 by the verifier so
    // the probe mirrors upstream exactly, as Pro's env_probe.js does).
    // `typeof SharedArrayBuffer` alone proves nothing — it can be
    // defined yet untransferable, or transferable yet unable to back
    // shared-memory WASM.
    if (typeof SharedArrayBuffer !== 'undefined') {
      try {
        const sab = new SharedArrayBuffer(1);
        const ch = new MessageChannel();
        try {
          probe.sabLive = await Promise.race([
            new Promise((resolve) => {
              ch.port1.onmessage = () => resolve(true);
              try {
                ch.port2.postMessage(sab);
              } catch (_) {
                resolve(false);
              }
            }),
            timeoutMs(1000, false),
          ]);
        } finally {
          // Close both ports: an open MessageChannel keeps a Node
          // process alive forever (it hung web/smoke-bundle.mjs — the
          // script printed its final line but never exited). In the
          // WebView the page lifetime makes this moot, but closing is
          // correct everywhere.
          try { ch.port1.close(); } catch (_) { /* best-effort */ }
          try { ch.port2.close(); } catch (_) { /* best-effort */ }
        }
        // Shared-memory WASM validation (wasm-factory.ts:31-35, same
        // probe bytes as Pro's env_probe.js). A SAB that posts fine
        // can still fail this step; sabLive must reflect all three.
        if (probe.sabLive) {
          try {
            probe.sabLive = WebAssembly.validate(
              new Uint8Array([
                0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 5, 4, 1, 3, 1, 1, 10, 11, 1, 9, 0, 65, 0, 254, 16,
                2, 0, 26, 11,
              ]),
            );
          } catch (_) {
            probe.sabLive = false;
          }
        }
      } catch (_) {
        probe.sabLive = false;
      }
    }
    // WebGPU: presence of navigator.gpu proves nothing about the
    // adapter — request one, guarded with a timeout so a hung
    // requestAdapter can never hang the load.
    try {
      const nav = globalThis.navigator;
      probe.webgpu.inNavigator = !!nav && 'gpu' in nav;
      probe.webgpu.available = !!nav && typeof nav.gpu !== 'undefined' && nav.gpu !== null;
      if (probe.webgpu.available) {
        const adapter = await Promise.race([
          nav.gpu.requestAdapter().then(
            (a) => (a ? 'ok' : 'null'),
            (e) => 'error:' + (e && e.message ? e.message : String(e)),
          ),
          timeoutMs(3000, 'timeout'),
        ]);
        probe.webgpu.adapter = adapter;
      }
    } catch (e) {
      probe.webgpu.adapter = 'error:' + (e && e.message ? e.message : String(e));
    }
    // JSEP files the loader will request, under the wasmPaths prefix.
    // Status only (headers + cancel) — never the full 28 MB body.
    if (opts && opts.wasmPaths) {
      const base = opts.wasmPaths.endsWith('/')
        ? opts.wasmPaths
        : opts.wasmPaths + '/';
      const checks = await Promise.all(
        JSEP_FILES.map((f) => checkServedFile(base + f)),
      );
      JSEP_FILES.forEach((f, i) => {
        probe.jsep[f] = checks[i];
      });
    } else {
      probe.jsep = 'not-checked (no wasmPaths)';
    }
  } catch (e) {
    probe.probeError = e && e.message ? e.message : String(e);
  }
  return probe;
}

window.TilawaPoc = {
  async init(opts) {
    const t0 = performance.now();
    try {
      // Load the reference + model from the localhost server (self-hosted).
      // loadWebModel({model, reference, wasmPaths}) is the documented
      // offline path; createTilawa with a loaded model does not hit the
      // network at all.
      const reference = await (await fetch(opts.referenceUrl)).json();
      // Threads (2026-11-26, corrected): onnxruntime-web 1.30.0 ships
      // ONLY threaded WASM builds (ort-wasm-simd-threaded.*); there is no
      // separate single-threaded build — @tilawa/core requires >= 1.19
      // (peerDependencies in its package.json), and 1.19+ dropped the
      // single-threaded files. The "single-thread path" is the SAME JSEP
      // files with numThreads = 1: @tilawa/core forces numThreads = 1
      // whenever the page is NOT cross-origin isolated
      // (dist/runtime/web.js:37), and onnxruntime-web itself warns and
      // falls back to 1 when multi-threading is unsupported
      // (lib/wasm/wasm-factory.ts:131-149). So requesting threads > 1
      // here is only a request — the loader clamps it to 1 when not
      // isolated, and either way it fetches the same JSEP pair. The
      // earlier poc-10 claim ("the page IS cross-origin isolated") was
      // never measured on-device; the env-probe below measures it.
      const threads = Math.max(2, Math.min(4, navigator.hardwareConcurrency || 4));
      // EARLY DIAGNOSTICS: probe the environment BEFORE loadWebModel and
      // post the result to Dart. If loadWebModel then fails, Dart already
      // holds the probe and the failure names its cause. The probe never
      // blocks the load: it is fully guarded/timeout-bounded, and if it
      // throws, the error is posted as the probe and init() continues.
      const probe = await probeEnvironment({ wasmPaths: opts.wasmPaths });
      // Threads actually applied by the loader (core forces 1 when not
      // isolated) — reported with the probe so the log states the real
      // thread count, not the requested one.
      probe.threadsRequested = threads;
      probe.threadsApplied = probe.crossOriginIsolated ? threads : 1;
      post({ type: 'env-probe', probe });
      // 2026-11-26 404 + tier fix: loadWebModel derives the tier ONLY
      // from its `tier` option (default "full") and IGNORES the `model`
      // URL entirely — the loader fetches `<registry base>/model.onnx`
      // from its bundled registry instead. The bridge used to pass only
      // `model: opts.modelUrl`, so a lite pick silently loaded the FULL
      // model (and 404'd on models/spliced-clean/1-int8/model.onnx
      // because the server had no such file). Pass the tier explicitly.
      // NOTE: no `providers` option is passed on purpose — the default
      // ["webgpu", "wasm"] (PROVIDERS above) is kept; see the decision
      // comment at the top of this file.
      post({ type: 'stage', stage: 'load-onnx' });
      const model = await loadWebModel({
        tier: opts.tier,
        model: opts.modelUrl,
        reference,
        wasmPaths: opts.wasmPaths,
        threads,
      });
      // loadWebModel resolves only after its internal warmup probe (a
      // real session run on zeroed, silence-shaped inputs, checking the
      // run returns structurally valid output) succeeds — report that
      // result EXPLICITLY: a silent probe is not evidence, and Dart must
      // not declare ready on a load whose probe never reported.
      post({ type: 'probe', result: 'passed' });
      post({ type: 'stage', stage: 'create-session' });
      tilawa = await createTilawa({ model, reference });
      // Reaching here means the model loaded AND probed successfully —
      // ready is never declared on a failed or unprobed load.
      // Report the model that was ACTUALLY loaded (from the loader's own
      // manifest), not the tier Dart asked for: if the bundle is stale
      // or the tier mismatched, Dart must see the truth and fail loudly
      // instead of showing a wrong "ready" card.
      const loadedId = (model && model.manifest && model.manifest.id) || null;
      const loadedTier = loadedId === 'spliced-clean-lite' ? 'lite'
        : loadedId === 'spliced-clean' ? 'full' : opts.tier;
      const ms = Math.round(performance.now() - t0);
      // The capabilities event arrives on the first session, but the PoC
      // also needs the backend + load time now: subscribe to a throwaway
      // probe session is NOT possible (a session is a take), so the backend
      // is reported from the first real session's capabilities event, and
      // the load time is reported here.
      post({ type: 'modelLoadMs', ms, backend: 'unknown-yet', crossOriginIsolated: globalThis.crossOriginIsolated, threads });
      // Report readiness: the capabilities payload comes with the first
      // session; here we report the model identity from the registry data
      // the bridge already knows (tier + urls), so Dart can show the card.
      post({
        type: 'ready',
        capabilities: {
          modelVersion: (loadedId || (opts.tier === 'lite'
            ? 'spliced-clean-lite'
            : 'spliced-clean')) + '@1-int8',
          modelRelease: '1',
          referenceVersion: reference.version || 'ref-v2',
          sdkVersion: '1.0.0-rc.1',
          modelSha256: 'verified-by-dart-before-load',
          tier: loadedTier,
          backend: 'unknown-yet',
          supported: ['wrong_word', 'omitted_word', 'added_word', 'skipped_passage'],
          unsupported: ['tajweed', 'pronunciation', 'hadr', 'children'],
        },
      });
    } catch (err) {
      // The error string alone cannot distinguish a missing JSEP file
      // from a missing SAB from a missing GPU adapter (the webgpu label
      // is attached to a provider-agnostic initWasm failure). Attach the
      // environment facts so Dart can name the cause; the env-probe
      // posted before loadWebModel carries the full detail.
      const ctx = [];
      try {
        ctx.push('crossOriginIsolated=' + globalThis.crossOriginIsolated);
        ctx.push('SharedArrayBuffer=' + typeof SharedArrayBuffer);
        ctx.push('gpuInNavigator=' + ('gpu' in globalThis.navigator));
        ctx.push('providers=' + PROVIDERS.join(','));
      } catch (_) {
        /* context is best-effort; the message below is what matters */
      }
      post({
        type: 'error',
        message: 'فشل تحميل النموذج: ' + (err && err.message ? err.message : String(err))
          + (ctx.length ? ' [' + ctx.join(' ') + ']' : ''),
        reason: err && err.reason ? err.reason : undefined,
      });
    }
  },

  // Exposed for testing (web/smoke-bundle.mjs) and for Dart-initiated
  // re-probes: runs the same pre-load environment probe init() runs,
  // without loading any model. Returns the probe object.
  probeEnvironment,

  startSession(opts) {
    if (!tilawa) {
      post({ type: 'error', message: 'المحرك غير محمّل بعد' });
      return;
    }
    const policy = { confirm: { after: 'next-word' } }; // upstream default
    if (opts.mode === 'memorization') {
      session = tilawa.startMemorization(
        { surah: opts.surah, fromAyah: opts.fromAyah, toAyah: opts.toAyah },
        policy,
      );
    } else {
      session = tilawa.startFreeRecitation(policy);
    }
    session.subscribe((e) => {
      if (e.type === 'capabilities') {
        // The real capabilities event: forward it so Dart replaces the
        // provisional card (notably the true `backend`: wasm/webgpu/cpu).
        post({ type: 'ready', capabilities: e });
      } else if (e.type === 'position' || e.type === 'checker') {
        post({ type: e.type, event: e });
      }
    });
    // Microphone -> session. Rejects with MicrophoneError on denial.
    // (2026-11-26) Two lessons from the phone tests:
    //   1. The error NAME matters: MicrophoneError carries the original
    //      DOMException as `cause`, and without its name ("NotReadableError"
    //      vs "NotAllowedError") Dart cannot tell a denied mic from a
    //      busy audio source. Post the name with the message.
    //   2. "unavailable" (e.g. NotReadableError — the audio source is
    //      busy or the driver hiccuped) is often transient: retry
    //      listen() ONCE after a short pause before reporting failure.
    const micErrorText = (err) => {
      const name = (err && err.cause && err.cause.name) || (err && err.name) || '';
      const msg = err && err.message ? err.message : String(err);
      return 'تعذّر فتح الميكروفون' + (name ? ' [' + name + ']' : '') + ': ' + msg;
    };
    const openMic = async () => {
      try {
        mic = await tilawa.listen(session);
      } catch (err) {
        if (err && err.reason === 'unavailable') {
          await new Promise((r) => setTimeout(r, 1500));
          mic = await tilawa.listen(session);
        } else {
          throw err;
        }
      }
    };
    openMic().catch((err) => {
      post({
        type: 'error',
        message: micErrorText(err),
        reason: err && err.reason ? err.reason : 'unavailable',
      });
    });
  },

  async stopSession() {
    try {
      if (mic) {
        await mic.stop();
        mic = null;
      }
    } catch (_) {
      /* stopping the mic is best-effort */
    }
    try {
      if (session) {
        await session.end();
        session = null;
      }
    } catch (_) {
      /* end() is idempotent; ignore */
    }
  },

  dispose() {
    if (tilawa) {
      tilawa.dispose();
      tilawa = null;
    }
  },
};
