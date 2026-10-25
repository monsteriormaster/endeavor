# -*- coding: utf-8 -*-
import json, ssl, urllib.request, urllib.parse
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

def srch(term):
    u = "https://store.steampowered.com/api/storesearch/?term=%s&l=schinese&cc=CN" % urllib.parse.quote(term)
    req = urllib.request.Request(u, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
        d = json.loads(r.read().decode("utf-8", "ignore"))
    print("=== %s (total=%s) ===" % (term, d.get("total")))
    for it in d.get("items", [])[:8]:
        print("  id=%-8s %s" % (it.get("id"), it.get("name")))

for t in ["Morimens", "月圆之夜", "苏丹的游戏", "Sultan's Game", "Night of the Full Moon", "忘却前夜"]:
    try:
        srch(t)
    except Exception as e:
        print("ERR", t, e)
