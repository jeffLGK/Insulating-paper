// lib/features/cert_search/cert_search_screen.dart
//
// 合格標識序號線上查詢畫面
// 規則：
//   - 輸入自動轉大寫、只允許英數字及空格
//   - 必須以 FA 或 SA 開頭
//   - 空格代表萬用字元（轉成 % 送 API）
//   - 查詢結果來自線上 API，需要連網

import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../data/datasources/car_safety_scraper.dart';
import '../../data/models/tint_product.dart';

class CertSearchScreen extends StatefulWidget {
  const CertSearchScreen({super.key});

  @override
  State<CertSearchScreen> createState() => _CertSearchScreenState();
}

class _CertSearchScreenState extends State<CertSearchScreen> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  List<TintProduct>? _results;
  String? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── 輸入處理 ─────────────────────────────────────────────────────

  String _processInput(String raw) {
    // 轉大寫、只保留英文字母、數字、空格
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), '');
  }

  bool _hasValidPrefix(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('FA') || trimmed.startsWith('SA');
  }

  /// 數字部分固定 8 碼（不足補前導 0）
  static const int _numberLength = 8;

  bool get _canSearch {
    final v = _controller.text.trim();
    // 必須有前綴且前綴後至少有 1 個數字
    if (!_hasValidPrefix(v) || v.length < 3) return false;
    if (_isSearching) return false;
    // 去掉前綴與空格後必須全是數字
    final digits = v.substring(2).replaceAll(' ', '');
    return digits.isNotEmpty && RegExp(r'^\d+$').hasMatch(digits);
  }

  /// 前綴（FA/SA）+ 數字部分去掉空格後補前導 0 至 8 碼
  String get _apiQuery {
    final v = _controller.text.trim();
    final prefix = v.substring(0, 2);                        // FA 或 SA
    final digits = v.substring(2).replaceAll(' ', '');       // 純數字
    final padded = digits.padLeft(_numberLength, '0');       // 補 0 至 8 碼
    return '$prefix$padded';
  }

  /// 顯示用：與 _apiQuery 相同（讓使用者確認實際查詢序號）
  String get _displayPattern => _apiQuery;

  // ── 查詢 ──────────────────────────────────────────────────────────

  Future<void> _search() async {
    if (!_canSearch) return;
    final query = _apiQuery;
    _lastQuery = _displayPattern;

    setState(() {
      _isSearching = true;
      _results = null;
      _error = null;
    });

    try {
      final scraper = CarSafetyScraper();
      final products = await scraper.searchByCertSerial(query);
      if (mounted) {
        setState(() {
          _results = products;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '查詢失敗：$e';
          _isSearching = false;
        });
      }
    }
  }

  // ── 畫面 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('合格標識序號查詢')),
      body: Column(
        children: [
          // ── 連網提示 ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(Icons.wifi, size: 18, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  '此功能需要連接網路才可查詢',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // ── 輸入區 ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          _UpperCaseAlphanumFormatter(),
                        ],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: '例：SA 678 → SA00000678',
                          prefixIcon: const Icon(Icons.qr_code_scanner),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _controller.clear();
                                    setState(() {
                                      _results = null;
                                      _error = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _canSearch ? _search : null,
                      icon: _isSearching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.search),
                      label: const Text('查詢'),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // 格式提示 / 驗證訊息
                _buildInputHint(),
              ],
            ),
          ),

          // ── 結果區 ──────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildInputHint() {
    final input = _controller.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    if (input.isEmpty) {
      return Text(
        '格式說明：必須以 FA 或 SA 開頭，後接數字。\n'
        '空格可分隔數字，系統自動補 0 至 8 碼。\n'
        '例：SA 678 → 查詢 SA00000678　　SA 55555 → 查詢 SA00055555',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
      );
    }
    if (!_hasValidPrefix(input)) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '序號必須以 FA 或 SA 開頭',
            style: TextStyle(color: colorScheme.error, fontSize: 13),
          ),
        ],
      );
    }
    // 檢查前綴後是否有非數字字元（空格除外）
    final digits = input.substring(2).replaceAll(' ', '');
    if (digits.isNotEmpty && !RegExp(r'^\d+$').hasMatch(digits)) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '前綴後只能輸入數字與空格',
            style: TextStyle(color: colorScheme.error, fontSize: 13),
          ),
        ],
      );
    }
    if (digits.isEmpty) {
      return Text(
        '請輸入序號的數字部分（系統將自動補 0 至 8 碼）',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
      );
    }
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          '實際查詢序號：$_displayPattern',
          style: TextStyle(
            color: colorScheme.primary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('線上查詢中，請稍候...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 56,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.refresh),
                label: const Text('重新查詢'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results == null) {
      // 尚未查詢
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 72,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              '輸入合格標識序號後點選「查詢」',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    if (_results!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 64,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '查無「$_lastQuery」的認證資料',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    // 顯示結果列表
    return Column(
      children: [
        // 結果筆數
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '「$_lastQuery」共找到 ${_results!.length} 筆',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: _results!.length,
            itemBuilder: (context, i) =>
                _CertResultCard(product: _results![i]),
          ),
        ),
      ],
    );
  }
}

