import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/image/image_hasher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/database/app_database.dart';
import '../../data/datasources/car_safety_scraper.dart';
import '../../data/models/tint_product.dart';

const String kSyncTaskName = 'tint_weekly_sync';
const String kSyncTaskTag = 'tint_sync';
const String kPrefLastSync = 'last_sync_at';
const String kPrefDataVersion = 'data_version';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kSyncTaskName) {
      await SyncService.instance.syncNow(silent: true);
    }
    return Future.value(true);
  });
}

enum SyncStatus { idle, syncing, success, failed }

class SyncState {
  final SyncStatus status;
  final String? message;
  final int? newCount;
  final DateTime? syncedAt;
  /// 0.0 ~ 1.0，null 或 0 代表不確定進度（indeterminate）
  final double progress;
  final String? progressMessage;

  const SyncState({
    required this.status,
    this.message,
    this.newCount,
    this.syncedAt,
    this.progress = 0.0,
    this.progressMessage,
  });

  static const idle = SyncState(status: SyncStatus.idle);
}

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _scraper = CarSafetyScraper();
  final _db = AppDatabase.instance;
  final _notifications = FlutterLocalNotificationsPlugin();

  final _stateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  SyncState _currentState = SyncState.idle;
  SyncState get currentState => _currentState;

  Future<void> initialize() async {
    // 網頁平台不支援背景任務和通知
    if (kIsWeb) {
      return;
    }

    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

      await Workmanager().registerPeriodicTask(
        kSyncTaskName,
        kSyncTaskName,
        tag: kSyncTaskTag,
        frequency: const Duration(days: 7),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      // 忽略 workmanager 初始化錯誤
    }

    // 只在行動平台初始化通知
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _notifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
    }
  }

  Future<SyncResult> syncNow({bool silent = false}) async {
    if (_currentState.status == SyncStatus.syncing) {
      return SyncResult.alreadyRunning();
    }

    _emit(SyncState(
      status: silent ? SyncStatus.idle : SyncStatus.syncing,
      message: '下載資料中...',
      progressMessage: '正在取得產品資料...',
      progress: 0.0,
    ));

    try {
      final scraperResult = await _scraper.fetchProducts();

      _emit(SyncState(
        status: silent ? SyncStatus.idle : SyncStatus.syncing,
        message: '儲存資料中...',
        progressMessage: '正在儲存 ${scraperResult.count} 筆資料...',
        progress: 0.1,
      ));
      await _db.upsertProducts(scraperResult.products);

      // 下載所有產品圖片到本機
      await _downloadImages(scraperResult.products, silent: silent);

      final prefs = await SharedPreferences.getInstance();
      final nowStr = DateTime.now().toIso8601String();
      await prefs.setString(kPrefLastSync, nowStr);
      await prefs.setInt(
        kPrefDataVersion,
        (prefs.getInt(kPrefDataVersion) ?? 0) + 1,
      );

      if (silent) {
        await _sendSyncNotification(scraperResult.count);
      }

      final state = SyncState(
        status: SyncStatus.success,
        message: 'Synced ${scraperResult.count} records',
        newCount: scraperResult.count,
        syncedAt: scraperResult.fetchedAt,
      );
      _emit(state);

      return SyncResult.success(
        count: scraperResult.count,
        syncedAt: scraperResult.fetchedAt,
      );
    } on ScraperException catch (e) {
      final state = SyncState(
        status: SyncStatus.failed,
        message: 'Sync failed: ${e.message}',
      );
      _emit(state);
      return SyncResult.failure(e.message);
    } catch (e) {
      final state = SyncState(
        status: SyncStatus.failed,
        message: 'Sync failed: unexpected error',
      );
      _emit(state);
      return SyncResult.failure(e.toString());
    }
  }

  /// 下載所有產品圖片到本機儲存，並更新 DB 中的 image_local_path
  Future<void> _downloadImages(
    List<TintProduct> products, {
    bool silent = false,
  }) async {
    if (kIsWeb) return;

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'tint_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 只計算有圖片的產品數，用於進度計算
    final withImages = products.where((p) => p.imageUrls.isNotEmpty).toList();
    final total = withImages.length;
    int done = 0;

    for (final product in withImages) {
      final urls = product.imageUrls;
      final localPaths = <String>[];

      for (final url in urls) {
        try {
          final filename = '${url.hashCode.abs()}.jpg';
          final localPath = p.join(imagesDir.path, filename);
          final file = File(localPath);

          if (!await file.exists()) {
            // 使用 Uri.encodeFull 處理路徑含中文字的 URL（如 ...範例.jpg）
            final uri = _safeParseUri(url);
            if (uri == null) continue;
            final resp = await http
                .get(uri)
                .timeout(const Duration(seconds: 15));
            if (resp.statusCode == 200) {
              await file.writeAsBytes(resp.bodyBytes);
            }
          }

          if (await file.exists()) {
            localPaths.add(localPath);
          }
        } catch (_) {
          // 單張圖片下載失敗不影響整體流程
        }
      }

      if (localPaths.isNotEmpty) {
        await _db.updateImageLocalPath(
          product.certNumber,
          localPaths.join(','),
        );

        // 計算並儲存第一張圖片的 pHash（僅在尚未計算時執行）
        if (product.imagePhash == null || product.imagePhash!.isEmpty) {
          try {
            final bytes = await File(localPaths.first).readAsBytes();
            final phash = ImageHasher.hashFromBytes(bytes);
            if (phash != null) {
              await _db.updateImagePhash(product.certNumber, phash);
            }
          } catch (_) {}
        }
      }

      done++;
      if (!silent && total > 0) {
        _emit(SyncState(
          status: SyncStatus.syncing,
          message: '下載圖片中...',
          progress: 0.1 + 0.9 * (done / total),
          progressMessage: '下載圖片 $done / $total',
        ));
      }
    }
  }

  /// 安全解析 URL，若路徑含未編碼中文字（如 ...範例.jpg）則先 encodeFull 再解析
  Uri? _safeParseUri(String url) {
    try {
      return Uri.parse(url);
    } catch (_) {}
    try {
      return Uri.parse(Uri.encodeFull(url));
    } catch (_) {}
    return null;
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(kPrefLastSync);
    return str != null ? DateTime.tryParse(str) : null;
  }

  void _emit(SyncState state) {
    _currentState = state;
    _stateController.add(state);
  }

  Future<void> _sendSyncNotification(int count) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tint_sync_channel',
        'Data Sync',
        channelDescription: 'Tint film database update notifications',
        importance: Importance.low,
        priority: Priority.low,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notifications.show(
      1001,
      'Database Updated',
      'Downloaded $count records',
      details,
    );
  }

  void dispose() {
    _stateController.close();
  }
}

class SyncResult {
  final bool isSuccess;
  final String? errorMessage;
  final int? count;
  final DateTime? syncedAt;
  final bool wasAlreadyRunning;

  const SyncResult._({
    required this.isSuccess,
    this.errorMessage,
    this.count,
    this.syncedAt,
    this.wasAlreadyRunning = false,
  });

  factory SyncResult.success({required int count, required DateTime syncedAt}) {
    return SyncResult._(isSuccess: true, count: count, syncedAt: syncedAt);
  }

  factory SyncResult.failure(String message) {
    return SyncResult._(isSuccess: false, errorMessage: message);
  }

  factory SyncResult.alreadyRunning() {
    return const SyncResult._(isSuccess: false, wasAlreadyRunning: true);
  }
}
