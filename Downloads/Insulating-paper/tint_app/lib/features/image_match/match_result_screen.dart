import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image/similarity_calculator.dart';
import '../search/search_screen.dart' show ProductDetailScreen;
import 'image_match_providers.dart';
import 'widgets/similarity_badge.dart';

/// 比對結果瀏覽畫面（OCR 或圖像相似度）
class MatchResultScreen extends ConsumerStatefulWidget {
  const MatchResultScreen({super.key});

  @override
  ConsumerState<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends ConsumerState<MatchResultScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToDetail(int? productId) {
    if (productId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: productId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageMatchProvider);

    // ── Loading ──────────────────────────────────────────────────
    if (state.status == MatchStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('比對中')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                state.progressMessage,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                '首次執行 OCR 模型載入約需數秒',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final results = state.results;

    return Scaffold(
      appBar: AppBar(
        title: const Text('比對結果'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(imageMatchProvider.notifier).reset();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: results.isEmpty
          ? _buildEmpty(state)
          : Column(
              children: [
                // OCR 原始文字（可展開查看）
                if (state.ocrRawText != null)
                  _OcrTextBar(ocrText: state.ocrRawText!),

                // 頁碼指示器
                _PageIndicator(
                  count: results.length,
                  current: _currentPage,
                ),

                // 卡片 PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: results.length,
                    onPageChanged: (i) =>
                        setState(() => _currentPage = i),
                    itemBuilder: (ctx, i) => _ResultCard(
                      result: results[i],
                      queryBytes: state.queryBytes,
                      rank: i + 1,
                      total: results.length,
                    ),
                  ),
                ),

                // 動作按鈕列
                _ActionBar(
                  onMatch: () =>
                      _goToDetail(results[_currentPage].product.id),
                  onNext: results.length > 1 &&
                          _currentPage < results.length - 1
                      ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                      : null,
                  onPrev: _currentPage > 0
                      ? () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                      : null,
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(ImageMatchState state) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_search, size: 72, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? '未找到符合的隔熱紙',
                style:
                    const TextStyle(fontSize: 15, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              if (state.ocrRawText != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'OCR 擷取：\n${state.ocrRawText}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  ref.read(imageMatchProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重新比對'),
              ),
            ],
          ),
        ),
      );
}

// ─── OCR 文字顯示列（可展開） ─────────────────────────────────────

class _OcrTextBar extends StatefulWidget {
  final String ocrText;
  const _OcrTextBar({required this.ocrText});

  @override
  State<_OcrTextBar> createState() => _OcrTextBarState();
}

class _OcrTextBarState extends State<_OcrTextBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.ocrText.replaceAll('\n', '  ').trim();
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        color: Colors.green.withValues(alpha: 0.08),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.text_fields, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _expanded ? widget.ocrText : preview,
                style:
                    const TextStyle(fontSize: 12, color: Colors.green),
                maxLines: _expanded ? null : 1,
                overflow:
                    _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
            Icon(
              _expanded
                  ? Icons.expand_less
                  : Icons.expand_more,
              size: 16,
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 單張比對結果卡片 ─────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final MatchResult result;
  final Uint8List? queryBytes;
  final int rank;
  final int total;

  const _ResultCard({
    required this.result,
    required this.queryBytes,
    required this.rank,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final product = result.product;
    final colorScheme = Theme.of(context).colorScheme;
    final isOcr = result.source == MatchSource.ocr;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 比對來源標籤 ───────────────────────────────────────
          Row(
            children: [
              _SourceBadge(isOcr: isOcr),
              const Spacer(),
              Text(
                '第 $rank 筆 / 共 $total 筆',
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── 圖片比較區 ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('拍攝圖片',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: queryBytes != null
                          ? Image.memory(queryBytes!,
                              height: 150, fit: BoxFit.cover,
                              width: double.infinity)
                          : _placeholder(150),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    const Text('資料庫圖片',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _ProductImage(product: product, height: 150),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── 相似度／匹配分數 ───────────────────────────────────
          Center(
            child: SimilarityBadge(
              similarity: result.similarity,
              label: isOcr ? 'OCR 吻合度' : '圖像相似度',
            ),
          ),

          const SizedBox(height: 16),

          // ── 產品資料卡 ─────────────────────────────────────────
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.brand}  ${product.model}',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                  const Divider(height: 16),
                  _infoRow('認證號碼', product.certNumber),
                  if (product.visibleLight != null)
                    _infoRow('可見光穿透率', '${product.visibleLight}%'),
                  if (product.heatRejection != null)
                    _infoRow('隔熱率', '${product.heatRejection}%'),
                  if (product.uvRejection != null)
                    _infoRow('紫外線阻隔率', '${product.uvRejection}%'),
                  if (product.standard != null)
                    _infoRow('標示方式', product.standard!),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Widget _placeholder(double h) => Container(
        height: h,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.grey, size: 40),
      );
}

// ─── 來源標籤 ─────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final bool isOcr;
  const _SourceBadge({required this.isOcr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOcr
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOcr ? Colors.green : Colors.blue,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOcr ? Icons.text_fields : Icons.image_search,
            size: 14,
            color: isOcr ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 4),
          Text(
            isOcr ? 'OCR 文字辨識' : '圖像比對',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOcr ? Colors.green : Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 產品圖片 ─────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final dynamic product;
  final double height;

  const _ProductImage({required this.product, required this.height});

  @override
  Widget build(BuildContext context) {
    final localPath = product.firstImageLocalPath as String?;
    if (localPath != null) {
      return FutureBuilder<bool>(
        future: File(localPath).exists(),
        builder: (_, snap) {
          if (snap.data == true) {
            return Image.file(File(localPath),
                height: height, fit: BoxFit.cover, width: double.infinity);
          }
          return _networkOrPlaceholder();
        },
      );
    }
    return _networkOrPlaceholder();
  }

  Widget _networkOrPlaceholder() {
    final url = product.firstImageUrl as String?;
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        height: height,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (_, __) => Container(
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => _empty(),
      );
    }
    return _empty();
  }

  Widget _empty() => Container(
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.grey, size: 40),
      );
}

// ─── 頁碼指示器 ──────────────────────────────────────────────────

class _PageIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _PageIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ─── 動作按鈕列 ──────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final VoidCallback onMatch;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  const _ActionBar({required this.onMatch, this.onNext, this.onPrev});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (onPrev != null)
              OutlinedButton.icon(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                label: const Text('上一筆'),
              )
            else
              const SizedBox(width: 96),
            const Spacer(),
            FilledButton.icon(
              onPressed: onMatch,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('符合',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 48),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const Spacer(),
            if (onNext != null)
              OutlinedButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                label: const Text('下一筆'),
                iconAlignment: IconAlignment.end,
              )
            else
              const SizedBox(width: 96),
          ],
        ),
      ),
    );
  }
}
