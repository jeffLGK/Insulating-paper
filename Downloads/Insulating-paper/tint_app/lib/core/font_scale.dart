// lib/core/font_scale.dart
//
// 全域字體大小設定（C 方案）。
//   - 透過 SharedPreferences 持久化使用者選擇
//   - main.dart 在啟動時預載入並注入 ProviderScope override，避免字級閃爍
//   - main.dart 透過 MaterialApp.builder 套用 MediaQuery.textScaler，
//     會同步放大「textTheme 預設值」與「寫死 fontSize 的 Text」

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPrefFontScale = 'font_scale';

enum FontScale {
  small('小', 0.9),
  medium('中', 1.0),
  large('大', 1.15),
  xlarge('特大', 1.3);

  final String label;
  final double factor;
  const FontScale(this.label, this.factor);

  static FontScale fromName(String? name) {
    if (name == null) return FontScale.medium;
    return FontScale.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FontScale.medium,
    );
  }
}

/// 從 SharedPreferences 同步讀取目前選擇（main() 啟動時呼叫）。
Future<FontScale> loadInitialFontScale() async {
  final prefs = await SharedPreferences.getInstance();
  return FontScale.fromName(prefs.getString(kPrefFontScale));
}

class FontScaleNotifier extends Notifier<FontScale> {
  final FontScale _initial;
  FontScaleNotifier(this._initial);

  @override
  FontScale build() => _initial;

  Future<void> set(FontScale scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefFontScale, scale.name);
  }
}

/// 預設給 medium，main() 會用 override 改成實際載入值。
final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, FontScale>(
        () => FontScaleNotifier(FontScale.medium));
