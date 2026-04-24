// lib/main.dart
//
// APP 進入點。
// 完成：
//   1. SyncService 初始化（Workmanager + 通知）
//   2. 首次啟動時自動同步一次
//   3. 設定 Material 3 主題

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

import 'features/home/home_screen.dart';
import 'features/sync/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 限制圖片快取，避免長清單連續捲動造成記憶體堆積
  PaintingBinding.instance.imageCache
    ..maximumSize = 200        // 最多保留 200 張已解碼圖片（原為 1000）
    ..maximumSizeBytes = 50 << 20; // 最多 50 MB（原為 100 MB）

  // Web 平台使用記憶體存儲，不需要 SQLite 初始化
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 初始化同步服務（登記 Workmanager 背景任務）
  await SyncService.instance.initialize();

  // 首次安裝，或超過 7 天未同步 → 自動觸發一次
  await _autoSyncIfNeeded();

  runApp(
    const ProviderScope(
      child: TintApp(),
    ),
  );
}

Future<void> _autoSyncIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final lastSyncStr = prefs.getString(kPrefLastSync);

  bool shouldSync = lastSyncStr == null;
  if (!shouldSync && lastSyncStr != null) {
    final lastSync = DateTime.tryParse(lastSyncStr);
    if (lastSync != null) {
      shouldSync = DateTime.now().difference(lastSync).inDays >= 7;
    }
  }

  if (shouldSync) {
    // 背景靜默同步，不阻塞 UI 啟動
    SyncService.instance.syncNow(silent: false);
  }
}

class TintApp extends StatelessWidget {
  const TintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '隔熱紙查詢',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
