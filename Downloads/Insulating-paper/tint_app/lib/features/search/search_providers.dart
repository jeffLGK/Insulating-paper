// lib/features/search/search_providers.dart
//
// Riverpod Provider 定義，供全 APP 共享狀態。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/tint_repository.dart';
import '../../features/sync/sync_service.dart';
import 'advanced_filters_providers.dart';

// ── Repository provider ─────────────────────────────────────────────
final tintRepositoryProvider = Provider<TintRepository>((ref) {
  return TintRepository();
});

// ── 品牌清單 ────────────────────────────────────────────────────────
final brandsProvider = FutureProvider<List<String>>((ref) async {
  return ref.read(tintRepositoryProvider).getBrands();
});

// ── 各廠牌筆數 Map<品牌名稱, 筆數> ─────────────────────────────────
final brandCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(tintRepositoryProvider).getBrandCounts();
});

// ── 搜尋狀態 ────────────────────────────────────────────────────────
class SearchState {
  final String query;
  final String? brandFilter;
  final List<_ProductItem> items;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? errorMessage;
  final int? totalCount; // 資料庫實際總筆數（無搜尋時使用）

  const SearchState({
    this.query = '',
    this.brandFilter,
    this.items = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.page = 0,
    this.errorMessage,
    this.totalCount,
  });

  SearchState copyWith({
    String? query,
    String? brandFilter,
    List<_ProductItem>? items,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? errorMessage,
    int? totalCount,
    bool clearBrand = false,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      brandFilter: clearBrand ? null : (brandFilter ?? this.brandFilter),
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

// 僅對 UI 暴露所需欄位的 view model
class _ProductItem {
  final int id;
  final String brand;
  final String model;
  final String certNumber;
  final String? visibleLight;
  final String? heatRejection;
  final String? imageUrl;
  final String? imageLocalPath;

  const _ProductItem({
    required this.id,
    required this.brand,
    required this.model,
    required this.certNumber,
    this.visibleLight,
    this.heatRejection,
    this.imageUrl,
    this.imageLocalPath,
  });
}

// ── SearchNotifier ──────────────────────────────────────────────────
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repo, this._ref) : super(const SearchState()) {
    // 啟動時載入全部資料
    _load(reset: true);
  }

  final TintRepository _repo;
  final Ref _ref;
  static const int _pageSize = 30;

  // 防抖用
  DateTime? _lastSearchTrigger;

  // ── 公開 API ──────────────────────────────────────────────────

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _debounceSearch();
  }

  void setBrandFilter(String? brand) {
    state = state.copyWith(brandFilter: brand, clearBrand: brand == null);
    _load(reset: true);
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _load(reset: false);
  }

  Future<void> refresh() async {
    await _load(reset: true);
  }

  // ── 私有 ──────────────────────────────────────────────────────

  void _debounceSearch() {
    final trigger = _lastSearchTrigger = DateTime.now();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_lastSearchTrigger == trigger) {
        _load(reset: true);
      }
    });
  }

  Future<void> _load({required bool reset}) async {
    if (state.isLoading) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      page: reset ? 0 : state.page,
      items: reset ? [] : state.items,
    );

    try {
      final filters = _ref.read(advancedFiltersProvider);
      final brandList = filters.selectedBrands.isEmpty ? null : filters.selectedBrands;
      final hasAdvanced = filters.hasActiveFilters;
      final isSearch = state.query.trim().isNotEmpty
          || state.brandFilter != null
          || hasAdvanced;
      final result = isSearch
          ? await _repo.search(
              query: state.query,
              brandFilter: state.brandFilter,
              brandList: brandList,
              page: reset ? 0 : state.page,
              pageSize: _pageSize,
            )
          : await _repo.getAll(page: reset ? 0 : state.page, pageSize: _pageSize);

      // 首次載入或重置時取得總筆數（無搜尋且無品牌篩選才顯示全部總數）
      final totalCount = (reset && !isSearch)
          ? await _repo.getTotalCount()
          : state.totalCount;

      // 進階篩選：可見光僅分兩級（符合40%／符合70%），以 client-side 過濾
      final stds = filters.visibleLightStandards;
      final filtered = stds.isEmpty
          ? result.items
          : result.items.where((p) {
              final v = (p.visibleLight ?? '').replaceAll(' ', '');
              final is70 = v.contains('70%以上');
              final is40 = v.contains('未達70%') || v.contains('40%');
              if (stds.contains(VisibleLightStandard.pct70) && is70) return true;
              if (stds.contains(VisibleLightStandard.pct40) && is40) return true;
              return false;
            }).toList();

      final newItems = filtered.map((p) => _ProductItem(
        id: p.id ?? 0,
        brand: p.brand,
        model: p.model,
        certNumber: p.certNumber,
        visibleLight: p.visibleLight,
        heatRejection: p.heatRejection,
        imageUrl: p.selfBrandedImageUrl,
        imageLocalPath: p.selfBrandedImageLocalPath,
      )).toList();

      state = state.copyWith(
        items: reset ? newItems : [...state.items, ...newItems],
        isLoading: false,
        hasMore: result.hasMore,
        page: result.page + 1,
        totalCount: totalCount,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '搜尋時發生錯誤：$e',
      );
    }
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final notifier = SearchNotifier(ref.read(tintRepositoryProvider), ref);

  // 同步成功後自動刷新搜尋結果與品牌清單
  ref.listen<AsyncValue<SyncState>>(syncStateProvider, (previous, next) {
    next.whenData((syncState) {
      if (syncState.status == SyncStatus.success) {
        notifier.refresh();
        ref.invalidate(brandsProvider);
        ref.invalidate(brandCountsProvider);
      }
    });
  });

  // 進階篩選變更後自動重新載入
  ref.listen<FilterState>(advancedFiltersProvider, (previous, next) {
    notifier.refresh();
  });

  return notifier;
});

// ── 同步狀態 ────────────────────────────────────────────────────────
final syncStateProvider = StreamProvider<SyncState>((ref) {
  return SyncService.instance.stateStream;
});

final lastSyncTimeProvider = FutureProvider<DateTime?>((ref) {
  return SyncService.instance.getLastSyncTime();
});
