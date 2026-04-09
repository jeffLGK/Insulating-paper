import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageHasher {
  /// 計算感知雜湊（pHash）。
  /// 回傳 64 字元的二進位字串（'0'/'1'）。
  static String computePHash(img.Image image) {
    // 1. 縮放至 32×32
    final resized = img.copyResize(image, width: 32, height: 32);
    // 2. 灰階化
    final gray = img.grayscale(resized);

    // 3. 取得每個像素的亮度值 [0.0, 1.0]
    final pixels = List.generate(
      32,
      (y) => List.generate(32, (x) {
        final pixel = gray.getPixel(x, y);
        return pixel.r.toDouble() / 255.0;
      }),
    );

    // 4. 2D DCT
    final dct = _dct2d(pixels);

    // 5. 取左上角 8×8 低頻分量
    final lowFreq = <double>[];
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        lowFreq.add(dct[y][x]);
      }
    }

    // 6. 計算均值（排除 DC 分量 [0][0]）
    final values = lowFreq.skip(1).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;

    // 7. 產生雜湊字串
    return lowFreq.map((v) => v > mean ? '1' : '0').join();
  }

  /// 計算兩個 pHash 字串的漢明距離
  static int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) return hash1.length;
    int dist = 0;
    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) dist++;
    }
    return dist;
  }

  /// pHash 相似度（0.0 = 完全不同，1.0 = 完全相同）
  static double pHashSimilarity(String hash1, String hash2) =>
      1.0 - hammingDistance(hash1, hash2) / 64.0;

  /// 計算 RGB 色彩直方圖（各 64 bins，共 192 維），結果已正規化
  static List<double> computeHistogram(img.Image image) {
    const bins = 64;
    final rHist = List<double>.filled(bins, 0.0);
    final gHist = List<double>.filled(bins, 0.0);
    final bHist = List<double>.filled(bins, 0.0);

    int pixelCount = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final ri = (pixel.r.toDouble() * (bins - 1) / 255)
            .round()
            .clamp(0, bins - 1);
        final gi = (pixel.g.toDouble() * (bins - 1) / 255)
            .round()
            .clamp(0, bins - 1);
        final bi = (pixel.b.toDouble() * (bins - 1) / 255)
            .round()
            .clamp(0, bins - 1);
        rHist[ri]++;
        gHist[gi]++;
        bHist[bi]++;
        pixelCount++;
      }
    }

    if (pixelCount == 0) return List<double>.filled(bins * 3, 0.0);

    final result = <double>[];
    for (final hist in [rHist, gHist, bHist]) {
      result.addAll(hist.map((v) => v / pixelCount));
    }
    return result;
  }

  /// 直方圖交集相似度（0.0 ~ 1.0）
  static double histogramSimilarity(List<double> h1, List<double> h2) {
    if (h1.length != h2.length) return 0.0;
    double intersection = 0.0;
    for (int i = 0; i < h1.length; i++) {
      intersection += min(h1[i], h2[i]);
    }
    // 每個通道的最大交集為 1/3，三通道共 1.0
    return intersection;
  }

  // ─── 內部方法 ───────────────────────────────────────────────

  static List<double> _dct1d(List<double> input) {
    final n = input.length;
    final output = List<double>.filled(n, 0.0);
    for (int k = 0; k < n; k++) {
      double sum = 0.0;
      for (int i = 0; i < n; i++) {
        sum += input[i] * cos(pi * k * (2 * i + 1) / (2 * n));
      }
      output[k] = sum;
    }
    return output;
  }

  static List<List<double>> _dct2d(List<List<double>> pixels) {
    final n = pixels.length;
    final m = pixels[0].length;

    // 行方向 DCT
    final rowDct = pixels.map(_dct1d).toList();

    // 列方向 DCT
    final result = List.generate(n, (_) => List<double>.filled(m, 0.0));
    for (int x = 0; x < m; x++) {
      final col = List.generate(n, (y) => rowDct[y][x]);
      final dctCol = _dct1d(col);
      for (int y = 0; y < n; y++) {
        result[y][x] = dctCol[y];
      }
    }
    return result;
  }

  /// 從圖片 bytes 計算 pHash（供 isolate 使用的純函式）
  static String? hashFromBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return computePHash(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 從圖片 bytes 計算縮圖直方圖（供 isolate 使用的純函式）
  static List<double>? histFromBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: 64, height: 64);
      return computeHistogram(resized);
    } catch (_) {
      return null;
    }
  }
}
