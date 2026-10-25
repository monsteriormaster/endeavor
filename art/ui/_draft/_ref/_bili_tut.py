# -*- coding: utf-8 -*-
import os, ssl, urllib.request, urllib.parse
CTX=ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
     "Referer":"https://wiki.biligame.com/sultansgame/"}
OUT=r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref/sudan_wiki'
URLS=["https://patchwiki.biligame.com/images/sultansgame/thumb/7/7a/ml0uofd3aaofqp2z52l1lg78htiohgx.jpg/1300px-Tutorial1.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/e/ea/priz9sn0rfqdmzoqz86wws02nohqz69.jpg/1300px-Tutorial1-1.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/9/97/3xmrs2zx1x9fcmvsvvk3884jynteja6.jpg/1300px-Tutorial1-2.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/e/e1/1lj3abrtyeplq7l5cyeqrxlqi0rwff8.jpg/1300px-Tutorial1-4.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/3/3f/cmuxg98iiqs4h4gto9nnf1qqcsgc30k.jpg/1300px-Tutorial1-5.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/7/79/jaangemtisonhk3gopl0r8b0ntoptzf.jpg/1300px-Tutorial1-6.jpg",
"https://patchwiki.biligame.com/images/sultansgame/thumb/9/9f/bje2s7tpeuibsenr0pv0ukfvj92ou2t.jpg/1300px-Tutorial1-7.jpg",
"https://patchwiki.biligame.com/images/sultansgame/3/3b/d985uqbcdi15y4o3qlvj6ophbpvkktf.jpg"]
for u in URLS:
    n=urllib.parse.unquote(u.rsplit('/',1)[-1])
    try:
        r=urllib.request.Request(u,headers=HDR)
        with urllib.request.urlopen(r,timeout=60,context=CTX) as x: b=x.read()
        p=os.path.join(OUT,n); open(p,'wb').write(b); print("saved %-28s %7d B"%(n,len(b)))
    except Exception as e: print("ERR",n,e)
