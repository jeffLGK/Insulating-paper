# iOS 版建置指南（Mac mini 到手後照這份做）

> Windows 端的前置作業已完成並進版控：`ios/` 專案、Podfile（含中文 OCR 模型）、
> Info.plist 權限文字、AppDelegate 背景任務註冊、iOS App 圖示。
> Mac 端只需安裝工具鏈 → `pod install` → 簽章 → 跑實機。

---

## 0. 買 Mac mini 時的規格建議

| 項目 | 建議 | 原因 |
|---|---|---|
| 機型 | Mac mini（Apple Silicon，現售款即可） | 僅用於編譯／上架，不需要 Pro 機種 |
| 記憶體 | **16GB 以上** | Xcode + Flutter + 模擬器同時開會吃滿 8GB |
| 硬碟 | **512GB**（最低 256GB + 外接 SSD） | Xcode 約 20GB、iOS 平台元件約 10GB、CocoaPods 快取與建置產物約 15GB |
| 其他 | 沿用現有螢幕／鍵鼠即可；需一條 USB-C 線接 iPhone | mini 不含螢幕鍵鼠 |

公務機關採購可先查**共同供應契約**是否有 Apple 品項，通常比官網零售價低；
教育價不適用於機關採購。

---

## 1. Mac 到手後的環境安裝（約半天，多數時間在等下載）

```bash
# (1) 先把 macOS 更新到最新版（Xcode 會要求新系統）
# (2) 從 App Store 安裝 Xcode（約 15-20GB，網路慢會下載 1-2 小時）

# (3) Xcode 首次設定：同意授權、安裝命令列工具與 iOS 平台元件
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

# (4) 安裝 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# (5) 安裝 CocoaPods（用 Homebrew，避免系統 Ruby 權限問題）
brew install cocoapods

# (6) 安裝 Flutter 3.44.9（勿用 brew 裝，會自動裝成最新版）
git clone https://github.com/flutter/flutter.git -b 3.44.9 --depth 1 ~/development/flutter
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# (7) 驗證
flutter doctor -v
flutter --version   # 應顯示 3.44.9
```

`flutter doctor` 的 Android 項目顯示紅字可以忽略（Mac 上不需要編 Android 版）。

### 為什麼要鎖 3.44.9

**本專案三台機器（筆電、桌機、Mac）統一使用 Flutter 3.44.9 stable。**
Play 商店上的 1.0.9+10 就是 3.44 這條線建出來的，iOS 首版沿用同一版最安全。
要升版時三台一起升，並重跑一次測試與實機驗證。

