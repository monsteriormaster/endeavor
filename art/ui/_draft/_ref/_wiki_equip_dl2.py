# -*- coding: utf-8 -*-
import os, ssl, urllib.request
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
HDR = {"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
OUT = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref/sudan_wiki'
os.makedirs(OUT, exist_ok=True)
NAMES = ["Equip_slot","Accessory_equip","Accessory_unequip","Animal_equip","Animal_unequip",
         "Attire_equip","Attire_unequip","Weapon_equip","Weapon_unequip"]
for n in NAMES:
    u = "https://sultansgame.wiki.gg/images/%s.png" % n
    try:
        req = urllib.request.Request(u, headers=HDR)
        with urllib.request.urlopen(req, timeout=40, context=CTX) as r:
            b = r.read()
        p = os.path.join(OUT, n + ".png")
        open(p,'wb').write(b)
        print("saved %-24s %6d B" % (n, len(b)))
    except Exception as e:
        print("ERR", n, e)
