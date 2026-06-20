"""一鍵驗證 Google Cloud Vision 金鑰是否可用。

用法：填好 config.json 的 google_vision_api_key 後執行
    python verify_gcv.py
會抓一張真實的 VSCC 標貼圖做 OCR，印出辨識文字與解析後 token。
"""
import sys

from rule_builder.config import load_config
from rule_builder.parser import LabelParser, load_rules_from_dart
from rule_builder import vscc, ocr

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def main():
    cfg = load_config()
    print(f"引擎={cfg.ocr_engine}  金鑰已設定={cfg.has_gcv_key}")
    if cfg.ocr_engine == "gcv" and not cfg.has_gcv_key:
        print("✗ 尚未在 config.json 填入有效金鑰（或仍是預設提示字）。")
        return 1

    print("→ 抓一張 DuPont 標貼圖測試...")
    prods = vscc.fetch_brand_products("DuPont")
    if not prods:
        print("✗ 抓不到測試圖。")
        return 1
    url = prods[0]["image_urls"][0]
    data, path = vscc.download_image(url)
    print(f"  圖片：{prods[0]['brand']} {prods[0]['model']}（{len(data)} bytes）")

    engine = ocr.build_engine(cfg)
    try:
        text = engine.extract(data)
    except Exception as e:  # noqa: BLE001
        print(f"✗ OCR 失敗：{e}")
        return 1

    print("\n=== OCR 原始文字 ===")
    print(text or "(空白)")

    triggers, repl = load_rules_from_dart(cfg.dart_parser_path)
    tokens = LabelParser(triggers, repl).parse(text)
    print("\n=== 套用目前規則後的 token ===")
    print(tokens)
    print("\n✓ GCV 金鑰運作正常，可以開始用 python run.py。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
