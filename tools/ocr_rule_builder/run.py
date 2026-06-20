"""OCR 規則建立工具 — 本地網頁版入口。

用法：
    pip install -r requirements.txt
    複製 config.example.json → config.json 並填 GCV 金鑰
    python run.py            # 啟動後瀏覽器開 http://127.0.0.1:5000

離線測試管線(不呼叫 GCV)：在 config.json 設 "ocr_engine": "mock"
"""
import io
import sys
import threading
import webbrowser

from flask import (
    Flask, render_template_string, request, redirect, url_for, send_file, abort,
)

from rule_builder.config import load_config
from rule_builder.parser import LabelParser, load_rules_from_dart
from rule_builder.suggest import suggest
from rule_builder import vscc, ocr, store, dart_sync

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

app = Flask(__name__)
CFG = load_config()
ENGINE = None  # 延後到實際辨識時才建立，避免無金鑰時啟動即失敗

STATE = {
    "brand": None, "dir_name": None, "items": [], "index": 0,
    "pending": {"ignores": [], "replacements": [], "specials": []},
}


def get_engine():
    global ENGINE
    if ENGINE is None:
        ENGINE = ocr.build_engine(CFG)
    return ENGINE


def current_parser() -> LabelParser:
    """合併『Dart 現有規則』與『本次 session 暫存(尚未同步)規則』，
    讓同一次 session 內剛加的規則即時生效，避免同廠牌重複建議。"""
    triggers, repl = load_rules_from_dart(CFG.dart_parser_path)
    p = STATE["pending"]
    trig_set = {t.upper() for t in triggers}
    merged_trig = list(triggers)
    for ig in p["ignores"]:
        if ig.upper() not in trig_set:
            trig_set.add(ig.upper())
            merged_trig.append(ig)
    merged_repl = dict(repl)
    for r in p["replacements"]:
        merged_repl.setdefault(r["from"], r["to"])
    return LabelParser(merged_trig, merged_repl)


# ── 模板 ────────────────────────────────────────────────────────────
BASE_CSS = """
<style>
 body{font-family:system-ui,"Microsoft JhengHei",sans-serif;max-width:980px;margin:24px auto;padding:0 16px;color:#1f2933;}
 h1{font-size:20px;} .muted{color:#6b7280;font-size:13px;}
 .card{border:1px solid #e5e7eb;border-radius:10px;padding:16px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.04);}
 .img{max-width:100%;max-height:420px;border:1px solid #e5e7eb;border-radius:8px;background:#fafafa;}
 .row{display:flex;gap:20px;flex-wrap:wrap;} .col{flex:1;min-width:300px;}
 label{display:block;font-weight:600;font-size:13px;margin:10px 0 4px;}
 input[type=text],textarea{width:100%;padding:8px;border:1px solid #d1d5db;border-radius:6px;font-size:14px;box-sizing:border-box;}
 .tag{display:inline-block;background:#eef2ff;color:#3730a3;border-radius:6px;padding:2px 8px;margin:2px;font-size:13px;}
 .ocr{background:#0f172a;color:#e2e8f0;padding:10px;border-radius:8px;white-space:pre-wrap;font-family:Consolas,monospace;font-size:13px;}
 .sg{background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:10px;font-size:14px;}
 button,.btn{font-size:14px;padding:8px 16px;border-radius:7px;border:1px solid #d1d5db;background:#fff;cursor:pointer;text-decoration:none;color:#1f2933;}
 .primary{background:#2563eb;color:#fff;border-color:#2563eb;} .danger{color:#b91c1c;}
 .bar{height:6px;background:#e5e7eb;border-radius:3px;overflow:hidden;} .bar>i{display:block;height:100%;background:#2563eb;}
 .warn{background:#fef2f2;border:1px solid #fecaca;color:#991b1b;padding:10px;border-radius:8px;}
</style>
"""

INDEX_HTML = BASE_CSS + """
<h1>🔍 OCR 規則建立工具</h1>
<p class="muted">輸入廠牌 → 抓 VSCC「申請者自行烙印」標貼圖 → 逐張 OCR → 建立 忽略字串／OCR 誤讀規則。</p>
<div class="card">
 <div class="muted">OCR 引擎：<b>{{engine}}</b>{% if not key_ok and engine=='gcv' %} <span class="danger">(尚未設定 GCV 金鑰)</span>{% endif %}
  ｜ xlsx：{{xlsx}}<br>Dart：{{dart}}</div>
</div>
{% if not key_ok and engine=='gcv' %}
<div class="warn">尚未設定 Google Cloud Vision 金鑰。請複製 <code>config.example.json</code> 為 <code>config.json</code> 填入金鑰，
或設環境變數 <code>GOOGLE_VISION_API_KEY</code>；或在 config.json 設 <code>"ocr_engine":"mock"</code> 做離線測試。</div>
{% endif %}
<form method="post" action="/start" class="card">
 <label>廠牌名稱(VSCC 線上的 Brand)</label>
 <input type="text" name="brand" placeholder="例：V-KOOL、Quantum量子膜、XPEL" required>
 <label>資料夾／目錄名稱(寫進 xlsx 第 1 欄，預設同廠牌)</label>
 <input type="text" name="dir_name" placeholder="留空則用廠牌名">
 <p><button class="primary" type="submit">開始抓圖辨識</button></p>
</form>
"""

