// btox/flutter/lib/main.dart
//
// BTOX — Flutter girişi.
// Material 3 koyu+aydınlık temalar, basit yönlendirme ve Rust çekirdeğinin
// olay akışını dinleyen bir AppState.

import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge/btox_api.dart' as btox;
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Rust çekirdeğini yükle (libbtox_core.so / .dll / .dylib).
  await btox.initBridge();
  btox.api.initLogger();

  // Profil dosyaları için uygun bir dizin verilmeli; placeholder olarak app docs.
  // Üretimde getApplicationDocumentsDirectory() kullanılır.
  final dataDir = await btox.bootstrapDataDir();
  final selfId = await btox.api.start(dataDir: dataDir, profileName: 'default');
  // ignore: avoid_print
  print('BTOX self Tox ID: $selfId');

  runApp(const BtoxApp());
}

class BtoxApp extends StatelessWidget {
  const BtoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BTOX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4CAF50),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4CAF50),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

