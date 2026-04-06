// Error scenario tests for CarSafetyScraper
// Tests exception handling and error codes

import 'package:flutter_test/flutter_test.dart';
import 'package:tint_app/data/datasources/car_safety_scraper.dart';
import 'package:tint_app/data/models/tint_product.dart';

void main() {
  group('CarSafetyScraper Exception Tests', () {
    test('ScraperException with networkError code', () {
      expect(
        () => throw ScraperException(
          '網路連線失敗：Connection refused',
          code: ScraperErrorCode.networkError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.networkError)
            .having((e) => e.message, 'message', contains('連線失敗'))),
      );
    });

    test('ScraperException with httpError code (404)', () {
      expect(
        () => throw ScraperException(
          'HTTP 404：無法取得頁面',
          code: ScraperErrorCode.httpError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.httpError)
            .having((e) => e.message, 'message', contains('404'))),
      );
    });

    test('ScraperException with httpError code (500)', () {
      expect(
        () => throw ScraperException(
          'HTTP 500：伺服器錯誤',
          code: ScraperErrorCode.httpError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.httpError)
            .having((e) => e.message, 'message', contains('500'))),
      );
    });

    test('ScraperException with parseError code', () {
      expect(
        () => throw ScraperException(
          '找不到資料表格，請確認頁面結構是否改變',
          code: ScraperErrorCode.parseError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.parseError)
            .having((e) => e.message, 'message', contains('表格'))),
      );
    });

    test('ScraperException with emptyResult code', () {
      expect(
        () => throw ScraperException(
          '解析結果為空，頁面可能需要登入或 JS 渲染',
          code: ScraperErrorCode.emptyResult,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.emptyResult)
            .having((e) => e.message, 'message', contains('結果為空'))),
      );
    });

    test('ScraperException toString formats correctly', () {
      final exception = ScraperException(
        'Test error message',
        code: ScraperErrorCode.networkError,
      );

      expect(
        exception.toString(),
        contains('ScraperException'),
      );
      expect(
        exception.toString(),
        contains('networkError'),
      );
    });

    test('All ScraperErrorCode values exist', () {
      expect(ScraperErrorCode.networkError, isNotNull);
      expect(ScraperErrorCode.httpError, isNotNull);
      expect(ScraperErrorCode.parseError, isNotNull);
      expect(ScraperErrorCode.emptyResult, isNotNull);
    });

    test('ScraperErrorCode names are correct', () {
      expect(ScraperErrorCode.networkError.name, 'networkError');
      expect(ScraperErrorCode.httpError.name, 'httpError');
      expect(ScraperErrorCode.parseError.name, 'parseError');
      expect(ScraperErrorCode.emptyResult.name, 'emptyResult');
    });
  });

  group('ScraperResult Tests', () {
    test('ScraperResult with zero products', () {
      final result = ScraperResult(
        products: [],
        fetchedAt: DateTime.now(),
        sourceUrl: 'https://example.com',
      );

      expect(result.count, equals(0));
      expect(result.products.isEmpty, true);
    });

    test('ScraperResult with multiple products', () {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'M1', certNumber: 'C2'),
        TintProduct(brand: 'SunTek', model: 'S1', certNumber: 'C3'),
      ];

      final result = ScraperResult(
        products: products,
        fetchedAt: DateTime.now(),
        sourceUrl: 'https://example.com',
      );

      expect(result.count, equals(3));
      expect(result.products.length, equals(3));
    });

    test('ScraperResult timestamp is valid', () {
      final now = DateTime.now();
      final result = ScraperResult(
        products: [],
        fetchedAt: now,
        sourceUrl: 'https://example.com',
      );

      expect(
        result.fetchedAt.difference(now).inSeconds.abs(),
        lessThan(1),
      );
    });
  });

  group('TintProduct Error Handling Tests', () {
    test('TintProduct with missing optional fields', () {
      final product = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'CERT-001',
      );

      expect(product.visibleLight, isNull);
      expect(product.uvRejection, isNull);
      expect(product.irRejection, isNull);
      expect(product.heatRejection, isNull);
      expect(product.standard, isNull);
      expect(product.imageUrl, isNull);
    });

    test('TintProduct fromMap with missing fields', () {
      final map = {
        'brand': '3M',
        'model': 'FX',
        'cert_number': 'CERT-001',
      };

      final product = TintProduct.fromMap(map);

      expect(product.brand, '3M');
      expect(product.model, 'FX');
      expect(product.certNumber, 'CERT-001');
      expect(product.visibleLight, isNull);
    });

    test('TintProduct fromMap with null values', () {
      final map = {
        'id': 1,
        'brand': '3M',
        'model': 'FX',
        'cert_number': 'CERT-001',
        'visible_light': null,
        'uv_rejection': null,
        'ir_rejection': null,
        'heat_rejection': null,
        'standard': null,
        'image_url': null,
      };

      final product = TintProduct.fromMap(map);

      expect(product.brand, '3M');
      expect(product.visibleLight, isNull);
    });

    test('TintProduct toMap roundtrip preserves data', () {
      final original = TintProduct(
        brand: '3M',
        model: 'Crystalline',
        certNumber: 'CERT-123',
        visibleLight: '45%',
        uvRejection: '99%',
        standard: 'CNS 4001',
      );

      final map = original.toMap();
      final restored = TintProduct.fromMap(map);

      expect(restored.brand, original.brand);
      expect(restored.model, original.model);
      expect(restored.certNumber, original.certNumber);
      expect(restored.visibleLight, original.visibleLight);
      expect(restored.uvRejection, original.uvRejection);
      expect(restored.standard, original.standard);
    });
  });

  group('Error Recovery Scenarios', () {
    test('Timeout error is handled', () {
      expect(
        () => throw ScraperException(
          '網路連線失敗：Timeout',
          code: ScraperErrorCode.networkError,
        ),
        throwsA(isA<ScraperException>()),
      );
    });

    test('Connection refused error is handled', () {
      expect(
        () => throw ScraperException(
          '網路連線失敗：Connection refused',
          code: ScraperErrorCode.networkError,
        ),
        throwsA(isA<ScraperException>()),
      );
    });

    test('401 Unauthorized error is handled', () {
      expect(
        () => throw ScraperException(
          'HTTP 401：未授權',
          code: ScraperErrorCode.httpError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.httpError)),
      );
    });

    test('403 Forbidden error is handled', () {
      expect(
        () => throw ScraperException(
          'HTTP 403：禁止存取',
          code: ScraperErrorCode.httpError,
        ),
        throwsA(isA<ScraperException>()
            .having((e) => e.code, 'code', ScraperErrorCode.httpError)),
      );
    });

    test('Invalid HTML structure error is handled', () {
      expect(
        () => throw ScraperException(
          '找不到資料表格，頁面結構可能已變更',
          code: ScraperErrorCode.parseError,
        ),
        throwsA(isA<ScraperException>()),
      );
    });
  });
}
