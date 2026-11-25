# تقرير جاهزية البناء — Tilawa PoC (poc-1)

**التاريخ:** 2026-11-25 — **الحالة: جاهز للبناء، بعد إصلاح واحد حاجب**
**المشروع:** `~/workspace/tilawa-poc/` (29 ملفاً + هذا الملف + `UPLOAD_MANIFEST.md`)
**المستودع الهدف:** `Tilawa-PoC` المنفصل (لم يُنشأ بعد — خطوة متصفح)
**المرجع:** `~/workspace/tilawa/phase1/POC_STATUS.md` (قُرئ كاملاً أولاً)

## 1. الحكم: جاهز للرفع والبناء (طبقة lite أولاً)

المشروع مكتمل ملفاً ملفاً (29/29)، ولا ملفات ناقصة. أُصلح محلياً في هذه
الجولة عيب حاجب واحد كان سيمنع المحرك من العمل إطلاقاً على الهاتف،
وعيبان توثيقيان كانا سيوجهان البناء إلى المستودع الخطأ. لا يوجد الآن أي
عيب معروف يمنع تشغيل `poc.yml`. ما لم يُختبَر بعد (لا Flutter SDK هنا)
هو: `flutter analyze` + `flutter test` + `flutter build apk`، ومهمة
`node-smoke`، وكل القياسات على الجهاز — وكلها موكولة إلى CI والهاتف
حسب التصميم، وليست حاجباً للرفع.

## 2. الفحص ملفاً ملفاً (ما فُحص وما وُجد)

