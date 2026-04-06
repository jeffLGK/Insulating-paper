// lib/data/datasources/car_safety_scraper.dart
//
// 負責從 car-safety.org.tw 爬取隔熱紙表格資料。
//
// 策略：
//   1. 送出 HTTP GET 取得 HTML
//   2. 用 html 套件解析 <table> 結構
//   3. 把每列映射到 TintProduct
//
// 注意：若網站調整 HTML 結構，需更新對應的 CSS selector。

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart';

import '../models/tint_product.dart';

class CarSafetyScraper {
  static const String _targetUrl =
      'https://www.car-safety.org.tw/car_safety/TemplateTwoContent?OpID=536';

  // 請求 timeout
  static const Duration _timeout = Duration(seconds: 30);

  // User-Agent 模擬正常瀏覽器（避免被擋）
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'zh-TW,zh;q=0.9',
  };

  // ── 主入口 ──────────────────────────────────────────────────────

  /// 抓取並解析，回傳產品清單
  /// 若網路失敗或解析失敗，拋出 [ScraperException]
  Future<ScraperResult> fetchProducts() async {
    final html = await _fetchHtml(_targetUrl);
    final products = _parseHtml(html);
    return ScraperResult(
      products: products,
      fetchedAt: DateTime.now(),
      sourceUrl: _targetUrl,
    );
  }

  // ── 網路請求 ────────────────────────────────────────────────────

  Future<String> _fetchHtml(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw ScraperException(
          'HTTP ${response.statusCode}：無法取得頁面',
          code: ScraperErrorCode.httpError,
        );
      }

      // 嘗試 UTF-8，若亂碼再試 Big5
      try {
        return utf8.decode(response.bodyBytes);
      } catch (_) {
        return latin1.decode(response.bodyBytes);
      }
    } on ScraperException {
      rethrow;
    } catch (e) {
      throw ScraperException(
        '網路連線失敗：$e',
        code: ScraperErrorCode.networkError,
      );
    }
  }

  // ── HTML 解析 ───────────────────────────────────────────────────

  List<TintProduct> _parseHtml(String html) {
    final document = htmlParser.parse(html);
    final products = <TintProduct>[];

    // 嘗試多種策略尋找資料表格
    final table = _findDataTable(document);
    if (table == null) {
      throw ScraperException(
        '找不到資料表格，請確認頁面結構是否改變',
        code: ScraperErrorCode.parseError,
      );
    }

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return products;

    // 解析表頭，動態對應欄位索引
    final headerRow = rows.first;
    final columnMap = _parseHeaders(headerRow);

    // 從第二列開始解析資料
    for (var i = 1; i < rows.length; i++) {
      final product = _parseRow(rows[i], columnMap, i);
      if (product != null) products.add(product);
    }

    if (products.isEmpty) {
      throw ScraperException(
        '解析結果為空，頁面可能需要登入或 JS 渲染',
        code: ScraperErrorCode.emptyResult,
      );
    }

    return products;
  }

  /// 嘗試多種 selector 尋找資料表格
  Element? _findDataTable(Document document) {
    // 策略 1：找 class 含 table 的元素
    for (final sel in [
      'table.table',
      'table.list-table',
      '.content-area table',
      'main table',
      '#content table',
      '.article-content table',
      'table',               // 最後兜底：頁面上第一個 table
    ]) {
      final el = document.querySelector(sel);
      if (el != null) {
        // 確認有足夠的列數（至少表頭 + 1 筆資料）
        if ((el.querySelectorAll('tr').length) >= 2) return el;
      }
    }
    return null;
  }

  /// 解析表頭列，回傳 { 欄位關鍵字: 欄位索引 } 對應表
  Map<String, int> _parseHeaders(Element headerRow) {
    final headers = headerRow.querySelectorAll('th, td');
    final map = <String, int>{};

    for (var i = 0; i < headers.length; i++) {
      final text = headers[i].text.trim().toLowerCase();

      if (text.contains('品牌') || text.contains('brand')) {
        map['brand'] = i;
      } else if (text.contains('型號') || text.contains('model')) {
        map['model'] = i;
      } else if (text.contains('認證') || text.contains('證號') ||
          text.contains('cert')) {
        map['cert_number'] = i;
      } else if (text.contains('可見光') || text.contains('vlt')) {
        map['visible_light'] = i;
      } else if (text.contains('紫外線') || text.contains('uv')) {
        map['uv_rejection'] = i;
      } else if (text.contains('紅外線') || text.contains('ir')) {
        map['ir_rejection'] = i;
      } else if (text.contains('熱能') || text.contains('tser') ||
          text.contains('隔熱')) {
        map['heat_rejection'] = i;
      } else if (text.contains('標準') || text.contains('規範') ||
          text.contains('standard')) {
        map['standard'] = i;
      } else if (text.contains('圖') || text.contains('標籤') ||
          text.contains('image')) {
        map['image'] = i;
      }
    }

    // 若表頭完全不符，退回索引猜測（對應常見欄位順序）
    if (map.isEmpty) {
      map.addAll({
        'brand': 0, 'model': 1, 'cert_number': 2,
        'visible_light': 3, 'uv_rejection': 4,
        'ir_rejection': 5, 'heat_rejection': 6,
        'standard': 7,
      });
    }

    return map;
  }

  /// 解析單一資料列
  TintProduct? _parseRow(
    Element row,
    Map<String, int> columnMap,
    int rowIndex,
  ) {
    final cells = row.querySelectorAll('td, th');
    if (cells.isEmpty) return null;

    // 跳過全部空白的列
    final allText = cells.map((c) => c.text.trim()).join();
    if (allText.isEmpty) return null;

    String cellText(String key) {
      final idx = columnMap[key];
      if (idx == null || idx >= cells.length) return '';
      return cells[idx].text.trim();
    }

    // 圖片 URL 提取
    String? imageUrl;
    final imgIdx = columnMap['image'];
    if (imgIdx != null && imgIdx < cells.length) {
      final img = cells[imgIdx].querySelector('img');
      imageUrl = img?.attributes['src'];
      if (imageUrl != null && imageUrl.startsWith('/')) {
        imageUrl = 'https://www.car-safety.org.tw$imageUrl';
      }
    }

    final brand = cellText('brand');
    final model = cellText('model');
    // 若品牌和型號都空，跳過
    if (brand.isEmpty && model.isEmpty) return null;

    final certNumber = cellText('cert_number').isNotEmpty
        ? cellText('cert_number')
        : 'ROW_$rowIndex'; // 備援 id，確保 UNIQUE 不衝突

    return TintProduct(
      brand: brand,
      model: model,
      certNumber: certNumber,
      visibleLight: cellText('visible_light').isNotEmpty
          ? cellText('visible_light')
          : null,
      uvRejection: cellText('uv_rejection').isNotEmpty
          ? cellText('uv_rejection')
          : null,
      irRejection: cellText('ir_rejection').isNotEmpty
          ? cellText('ir_rejection')
          : null,
      heatRejection: cellText('heat_rejection').isNotEmpty
          ? cellText('heat_rejection')
          : null,
      standard: cellText('standard').isNotEmpty
          ? cellText('standard')
          : null,
      imageUrl: imageUrl,
      updatedAt: DateTime.now(),
    );
  }
}

// ── 回傳值 & 例外型別 ──────────────────────────────────────────────

class ScraperResult {
  final List<TintProduct> products;
  final DateTime fetchedAt;
  final String sourceUrl;

  const ScraperResult({
    required this.products,
    required this.fetchedAt,
    required this.sourceUrl,
  });

  int get count => products.length;
}

enum ScraperErrorCode {
  networkError,
  httpError,
  parseError,
  emptyResult,
}

class ScraperException implements Exception {
  final String message;
  final ScraperErrorCode code;

  const ScraperException(this.message, {required this.code});

  @override
  String toString() => 'ScraperException(${code.name}): $message';
}
