import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 使用 Google ML Kit（離線）對圖片進行文字辨識。
/// 同時執行 Latin 與 Chinese 辨識器，合併結果以支援英文、數字及繁體中文。
class OcrService {
  OcrService._();

  static final _latinRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  static final _chineseRecognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  // 匹配 CJK 統一漢字（涵蓋繁體中文常用字）
  static final _cjkPattern = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]');

  /// 從圖片 bytes 擷取所有可辨識文字，回傳原始字串。
  /// 若平台不支援或辨識失敗，回傳空字串。
  static Future<String> extractText(Uint8List imageBytes) async {
    if (kIsWeb) return '';

    File? tmpFile;
    try {
      final tmpDir = await getTemporaryDirectory();
      final tmpPath =
          '${tmpDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(imageBytes);

      // 為每個辨識器建立獨立的 InputImage，避免原生層併發存取導致閃退
      final latinResult =
          await _latinRecognizer.processImage(InputImage.fromFilePath(tmpPath));
      final chineseResult = await _chineseRecognizer
          .processImage(InputImage.fromFilePath(tmpPath));

      final latinText = latinResult.text.trim();
      final chineseText = chineseResult.text.trim();

      // 從 Chinese 辨識結果中僅提取中文字元（避免重複 Latin 內容）
      final chineseOnly = chineseText
          .split('')
          .where((c) => _cjkPattern.hasMatch(c) || c == ' ' || c == '\n')
          .join()
          .trim();

      if (chineseOnly.isEmpty) return latinText;
      if (latinText.isEmpty) return chineseText;
      return '$latinText\n$chineseOnly';
    } catch (_) {
      return '';
    } finally {
      tmpFile?.delete().catchError((_) {});
    }
  }

  static Future<void> dispose() async {
    await Future.wait([
      _latinRecognizer.close(),
      _chineseRecognizer.close(),
    ]);
  }
}
