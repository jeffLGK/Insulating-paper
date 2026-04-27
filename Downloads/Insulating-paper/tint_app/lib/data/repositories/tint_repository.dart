// lib/data/repositories/tint_repository.dart
//
// Repository 是 UI 層和資料層之間的單一窗口。
// UI 只跟 TintRepository 說話，不直接碰 DB 或 Scraper。

import '../models/tint_product.dart';
import '../../core/database/app_database.dart';

class TintRepository {
  TintRepository({AppDatabase? db})
      : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  // ── 查詢 ────────────────────────────────────────────────────────

  /// 全文搜尋，支援多關鍵字（空格分隔）與品牌篩選
  Future<SearchResult> search({
    required String query,
    String? brandFilter,
    Set<String>? brandList,
    int page = 0,
    int pageSize = 30,
  }) async {
    final products = await _db.searchProducts(
      query,
      limit: pageSize,
      offset: page * pageSize,
      brandFilter: brandFilter,
      brandList: brandList,
    );
    return SearchResult(
      items: products,
      query: query,
      page: page,
      hasMore: products.length == pageSize,
    );
  }

  /// 分頁取全部（搜尋框為空時使用）
  Future<SearchResult> getAll({
    int page = 0,
    int pageSize = 30,
    Set<String>? brandList,
  }) async {
    final products = await _db.getAllProducts(
      limit: pageSize,
      offset: page * pageSize,
      brandList: brandList,
    );
    return SearchResult(
      items: products,
      query: '',
      page: page,
      hasMore: products.length == pageSize,
    );
  }

  /// 取得所有品牌（供篩選下拉清單）
  Future<List<String>> getBrands() => _db.getAllBrands();

  /// 取得各廠牌名稱與其產品筆數
  Future<Map<String, int>> getBrandCounts() => _db.getBrandCounts();

  /// 依 id 取單筆詳細資料
  Future<TintProduct?> getById(int id) => _db.getProductById(id);

  /// 資料庫中的總筆數
  Future<int> getTotalCount() => _db.getProductCount();
}

// ── 搜尋結果封裝 ────────────────────────────────────────────────────
class SearchResult {
  final List<TintProduct> items;
  final String query;
  final int page;
  final bool hasMore;

  const SearchResult({
    required this.items,
    required this.query,
    required this.page,
    required this.hasMore,
  });

  bool get isEmpty => items.isEmpty;
  int get count => items.length;

  SearchResult copyWithMore(List<TintProduct> moreItems) {
    return SearchResult(
      items: [...items, ...moreItems],
      query: query,
      page: page + 1,
      hasMore: moreItems.length == items.length,
    );
  }
}
