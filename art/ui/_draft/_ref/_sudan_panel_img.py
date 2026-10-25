# -*- coding: utf-8 -*-
# 抓攻略页里的图片地址，找「人物面板+装备栏」实图
import re, os, ssl, urllib.request

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

PAGES = [
    "https://www.wywyx.com/gonglue/500735.html",
    "https://3g.ali213.net/gl/html/1641159.html",
    "https://gamemad.com/guide/364003",
]
HDR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}

for u in PAGES:
    print("=" * 70)
    print(u)
    try:
        req = urllib.request.Request(u, headers=HDR)
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            html = r.read().decode("utf-8", "ignore")
    except Exception as e:
        print("  ERR", e)
        continue
    srcs = re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', html, re.I)
    for s in srcs:
        if any(k in s.lower() for k in (".jpg", ".jpeg", ".png", ".webp")):
            print("  ", s)
