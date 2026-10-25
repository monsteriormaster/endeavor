import json
import os
import re

ROOT = r"C:\Users\26464\IdeaProjects\endeavor"
SRC = os.path.join(ROOT, "resoures", "triggers", "trigger.json")
OUT = os.path.join(ROOT, "art", "ui", "_draft", "_ref", "_q_text.log")


def load_lenient(path):
    raw = open(path, encoding="utf-8").read()
    try:
        return json.loads(raw)
    except Exception:
        fixed = re.sub(r",(\s*[}\]])", r"\1", raw)
        return json.loads(fixed)


def walk(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "显示内容" and isinstance(v, str):
                out.append(v)
            else:
                walk(v, out)
    elif isinstance(node, list):
        for v in node:
            walk(v, out)


with open(OUT, "w", encoding="utf-8") as f:
    data = load_lenient(SRC)
    texts = []
    walk(data, texts)
    # 同一个字符串会被多个 display 复用 -> 去重后再统计
    uniq = sorted(set(texts))
    lens = sorted(len(t) for t in uniq)
    n = len(lens)

    f.write("trigger.json 里 '显示内容' 去重后 %d 条（原始出现 %d 次）\n" % (n, len(texts)))
    f.write("字符数分布: min=%d\n" % lens[0])
    for q in (0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1.0):
        idx = min(n - 1, int(q * (n - 1) + 0.5))
        f.write("  p%-4s = %d\n" % (int(q * 100), lens[idx]))
    f.write("  mean = %.0f\n" % (sum(lens) / n))

    f.write("\n--- 最长的 8 条 ---\n")
    for t in sorted(uniq, key=len, reverse=True)[:8]:
        f.write("[%d] %s\n" % (len(t), t.replace("\n", "⏎")))

    f.write("\n--- 按 18px 字号估算（CJK 1em）---\n")
    for w in (744, 520, 420, 350):
        need = []
        for t in uniq:
            cpl = max(1, int(w // 18))          # 每行字数
            lines = 0
            for seg in t.split("\n"):
                lines += max(1, -(-len(seg) // cpl))
            need.append(lines * 25)             # 行距 25
        need.sort()
        f.write("  栏宽 %4dpx (每行 %2d 字): 中位 %3dpx, p90 %3dpx, 最大 %4dpx  (面板正文可用高约 530)\n"
                % (w, w // 18, need[len(need) // 2], need[int(0.9 * (len(need) - 1))], need[-1]))

print("OK", OUT)
