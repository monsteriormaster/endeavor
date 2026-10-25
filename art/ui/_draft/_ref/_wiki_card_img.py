# -*- coding: utf-8 -*-
import re, ssl, urllib.request
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
def html(u):
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=40,context=CTX) as x: return x.read().decode('utf-8','ignore')
for page in ["Maggie","Cards","Characters"]:
    try:
        h=html("https://sultansgame.wiki.gg/wiki/"+page)
    except Exception as e:
        print(page,"ERR",e); continue
    urls=set()
    for m in re.findall(r'(?:src|href)="([^"]+)"', h):
        if '/images/' in m and not m.endswith('.ico'):
            urls.add(m.split('?')[0])
    print("="*60); print(page, len(urls))
    for u in sorted(urls):
        print("   ", u)
