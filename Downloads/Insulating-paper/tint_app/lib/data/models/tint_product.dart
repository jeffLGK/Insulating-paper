class TintProduct {
  final int? id;
  final String brand;
  final String model;
  final String certNumber;
  final String? visibleLight;
  final String? uvRejection;
  final String? irRejection;
  final String? heatRejection;
  final String? standard;
  final String? imageUrl;
  final String? imageLocalPath;
  final String? imagePhash;
  final String? rawText;
  final DateTime? updatedAt;

  const TintProduct({
    this.id,
    required this.brand,
    required this.model,
    required this.certNumber,
    this.visibleLight,
    this.uvRejection,
    this.irRejection,
    this.heatRejection,
    this.standard,
    this.imageUrl,
    this.imageLocalPath,
    this.imagePhash,
    this.rawText,
    this.updatedAt,
  });

  factory TintProduct.fromMap(Map<String, dynamic> map) {
    return TintProduct(
      id: map['id'] as int?,
      brand: map['brand'] as String? ?? '',
      model: map['model'] as String? ?? '',
      certNumber: map['cert_number'] as String? ?? '',
      visibleLight: map['visible_light'] as String?,
      uvRejection: map['uv_rejection'] as String?,
      irRejection: map['ir_rejection'] as String?,
      heatRejection: map['heat_rejection'] as String?,
      standard: map['standard'] as String?,
      imageUrl: map['image_url'] as String?,
      imageLocalPath: map['image_local_path'] as String?,
      imagePhash: map['image_phash'] as String?,
      rawText: map['raw_text'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'brand': brand,
      'model': model,
      'cert_number': certNumber,
      'visible_light': visibleLight,
      'uv_rejection': uvRejection,
      'ir_rejection': irRejection,
      'heat_rejection': heatRejection,
      'standard': standard,
      'image_url': imageUrl,
      'image_local_path': imageLocalPath,
      'image_phash': imagePhash,
      'raw_text': rawText ?? _buildRawText(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  String _buildRawText() {
    return [brand, model, certNumber, standard ?? ''].join(' ');
  }

  TintProduct copyWith({
    int? id,
    String? brand,
    String? model,
    String? certNumber,
    String? visibleLight,
    String? uvRejection,
    String? irRejection,
    String? heatRejection,
    String? standard,
    String? imageUrl,
    String? imageLocalPath,
    String? imagePhash,
    String? rawText,
    DateTime? updatedAt,
  }) {
    return TintProduct(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      certNumber: certNumber ?? this.certNumber,
      visibleLight: visibleLight ?? this.visibleLight,
      uvRejection: uvRejection ?? this.uvRejection,
      irRejection: irRejection ?? this.irRejection,
      heatRejection: heatRejection ?? this.heatRejection,
      standard: standard ?? this.standard,
      imageUrl: imageUrl ?? this.imageUrl,
      imageLocalPath: imageLocalPath ?? this.imageLocalPath,
      imagePhash: imagePhash ?? this.imagePhash,
      rawText: rawText ?? this.rawText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 解析 image_url 欄位（逗號分隔）回傳所有圖片
  List<String> get imageUrls {
    if (imageUrl == null || imageUrl!.isEmpty) return [];
    return imageUrl!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 縮圖用：只取第一張
  String? get firstImageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// 解析 image_local_path 欄位（逗號分隔）回傳所有本機圖片路徑
  List<String> get imageLocalPaths {
    if (imageLocalPath == null || imageLocalPath!.isEmpty) return [];
    return imageLocalPath!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 縮圖用：只取第一張本機路徑
  String? get firstImageLocalPath =>
      imageLocalPaths.isEmpty ? null : imageLocalPaths.first;

  /// 根據 URL 的 hash 值找到對應的本機路徑，不依賴 index 順序。
  /// 下載時以 '${url.hashCode.abs()}.jpg' 命名，因此可逆向比對。
  String? localPathForUrl(String url) {
    final expectedFilename = '${url.hashCode.abs()}.jpg';
    for (final path in imageLocalPaths) {
      // 取路徑最後一段（檔名），相容 Android / Windows 路徑分隔符
      final filename = path.replaceAll('\\', '/').split('/').last;
      if (filename == expectedFilename) return path;
    }
    return null;
  }

  /// 業者自行烙印圖的本機路徑。
  /// 優先找 imageUrls 中不含「範例」的 URL 所對應的本機檔案；
  /// 若所有 URL 都含「範例」或均未下載，fallback 到最後一筆本機路徑。
  String? get selfBrandedImageLocalPath {
    for (final url in imageUrls) {
      if (!url.contains('範例')) {
        final lp = localPathForUrl(url);
        if (lp != null) return lp;
      }
    }
    // fallback：業者烙印圖通常排在後面
    final paths = imageLocalPaths;
    return paths.isNotEmpty ? paths.last : null;
  }

  /// 業者自行烙印圖的網路 URL（本機無檔案時 fallback 使用）。
  /// 優先取不含「範例」的 URL。
  String? get selfBrandedImageUrl {
    for (final url in imageUrls) {
      if (!url.contains('範例')) return url;
    }
    return firstImageUrl;
  }

  @override
  String toString() => 'TintProduct($brand $model, cert: $certNumber)';
}
