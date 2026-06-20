"""VSCC API 用戶端：依廠牌抓產品 + 取「申請者自行烙印」標貼圖。"""
import hashlib
import urllib3
import requests

from .config import CACHE_DIR

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

_API = "https://b2c.vscc.org.tw/HeatInsulationFilmProductApi/GetProductList"
_HEADERS = {
    "Content-Type": "application/x-www-form-urlencoded",
    "Referer": "https://www.car-safety.org.tw/car_safety/TemplateTwoContent?OpID=536",
    "Origin": "https://www.car-safety.org.tw",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
}
_PAGE_SIZE = 20


def _fetch_page(brand: str, page_index: int) -> dict:
    body = {
        "manufacturer": "", "brand": brand, "productModel": "",
        "lightTransmittance": "", "labelMethod": "", "certSerial": "",
        "imageBase64": "", "cropX1": "0", "cropY1": "0", "cropX2": "0", "cropY2": "0",
        "pageIndex": str(page_index), "pageSize": str(_PAGE_SIZE),
    }
    resp = requests.post(_API, headers=_HEADERS, data=body, timeout=30, verify=False)
    resp.raise_for_status()
    return resp.json()


def _applicant_urls(cert_image_url: str) -> list[str]:
    """從逗號分隔的 CertImageUrl 取出『申請者自行烙印』圖（排除合格標識範例圖）。"""
    if not cert_image_url:
        return []
    urls = [u.strip() for u in cert_image_url.split(",") if u.strip()]
    return [u for u in urls if "範例" not in u and "合格標識" not in u]


def fetch_brand_products(brand: str) -> list[dict]:
    """回傳該廠牌所有有『自行烙印圖』的產品清單。"""
    products = []
    seen = set()
    first = _fetch_page(brand, 1)
    if not first.get("success"):
        raise RuntimeError(f"VSCC API 回傳失敗：{first.get('message')}")
    total_pages = int(first.get("totalPages") or 1)

    def collect(data):
        for item in data or []:
            b = (item.get("Brand") or "").strip()
            m = (item.get("ProductModel") or "").strip()
            key = f"{b}|{m}|{item.get('CertSerial')}"
            if key in seen:
                continue
            seen.add(key)
            applicant = _applicant_urls(item.get("CertImageUrl") or "")
            if not applicant:
                continue
            products.append({
                "brand": b,
                "model": m,
                "cert_serial": (item.get("CertSerial") or "").strip(),
                "label_method": (item.get("LabelMethod") or "").strip(),
                "light": (item.get("LightTransmittance") or "").strip(),
                "image_urls": applicant,
            })

    collect(first.get("data"))
    for p in range(2, total_pages + 1):
        collect(_fetch_page(brand, p).get("data"))
    return products


def download_image(url: str) -> tuple[bytes, str]:
    """下載圖片，回傳 (bytes, 本機快取路徑)。已快取則直接讀檔。"""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    ext = ".png" if url.lower().endswith(".png") else ".jpg"
    name = hashlib.md5(url.encode("utf-8")).hexdigest() + ext
    path = CACHE_DIR / name
    if path.exists():
        return path.read_bytes(), str(path)
    resp = requests.get(url, headers=_HEADERS, timeout=30, verify=False)
    resp.raise_for_status()
    path.write_bytes(resp.content)
    return resp.content, str(path)
