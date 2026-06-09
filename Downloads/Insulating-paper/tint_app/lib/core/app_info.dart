// App 版本資訊
//
// 直接從打包產物 (PackageInfo) 讀取，與 pubspec.yaml 的 version 永遠同步，
// 不再需要每次發版手動更新常數。

import 'package:package_info_plus/package_info_plus.dart';

/// 回傳顯示用版本字串，例如 "v1.0.5+6"。
Future<String> getAppVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}+${info.buildNumber}';
}
