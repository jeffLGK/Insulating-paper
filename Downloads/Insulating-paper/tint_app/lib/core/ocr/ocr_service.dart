import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 使用 Google ML Kit（離線）對圖片進行文字辨識。
class OcrService {
  OcrService._();

  static final _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

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

      final inputImage = InputImage.fromFilePath(tmpPath);
      final result = await _recognizer.processImage(inputImage);
      return result.text;
    } catch (_) {
      return '';
    } finally {
      tmpFile?.delete().catchError((_) {});
    }
  }

  static Future<void> dispose() => _recognizer.close();
}
