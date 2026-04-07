import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../data/models/tint_product.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  static Database? _db;

  static const String tableProducts = 'tint_products';
  static const String tableFts = 'tint_products_fts';
  static const String tableFavorites = 'favorites';

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String fullPath;
    if (kIsWeb) {
      fullPath = 'tint_app.db';
    } else {
      final dbPath = await getDatabasesPath();
      fullPath = p.join(dbPath, 'tint_app.db');
    }
    return openDatabase(
      fullPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: kIsWeb ? null : (db) async => await db.rawQuery('PRAGMA journal_mode=WAL;'),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createFavoritesTable(db);
    }
  }

  Future<void> _createFavoritesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableFavorites (
        product_id INTEGER PRIMARY KEY,
        added_at   TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableProducts (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        brand          TEXT NOT NULL,
        model          TEXT NOT NULL,
        cert_number    TEXT NOT NULL UNIQUE,
        visible_light  TEXT,
        uv_rejection   TEXT,
        ir_rejection   TEXT,
        heat_rejection TEXT,
        standard       TEXT,
        image_url      TEXT,
        image_local_path TEXT,
        raw_text       TEXT,
        updated_at     TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_brand ON $tableProducts (brand)');
    await db.execute('CREATE INDEX idx_cert  ON $tableProducts (cert_number)');

    await db.execute('''
      CREATE VIRTUAL TABLE $tableFts USING fts5(
        brand,
        model,
        cert_number,
        standard,
        raw_text
      )
    ''');

    await db.execute('''
      CREATE TRIGGER tint_ai AFTER INSERT ON $tableProducts BEGIN
        INSERT INTO $tableFts(rowid, brand, model, cert_number, standard, raw_text)
        VALUES (new.id, new.brand, new.model, new.cert_number, new.standard, new.raw_text);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER tint_ad AFTER DELETE ON $tableProducts BEGIN
        DELETE FROM $tableFts WHERE rowid = old.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER tint_au AFTER UPDATE ON $tableProducts BEGIN
        DELETE FROM $tableFts WHERE rowid = old.id;
        INSERT INTO $tableFts(rowid, brand, model, cert_number, standard, raw_text)
        VALUES (new.id, new.brand, new.model, new.cert_number, new.standard, new.raw_text);
      END
    ''');

    await _createFavoritesTable(db);
  }

  Future<void> upsertProducts(List<TintProduct> products) async {
    final db = await database;
    final batch = db.batch();
    for (final product in products) {
      batch.insert(
        tableProducts,
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<TintProduct>> getAllProducts({int limit = 50, int offset = 0}) async {
    final db = await database;
    final rows = await db.query(
      tableProducts,
      orderBy: 'brand ASC, model ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(TintProduct.fromMap).toList();
  }

  Future<List<TintProduct>> searchProducts(String query, {
    int limit = 50,
    int offset = 0,
    String? brandFilter,
  }) async {
    if (query.trim().isEmpty) {
      return getAllProducts(limit: limit, offset: offset);
    }
    final db = await database;
    final ftsQuery = query.trim().split(RegExp(r'\s+')).join('* ') + '*';
    String sql = '''
      SELECT p.* FROM $tableProducts p
      WHERE p.id IN (
        SELECT rowid FROM $tableFts WHERE $tableFts MATCH ?
      )
    ''';
    final args = <dynamic>[ftsQuery];
    if (brandFilter != null && brandFilter.isNotEmpty) {
      sql += ' AND p.brand = ?';
      args.add(brandFilter);
    }
    sql += ' ORDER BY p.brand ASC, p.model ASC LIMIT ? OFFSET ?';
    args.addAll([limit, offset]);
    final rows = await db.rawQuery(sql, args);
    return rows.map(TintProduct.fromMap).toList();
  }

  Future<List<String>> getAllBrands() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT brand FROM $tableProducts ORDER BY brand ASC',
    );
    return rows.map((r) => r['brand'] as String).toList();
  }

  Future<TintProduct?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query(tableProducts, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return TintProduct.fromMap(rows.first);
  }

  Future<int> getProductCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $tableProducts');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(tableProducts);
  }

  Future<void> close() async => _db?.close();
}
