import 'dart:math';

/// 從 OCR 原始文字中解析隔熱紙標貼的結構化資訊。
///
/// 典型標貼文字範例：
///   "V-KOOL\nUXM70"
///   "3M\nCS35"
///   "Johnson\nJW50"
///   "AI-40"       → tokens: ['AI-40']
///   "MOT40"       → 整個 token 含 MOT → 全部移除 → nothing
///   "40%"         → 整個 token 含 %   → 全部移除 → nothing
///   ">40"         → 整個 token 含 >   → 全部移除 → nothing
class LabelTextParser {
  // ── 觸發字串（合併）：含有以下任一字串的 token 整個移除 ──────────
  //
  // 規則：token.contains(trigger) → 整個 token 移除
  // 例：MOT40 含 MOT → 全部移除；40% 含 % → 全部移除
  // 'UP' 使用精確相等比對，避免誤刪含 UP 的型號（如 SUPER、SETUP）
  static const _triggers = [
    '>',
    '%',
    'MOT', 'GBS', 'GRA', 'GMK', 'AAK', 'AAP',
    'ACT', 'AEV', 'AKP', 'AVN', 'AVK', 'AUV', 'ATK',
    'MIN', 'VLT', 'USA', 'ALV', 'AUL', 'AGC', 'AUH',
  ];

  // ── 公開方法 ────────────────────────────────────────────────────

