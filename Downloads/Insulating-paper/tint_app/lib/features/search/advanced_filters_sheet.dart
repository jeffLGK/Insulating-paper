// 高級篩選底部表單

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'advanced_filters_providers.dart';
import 'search_providers.dart';

class AdvancedFiltersSheet extends ConsumerWidget {
  const AdvancedFiltersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(advancedFiltersProvider);
    final brands = ref.watch(brandsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // ── 標題欄 ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '進階篩選',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (filterState.hasActiveFilters)
                    TextButton.icon(
                      onPressed: () {
                        ref.read(advancedFiltersProvider.notifier).reset();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重置'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 0),

            // ── 內容區 ────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // 品牌篩選
                  brands.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Text('無法載入品牌列表'),
                    data: (brandList) => _BrandFilter(
                      brands: brandList,
                      selectedBrands: filterState.selectedBrands,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 可見光範圍
                  _RangeFilter(
                    title: '可見光穿透率範圍',
                    minValue: filterState.minVisibleLight,
                    maxValue: filterState.maxVisibleLight,
                    onChanged: (min, max) {
                      ref.read(advancedFiltersProvider.notifier).setVisibleLightRange(min, max);
                    },
                  ),
                  const SizedBox(height: 24),

                  // 隔熱範圍
                  _RangeFilter(
                    title: '總熱能阻隔率範圍',
                    minValue: filterState.minHeatRejection,
                    maxValue: filterState.maxHeatRejection,
                    onChanged: (min, max) {
                      ref.read(advancedFiltersProvider.notifier).setHeatRejectionRange(min, max);
                    },
                  ),
                ],
              ),
            ),

            // ── 按鈕欄 ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('套用篩選'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandFilter extends ConsumerWidget {
  final List<String> brands;
  final Set<String> selectedBrands;

  const _BrandFilter({
    required this.brands,
    required this.selectedBrands,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '品牌',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final brand in brands)
              FilterChip(
                selected: selectedBrands.contains(brand),
                label: Text(brand),
                onSelected: (_) {
                  ref.read(advancedFiltersProvider.notifier).toggleBrand(brand);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _RangeFilter extends StatefulWidget {
  final String title;
  final String? minValue;
  final String? maxValue;
  final Function(String?, String?) onChanged;

  const _RangeFilter({
    required this.title,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  @override
  State<_RangeFilter> createState() => _RangeFilterState();
}

class _RangeFilterState extends State<_RangeFilter> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(text: widget.minValue ?? '');
    _maxController = TextEditingController(text: widget.maxValue ?? '');
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _updateRange() {
    widget.onChanged(
      _minController.text.isEmpty ? null : _minController.text,
      _maxController.text.isEmpty ? null : _maxController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '最小值',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) => _updateRange(),
              ),
            ),
            const SizedBox(width: 8),
            const Text('~'),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maxController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '最大值',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) => _updateRange(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
