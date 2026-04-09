import 'dart:io';
import 'dart:typed_data';

import '../../data/models/tint_product.dart';
import 'image_hasher.dart';

// ── 比對來源 ──────────────────────────────────────────────────────

enum MatchSource {
  /// OCR 文字辨識命中
  ocr,
  /// 圖像相似度比對（備援）
  imageSimilarity,
}

// ── 單筆比對結果 ──────────────────────────────────────────────────

class MatchResult {
  final TintProduct product;

  /// 0.0 ~ 1.0
  final double similarity;

  /// 本筆結果的來源
  final MatchSource source;

  /// OCR 辨識出的原始文字（僅 source == ocr 時有值）
  final String? ocrText;

  const MatchResult({
    required this.product,
    required this.similarity,
    this.source = MatchSource.imageSimilarity,
    this.ocrText,
  });
}

// ── 圖像相似度計算器 ──────────────────────────────────────────────

class SimilarityCalculator {
  static const double threshold = 0.70;
  static const int topN = 5;

  /// 兩階段圖像比對（圖像相似度備援用）：
  ///   Phase 1 – pHash 快速篩選
  ///   Phase 2 – 色彩直方圖精排
  static Future<List<MatchResult>> findMatches({
    required Uint8List queryBytes,
    required List<TintProduct> products,
  }) async {
    final queryHash = ImageHasher.hashFromBytes(queryBytes);
    if (queryHash == null) return [];

    // Phase 1：pHash 篩選
    const looseCutoff = 0.45;
    final candidates = <({TintProduct product, double pScore})>[];
    for (final product in products) {
      final hash = product.imagePhash;
      if (hash == null || hash.isEmpty) continue;
      final score = ImageHasher.pHashSimilarity(queryHash, hash);
      if (score >= looseCutoff) {
        candidates.add((product: product, pScore: score));
      }
    }

    candidates.sort((a, b) => b.pScore.compareTo(a.pScore));
    final top20 = candidates.take(20).toList();
    if (top20.isEmpty) return [];

    // Phase 2：直方圖精排
    final queryHist = ImageHasher.histFromBytes(queryBytes);
    final results = <MatchResult>[];

    for (final candidate in top20) {
      double finalScore = candidate.pScore;
      if (queryHist != null) {
        final localPath = candidate.product.firstImageLocalPath;
        if (localPath != null) {
          try {
            final file = File(localPath);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final prodHist = ImageHasher.histFromBytes(bytes);
              if (prodHist != null) {
                final histScore =
                    ImageHasher.histogramSimilarity(queryHist, prodHist);
                finalScore = candidate.pScore * 0.6 + histScore * 0.4;
              }
            }
          } catch (_) {}
        }
      }
      if (finalScore >= threshold) {
        results.add(MatchResult(
          product: candidate.product,
          similarity: finalScore,
          source: MatchSource.imageSimilarity,
        ));
      }
    }

    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    return results.take(topN).toList();
  }
}
