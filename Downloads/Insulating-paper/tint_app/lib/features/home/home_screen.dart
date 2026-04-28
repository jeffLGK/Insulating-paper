// 主頁面 - 搜尋、序號查詢、收藏 標籤頁

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_screen.dart';
import '../cert_search/cert_search_screen.dart';
import '../favorites/favorites_screen.dart';
import '../image_match/image_match_screen.dart';
import '../settings/font_scale_sheet.dart';
import '../../core/app_info.dart';
import '../../core/database/app_database.dart';
import '../../data/datasources/car_safety_scraper.dart';
import '../sync/sync_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStartupInfo());
  }

  Future<void> _showImageStats(BuildContext context) async {
    // 顯示載入中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在從 API 抓取資料，請稍候…'),
          ],
        ),
      ),
    );

    try {
      final scraper = CarSafetyScraper();
      final result = await scraper.fetchProducts();

      int count0 = 0; // 無圖片
      int count1 = 0; // 1張（僅烙印）
      int count2 = 0; // 2張（範例 + 烙印）
      int countOther = 0; // 其他（含範例但只有1張、或3張以上）
      int countExampleOnly = 0; // 只有範例圖（無烙印）

      for (final p in result.products) {
        final urls = p.imageUrls;
        if (urls.isEmpty) {
          count0++;
        } else if (urls.length == 1) {
          if (urls.first.contains('範例')) {
            countExampleOnly++;
          } else {
            count1++;
          }
        } else {
          // 2張以上：判斷是否包含範例圖
          final hasExample = urls.any((u) => u.contains('範例'));
          if (urls.length == 2 && hasExample) {
            count2++;
          } else {
            countOther++;
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // 關閉載入中

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.teal),
              SizedBox(width: 8),
              Text('圖片統計分析'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API 共取得 ${result.count} 筆產品',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Divider(height: 20),
              _StatRow(
                  icon: Icons.filter_2,
                  color: Colors.green,
                  label: '2張圖（範例＋烙印）',
                  count: count2),
              const SizedBox(height: 6),
              _StatRow(
                  icon: Icons.filter_1,
                  color: Colors.blue,
                  label: '1張圖（僅烙印）',
                  count: count1),
              const SizedBox(height: 6),
              _StatRow(
                  icon: Icons.image_outlined,
                  color: Colors.orange,
                  label: '1張圖（僅範例）',
                  count: countExampleOnly),
              const SizedBox(height: 6),
              _StatRow(
                  icon: Icons.image_not_supported_outlined,
                  color: Colors.grey,
                  label: '無圖片',
                  count: count0),
              if (countOther > 0) ...[
                const SizedBox(height: 6),
                _StatRow(
                    icon: Icons.more_horiz,
                    color: Colors.purple,
                    label: '其他（3張以上等）',
                    count: countOther),
              ],
              const Divider(height: 20),
              Text(
                '有效圖片率：${((count1 + count2 + countExampleOnly) / result.count * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('抓取失敗：$e')),
      );
    }
  }

  Future<void> _showStartupInfo() async {
    final count = await AppDatabase.instance.getProductCount();
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(kPrefLastSync);
    final lastSync =
        lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 8),
            Text('認證隔熱紙查尋'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_outlined,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text('目前資料筆數：$count 筆',
                    style: const TextStyle(fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  lastSync != null
                      ? '安審發布時間：${DateFormat('yyyy-MM-dd HH:mm').format(lastSync)}'
                      : '安審發布時間：尚未同步',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  'App 版本：v$kAppVersion ($kAppBuildDate)',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showFontScaleSheet(context);
            },
            icon: const Icon(Icons.format_size, size: 18),
            label: const Text('字體大小'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showImageStats(context);
            },
            child: const Text('圖片統計'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 鍵盤升起時 body 與底部導覽列都不重新 layout，
      // 避免 IndexedStack 內 4 個畫面全部一起被 re-layout 造成卡頓
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          SearchScreen(),
          CertSearchScreen(),
          FavoritesScreen(),
          ImageMatchScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: '搜尋',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            selectedIcon: Icon(Icons.qr_code),
            label: '序號查詢',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_search_outlined),
            selectedIcon: Icon(Icons.image_search),
            label: '圖像比對',
          ),
        ],
      ),
    );
  }
}

// ── 統計列 ──────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(
          '$count 筆',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