| الملف | النتيجة |
|---|---|
| `pubspec.yaml` | سليم. `tilawa_poc` 0.1.0، `webview_flutter ^4.0.0` + `path_provider ^2.1.5` + `crypto ^3.0.6` + `share_plus ^10.1.4` + `permission_handler ^11.0.0` + `http ^1.6.0`، `flutter_lints ^4.0.0`. النطاقات واسعة عمداً وتُثبَّت من أول بناء أخضر (`pubspec.lock` غير مستثنى في `.gitignore` — سيُثبَّت). الأصول المعلنة `assets/web/tilawa.html` + `assets/web/bundle.js` فقط — لا نموذج ولا WASM مضمّن (مقصود: التنزيل عند التشغيل الأول). |
| `web/package.json` | سليم. `@tilawa/core@1.0.0-rc.1` + `onnxruntime-web@1.30.0` مثبَّتان، `esbuild ^0.25.0`، `onnxruntime-node 1.30.0` (لـ node-smoke). **لا يوجد `package-lock.json` بعد** — متوقع؛ يُولد في CI ويُثبَّت بعد أول بناء أخضر. |
| `web/build.mjs` | سليم. esbuild يبني `src/bridge.js` إلى `../assets/web/bundle.js` (iife، chrome110، minify). نحو JS سليم (`node --check` ناجح). |
| `web/src/bridge.js` | سليم. `window.TilawaPoc` (init/startSession/stopSession/dispose)، `loadWebModel` باستضافة ذاتية + `wasmPaths`، إعادة كل الأحداث عبر قناة `TilawaBridge`. نحو JS سليم (`node --check` ناجح). |
| `.github/workflows/poc.yml` | سليم وقُرئ كاملاً. تشغيل يدوي فقط (`workflow_dispatch`، خيار `tier`: lite/full، الافتراضي lite). مهمة `node-smoke` (Node 20، تنزيل lite + المرجع مع تحقق SHA، `npm install` + `npm run build`، تحميل lite + جلسة صمت 1 ثانية، يشترط حدث `capabilities`) — بوابة تمنع بناء APK إن فشلت. مهمة `build` (تعتمد على `node-smoke`): Java 17، Flutter 3.50.1، Node 20، بناء الحزمة، تنزيل الأصول مع تحقق SHA + فحص مخطط المرجع، `flutter create --platforms=android --org com.tilawa.app --project-name tilawa_poc .` + تصحيح `AndroidManifest.xml` (التسمية «Tilawa PoC» + إذنا INTERNET وRECORD_AUDIO)، `flutter pub get`، `flutter analyze`، `flutter test`، `flutter build apk --release --split-per-abi` (arm64 فقط)، رفع الأثر، ثم إصدار `poc-${run_number}` بملف `app-arm64-v8a-release.apk`. الأذونات `contents: write` للإصدار فقط. |
| `lib/main.dart` | سليم. 3 تبويبات، شريط تحذير دائم (مساعد حفظ تجريبي، حفص فقط، الصوت لا يغادر الجهاز). |
| `lib/speech_engine.dart` | سليم. الواجهة المجردة + `EngineCapabilities` + الحالات. أُضيف حقل `ortBytes` (انظر §3). |
| `lib/models.dart` | سليم. `RefWord`، الحالات الأربع للتتبع والفاحص، فئات الأخطاء الأربع؛ `confirmed` فقط يُحسب خطأً. |
| `lib/webview_engine.dart` | سليم بعد الإصلاح. ينتظر تحميل الصفحة (مهلة 30 ث)، يهيئ الجسر (مهلة 120 ث)، يترجم `capabilities`/`position`/`checker`، يبني نص المقطع من `ref-v2.json` نفسه. أُضيف فحص WASM قبل التحميل (انظر §3). |
| `lib/local_server.dart` | سليم. `127.0.0.1` فقط، منفذ عشوائي، يقدّم `tilawa.html` و`bundle.js` من الأصول، و`/models/*` و`/ort/*` من مجلد النماذج؛ MIME صحيح لـ `.wasm` و`.onnx` و`.json`؛ بلا COOP/COEP (WASM أحادي الخيط — قيد موثَّق). |
| `lib/model_manager.dart` | سليم بعد الإصلاح الحاجب (§3). بصمات lite/full مطابقة للموثق (lite `4974de78…`، 24,650,054 بايت؛ full `714e98ad…`، 67,759,744 بايت)، المرجع يُتحقق منه بعدد الآيات 6236. |
| `lib/event_log.dart` | سليم. JSONL + `LogMetrics` (زمن التظليل، الوسيط، P90). |
| `lib/screens/recitation_screen.dart` | سليم. المقاطع الأربعة المعلنة: الفاتحة 1:1–7، آية الكرسي 2:255، الإخلاص 112:1–4، الملك 67:1–5. طلب إذن الميكروفون قبل البدء، رسالة واضحة عند الرفض، التظليل فقط عند `locked` وثقة ≥ 0.6، `uncertain`/`resolved` لا تُحسب أخطاءً. |
| `lib/screens/model_screen.dart` | سليم بعد الإصلاح. بطاقة الحالة + التنزيل + البصمة؛ أُضيف عرض حجم WASM (انظر §3). |
| `lib/screens/logs_screen.dart` | سليم. قائمة السجلات + ملخص + تصدير محلي عبر `share_plus` فقط. |
| `assets/web/tilawa.html` | سليم. صفحة حد أدنى تحمّل `/bundle.js` وتبلّغ `page-loaded`. |
| `tools/download_assets.py` | سليم ومُختبَر: نحو سليم؛ `--check-only` على مجلد فارغ → `MISSING`، خروج 1 (كما هو موثق). ينزّل النموذج + المرجع + ملفات WASM الأربعة (ORT 1.30.0) من jsDelivr. |
| `tools/check_ref_schema.py` | سليم ومُختبَر: ملف مفقود → `MISSING`، خروج 1. يتحقق من `version == ref-v2` و6236 آية وكل آية فيها `w`. |
| `tools/score_sessions.py` | سليم ومُختبَر على البيانات التركيبية: أعطى بالضبط القيم المحسوبة يدوياً (TP=2، FP=1، FN=1، precision=recall=0.667، وسيط التظليل 1100ms، P90 ‏1200ms، وسيط تأخير التأكيد 1000ms، الأقصى 2200ms). |
| `test/event_log_test.dart` | سليم (قراءة). يغطي زمن التظليل والوسيط و`RefWord` وفئات الأخطاء وقاعدة «`confirmed` فقط». لم يُشغَّل هنا (لا Flutter SDK) — يُشغَّل في CI. |
| `test_data/` (3 ملفات) | سليمة. جلسة تركيبية + حقيقة أرضية مقابلة (3 أخطاء مزروعة) + README يصرّح أنها ليست نتائج. (ملاحظة: `ground_truth_example.json` سطر واحد بلا سطر جديد أخير — صالح، لا يؤثر.) |
| `docs/MEASUREMENT_PLAN.md` | سليم. التعريفات التشغيلية + العتبات الـ 14 + المصفوفة (30 جلسة) + قاعدة القرار. |
| `docs/PHONE_TEST_PROTOCOL.md` | سليم بعد التحديث (§3). |
| `docs/COMPARISON.md` | سليم. البدائل + التوصية الأولية + المستبعَد (Quran-Lab/NPL). |
| `README.md` | سليم بعد الإصلاحين (§3). |
| `NOTICE.md` | سليم. MIT + CC BY 4.0 + النِّسَب حرفياً من المصدر (yazinsai/tilawa، الالتزام `a021377`). |
| `.gitignore` | سليم بعد الإصلاح. يستثني `assets/models/` و`assets/web/bundle.js` و`web/node_modules/` و`build/` و`android/` و`*.apk`؛ **لا** يستثني `web/package-lock.json` بعد الآن (انظر §3). |

