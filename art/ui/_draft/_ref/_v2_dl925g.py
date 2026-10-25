# -*- coding: utf-8 -*-
# 抓取 925g「事件界面」文章里的全部正文配图
import os, urllib.request, ssl

BASE = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_panel'
os.makedirs(BASE, exist_ok=True)

URLS = {
    'g1': 'https://img.925g.com/upload/cms/20230321/1614/b60fd9c7241ea7e8f337b1470cba2d85.png',
    'g2': 'https://img.925g.com/upload/cms/20230321/1750/9c4baca599c6952818680893c81f8f47.png',
    'g3': 'https://img.925g.com/upload/cms/20230321/1156/646407d1f58113ae77a06446f5208f79.png',
    'g4': 'https://img.925g.com/upload/cms/20230321/1644/2b17d558aee15cb16cd7234d46affe22.png',
    'g5': 'https://img.925g.com/upload/cms/20230323/1016/62d4e024b4757d3fdf59bf171519f92e.png',
    'g6': 'https://img.925g.com/upload/cms/20230323/1643/7ff3995878a6873c46a690a77d7e95a7.png',
    'g7': 'https://img.925g.com/upload/cms/20230321/1649/68c77bfaf72f3932e0f3820af52da43e.png',
    'dm1': 'https://img.3dmgame.com/uploads/images/gl/20250408/1744076274_902749_png_r.png',
    'dm2': 'https://img.3dmgame.com/uploads/images/gl/20250408/1744076274_557814_jpeg_r.jpeg',
    'dm3': 'https://img.3dmgame.com/uploads/images/gl/20250408/1744076276_946173_png_r.png',
}

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

log = []
for k, u in URLS.items():
    ext = '.png' if u.lower().endswith('png') or 'png_r' in u else '.jpg'
    dst = os.path.join(BASE, 'src_%s%s' % (k, ext))
    try:
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=25, context=ctx) as r:
            data = r.read()
        with open(dst, 'wb') as f:
            f.write(data)
        log.append('OK  %-4s %8d bytes -> %s' % (k, len(data), os.path.basename(dst)))
    except Exception as e:
        log.append('ERR %-4s %s' % (k, e))

with open(os.path.join(BASE, '_dl925g.log'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(log))
print('\n'.join(log))
