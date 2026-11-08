# -*- coding: utf-8 -*-
"""tools/assetgen/build_avatar_heads.py — 28 只龟的头像统一裁成头部特写(2026-11-08)。

用户 11-08:「你知道什么叫头像吗？就是他头肯定是要在…表现他这个头部的这个形象啊」「龟壳的话，你就截取左边那个眼睛部分就可以了」。
原来后做的 14 只头像只裁透明边 ⇒ 半身像, 头只占画面上面一小块; 游戏各处都把整张头像塞进框里, 所以改图本身就够了。

输入: tools/assetgen/avatar_heads.json —— 每只龟 {"src": 源图(仓库相对路径), "k": 源图的像素倍率, "box": [x, y, 边长]}。
  · box 以【原始像素】计(源图先按 k 整数倍缩回原始像素), 正方形; 超出源图的部分透明。
  · 源图: 后做 14 只 = tools/assetgen/pet_seq/<龟>/avatar.png(PixelLab 128×128);
          外包 11 只 = tools/assetgen/avatar_src/<龟>.png(build_spine_avatars.py 的输出);
          幽灵 / 忍者 / 变脸 = tools/assetgen/avatar_src/<龟>.png(原头像, 没有生成脚本)。
  · 构图规矩: 整颗头(含帽子、头饰)加一点脖子; 头高约占边长的七到八成; 龟壳取左下伸出来的那块(有一只眼睛)。
输出: assets/sprites/avatars/<龟>.png —— 透明度二值(像素画零半透明), 按整数倍最近邻放大到边长约 240。确定性: 重跑逐字节相同。
用法: python tools/assetgen/build_avatar_heads.py [龟id ...]      (不给 ⇒ 全部)
仓库根目录 = 本文件往上三层。
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TABLE = os.path.join(HERE, "avatar_heads.json")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "avatars")
TARGET = 240          # 输出边长目标(像素); 实际 = 边长 × 整数倍


def _binarize(im: Image.Image) -> Image.Image:
	"""二值透明, 透明处清零(与 build_turtle_seq._clean 同一个规矩)"""
	im = im.convert("RGBA")
	px = im.load()
	for y in range(im.height):
		for x in range(im.width):
			r, g, b, a = px[x, y]
			px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
	return im


def _native(im: Image.Image, k: int) -> Image.Image:
	"""按 k 缩回原始像素。★先核对每个 k×k 块是同一色, 不是就报错(倍率登记错了, 不猜)"""
	if k <= 1:
		return im
	if im.width % k or im.height % k:
		raise SystemExit("源图 %d×%d 不是 %d 的整数倍" % (im.width, im.height, k))
	px = im.load()
	for y in range(0, im.height, k):
		for x in range(0, im.width, k):
			c = px[x, y]
			if px[x + k - 1, y] != c or px[x, y + k - 1] != c or px[x + k - 1, y + k - 1] != c:
				raise SystemExit("源图在 (%d,%d) 不是 %d 倍的像素块" % (x, y, k))
	return im.resize((im.width // k, im.height // k), Image.NEAREST)


def build_one(tid: str, table: dict = None) -> Image.Image:
	"""生成一只并写盘; 返回输出图。build_turtle_seq / build_spine_avatars 也调它。"""
	t = (table or json.load(open(TABLE, encoding="utf-8")))[tid]
	src = _native(_binarize(Image.open(os.path.join(ROOT, t["src"]))), int(t.get("k", 1)))
	x, y, s = (int(v) for v in t["box"])
	canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	canvas.alpha_composite(src.crop((x, y, x + s, y + s)))      # 超出源图的部分 crop 自动补透明
	n = max(1, round(TARGET / s))
	out = canvas.resize((s * n, s * n), Image.NEAREST)
	os.makedirs(OUT_DIR, exist_ok=True)
	out.save(os.path.join(OUT_DIR, "%s.png" % tid), optimize=False)
	return out


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	table = json.load(open(TABLE, encoding="utf-8"))
	ids = sys.argv[1:] or sorted(table)
	for tid in ids:
		out = build_one(tid, table)
		print("%-10s 框 %s → %d×%d" % (tid, table[tid]["box"], out.width, out.height))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
