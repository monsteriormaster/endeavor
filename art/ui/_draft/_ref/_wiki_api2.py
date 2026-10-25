# -*- coding: utf-8 -*-
import json, ssl, urllib.request, urllib.parse, os
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
OUT=r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref/sudan_wiki'
os.makedirs(OUT,exist_ok=True)
def api(params):
    u="https://sultansgame.wiki.gg/api.php?"+urllib.parse.urlencode(params)
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=40,context=CTX) as x: return json.loads(x.read().decode('utf-8','ignore'))
alln=[]; cont=None
for _ in range(6):
    p={"action":"query","list":"allimages","ailimit":"500","format":"json"}
    if cont: p["aicontinue"]=cont
    d=api(p)
    alln+= [i["name"] for i in d.get("query",{}).get("allimages",[])]
    cont=d.get("continue",{}).get("aicontinue")
    if not cont: break
print("总计", len(alln))
KEY=("slot","equip","panel","screen","ui_","_ui","hud","menu")
print("--- 命中 ---")
for n in sorted(set(alln)):
    if any(k in n.lower() for k in KEY): print("   ", n)
# 下载 Equipments.png
for n in ["Equipments.png"]:
    u="https://sultansgame.wiki.gg/images/"+urllib.parse.quote(n)
    r=urllib.request.Request(u,headers=HDR)
    with urllib.request.urlopen(r,timeout=60,context=CTX) as x: b=x.read()
    open(os.path.join(OUT,n),'wb').write(b)
    print("saved",n,len(b),"B")
