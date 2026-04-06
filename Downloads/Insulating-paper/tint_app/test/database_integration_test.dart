// Database integration tests
// Tests SQLite operations with real data

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tint_app/core/database/app_database.dart';
import 'package:tint_app/data/models/tint_product.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();

  group('Database Integration Tests', () {
    late AppDatabase db;

    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      db = AppDatabase.instance;
      // Clear database before each test
      await db.clearAll();
    });

    tearDown(() async {
      await db.close();
    });

    test('Upsert single product', () async {
      final product = TintProduct(
        brand: '3M',
        model: 'Crystalline',
        certNumber: 'CERT-001',
        visibleLight: '45%',
        uvRejection: '99.9%',
      );

      await db.upsertProducts([product]);
      final count = await db.getProductCount();

      expect(count, equals(1));
    });

    test('Upsert multiple products', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX1', certNumber: 'C-001'),
        TintProduct(brand: '3M', model: 'FX2', certNumber: 'C-002'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C-003'),
        TintProduct(brand: 'SunTek', model: 'Carbon', certNumber: 'C-004'),
      ];

      await db.upsertProducts(products);
      final count = await db.getProductCount();

      expect(count, equals(4));
    });

    test('Update existing product via upsert', () async {
      final product1 = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'CERT-SAME',
      );

      final product2 = TintProduct(
        brand: 'Llumar',
        model: 'Updated',
        certNumber: 'CERT-SAME', // Same cert_number
      );

      await db.upsertProducts([product1]);
      await db.upsertProducts([product2]);

      final count = await db.getProductCount();
      expect(count, equals(1)); // Should still be 1 (updated, not inserted)

      final product = await db.getProductById(1);
      expect(product?.brand, 'Llumar'); // Should be updated
      expect(product?.model, 'Updated');
    });

    test('UNIQUE constraint on cert_number', () async {
      final product1 = TintProduct(
        brand: '3M',
        model: 'FX',
        certNumber: 'UNIQUE-001',
      );

      await db.upsertProducts([product1]);
      final count1 = await db.getProductCount();
      expect(count1, equals(1));

      // Try to insert same cert_number (should replace)
      final product2 = TintProduct(
        brand: 'SunTek',
        model: 'Different',
        certNumber: 'UNIQUE-001',
      );

      await db.upsertProducts([product2]);
      final count2 = await db.getProductCount();
      expect(count2, equals(1)); // Still 1
    });

    test('getAllProducts with pagination', () async {
      final products = List.generate(
        50,
        (i) => TintProduct(
          brand: 'Brand$i',
          model: 'Model$i',
          certNumber: 'CERT-$i',
        ),
      );

      await db.upsertProducts(products);

      final page1 = await db.getAllProducts(limit: 20, offset: 0);
      expect(page1.length, equals(20));

      final page2 = await db.getAllProducts(limit: 20, offset: 20);
      expect(page2.length, equals(20));

      final page3 = await db.getAllProducts(limit: 20, offset: 40);
      expect(page3.length, equals(10));
    });

    test('getAllBrands returns unique brands', () async {
      final products = [
        TintProduct(brand: '3M', model: 'M1', certNumber: 'C1'),
        TintProduct(brand: '3M', model: 'M2', certNumber: 'C2'),
        TintProduct(brand: 'Llumar', model: 'M3', certNumber: 'C3'),
        TintProduct(brand: 'Llumar', model: 'M4', certNumber: 'C4'),
        TintProduct(brand: 'SunTek', model: 'M5', certNumber: 'C5'),
      ];

      await db.upsertProducts(products);
      final brands = await db.getAllBrands();

      expect(brands.length, equals(3));
      expect(brands, contains('3M'));
      expect(brands, contains('Llumar'));
      expect(brands, contains('SunTek'));
    });

    test('Brands are sorted alphabetically', () async {
      final products = [
        TintProduct(brand: 'Zulu', model: 'M1', certNumber: 'C1'),
        TintProduct(brand: 'Apple', model: 'M2', certNumber: 'C2'),
        TintProduct(brand: 'Mango', model: 'M3', certNumber: 'C3'),
      ];

      await db.upsertProducts(products);
      final brands = await db.getAllBrands();

      expect(brands[0], 'Apple');
      expect(brands[1], 'Mango');
      expect(brands[2], 'Zulu');
    });

    test('searchProducts finds by brand', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C2'),
      ];

      await db.upsertProducts(products);
      final results = await db.searchProducts('3M');

      expect(results.length, greaterThan(0));
      expect(results.any((p) => p.brand == '3M'), true);
    });

    test('searchProducts finds by model', () async {
      final products = [
        TintProduct(brand: '3M', model: 'Crystalline', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic IR', certNumber: 'C2'),
      ];

      await db.upsertProducts(products);
      final results = await db.searchProducts('Crystalline');

      expect(results.length, greaterThan(0));
      expect(results.any((p) => p.model.contains('Crystalline')), true);
    });

    test('searchProducts with brand filter', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: '3M', model: 'Crystalline', certNumber: 'C2'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C3'),
      ];

      await db.upsertProducts(products);
      final results = await db.searchProducts(
        'FX',
        brandFilter: '3M',
      );

      expect(
        results.every((p) => p.brand == '3M'),
        true,
      );
    });

    test('searchProducts with empty query', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C2'),
      ];

      await db.upsertProducts(products);
      final results = await db.searchProducts('');

      expect(results.length, equals(2));
    });

    test('getProductById retrieves specific product', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C2'),
      ];

      await db.upsertProducts(products);
      final product = await db.getProductById(1);

      expect(product, isNotNull);
      expect(product?.brand, '3M');
      expect(product?.model, 'FX');
    });

    test('getProductById returns null for non-existent id', () async {
      final product = await db.getProductById(999);
      expect(product, isNull);
    });

    test('getProductCount returns correct count', () async {
      expect(await db.getProductCount(), equals(0));

      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C2'),
        TintProduct(brand: 'SunTek', model: 'Carbon', certNumber: 'C3'),
      ];

      await db.upsertProducts(products);
      expect(await db.getProductCount(), equals(3));
    });

    test('FTS search performance with large dataset', () async {
      // Insert 100 products
      final products = List.generate(
        100,
        (i) => TintProduct(
          brand: i % 3 == 0 ? '3M' : (i % 3 == 1 ? 'Llumar' : 'SunTek'),
          model: 'Model-${i ~/ 10}',
          certNumber: 'CERT-$i',
          standard: i % 2 == 0 ? 'CNS 4001' : 'ISO 12345',
        ),
      );

      await db.upsertProducts(products);

      final stopwatch = Stopwatch()..start();
      final results = await db.searchProducts('3M');
      stopwatch.stop();

      expect(results.length, greaterThan(0));
      print('✓ FTS search completed in ${stopwatch.elapsedMilliseconds}ms');
    });

    test('Multiple searches return consistent results', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'Ceramic', certNumber: 'C2'),
      ];

      await db.upsertProducts(products);

      final results1 = await db.searchProducts('3M');
      final results2 = await db.searchProducts('3M');

      expect(results1.length, equals(results2.length));
      expect(
        results1.map((p) => p.certNumber).toList(),
        equals(results2.map((p) => p.certNumber).toList()),
      );
    });
  });
}
