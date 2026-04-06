// 收藏產品的存儲和查詢

import 'package:sqflite/sqflite.dart';
import '../models/tint_product.dart';

/// 管理收藏產品的存儲和查詢
class FavoritesRepository {
  final Database _db;

  FavoritesRepository(this._db);

  /// 添加收藏
  Future<void> addFavorite(int productId) async {
    await _db.insert(
      'favorites',
      {'product_id': productId, 'added_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 移除收藏
  Future<void> removeFavorite(int productId) async {
    await _db.delete('favorites', where: 'product_id = ?', whereArgs: [productId]);
  }

  /// 檢查是否已收藏
  Future<bool> isFavorite(int productId) async {
    final result = await _db.query(
      'favorites',
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// 獲取所有收藏產品ID
  Future<List<int>> getFavoriteIds() async {
    final result = await _db.query('favorites');
    return result.map((row) => row['product_id'] as int).toList();
  }

  /// 批量檢查產品是否收藏
  Future<Set<int>> checkFavorites(List<int> productIds) async {
    if (productIds.isEmpty) return {};
    final placeholders = List.filled(productIds.length, '?').join(',');
    final result = await _db.query(
      'favorites',
      where: 'product_id IN ($placeholders)',
      whereArgs: productIds,
    );
    return result.map((row) => row['product_id'] as int).toSet();
  }

  /// 清空所有收藏
  Future<void> clearAll() async {
    await _db.delete('favorites');
  }

  /// 獲取收藏數量
  Future<int> getFavoriteCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM favorites');
    return (result.first['count'] as int?) ?? 0;
  }
}
