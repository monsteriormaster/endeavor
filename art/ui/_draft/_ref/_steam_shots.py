# -*- coding: utf-8 -*-
"""从 Steam appdetails 拉真实游戏截图（官方截图 = 真实卡面/界面）。"""
import json, os, ssl, sys, urllib.request
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

OUT = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"

def appdetails(appid):
    u = "https://store.steampowered.com/api/appdetails?appids=%s&l=schinese&cc=CN" % appid
    req = urllib.request.Request(u, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=45, context=CTX) as r:
        d = json.loads(r.read().decode("utf-8", "ignore"))
    # Steam 有时把返回的键写成另一个 appid（DLC），所以按值取第一个
    node = d.get(str(appid)) or list(d.values())[0]
    if not node.get("success"):
        raise RuntimeError("success=false for %s" % appid)
    return node["data"]

def dl(url, dst):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://store.steampowered.com/"})
    with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
        data = r.read()
    open(dst, "wb").write(data)
    return len(data)

JOBS = [
    (3052450, "morimens",  24),
    (769560,  "yueyuan",   24),
    (3117820, "sudan",     24),
]

for appid, tag, maxn in JOBS:
    try:
        d = appdetails(appid)
    except Exception as e:
        print("ERR appdetails", appid, e); continue
    name = d.get("name")
    print("=== %s (%s)  截图 %d 张 ===" % (name, appid, len(d.get("screenshots") or [])))
    outdir = os.path.join(OUT, tag)
    os.makedirs(outdir, exist_ok=True)
    # 头图 + 宣传图
    extra = []
    if d.get("header_image"): extra.append(("header", d["header_image"]))
    for i, s in enumerate(d.get("screenshots") or []):
        extra.append(("ss%02d" % i, s.get("path_full")))
    n = 0
    for label, url in extra:
        ext = os.path.splitext(url.split("?")[0])[1] or ".jpg"
        dst = os.path.join(outdir, "%s_%s%s" % (tag, label, ext))
        try:
            sz = dl(url, dst)
            print("  OK %8d  %s" % (sz, os.path.basename(dst)))
            n += 1
        except Exception as e:
            print("  ERR", label, e)
        if n >= maxn:
            break
    print("  ->", outdir, n)
