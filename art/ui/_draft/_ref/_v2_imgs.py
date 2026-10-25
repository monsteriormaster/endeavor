# -*- coding: utf-8 -*-
"""从攻略页 HTML 提所有图片直链（不下载，只列），用来找苏丹事件界面的大图。"""
import re, os, io, ssl, urllib.request
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
HDR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}

PAGES = [
    "https://m.925g.com/jxgl/318129.html",
    "https://www.39kf.com/game/135618.html",
    "https://m.3dmgame.com/gl/3965650_6.html",
    "https://www.yuanyz6.cn/?p=43473/",
]
OUT = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\_v2_imgs.log"
buf = []
for u in PAGES:
    buf.append("=" * 90)
    buf.append("PAGE " + u)
    try:
        html = urllib.request.urlopen(urllib.request.Request(u, headers=HDR), timeout=30, context=ctx).read()
    except Exception as e:
        buf.append("  FAIL " + repr(e)[:180]); continue
    txt = html.decode("utf-8", "ignore")
    hits = re.findall(r"""(?:src|data-src|data-original|href)\s*=\s*["']([^"']+\.(?:png|jpg|jpeg|webp)[^"']*)["']""", txt, re.I)
    seen = []
    for h in hits:
        if h in seen: continue
        seen.append(h)
    for h in seen:
        buf.append("  " + h)
    # 顺带把正文里的文字提一段（去掉标签），看有没有更多界面描述
    body = re.sub(r"<(script|style)[\s\S]*?</\1>", " ", txt, flags=re.I)
    body = re.sub(r"<[^>]+>", "\n", body)
    body = re.sub(r"\n{2,}", "\n", body)
    lines = [l.strip() for l in body.split("\n") if len(l.strip()) > 12]
    buf.append("  --- 正文含「槽」「界面」「放置」「图标」的行 ---")
    for l in lines:
        if any(k in l for k in ("槽", "界面", "放置", "图标", "事件")):
            buf.append("  | " + l[:260])
io.open(OUT, "w", encoding="utf-8").write("\n".join(buf))
print("\n".join(buf))
