"""規則建議：比對 OCR 解析結果與 VSCC 已知 brand/model，提出建議。

產出兩類建議：
  1. 忽略字串(ignore)：OCR 出現、但不屬於 brand/model 的雜訊 token。
  2. OCR 誤讀對應(replacement)：與正確 brand/model 高度相似但不相等的誤讀字。
"""
from difflib import SequenceMatcher

from .parser import normalize


def _matches(token: str, norm_brand: str, norm_model: str) -> bool:
    """比照 Dart scoreProduct 的命中判定(含 O↔0 容錯)。"""
    nt = normalize(token)
    if not nt:
        return True
    for hay in (norm_brand, norm_model):
        if hay and (nt in hay or hay in nt):
            return True
    fz = nt.replace("0", "O")
    for hay in (norm_brand, norm_model):
        h = hay.replace("0", "O")
        if h and (fz in h or h in fz):
            return True
    return False


def suggest(tokens: list[str], brand: str, model: str) -> dict:
    nb, nm = normalize(brand), normalize(model)
    ignores, replacements = [], []

    for tok in tokens:
        if _matches(tok, nb, nm):
            continue
        # 與 brand/model 高度相似 → 視為 OCR 誤讀，建議對應修正
        best_ratio, best_target = 0.0, None
        for target in (nb, nm):
            if not target:
                continue
            ratio = SequenceMatcher(None, normalize(tok), target).ratio()
            if ratio > best_ratio:
                best_ratio, best_target = ratio, target
        if best_ratio >= 0.6 and best_target:
            replacements.append({"from": normalize(tok), "to": best_target})
        else:
            ignores.append(tok)

    return {
        "ignore_candidates": ignores,
        "replacement_candidates": replacements,
        "note": _build_note(ignores, replacements, brand, model),
    }


def _build_note(ignores, replacements, brand, model) -> str:
    parts = []
    if replacements:
        parts.append(
            "疑似 OCR 誤讀：" + "、".join(f"{r['from']}→{r['to']}" for r in replacements)
        )
    if ignores:
        parts.append("疑似雜訊(可加忽略字串):" + "、".join(ignores))
    if not parts:
        parts.append(f"OCR 結果與 {brand} {model} 大致相符，無需新增規則。")
    return "；".join(parts)
