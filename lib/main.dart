// Tilawa PoC — entry point.
//
// Standalone experiment app. Three tabs: Recitation, Model, Logs.
// No accounts, no ads, no analytics, no uploads. Audio never leaves the device.

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'model_manager.dart';
import 'progress_store.dart';
import 'screens/logs_screen.dart';
import 'screens/model_screen.dart';
import 'screens/recitation_screen.dart';
import 'webview_engine.dart';

void main() {
  runApp(const TilawaPocApp());
}

class TilawaPocApp extends StatefulWidget {
  const TilawaPocApp({super.key});
  @override
  State<TilawaPocApp> createState() => _TilawaPocAppState();
}

class _TilawaPocAppState extends State<TilawaPocApp> {
  late final Future<(ModelManager, WebViewEngine, ProgressStore)> _ready;
  int _tab = 0;
  bool _dark = false;

  /// Set when the startup bundle check (below) finds bundle.js missing
  /// or empty: the engine is unavailable in this build, with a clear
  /// message. Null when the bundle is present.
  String? _bundleWarning;

  @override
  void initState() {
    super.initState();
    _checkBundle();
    _ready = ModelManager.create().then(
      (m) async =>
          (m, WebViewEngine(modelManager: m), await ProgressStore.create()),
    );
  }

  /// Early bundle check (TASMEE Phase 2, item 2.3): verify at startup
  /// that assets/web/bundle.js exists and is non-empty, so a broken or
  /// missing engine bundle fails loudly here instead of at
  /// «ابدأ التسميع». Local dev copies have no bundle.js by design (it
  /// is built in CI only) — that only logs a warning and marks the
  /// engine unavailable with a clear message; the rest of the PoC keeps
  /// working, and nothing here throws.
  Future<void> _checkBundle() async {
    try {
      final data = await rootBundle.load('assets/web/bundle.js');
      if (data.lengthInBytes == 0) {
        throw StateError('bundle.js is empty');
      }
      debugPrint('[TilawaPoc] bundle.js OK (${data.lengthInBytes} bytes)');
    } catch (e) {
      debugPrint('[TilawaPoc] WARNING: bundle.js unavailable at startup: $e');
      if (mounted) {
        setState(() {
          _bundleWarning =
              'حزمة المحرك (bundle.js) غير موجودة أو فارغة في هذه النسخة — '
              'التسميع غير متاح حتى تُبنى الحزمة (npm run build في web/). '
              'باقي وظائف المختبر تعمل كالمعتاد.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tilawa PoC — التسميع الذكي (تجريبي)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<(ModelManager, WebViewEngine, ProgressStore)>(
        future: _ready,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final (manager, engine, progressStore) = snap.data!;
          final pages = [
            RecitationScreen(engine: engine, progressStore: progressStore),
            ModelScreen(manager: manager, engine: engine),
            const LogsScreen(),
          ];
          return Scaffold(
            appBar: AppBar(
              title: const Text('التسميع الذكي — PoC تجريبي'),
              actions: [
                IconButton(
                  icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
                  tooltip: _dark ? 'الوضع النهاري' : 'الوضع الليلي',
                  onPressed: () => setState(() => _dark = !_dark),
                ),
              ],
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Colors.amber.shade100,
                  child: const Text(
                    'مساعد حفظ تجريبي — يكشف أخطاء الحفظ فقط، لا يقيّم التجويد أو النطق؛ '
                    'حفص فقط؛ قد يخطئ؛ الصوت لا يغادر جهازك.',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                if (_bundleWarning != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Colors.orange.shade100,
                    child: Text(
                      _bundleWarning!,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                Expanded(child: pages[_tab]),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.mic), label: 'التسميع'),
                NavigationDestination(
                    icon: Icon(Icons.memory), label: 'النموذج'),
                NavigationDestination(
                    icon: Icon(Icons.list_alt), label: 'السجلات'),
              ],
            ),
          );
        },
      ),
    );
  }
}
