import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../data/models/tint_product.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  static Database? _db;

  // Web 平台：記憶體存儲
  static List<TintProduct> _webStore = [];
  static List<int> _webFavorites = [];

  static const String tableProducts = 'tint_products';
  static const String tableFts = 'tint_products_fts';
  static const String tableFavorites = 'favorites';

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'tint_app.db');
    return openDatabase(
      fullPath,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async => await db.rawQuery('PRAGMA journal_mode=WAL;'),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createFavoritesTable(db);
    }
    if (oldVersion < 3) {
      // cert_number 改用 manufacturer+brand+model 組合，清除舊的 IDX_X 資料
      await db.delete(tableProducts);
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
        brand, model, cert_number, standard, raw_text
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
    if (kIsWeb) {
      _webStore = List.from(products);
      return;
    }
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
    if (kIsWeb) {
      final sorted = List<TintProduct>.from(_webStore)
        ..sort((a, b) {
          final c = a.brand.compareTo(b.brand);
          return c != 0 ? c : a.model.compareTo(b.model);
        });
      return sorted.skip(offset).take(limit).toList();
    }
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

    if (kIsWeb) {
      final q = query.trim().toLowerCase();
      var results = _webStore.where((p) {
        final match = p.brand.toLowerCase().contains(q) ||
            p.model.toLowerCase().contains(q) ||
            p.certNumber.toLowerCase().contains(q);
        if (!match) return false;
        if (brandFilter != null && brandFilter.isNotEmpty) {
          return p.brand == brandFilter;
        }
        return true;
      }).toList()
        ..sort((a, b) {
          final c = a.brand.compareTo(b.brand);
          return c != 0 ? c : a.model.compareTo(b.model);
        });
      return results.skip(offset).take(limit).toList();
    }

    final db = await database;
    // 先將所有非字母/數字/中日韓字元（含 FTS5 特殊字元 - + * " () 等）替換成空白，
    // 再以空白切分，過濾空字串。
    // 若清理後無任何 token（如只輸入 -），FTS5 無法處理，
    // 改用 LIKE 對原始查詢做子字串比對（例如 - 可找到 P-40、K-40 等）。
    final cleaned = query.trim()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\u3040-\u30ff]'), ' ');
    final tokens = cleaned.trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      // FTS 無法處理此查詢，改用 LIKE 模糊搜尋原始字串
      final likePattern = '%${query.trim()}%';
      String likeSql = '''
        SELECT * FROM $tableProducts
        WHERE brand LIKE ? OR model LIKE ? OR cert_number LIKE ? OR raw_text LIKE ?
      ''';
      final likeArgs = <dynamic>[
        likePattern, likePattern, likePattern, likePattern,
      ];
      if (brandFilter != null && brandFilter.isNotEmpty) {
        likeSql += ' AND brand = ?';
        likeArgs.add(brandFilter);
      }
      likeSql += ' ORDER BY brand ASC, model ASC LIMIT ? OFFSET ?';
      likeArgs.addAll([limit, offset]);
      final rows = await db.rawQuery(likeSql, likeArgs);
      return rows.map(TintProduct.fromMap).toList();
    }

    final ftsQuery = tokens.map((t) => '$t*').join(' ');
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
    if (kIsWeb) {
      final brands = _webStore.map((p) => p.brand).toSet().toList()..sort();
      return brands;
    }
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT brand FROM $tableProducts ORDER BY brand ASC',
    );
    return rows.map((r) => r['brand'] as String).toList();
  }

  Future<TintProduct?> getProductById(int id) async {
    if (kIsWeb) {
      try {
        return _webStore.firstWhere((p) => p.id == id);
      } catch (_) {
        return null;
      }
    }
    final db = await database;
    final rows = await db.query(tableProducts, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return TintProduct.fromMap(rows.first);
  }

  Future<int> getProductCount() async {
    if (kIsWeb) return _webStore.length;
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $tableProducts');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    if (kIsWeb) {
      _webStore.clear();
      return;
    }
    final db = await database;
    await db.delete(tableProducts);
  }

  Future<void> close() async => _db?.close();
}
