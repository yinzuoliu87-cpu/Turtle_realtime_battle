# -*- coding: utf-8 -*-
"""tools/assetgen/build_bio_chain_h.py — 精英小将铁锁链环横向版 bio-chain-h.png(2026-11-11)。

用户 11-11「这个铁链，这个到底整个铁链长啥样？你有没有看到？」⇒ 查出 bio-chain.png(32×32)画的是**竖着**两节链,
PullRopeVfx 按「横向一节」沿链方向转 ⇒ 每节与链子垂直, 加上每 55 码一节 ⇒ 一排漂着的小竖记号。
这里把它顺时针转 90° 成横向一节(两节链环左右相扣), PullRopeVfx.shoot 按链环长度首尾相接铺。
过渡件: 新链子(两种链环交替 + 尖穿刺链头)画好后替换(方案书 docs/plans/20261111-忍者普攻与小将铁链与灵物统计.md §4 C)。
确定性: 只做无损旋转, 重跑逐字节相同。用法: python tools/assetgen/build_bio_chain_h.py
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "assets", "sprites", "vfx", "bio-chain.png")
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "bio-chain-h.png")

im = Image.open(SRC).convert("RGBA").transpose(Image.Transpose.ROTATE_270)
bb = im.getbbox()
im = im.crop((bb[0], bb[1], bb[2], bb[3]))   # 去掉上下空白, 链子粗细 = 图高
im.save(OUT, optimize=False)
print("写出", OUT, im.size)
