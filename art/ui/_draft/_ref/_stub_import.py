# -*- coding: utf-8 -*-
"""工程外 stub 导入：绕开「编辑器开着不能跑 --import」的限制。

原理：新建一个临时 Godot 工程，把待导入的 png 和**原工程的 .import**（= 原样参数）放进去，
跑 --headless --import 生成 .ctex，再把 .ctex 拷回原工程的 .godot/imported/ **同名覆盖**。
因为 .import 里的 dest_files 路径没变，**原 .import 一个字都不用改**，uid / 参数全部保留；
最后重写 .md5 侧车（source_md5 = 源图 md5，dest_md5 = ctex md5，两边语义已实测核对过）。
"""
import hashlib, os, shutil, subprocess, sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
STUB = r"C:\Users\26464\IdeaProjects\_endeavor_import_stub"
BAK = os.path.join(R, "art", "ai_assets_transparent", "card_frame_20260927_v0")

SRC_PNG = os.path.join(R, "art", "card.png")
SRC_IMPORT = os.path.join(BAK, "card.png.import")          # 原参数（从备份取）
DEST_CTEX_REL = "card.png-cbf59a8dc0f4acbf700dd43db8122ba8.ctex"   # 与原 .import 的 dest_files 一致
DEST_CTEX = os.path.join(R, ".godot", "imported", DEST_CTEX_REL)
DEST_MD5 = DEST_CTEX[:-5] + ".md5"


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    # ---------- 1) 搭 stub 工程 ----------
    if os.path.isdir(STUB):
        shutil.rmtree(STUB, ignore_errors=True)
    os.makedirs(os.path.join(STUB, "art"), exist_ok=True)
    with open(os.path.join(STUB, "project.godot"), "w", encoding="utf-8") as f:
        f.write('config_version=5\n\n[application]\n\nconfig/name="stub"\n'
                'config/features=PackedStringArray("4.7", "GL Compatibility")\n\n'
                '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copy2(SRC_PNG, os.path.join(STUB, "art", "card.png"))
    shutil.copy2(SRC_IMPORT, os.path.join(STUB, "art", "card.png.import"))
    assert not os.path.exists(os.path.join(STUB, ".godot")), "stub 里不应有旧 .godot"
    print("[1] stub 工程已搭好:", STUB)

    # ---------- 2) 导入 ----------
    cmd = [GODOT, "--headless", "--path", STUB, "--import"]
    print("[2] 运行:", " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=300)
    log = (r.stdout or "") + "\n" + (r.stderr or "")
    with open(os.path.join(STUB, "_import.log"), "w", encoding="utf-8") as f:
        f.write(log)
    print("    exit=%d  日志尾部:" % r.returncode)
    for line in [l for l in log.splitlines() if l.strip()][-12:]:
        print("    |", line)

    # ---------- 3) 找 stub 产出的 ctex ----------
    imp = os.path.join(STUB, ".godot", "imported")
    if not os.path.isdir(imp):
        print("!! stub 没有产出 .godot/imported，中止"); sys.exit(1)
    cands = [f for f in os.listdir(imp) if f.startswith("card.png-") and f.endswith(".ctex")]
    print("[3] stub 产出:", cands)
    # 优先选与本工程 dest 同名的；否则取第一个
    pick = DEST_CTEX_REL if DEST_CTEX_REL in cands else (cands[0] if cands else None)
    if pick is None:
        print("!! 没找到 ctex，中止"); sys.exit(1)
    src_ctex = os.path.join(imp, pick)
    print("    选用:", pick, os.path.getsize(src_ctex), "bytes")

    # ---------- 4) 拷回原工程 ----------
    shutil.copy2(src_ctex, DEST_CTEX)
    print("[4] 已覆盖:", os.path.relpath(DEST_CTEX, R))

    # ---------- 5) 重写 .md5 侧车 ----------
    s, d = md5(SRC_PNG), md5(DEST_CTEX)
    with open(DEST_MD5, "w", encoding="utf-8") as f:
        f.write('source_md5="%s"\ndest_md5="%s"\n\n' % (s, d))
    print("[5] 侧车已重写: source_md5=%s  dest_md5=%s" % (s, d))

    # ---------- 6) 核对 ----------
    print("\n[6] 核对：")
    print("    新 card.png md5      =", s)
    print("    .md5 里的 source_md5 =", open(DEST_MD5, encoding="utf-8").read().split('"')[1])
    print("    .import 的 dest_files 未改动 =",
          DEST_CTEX_REL in open(os.path.join(R, "art", "card.png.import"), encoding="utf-8").read())
    print("    新 ctex 大小 =", os.path.getsize(DEST_CTEX), "（旧的 205136）")


main()
