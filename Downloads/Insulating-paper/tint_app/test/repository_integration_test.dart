// Repository integration tests
// Tests the data access layer with real database

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tint_app/core/database/app_database.dart';
import 'package:tint_app/data/models/tint_product.dart';
import 'package:tint_app/data/repositories/tint_repository.dart';

void main() {
  sqfliteFfiInit();

  group('TintRepository Integration Tests', () {
    late TintRepository repo;
    late AppDatabase db;

    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      db = AppDatabase.instance;
      repo = TintRepository(db: db);

      await db.clearAll();

      // Setup test data
      final products = [
        TintProduct(
          brand: '3M',
          model: 'Crystalline',
          certNumber: 'CERT-001',
          visibleLight: '45%',
          standard: 'CNS 4001',
        ),
        TintProduct(
          brand: '3M',
          model: 'FX 70',
          certNumber: 'CERT-002',
          visibleLight: '70%',
          standard: 'CNS 4001',
        ),
        TintProduct(
          brand: '3M',
          model: 'FX 55',
          certNumber: 'CERT-003',
          visibleLight: '55%',
          standard: 'CNS 4001',
        ),
        TintProduct(
          brand: 'Llumar',
          model: 'Ceramic IR',
          certNumber: 'CERT-004',
          visibleLight: '50%',
          standard: 'ISO 12345',
        ),
        TintProduct(
          brand: 'Llumar',
          model: 'Quantum',
          certNumber: 'CERT-005',
          visibleLight: '65%',
          standard: 'ISO 12345',
        ),
        TintProduct(
          brand: 'SunTek',
          model: 'Carbon XT',
          certNumber: 'CERT-006',
          visibleLight: '35%',
          standard: 'ASTM E1428',
        ),
      ];

      await db.upsertProducts(products);
    });

    tearDown(() async {
      await db.close();
    });

    test('search returns products matching brand', () async {
      final result = await repo.search(query: '3M');

      expect(result.items.isNotEmpty, true);
      expect(
        result.items.every((p) => p.brand.contains('3M')),
        true,
      );
    });

    test('search returns products matching model', () async {
      final result = await repo.search(query: 'Crystalline');

      expect(result.items.isNotEmpty, true);
      expect(
        result.items.any((p) => p.model.contains('Crystalline')),
        true,
      );
    });

    test('search with multiple keywords', () async {
      final result = await repo.search(query: '3M Crystalline');

      expect(result.items.isNotEmpty, true);
    });

    test('search with brand filter restricts results', () async {
      final result = await repo.search(
        query: 'IR',
        brandFilter: 'Llumar',
      );

      expect(
        result.items.every((p) => p.brand == 'Llumar'),
        true,
      );
    });

    test('search with brand filter only', () async {
      final result = await repo.search(
        query: '',
        brandFilter: '3M',
      );

      expect(
        result.items.every((p) => p.brand == '3M'),
        true,
      );
      expect(result.items.length, equals(3)); // 3M has 3 products
    });

    test('search handles no matches', () async {
      final result = await repo.search(query: 'NonExistentBrand');

      expect(result.items.isEmpty, true);
    });

    test('search returns paginated results', () async {
      final result = await repo.search(
        query: '3M',
        page: 0,
        pageSize: 2,
      );

      expect(result.items.length, lessThanOrEqualTo(2));
    });

    test('getAll returns all products', () async {
      final result = await repo.getAll();

      expect(result.items.length, equals(6));
    });

    test('getAll with pagination', () async {
      final page1 = await repo.getAll(page: 0, pageSize: 2);
      expect(page1.items.length, equals(2));

      final page2 = await repo.getAll(page: 1, pageSize: 2);
      expect(page2.items.length, equals(2));

      final page3 = await repo.getAll(page: 2, pageSize: 2);
      expect(page3.items.length, equals(2));
    });

    test('getBrands returns unique brands', () async {
      final brands = await repo.getBrands();

      expect(brands.length, equals(3));
      expect(brands, contains('3M'));
      expect(brands, contains('Llumar'));
      expect(brands, contains('SunTek'));
    });

    test('getBrands returns sorted brands', () async {
      final brands = await repo.getBrands();

      // Should be sorted alphabetically
      expect(brands[0], equals('3M'));
      expect(brands[1], equals('Llumar'));
      expect(brands[2], equals('SunTek'));
    });

    test('getTotalCount returns correct count', () async {
      final count = await repo.getTotalCount();
      expect(count, equals(6));
    });

    test('getById retrieves specific product', () async {
      final product = await repo.getById(1);

      expect(product, isNotNull);
      expect(product?.brand, '3M');
      expect(product?.model, 'Crystalline');
    });

    test('getById returns null for non-existent id', () async {
      final product = await repo.getById(999);
      expect(product, isNull);
    });
  });

  group('SearchResult Tests', () {
    test('SearchResult isEmpty detection', () {
      final emptyResult = SearchResult(
        items: [],
        query: 'test',
        page: 0,
        hasMore: false,
      );

      expect(emptyResult.isEmpty, true);
      expect(emptyResult.count, equals(0));
    });

    test('SearchResult with items', () {
      final items = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'M1', certNumber: 'C2'),
      ];

      final result = SearchResult(
        items: items,
        query: 'test',
        page: 0,
        hasMore: true,
      );

      expect(result.isEmpty, false);
      expect(result.count, equals(2));
      expect(result.hasMore, true);
    });

    test('SearchResult copyWithMore appends items', () {
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

      expect(result.items.length, equals(3));
      expect(result.page, equals(1));
      expect(result.items[0].brand, '3M');
      expect(result.items[1].brand, 'Llumar');
      expect(result.items[2].brand, 'SunTek');
    });

    test('SearchResult tracks pagination state', () {
      final result = SearchResult(
        items: [TintProduct(brand: '3M', model: 'M1', certNumber: 'C1')],
        query: 'search',
        page: 2,
        hasMore: false,
      );

      expect(result.query, 'search');
      expect(result.page, equals(2));
      expect(result.hasMore, false);
    });
  });

  group('Repository Data Consistency Tests', () {
    late TintRepository repo;
    late AppDatabase db;

    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      db = AppDatabase.instance;
      repo = TintRepository(db: db);
      await db.clearAll();
    });

    tearDown(() async {
      await db.close();
    });

    test('Multiple searches return consistent results', () async {
      final products = [
        TintProduct(brand: '3M', model: 'FX', certNumber: 'C1'),
        TintProduct(brand: 'Llumar', model: 'M1', certNumber: 'C2'),
        TintProduct(brand: '3M', model: 'Crystalline', certNumber: 'C3'),
      ];

      await db.upsertProducts(products);

      final result1 = await repo.search(query: '3M');
      final result2 = await repo.search(query: '3M');

      expect(result1.items.length, equals(result2.items.length));
      expect(
        result1.items.map((p) => p.certNumber).toList(),
        equals(result2.items.map((p) => p.certNumber).toList()),
      );
    });

    test('Brand list is consistent with products', () async {
      final products = [
        TintProduct(brand: 'Apple', model: 'M1', certNumber: 'C1'),
        TintProduct(brand: 'Banana', model: 'M2', certNumber: 'C2'),
        TintProduct(brand: 'Apple', model: 'M3', certNumber: 'C3'),
      ];

      await db.upsertProducts(products);

      final brands = await repo.getBrands();
      expect(brands.length, equals(2));
      expect(brands, contains('Apple'));
      expect(brands, contains('Banana'));
    });

    test('Total count matches getAll length', () async {
      final products = List.generate(
        10,
        (i) => TintProduct(
          brand: 'Brand$i',
          model: 'Model$i',
          certNumber: 'C$i',
        ),
      );

      await db.upsertProducts(products);

      final count = await repo.getTotalCount();
      final allProducts = await repo.getAll();

      expect(count, equals(allProducts.items.length));
    });
  });
}
