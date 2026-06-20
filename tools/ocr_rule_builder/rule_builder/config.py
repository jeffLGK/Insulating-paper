"""組態載入與路徑推算。"""
import json
import os
from pathlib import Path

# tools/ocr_rule_builder/rule_builder/config.py → 專案根目錄為上溯三層
PROJECT_ROOT = Path(__file__).resolve().parents[3]
TOOL_DIR = Path(__file__).resolve().parents[1]

DEFAULT_XLSX = PROJECT_ROOT / "隔熱紙測試圖" / "重要-隔熱紙OCR辨識規則.xlsx"
DEFAULT_DART = (
    PROJECT_ROOT
    / "Downloads" / "Insulating-paper" / "tint_app"
    / "lib" / "core" / "ocr" / "label_text_parser.dart"
)
CACHE_DIR = TOOL_DIR / "cache"
PENDING_SPECIAL = TOOL_DIR / "pending_special_rules.md"


class Config:
    def __init__(self, data: dict):
        self.google_vision_api_key = (
            os.environ.get("GOOGLE_VISION_API_KEY")
            or data.get("google_vision_api_key", "")
        ).strip()
        self.ocr_engine = (data.get("ocr_engine") or "gcv").strip().lower()
        self.xlsx_path = Path(data.get("xlsx_path") or DEFAULT_XLSX)
        self.dart_parser_path = Path(data.get("dart_parser_path") or DEFAULT_DART)

    @property
    def has_gcv_key(self) -> bool:
        return bool(self.google_vision_api_key) and "貼上" not in self.google_vision_api_key


def load_config() -> Config:
    cfg_file = TOOL_DIR / "config.json"
    data = {}
    if cfg_file.exists():
        data = json.loads(cfg_file.read_text(encoding="utf-8"))
    return Config(data)
