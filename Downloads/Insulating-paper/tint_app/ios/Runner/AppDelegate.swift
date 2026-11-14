import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Dart 端 kSyncTaskName（lib/features/sync/sync_service.dart）。
  // 三處必須一致：此處、Info.plist 的 BGTaskSchedulerPermittedIdentifiers、Dart 常數。
  private static let syncTaskIdentifier = "tint_weekly_sync"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 背景 isolate 也需要註冊插件（sqflite、http 等），否則背景同步會失敗。
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // iOS 的 BGTaskScheduler 任務必須在 App 啟動時（launch 前）完成註冊。
    // 注意：iOS 不保證執行時間，系統會依使用者習慣與電量決定何時喚醒，
    // 故每週同步在 iOS 屬「盡力而為」；主要更新機制仍是 main.dart 的
    // _autoSyncIfNeeded()（啟動時超過 7 天未同步就前景同步一次）。
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: AppDelegate.syncTaskIdentifier,
      frequency: NSNumber(value: 7 * 24 * 60 * 60)
    )

    // 讓 App 在前景時也能顯示 flutter_local_notifications 發出的同步完成通知。
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
