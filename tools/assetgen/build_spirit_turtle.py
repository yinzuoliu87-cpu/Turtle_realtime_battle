# -*- coding: utf-8 -*-
"""tools/assetgen/build_spirit_turtle.py — 训龟大师口哨召出的「灵体小龟」(assets/sprites/vfx/spirit-turtle.png)按新小龟重出(2026-11-05)。

原图是旧小龟画的; 小龟待机换成外包像素序列帧(pets/spine/basic_idle.png)后两只对不上。
做法: 取小龟待机第 0 帧 → 隔一取一缩一半(灵体小龟显示高 1.45 米, 缩一半后像素密度 ≈ 正常龟) → 按亮度映射成 4 档幽蓝
  (与旧图同一种「灵体」观感; 透明度二值, 不留半透) → 补成正方形(底边对齐、水平居中, 留 2px 边)。确定性, 重跑逐字节相同。
游戏里 trainer_system._spawn_spirit_turtle 按贴图高度算 pixel_size, 再整体乘幽蓝 modulate + 淡入淡出。
方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.3 待办。
用法: python tools/assetgen/build_spirit_turtle.py
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAD = 2
## 亮度 → 幽蓝 4 档(暗线 / 中 / 亮 / 高光), 分界按亮度 0~255
RAMP = [(60, (58, 96, 168)), (120, (112, 162, 226)), (185, (172, 212, 252)), (256, (226, 242, 255))]


def main() -> int:
	pets = json.load(open(os.path.join(ROOT, "data", "pets.json"), encoding="utf-8"))
	pets = pets["pets"] if isinstance(pets, dict) else pets
	b = next(p for p in pets if p["id"] == "basic")
	sp = b["sprite"]
	sheet = np.asarray(Image.open(os.path.join(ROOT, "assets", "sprites", b["img"])).convert("RGBA"))
	f0 = sheet[:int(sp["frameH"]), :int(sp["frameW"])].copy()
	f0[..., 3] = np.where(f0[..., 3] >= 128, 255, 0)
	f0[f0[..., 3] == 0] = 0
	ys, xs = np.where(f0[..., 3] > 0)
	body = f0[ys.min():ys.max() + 1, xs.min():xs.max() + 1][::2, ::2].copy()
	lum = body[..., :3].astype(int) @ np.array([299, 587, 114]) // 1000
	tint = np.zeros_like(body[..., :3])
	lo = -1
	for hi, rgb in RAMP:
		tint[(lum > lo) & (lum < hi)] = rgb
		lo = hi - 1
	body[..., :3] = np.where(body[..., 3:] > 0, tint, 0)
	h, w = body.shape[:2]
	side = max(h, w) + PAD * 2
	out = np.zeros((side, side, 4), dtype=np.uint8)
	ox, oy = (side - w) // 2, side - PAD - h
	out[oy:oy + h, ox:ox + w] = body
	dst = os.path.join(ROOT, "assets", "sprites", "vfx", "spirit-turtle.png")
	Image.fromarray(out, "RGBA").save(dst, optimize=False)
	print("灵体小龟 %d×%d ← %s 第 0 帧(本体 %d×%d)" % (side, side, b["img"], w, h))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
