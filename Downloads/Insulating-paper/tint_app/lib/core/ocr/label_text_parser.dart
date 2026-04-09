import 'dart:math';

/// 從 OCR 原始文字中解析隔熱紙標貼的結構化資訊。
///
/// 典型標貼文字範例：
///   "V-KOOL\nUXM70\nVLT:76.0%"
///   "3M\nCS35\nVLT 35%"
///   "Johnson\nJW50\n50%"
class LabelTextParser {
  // ── 正規表示式 ──────────────────────────────────────────────────

  /// VLT 數值，例如 "VLT:76.0%" 或 "76.0%"
  static final _vltExplicit =
      RegExp(r'VLT\s*:?\s*(\d{1,3}(?:\.\d+)?)\s*%', caseSensitive: false);

  static final _vltPercent =
      RegExp(r'\b(\d{1,3}(?:\.\d+)?)\s*%', caseSensitive: false);

  /// 符合品牌/型號的 token：2 字以上英數字（允許連字號）
  static final _tokenPattern = RegExp(r'[A-Z0-9][A-Z0-9\-]{1,}', caseSensitive: false);

  // ── 公開方法 ────────────────────────────────────────────────────

  /// 解析 OCR 文字，回傳 [ParsedLabel]。
  static ParsedLabel parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return ParsedLabel(tokens: [], vlt: null, rawText: rawText);
    }

    // 1. 標準化：去除雜訊字元，轉大寫
    final normalized = rawText
        .toUpperCase()
        .replaceAll(RegExp(r'[^\w\s:%.\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 2. 提取 VLT（優先取明確標示，次取第一個百分比）
    String? vlt;
    final vltMatch = _vltExplicit.firstMatch(rawText);
    if (vltMatch != null) {
      vlt = vltMatch.group(1);
    } else {
      final pctMatch = _vltPercent.firstMatch(rawText);
      if (pctMatch != null) {
        final val = double.tryParse(pctMatch.group(1) ?? '');
        // VLT 通常 5~99%，過濾明顯不合理的數值
        if (val != null && val >= 5 && val <= 99) {
          vlt = pctMatch.group(1);
        }
      }
    }

    // 3. 提取品牌/型號 tokens
    //    排除：純數字、VLT 數值本身、過短
    final vltValue = vlt != null ? RegExp(RegExp.escape(vlt)) : null;
    final tokens = <String>[];
    for (final m in _tokenPattern.allMatches(normalized)) {
      final t = m.group(0)!;
      // 排除純數字
      if (RegExp(r'^\d+$').hasMatch(t)) continue;
      // 排除與 VLT 數值重複的 token
      if (vltValue != null && vltValue.hasMatch(t)) continue;
      // 排除太短（單字元或 2 字元純數字）
      if (t.length < 2) continue;
      if (!tokens.contains(t)) tokens.add(t);
    }

    return ParsedLabel(tokens: tokens, vlt: vlt, rawText: rawText);
  }
}

// ── 資料類別 ────────────────────────────────────────────────────────

class ParsedLabel {
  final List<String> tokens;
  final String? vlt;
  final String rawText;

  const ParsedLabel({
    required this.tokens,
    required this.vlt,
    required this.rawText,
  });

  /// OCR 有擷取到有效內容
  bool get hasContent => tokens.isNotEmpty;

  /// 品牌/型號 token 數量
  int get tokenCount => tokens.length;

  /// 對每個資料庫產品計算 OCR 匹配分數（0.0 ~ 1.0）
  double scoreProduct(String brand, String model) {
    if (tokens.isEmpty) return 0.0;

    final brandUp = brand.toUpperCase();
    final modelUp = model.toUpperCase();

    int matched = 0;
    for (final token in tokens) {
      // 完整包含 token
      if (brandUp.contains(token) || modelUp.contains(token)) {
        matched++;
        continue;
      }
      // token 包含品牌或型號（應對 OCR 多餘字元）
      if (token.contains(brandUp) || token.contains(modelUp)) {
        matched++;
        continue;
      }
      // 容錯：O ↔ 0 互換
      final fuzzy = token
          .replaceAll('0', 'O')
          .replaceAll('O', '0');
      if (brandUp.contains(fuzzy) || modelUp.contains(fuzzy) ||
          brandUp.replaceAll('0', 'O').contains(token) ||
          modelUp.replaceAll('0', 'O').contains(token)) {
        matched++;
      }
    }

    if (matched == 0) return 0.0;

    // 基本分：matched / total tokens
    double score = matched / tokens.length;

    // VLT 加分：若資料庫產品的可見光透過率與 OCR 解析值接近
    // （此處不傳入 visibleLight，由呼叫方加分）
    return min(score, 1.0);
  }

  @override
  String toString() =>
      'ParsedLabel(tokens=$tokens, vlt=$vlt)';
}
