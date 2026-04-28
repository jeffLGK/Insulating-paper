// lib/features/settings/font_scale_sheet.dart
//
// 字體大小選擇 Bottom Sheet。
// 使用者點選後立即套用並儲存到 SharedPreferences。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/font_scale.dart';

Future<void> showFontScaleSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const _FontScaleSheet(),
  );
}

class _FontScaleSheet extends ConsumerWidget {
  const _FontScaleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fontScaleProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.format_size, color: Colors.blueGrey),
                  SizedBox(width: 8),
                  Text(
                    '字體大小',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '會同步影響整個 APP 的所有文字。',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            for (final scale in FontScale.values)
              _ScaleOption(
                scale: scale,
                selected: scale == current,
                onTap: () async {
                  await ref.read(fontScaleProvider.notifier).set(scale);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ScaleOption extends StatelessWidget {
  final FontScale scale;
  final bool selected;
  final VoidCallback onTap;

  const _ScaleOption({
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withOpacity(0.4)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              // 預覽：用 MediaQuery.textScaler 局部 override，讓使用者看到實際縮放效果
              SizedBox(
                width: 64,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale.factor)),
                  child: const Text(
                    'Aa 中',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          scale.label,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        if (scale == FontScale.medium) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '（預設）',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '× ${scale.factor.toStringAsFixed(2)}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