## 3. الإصلاحات التي أُجريت محلياً في هذه الجولة (4 إصلاحات)

### 3.1 [حاجب] ملفات WASM لم تكن تصل إلى الجهاز إطلاقاً — أُصلح

**المشكلة (مكتشفة في هذه الجولة):** ثلاث حقائق مجتمعة كانت تعني فشل
المحرك حتماً عند أول تشغيل على الهاتف:
1. `webview_engine.dart` يمرر للجسر `wasmPaths: <localhost>/ort/1.30.0/`،
   و`local_server.dart` يقدّم `/ort/*` من مجلد النماذج في تخزين التطبيق.
2. `model_manager.dart` (تنزيل التشغيل الأول) كان ينزّل النموذج والمرجع
   فقط — **لا ملفات WASM إطلاقاً**.
3. نسخة CI من WASM (`assets/models/ort/` عبر `tools/download_assets.py`)
   **لا تُضمَّن في APK** لأن `pubspec.yaml` لا يدرج `assets/models/` في
   الأصول.
النتيجة قبل الإصلاح: طلبات WASM كانت ستعيد 404، و`loadWebModel` كان
سيفشل قبل أي جلسة، دون رسالة واضحة للمستخدم.

**الإصلاح (4 ملفات):**
- `lib/model_manager.dart`: أُضيفت ثوابت `kOrtWasmFiles` (الملفات الأربعة
  نفسها في `tools/download_assets.py` — يُحافظ على تزامنهما) و`kOrtBaseUrl`
  (jsDelivr، `onnxruntime-web@1.30.0`)؛ أُضيفت دالة `_downloadOrtWasm()`
  تنزّل أي ملف ناقص إلى `<modelDir>/ort/1.30.0/` (مع تحقق من عدم الفراغ
  وخطأ صريح عند فشل HTTP) وتُستدعى من `download()` بعد النموذج والمرجع؛
  وأُضيفت `ortWasmReady()` و`ortBytes()`؛ و`status()` يعيد الآن حجم WASM
  في `ModelInfo.ortBytes`.
- `lib/speech_engine.dart`: أُضيف حقل `ortBytes` إلى `ModelInfo`.
- `lib/webview_engine.dart`: `load()` يتحقق الآن من `ortWasmReady()` قبل
  تحميل الصفحة، ويرمي خطأً صريحاً قابلاً للفهم («ملفات تشغيل المحرك (WASM)
  غير موجودة — نزّلها من تبويب النموذج») بدل خطأ جسر غامض.
- `lib/screens/model_screen.dart`: بطاقة النموذج تعرض الآن سطر «ملفات
  تشغيل المحرك (WASM): X MB / غير منزَّلة بعد»، وزر التنزيل صار
  «تنزيل النموذج + ملفات التشغيل والتحقق منها».

**ما لم يُختبَر من هذا الإصلاح:** الكود لم يُترجم هنا (لا Flutter SDK) —
أول تحقق له هو `flutter analyze` + `flutter test` في CI، ثم ظهور حجم
WASM غير الصفر في بطاقة النموذج على الهاتف (§أ من البروتوكول). المنطق
نفسه (HttpClient + ملف مؤقت + إعادة تسمية) مطابق للنمط المستخدم أصلاً
في `_downloadChecked` في الملف نفسه.

### 3.2 [توثيقي] `.gitignore` كان يستثني `web/package-lock.json` — أُصلح

