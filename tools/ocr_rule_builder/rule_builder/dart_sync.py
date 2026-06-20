"""把新規則自動同步進 label_text_parser.dart。

- 忽略字串 → _triggers 清單(RULE_BUILDER_TRIGGERS 標記區內)
- OCR 誤讀對應 → _ocrReplacements map(RULE_BUILDER_REPLACEMENTS 標記區內)
- 無法結構化的自由規則 → 寫入 pending_special_rules.md 待人工改碼
"""
import datetime as _dt
import re
from pathlib import Path

from .config import PENDING_SPECIAL
from .parser import load_rules_from_dart

_TRIG_BEGIN = "// >>> RULE_BUILDER_TRIGGERS"
_TRIG_END = "// <<< RULE_BUILDER_TRIGGERS"
_REPL_BEGIN = "// >>> RULE_BUILDER_REPLACEMENTS"
_REPL_END = "// <<< RULE_BUILDER_REPLACEMENTS"


def _insert_between(src: str, begin: str, end: str, new_lines: list[str]) -> str:
    i = src.index(begin) + len(begin)
    j = src.index(end, i)
    # 取得 end 標記行的縮排
    line_start = src.rfind("\n", 0, j) + 1
    indent = src[line_start:j]
    block = "".join(f"\n{indent}{ln}" for ln in new_lines)
    return src[:i] + block + "\n" + src[line_start:]  # 接回 end 行(含縮排)


def sync(dart_path: Path, ignores: list[str], replacements: list[dict],
         specials: list[dict] | None = None) -> dict:
    """回傳 {added_triggers, added_replacements, pending}。冪等：重複的不再加。"""
    existing_trig, existing_repl = load_rules_from_dart(dart_path)
    existing_trig_set = {t.upper() for t in existing_trig}
    src = dart_path.read_text(encoding="utf-8")

    new_trig = []
    for ig in ignores:
        v = ig.strip().upper()
        if v and v not in existing_trig_set:
            existing_trig_set.add(v)
            new_trig.append(v)

    new_repl = []
    for rp in replacements:
        frm, to = rp["from"].strip().upper(), rp["to"].strip().upper()
        if frm and to and frm != to and frm not in existing_repl:
            existing_repl[frm] = to
            new_repl.append((frm, to))

    if new_trig:
        lines = [f"'{v}'," for v in new_trig]
        src = _insert_between(src, _TRIG_BEGIN, _TRIG_END, lines)
    if new_repl:
        lines = [f"'{f}': '{t}'," for f, t in new_repl]
        src = _insert_between(src, _REPL_BEGIN, _REPL_END, lines)

    if new_trig or new_repl:
        dart_path.write_text(src, encoding="utf-8")

    pending = _write_pending(specials or [])
    return {"added_triggers": new_trig, "added_replacements": new_repl, "pending": pending}


def _write_pending(specials: list[dict]) -> int:
    items = [s for s in specials if (s.get("special") or "").strip()]
    if not items:
        return 0
    if not PENDING_SPECIAL.exists():
        PENDING_SPECIAL.write_text(
            "# 待人工改碼的特殊規則\n\n"
            "以下為無法安全自動同步進 Dart 的自由敘述規則，請評估後手動實作於 "
            "`label_text_parser.dart`。\n",
            encoding="utf-8",
        )
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [f"\n## {ts}\n"]
    for s in items:
        lines.append(
            f"- **{s.get('brand','')} {s.get('model','')}**:{s['special'].strip()}"
        )
    with PENDING_SPECIAL.open("a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return len(items)
