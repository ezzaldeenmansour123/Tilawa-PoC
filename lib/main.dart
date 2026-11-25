// Tilawa PoC — entry point.
//
// Standalone experiment app. Three tabs: Recitation, Model, Logs.
// No accounts, no ads, no analytics, no uploads. Audio never leaves the device.

import 'package:material_ui/material_ui.dart';

import 'model_manager.dart';
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
  late final Future<(ModelManager, WebViewEngine)> _ready;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _ready = ModelManager.create().then(
      (m) => (m, WebViewEngine(modelManager: m)),
    );
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
      home: FutureBuilder<(ModelManager, WebViewEngine)>(
        future: _ready,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final (manager, engine) = snap.data!;
          final pages = [
            RecitationScreen(engine: engine),
            ModelScreen(manager: manager, engine: engine),
            const LogsScreen(),
          ];
          return Scaffold(
            appBar: AppBar(
              title: const Text('التسميع الذكي — PoC تجريبي'),
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