REVIEW_HTML = BASE_CSS + """
<h1>{{brand}} — 第 {{idx1}} / {{total}} 張</h1>
<div class="bar"><i style="width:{{pct}}%"></i></div>
<div class="card"><div class="row">
 <div class="col">
   <img class="img" src="/image/{{idx}}" alt="label">
   <div class="muted" style="margin-top:6px">型號(VSCC)：<b>{{item.model}}</b> ｜ 可見光 {{item.light}} ｜ 序號 {{item.cert_serial or '—'}}</div>
 </div>
 <div class="col">
   <label>OCR 原始辨識文字</label>
   <div class="ocr">{{ocr_text or '(空白／無文字)'}}</div>
   <label>套用目前規則後的 token</label>
   <div>{% for t in tokens %}<span class="tag">{{t}}</span>{% else %}<span class="muted">(無)</span>{% endfor %}</div>
   <div class="sg" style="margin-top:10px">💡 建議：{{sg.note}}</div>
 </div>
</div></div>

<form method="post" action="/review" class="card">
 <input type="hidden" name="model_out" value="{{item.model}}">
 <div class="row">
  <div class="col">
   <label>忽略字串(會加進 _triggers，含此字串的 token 整個移除；多個用半形逗號)</label>
   <input type="text" name="ignore" value="{{prefill_ignore}}">
  </div>
  <div class="col">
   <label>OCR 誤讀對應(from → to，正規化大寫；多組用分號，如 DUPONT=DUPONT)</label>
   <input type="text" name="replacement" value="{{prefill_repl}}">
  </div>
 </div>
 <label>特殊規則說明(自由敘述，無法自動改碼者會列入 pending 待人工處理)</label>
 <textarea name="special" rows="2">{{prefill_special}}</textarea>
 <p style="margin-top:12px">
  <button class="primary" name="action" value="save" type="submit">儲存並下一張</button>
  <button name="action" value="skip" type="submit">略過</button>
  <a class="btn" href="/review?back=1">上一張</a>
  <a class="btn" href="/finish">結束並同步規則 →</a>
 </p>
 <p class="muted">本次已暫存待同步：忽略字串 {{pending_ig}} 個、誤讀對應 {{pending_rp}} 組、特殊規則 {{pending_sp}} 筆。</p>
</form>
"""

DONE_HTML = BASE_CSS + """
<h1>✅ {{brand}} 完成</h1>
<div class="card">
 <p>本次共處理 {{total}} 張。準備把暫存規則同步進程式碼與規格檔。</p>
 <p class="muted">忽略字串 {{pending_ig}} 個、OCR 誤讀對應 {{pending_rp}} 組、特殊規則 {{pending_sp}} 筆。</p>
 <form method="post" action="/sync">
  <button class="primary" type="submit">寫入 _triggers / _ocrReplacements + pending</button>
  <a class="btn" href="/">回首頁</a>
 </form>
</div>
{% if result %}
<div class="card">
 <h3>同步結果</h3>
 <p>新增 _triggers：{{result.added_triggers or '無'}}</p>
 <p>新增 _ocrReplacements：{{result.added_replacements or '無'}}</p>
 <p>列入待人工處理(pending_special_rules.md):{{result.pending}} 筆</p>
 <p class="muted">建議接著到 tint_app 跑 <code>flutter test</code> 驗證解析行為。</p>
</div>
{% endif %}
"""


# ── 路由 ────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return render_template_string(
        INDEX_HTML, engine=CFG.ocr_engine, key_ok=CFG.has_gcv_key,
        xlsx=CFG.xlsx_path, dart=CFG.dart_parser_path,
    )


@app.route("/start", methods=["POST"])
def start():
    brand = request.form["brand"].strip()
    dir_name = request.form.get("dir_name", "").strip() or brand
    products = vscc.fetch_brand_products(brand)
    items = []
    for prod in products:
        for u in prod["image_urls"]:
            items.append({
                "url": u, "model": prod["model"], "cert_serial": prod["cert_serial"],
                "light": prod["light"], "local_path": None, "ocr_text": None,
            })
    STATE.update({
        "brand": brand, "dir_name": dir_name, "items": items, "index": 0,
        "pending": {"ignores": [], "replacements": [], "specials": []},
    })
    if not items:
        return render_template_string(
            BASE_CSS + '<div class="warn">此廠牌查無「申請者自行烙印」圖。</div>'
            '<p><a class="btn" href="/">回首頁</a></p>')
    return redirect(url_for("review"))