若各機器自己裝「當下最新版」，`pubspec.lock` 會被不同版本反覆改寫
（下面說明原因），iOS 與 Android 的產出也可能不一致。
長期要管多台機器的話，改用 [FVM](https://fvm.app/) 比手動 clone 好維護。

### 用 pubspec.lock 反推某台機器的 Flutter 版本

`meta` 與 `test_api` 這兩個套件是被 Flutter SDK **寫死成固定版本**的
（見 SDK 內的 `packages/flutter/pubspec.yaml` 與 `packages/flutter_test/pubspec.yaml`），
所以 `pubspec.lock` 裡的值可以直接反推出產生它的 Flutter 版本：

| Flutter | `meta` | `test_api` |
|---|---|---|
| 3.41.0 ~ 3.41.9 | `1.17.0` | 0.7.8 ~ 0.7.10 |
| **3.44.0 ~ 3.44.9（本專案）** | **`1.18.0`** | **`0.7.11`** |
| 3.47.0 ~ 3.47.9 | `^1.18.3` | `0.7.12` |
| 3.50.0 | `^1.19.0` | `0.7.14` |

**症狀：** 某台機器 `flutter pub get` 後，`pubspec.lock` 的 `meta` / `test_api`
莫名被改動（且 `git checkout` 丟棄後又再出現）。
**原因：** 那台機器的 Flutter 版本和別台不同，SDK 的固定 pin 會強制覆寫。
**處理：** 把該機器切到 3.44.9，而不是去改 lock：

```bash
cd <FLUTTER_ROOT> && git checkout -B stable 3.44.9 && flutter --version
```

---

## 2. 取得專案並建置

> **動手前先確認 Windows 端沒有未提交的變更**，在 Windows 跑 `git status`，
> 有東西就先 commit + push。否則 Mac 上 clone 到的是舊狀態，
> 兩邊的 `pubspec.lock` 很容易再分叉。

`.git` 約 377MB（歷史含簡報與圖片），用 partial clone 可以省掉大量舊 blob 下載：

```bash
git clone --filter=blob:none https://github.com/jeffLGK/Insulating-paper.git
cd Insulating-paper/Downloads/Insulating-paper/tint_app
```

專案在 repo 內的路徑就是 `Downloads/Insulating-paper/tint_app`，
**不要在 Mac 上自行搬動目錄位置**，否則兩邊路徑分叉。
也不要用 USB 或雲端硬碟複製整個資料夾過去——裡面的 `build/`、`.dart_tool/`、
`.flutter-plugins-dependencies`（內含 Windows 絕對路徑）都是本機狀態，搬過去只會製造問題。

```bash
flutter pub get
```

```bash
cd ios && pod install && cd ..
```

`pod install` 第一次會下載 GoogleMLKit（含中文辨識模型，約 300-400MB），請耐心等。
**完成後務必確認輸出中有 `GoogleMLKit/TextRecognitionChinese`**，沒有的話中文標貼會辨識不到。

---

## 3. 簽章設定（Xcode）

```bash
open ios/Runner.xcworkspace
```

**重要：一定要開 `.xcworkspace`，不是 `.xcodeproj`**（後者不含 CocoaPods 相依）。

在 Xcode 左側點 `Runner` → `Signing & Capabilities`，上方分頁切到 `Debug`：

1. 勾選 **Automatically manage signing**
2. `Team` 選你的 Apple 帳戶／機關團隊
3. `Bundle Identifier` 此處會顯示 `com.jefflgk.tintapp.dev`（Debug 專用，原因見下）
4. 確認 `Background Modes` 中的 **Background fetch** 已勾選（Info.plist 已設定，Xcode 會自動帶出）

`Release` 分頁同樣把 Team 設好即可，Bundle ID 保持 `com.jefflgk.tintapp` 不要改。

### Bundle ID 分兩組的原因（專案已設定完成，無需手動改）

| 組態 | Bundle ID | 用途 |
|---|---|---|
| Debug / Profile | `com.jefflgk.tintapp.dev` | 免費 Apple 帳戶實機測試（`flutter run` 預設走這組） |
| Release | `com.jefflgk.tintapp` | 正式上架，與 Android 版一致 |

免費簽章時 Xcode 會把 Bundle ID 註冊到個人 Team 名下，而 App ID 在 Apple 是全球唯一。
若測試階段就用掉 `com.jefflgk.tintapp`，日後機關付費帳號要註冊同一個識別碼可能會被擋，
而免費帳戶沒有開發者後台可以自行釋放。分成兩組即可完全避開這個風險。

設定位置：`ios/Runner.xcodeproj/project.pbxproj` 的 `PRODUCT_BUNDLE_IDENTIFIER`，
或在 Xcode → `Runner` → `Build Settings` → 搜尋 `Product Bundle Identifier`
→ 點開左側三角形即可分組態檢視。

### 還沒有付費開發者帳號也能先測

免費帳號就是一般的 Apple 帳戶（Apple 2024 年底起將「Apple ID」正名為「Apple 帳戶」），
不需另外申請開發者方案。把它登入 Xcode（`Xcode` → `Settings…` → `Accounts` → 左下角 `+`
→ `Apple ID`），Xcode 會自動產生一個 **Personal Team**，即可簽章安裝到自己的 iPhone。

憑證有效期 7 天，到期後 App 會開不起來，重跑一次 `flutter run` 即可。
**實機測試不必等開發者帳號核准**——相機、中文 OCR、本地通知、背景同步全都能測
（這些都不是需要付費帳號的 entitlement）。免費帳號唯一做不到的是 TestFlight 與上架。

---

## 4. 實機測試（模擬器不能測相機！）

iPhone 用線接上 Mac → iPhone 上「設定 → 隱私權與安全性 → 開發者模式」開啟 → 重開機。

```bash
flutter devices
```

```bash
flutter run -d <你的 iPhone 名稱>
```

### 必測清單（這幾項是 iOS 最容易出問題的地方）

- [ ] **相機拍標貼 → OCR 辨識出中文**（廠牌、型號、品名）— 驗證 Chinese pod 生效
- [ ] 從相簿選照片 → 裁切 → 辨識（image_picker + image_cropper）
- [ ] 權限彈窗的中文說明文字正確顯示
- [ ] 線上查詢與認證標識圖片能正常載入 — 驗證 TWCA 憑證鏈在 iOS 生效
- [ ] **關鍵字搜尋能正常回傳結果** — 驗證 iOS 的 libsqlite3 支援 `fts4`
      （`app_database.dart` 的全文虛擬表用 fts4；Windows 桌機測試環境的
      預編譯 sqlite3.dll 缺這個模組，導致 DB 相關測試在桌機全數失敗，
      Android 實機則正常。iOS 實機務必實際搜尋一次確認）
- [ ] 首次啟動自動同步（`_autoSyncIfNeeded`）正常完成
- [ ] 同步完成的本地通知能顯示
- [ ] 字體大小調整、深色模式、橫豎向切換
- [ ] 小螢幕（iPhone SE/13 mini）版面不破

---

## 5. 上架 App Store

```bash
flutter build ipa
```

產出的 `build/ios/ipa/*.ipa` 用 Xcode 的 **Organizer** 或 **Transporter** App 上傳。

### App Store Connect 要準備的資料

| 項目 | 內容／注意事項 |
|---|---|
| 開發者帳號 | Apple Developer Program US$99/年。機關名義需 **D-U-N-S 號碼**，審核 2-6 週，建議先問公路局資訊室是否已有機關帳號可掛 |
| App 名稱 | 認證隔熱紙查詢（與 Android 版一致） |
| Bundle ID | `com.jefflgk.tintapp`（Release 組態；Debug 用 `.dev` 另一組，見第 3 節） |
| 隱私權政策網址 | 沿用現有的 `docs/privacy.html` 線上位址 |
| 隱私權標示 | App 不收集任何個人資料 → 選「不收集資料」；相機與相片僅在裝置端處理 |
| 出口合規 | Info.plist 已設 `ITSAppUsesNonExemptEncryption = false`，不會再問 |
| 截圖 | 必備 **6.9 吋 iPhone**（1290×2796 或 1320×2868）；若支援 iPad 還要 13 吋 |
| 審查時間 | 通常 1-3 天；首次送審可能較久 |

**小技巧：** 若不想另外準備 iPad 截圖，可在 Xcode 的 `Runner` → `General` →
`Supported Destinations` 移除 iPad（或設 `TARGETED_DEVICE_FAMILY = 1`），
改為僅支援 iPhone。

建議正式送審前先用 **TestFlight** 發給同事試用一輪。

---

## 6. 疑難排解

| 症狀 | 處理 |
|---|---|
| `pod install` 找不到 GoogleMLKit | `pod repo update` 後重試 |
| CocoaPods 報 static/dynamic framework 衝突 | 把 Podfile 的 `use_frameworks!` 改成 `use_frameworks! :linkage => :static` |
| 建置報 `Sandbox: rsync deny file-write` | Xcode → Build Settings → `ENABLE_USER_SCRIPT_SANDBOXING` 設為 `NO` |
| 中文完全辨識不到、英數字正常 | Chinese pod 沒裝成功，檢查 ios/Podfile 第 54 行並重跑 `pod install` |
| 相機黑畫面 | 確認是實機；模擬器沒有相機硬體 |
| 背景同步沒在跑 | iOS 的 BGTaskScheduler 由系統決定時機，無法保證。App 啟動時的 `_autoSyncIfNeeded()` 是主要更新機制，此為預期行為 |
| ML Kit 相關的最低版本錯誤 | 最低 iOS 已設 15.5（ML Kit 6.x 要求），勿調低 |

---

## 7. 平台差異備忘

| 項目 | Android | iOS |
|---|---|---|
| 最低版本 | Android 5.0（minSdk 21） | **iOS 15.5**（受 ML Kit 限制，iPhone 6s 以後） |
| 中文 OCR 模型 | `android/app/build.gradle.kts` 的 `text-recognition-chinese` | `ios/Podfile` 的 `GoogleMLKit/TextRecognitionChinese` |
| 每週背景同步 | WorkManager，可靠 | BGTaskScheduler，**系統決定時機、不保證執行** |
| 權限說明 | AndroidManifest | `ios/Runner/Info.plist` 的 `NS*UsageDescription` |
| App 大小 | 約 60MB | 預估 80-120MB（ML Kit 中文模型較大） |

> Dart 程式碼（`lib/`）完全共用，後續功能開發仍可在 Windows 進行；
> 只有「編 iOS 版」與「上架」這兩件事需要 Mac。

---

## 8. 多機維護注意事項

- **Android 上架金鑰只存在 Windows 開發機，且不在版控內**
  （`key.properties` 與 keystore 都被 `.gitignore` 排除）。
  務必確認有離線備份——遺失後就無法再更新 Play 商店上的 `com.jefflgk.tintapp`。
  Android 版請固定在 Windows 出，不要試著搬到 Mac。
- **iOS 的簽章憑證反過來只在 Mac 的鑰匙圈裡**，由 Xcode 自動管理；
  若日後要上 CI（GitHub Actions macOS runner），憑證與 Provisioning Profile
  的匯出管理較繁瑣，初期建議維持手動建置。
- 三台機器的 Flutter 版本一律 **3.44.9**（見第 1 節，含版本不一致時的反推方式）。
- 根目錄的 `docs/` 是 GitHub Pages 的隱私權政策（對外公開），
  開發文件請勿放進該目錄。
