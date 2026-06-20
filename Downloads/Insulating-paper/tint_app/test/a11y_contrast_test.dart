// 對比度檢查測試（Flutter DevTools Accessibility Inspector 的 CLI 等價物）
//
// 把 APP 中實際用到的 Text + 背景配色組合塞進一個合成畫面，
// 跑 meetsGuideline(textContrastGuideline)。失敗時會列出哪一段文字
// 沒達 WCAG AA（normal text 4.5:1 / large text 3:1）。
//
// 執行：flutter test test/a11y_contrast_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('合成畫面：APP 中所有 Text 配色 vs WCAG AA 對比度', (tester) async {
    await tester.pumpWidget(const _ContrastShowcase());
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}

class _ContrastShowcase extends StatelessWidget {
  const _ContrastShowcase();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Badges (_StatChip 配色) ────────────────────────────
              Wrap(spacing: 6, runSpacing: 6, children: const [
                _Badge(text: '可見光 70%以上',
                    bg: Color(0xFFFFEB3B), fg: Colors.black87),       // 黃底
                _Badge(text: '可見光 40%',
                    bg: Color(0xFFE0E0E0), fg: Colors.black87),       // 灰底
                _Badge(text: '可見光 異常',
                    bg: Color(0xFFEF9A9A), fg: Colors.black87),       // red.shade300
                _Badge(text: '隔熱 50%',
                    bg: Color(0xFFFF7043), fg: Colors.white),         // deepOrange.400
              ]),
              const SizedBox(height: 24),

              // ── 白底純文字（home_screen 統計尾註、image_match 提示）──
              const Text('home stats footer 13/blueGrey',
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
              const SizedBox(height: 8),
              const Text('search empty hint 12/grey',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('image label 11/grey',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('match result 13/grey',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('match result 15/grey',
                  style: TextStyle(fontSize: 15, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('match score 12/green',
                  style: TextStyle(fontSize: 12, color: Colors.green)),
              const SizedBox(height: 24),

              // ── 橘色資訊區塊（search_screen / match_result）───────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0x14FF9800), // orange.withAlpha(0.08)
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0x66FF9800), width: 1),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange, size: 28),
                    SizedBox(height: 8),
                    Text(
                      '無業者自行烙印的實際認證貼紙',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      '本產品僅有專業機構印製的範例圖\n建議改用「序號查詢」功能查看詳細資訊',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Badge({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
