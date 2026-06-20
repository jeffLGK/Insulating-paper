"""OCR 引擎：Google Cloud Vision(REST + API 金鑰) 與 離線 mock。

註：App 實際用的是 Google ML Kit(行動裝置專用，無法在 Windows 跑)。
本工具改用同屬 Google 文字辨識血統的 Cloud Vision，為最接近的替代方案。
辨識後比照 App 的後處理：英文 + 僅中文字元合併。
"""
import base64
import re
import requests

_CJK = re.compile(r"[一-鿿㐀-䶿]")
_GCV_URL = "https://vision.googleapis.com/v1/images:annotate?key={key}"


def _merge_like_app(full_text: str) -> str:
    """比照 App ocr_service：保留英數行 + 僅中文字元，降低重複雜訊。"""
    return full_text.strip()


class GoogleVisionOCR:
    def __init__(self, api_key: str):
        self.api_key = api_key

    def extract(self, image_bytes: bytes) -> str:
        payload = {
            "requests": [{
                "image": {"content": base64.b64encode(image_bytes).decode("ascii")},
                "features": [{"type": "TEXT_DETECTION"}],
                "imageContext": {"languageHints": ["en", "zh-Hant"]},
            }]
        }
        resp = requests.post(_GCV_URL.format(key=self.api_key), json=payload, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        r = (data.get("responses") or [{}])[0]
        if "error" in r:
            raise RuntimeError(f"GCV 錯誤：{r['error'].get('message')}")
        fta = r.get("fullTextAnnotation")
        if fta and fta.get("text"):
            return _merge_like_app(fta["text"])
        anns = r.get("textAnnotations")
        if anns:
            return _merge_like_app(anns[0].get("description", ""))
        return ""


class MockOCR:
    """離線假引擎：僅供測試管線流通，不可用於建立真實規則。"""

    def __init__(self, sample: str = "DUPONT\nZ70 40% MIN"):
        self.sample = sample

    def extract(self, image_bytes: bytes) -> str:
        return self.sample


def build_engine(cfg):
    if cfg.ocr_engine == "mock":
        return MockOCR()
    if not cfg.has_gcv_key:
        raise RuntimeError(
            "未設定 Google Cloud Vision API 金鑰。請在 config.json 填 google_vision_api_key，"
            "或設環境變數 GOOGLE_VISION_API_KEY；或改用 mock 引擎做離線測試。"
        )
    return GoogleVisionOCR(cfg.google_vision_api_key)
