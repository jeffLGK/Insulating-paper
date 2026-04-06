// 產品對比功能的 Riverpod providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/tint_product.dart';
import '../search/search_providers.dart';

/// 對比產品列表的 Provider
final comparisonProvider = StateNotifierProvider<ComparisonNotifier, List<TintProduct>>((ref) {
  return ComparisonNotifier(ref);
});

class ComparisonNotifier extends StateNotifier<List<TintProduct>> {
  final Ref _ref;

  ComparisonNotifier(this._ref) : super([]);

  /// 添加產品到對比
  Future<void> addProduct(int productId) async {
    try {
      final repo = _ref.read(tintRepositoryProvider);
      final product = await repo.getById(productId);

      if (product != null) {
        // 檢查是否已經在對比列表中
        if (!state.any((p) => p.id == product.id)) {
          // 最多對比 4 個產品
          if (state.length < 4) {
            state = [...state, product];
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 移除產品從對比
  void removeProduct(int productId) {
    state = state.where((p) => p.id != productId).toList();
  }

  /// 檢查產品是否在對比列表中
  bool isInComparison(int productId) {
    return state.any((p) => p.id == productId);
  }

  /// 清空對比列表
  void clear() {
    state = [];
  }

  /// 獲取對比產品數
  int getComparisonCount() {
    return state.length;
  }
}

/// 對比產品 ID 集合（用於 UI 中快速檢查）
final comparisonIdsProvider = Provider<Set<int>>((ref) {
  final products = ref.watch(comparisonProvider);
  return products.map((p) => p.id).whereType<int>().toSet();
});
