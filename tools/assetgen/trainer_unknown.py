# -*- coding: utf-8 -*-
"""trainer_unknown.py —— 图鉴「角色」栏训龟大师的形象: 一个像素风问号(2026-11-27)。

用户 11-27:「训龟大师的形象不要用这个老头，最好用个像素风的问号。因为训龟大师的形象本来就是…玩家可以自己选的。」
做法(如实): 与召唤物技能图标同一套(icon_kit.py): 逐像素按几何上色 —— 问号的弯钩(圆弧带) + 斜下的竖 + 底下一个点,
金色左上亮边、深色描边、背后一圈硬边光; 分层 PNG 再拼 .aseprite(tools/assetgen/ase/summon_icons/trainer-unknown.aseprite)。
不是手画、不是 AI 生成; 重跑逐字节相同。64×64, 同时用作列表头像(avatars/summon-trainer.png)与详情立绘(trainer/trainer-unknown.png)。
用法: python tools/assetgen/trainer_unknown.py
"""
import math, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from icon_kit import *  # noqa: F401,F403
import icon_kit as K

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, ".out", "summon_icons_all")


def main():
	ic = Icon()
	cx, cy, r, th = 32.0, 22.0, 15.0, 7.5
	def hook(x, y, px, py):                       # 弯钩: 从左边起, 经过顶上, 绕到右下
		dx, dy = px - cx, py - cy
		d = math.hypot(dx, dy)
		a = math.atan2(dy, dx)
		if r - th <= d <= r and (a <= 0.75 or a >= math.pi * 0.98 or a <= -math.pi * 0.98 or a < 0):
			if a > 0.75 and a < math.pi * 0.98:
				return
			ic.put("body", x, y, GOLD[lit_idx(dx, dy, r, 4, 0.1)])
	each(hook)
	ex, ey = cx + math.cos(0.75) * (r - th / 2), cy + math.sin(0.75) * (r - th / 2)
	thick_line(ic, "body", (ex, ey), (33.0, 40.0), 3.8, [GOLD[1], GOLD[2], GOLD[3]])   # 斜下来的一笔
	thick_line(ic, "body", (33.0, 40.0), (33.0, 45.0), 3.8, [GOLD[1], GOLD[2], GOLD[3]])
	ellipse(ic, "body", 33.0, 55.0, 5.0, 5.0, GOLD)                                     # 底下的点
	ic.rim()
	ic.halo([GOLD[3]])
	sparkle(ic, 21.0, 12.0, 4)
	K.finish_all([("trainer-unknown", ic)], OUT)
	src = os.path.join(OUT, "trainer-unknown", "trainer-unknown.png")
	for dst in ("assets/sprites/avatars/summon-trainer.png", "assets/sprites/trainer/trainer-unknown.png"):
		shutil.copyfile(src, os.path.join(ROOT, dst))
	print("ok", src)


if __name__ == "__main__":
	main()
