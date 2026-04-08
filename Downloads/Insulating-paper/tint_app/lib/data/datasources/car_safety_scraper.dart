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

  /// 抓取所有產品，支援分頁
  /// 若偵測到回傳資料與上一頁相同（API 分頁失效），提早結束避免重複請求。
  Future<ScraperResult> fetchProducts() async {
    final products = <TintProduct>[];
    final seenKeys = <String>{};
    int pageIndex = 1;
    int totalPages = 1;

    do {
      final result = await _fetchPage(pageIndex);

      // 計算本頁新增的 key 數量，若無新資料代表 API 分頁失效，提早結束
      final pageKeys = result.products.map((p) => p.certNumber).toSet();
      final newKeys = pageKeys.difference(seenKeys);
      if (newKeys.isEmpty) break;

      seenKeys.addAll(pageKeys);
      products.addAll(result.products);
      totalPages = result.totalPages;
      pageIndex++;
    } while (pageIndex <= totalPages);

    return ScraperResult(
      products: products,
      fetchedAt: DateTime.now(),
      sourceUrl: _apiUrl,
    );
  }

  Future<_PageResult> _fetchPage(int pageIndex) async {
    // 以 form-encoded 格式送出，與網站前端行為一致
    final body = {
      'manufacturer': '',
      'brand': '',
      'productModel': '',
      'lightTransmittance': '',
      'labelMethod': '',
      'certSerial': '',
      'imageBase64': '',
      'cropX1': '0',
      'cropY1': '0',
      'cropX2': '0',
      'cropY2': '0',
      'pageIndex': '$pageIndex',
      'pageSize': '$_pageSize',
    };

    try {
      final response = await http
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
      // 把廠商/有效期限/備註存進 rawText 方便搜尋
      rawText: [manufacturer, expiryDate, remark]
          .where((s) => s != null && s.isNotEmpty)
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
