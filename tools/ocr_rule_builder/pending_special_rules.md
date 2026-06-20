# 特殊規則狀態

無法用簡單「刪字串/換字串」表達的規則記錄於此。工具新寫入的規則會 append 到「待處理」區。

## ✅ 已實作進 label_text_parser.dart（2026-06-20）

以下規則已寫入程式碼，並由 `test/label_text_parser_test.dart` 覆蓋：

- **COSMI（可舒您）**：OCR 的 `_` 還原為 `-`（文字層級，`_applyBrandSpecialRules`）
- **CAROYAL**：系列詞 + 裸數字 → 型號代碼（token 層級查表 `_caroyalTokenMap`）
  - `SUPREME 70→S7`、`SUPREME 45→S5`、`PURITY 75→P75`、`PURITY 45→P45`、
    `R.SUPREME 70→RS7`、`R.SUPREME 40→RS4`、`ROYAL 75→R75`、`ROYAL 45→R45`、
    `GLORY 70→G70`、`GLORY 55→G55`、`GLORY 45→G45`、`CAT 70→CAT70`
- **KORAAN**：移除型號尾端獨立的可見光數字（如 `KN-N70 70` → `KN-N70`）

同期亦修正 `550→S50` 全域取代誤傷 FSK `BW550` 的問題（改為 token 起始邊界取代）。

## 待處理

（目前無）
