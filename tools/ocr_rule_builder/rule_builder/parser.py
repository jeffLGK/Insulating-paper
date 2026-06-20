"""label_text_parser.dart 的 Python 對應實作。

直接從 Dart 原始碼讀出當前的 _triggers 與 _ocrReplacements，
確保本工具顯示的「目前規則解析結果」與 App 行為一致。
"""
import re
from pathlib import Path

_TOKEN_KEEP = re.compile(r"[^A-Z0-9\-一-鿿㐀-䶿]")
_TRIM_HYPHEN = re.compile(r"^-+|-+$")
_PURE_NUM = re.compile(r"^\d+\.?\d*$")
_SPLIT = re.compile(r"[\s/]+")
_STR_LIT = re.compile(r"'((?:[^'\\]|\\.)*)'")


def load_rules_from_dart(dart_path: Path) -> tuple[list[str], dict]:
    """解析 Dart 檔，取出 _triggers 清單與 _ocrReplacements map。"""
    src = dart_path.read_text(encoding="utf-8")
    triggers = []
    repl = {}

    m = re.search(r"_triggers\s*=\s*\[(.*?)\];", src, re.S)
    if m:
        triggers = _STR_LIT.findall(m.group(1))

    m = re.search(r"_ocrReplacements\s*=\s*<String,\s*String>\{(.*?)\};", src, re.S)
    if m:
        for pair in re.finditer(r"'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'", m.group(1)):
            repl[pair.group(1)] = pair.group(2)
    return triggers, repl


class LabelParser:
    def __init__(self, triggers: list[str], replacements: dict):
        self.triggers = triggers
        self.replacements = replacements

    def parse(self, raw_text: str) -> list[str]:
        if not raw_text or not raw_text.strip():
            return []
        raw_upper = raw_text.upper()
        text = raw_upper

        # COSMI（可舒您）：底線還原為連字號（文字層級）
        if "COSMI" in text or "可舒您" in text:
            text = text.replace("_", "-")

        # OCR 誤讀對應：以 token 起始邊界套用（避免 550→S50 誤傷 BW550）
        for frm, to in self.replacements.items():
            text = re.sub(r"(?<![A-Z0-9])" + re.escape(frm.upper()), to.upper(), text)

        words = [w for w in _SPLIT.split(text) if w]
        kept = []
        for word in words:
            discard = any(t in word for t in self.triggers)
            if not discard and word == "UP":
                discard = True
            if not discard:
                kept.append(word)

        tokens, seen_nums = [], set()
        for word in kept:
            clean = _TRIM_HYPHEN.sub("", _TOKEN_KEEP.sub("", word))
            if len(clean) < 2:
                continue
            if _PURE_NUM.match(clean):
                if clean in seen_nums:
                    continue
                seen_nums.add(clean)
            if clean not in tokens:
                tokens.append(clean)

        return _apply_brand_token_rules(tokens, raw_upper)


# CAROYAL 系列裸數字補字母前綴（token 層級查表，對應 Dart _caroyalTokenMap）
_CAROYAL_TOKEN_MAP = {
    "RSUPREME_70": "RS7", "RSUPREME_40": "RS4",
    "SUPREME_70": "SUPREME S7", "SUPREME_45": "SUPREME S5",
    "PURITY_75": "PURITY P75", "PURITY_45": "PURITY P45",
    "ROYAL_75": "ROYAL R75", "ROYAL_45": "ROYAL R45",
    "GLORY_70": "GLORY G70", "GLORY_55": "GLORY G55", "GLORY_45": "GLORY G45",
    "CAT_70": "CAT70",
}


def _apply_brand_token_rules(tokens: list[str], raw_upper: str) -> list[str]:
    """對應 Dart _applyBrandTokenRules：CAROYAL 補前綴、KORAAN 去尾數。"""
    if "CAROYAL" in raw_upper:
        out, i = [], 0
        while i < len(tokens):
            if i + 1 < len(tokens):
                mapped = _CAROYAL_TOKEN_MAP.get(f"{tokens[i]}_{tokens[i + 1]}")
                if mapped:
                    out.extend(mapped.split(" "))
                    i += 2
                    continue
            out.append(tokens[i])
            i += 1
        tokens = out
    if "KORAAN" in raw_upper:
        while tokens and _PURE_NUM.match(tokens[-1]):
            tokens.pop()
    return tokens


def normalize(s: str) -> str:
    """對應 Dart _normalize：去除非英數與非中文字符。"""
    return re.sub(r"[^A-Z0-9一-鿿㐀-䶿]", "", s.upper())
