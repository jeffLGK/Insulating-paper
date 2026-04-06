// 收藏列表畫面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'favorites_providers.dart';
import '../search/search_providers.dart';
import '../../data/models/tint_product.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds = ref.watch(favoriteIdsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: favoriteIds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              const Text('載入收藏時發生錯誤'),
            ],
          ),
        ),
        data: (ids) => ids.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    const Text('還沒有收藏任何產品'),
                  ],
                ),
              )
            : _FavoritesList(
                productIds: ids.toList(),
                ref: ref,
              ),
      ),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  final List<int> productIds;
  final WidgetRef ref;

  const _FavoritesList({
    required this.productIds,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tintRepo = ref.watch(tintRepositoryProvider);

    return FutureBuilder<List<TintProduct?>>(
      future: Future.wait(productIds.map((id) => tintRepo.getById(id))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data?.whereType<TintProduct>().toList() ?? [];
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                const Text('還沒有收藏任何產品'),
              ],
            ),
          );
        }

        final validProducts = products.where((p) => p.id != null).toList();
        if (validProducts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                const Text('還沒有收藏任何產品'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: validProducts.length,
          itemBuilder: (context, i) {
            final product = validProducts[i];
            final productId = product.id!; // Safe because of the where clause above
            return _FavoritesCard(
              product: product,
              onRemove: () async {
                await ref.read(favoriteIdsProvider.notifier).removeFavorite(productId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已移除收藏')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

class _FavoritesCard extends StatelessWidget {
  final TintProduct product;
  final VoidCallback onRemove;

  const _FavoritesCard({
    required this.product,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 縮圖
            _Thumbnail(url: product.imageUrl),
            const SizedBox(width: 14),
            // 文字資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.brand}  ${product.model}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '認證號：${product.certNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (product.visibleLight != null)
                        _StatChip(
                          label: '可見光',
                          value: product.visibleLight!,
                          color: Colors.blue.shade100,
                        ),
                      if (product.heatRejection != null) ...[
                        const SizedBox(width: 6),
                        _StatChip(
                          label: '隔熱',
                          value: product.heatRejection!,
                          color: Colors.orange.shade100,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 移除按鈕
            IconButton(
              icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onRemove,
            ),
          ],
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
