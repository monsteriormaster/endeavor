# -*- coding: utf-8 -*-
# 亮度缩略图：把若干张图并排渲成 ASCII（cols x rows，按字符 2:1 长宽比取样）
import os, sys
import numpy as np
from PIL import Image

BASE = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'
RAMP = ' .:-=+*#%@'

def thumbs(names, cols=40, rows=20, per_line=2):
    blocks = []
    for n in names:
        p = n if os.path.isabs(n) else os.path.join(BASE, n)
        im = Image.open(p).convert('L').resize((cols, rows), Image.LANCZOS)
        a = np.asarray(im, dtype=np.float32)
        lo, hi = float(a.min()), float(a.max())
        if hi - lo < 1:
            hi = lo + 1
        g = ((a - lo) / (hi - lo) * (len(RAMP) - 1)).astype(int)
        blocks.append((os.path.basename(n), [''.join(RAMP[v] for v in row) for row in g]))
    out = []
    for i in range(0, len(blocks), per_line):
        grp = blocks[i:i + per_line]
        out.append(' | '.join('%-*s' % (cols, t[0][:cols * 2]) for t in grp))
        for r in range(rows):
            out.append(' | '.join(t[1][r] for t in grp))
        out.append('')
    return out

if __name__ == '__main__':
    spec = sys.argv[1]
    names = [x for x in sys.argv[2:] if not x.startswith('--')]
    cols = rows = None
    args = dict(s.split('=') for s in sys.argv[2:] if s.startswith('--'))
    cols = int(args.get('--cols', 40)); rows = int(args.get('--rows', 20))
    per = int(args.get('--per', 2))
    txt = thumbs(names, cols, rows, per)
    dst = sys.argv[1]
    with open(dst, 'w', encoding='utf-8') as f:
        f.write('\n'.join(txt))
    print('written', dst, len(txt), 'lines')
