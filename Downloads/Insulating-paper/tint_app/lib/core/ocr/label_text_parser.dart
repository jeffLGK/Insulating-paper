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
    // >>> RULE_BUILDER_TRIGGERS
    'WINDOW',
    'FILMS',
    // <<< RULE_BUILDER_TRIGGERS
  ];

  // ── OCR 誤讀／品牌正規化對應（前處理階段套用 replaceAll） ─────────
  //
  // 規則：text.replaceAll(key, value)，在分割 token 前先把 OCR 常見誤讀字串
  // 修正成正確品牌字。例：'CPX' → 'CLEARPLEX'（normalize 後可匹配 'Clear Plex'）。
  static const _ocrReplacements = <String, String>{
    'CPX': 'CLEARPLEX',
    // >>> RULE_BUILDER_REPLACEMENTS
    '550': 'S50',
    'G570': 'GS70',
    // <<< RULE_BUILDER_REPLACEMENTS
  };

  /// 依 OCR 文字中出現的品牌關鍵字，套用該品牌的「文字層級」特殊前處理。
  static String _applyBrandSpecialRules(String text) {
    // COSMI（可舒您）：OCR 常把型號中的 '-' 誤讀成 '_'，還原回來
    if (text.contains('COSMI') || text.contains('可舒您')) {
      text = text.replaceAll('_', '-');
    }
    return text;
  }

  // ── CAROYAL 系列裸數字補字母前綴（token 層級查表，對應不規則） ──
  // key = '系列詞_數字'（VLT/% 已在前面移除，故系列詞與數字相鄰）。
  static const _caroyalTokenMap = <String, String>{
    'RSUPREME_70': 'RS7', 'RSUPREME_40': 'RS4',
    'SUPREME_70': 'SUPREME S7', 'SUPREME_45': 'SUPREME S5',
    'PURITY_75': 'PURITY P75', 'PURITY_45': 'PURITY P45',
    'ROYAL_75': 'ROYAL R75', 'ROYAL_45': 'ROYAL R45',
    'GLORY_70': 'GLORY G70', 'GLORY_55': 'GLORY G55', 'GLORY_45': 'GLORY G45',
    'CAT_70': 'CAT70',
  };

  /// 依 OCR 文字中出現的品牌關鍵字，套用該品牌的「token 層級」特殊規則。
  static List<String> _applyBrandTokenRules(List<String> tokens, String rawUpper) {
    // CAROYAL：把相鄰的「系列詞 + 裸數字」依查表轉成型號代碼
    if (rawUpper.contains('CAROYAL')) {
      final out = <String>[];
      for (int i = 0; i < tokens.length; i++) {
        if (i + 1 < tokens.length) {
          final mapped = _caroyalTokenMap['${tokens[i]}_${tokens[i + 1]}'];
          if (mapped != null) {
            out.addAll(mapped.split(' '));
            i++; // 跳過已消化的數字 token
            continue;
          }
        }
        out.add(tokens[i]);
      }
      tokens = out;
    }
    // KORAAN：移除尾端獨立的可見光數字 token（如 KN-N70 之後的 70/40）
    if (rawUpper.contains('KORAAN')) {
      while (tokens.isNotEmpty && RegExp(r'^\d+$').hasMatch(tokens.last)) {
        tokens.removeLast();
      }
    }
    return tokens;
  }

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

    // ── 步驟 2a：廠牌條件式特殊規則（COSMI/CAROYAL，依 OCR 內品牌字觸發） ──
    text = _applyBrandSpecialRules(text);

    // ── 步驟 2b：OCR 誤讀／品牌對應（如 CPX → CLEARPLEX） ─────────
    // 以「token 起始邊界」套用（前一字非英數才取代），避免 550→S50
    // 誤傷 FSK BW550（550 為字尾不取代）。注意：對應 key 僅限英數/中文。
    _ocrReplacements.forEach((from, to) {
      text = text.replaceAllMapped(RegExp('(?<![A-Z0-9])$from'), (_) => to);
    });

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
      // 保留英數字、連字符與繁體中文字元，清理其他特殊字元
      final clean = word
          .replaceAll(RegExp(r'[^A-Z0-9\-\u4E00-\u9FFF\u3400-\u4DBF]'), '')
          .replaceAll(RegExp(r'^-+|-+$'), ''); // 修剪頭尾連字符
      if (clean.length < 2) continue;

      // 純數字 token 去重
      final isPureNum = RegExp(r'^\d+\.?\d*$').hasMatch(clean);
      if (isPureNum) {
        if (!seenNums.add(clean)) continue;
      }

      if (!tokens.contains(clean)) tokens.add(clean);
    }

    // ── 步驟 7：廠牌條件式 token 規則（CAROYAL 補前綴、KORAAN 去尾數） ──
    final finalTokens = _applyBrandTokenRules(tokens, rawText.toUpperCase());

    return ParsedLabel(tokens: finalTokens, rawText: rawText);
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

  /// 去除所有非英數字與非中文字符號，用於寬鬆比對。
  /// 例："V-KOOL" → "VKOOL"、"3M" → "3M"、"威固" → "威固"
  static String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\u4E00-\u9FFF\u3400-\u4DBF]'), '');

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
