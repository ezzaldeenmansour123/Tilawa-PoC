# قائمة ملفات الرفع — مستودع Tilawa-PoC المنفصل

**التاريخ:** 2026-11-25 — **المصدر المحلي:** `~/workspace/tilawa-poc/`
**المستودع الهدف:** `github.com/ezzaldeenmansour123/Tilawa-PoC` (عام، جديد، فارغ)
**عدد الملفات:** 29 ملفاً بالضبط — لا أكثر ولا أقل. لا تُرفع أي ملفات أخرى
(لا `assets/models/`، لا `assets/web/bundle.js`، لا `node_modules/`، لا
`__pycache__`، لا ملفات `.apk`، لا `pubspec.lock` إن وُلد محلياً بالخطأ —
كلها مخرجات بناء تُبنى في CI).

> تحذير: هذه القائمة مرجع للوكيل الرئيسي (المتصفح) فقط. الوكيل العام
> (مُعدّ هذه القائمة) لا يستطيع إنشاء مستودع ولا الدفع إلى GitHub.

## 1. الملفات الـ29 (بالمسار الكامل كما تُرفع)

| # | المسار في المستودع | الوظيفة |
|---|---|---|
| 1 | `.gitignore` | يستثني مخرجات البناء؛ **لا** يستثني `web/package-lock.json` (يُثبَّت بعد أول بناء أخضر) |
| 2 | `.github/workflows/poc.yml` | CI: تشغيل يدوي فقط — `node-smoke` ثم بناء APK arm64 ثم إصدار `poc-N` |
| 3 | `README.md` | نظرة عامة + خطوات البناء + المعايير + ما لم يُختبَر |
| 4 | `NOTICE.md` | النِّسَب والتراخيص (MIT + CC BY 4.0) |
| 5 | `pubspec.yaml` | `tilawa_poc` 0.1.0 — الحزم بنطاقات واسعة تُثبَّت من أول بناء أخضر |
| 6 | `lib/main.dart` | نقطة الدخول — 3 تبويبات (التسميع / النموذج / السجلات) |
| 7 | `lib/speech_engine.dart` | الواجهة المجردة `SpeechEngine` + `ModelInfo` |
| 8 | `lib/models.dart` | `RefWord`، حالات التتبع، فئات الأخطاء، حالات الفاحص |
| 9 | `lib/webview_engine.dart` | محوّل WebView: الجسر JS↔Dart + ترجمة الأحداث + السجل |
| 10 | `lib/local_server.dart` | خادم localhost (`127.0.0.1` فقط) — السياق الآمن للميكروفون |
| 11 | `lib/model_manager.dart` | تنزيل lite/full + `ref-v2.json` + **ملفات WASM الأربعة** مع تحقق SHA-256 |
| 12 | `lib/event_log.dart` | سجل JSONL لكل جلسة + حساب زمن التظليل (وسيط/P90) |
| 13 | `lib/screens/recitation_screen.dart` | التسميع: المقاطع الأربعة المعلنة، التظليل، الثقة، «غير متأكد» |
| 14 | `lib/screens/model_screen.dart` | بطاقة النموذج: الحالة/التنزيل/البصمة/حجم WASM |
| 15 | `lib/screens/logs_screen.dart` | قائمة السجلات + الملخص + التصدير المحلي |
| 16 | `web/package.json` | `@tilawa/core@1.0.0-rc.1` + `onnxruntime-web@1.30.0` + `esbuild` |
| 17 | `web/build.mjs` | بناء الحزمة بـ esbuild إلى `assets/web/bundle.js` |
| 18 | `web/src/bridge.js` | جسر `@tilawa/core/web` (تهيئة/جلسات/إعادة الأحداث إلى Dart) |
| 19 | `assets/web/tilawa.html` | صفحة WebView (الواجهة في Flutter؛ WebView مضيف للمحرك فقط) |
| 20 | `tools/download_assets.py` | تنزيل الأصول مع تحقق SHA-256 (+ `--check-only`) |
| 21 | `tools/check_ref_schema.py` | يتحقق أن `ref-v2.json` فيه 6236 آية وأن كل آية فيها كلمات `w` |
| 22 | `tools/score_sessions.py` | الدقة/الالتقاط/الإنذارات الكاذبة/زمن التظليل/تأخير التأكيد من JSONL |
| 23 | `test/event_log_test.dart` | اختبارات Dart للمنطق النقي — تُشغَّل في CI |
| 24 | `test_data/README.md` | شرح البيانات التركيبية + النتائج المتوقعة من أداة التقييم |
| 25 | `test_data/session_example.jsonl` | جلسة تركيبية (لاختبار أداة التقييم فقط — ليست نتائج) |
| 26 | `test_data/ground_truth_example.json` | حقيقة أرضية تركيبية مقابلة (3 أخطاء مزروعة) |
| 27 | `docs/MEASUREMENT_PLAN.md` | خطة القياس الكاملة (التعريفات + العتبات الـ 14 + المصفوفة) |
| 28 | `docs/PHONE_TEST_PROTOCOL.md` | بروتوكول اختبار الهاتف خطوة بخطوة (30 جلسة، S22 Ultra) |
| 29 | `docs/COMPARISON.md` | مقارنة البدائل + التوصية الأولية |
| — | `UPLOAD_MANIFEST.md` (هذا الملف) | قائمة الرفع — تُرفع مع الملفات الـ29 (ملف 30 في المستودع) |
| — | `BUILD_READINESS.md` | تقرير الجاهزية — يُرفع مع الملفات الـ29 (ملف 31 في المستودع) |