@app.route("/review", methods=["GET", "POST"])
def review():
    if request.method == "POST":
        action = request.form.get("action")
        if action == "save":
            try:
                _save_current()
            except PermissionError:
                return render_template_string(
                    BASE_CSS + '<div class="warn">無法寫入 xlsx：檔案可能正在 Excel 中開啟，'
                    '請先關閉 Excel 再回上一步重存。</div>'
                    '<p><a class="btn" href="/review">回到這一張</a></p>')
        STATE["index"] += 1
        return redirect(url_for("review"))

    if request.args.get("back"):
        STATE["index"] = max(0, STATE["index"] - 1)
        return redirect(url_for("review"))

    idx = STATE["index"]
    items = STATE["items"]
    if idx >= len(items):
        return redirect(url_for("finish"))

    item = items[idx]
    _ensure_ocr(idx)
    parser = current_parser()
    tokens = parser.parse(item["ocr_text"] or "")
    sg = suggest(tokens, STATE["brand"], item["model"])

    prefill_repl = ";".join(f"{r['from']}={r['to']}" for r in sg["replacement_candidates"])
    prefill_ignore = ",".join(sg["ignore_candidates"])
    p = STATE["pending"]
    return render_template_string(
        REVIEW_HTML, brand=STATE["brand"], idx=idx, idx1=idx + 1, total=len(items),
        pct=int((idx) / len(items) * 100), item=item, ocr_text=item["ocr_text"],
        tokens=tokens, sg=sg, prefill_ignore=prefill_ignore, prefill_repl=prefill_repl,
        prefill_special=sg["note"],
        pending_ig=len(p["ignores"]), pending_rp=len(p["replacements"]), pending_sp=len(p["specials"]),
    )


@app.route("/finish")
def finish():
    p = STATE["pending"]
    return render_template_string(
        DONE_HTML, brand=STATE["brand"], total=len(STATE["items"]), result=None,
        pending_ig=len(p["ignores"]), pending_rp=len(p["replacements"]), pending_sp=len(p["specials"]),
    )


@app.route("/sync", methods=["POST"])
def do_sync():
    p = STATE["pending"]
    result = dart_sync.sync(
        CFG.dart_parser_path, p["ignores"], p["replacements"], p["specials"],
    )
    return render_template_string(
        DONE_HTML, brand=STATE["brand"], total=len(STATE["items"]), result=result,
        pending_ig=len(p["ignores"]), pending_rp=len(p["replacements"]), pending_sp=len(p["specials"]),
    )


@app.route("/image/<int:idx>")
def image(idx):
    items = STATE["items"]
    if idx >= len(items):
        abort(404)
    _ensure_download(idx)
    return send_file(items[idx]["local_path"])


# ── 內部輔助 ────────────────────────────────────────────────────────
def _ensure_download(idx):
    item = STATE["items"][idx]
    if item["local_path"] is None:
        _, path = vscc.download_image(item["url"])
        item["local_path"] = path


def _ensure_ocr(idx):
    item = STATE["items"][idx]
    if item["ocr_text"] is None:
        data, path = vscc.download_image(item["url"])
        item["local_path"] = path
        try:
            item["ocr_text"] = get_engine().extract(data)
        except Exception as e:  # noqa: BLE001
            item["ocr_text"] = f"(OCR 失敗：{e})"


def _save_current():
    item = STATE["items"][STATE["index"]]
    ignore = request.form.get("ignore", "").strip()
    replacement = request.form.get("replacement", "").strip()
    special = request.form.get("special", "").strip()
    model_out = request.form.get("model_out", "").strip()
    p = STATE["pending"]

    ignores = [s.strip().upper() for s in ignore.split(",") if s.strip()]
    for ig in ignores:
        if ig not in p["ignores"]:
            p["ignores"].append(ig)

    repls = []
    for grp in replacement.split(";"):
        if "=" in grp:
            frm, to = grp.split("=", 1)
            frm, to = frm.strip().upper(), to.strip().upper()
            if frm and to:
                repls.append({"from": frm, "to": to})
                if not any(r["from"] == frm for r in p["replacements"]):
                    p["replacements"].append({"from": frm, "to": to})

    # 只有「非建議預填、屬於真正自由敘述」的特殊規則才列入 pending
    if special and not repls and not ignores:
        p["specials"].append({"brand": STATE["brand"], "model": item["model"], "special": special})

    store.append_rule_row(CFG.xlsx_path, {
        "dir_name": STATE["dir_name"], "brand": STATE["brand"],
        "ocr_brand": "", "ocr_model": item["model"], "model_out": model_out,
        "ignore": ignore, "special": special,
    })


def _open_browser():
    webbrowser.open("http://127.0.0.1:5000")


if __name__ == "__main__":
    threading.Timer(1.0, _open_browser).start()
    app.run(host="127.0.0.1", port=5000, debug=False)
