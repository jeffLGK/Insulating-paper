// lib/core/network/twca_http_overrides.dart
//
// 全域 HttpOverrides：把打包在 App 內的 TWCA 中繼 + 根憑證附加到預設
// SecurityContext，補上 b2c.vscc.org.tw 伺服器漏送的中繼憑證
// （TWCA SSL Certification Authority），修正 API 查詢與認證標識圖片
// 下載/顯示時出現的：
//   CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate
// 瀏覽器會自動透過 AIA 補抓中繼憑證，但 Dart/Flutter 的 HttpClient 不會。
//
// 採 withTrustedRoots: true（保留內建根憑證）再「附加」TWCA 憑證，因此是
// 正常信任的超集，不影響其他 HTTPS 連線（例如 ML Kit 模型下載）。
//
// 注意：Workmanager 背景同步在獨立 isolate 執行，HttpOverrides.global
// 不會跨 isolate，因此 callbackDispatcher 也需自行呼叫一次。
//
// 維護：打包的中繼憑證有效至 2033-02-23，屆時若 VSCC 換證需更新
// assets/certs/twca_chain.pem。

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class TwcaHttpOverrides extends HttpOverrides {
  TwcaHttpOverrides(this._context);

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _context);
}

/// 載入打包的 TWCA 憑證鏈並設為全域 HttpOverrides。
/// 可重複呼叫；需在 WidgetsFlutterBinding 初始化後執行（rootBundle 需要）。
Future<void> installTwcaHttpOverrides() async {
  try {
    final pem = await rootBundle.load('assets/certs/twca_chain.pem');
    final context = SecurityContext(withTrustedRoots: true);
    try {
      context.setTrustedCertificatesBytes(pem.buffer.asUint8List());
    } on TlsException {
      // 憑證可能已存在於內建信任庫，忽略重複加入
    }
    HttpOverrides.global = TwcaHttpOverrides(context);
  } catch (_) {
    // 載入憑證失敗時不阻斷 App 啟動（最差退回原行為）
  }
}
