# -*- coding: utf-8 -*-
# 把 UI 截图「线稿化」：只保留长横线 / 长竖线，再按字符格渲成 ASCII。
#   mode=bright : 亮线（暗底 UI）      thr 自适应 p85
#   mode=dark   : 暗线（亮底 UI）      thr 自适应 p15
#   mode=edge   : 梯度线（任意底色）    thr 自适应 p92（Sobel 幅值）
import os, sys
import numpy as np
from PIL import Image

BASE = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'

def runs_1d(b):
    d = np.diff(np.concatenate(([0], b.astype(np.int8), [0])))
    s = np.flatnonzero(d == 1)
    e = np.flatnonzero(d == -1)
    return list(zip(s.tolist(), (e - s).tolist()))

def linify(m, min_len, vertical=True):
    H, W = m.shape
    out = np.zeros_like(m)
    if vertical:
        for x in range(W):
            for st, ln in runs_1d(m[:, x]):
                if ln >= min_len:
                    out[st:st + ln, x] = True
    else:
        for y in range(H):
            for st, ln in runs_1d(m[y]):
                if ln >= min_len:
                    out[y, st:st + ln] = True
    return out

def render(mask, cell):
    H, W = mask.shape
    rows = []
    for y0 in range(0, H, cell):
        line = []
        for x0 in range(0, W, cell):
            n = int(mask[y0:y0 + cell, x0:x0 + cell].sum())
            line.append('.' if n == 0 else ('-' if n < cell * 0.5 else '#'))
        rows.append(line)
    return rows

def main():
    out = []
    for arg in sys.argv[1:]:
        parts = arg.split(',')
        name = parts[0]
        o = {'thr': '0', 'cell': '5', 'minlen': '40', 'mode': 'bright'}
        for p in parts[1:]:
            k, v = p.split('='); o[k] = v
        cell = int(o['cell']); minlen = int(o['minlen']); mode = o['mode']; thr = int(o['thr'])
        p = name if os.path.isabs(name) else os.path.join(BASE, name)
        im = Image.open(p).convert('L')
        W, H = im.size
        a = np.asarray(im, dtype=np.float32)

        if mode == 'edge':
            gx = np.zeros_like(a); gy = np.zeros_like(a)
            gx[:, 1:] = np.abs(a[:, 1:] - a[:, :-1])
            gy[1:, :] = np.abs(a[1:, :] - a[:-1, :])
            mag = gx + gy
            t = thr if thr else int(np.percentile(mag, 92))
            m = mag > t
        elif mode == 'dark':
            t = thr if thr else int(np.percentile(a, 15))
            m = a < t
        else:
            t = thr if thr else int(np.percentile(a, 85))
            m = a > t

        # 太长的一条线（整幅边界）先排掉噪点影响：要求某行/列里像素连续
        Vm = linify(m, minlen, True)
        Hm = linify(m, minlen, False)
        vr = render(Vm, cell); hr = render(Hm, cell)
        chunk = []
        chunk.append('=' * 104)
        chunk.append('== %s  %dx%d  mode=%s thr=%d  cell=%dpx/char  minlen=%dpx'
                     % (os.path.basename(name), W, H, mode, t, cell, minlen))
        chunk.append('     ' + ''.join(str(((i * cell) // 100) % 10) for i in range(len(vr[0]))))
        for i in range(len(vr)):
            merged = ''.join('=' if hr[i][j] == '#' else vr[i][j] for j in range(len(vr[i])))
            chunk.append('%4d %s' % (i * cell, merged))
        out.extend(chunk)
        per = os.path.join(BASE, '_v2_ui_%s.log' % os.path.splitext(os.path.basename(name))[0])
        with open(per, 'w', encoding='utf-8') as f:
            f.write('\n'.join(chunk))
    log = os.path.join(BASE, '_v2_ui.log')
    with open(log, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print('written', log)

if __name__ == '__main__':
    main()
