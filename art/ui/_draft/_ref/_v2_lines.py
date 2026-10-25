# -*- coding: utf-8 -*-
# 提取 UI 截图里的「长横线 / 长竖线」，用直线结构反推面板与槽框布局
import os, sys
import numpy as np
from PIL import Image

BASE = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'

def longest_run(b):
    """b: 1-D bool array -> (start, length) of longest True run"""
    d = np.diff(np.concatenate(([0], b.astype(np.int8), [0])))
    s = np.flatnonzero(d == 1)
    e = np.flatnonzero(d == -1)
    if len(s) == 0:
        return 0, 0
    lens = e - s
    k = int(np.argmax(lens))
    return int(s[k]), int(lens[k])

def cluster(vals, gap=3):
    out = []
    for v in vals:
        if out and v - out[-1][-1] <= gap:
            out[-1].append(v)
        else:
            out.append([v])
    return [int(round(sum(g) / len(g))) for g in out]

def main(names):
    lines = []
    for n in names:
        p = n if os.path.isabs(n) else os.path.join(BASE, n)
        im = Image.open(p).convert('L')
        W, H = im.size
        a = np.asarray(im, dtype=np.int16)
        lines.append('=' * 90)
        lines.append('== %s  %dx%d' % (os.path.basename(n), W, H))
        for thr in (70, 100, 140):
            m = a > thr
            hs, vs = [], []
            for y in range(H):
                st, ln = longest_run(m[y])
                if ln > W * 0.45:
                    hs.append(y)
            for x in range(W):
                st, ln = longest_run(m[:, x])
                if ln > H * 0.45:
                    vs.append(x)
            lines.append('  thr=%d  H线(行号)=%s' % (thr, cluster(hs)))
            lines.append('  thr=%d  V线(列号)=%s' % (thr, cluster(vs)))
        # 用中等阈值扫「较长但不过半」的竖线（槽框竖边常只有 100~200px 高）
        thr = 100
        m = a > thr
        vseg = []
        for x in range(W):
            st, ln = longest_run(m[:, x])
            if ln > H * 0.15:
                vseg.append((x, st, st + ln - 1, ln))
        # 按 x 聚簇，保留每簇里最长的
        merg = []
        for it in vseg:
            if merg and it[0] - merg[-1][-1][0] <= 3:
                merg[-1].append(it)
            else:
                merg.append([it])
        keeps = []
        for g in merg:
            best = max(g, key=lambda t: t[3])
            keeps.append(best)
        lines.append('  --- 竖线段(>15%% 高) %d 条 ---' % len(keeps))
        for x, s, e, ln in keeps[:60]:
            lines.append('     x=%4d  y %4d..%4d  len=%4d' % (x, s, e, ln))
    return lines

if __name__ == '__main__':
    out = main(sys.argv[1:])
    log = os.path.join(BASE, '_v2_lines.log')
    with open(log, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print('written', log)
