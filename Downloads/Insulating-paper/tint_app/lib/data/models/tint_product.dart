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

  @override
  String toString() => 'TintProduct($brand $model, cert: $certNumber)';
}
