# -*- coding: utf-8 -*-
import json, ssl, urllib.request, urllib.parse
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
def api(params):
    u="https://sultansgame.wiki.gg/api.php?"+urllib.parse.urlencode(params)
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=40,context=CTX) as x:
        return json.loads(x.read().decode('utf-8','ignore'))
d=api({"action":"query","list":"allimages","ailimit":"500","format":"json"})
names=[i["name"] for i in d.get("query",{}).get("allimages",[])]
print("共", len(names))
KEY=("slot","equip","card","weapon","attire","accessory","animal","panel","screen","ui")
for n in sorted(names):
    if any(k in n.lower() for k in KEY):
        print("  ", n)
