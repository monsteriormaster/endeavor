# -*- coding: utf-8 -*-
"""抓真实参考原图：从页面 HTML 里提取图片直链，可选下载。
用法:
  python _fetch_imgs.py list  <url> [regex]
  python _fetch_imgs.py save  <url> <outdir> <name_prefix> [regex] [maxn]
"""
import sys, os, re, io, json, ssl, urllib.request, urllib.parse

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def get(url, referer=None):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,image/*,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    })
    if referer:
        req.add_header("Referer", referer)
    with urllib.request.urlopen(req, timeout=45, context=CTX) as r:
        return r.read()


def img_urls(html, page_url):
    txt = html.decode("utf-8", "ignore") if isinstance(html, bytes) else html
    found = []
    # plain attributes
    for m in re.finditer(r'(?:src|data-src|data-original|href)\s*=\s*["\']([^"\']+\.(?:png|jpe?g|webp)[^"\']*)["\']', txt, re.I):
        found.append(m.group(1))
    # css url(...)
    for m in re.finditer(r'url\((["\']?)([^)"\']+\.(?:png|jpe?g|webp))\1\)', txt, re.I):
        found.append(m.group(2))
    # steam cdn anywhere
    for m in re.finditer(r'(https?://[^"\'\\ ]*steamstatic\.com/[^"\'\\ ]+\.(?:jpg|png))', txt, re.I):
        found.append(m.group(1))
    out, seen = [], set()
    for u in found:
        u = u.replace("\\/", "/").strip()
        if u.startswith("//"):
            u = "https:" + u
        elif u.startswith("/"):
            u = urllib.parse.urljoin(page_url, u)
        if not u.startswith("http"):
            continue
        if u in seen:
            continue
        seen.add(u)
        out.append(u)
    return out


def main():
    mode = sys.argv[1]
    url = sys.argv[2]
    html = get(url)
    urls = img_urls(html, url)
    if mode == "list":
        rx = re.compile(sys.argv[3], re.I) if len(sys.argv) > 3 else None
        for u in urls:
            if rx and not rx.search(u):
                continue
            print(u)
        print("TOTAL", len(urls))
        return
    outdir, prefix = sys.argv[3], sys.argv[4]
    rx = re.compile(sys.argv[5], re.I) if len(sys.argv) > 5 else None
    maxn = int(sys.argv[6]) if len(sys.argv) > 6 else 40
    os.makedirs(outdir, exist_ok=True)
    n = 0
    for u in urls:
        if rx and not rx.search(u):
            continue
        for ext in (".png", ".jpg", ".jpeg", ".webp"):
            pass
        ext = os.path.splitext(urllib.parse.urlparse(u).path)[1].lower() or ".jpg"
        dst = os.path.join(outdir, "%s_%02d%s" % (prefix, n, ext))
        try:
            data = get(u, referer=url)
            if len(data) < 4096:
                print("skip small", u); continue
            open(dst, "wb").write(data)
            print("OK %8d  %s  <- %s" % (len(data), os.path.basename(dst), u))
            n += 1
        except Exception as e:
            print("ERR", u, e)
        if n >= maxn:
            break
    print("SAVED", n, "->", outdir)


main()
