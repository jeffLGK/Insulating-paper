"""OCR 規則建立工具套件。

從 VSCC 抓取指定廠牌的「申請者自行烙印」標貼圖，逐張用 OCR 辨識，
依建議協助建立 忽略字串 / OCR 誤讀對應 規則，寫入 OCR 規則 xlsx，
並可自動同步進 App 的 label_text_parser.dart。
"""
