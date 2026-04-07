// lib/features/search/search_screen.dart
//
// 關鍵字搜尋畫面：搜尋框 + 品牌篩選 + 無限捲動列表

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import 'search_providers.dart';
import '../sync/sync_service.dart';
import '../favorites/favorites_providers.dart';
import '../comparison/comparison_providers.dart';
import '../comparison/comparison_screen.dart';
import 'advanced_filters_providers.dart';
import 'advanced_filters_sheet.dart';
import '../../data/models/tint_product.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late RefreshController _refreshController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshController = RefreshController(initialRefresh: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _refreshController.dispose();
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
    _refreshController.refreshCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final syncStream = ref.watch(syncStateProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
          const SizedBox(width: 8),
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
                    : SmartRefresher(
                        controller: _refreshController,
                        onRefresh: _onRefresh,
                        header: const WaterDropHeader(
                          idleIcon: Icon(Icons.cloud_download_outlined),
                        ),
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
    final current = ref.watch(searchProvider).brandFilter;

    return brands.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
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
              return FilterChip(
                label: Text(isAll ? '全部' : brand!),
                selected: selected,
                onSelected: (_) {
                  ref.read(searchProvider.notifier).setBrandFilter(brand);
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
      final suffix = state.hasMore ? '（載入中…）' : ' 筆';
      label = '共 $total$suffix';
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
class _ProductList extends StatelessWidget {
  final SearchState state;
  final ScrollController scrollController;

  const _ProductList({
    required this.state,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: state.items.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = state.items[i];

        // Simple fade-in animation for list items
        return AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 300),
          child: _ProductCard(
            id: item.id,
            brand: item.brand,
            model: item.model,
            certNumber: item.certNumber,
            visibleLight: item.visibleLight,
            heatRejection: item.heatRejection,
            imageUrl: item.imageUrl,
          ),
        );
      },
    );
  }
}

// ── 產品卡片 ────────────────────────────────────────────────────────
class _ProductCard extends ConsumerWidget {
  final int id;
  final String brand;
  final String model;
  final String certNumber;
  final String? visibleLight;
  final String? heatRejection;
  final String? imageUrl;

  const _ProductCard({
    required this.id,
    required this.brand,
    required this.model,
    required this.certNumber,
    this.visibleLight,
    this.heatRejection,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final favoriteIds = ref.watch(favoriteIdsProvider);
    final comparisonIds = ref.watch(comparisonIdsProvider);

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
              // 縮圖
              _Thumbnail(url: imageUrl),
              const SizedBox(width: 14),
              // 文字資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$brand  $model',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
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
                            color: Colors.blue.shade100,
                          ),
                        if (heatRejection != null) ...[
                          const SizedBox(width: 6),
                          _StatChip(
                            label: '隔熱',
                            value: heatRejection!,
                            color: Colors.orange.shade100,
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
                    // 收藏按鈕
                    favoriteIds.when(
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
                    ),
                    const SizedBox(width: 4),
                    // 對比按鈕
                    IconButton(
                      icon: Icon(
                        comparisonIds.contains(id) ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        if (comparisonIds.contains(id)) {
                          ref.read(comparisonProvider.notifier).removeProduct(id);
                        } else {
                          await ref.read(comparisonProvider.notifier).addProduct(id);
                        }
                      },
                    ),
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

class _Thumbnail extends StatelessWidget {
  final String? url;
  const _Thumbnail({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              placeholder: (_, __) => _placeholder(context),
              errorWidget: (_, __, ___) => _placeholder(context),
            )
          : _placeholder(context),
    );
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ── 空狀態 ──────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

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
            query.isEmpty ? '資料庫尚無資料，請先同步' : '找不到「$query」的相關資料',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (query.isEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => SyncService.instance.syncNow(),
              icon: const Icon(Icons.sync),
              label: const Text('立即下載'),
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

// ── 同步按鈕 ────────────────────────────────────────────────────────
class _SyncButton extends StatelessWidget {
  final SyncState state;
  const _SyncButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final isSyncing = state.status == SyncStatus.syncing;
    return IconButton(
      tooltip: isSyncing ? '同步中...' : '立即更新資料',
      onPressed: isSyncing
          ? null
          : () => SyncService.instance.syncNow(),
      icon: isSyncing
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(tintRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('產品詳細資料')),
      body: FutureBuilder<TintProduct?>(
        future: repo.getById(productId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final product = snap.data;
          if (product == null) {
            return const Center(child: Text('找不到該產品'));
          }
          return _DetailBody(product: product);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final TintProduct product;
  const _DetailBody({required this.product});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 標籤圖片
        if (product.imageUrl != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl!,
                height: 180,
                fit: BoxFit.contain,
              ),
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
