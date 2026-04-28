// lib/features/search/search_screen.dart
//
// 關鍵字搜尋畫面：搜尋框 + 品牌篩選 + 無限捲動列表

import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'search_providers.dart';
import '../sync/sync_service.dart';
import '../favorites/favorites_providers.dart';
import '../comparison/comparison_providers.dart';
import '../comparison/comparison_screen.dart';
import 'advanced_filters_providers.dart';
import 'advanced_filters_sheet.dart';
import '../settings/font_scale_sheet.dart';
import '../../core/font_scale.dart';
import '../../core/database/app_database.dart';
import '../../data/models/tint_product.dart';
import '../../data/datasources/car_safety_scraper.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchProvider.notifier).loadMore();
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(searchProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final syncStream = ref.watch(syncStateProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      // 鍵盤彈出時不強制 resize body，避免長清單每 frame 重新 layout 造成卡頓
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('隔熱紙認證查詢'),
        actions: [
          // 對比按鈕
          ref.watch(comparisonProvider).isNotEmpty
              ? Badge.count(
                  count: ref.watch(comparisonProvider).length,
                  child: IconButton(
                    tooltip: '產品對比',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ComparisonScreen()),
                    ),
                    icon: const Icon(Icons.compare),
                  ),
                )
              : IconButton(
                  tooltip: '產品對比',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ComparisonScreen()),
                  ),
                  icon: const Icon(Icons.compare),
                ),
          const SizedBox(width: 8),
          // 同步按鈕
          syncStream.when(
            data: (state) => _SyncButton(state: state),
            loading: () => const _SyncButton(state: SyncState.idle),
            error: (_, __) => const _SyncButton(state: SyncState.idle),
          ),
          // 字體大小設定
          IconButton(
            tooltip: '字體大小',
            icon: const Icon(Icons.format_size),
            onPressed: () => showFontScaleSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── 搜尋區域 ─────────────────────────────────────────
          _SearchBar(controller: _searchController),
          _BrandFilterChips(),

          // ── 搜尋結果資訊列 ──────────────────────────────────
          if (!searchState.isLoading || searchState.items.isNotEmpty)
            _ResultsHeader(state: searchState),

          // ── 錯誤訊息 ────────────────────────────────────────
          if (searchState.errorMessage != null)
            _ErrorBanner(message: searchState.errorMessage!),

          // ── 結果列表 ────────────────────────────────────────
          Expanded(
            child: searchState.items.isEmpty && searchState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : searchState.items.isEmpty
                    ? _EmptyState(query: searchState.query)
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: _ProductList(
                          state: searchState,
                          scrollController: _scrollController,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── 搜尋框 ──────────────────────────────────────────────────────────
class _SearchBar extends ConsumerWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(advancedFiltersProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: ref.read(searchProvider.notifier).setQuery,
              decoration: InputDecoration(
                hintText: '輸入品牌、型號、認證號碼...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          ref.read(searchProvider.notifier).setQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 篩選按鈕
          Badge(
            isLabelVisible: filterState.hasActiveFilters,
            label: const Text(''),
            child: IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const AdvancedFiltersSheet(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 品牌篩選 chips ───────────────────────────────────────────────────
class _BrandFilterChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(brandsProvider);
    final brandCounts = ref.watch(brandCountsProvider);
    final current = ref.watch(searchProvider).brandFilter;

    return brands.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        // 取得筆數 Map（若尚未載入則為空 Map）
        final counts = brandCounts.valueOrNull ?? {};
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length + 1, // +1 for "全部"
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final isAll = i == 0;
              final brand = isAll ? null : list[i - 1];
              final selected = isAll ? current == null : current == brand;
              final String chipLabel;
              if (isAll) {
                chipLabel = '全部';
              } else {
                final cnt = counts[brand!];
                chipLabel = cnt != null ? '$brand ($cnt筆)' : brand;
              }
              return FilterChip(
                label: Text(chipLabel),
                selected: selected,
                onSelected: (_) {
                  ref.read(searchProvider.notifier).setBrandFilter(current == brand ? null : brand);
                },
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 40),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── 結果筆數列 ──────────────────────────────────────────────────────
class _ResultsHeader extends StatelessWidget {
  final SearchState state;
  const _ResultsHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final loadedCount = state.items.length;
    final String label;
    if (state.query.isEmpty) {
      // 無搜尋時顯示資料庫總筆數，取得前暫顯已載入筆數
      final total = state.totalCount ?? loadedCount;
      label = state.hasMore
          ? '已載入 $loadedCount / $total'
          : '共 $total 筆';
    } else {
      final suffix = state.hasMore ? '（還有更多）' : ' 筆';
      label = '「${state.query}」找到 $loadedCount$suffix';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ),
    );
  }
}

// ── 產品列表 ────────────────────────────────────────────────────────
class _ProductList extends ConsumerWidget {
  final SearchState state;
  final ScrollController scrollController;

  const _ProductList({
    required this.state,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontScaleProvider);
    // 原本 itemExtent 寫死 104 是為了捲動效能，但會把字級放大後的卡片內容
    // 裁掉（綠色 chip 被切）。中字級時保留原優化；其他字級放棄固定高度，
    // 讓 ListView 自動測量。700 筆資料下 lazy build 仍可接受。
    final itemExtent = fontScale == FontScale.medium ? 104.0 : null;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: state.items.length + (state.hasMore ? 1 : 0),
      itemExtent: itemExtent,
      addAutomaticKeepAlives: false, // 捲出視窗的 item 立即釋放，減少記憶體累積
      addRepaintBoundaries: true,
      cacheExtent: 600, // 預渲染上下 600px，減少邊緣 jank
      itemBuilder: (context, i) {
        if (i == state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = state.items[i];
        // 刻意不使用 key — 讓 Flutter 重用卡片的 RenderObject，大幅提升捲動效能
        return _ProductCard(
          id: item.id,
          brand: item.brand,
          model: item.model,
          certNumber: item.certNumber,
          visibleLight: item.visibleLight,
          heatRejection: item.heatRejection,
          imageUrl: item.imageUrl,
          imageLocalPath: item.imageLocalPath,
        );
      },
    );
  }
}

// ── 產品卡片 ────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final int id;
  final String brand;
  final String model;
  final String certNumber;
  final String? visibleLight;
  final String? heatRejection;
  final String? imageUrl;
  final String? imageLocalPath;

  const _ProductCard({
    super.key,
    required this.id,
    required this.brand,
    required this.model,
    required this.certNumber,
    this.visibleLight,
    this.heatRejection,
    this.imageUrl,
    this.imageLocalPath,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 縮圖（優先使用本機已下載圖片）
              _Thumbnail(
                localPath: imageLocalPath,
                url: imageUrl?.split(',').first.trim(),
              ),
              const SizedBox(width: 14),
              // 文字資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$brand  $model',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '認證號：$certNumber',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (visibleLight != null)
                          _StatChip(
                            label: '可見光',
                            value: visibleLight!,
                            color: _visibleLightColor(visibleLight!),
                          ),
                        if (heatRejection != null) ...[
                          const SizedBox(width: 6),
                          _StatChip(
                            label: '隔熱',
                            value: heatRejection!,
                            color: Colors.deepOrange.shade400,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 按鈕組
              SizedBox(
                width: 100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _FavoriteButton(id: id),
                    const SizedBox(width: 4),
                    _ComparisonButton(id: id),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 20),
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

// 獨立的收藏按鈕 — 只有此 widget 會因收藏狀態變更而重建
class _FavoriteButton extends ConsumerWidget {
  final int id;
  const _FavoriteButton({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds = ref.watch(favoriteIdsProvider);
    return favoriteIds.when(
      data: (ids) => IconButton(
        icon: Icon(
          ids.contains(id) ? Icons.favorite : Icons.favorite_border,
          color: ids.contains(id) ? Colors.red : null,
          size: 18,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () async {
          await ref.read(favoriteIdsProvider.notifier).toggleFavorite(id);
        },
      ),
      loading: () => const SizedBox(width: 20),
      error: (_, __) => const SizedBox(width: 20),
    );
  }
}

// 獨立的對比按鈕 — 只有此 widget 會因對比清單變更而重建
class _ComparisonButton extends ConsumerWidget {
  final int id;
  const _ComparisonButton({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisonIds = ref.watch(comparisonIdsProvider);
    final inList = comparisonIds.contains(id);
    return IconButton(
      icon: Icon(
        inList ? Icons.check_box : Icons.check_box_outline_blank,
        size: 18,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () async {
        if (inList) {
          ref.read(comparisonProvider.notifier).removeProduct(id);
        } else {
          await ref.read(comparisonProvider.notifier).addProduct(id);
        }
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? localPath;
  final String? url;
  const _Thumbnail({this.localPath, this.url});

  @override
  Widget build(BuildContext context) {
    // 優先使用本機已下載的圖片，避免重複連網
    // cacheWidth/cacheHeight 強制以縮圖尺寸解碼，避免載入完整解析度造成卷動卡頓
    if (!kIsWeb && localPath != null) {
      final file = File(localPath!);
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 56,
            height: 56,
            cacheWidth: 168, // 3x for high-DPI displays
            cacheHeight: 168,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _networkOrPlaceholder(context),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _networkOrPlaceholder(context),
      ),
    );
  }

  Widget _networkOrPlaceholder(BuildContext context) {
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url!,
        width: 56,
        height: 56,
        memCacheWidth: 168,
        memCacheHeight: 168,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        placeholder: (_, __) => _placeholder(context),
        errorWidget: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.local_car_wash, size: 28),
    );
  }
}

/// 依可見光分級回傳合格標識貼紙對應底色
/// （與規格內「70%Min 黃色貼紙 / 40%Min 灰色貼紙」配色一致）
Color _visibleLightColor(String value) {
  final v = value.replaceAll(' ', '');
  if (v.contains('70%以上')) {
    return const Color(0xFFFFEB3B); // 黃底（對應 70%Min 標貼）
  }
  if (v.contains('未達70%') || v.contains('40%')) {
    return const Color(0xFFE0E0E0); // 灰底（對應 40%Min 標貼）
  }
  // fallback：嘗試解析數字
  final numStr = v.replaceAll(RegExp(r'[^0-9.]'), '');
  final pct = double.tryParse(numStr);
  if (pct != null) {
    if (pct >= 70) return const Color(0xFFFFEB3B);
    if (pct >= 40) return const Color(0xFFE0E0E0);
  }
  return Colors.red.shade300;
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // 深色背景用白字，淺色背景用黑字
    final textColor = color.computeLuminance() > 0.4
        ? Colors.black87
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// ── 空狀態 ──────────────────────────────────────────────────────────
class _EmptyState extends StatefulWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  bool _fetchingMeta = false;

  Future<void> _onDownloadPressed() async {
    if (_fetchingMeta) return;
    setState(() => _fetchingMeta = true);

    ScraperMetadata? meta;
    String? errorMsg;
    try {
      meta = await CarSafetyScraper().fetchMetadata();
    } catch (e) {
      errorMsg = e.toString();
    } finally {
      if (mounted) setState(() => _fetchingMeta = false);
    }

    if (!mounted) return;

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得資料資訊：$errorMsg')),
      );
      return;
    }

    await _confirmAndSync(context, meta!);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            widget.query.isEmpty ? '資料庫尚無資料，請先同步' : '找不到「${widget.query}」的相關資料',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (widget.query.isEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _fetchingMeta ? null : _onDownloadPressed,
              icon: _fetchingMeta
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync),
              label: Text(_fetchingMeta ? '查詢中...' : '立即下載'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 錯誤橫幅 ────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── 下載進度對話框 ───────────────────────────────────────────────────
class _SyncProgressDialog extends ConsumerStatefulWidget {
  const _SyncProgressDialog();

  @override
  ConsumerState<_SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends ConsumerState<_SyncProgressDialog> {
  @override
  Widget build(BuildContext context) {
    // 監聽完成/失敗 → 自動關閉對話框
    ref.listen<AsyncValue<SyncState>>(syncStateProvider, (_, next) {
      next.whenData((state) {
        if ((state.status == SyncStatus.success ||
                state.status == SyncStatus.failed) &&
            mounted &&
            Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    });

    final syncState = ref.watch(syncStateProvider);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined),
            SizedBox(width: 8),
            Text('更新資料中'),
          ],
        ),
        content: syncState.when(
          data: (state) {
            final progress = state.progress > 0 ? state.progress : null;
            final msg = state.progressMessage ?? state.message ?? '處理中...';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 12),
                Text(msg),
                if (progress != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ],
            );
          },
          loading: () => Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              LinearProgressIndicator(),
              SizedBox(height: 12),
              Text('準備中...'),
            ],
          ),
          error: (_, __) => const Text('發生錯誤'),
        ),
      ),
    );
  }
}

/// 顯示確認對話框，確認後啟動下載並顯示進度
Future<void> _confirmAndSync(BuildContext context, ScraperMetadata meta) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('確認更新資料'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_outlined, size: 20),
              const SizedBox(width: 8),
              Text('線上資料總筆數：${meta.totalCount} 筆'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 20),
              const SizedBox(width: 8),
              Text(
                '發布時間：${DateFormat('yyyy-MM-dd HH:mm').format(meta.fetchedAt)}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('確定要下載更新嗎？（含圖片下載，需要一些時間）'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('確認下載'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    SyncService.instance.syncNow();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SyncProgressDialog(),
    );
  }
}

// ── 同步按鈕（含下載前確認對話框）───────────────────────────────────
class _SyncButton extends StatefulWidget {
  final SyncState state;
  const _SyncButton({required this.state});

  @override
  State<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<_SyncButton> {
  bool _fetchingMeta = false;

  Future<void> _onPressed() async {
    if (widget.state.status == SyncStatus.syncing || _fetchingMeta) return;

    setState(() => _fetchingMeta = true);

    ScraperMetadata? meta;
    String? errorMsg;

    try {
      meta = await CarSafetyScraper().fetchMetadata();
    } catch (e) {
      errorMsg = e.toString();
    } finally {
      if (mounted) setState(() => _fetchingMeta = false);
    }

    if (!mounted) return;

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得資料資訊：$errorMsg')),
      );
      return;
    }

    await _confirmAndSync(context, meta!);
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = widget.state.status == SyncStatus.syncing || _fetchingMeta;
    return IconButton(
      tooltip: isBusy ? '處理中...' : '立即更新資料',
      onPressed: isBusy ? null : _onPressed,
      icon: isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
    );
  }
}

// ── 詳細資料頁 ──────────────────────────────────────────────────────
class ProductDetailScreen extends ConsumerWidget {
  final int productId;
  const ProductDetailScreen({super.key, required this.productId});

  Future<({TintProduct? product, List<TintProduct> variants})> _loadData(
      dynamic repo) async {
    final product = await repo.getById(productId) as TintProduct?;
    if (product == null) return (product: null, variants: <TintProduct>[]);
    final variants = await AppDatabase.instance
        .getProductsByBrandModel(product.brand, product.model);
    return (product: product, variants: variants);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(tintRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('產品詳細資料')),
      body: FutureBuilder<({TintProduct? product, List<TintProduct> variants})>(
        future: _loadData(repo),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null || data.product == null) {
            return const Center(child: Text('找不到該產品'));
          }
          return _DetailBody(product: data.product!, variants: data.variants);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final TintProduct product;
  final List<TintProduct> variants;
  const _DetailBody({required this.product, this.variants = const []});

  /// 從所有 variants 收集圖片，每筆附上 LabelMethod 標籤。
  ///
  /// 以 imageUrls 為基準逐張決定來源：
  ///   - 用 localPathForUrl(url) 根據 URL hash 找到對應本機路徑（不依賴 index）
  ///   - 本機檔案存在 → 顯示本機；否則 → fallback 網路 URL
  ///
  /// 若 imageUrls 為空但有本機路徑（舊版資料），直接顯示全部本機路徑。
  List<({String label, String path, bool isLocal})> _allImages() {
    final result = <({String label, String path, bool isLocal})>[];
    final all = variants.isNotEmpty ? variants : [product];

    for (final v in all) {
      final label = v.standard ?? '';
      final networkUrls = v.imageUrls;

      if (networkUrls.isEmpty) {
        // 舊版資料：無 imageUrls，只有本機路徑
        if (!kIsWeb) {
          for (final lp in v.imageLocalPaths) {
            result.add((label: label, path: lp, isLocal: true));
          }
        }
        continue;
      }

      for (final url in networkUrls) {
        // 過濾範例圖，只顯示業者自行烙印圖
        if (url.contains('範例')) continue;
        if (!kIsWeb) {
          final lp = v.localPathForUrl(url);
          if (lp != null && File(lp).existsSync()) {
            result.add((label: label, path: lp, isLocal: true));
            continue;
          }
        }
        // 本機無檔案 → 使用網路 URL
        result.add((label: label, path: url, isLocal: false));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final images = _allImages();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 合格標識圖片（本機優先；未下載者 fallback 網路 URL；無烙印圖顯示提示）
        if (images.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: images.map((img) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: img.isLocal
                      ? Image.file(File(img.path),
                          height: 180, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink())
                      : CachedNetworkImage(
                          imageUrl: img.path,
                          height: 180,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const SizedBox(
                            width: 120,
                            height: 180,
                            child: Center(
                                child: CircularProgressIndicator()),
                          ),
                          errorWidget: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                ),
                if (img.label.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(img.label,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ],
              ],
            )).toList(),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.4), width: 1),
            ),
            child: const Column(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 28),
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
        const SizedBox(height: 20),

        // 標題
        Text(
          '${product.brand}  ${product.model}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '認證號：${product.certNumber}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const Divider(height: 32),

        // 規格表
        _SpecTable(product: product),

        // 更新時間
        if (product.updatedAt != null) ...[
          const SizedBox(height: 16),
          Text(
            '資料更新：${DateFormat('yyyy-MM-dd HH:mm').format(product.updatedAt!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ],
    );
  }
}

class _SpecTable extends StatelessWidget {
  final TintProduct product;
  const _SpecTable({required this.product});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (product.visibleLight != null)
        MapEntry('可見光穿透率', product.visibleLight!),
      if (product.uvRejection != null)
        MapEntry('紫外線阻隔率', product.uvRejection!),
      if (product.irRejection != null)
        MapEntry('紅外線阻隔率', product.irRejection!),
      if (product.heatRejection != null)
        MapEntry('總熱能阻隔率', product.heatRejection!),
      if (product.standard != null)
        MapEntry('符合標準', product.standard!),
    ];

    if (rows.isEmpty) {
      return const Text('無詳細規格資料');
    }

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      border: TableBorder.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      children: rows.map((entry) {
        return TableRow(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(entry.key,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(entry.value),
          ),
        ]);
      }).toList(),
    );
  }
}
