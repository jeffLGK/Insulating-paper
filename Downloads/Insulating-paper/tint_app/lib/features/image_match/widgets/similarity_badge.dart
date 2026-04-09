import 'package:flutter/material.dart';

/// 相似度／吻合度百分比徽章
class SimilarityBadge extends StatelessWidget {
  final double similarity;
  final double fontSize;

  /// 顯示在百分比後的說明文字，預設「相似」
  final String label;

  const SimilarityBadge({
    super.key,
    required this.similarity,
    this.fontSize = 20,
    this.label = '相似',
  });

  Color _color() {
    if (similarity >= 0.90) return Colors.green;
    if (similarity >= 0.80) return Colors.lightGreen;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (similarity * 100).toStringAsFixed(1);
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, color: c, size: fontSize + 2),
          const SizedBox(width: 6),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: fontSize - 4, color: c),
          ),
        ],
      ),
    );
  }
}
