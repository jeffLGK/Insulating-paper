// 收藏功能的 Riverpod providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../data/repositories/favorites_repository.dart';

/// FavoritesRepository provider
final favoritesRepositoryProvider = FutureProvider<FavoritesRepository>((ref) async {
  final db = await AppDatabase.instance.database;
  return FavoritesRepository(db);
});

/// 檢查某個產品是否已收藏
final isFavoriteProvider = FutureProvider.family<bool, int>((ref, productId) async {
  final repo = await ref.watch(favoritesRepositoryProvider.future);
  return repo.isFavorite(productId);
});

/// 所有收藏產品的 ID
final favoriteIdsProvider = StateNotifierProvider<FavoriteIdsNotifier, AsyncValue<Set<int>>>((ref) {
  return FavoriteIdsNotifier(ref);
});

class FavoriteIdsNotifier extends StateNotifier<AsyncValue<Set<int>>> {
  final Ref _ref;

  FavoriteIdsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    state = const AsyncValue.loading();
    try {
      final repo = await _ref.read(favoritesRepositoryProvider.future);
      final ids = await repo.getFavoriteIds();
      state = AsyncValue.data(ids.toSet());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加收藏
  Future<void> addFavorite(int productId) async {
    try {
      final repo = await _ref.read(favoritesRepositoryProvider.future);
      await repo.addFavorite(productId);
      // 更新本地狀態
      state.whenData((favorites) {
        state = AsyncValue.data({...favorites, productId});
      });
    } catch (e) {
      rethrow;
    }
  }

  /// 移除收藏
  Future<void> removeFavorite(int productId) async {
    try {
      final repo = await _ref.read(favoritesRepositoryProvider.future);
      await repo.removeFavorite(productId);
      // 更新本地狀態
      state.whenData((favorites) {
        final updated = {...favorites};
        updated.remove(productId);
        state = AsyncValue.data(updated);
      });
    } catch (e) {
      rethrow;
    }
  }

  /// 切換收藏狀態
  Future<bool> toggleFavorite(int productId) async {
    try {
      final isFav = await _ref.read(favoritesRepositoryProvider.future).then((repo) => repo.isFavorite(productId));
      if (isFav) {
        await removeFavorite(productId);
        return false;
      } else {
        await addFavorite(productId);
        return true;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 刷新收藏列表
  Future<void> refresh() async {
    await _init();
  }
}

/// 收藏數量
final favoritesCountProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(favoritesRepositoryProvider.future);
  return repo.getFavoriteCount();
});
