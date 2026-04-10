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

  /// 是否辨識到 SA\d+ 或 FA\d+ 格式的 token（專業機構印製序號）
  bool get isProfessionalSerialFormat {
    final pattern = RegExp(r'^(SA|FA)\d+$', caseSensitive: false);
    return tokens.any((t) => pattern.hasMatch(t));
  }

  /// 品牌/型號 token 數量
  int get tokenCount => tokens.length;

  /// 去除連字號、空格等所有非英數字符號，僅保留英數字，用於寬鬆比對。
  /// 例："V-KOOL" → "VKOOL"、"3M" → "3M"、"CS-35" → "CS35"
  static String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// 對每個資料庫產品計算 OCR 匹配分數（0.0 ~ 1.0）。
  ///
  /// 比對前先正規化（去除連字號/空格等），確保：
  ///   OCR 讀到 "VKOOL" 能匹配資料庫 "V-KOOL"
  ///   OCR 讀到 "CS35"  能匹配資料庫 "CS-35"
  double scoreProduct(String brand, String model) {
    if (tokens.isEmpty) return 0.0;

    // 正規化品牌與型號
    final normBrand = _normalize(brand);
    final normModel = _normalize(model);

    int matched = 0;
    for (final token in tokens) {
      final normToken = _normalize(token);
      if (normToken.isEmpty) continue;

      // ① 正規化後 contains 比對（主要路徑）
      if (normBrand.contains(normToken) || normModel.contains(normToken)) {
        matched++;
        continue;
      }
      // ② token 較長，包含了品牌或型號（應對 OCR 多餘字元）
      if (normToken.contains(normBrand) || normToken.contains(normModel)) {
        matched++;
        continue;
      }
      // ③ 容錯：O ↔ 0 互換（如 "O" 被 OCR 讀成 "0"）
      final fuzzyToken = normToken.replaceAll('0', 'O');
      final fuzzyBrand = normBrand.replaceAll('0', 'O');
      final fuzzyModel = normModel.replaceAll('0', 'O');
      if (fuzzyBrand.contains(fuzzyToken) || fuzzyModel.contains(fuzzyToken) ||
          fuzzyToken.contains(fuzzyBrand) || fuzzyToken.contains(fuzzyModel)) {
        matched++;
      }
    }

    if (matched == 0) return 0.0;

    // 分數：命中 token 數 / 全部 token 數
    return min(matched / tokens.length, 1.0);
  }

  @override
  String toString() =>
      'ParsedLabel(tokens=$tokens, vlt=$vlt)';
}