## 2. تعليمات حرفية للوكيل الرئيسي (المتصفح) — بالترتيب

### الخطوة 1 — إنشاء المستودع (مرة واحدة)

1. افتح GitHub بالحساب `ezzaldeenmansour123`.
2. أنشئ مستودعاً **عاماً (Public)** جديداً باسم **`Tilawa-PoC`** بالضبط.
3. **بلا README ولا ترخيص ولا .gitignore** عند الإنشاء (مستودع فارغ تماماً) —
   كل هذه الملفات تأتي من المشروع المحلي.
4. الوصف المقترح (اختياري): `Tilawa PoC — offline Quran recitation follower experiment (yazinsai/tilawa WebView). Standalone experiment, NOT the Tilawa app.`
5. تحقق: المستودع الجديد فارغ، وعنوانه
   `https://github.com/ezzaldeenmansour123/Tilawa-PoC`.

### الخطوة 2 — رفع الملفات الـ29 (+ هذا الملف + BUILD_READINESS.md)

1. ارفع الملفات الـ29 المذكورة أعلاه **فقط**، بمساراتها نفسها، إلى الفرع
   `main` في مستودع `Tilawa-PoC`.
2. لا ترفع أي ملف آخر من `~/workspace/tilawa-poc/` (تأكد خصوصاً من غياب:
   `assets/models/`، `assets/web/bundle.js`، `web/node_modules/`،
   `__pycache__`، أي ملف `.apk`، أي ملف `.onnx` أو `.wasm`).
3. لا تدفع أي شيء إلى مستودع `Tilawa` أو `Tilawa-Pro` أو أي مستودع آخر.
4. بعد الرفع، تحقق من العدد: **31 ملفاً** في جذر المستودع وفروعه
   (29 + `UPLOAD_MANIFEST.md` + `BUILD_READINESS.md`)، ومن وجود
   `.github/workflows/poc.yml` في مكانه.
5. تحقق سريعاً من أن `pubspec.yaml` و`web/package.json` و`lib/model_manager.dart`
   (وفيه إصلاح WASM — انظر BUILD_READINESS.md) موجودة كما هي محلياً.

### الخطوة 3 — تشغيل poc.yml يدوياً (طبقة lite أولاً)

1. في مستودع `Tilawa-PoC` على GitHub: **Actions** ← سير العمل
   **«Build Tilawa PoC APK»** ← **Run workflow**.
2. اختر الطبقة **`lite`** (الخيار الافتراضي — أولاً حتماً، لا `full`).
3. اضغط **Run workflow** وانتظر.
4. راقب المهمة الأولى **`node-smoke`**:
   - إن **نجحت**، تابع إلى مهمة `build` تلقائياً.
   - إن **فشلت**، أوقف هنا: لا يُبنى APK، ودوّن سبب الفشل نصاً من سجل
     المهمة (هذا هو الغرض من البوابة)، وأبلغ المستخدم قبل أي إعادة محاولة.
5. راقب مهمة **`build`**: حزمة الويب → تنزيل الأصول مع تحقق SHA-256 →
   `flutter analyze` → `flutter test` → بناء APK (arm64 فقط).
6. بعد نجاح المهمة الأولى، **ثبّت الإصدارات**: سيتولد `web/package-lock.json`
   و`pubspec.lock` في CI أثناء البناء — نزّلهما وثبّتهما (commit) في
   مستودع Tilawa-PoC (هذا ما ينص عليه `poc.yml`: «The first green build
   MUST commit the generated lock file»)، ليكون البناء التالي قابلاً
   لإعادة الإنتاج حرفياً.

### الخطوة 4 — تسليم رابط إصدار poc-1

1. بعد نجاح `build`، يُنشر إصدار تلقائي بوسم **`poc-1`** (أو `poc-N`
   برقم التشغيل) في صفحة **Releases** في مستودع Tilawa-PoC.
2. تحقق من أن الإصدار يحتوي ملف **`app-arm64-v8a-release.apk`** واحداً.
3. سلّم المستخدم في المحادثة: **رابط تنزيل APK المباشر من إصدار poc-1**
   + رقم الإصدار + الطبقة (`lite`) + نتيجة `node-smoke`.
4. لا تثبّت APK على أي جهاز، ولا تدمج أي شيء في التطبيق الرئيسي.

## 3. ما لا يُفعل إطلاقاً

- لا دفع إلى `Tilawa` أو `Tilawa-Pro` أو أي مستودع غير `Tilawa-PoC`.
- لا تشغيل لـ `poc.yml` على طبقة `full` قبل اكتمال اختبار `lite` (30 جلسة).
- لا تعديل على كود المشروع أثناء الرفع — أي إصلاح لاحق يُناقش أولاً ويُوثَّق.
- لا إنشاء إصدار يدوي ولا رفع APK يدوياً — الإصدار يأتي من سير العمل فقط.
