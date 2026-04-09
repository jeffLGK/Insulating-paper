import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/image/similarity_calculator.dart';
import '../../core/ocr/label_text_parser.dart';
import '../../core/ocr/ocr_service.dart';
import '../../data/models/tint_product.dart';

export '../../core/image/similarity_calculator.dart' show MatchResult, MatchSource;

// ── 狀態定義 ────────────────────────────────────────────────────

enum MatchStatus { idle, loading, done, noMatch, error }

class ImageMatchState {
  final MatchStatus status;
  final List<MatchResult> results;
  final Uint8List? queryBytes;
  final String? errorMessage;

  /// 目前進行中的步驟描述（顯示於 loading 畫面）
  final String progressMessage;

  /// OCR 辨識出的原始文字（僅供顯示除錯用）
  final String? ocrRawText;

  const ImageMatchState({
    this.status = MatchStatus.idle,
    this.results = const [],
    this.queryBytes,
    this.errorMessage,
    this.progressMessage = '',
    this.ocrRawText,
  });

  ImageMatchState copyWith({
    MatchStatus? status,
    List<MatchResult>? results,
    Uint8List? queryBytes,
    String? errorMessage,
    String? progressMessage,
    String? ocrRawText,
  }) =>
      ImageMatchState(
        status: status ?? this.status,
        results: results ?? this.results,
        queryBytes: queryBytes ?? this.queryBytes,
        errorMessage: errorMessage ?? this.errorMessage,
        progressMessage: progressMessage ?? this.progressMessage,
        ocrRawText: ocrRawText ?? this.ocrRawText,
      );
}

// ── Notifier ────────────────────────────────────────────────────

class ImageMatchNotifier extends StateNotifier<ImageMatchState> {
  ImageMatchNotifier() : super(const ImageMatchState());

  Future<void> startMatch(Uint8List imageBytes) async {
    state = ImageMatchState(
      status: MatchStatus.loading,
      queryBytes: imageBytes,
      progressMessage: 'OCR 文字辨識中…',
    );

    try {
      // ══════════════════════════════════════════════════════════
      // Phase 1：OCR 文字辨識（主要方法）
      // ══════════════════════════════════════════════════════════
      final ocrText = await OcrService.extractText(imageBytes);
      final parsed = LabelTextParser.parse(ocrText);

      if (parsed.hasContent) {
        _emitProgress('比對資料庫中（OCR）…');
        final ocrResults = await _matchByOcr(parsed, ocrText);
        if (ocrResults.isNotEmpty) {
          state = state.copyWith(
            status: MatchStatus.done,
            results: ocrResults,
            ocrRawText: ocrText,
          );
          return;
        }
      }

      // ══════════════════════════════════════════════════════════
      // Phase 2：圖像相似度備援（OCR 無結果時）
      // ══════════════════════════════════════════════════════════
      _emitProgress('OCR 無結果，改用圖像比對…');
      final products = await AppDatabase.instance.getProductsForMatching();

      if (products.isEmpty) {
        state = state.copyWith(
          status: MatchStatus.noMatch,
          errorMessage: '資料庫中尚無圖片資料，請先執行同步',
          ocrRawText: ocrText.isEmpty ? null : ocrText,
        );
        return;
      }

      final imgResults = await SimilarityCalculator.findMatches(
        queryBytes: imageBytes,
        products: products,
      );

      if (imgResults.isEmpty) {
        state = state.copyWith(
          status: MatchStatus.noMatch,
          errorMessage: 'OCR 及圖像比對均未找到符合結果\n'
              '（OCR 擷取文字：${ocrText.isEmpty ? "無" : ocrText.trim()}）',
          ocrRawText: ocrText.isEmpty ? null : ocrText,
        );
      } else {
        state = state.copyWith(
          status: MatchStatus.done,
          results: imgResults,
          ocrRawText: ocrText.isEmpty ? null : ocrText,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: MatchStatus.error,
        errorMessage: '比對過程發生錯誤：$e',
      );
    }
  }

  // ── OCR 資料庫搜尋 ─────────────────────────────────────────────

  Future<List<MatchResult>> _matchByOcr(
      ParsedLabel parsed, String ocrText) async {
    final db = AppDatabase.instance;

    // 以每個 token 搜尋資料庫，蒐集候選產品
    final seen = <String>{};
    final candidates = <TintProduct>[];

    for (final token in parsed.tokens) {
      try {
        final found = await db.searchProducts(token, limit: 50);
        for (final p in found) {
          if (seen.add(p.certNumber)) candidates.add(p);
        }
      } catch (_) {}
    }

    if (candidates.isEmpty) return [];

    // 計算每個候選產品的 OCR 匹配分數
    final scored = <({TintProduct product, double score})>[];
    for (final product in candidates) {
      double score = parsed.scoreProduct(product.brand, product.model);

      // VLT 吻合加分 +0.1
      if (parsed.vlt != null && product.visibleLight != null) {
        final ocrVlt = double.tryParse(parsed.vlt!);
        final dbVlt = double.tryParse(
            product.visibleLight!.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (ocrVlt != null && dbVlt != null && (ocrVlt - dbVlt).abs() <= 2) {
          score = (score + 0.1).clamp(0.0, 1.0);
        }
      }

      if (score > 0) scored.add((product: product, score: score));
    }

    if (scored.isEmpty) return [];

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.take(5).map((s) => MatchResult(
          product: s.product,
          similarity: s.score,
          source: MatchSource.ocr,
          ocrText: ocrText,
        )).toList();
  }

  void _emitProgress(String msg) {
    state = state.copyWith(
      status: MatchStatus.loading,
      progressMessage: msg,
    );
  }

  void reset() => state = const ImageMatchState();
}

// ── Provider ────────────────────────────────────────────────────

final imageMatchProvider =
    StateNotifierProvider<ImageMatchNotifier, ImageMatchState>(
  (_) => ImageMatchNotifier(),
);
