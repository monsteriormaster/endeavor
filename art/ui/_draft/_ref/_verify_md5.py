# -*- coding: utf-8 -*-
"""核对 Godot 导入侧车 .md5 的语义：source_md5 是不是原始文件 md5，dest_md5 是不是 ctex 的 md5。"""
import hashlib, os, shutil

R = r"C:\Users\26464\IdeaProjects\endeavor"
BAK = os.path.join(R, "art", "ai_assets_transparent", "card_frame_20260927_v0")


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


old_png = os.path.join(BAK, "card.png")
old_ctex = os.path.join(BAK, "card.png.ctex")
print("旧 card.png      md5 =", md5(old_png), "  期望 a4d0f89443a80083e3feaf2f04cd5f6a",
      "→", "✓" if md5(old_png) == "a4d0f89443a80083e3feaf2f04cd5f6a" else "✗")
print("旧 card.png.ctex md5 =", md5(old_ctex), "  期望 dd7de000bcff7ed4c6c479409ce9a3a5",
      "→", "✓" if md5(old_ctex) == "dd7de000bcff7ed4c6c479409ce9a3a5" else "✗")

new_png = os.path.join(R, "art", "card.png")
print("\n新 card.png      md5 =", md5(new_png), " size =", os.path.getsize(new_png))
print("新 card.png.import 是否仍在（未被我改动）:", os.path.exists(new_png + ".import"))
