# -*- coding: utf-8 -*-
import json, ssl, urllib.request, re
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

def raw(u, extra=None):
    h = {"User-Agent": UA, "Accept-Language": "zh-CN,zh;q=0.9"}
    if extra: h.update(extra)
    with urllib.request.urlopen(urllib.request.Request(u, headers=h), timeout=45, context=CTX) as r:
        return r.read().decode("utf-8", "ignore")

for appid in (3052450, 769560, 3117820):
    u = "https://store.steampowered.com/api/appdetails?appids=%s&l=schinese&cc=CN" % appid
    t = raw(u)
    print("### appdetails", appid, "len", len(t))
    print(t[:300].replace("\n", " "))
    print()
    u2 = "https://store.steampowered.com/app/%s/?l=schinese&cc=CN" % appid
    h = raw(u2)
    print("### storepage", appid, "len", len(h))
    ss = set(re.findall(r'https://[^"\']*steamstatic\.com/steam/apps/%s/[^"\']*' % appid, h))
    print("  ss-links:", len(ss))
    for x in sorted(ss)[:6]:
        print("   ", x)
    print("  has_g_rgScreenshots:", "g_rgScreenshots" in h, "| has 'screenshots':", "screenshots" in h)
    print()
