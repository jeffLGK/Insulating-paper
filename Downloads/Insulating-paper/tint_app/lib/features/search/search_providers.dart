// lib/features/search/search_providers.dart
//
// Riverpod Provider 定義，供全 APP 共享狀態。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/tint_repository.dart';
import '../../features/sync/sync_service.dart';

// ── Repository provider ─────────────────────────────────────────────
final tintRepositoryProvider = Provider<TintRepository>((ref) {
  return TintRepository();
});

// ── 品牌清單 ────────────────────────────────────────────────────────
final brandsProvider = FutureProvider<List<String>>((ref) async {
  return ref.read(tintRepositoryProvider).getBrands();
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

  const _ProductItem({
    required this.id,
    required this.brand,
    required this.model,
    required this.certNumber,
    this.visibleLight,
    this.heatRejection,
    this.imageUrl,
  });
}

// ── SearchNotifier ──────────────────────────────────────────────────
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repo) : super(const SearchState()) {
    // 啟動時載入全部資料
    _load(reset: true);
  }

  final TintRepository _repo;
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
      final isSearch = state.query.trim().isNotEmpty;
      final result = isSearch
          ? await _repo.search(
              query: state.query,
              brandFilter: state.brandFilter,
              page: reset ? 0 : state.page,
              pageSize: _pageSize,
            )
          : await _repo.getAll(page: reset ? 0 : state.page, pageSize: _pageSize);

      // 首次載入或重置時取得總筆數
      final totalCount = (reset && !isSearch)
          ? await _repo.getTotalCount()
          : state.totalCount;

      final newItems = result.items.map((p) => _ProductItem(
        id: p.id ?? 0,
        brand: p.brand,
        model: p.model,
        certNumber: p.certNumber,
        visibleLight: p.visibleLight,
        heatRejection: p.heatRejection,
        imageUrl: p.imageUrl,
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
  final notifier = SearchNotifier(ref.read(tintRepositoryProvider));

  // 同步成功後自動刷新搜尋結果與品牌清單
  ref.listen<AsyncValue<SyncState>>(syncStateProvider, (previous, next) {
    next.whenData((syncState) {
      if (syncState.status == SyncStatus.success) {
        notifier.refresh();
        ref.invalidate(brandsProvider);
      }
    });
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
