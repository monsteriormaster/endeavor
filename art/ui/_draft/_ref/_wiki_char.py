# -*- coding: utf-8 -*-
import json, ssl, urllib.request, urllib.parse, re
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
def api(p):
    u="https://sultansgame.wiki.gg/api.php?"+urllib.parse.urlencode(p)
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=40,context=CTX) as x: return json.loads(x.read().decode('utf-8','ignore'))
for t in ["Adila","Aziz","Cards"]:
    d=api({"action":"parse","page":t,"prop":"wikitext","format":"json"})
    wt=d.get("parse",{}).get("wikitext",{}).get("*","")
    print("="*70); print(t, "len", len(wt))
    # 找 equip slot 相关行
    for i,l in enumerate(wt.split("\n")):
        if re.search(r'equip|slot|Weapon_|Attire_|Accessory_|Animal_', l, re.I):
            print("  %4d| %s" % (i, l[:220]))
