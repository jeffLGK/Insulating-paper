import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/image/similarity_calculator.dart';
import '../../core/ocr/label_text_parser.dart';
import '../../core/ocr/ocr_service.dart';
import '../../data/models/tint_product.dart';

export '../../core/image/similarity_calculator.dart' show MatchResult, MatchSource;

// ── 狀態定義 ────────────────────────────────────────────────────

enum MatchStatus { idle, loading, done, noMatch, error, professionalLabel }

class ImageMatchState {
  final MatchStatus status;
  final List<MatchResult> results;
  final Uint8List? queryBytes;
  final String? errorMessage;

  /// 目前進行中的步驟描述（顯示於 loading 畫面）
  final String progressMessage;

  /// OCR 辨識出的原始文字（僅供顯示除錯用）
  final String? ocrRawText;

  /// OCR 辨識到 SA\d+ 或 FA\d+ 格式（專業機構印製序號）
  final bool isProfessionalLabel;

  const ImageMatchState({
    this.status = MatchStatus.idle,
    this.results = const [],
    this.queryBytes,
    this.errorMessage,
    this.progressMessage = '',
    this.ocrRawText,
    this.isProfessionalLabel = false,
  });

  ImageMatchState copyWith({
    MatchStatus? status,
    List<MatchResult>? results,
    Uint8List? queryBytes,
    String? errorMessage,
    String? progressMessage,
    String? ocrRawText,
    bool? isProfessionalLabel,
  }) =>
      ImageMatchState(
        status: status ?? this.status,
        results: results ?? this.results,
        queryBytes: queryBytes ?? this.queryBytes,
        errorMessage: errorMessage ?? this.errorMessage,
        progressMessage: progressMessage ?? this.progressMessage,
        ocrRawText: ocrRawText ?? this.ocrRawText,
        isProfessionalLabel: isProfessionalLabel ?? this.isProfessionalLabel,
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

      // ── 專業機構印製序號（SA* / FA*）→ 直接中止，不執行任何比對 ──
      if (parsed.isProfessionalSerialFormat) {
        state = state.copyWith(
          status: MatchStatus.professionalLabel,
          isProfessionalLabel: true,
          ocrRawText: ocrText.isEmpty ? null : ocrText,
        );
        return;
      }

      // ── OCR 比對資料庫 ───────────────────────────────────────────
      if (parsed.hasContent) {
        _emitProgress('比對資料庫中（OCR）…');
        final ocrResults = await _matchByOcr(parsed, ocrText);
        if (ocrResults.isNotEmpty) {
          state = state.copyWith(
            status: MatchStatus.done,
            results: ocrResults,
            ocrRawText: ocrText,
            isProfessionalLabel: false,
          );
          return;
        }
      }

      // ── 無符合結果 ───────────────────────────────────────────────
      state = state.copyWith(
        status: MatchStatus.noMatch,
        errorMessage: '無符合資料',
        ocrRawText: ocrText.isEmpty ? null : ocrText,
        isProfessionalLabel: false,
      );
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

    // ── 候選搜尋策略 ─────────────────────────────────────────────
    //
    // 優先：取含有 `-` 的 token（保留連字符做整段比對）
    //       例："V-KOOL UXM70" → 先用 ['V-KOOL'] 搜尋
    // 退回：將 `-` 也當分隔符，拆成更細的 tokens 搜尋
    //       例：['V', 'KOOL', 'UXM70']

    final hyphenTokens = LabelTextParser.likeTokensWithHyphens(ocrText)
        .where((t) => t.contains('-'))
        .toList();

    List<TintProduct> candidates = [];

    if (hyphenTokens.isNotEmpty) {
      candidates = await db.searchByLikeTokens(hyphenTokens);
    }

    // 無含 `-` 的 token，或含 `-` 的搜尋無結果 → 退回一般分割搜尋
    if (candidates.isEmpty) {
      final tokens = LabelTextParser.likeTokens(ocrText);
      if (tokens.isEmpty) return [];
      candidates = await db.searchByLikeTokens(tokens);
    }

    if (candidates.isEmpty) return [];

    // ── 評分（加權比對，由右往左：60% / 30% / 10%） ────────────
    final scored = <({TintProduct product, double score})>[];
    for (final product in candidates) {
      final score = parsed.scoreProduct(product.brand, product.model);
      // 門檻：≥ 50%
      if (score >= 0.50) scored.add((product: product, score: score));
    }

    if (scored.isEmpty) return [];

    scored.sort((a, b) => b.score.compareTo(a.score));

    // 最多回傳 3 筆
    return scored.take(3).map((s) => MatchResult(
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
