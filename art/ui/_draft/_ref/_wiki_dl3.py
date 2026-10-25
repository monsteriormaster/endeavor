# -*- coding: utf-8 -*-
import ssl, urllib.request, urllib.parse, os
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
OUT=r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref/sudan_wiki'
for n in ["Screenshot_rep.png","Prison_screenshot.jpg","House_of_Delights_screenshot.jpg"]:
    u="https://sultansgame.wiki.gg/images/"+urllib.parse.quote(n)
    try:
        r=urllib.request.Request(u,headers=HDR)
        with urllib.request.urlopen(r,timeout=60,context=CTX) as x: b=x.read()
        open(os.path.join(OUT,n),'wb').write(b); print("saved",n,len(b))
    except Exception as e: print("ERR",n,e)
