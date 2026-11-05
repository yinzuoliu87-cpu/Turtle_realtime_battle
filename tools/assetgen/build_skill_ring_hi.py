# -*- coding: utf-8 -*-
"""build_skill_ring_hi.py — 共享技能环 `_skill_ring` 的高分辨率档(2026-11-05)。

由来: 11-05 审核片逐段审, 大范围技能(竹刺阵 / 糖衣炮弹 / 墨水炸弹 / 碎晶爆破 / 财宝风暴 / 万千触须 / 火炮齐射)
脚下的环边缘一格一格的台阶 —— 环只有一张 64 像素的帧表(skill-ring-10f.png), 半径 300 码时 1 个贴图像素
≈ 10 个屏幕像素, 比场上其它像素画(龟立绘约 2~3 屏幕像素一格)粗三四倍。我 11-04 加的敌我描边用同一张图, 把台阶又描了一圈。
⇒ 同一套几何再烤两档: 128 / 256。运行时按半径挑最接近「一格 ≈ 2.5 屏幕像素」的那档(RealtimeBattle3DScene._ring_sheet_for)。

流水(与 64 档同一条, 只换输出边长):
  ① Blender 渲 10 帧(tools/assetgen/blender_ring.py, --px 1024, 俯视正交, 画布 -1..1)
  ② 本脚本: BOX 面积平均缩到格边长 → 锁 ring 板(4 档纯灰, tools/pixelize_sheet.py 的 quantize_to, alpha<24 切掉)
     → 淡出烤进帧 alpha(第 6~9 帧 200/150/95/45, 与 64 档逐字相同) → 横排 10 帧。
  ③ 自检: 用同一流水出 64 档, 与仓库里现有的 skill-ring-10f.png 逐帧比不透明像素数(证明流水复刻对了, 再信 128/256 两档)。
确定性: 同一组 Blender 帧重跑逐字节相同。

用法:
  blender --background --python tools/assetgen/blender_ring.py -- --out <目录> --frames 10 --px 1024
  python tools/assetgen/build_skill_ring_hi.py <目录>
"""
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from pixelize_sheet import PALETTES, quantize_to  # noqa: E402

FRAMES = 10
FRAME_A = [255, 255, 255, 255, 255, 255, 200, 150, 95, 45]   # 与 skill-ring-10f.png 逐帧实测一致


def build(src: str, cell: int) -> Image.Image:
	sheet = Image.new("RGBA", (cell * FRAMES, cell), (0, 0, 0, 0))
	for f in range(FRAMES):
		im = Image.open(os.path.join(src, "d0_f%d.png" % f)).convert("RGBA").resize((cell, cell), Image.BOX)
		q = quantize_to(im, PALETTES["ring"])
		px = q.load()
		for y in range(cell):
			for x in range(cell):
				r, g, b, a = px[x, y]
				if a:
					px[x, y] = (r, g, b, FRAME_A[f])
		sheet.paste(q, (f * cell, 0))
	return sheet


def opaque_counts(sheet: Image.Image, cell: int) -> list:
	out = []
	for f in range(FRAMES):
		c = sheet.crop((f * cell, 0, f * cell + cell, cell))
		out.append(sum(1 for p in c.getdata() if p[3] > 0))
	return out


def main() -> int:
	src = sys.argv[1]
	ref = Image.open(os.path.join(ROOT, "assets", "sprites", "vfx", "skill-ring-10f.png")).convert("RGBA")
	mine = build(src, 64)
	a, b = opaque_counts(ref, 64), opaque_counts(mine, 64)
	print("64 档自检 · 仓库现有:", a)
	print("64 档自检 · 本流水  :", b)
	worst = max(abs(x - y) / max(1, x) for x, y in zip(a, b))
	print("逐帧不透明像素数最大相对差 %.1f%%" % (worst * 100))
	if worst > 0.12:
		print("✗ 流水没复刻出现有 64 档(差 >12%), 不出高分辨率档")
		return 1
	for cell in (128, 256):
		out = os.path.join(ROOT, "assets", "sprites", "vfx", "skill-ring-10f-%d.png" % cell)
		build(src, cell).save(out, optimize=False)
		print("→", os.path.relpath(out, ROOT))
	return 0


if __name__ == "__main__":
	sys.exit(main())
