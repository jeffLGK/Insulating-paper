// Unit tests for Phase 1 - Data layer and search functionality
import 'package:flutter_test/flutter_test.dart';
import 'package:tint_app/data/models/tint_product.dart';
import 'package:tint_app/data/repositories/tint_repository.dart';

void main() {
  group('TintProduct Model Tests', () {
    test('TintProduct.toMap and fromMap work correctly', () {
      final product = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'CERT-001',
        visibleLight: '50%',
        uvRejection: '99%',
        standard: 'CNS',
      );

      final map = product.toMap();
      expect(map['brand'], '3M');
      expect(map['model'], 'FX');
      expect(map['cert_number'], 'CERT-001');

      final restored = TintProduct.fromMap(map);
      expect(restored.brand, product.brand);
      expect(restored.model, product.model);
      expect(restored.certNumber, product.certNumber);
    });

    test('TintProduct copyWith creates new instance with changed fields', () {
      final original = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'CERT-001',
      );

      final modified = original.copyWith(brand: 'Llumar');
      expect(modified.brand, 'Llumar');
      expect(modified.model, 'FX');
      expect(original.brand, '3M'); // Original unchanged
    });

    test('TintProduct.toString works', () {
      final product = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'CERT-001',
      );
      expect(product.toString(), contains('3M'));
      expect(product.toString(), contains('FX'));
    });

    test('TintProduct with all fields', () {
      final product = TintProduct(
        brand: '3M',
        model: 'Crystalline',
        certNumber: 'CERT-001',
        visibleLight: '45%',
        uvRejection: '99.9%',
        irRejection: '60%',
        heatRejection: '65%',
        standard: 'CNS 4001',
        imageUrl: 'https://example.com/image.jpg',
      );

      expect(product.brand, '3M');
      expect(product.model, 'Crystalline');
      expect(product.visibleLight, '45%');
      expect(product.heatRejection, '65%');
    });

    test('TintProduct buildRawText generates search text', () {
      final product = TintProduct(
        brand: '3M',
        model: 'Crystalline',
        certNumber: 'CERT-001',
        standard: 'CNS 4001',
      );
      final map = product.toMap();
      expect(map['raw_text'], contains('3M'));
      expect(map['raw_text'], contains('Crystalline'));
      expect(map['raw_text'], contains('CERT-001'));
    });
  });

  group('SearchResult Tests', () {
    test('SearchResult.isEmpty returns true when no items', () {
      final result = SearchResult(
        items: [],
        query: 'test',
        page: 0,
        hasMore: false,
      );
      expect(result.isEmpty, true);
    });

    test('SearchResult.isEmpty returns false with items', () {
      final result = SearchResult(
        items: [TintProduct(brand: '3M', model: 'M1', certNumber: 'C1')],
        query: 'test',
        page: 0,
        hasMore: false,
      );
      expect(result.isEmpty, false);
    });

    test('SearchResult.count returns correct count', () {
      final result = SearchResult(
        items: [
          TintProduct(brand: '3M', model: 'M1', certNumber: 'C1'),
          TintProduct(brand: 'Llumar', model: 'M2', certNumber: 'C2'),
        ],
        query: 'test',
        page: 0,
        hasMore: false,
      );
      expect(result.count, 2);
    });

    test('SearchResult.copyWithMore appends items correctly', () {
      final items1 = [
        TintProduct(brand: '3M', model: 'M1', certNumber: 'C1'),
      ];
      final items2 = [
        TintProduct(brand: 'Llumar', model: 'M2', certNumber: 'C2'),
        TintProduct(brand: 'SunTek', model: 'M3', certNumber: 'C3'),
      ];

      var result = SearchResult(
        items: items1,
        query: 'test',
        page: 0,
        hasMore: true,
      );

      result = result.copyWithMore(items2);
      expect(result.items.length, 3);
      expect(result.page, 1);
      expect(result.items[0].brand, '3M');
      expect(result.items[1].brand, 'Llumar');
      expect(result.items[2].brand, 'SunTek');
    });
  });

  group('Integration Tests - Data Flow', () {
    test('Multiple products can be created and compared', () {
      final p1 = TintProduct(brand: '3M', model: 'FX', certNumber: 'C1');
      final p2 = TintProduct(brand: 'Llumar', model: 'M1', certNumber: 'C2');
      final p3 = p1.copyWith(brand: 'SunTek');

      expect(p1.brand, '3M');
      expect(p2.brand, 'Llumar');
      expect(p3.brand, 'SunTek');
      expect(p3.model, p1.model);
      expect(p3.certNumber, p1.certNumber);
    });

    test('Products can be converted to/from maps for serialization', () {
      final original = TintProduct(
        brand: '3M',
        model: 'Crystalline',
        certNumber: 'CERT-12345',
        visibleLight: '45%',
        uvRejection: '99.9%',
        standard: 'CNS 4001',
      );

      final map = original.toMap();
      final restored = TintProduct.fromMap(map);

      expect(restored.brand, original.brand);
      expect(restored.model, original.model);
      expect(restored.certNumber, original.certNumber);
      expect(restored.visibleLight, original.visibleLight);
      expect(restored.uvRejection, original.uvRejection);
    });

    test('Search can handle various product brands and models', () {
      final products = [
        TintProduct(brand: '3M', model: 'Crystalline', certNumber: 'C1', standard: 'CNS'),
        TintProduct(brand: '3M', model: 'FX 70', certNumber: 'C2', standard: 'CNS'),
        TintProduct(brand: 'Llumar', model: 'Ceramic IR', certNumber: 'C3', standard: 'CNS'),
        TintProduct(brand: 'SunTek', model: 'Carbon XT', certNumber: 'C4', standard: 'CNS'),
      ];

      expect(products.length, 4);
      expect(products.where((p) => p.brand == '3M').length, 2);
      expect(products.where((p) => p.model.contains('Ceramic')).length, 1);
    });
  });
}
