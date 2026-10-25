# -*- coding: utf-8 -*-
import os, ssl, urllib.request

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
HDR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
       "Referer": "https://www.ali213.net/"}
DST = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_panel"
os.makedirs(DST, exist_ok=True)

URLS = [
    ("wywyx_slots.jpg", "https://img1.wywyx.com/uploads/allimg/250418/61-25041R12221.jpg"),
    ("ali_0410_a.jpg", "https://img1.ali213.net/glpic/2025/04/10/8dfc36f1-ec70-efbe-def5-02c7e6c683c4.jpg"),
    ("ali_0410_b.jpg", "https://img1.ali213.net/glpic/2025/04/10/93edf925-3653-9ba9-3df0-62f7b849216c.jpg"),
    ("ali_0410_c.jpg", "https://img1.ali213.net/glpic/2025/04/10/6259d5b9-b76a-c5b6-049f-27ec55c5323f.jpg"),
    ("ali_0410_d.jpg", "https://img1.ali213.net/glpic/2025/04/10/d62956a6-a1da-08dd-f407-7624791c4ace.jpg"),
    ("ali_0401.png", "https://img1.ali213.net/glpic/2025/04/01/20250401110148452.png"),
    ("ali_0403.png", "https://img1.ali213.net/glpic/2025/04/03/2025040392108971.png"),
    ("ali_0402.png", "https://img1.ali213.net/glpic/2025/04/02/2025040214724452.png"),
]

for name, u in URLS:
    p = os.path.join(DST, name)
    try:
        req = urllib.request.Request(u, headers=HDR)
        with urllib.request.urlopen(req, timeout=40, context=CTX) as r:
            data = r.read()
        with open(p, "wb") as f:
            f.write(data)
        print("OK  %8d  %s" % (len(data), name))
    except Exception as e:
        print("ERR", name, e)