تعارض مع `poc.yml` («The first green build MUST commit the generated lock
file»): سطر `web/package-lock.json` حُذف من `.gitignore` ليُثبَّت القفل
بعد أول بناء أخضر.

### 3.3 [توثيقي] README كان يأمر بـ `npm ci` بلا ملف قفل — أُصلح

`npm ci` يفشل دون `package-lock.json` (غير موجود بعد). صار الأمر
`npm install` في المرة الأولى، مع ملاحظة تثبيت القفل بعد أول بناء أخضر.
وصُحح أيضاً: الإصدار `poc-N` يُنشر في **مستودع Tilawa-PoC المنفصل**
(كان مكتوباً «في مستودع Tilawa» — خطأ كان سيوجه البناء للمستودع الخطأ).

### 3.4 [توثيقي] بروتوكول الهاتف كان يشير إلى مستودع Tilawa — أُصلح وحُدّث

`docs/PHONE_TEST_PROTOCOL.md`:
- كل إشارة إلى «مستودع Tilawa» صارت «مستودع Tilawa-PoC المنفصل»
  (مع الرابط الكامل)؛ وحُذفت عبارة «دون إنشاء مستودع جديد» من المقدمة
  (القرار الآن: إنشاء Tilawa-PoC والبناء فيه).
- §أ: أُضيفت خطوة التحقق من WASM (سطر الحجم غير الصفر في بطاقة النموذج،
  ودوْن حجمه في تقرير النتائج) وخطوة إيقاف الاختبار إن تكرر غيابه.
- §0.1 (جديد): قائمة تحقق قبل البدء (بطارية ≥ 50%، مساحة ≥ 500 MB،
  APK مثبَّت بالاسم الصحيح، إنترنت للتنزيل الأول فقط، بطاقة النموذج جاهزة
  بالبصمة، إذن الميكروفون، النصوص المطبوعة + ملفات الحقيقة الأرضية،
  ساعة إيقاف + دفتر نتائج، `adb` اختياري).
- §4 (جديد): قالب «ما يُدوَّن في كل جلسة» (15 حقلاً: `session_id`، المقطع،
  النوع، الظروف، المزروعة/المؤكدة/الكاذبة/غير المتأكد، زمن أول تظليل،
  زمن تأكيد الخطأ بساعة الإيقاف، زمن التحميل، الخلفية، ملاحظات)؛ وتقرير
  النتائج `POC_RESULTS_YYYY-MM-DD.md` يُحفظ في **مستودع Tilawa-PoC**
  (كان مكتوباً «في فرع PoC» + PR — غير صحيح لمستودع منفصل)، مع منع
  صريح لفتح PR على Tilawa أو Tilawa-Pro.

## 4. التحقق من العزل (لا إشارة إلى Tilawa/Tilawa-Pro إطلاقاً)

- بحث نصي كامل في المشروع: **صفر** إشارة إلى مستودع Tilawa أو Tilawa-Pro
  أو `github.com/ezzaldeenmansour123/Tilawa` (الإشارتان الوحيدتان لكلمتي
  «Tilawa / Tilawa-Pro» هما نفيان صريحان في البروتوكول: «ليس مستودع
  Tilawa ولا Tilawa-Pro» و«لا يُفتح طلب سحب على Tilawa أو Tilawa-Pro»).
- `applicationId`: `com.tilawa.app.tilawa_poc` في كل المواضع (README،
  `poc.yml` عبر `--org com.tilawa.app --project-name tilawa_poc`،
  البروتوكول، خطة القياس) — حزمة مختلفة عن Tilawa، لا تستبدله.
- لا ملفات مضمّنة كبيرة: حجم المشروع الكلي **188 KB**؛ لا ملف `.onnx`
  ولا `.mp3`/`.wav` ولا `.apk` ولا `.zip`؛ لا `assets/models/` ولا
  `assets/web/bundle.js` (يُبنيان في CI)؛ النموذج (24.7 MB) والمرجع
  (4.7 MB) وWASM تُنزَّل عند التشغيل الأول فقط.
- الإشارات إلى `tilawa.dev` مقصودة ومحدودة: مصدر التنزيل الأول للنموذج
  والمرجع فقط (مع تحقق SHA-256)، ولا اعتماد عليه بعد التثبيت؛ و`yazinsai/tilawa`
  مذكور كمصدر للمحرك (MIT + CC BY 4.0) فقط.

