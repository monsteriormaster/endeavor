# -*- coding: utf-8 -*-
"""统计 trigger.json 里每个 phase 的卡槽：数量 / 槽名 / accept / required。
目的：决定放大卡槽后网格列数（4 列 2 行 还是 3 列 N 行）。
宽容解析：去掉尾逗号（resoures/characters.json 同族写法）。"""
import re, json, io, collections, os, sys

ROOT = r"C:\Users\26464\IdeaProjects\endeavor"
SRC = os.path.join(ROOT, "resoures", "triggers", "trigger.json")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_q_slots.log")

buf = []
def p(*a):
    buf.append(" ".join(str(x) for x in a))

raw = io.open(SRC, encoding="utf-8").read()
clean = re.sub(r",(\s*[}\]])", r"\1", raw)
data = json.loads(clean)

counts = collections.Counter()      # 槽数 -> 出现次数
names = collections.Counter()       # 槽名 -> 次数
accepts = collections.Counter()     # accept 值 -> 次数
req = collections.Counter()         # required True/False
maxslots = 0
rows = []

def walk(node, path=""):
    global maxslots
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "slots" and isinstance(v, dict):
                n = len(v)
                counts[n] += 1
                maxslots = max(maxslots, n)
                detail = []
                for sn, sv in v.items():
                    names[sn] += 1
                    if isinstance(sv, dict):
                        a = sv.get("accept", "")
                        accepts[str(a)] += 1
                        r = bool(sv.get("required", False))
                        req[r] += 1
                        detail.append("%s/%s%s" % (sn, a, "*" if r else ""))
                    else:
                        detail.append("%s/?" % sn)
                rows.append((path, n, detail))
            walk(v, path + "/" + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, path + "[%d]" % i)

walk(data)

p("=== 每处 slots 的槽数分布 ===")
for n in sorted(counts):
    p("  %d 槽 : %d 处" % (n, counts[n]))
p("  最大槽数 = %d ｜ slots 出现总处数 = %d" % (maxslots, sum(counts.values())))

p("")
p("=== 槽名 Top（用来定「空槽画什么」的类别集）===")
for k, v in names.most_common(30):
    p("  %-14s %d" % (k, v))
p("  不同槽名共 %d 种" % len(names))

p("")
p("=== accept 值分布 ===")
for k, v in accepts.most_common(30):
    p("  %-14s %d" % (k, v))

p("")
p("=== required ===")
p("  必需槽 %d ／ 可选槽 %d" % (req[True], req[False]))

p("")
p("=== 槽数 >=7 的实例（放大后最挤的那些）===")
for path, n, detail in rows:
    if n >= 7:
        p("  [%d] %s" % (n, path))
        p("       %s" % "  ".join(detail))

io.open(OUT, "w", encoding="utf-8").write("\n".join(buf))
print("\n".join(buf))
