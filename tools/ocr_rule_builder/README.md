# OCR 規則建立工具（ocr_rule_builder）

協助提升 App 圖像比對精準度：輸入廠牌 → 抓 VSCC「申請者自行烙印」標貼圖 →
逐張 OCR 辨識（顯圖 + 文字）→ 依建議建立「忽略字串 / OCR 誤讀對應」規則 →
寫入 `重要-隔熱紙OCR辨識規則.xlsx` 並**自動同步**進 App 的 `label_text_parser.dart`。

## 為什麼用 Google Cloud Vision，而不是 App 的 OCR？

App 實際用的是 **Google ML Kit**，只能在 Android/iOS 跑，無法在 Windows 程式呼叫。
本工具改用同屬 Google 文字辨識血統、最接近的 **Cloud Vision**。辨識結果與 ML Kit
高度相近但非 100% 相同，建立規則後仍建議在真機上抽驗。

## 安裝

```bash
cd tools/ocr_rule_builder
pip install -r requirements.txt
copy config.example.json config.json   # 然後填入 GCV 金鑰
```

`config.json` 設定：

| 欄位 | 說明 |
|---|---|
| `google_vision_api_key` | Google Cloud Vision API 金鑰（或設環境變數 `GOOGLE_VISION_API_KEY`） |
| `ocr_engine` | `gcv`（正式）或 `mock`（離線測試管線，不可建真實規則） |
| `xlsx_path` / `dart_parser_path` | 留空自動推算，通常不必填 |

取得金鑰：Google Cloud Console → 啟用 **Cloud Vision API** → 建立 API 金鑰。
計費約每 1000 張 US$1.5（前 1000 張/月免費）。

## 使用

```bash
python run.py     # 自動開瀏覽器 http://127.0.0.1:5000
```

1. 輸入廠牌名稱（VSCC 線上的 Brand，例：`V-KOOL`、`Quantum量子膜`）。
2. 逐張檢視：左側圖檔、右側 OCR 原始文字 + 套用目前規則後的 token + 系統建議。
3. 視需要填「忽略字串 / OCR 誤讀對應 / 特殊規則說明」（建議已預填，可改）→ 儲存。
4. 結束後按「同步」：規則寫進 xlsx，並自動加入 Dart 的 `_triggers` / `_ocrReplacements`。

## 規則同步範圍

| 規則類型 | 去處 |
|---|---|
| 忽略字串 | `label_text_parser.dart` 的 `_triggers`（標記區 `RULE_BUILDER_TRIGGERS` 內，冪等去重） |
| OCR 誤讀對應 `FROM→TO` | `_ocrReplacements` map（標記區 `RULE_BUILDER_REPLACEMENTS` 內） |
| 無法結構化的自由規則 | 只寫 xlsx + 列入 `pending_special_rules.md` 待人工改碼 |

同步後請到 `Downloads/Insulating-paper/tint_app` 跑 `flutter test` 驗證。

## 檔案

```
run.py                     Flask 網頁入口
rule_builder/
  config.py                組態與路徑
  vscc.py                  VSCC API + 下載自行烙印圖
  ocr.py                   GCV / mock OCR 引擎
  parser.py                label_text_parser.dart 的 Python 對應（並讀取當前規則）
  suggest.py               規則建議
  store.py                 寫入 xlsx
  dart_sync.py             同步進 Dart + pending 檔
```