  /// 保留連字符版本：以空白與斜線為分隔符拆成 token 列表（保留 `-`）。
  /// 用於優先搜尋含 `-` 的資料庫比對。
  static List<String> likeTokensWithHyphens(String rawText) {
    return rawText
        .trim()
        .toUpperCase()
        .split(RegExp(r'[\s\/]+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// 將 OCR 原始文字以空白、斜線與「-」為分隔符拆成 token 列表。
  static List<String> likeTokens(String rawText) {
    return rawText
        .trim()
        .toUpperCase()
        .split(RegExp(r'[\s\/\-]+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// 解析 OCR 文字，回傳 [ParsedLabel]。
  ///
  /// 前處理順序：
  ///   1. 轉大寫
  ///   2. CPX → CLEARPLEX（品牌對應，normalize 後可匹配資料庫 'Clear Plex'）
  ///   3. 以空白、斜線分割成 words（保留 `-`）
  ///   4. 逐 word 檢查：含任一觸發字串 → 整個 word 移除
  ///      UP → 僅整詞相等才移除
  ///   5. 清理殘留非英數/連字符字元，修剪頭尾連字符，長度 < 2 的丟棄
  ///   6. 去除重複數字 token
  static ParsedLabel parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return ParsedLabel(tokens: [], rawText: rawText);
    }

    // ── 步驟 1：轉大寫 ────────────────────────────────────────────
    String text = rawText.toUpperCase();

    // ── 步驟 2：CPX → CLEARPLEX（品牌對應） ─────────────────────
    // normalize() 會將 'CLEARPLEX' 與資料庫 'Clear Plex' 統一為 'CLEARPLEX'
    text = text.replaceAll('CPX', 'CLEARPLEX');

    // ── 步驟 3：分割成 words（以空白、斜線為分隔符，保留 `-`） ───
    final words = text
        .split(RegExp(r'[\s\/]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    // ── 步驟 4：逐 word 過濾 ──────────────────────────────────────
    final kept = <String>[];
    for (final word in words) {
      bool discard = false;

      // 觸發字串：含有 → 整個 word 移除
      for (final trigger in _triggers) {
        if (word.contains(trigger)) {
          discard = true;
          break;
        }
      }

      // 'UP' 特殊處理：整詞相等才移除，避免誤刪 SUPER、SETUP 等型號
      if (!discard && word == 'UP') {
        discard = true;
      }

      if (!discard) kept.add(word);
    }

    // ── 步驟 5 & 6：清理並建立最終 tokens ────────────────────────
    final tokens = <String>[];
    final seenNums = <String>{}; // 去除重複數字

    for (final word in kept) {
      // 保留英數字與連字符，清理其他特殊字元
      final clean = word
          .replaceAll(RegExp(r'[^A-Z0-9\-]'), '')
          .replaceAll(RegExp(r'^-+|-+$'), ''); // 修剪頭尾連字符
      if (clean.length < 2) continue;

      // 純數字 token 去重
      final isPureNum = RegExp(r'^\d+\.?\d*$').hasMatch(clean);
      if (isPureNum) {
        if (!seenNums.add(clean)) continue;
      }

      if (!tokens.contains(clean)) tokens.add(clean);
    }

    return ParsedLabel(tokens: tokens, rawText: rawText);
  }
}

// ── 資料類別 ────────────────────────────────────────────────────────

class ParsedLabel {
  final List<String> tokens;
  final String rawText;

  const ParsedLabel({
    required this.tokens,
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

  /// 去除所有非英數字符號，僅保留英數字，用於寬鬆比對。
  /// 例："V-KOOL" → "VKOOL"、"3M" → "3M"、"CS-35" → "CS35"
  static String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// 依 token 位置（由右往前）計算比對權重。
  ///
  ///   1 個 token：[1.00]
  ///   2 個 token：[0.35, 0.65]          ← 左→右
  ///   3 個 token：[0.10, 0.30, 0.60]
  ///   4+ tokens ：最右=0.60、次右=0.30，
  ///               其餘 (count-2) 個 token 平均共享 0.10
  static List<double> _buildWeights(int count) {
    if (count == 0) return [];
    if (count == 1) return [1.0];
    if (count == 2) return [0.35, 0.65];
    // count >= 3
    final restCount = count - 2;
    final eachRest = 0.10 / restCount;
    return [...List.filled(restCount, eachRest), 0.30, 0.60];
  }

  /// 對每個資料庫產品計算 OCR 匹配分數（0.0 ~ 1.0）。
  ///
  /// 比對策略（依序嘗試）：
  ///   ① 正規化後 contains 比對
  ///   ② token 較長，包含了品牌或型號（應對 OCR 多餘字元）
  ///   ③ O ↔ 0 容錯（如 "O" 被 OCR 讀成 "0"）
  ///
  /// 比對權重（由右往左）：
  ///   rightmost = 60%（2 tokens 時為 65%）
  ///   second    = 30%（2 tokens 時為 35%）
  ///   rest      = 10% 平均分配
  ///
  /// 分數 = Σ(命中 token 之權重)，上限 1.0
  double scoreProduct(String brand, String model) {
    if (tokens.isEmpty) return 0.0;

    final normBrand = _normalize(brand);
    final normModel = _normalize(model);
    final weights = _buildWeights(tokens.length);

    double totalScore = 0.0;

    for (int i = 0; i < tokens.length; i++) {
      final normToken = _normalize(tokens[i]);
      if (normToken.isEmpty) continue;

      bool hit = false;

      // ① 正規化後 contains 比對（主要路徑）
      if (normBrand.contains(normToken) || normModel.contains(normToken)) {
        hit = true;
      }
      // ② token 較長，包含了品牌或型號（應對 OCR 多餘字元）
      // 必須排除 normBrand/normModel 為空字串，避免 anyString.contains("") 誤判
      else if ((normBrand.isNotEmpty && normToken.contains(normBrand)) ||
          (normModel.isNotEmpty && normToken.contains(normModel))) {
        hit = true;
      }
      // ③ 容錯：O ↔ 0 互換（如 "O" 被 OCR 讀成 "0"）
      else {
        final fuzzyToken = normToken.replaceAll('0', 'O');
        final fuzzyBrand = normBrand.replaceAll('0', 'O');
        final fuzzyModel = normModel.replaceAll('0', 'O');
        if (fuzzyBrand.contains(fuzzyToken) ||
            fuzzyModel.contains(fuzzyToken) ||
            (fuzzyBrand.isNotEmpty && fuzzyToken.contains(fuzzyBrand)) ||
            (fuzzyModel.isNotEmpty && fuzzyToken.contains(fuzzyModel))) {
          hit = true;
        }
      }

      if (hit) totalScore += weights[i];
    }

    return totalScore.clamp(0.0, 1.0);
  }

  @override
  String toString() => 'ParsedLabel(tokens=$tokens)';
}