## 5. ما لم يُختبَر بعد — ويبقى حاجباً للقياس لا للرفع

1. `flutter analyze` + `flutter test` + `flutter build apk` (لا Flutter SDK
   هنا — أول تشغيل في CI).
2. مهمة `node-smoke` (تحميل lite + جلسة صمت) — بوابة قبل أي APK.
3. منح إذن الميكروفون داخل WebView على S22 Ultra (أكبر مجهول تقني رقم 1).
4. توفّر WebGPU في WebView + أداء WASM أحادي الخيط (مجهول رقم 2).
5. كل المعايير الـ 14 على الجهاز + حجم WASM الفعلي + حجم APK النهائي.
6. إصدارات الحزم وقت البناء (النطاقات واسعة عمداً؛ `webview_flutter` و
   `permission_handler` وغيرهما تُحلّ في CI وتُثبَّت في ملفي القفل).

## 6. الملفات الناقصة: لا شيء

29/29 ملفاً موجودة (القائمة الكاملة في `UPLOAD_MANIFEST.md`). لا ملف
ناقص، لا مسار مفقود. الملفات التي تبدو غائبة محلياً (`assets/web/bundle.js`،
`assets/models/`، `web/package-lock.json`، `pubspec.lock`، `android/`)
مخرجات بناء مقصود غيابها وتُولد في CI.

## 7. الخطوات المتبقية على الوكيل الرئيسي (المتصفح) — بالترتيب

(التفصيل الحرفي الكامل في `UPLOAD_MANIFEST.md` §2 — هذا ملخصها.)

1. **إنشاء مستودع عام فارغ** باسم `Tilawa-PoC` تحت `ezzaldeenmansour123`
   (بلا README ولا ترخيص ولا .gitignore).
2. **رفع الملفات الـ29 + `UPLOAD_MANIFEST.md` + `BUILD_READINESS.md`**
   إلى الفرع `main` فيه فقط، والتحقق من العدد (31) ومن وجود
   `.github/workflows/poc.yml`.
3. **تشغيل سير العمل يدوياً**: Actions ← «Build Tilawa PoC APK» ←
   Run workflow ← الطبقة **`lite`** ← Run.
4. **مراقبة `node-smoke` أولاً**: إن فشلت، توقف ودوّن السبب نصاً ولا تبنِ
   APK؛ إن نجحت، تابع مهمة `build` حتى الإصدار.
5. **تثبيت ملفي القفل** (`web/package-lock.json` + `pubspec.lock`)
   المولّدين في أول بناء أخضر (commit في Tilawa-PoC).
6. **تسليم رابط إصدار `poc-1`**: رابط تنزيل `app-arm64-v8a-release.apk`
   المباشر + رقم الإصدار + الطبقة + نتيجة `node-smoke`، في المحادثة.
7. بعدها: تنفيذ بروتوكول الهاتف (`docs/PHONE_TEST_PROTOCOL.md` — 30 جلسة
   على S22 Ultra) ثم تقرير النتائج في مستودع Tilawa-PoC. **لا دمج في
   التطبيق الرئيسي إطلاقاً** قبل GO موثَّق.

## 8. ملاحظات للمراجعة (ليست حواجب)

- `poc.yml` يستخدم `flutter create .` في مجلد فيه `lib/main.dart` قائم —
  النمط نفسه مستخدم في بناء Tilawa الرئيسي ويعمل؛ إن اعترض `flutter create`
  على ملفات قائمة في CI، فهذا أول ما يُفحص في سجل `build`.
- تنزيل WASM الجديد في `ModelManager` بلا بصمة مثبَّتة (لا يثبّت المنبع
  بصمة لملفات `onnxruntime-web`) — التحقق «موجود + غير فارغ» فقط؛ أي
  تلف يُكتشف عند `loadWebModel` كخطأ تحميل صريح، لا كنتيجة خاطئة صامتة.
- `download_assets.py` في CI ينزّل WASM إلى `assets/models/ort/` لكنه لا
  يُضمَّن في APK — دوره الآن التحقق من توفر الملفات فقط؛ التنزيل الفعلي
  للجهاز يتم داخل التطبيق. إن أراد الفريق لاحقاً تضمين WASM في APK
  (بلا تنزيل وقت التشغيل)، فذلك تغيير تصميم يُناقش منفصلاً.
