// LabelTextParser 規則測試：涵蓋 OCR 誤讀對應、廠牌特殊規則與回歸案例。
import 'package:flutter_test/flutter_test.dart';
import 'package:tint_app/core/ocr/label_text_parser.dart';

void main() {
  List<String> tk(String raw) => LabelTextParser.parse(raw).tokens;

  group('OCR 誤讀對應（邊界保護）', () {
    test('CPX46 → CLEARPLEX46（前綴取代仍生效）', () {
      expect(tk('Clear Plex\nCPX46'), contains('CLEARPLEX46'));
    });

    test('獨立 550 → S50', () {
      expect(tk('XYZ 550'), contains('S50'));
    });

    test('回歸：FSK BW550 不可被 550→S50 誤傷', () {
      final tokens = tk('FSK\nBW550 VLT>40');
      expect(tokens, contains('BW550'));
      expect(tokens, isNot(contains('BWS50')));
    });

    test('G570 → GS70', () {
      expect(tk('GREENWAY\nG570'), contains('GS70'));
    });
  });

  group('COSMI：底線還原為連字號', () {
    test('COSMI KT_50 → KT-50', () {
      expect(tk('COSMI\nKT_50'), contains('KT-50'));
    });
    test('非 COSMI 不受影響', () {
      // 其他廠牌的底線不應被改（這裡僅確認規則有品牌條件）
      expect(tk('OTHER\nAB_50'), isNot(contains('AB-50')));
    });
  });

  group('CAROYAL：系列裸數字補字母前綴', () {
    test('SUPREME 70 → SUPREME S7', () {
      final t = tk('CAROYAL\nSUPREME VLT 70');
      expect(t, containsAll(['SUPREME', 'S7']));
    });
    test('R.SUPREME 70 → RS7（須先於 SUPREME 規則）', () {
      expect(tk('CAROYAL\nR.SUPREME VLT 70'), contains('RS7'));
    });
    test('GLORY 45 → GLORY G45', () {
      expect(tk('CAROYAL\nGLORY VLT 45'), containsAll(['GLORY', 'G45']));
    });
    test('CAT 70 → CAT70', () {
      expect(tk('CAROYAL\nCAT 70'), contains('CAT70'));
    });
  });

  group('KORAAN：去除尾端獨立可見光數字', () {
    test('KN-N70 70 UP → 保留 KN-N70、移除尾端 70', () {
      final t = tk('KORAAN\nKN-N70 70 UP');
      expect(t, contains('KN-N70'));
      expect(t, isNot(contains('70')));
    });
    test('GIA50 40 UP → 保留 GIA50、移除尾端 40', () {
      final t = tk('KORAAN\nGIA50 40 UP');
      expect(t, contains('GIA50'));
      expect(t, isNot(contains('40')));
    });
  });

  group('既有行為回歸', () {
    test('觸發字串移除：MOT40 40% → 空', () {
      expect(tk('MOT40 40%'), isEmpty);
    });
    test('保留型號內連字號：AI-40', () {
      expect(tk('AI-40'), contains('AI-40'));
    });
  });
}
