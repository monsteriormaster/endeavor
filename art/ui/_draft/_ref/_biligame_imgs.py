# -*- coding: utf-8 -*-
import re, ssl, urllib.request, urllib.parse
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
     "Referer":"https://wiki.biligame.com/"}
def get(u):
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=45,context=CTX) as x: return x.read()
PAGES=["https://wiki.biligame.com/sultansgame/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97",
       "https://wiki.biligame.com/sultansgame/%E9%A6%96%E9%A1%B5"]
for u in PAGES:
    print("="*70); print(u)
    try:
        h=get(u).decode('utf-8','ignore')
    except Exception as e:
        print("  ERR",e); continue
    srcs=set()
    for m in re.findall(r'(?:src|data-src)="([^"]+)"',h):
        if re.search(r'\.(png|jpg|jpeg|gif|webp)',m,re.I) and 'icon' not in m.lower():
            srcs.add(m.split('?')[0])
    for s in sorted(srcs)[:60]:
        print("   ", s)
