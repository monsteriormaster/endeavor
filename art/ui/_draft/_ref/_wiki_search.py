# -*- coding: utf-8 -*-
import json, ssl, urllib.request, urllib.parse, re
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
def api(p):
    u="https://sultansgame.wiki.gg/api.php?"+urllib.parse.urlencode(p)
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=40,context=CTX) as x: return json.loads(x.read().decode('utf-8','ignore'))
for q in ['equip slot','insource:"equip slot"','"Equip Slot"','card description equip']:
    d=api({"action":"query","list":"search","srsearch":q,"srlimit":"20","format":"json"})
    print("="*60); print("Q:", q)
    for it in d.get("query",{}).get("search",[]):
        print("   ", it["title"])
