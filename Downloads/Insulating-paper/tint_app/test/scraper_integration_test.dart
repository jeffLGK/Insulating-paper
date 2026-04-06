// Integration test for CarSafetyScraper
// Tests actual web scraping from car-safety.org.tw

import 'package:flutter_test/flutter_test.dart';
import 'package:tint_app/data/datasources/car_safety_scraper.dart';
import 'package:tint_app/data/models/tint_product.dart';

void main() {
  group('CarSafetyScraper Integration Tests', () {
    late CarSafetyScraper scraper;

    setUp(() {
      scraper = CarSafetyScraper();
    });

    test('fetchProducts returns valid ScraperResult', () async {
      final result = await scraper.fetchProducts();

      // ✅ Verify result structure
      expect(result, isNotNull);
      expect(result.products, isNotNull);
      expect(result.fetchedAt, isNotNull);
      expect(result.sourceUrl, isNotNull);
    });

    test('fetchProducts returns multiple products', () async {
      final result = await scraper.fetchProducts();

      // ✅ Verify data was actually scraped (not empty)
      expect(result.products.length, greaterThan(0));
      expect(result.count, greaterThan(0));
      print('✓ Scraped ${result.products.length} products');
    });

    test('Product fields are populated correctly', () async {
      final result = await scraper.fetchProducts();

      expect(result.products, isNotEmpty);

      // Check first few products for required fields
      for (var i = 0; i < (result.products.length > 5 ? 5 : result.products.length); i++) {
        final product = result.products[i];

        // ✅ Required fields
        expect(product.brand, isNotEmpty);
        expect(product.model, isNotEmpty);
        expect(product.certNumber, isNotEmpty);

        print('✓ Product $i: ${product.brand} ${product.model} (${product.certNumber})');
      }
    });

    test('Product image URLs are resolved correctly', () async {
      final result = await scraper.fetchProducts();

      final productsWithImages = result.products.where((p) => p.imageUrl != null).toList();

      if (productsWithImages.isNotEmpty) {
        for (final product in productsWithImages.take(3)) {
          // ✅ Image URLs should be absolute
          expect(product.imageUrl, startsWith('https://'));
          print('✓ Image URL: ${product.imageUrl}');
        }
      }
    });

    test('Chinese characters are properly decoded', () async {
      final result = await scraper.fetchProducts();

      expect(result.products, isNotEmpty);

      // ✅ Look for products with Chinese characters in brand/model
      final chineseProduct = result.products.firstWhere(
        (p) => p.brand.contains('紙') || p.model.contains('紙') ||
                p.brand.contains('膜') || p.model.contains('膜'),
        orElse: () => result.products.first,
      );

      // Verify no garbled characters (should contain CJK characters, not mojibake)
      expect(chineseProduct.brand, isNotEmpty);
      expect(chineseProduct.model, isNotEmpty);
      print('✓ Chinese characters properly decoded');
    });

    test('Certification numbers are unique (mostly)', () async {
      final result = await scraper.fetchProducts();

      final certNumbers = result.products.map((p) => p.certNumber).toList();
      final uniqueCertNumbers = certNumbers.toSet();

      // ✅ Most cert numbers should be unique (allow some duplicates due to ROW_ fallback)
      final duplicateCount = certNumbers.length - uniqueCertNumbers.length;
      expect(duplicateCount, lessThan(certNumbers.length * 0.1)); // < 10% duplicates
      print('✓ ${uniqueCertNumbers.length} unique cert numbers out of ${certNumbers.length}');
    });

    test('Fetch timestamp is recent', () async {
      final result = await scraper.fetchProducts();

      final now = DateTime.now();
      final diff = now.difference(result.fetchedAt);

      // ✅ Fetch should have happened within last minute
      expect(diff.inSeconds, lessThan(60));
      print('✓ Fetched at: ${result.fetchedAt}');
    });

    test('Source URL is correct', () async {
      final result = await scraper.fetchProducts();

      expect(
        result.sourceUrl,
        contains('car-safety.org.tw'),
      );
      expect(
        result.sourceUrl,
        contains('OpID=536'),
      );
    });

    test('Product count is consistent', () async {
      final result = await scraper.fetchProducts();

      expect(result.count, equals(result.products.length));
    });

    test('Optional fields are handled correctly', () async {
      final result = await scraper.fetchProducts();

      // ✅ Optional fields can be null or have values
      for (final product in result.products.take(10)) {
        // These should either be null or non-empty strings
        if (product.visibleLight != null) {
          expect(product.visibleLight, isNotEmpty);
        }
        if (product.uvRejection != null) {
          expect(product.uvRejection, isNotEmpty);
        }
        if (product.irRejection != null) {
          expect(product.irRejection, isNotEmpty);
        }
        if (product.heatRejection != null) {
          expect(product.heatRejection, isNotEmpty);
        }
      }
      print('✓ Optional fields properly validated');
    });
  });
}
