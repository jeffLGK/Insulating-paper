# 隔熱紙查詢 APP — Phase 1：資料層 + 關鍵字搜尋

## 專案結構

```
lib/
├── main.dart                          # APP 進入點
├── data/
│   ├── models/
│   │   └── tint_product.dart          # 資料模型
│   ├── datasources/
│   │   └── car_safety_scraper.dart    # HTML 爬蟲
│   └── repositories/
│       └── tint_repository.dart       # Repository（UI 的資料窗口）
├── core/
│   └── database/
│       └── app_database.dart          # SQLite + FTS5
└── features/
    ├── sync/
    │   └── sync_service.dart          # 同步排程 + 通知
    └── search/
        ├── search_providers.dart      # Riverpod 狀態管理
        └── search_screen.dart         # 搜尋 UI
```

## 快速開始

### 1. 安裝依賴

```bash
flutter pub get
```

### 2. Android 設定（Workmanager 背景任務）

在 `android/app/src/main/AndroidManifest.xml` 加入：

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.INTERNET"/>

<application ...>
  <!-- Workmanager -->
  <service
    android:name="be.tramckrijte.workmanager.BackgroundWorker"
    android:exported="false"/>
</application>
```

### 3. iOS 設定（背景 Fetch）

在 `ios/Runner/Info.plist` 加入：

```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>processing</string>
</array>
```

在 `ios/Runner/AppDelegate.swift` 加入：

```swift
WorkmanagerPlugin.registerTask(withIdentifier: "tint_weekly_sync")
```

### 4. 執行

```bash
flutter run
```

## 核心功能說明

### 爬蟲（CarSafetyScraper）

- 目標：`https://www.car-safety.org.tw/car_safety/TemplateTwoContent?OpID=536`
- 動態辨識表頭欄位，不依賴固定索引
- 支援 UTF-8 / Big5 編碼自動判斷
- 圖片 URL 自動補全相對路徑

### 資料庫（AppDatabase）

- SQLite WAL 模式，提高並發效能
- FTS5 全文虛擬表，支援中英文前綴搜尋
- 三個觸發器自動同步主表與 FTS5
- UNIQUE 衝突由認證號碼控制，安全 upsert

### 搜尋邏輯

```
輸入「3M FX」
→ FTS5 MATCH '"3M"* "FX"*'
→ 找出所有 brand/model/certNumber/standard 含 3M 且含 FX 的資料
→ 依 FTS5 rank 排序
→ 支援品牌 chip 二次篩選
→ 分頁（每頁 30 筆）+ 無限捲動
```

### 同步策略

| 觸發 | 時機 |
|------|------|
| 首次安裝 | 立即同步 |
| 超過 7 天未更新 | APP 啟動時自動觸發 |
| 手動 | AppBar 同步按鈕 |
| 背景排程 | 每 7 天（Workmanager） |

## 已知限制與後續處理

1. **需要網路**：爬蟲無法離線執行；資料快取後搜尋可離線使用
2. **網頁結構改變**：若 `car-safety.org.tw` 改版，需更新 `_findDataTable` 與 `_parseHeaders`
3. **JS 渲染**：若網頁內容由 JavaScript 動態生成，需改用 `flutter_inappwebview` 或 Puppeteer 後端
4. **圖片快取**：目前圖片由 `cached_network_image` 記憶體快取；Phase 2 可改存本地路徑供影像比對使用