// ── 萬用字元輸入格式化 ────────────────────────────────────────────────
class _UpperCaseAlphanumFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final processed =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), '');
    if (processed == newValue.text) return newValue;
    return newValue.copyWith(
      text: processed,
      selection: TextSelection.collapsed(offset: processed.length),
    );
  }
}

// ── 查詢結果卡片 ─────────────────────────────────────────────────────
class _CertResultCard extends StatelessWidget {
  final TintProduct product;
  const _CertResultCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _CertProductDetailScreen(product: product),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 縮圖
              _CertThumbnail(product: product),
              const SizedBox(width: 14),
              // 資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${product.brand}  ${product.model}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 序號（醒目顯示）
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '序號：${product.certNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (product.visibleLight != null)
                          _CertChip(
                            label: '可見光',
                            value: product.visibleLight!,
                            color: _vlColor(product.visibleLight!),
                          ),
                        if (product.standard != null) ...[
                          const SizedBox(width: 6),
                          _CertChip(
                            label: '標準',
                            value: product.standard!,
                            color: Colors.blueGrey.shade400,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Color _vlColor(String value) {
    final n = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (n == null) return Colors.blueGrey.shade600;
    if (n >= 70) return Colors.green.shade600;
    if (n >= 40) return Colors.amber.shade700;
    return Colors.red.shade600;
  }
}

class _CertChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CertChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final textColor =
        color.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(6)),
      child: Text('$label $value',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
    );
  }
}

class _CertThumbnail extends StatelessWidget {
  final TintProduct product;
  const _CertThumbnail({required this.product});

  @override
  Widget build(BuildContext context) {
    // 優先本機圖片
    final localPath = product.firstImageLocalPath;
    final url = product.firstImageUrl;

    Widget img;
    if (!kIsWeb && localPath != null) {
      img = Image.file(File(localPath),
          width: 56, height: 56, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context));
    } else if (url != null) {
      img = CachedNetworkImage(
          imageUrl: url,
          width: 56, height: 56, fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(context),
          errorWidget: (_, __, ___) => _placeholder(context));
    } else {
      img = _placeholder(context);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: img);
  }

  Widget _placeholder(BuildContext context) => Container(
        width: 56, height: 56,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.local_car_wash, size: 28),
      );
}

// ── 合格標識序號查詢結果詳細頁 ───────────────────────────────────────
class _CertProductDetailScreen extends StatelessWidget {
  final TintProduct product;
  const _CertProductDetailScreen({required this.product});

  @override
  Widget build(BuildContext context) {
    final localPaths = product.imageLocalPaths;
    final networkUrls = product.imageUrls;
    final hasLocal = !kIsWeb && localPaths.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('產品詳細資料')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 合格標識圖片
          if (hasLocal || networkUrls.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: hasLocal
                  ? localPaths
                      .map((p) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(p),
                                height: 180,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink()),
                          ))
                      .toList()
                  : networkUrls
                      .map((url) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              height: 180,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const SizedBox(
                                  width: 120,
                                  height: 180,
                                  child: Center(
                                      child: CircularProgressIndicator())),
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ))
                      .toList(),
            ),
          const SizedBox(height: 20),

          // 標題
          Text(
            '${product.brand}  ${product.model}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 序號醒目標示
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined,
                    size: 18,
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  '合格標識序號：${product.certNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          // 規格表
          _SpecTable(product: product),

          // 更新時間
          if (product.updatedAt != null) ...[
            const SizedBox(height: 16),
            Text(
              '資料更新：${DateFormat('yyyy-MM-dd HH:mm').format(product.updatedAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecTable extends StatelessWidget {
  final TintProduct product;
  const _SpecTable({required this.product});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (product.visibleLight != null)
        MapEntry('可見光穿透率', product.visibleLight!),
      if (product.uvRejection != null)
        MapEntry('紫外線阻隔率', product.uvRejection!),
      if (product.irRejection != null)
        MapEntry('紅外線阻隔率', product.irRejection!),
      if (product.heatRejection != null)
        MapEntry('總熱能阻隔率', product.heatRejection!),
      if (product.standard != null) MapEntry('符合標準', product.standard!),
    ];

    if (rows.isEmpty) return const Text('無詳細規格資料');

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      border: TableBorder.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      children: rows.map((e) {
        return TableRow(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(e.key,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(e.value),
          ),
        ]);
      }).toList(),
    );
  }
}
