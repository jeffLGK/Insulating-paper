// lib/data/datasources/car_safety_scraper.dart
//
// 從 b2c.vscc.org.tw API 抓取隔熱紙認證產品資料。
//
// API: POST https://b2c.vscc.org.tw/HeatInsulationFilmProductApi/GetProductList
// 需要帶 Referer/Origin header 才能通過 WAF 驗證。

import 'dart:convert' show jsonDecode, utf8;
import 'package:http/http.dart' as http;

import '../models/tint_product.dart';

class CarSafetyScraper {
  /// [client] 可注入自訂 HTTP client（測試用）；留空時用預設 client。
  ///
  /// 連線 b2c.vscc.org.tw 所需的 TWCA 憑證鏈，由全域 HttpOverrides
  /// （installTwcaHttpOverrides）統一補上，這裡不需處理憑證。
  CarSafetyScraper({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _apiUrl =
      'https://b2c.vscc.org.tw/HeatInsulationFilmProductApi/GetProductList';

  static const String _referer =
      'https://www.car-safety.org.tw/car_safety/TemplateTwoContent?OpID=536';

  static const Duration _timeout = Duration(seconds: 30);

  // API 必須用 form-encoded（application/x-www-form-urlencoded），
  // JSON 格式會導致分頁失效，每頁都回傳相同資料。
  static const Map<String, String> _headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Referer': _referer,
    'Origin': 'https://www.car-safety.org.tw',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  static const int _pageSize = 20;

  /// 只取第一頁 metadata（總筆數估計、查詢時間），不下載全部資料
  /// 用於下載前顯示確認資訊給使用者
  Future<ScraperMetadata> fetchMetadata() async {
    final result = await _fetchPage(1);
    // API 只回傳 totalPages，總筆數為估算值
    final totalCount = result.totalPages * _pageSize;
    return ScraperMetadata(
      totalCount: totalCount,
      fetchedAt: DateTime.now(),
    );
  }

  /// 同時平行抓取的最大頁數，避免一次對伺服器開太多連線
  static const int _pageConcurrency = 6;

  /// 抓取所有產品，支援分頁。
  ///
  /// 先抓第 1 頁取得 totalPages，後續頁面以 [_pageConcurrency] 為一批平行下載，
  /// 大幅縮短整體等待時間（原本 ~38 頁循序下載約需 30 秒以上）。
  ///
  /// [onProgress] 每抓完一批就回報 (已完成頁數, 總頁數)，供 UI 顯示進度。
  /// 以 certNumber 去重；若 API 分頁失效（每頁回傳相同資料），重複資料會被自動
  /// 合併，不會造成重複或無限迴圈（頁數上限由 totalPages 限制）。
  Future<ScraperResult> fetchProducts({
    void Function(int done, int total)? onProgress,
  }) async {
    // 以 certNumber 為鍵去重，並保留插入順序（LinkedHashMap）
    final byKey = <String, TintProduct>{};
    void mergeProducts(List<TintProduct> products) {
      for (final product in products) {
        byKey.putIfAbsent(product.certNumber, () => product);
      }
    }

    // 第 1 頁先取得 totalPages
    final first = await _fetchPage(1);
    final totalPages = first.totalPages < 1 ? 1 : first.totalPages;
    mergeProducts(first.products);
    onProgress?.call(1, totalPages);

    if (totalPages > 1) {
      final remaining = [for (int page = 2; page <= totalPages; page++) page];
      int done = 1;
      for (int i = 0; i < remaining.length; i += _pageConcurrency) {
        final batch = remaining.skip(i).take(_pageConcurrency).toList();
        final results = await Future.wait(batch.map(_fetchPage));
        for (final result in results) {
          mergeProducts(result.products);
        }
        done += batch.length;
        onProgress?.call(done, totalPages);
      }
    }

    return ScraperResult(
      products: byKey.values.toList(),
      fetchedAt: DateTime.now(),
      sourceUrl: _apiUrl,
    );
  }

  /// 依合格標識序號線上查詢（支援 % 萬用字元）
  Future<List<TintProduct>> searchByCertSerial(String certSerial) async {
    final products = <TintProduct>[];
    final seenKeys = <String>{};
    int pageIndex = 1;
    int totalPages = 1;

    do {
      final result = await _fetchPage(pageIndex, certSerial: certSerial);
      final pageKeys = result.products.map((p) => p.certNumber).toSet();
      final newKeys = pageKeys.difference(seenKeys);
      if (newKeys.isEmpty) break;

      seenKeys.addAll(pageKeys);
      products.addAll(result.products);
      totalPages = result.totalPages;
      pageIndex++;
    } while (pageIndex <= totalPages);

    return products;
  }

  Future<_PageResult> _fetchPage(int pageIndex, {String certSerial = ''}) async {
    // 以 form-encoded 格式送出，與網站前端行為一致
    final body = {
      'manufacturer': '',
      'brand': '',
      'productModel': '',
      'lightTransmittance': '',
      'labelMethod': '',
      'certSerial': certSerial,
      'imageBase64': '',
      'cropX1': '0',
      'cropY1': '0',
      'cropX2': '0',
      'cropY2': '0',
      'pageIndex': '$pageIndex',
      'pageSize': '$_pageSize',
    };

    try {
      final response = await _client
          .post(Uri.parse(_apiUrl), headers: _headers, body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw ScraperException(
          'HTTP ${response.statusCode}：API 請求失敗',
          code: ScraperErrorCode.httpError,
        );
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes));

      if (json['success'] != true) {
        throw ScraperException(
          'API 回傳失敗：${json['message'] ?? 'unknown'}',
          code: ScraperErrorCode.apiError,
        );
      }

      final data = json['data'] as List<dynamic>;
      final totalPages = (json['totalPages'] as num?)?.toInt() ?? 1;

      final products = data
          .map((e) => _parseProduct(e as Map<String, dynamic>))
          .whereType<TintProduct>()
          .toList();

      return _PageResult(products: products, totalPages: totalPages);
    } on ScraperException {
      rethrow;
    } catch (e) {
      throw ScraperException(
        '網路連線失敗：$e',
        code: ScraperErrorCode.networkError,
      );
    }
  }

  TintProduct? _parseProduct(Map<String, dynamic> item) {
    final brand = (item['Brand'] as String?)?.trim() ?? '';
    final model = (item['ProductModel'] as String?)?.trim() ?? '';
    if (brand.isEmpty && model.isEmpty) return null;

    final manufacturer = (item['Manufacturer'] as String?)?.trim() ?? '';
    final certSerial = (item['CertSerial'] as String?)?.trim();
    final certImageUrl = (item['CertImageUrl'] as String?)?.trim();
    final lightTransmittance = (item['LightTransmittance'] as String?)?.trim();
    final labelMethod = (item['LabelMethod'] as String?)?.trim();
    final expiryDate = (item['ExpiryDate'] as String?)?.trim();
    final remark = (item['Remark'] as String?)?.trim();

    // 用 manufacturer+brand+model 組合作為穩定唯一鍵，自動去除重複
    final certNumber = (certSerial != null && certSerial.isNotEmpty)
        ? certSerial
        : '${manufacturer}_${brand}_$model';

    // 保留全部圖片 URL（逗號分隔）
    final imageUrl = (certImageUrl != null && certImageUrl.isNotEmpty)
        ? certImageUrl
        : null;

    return TintProduct(
      brand: brand,
      model: model,
      certNumber: certNumber,
      visibleLight: lightTransmittance,
      uvRejection: null,
      irRejection: null,
      heatRejection: null,
      standard: labelMethod,
      imageUrl: imageUrl,
      updatedAt: DateTime.now(),
      // 把廠商/有效期限/備註存進 rawText 方便搜尋。
      // 過濾「---」等純符號佔位符，避免影響 LIKE 搜尋結果。
      rawText: [manufacturer, expiryDate, remark]
          .where((s) => s != null && s.isNotEmpty && !RegExp(r'^[-\s.]+$').hasMatch(s!))
          .join(' '),
    );
  }
}

// ── 內部結果型別 ─────────────────────────────────────────────────

class _PageResult {
  final List<TintProduct> products;
  final int totalPages;
  const _PageResult({required this.products, required this.totalPages});
}

// ── 公開結果 & 例外型別 ──────────────────────────────────────────

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

class ScraperMetadata {
  final int totalCount;
  final DateTime fetchedAt;

  const ScraperMetadata({
    required this.totalCount,
    required this.fetchedAt,
  });
}

enum ScraperErrorCode {
  networkError,
  httpError,
  apiError,
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
