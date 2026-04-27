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
      version: 5,
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
    if (oldVersion < 4) {
      // Android 不支援 FTS5，改用 FTS4；重建虛擬表與觸發器
      await db.execute('DROP TABLE IF EXISTS $tableFts');
      await db.execute('''
        DROP TRIGGER IF EXISTS tint_ai
      ''');
      await db.execute('DROP TRIGGER IF EXISTS tint_ad');
      await db.execute('DROP TRIGGER IF EXISTS tint_au');
      await _createFtsAndTriggers(db);
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE $tableProducts ADD COLUMN image_phash TEXT',
      );
    }
  }

  Future<void> _createFtsAndTriggers(Database db) async {
    // 使用 FTS4（Android 內建 SQLite 不支援 FTS5）
    await db.execute('''
      CREATE VIRTUAL TABLE $tableFts USING fts4(
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
        image_phash    TEXT,
        raw_text       TEXT,
        updated_at     TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_brand ON $tableProducts (brand)');
    await db.execute('CREATE INDEX idx_cert  ON $tableProducts (cert_number)');

    await _createFtsAndTriggers(db);

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

  Future<List<TintProduct>> getAllProducts({
    int limit = 50,
    int offset = 0,
    Set<String>? brandList,
  }) async {
    final hasBrandList = brandList != null && brandList.isNotEmpty;
    if (kIsWeb) {
      final sorted = List<TintProduct>.from(_webStore)
        ..sort((a, b) {
          final c = a.brand.compareTo(b.brand);
          return c != 0 ? c : a.model.compareTo(b.model);
        });
      final filtered = hasBrandList
          ? sorted.where((p) => brandList.contains(p.brand)).toList()
          : sorted;
      return filtered.skip(offset).take(limit).toList();
    }
    final db = await database;
    String? where;
    List<Object?>? whereArgs;
    if (hasBrandList) {
      final placeholders = List.filled(brandList.length, '?').join(',');
      where = 'brand IN ($placeholders)';
      whereArgs = brandList.toList();
    }
    final rows = await db.query(
      tableProducts,
      where: where,
      whereArgs: whereArgs,
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
    Set<String>? brandList,
  }) async {
    // 進階篩選的多廠牌優先於單一品牌 chip
    final hasBrandList = brandList != null && brandList.isNotEmpty;
    if (query.trim().isEmpty) {
      if (hasBrandList) {
        return getAllProducts(limit: limit, offset: offset, brandList: brandList);
      }
      if (brandFilter == null || brandFilter.isEmpty) {
        return getAllProducts(limit: limit, offset: offset);
      }
      // 無搜尋字但有品牌篩選：直接用 brand = ? 過濾
      if (kIsWeb) {
        return _webStore
            .where((p) => p.brand == brandFilter)
            .toList()
          ..sort((a, b) {
            final c = a.brand.compareTo(b.brand);
            return c != 0 ? c : a.model.compareTo(b.model);
          });
      }
      final db = await database;
      final rows = await db.query(
        tableProducts,
        where: 'brand = ?',
        whereArgs: [brandFilter],
        orderBy: 'brand ASC, model ASC',
        limit: limit,
        offset: offset,
      );
      return rows.map(TintProduct.fromMap).toList();
    }

    // 計算品牌條件子句（多選優先於單選）
    String brandClause = '';
    final List<Object?> brandArgs = [];
    if (hasBrandList) {
      final placeholders = List.filled(brandList.length, '?').join(',');
      brandClause = ' AND brand IN ($placeholders)';
      brandArgs.addAll(brandList);
    } else if (brandFilter != null && brandFilter.isNotEmpty) {
      brandClause = ' AND brand = ?';
      brandArgs.add(brandFilter);
    }

    if (kIsWeb) {
      final q = query.trim().toLowerCase();
      var results = _webStore.where((p) {
        final match = p.brand.toLowerCase().contains(q) ||
            p.model.toLowerCase().contains(q) ||
            p.certNumber.toLowerCase().contains(q);
        if (!match) return false;
        if (hasBrandList) {
          return brandList.contains(p.brand);
        }
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
    // 策略：
    // - 含特殊字元（如 -、+、*）→ 用 LIKE 對 brand/model 做字面子字串比對，
    //   讓 "-k" 找含 "-k" 的品牌/型號，"-" 找含連字號的品牌/型號。
    // - 純英數字/中日韓 → 用 FTS5 前綴搜尋，效能好且支援中文斷詞。
    final hasSpecialChars = query.trim()
        .contains(RegExp(r'[^\w\u4e00-\u9fff\u3040-\u30ff\s]'));

    if (hasSpecialChars) {
      // 含特殊字元：LIKE 搜 brand + model，只搜用戶可見欄位
      final likePattern = '%${query.trim()}%';
      String likeSql = '''
        SELECT * FROM $tableProducts
        WHERE (brand LIKE ? OR model LIKE ?)
      ''';
      final likeArgs = <dynamic>[likePattern, likePattern];
      if (brandClause.isNotEmpty) {
        likeSql += brandClause;
        likeArgs.addAll(brandArgs);
      }
      likeSql += ' ORDER BY brand ASC, model ASC LIMIT ? OFFSET ?';
      likeArgs.addAll([limit, offset]);
      final rows = await db.rawQuery(likeSql, likeArgs);
      return rows.map(TintProduct.fromMap).toList();
    }

    // 純英數字/中日韓：FTS4 前綴搜尋（精確命中）+ LIKE 補全子字串命中
    final tokens = query.trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return getAllProducts(limit: limit, offset: offset);
    }
    final ftsQuery = tokens.map((t) => '$t*').join(' ');

    // ① FTS 前綴搜尋
    String ftsSql = '''
      SELECT p.* FROM $tableProducts p
      WHERE p.id IN (
        SELECT rowid FROM $tableFts WHERE $tableFts MATCH ?
      )
    ''';
    final ftsArgs = <dynamic>[ftsQuery];
    if (brandClause.isNotEmpty) {
      // 此處 brand 欄位來自別名 p
      ftsSql += brandClause.replaceAll('AND brand', 'AND p.brand');
      ftsArgs.addAll(brandArgs);
    }
    final ftsRows = await db.rawQuery(ftsSql, ftsArgs);
    final seen = <String>{};
    final products = <TintProduct>[];
    for (final row in ftsRows) {
      final p = TintProduct.fromMap(row);
      if (seen.add(p.certNumber)) products.add(p);
    }

    // ② LIKE 子字串補全（補捉 FTS 前綴未命中的如 LB7080、TB70）
    final likePattern = '%${query.trim()}%';
    String likeSql = '''
      SELECT * FROM $tableProducts
      WHERE (brand LIKE ? OR model LIKE ?)
    ''';
    final likeArgs = <dynamic>[likePattern, likePattern];
    if (brandClause.isNotEmpty) {
      likeSql += brandClause;
      likeArgs.addAll(brandArgs);
    }
    final likeRows = await db.rawQuery(likeSql, likeArgs);
    for (final row in likeRows) {
      final p = TintProduct.fromMap(row);
      if (seen.add(p.certNumber)) products.add(p);
    }

    // 合併結果排序後套用 limit/offset
    products.sort((a, b) {
      final c = a.brand.compareTo(b.brand);
      return c != 0 ? c : a.model.compareTo(b.model);
    });
    return products.skip(offset).take(limit).toList();
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

  /// 各廠牌名稱 + 該廠牌的產品筆數
  Future<Map<String, int>> getBrandCounts() async {
    if (kIsWeb) {
      final counts = <String, int>{};
      for (final p in _webStore) {
        counts[p.brand] = (counts[p.brand] ?? 0) + 1;
      }
      return Map.fromEntries(
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    }
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT brand, COUNT(*) as cnt FROM $tableProducts GROUP BY brand ORDER BY brand ASC',
    );
    return {
      for (final r in rows) r['brand'] as String: (r['cnt'] as int),
    };
  }

  /// 回傳同品牌+型號的所有產品（涵蓋業者自行烙印與專業機構印製等所有記錄）
  Future<List<TintProduct>> getProductsByBrandModel(
      String brand, String model) async {
    if (kIsWeb) {
      return _webStore
          .where((p) => p.brand == brand && p.model == model)
          .toList();
    }
    final db = await database;
    final rows = await db.query(
      tableProducts,
      where: 'brand = ? AND model = ?',
      whereArgs: [brand, model],
    );
    return rows.map(TintProduct.fromMap).toList();
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

  Future<void> updateImageLocalPath(String certNumber, String localPath) async {
    if (kIsWeb) return;
    final db = await database;
    await db.update(
      tableProducts,
      {'image_local_path': localPath},
      where: 'cert_number = ?',
      whereArgs: [certNumber],
    );
  }

  Future<void> updateImagePhash(String certNumber, String phash) async {
    if (kIsWeb) return;
    final db = await database;
    await db.update(
      tableProducts,
      {'image_phash': phash},
      where: 'cert_number = ?',
      whereArgs: [certNumber],
    );
  }

  /// 回傳所有有本機圖片的產品（用於圖像比對）
  Future<List<TintProduct>> getProductsForMatching() async {
    if (kIsWeb) return [];
    final db = await database;
    final rows = await db.query(
      tableProducts,
      where: 'image_local_path IS NOT NULL AND image_local_path != ""',
      orderBy: 'brand ASC, model ASC',
    );
    return rows.map(TintProduct.fromMap).toList();
  }

  /// 以 LIKE tokens 搜尋品牌＋型號。
  /// AND 策略優先（所有 token 都需符合），無結果時退回 OR 策略。
  ///
  /// tokens：OCR 文字以空白/「-」分割後的列表，例：['V', 'KOOL', 'UXM70']
  Future<List<TintProduct>> searchByLikeTokens(List<String> tokens) async {
    if (tokens.isEmpty) return [];

    if (kIsWeb) {
      final q = tokens.map((t) => t.toLowerCase()).toList();
      bool andMatch(TintProduct p) {
        final c = '${p.brand} ${p.model}'.toLowerCase();
        return q.every((t) => c.contains(t));
      }
      bool orMatch(TintProduct p) {
        final c = '${p.brand} ${p.model}'.toLowerCase();
        return q.any((t) => c.contains(t));
      }
      final andResult = _webStore.where(andMatch).toList();
      return andResult.isNotEmpty ? andResult : _webStore.where(orMatch).toList();
    }

    final db = await database;
    final args = tokens.map((t) => '%$t%').toList();
    final clause = (String op) => tokens
        .map((_) => "(brand || ' ' || model) LIKE ?")
        .join(' $op ');

    // AND 查詢
    var rows = await db.rawQuery(
      'SELECT * FROM $tableProducts WHERE ${clause("AND")} ORDER BY brand ASC, model ASC',
      args,
    );
    if (rows.isNotEmpty) return rows.map(TintProduct.fromMap).toList();

    // OR 退回
    rows = await db.rawQuery(
      'SELECT * FROM $tableProducts WHERE ${clause("OR")} ORDER BY brand ASC, model ASC',
      args,
    );
    return rows.map(TintProduct.fromMap).toList();
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
