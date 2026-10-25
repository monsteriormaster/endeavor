# -*- coding: utf-8 -*-
"""苏丹的游戏 截图：多源重试。"""
import json, os, ssl, re, time, urllib.request
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
OUT = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan"
os.makedirs(OUT, exist_ok=True)

def get(u, binary=False, referer=None, timeout=60):
    h = {"User-Agent": UA, "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"}
    if referer: h["Referer"] = referer
    with urllib.request.urlopen(urllib.request.Request(u, headers=h), timeout=timeout, context=CTX) as r:
        d = r.read()
    return d if binary else d.decode("utf-8", "ignore")

shots = []
# 源1: appdetails 多语言重试
for lg, cc in (("english","us"), ("schinese","CN"), ("english","CN")):
    for attempt in range(2):
        try:
            t = get("https://store.steampowered.com/api/appdetails?appids=3117820&l=%s&cc=%s" % (lg, cc))
            d = json.loads(t)
            node = d.get("3117820") or list(d.values())[0]
            if node.get("success"):
                data = node["data"]
                print("appdetails OK lang=%s/%s name=%s ss=%d" % (lg, cc, data.get("name"), len(data.get("screenshots") or [])))
                if data.get("header_image"): shots.append(("header", data["header_image"]))
                for i, s in enumerate(data.get("screenshots") or []):
                    shots.append(("ss%02d" % i, s["path_full"]))
                break
        except Exception as e:
            print("  attempt %d %s/%s ERR %s" % (attempt, lg, cc, e))
            time.sleep(2)
    if shots: break

# 源2: 商店页 HTML
if not shots:
    for lg in ("schinese", "english"):
        try:
            h = get("https://store.steampowered.com/app/3117820/?l=%s&cc=CN" % lg)
            print("storepage len", len(h))
            cand = set(re.findall(r'https://[^"\'\\ ]*(?:steamstatic|akamai)[^"\'\\ ]*\.(?:jpg|png)', h))
            cand = [c for c in cand if "/apps/3117820/" in c or "store_item_assets" in c]
            for c in sorted(cand)[:30]:
                shots.append(("page%02d" % len(shots), c))
            print("storepage candidates", len(cand))
            if shots: break
        except Exception as e:
            print("storepage ERR", e)

print("total candidates", len(shots))
n = 0
for label, u in shots:
    ext = os.path.splitext(u.split("?")[0])[1].lower() or ".jpg"
    dst = os.path.join(OUT, "sudan_%s%s" % (label, ext))
    try:
        b = get(u, binary=True, referer="https://store.steampowered.com/", timeout=90)
        if len(b) < 4096:
            print("  skip small", u); continue
        open(dst, "wb").write(b)
        print("  OK %8d %s <- %s" % (len(b), os.path.basename(dst), u))
        n += 1
    except Exception as e:
        print("  ERR", u, e)
print("SAVED", n, "->", OUT)
