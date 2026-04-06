// 產品對比畫面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'comparison_providers.dart';

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(comparisonProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('產品對比'),
        actions: [
          if (products.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                ref.read(comparisonProvider.notifier).clear();
              },
              tooltip: '清空對比',
            ),
        ],
      ),
      body: products.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare, size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('選擇最少 2 個產品開始對比'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('回到搜尋'),
                  ),
                ],
              ),
            )
          : products.length == 1
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.compare, size: 64, color: colorScheme.outline),
                      const SizedBox(height: 16),
                      const Text('至少需要 2 個產品進行對比'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('繼續選擇'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: _ComparisonTable(products: products),
                  ),
                ),
    );
  }
}

class _ComparisonTable extends ConsumerWidget {
  final List products;

  const _ComparisonTable({required this.products});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DataTable(
        border: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        columns: [
          const DataColumn(label: Text('規格')),
          ...products.map<DataColumn>((product) {
            return DataColumn(
              label: Expanded(
                child: _ProductHeader(product: product),
              ),
            );
          }),
        ],
        rows: _buildRows(context, ref),
      ),
    );
  }

  List<DataRow> _buildRows(BuildContext context, WidgetRef ref) {
    final specs = [
      ('品牌', (p) => p.brand),
      ('型號', (p) => p.model),
      ('認證號', (p) => p.certNumber),
      ('可見光穿透率', (p) => p.visibleLight ?? '—'),
      ('紫外線阻隔率', (p) => p.uvRejection ?? '—'),
      ('紅外線阻隔率', (p) => p.irRejection ?? '—'),
      ('總熱能阻隔率', (p) => p.heatRejection ?? '—'),
      ('符合標準', (p) => p.standard ?? '—'),
    ];

    return specs.map((spec) {
      final label = spec.$1;
      final getter = spec.$2;
      return DataRow(
        cells: [
          DataCell(
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...products.map<DataCell>((product) {
            return DataCell(
              Text(
                getter(product),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }),
        ],
      );
    }).toList();
  }
}

class _ProductHeader extends ConsumerWidget {
  final product;

  const _ProductHeader({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '${product.brand}\n${product.model}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            icon: const Icon(Icons.close),
            iconSize: 16,
            padding: EdgeInsets.zero,
            onPressed: () {
              ref.read(comparisonProvider.notifier).removeProduct(product.id);
            },
          ),
        ),
      ],
    );
  }
}
