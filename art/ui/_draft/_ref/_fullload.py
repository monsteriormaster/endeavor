# -*- coding: utf-8 -*-
"""全量加载检查：跑 --headless --quit，并保护 user:// 存档（跑前备份、跑后按 md5 判断是否被改）。
Godot 无头运行有覆盖 %APPDATA%\\Godot\\app_userdata\\endeavor 的风险，不能不做保护。"""
import hashlib, os, shutil, subprocess, glob

R = r"C:\Users\26464\IdeaProjects\endeavor"
GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
APPDATA = os.environ.get("APPDATA", "")
UD = os.path.join(APPDATA, "Godot", "app_userdata", "endeavor")
TMP = os.path.join(R, ".workbuddy", "tmp", "_save_backup")


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def main():
    os.makedirs(TMP, exist_ok=True)
    files = glob.glob(os.path.join(UD, "*.json")) + glob.glob(os.path.join(UD, "*.cfg"))
    before = {}
    for f in files:
        b = os.path.join(TMP, os.path.basename(f))
        shutil.copy2(f, b)
        before[f] = md5(f)
    print("[备份] %d 个存档/配置文件 → %s" % (len(before), TMP))
    for f, m in before.items():
        print("   ", os.path.basename(f), m)

    cmd = [GODOT, "--headless", "--path", R, "--quit"]
    print("\n[运行]", " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=300)
    log = (r.stdout or "") + "\n" + (r.stderr or "")
    lp = os.path.join(R, "debug", "_fullload.log")
    with open(lp, "w", encoding="utf-8") as f:
        f.write(log)
    print("exit=%d  日志 → debug/_fullload.log" % r.returncode)

    errs = [l for l in log.splitlines()
            if ("ERROR" in l or "SCRIPT ERROR" in l or "Parse Error" in l or "Invalid" in l)]
    print("\n[错误行] %d 条" % len(errs))
    for l in errs[:40]:
        print("   |", l)

    print("\n[存档是否被改]")
    changed = []
    for f, m in before.items():
        now = md5(f) if os.path.exists(f) else "(文件消失)"
        st = "未变" if now == m else "★被改"
        if now != m:
            changed.append(f)
        print("   %-28s %s" % (os.path.basename(f), st))
    if changed:
        for f in changed:
            shutil.copy2(os.path.join(TMP, os.path.basename(f)), f)
            print("   → 已还原", os.path.basename(f))
    else:
        print("   （无需还原）")


main()
