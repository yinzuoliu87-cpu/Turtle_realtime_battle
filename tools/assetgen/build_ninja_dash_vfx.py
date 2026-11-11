# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_dash_vfx.py — 忍者龟被动「冲击」(自动冲刺斩)的专属特效(2026-11-11)。

用户 11-11:「关于忍者龟被动，就是这个冲击，它的这个命中特效，你看看」「你想办法先改喽」;
  此前定的规矩:「之后其实就不要有这种什么通用命中特效，之后每个角色将有自己的…普攻和技能命中特效」「肯定参考别人的呀」。
原来(实录逐帧): 冲刺前一排青色虚线方块 / 滑行一道糊的白蓝光条(LINEAR 软边, 一端一刀切) / 命中一个深蓝大月牙 + 通用火花方块 /
  落地又一个蓝月牙盖在忍者自己身上 0.6 秒。
参考(外部商业游戏, 逐帧研究 docs/studies/20261111c-忍者普攻挥刀参考-KatanaZERO逐帧.md 帧 0~17 + 本次「冲刺命中」一节):
  Katana ZERO 冲刺斩 —— 冲刺时身后一团扬尘 / 速度感; 斩中时一条细长亮线穿过敌人横到画面另一侧, 出现即全长,
  最亮停 2 帧, 再从远端变短变暗, 约 100 毫秒收完; 刀光与亮线都是硬边像素、没有柔光。
三张图(都画「朝右冲」, 游戏里按冲刺方向在屏幕上转角度 / 朝左时镜像; 颜色接普攻刀光: 白芯 / 浅金 / 金边; 实心无半透明):
  ninja-dash-trail.png  64×10 单张: 滑行拖影(右端 = 忍者那头粗, 往左变细、尾巴断成几截; 上下各一条短速度线), 游戏里横向拉到拖影长度
  ninja-dash-hit.png    6 格 144×32: 命中亮线(穿过目标中心, 沿冲刺方向), 每格 1/30 秒共 0.2 秒
  ninja-dash-dust.png   5 格 48×24: 落地脚下扬尘(取代原来盖在自己身上的大月牙), 每格 1/25 秒
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_ninja_dash_vfx.py [--check]
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
C_CORE = (255, 255, 255)
C_MID = (255, 236, 168)
C_RIM = (236, 178, 84)
C_DEEP = (198, 132, 52)
D_LIGHT = (236, 228, 212)
D_MID = (204, 192, 170)
D_DARK = (150, 138, 118)


def put(px, w, h, x, y, c):
	if 0 <= x < w and 0 <= y < h:
		px[x, y] = c + (255,)


## ── 滑行拖影 ──
TW, TH = 64, 10


def trail():
	im = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
	px = im.load()
	cy = TH // 2
	for x in range(TW):
		k = x / (TW - 1)                     # 0 = 尾(左) .. 1 = 头(右, 忍者那头)
		if x < 22 and (x // 3) % 3 == 2:     # 尾巴断成几截
			continue
		half = 0.5 + 2.6 * k                 # 头粗尾细
		for y in range(TH):
			d = abs(y + 0.5 - cy)
			if d > half:
				continue
			r = d / max(0.001, half)
			c = C_CORE if (r < 0.35 and k > 0.35) else (C_MID if r < 0.75 else C_RIM)
			put(px, TW, TH, x, y, c)
	## 上下两条短速度线(1 像素, 金)
	for x in range(26, 52):
		if (x // 4) % 4 != 3:
			put(px, TW, TH, x, 1, C_RIM)
	for x in range(18, 44):
		if (x // 5) % 4 != 1:
			put(px, TW, TH, x, TH - 2, C_RIM)
	return im


## ── 命中亮线 ──
HW, HH = 144, 48
HCX, HCY = 72.0, 24.0                       # 目标中心(胸口)
HALF = 60.0                                 # 亮线半长(像素): 全长 120 ≈ 3.75 米, 伸出目标两边
## 每格: (从哪到哪(沿冲刺方向, -1 = 冲刺来的那头(左), 1 = 前方(右)), 半宽像素)
STREAK = [(-1.0, 1.0, 0.9), (-1.0, 1.0, 1.7), (-1.0, 1.0, 1.4), (-0.35, 1.0, 1.0), (0.2, 1.0, 0.7), (0.6, 1.0, 0.5)]
## 命中点爆点(四尖星闪, 半径像素): 用户 11-11「中间这个爆点更大一点就好了」—— 原来 7 / 10 / 6, 放大到 12 / 18 / 12 / 6;
##   白芯 + 浅金一圈, 十字四芒根部宽 4~5 像素往外收尖, 斜向四芒(0.6r)
STAR = [12, 20, 13, 6, 0, 0]
## 碎光: (沿方向速度, 竖直速度, 下落加速度, 大小)
SHARDS = [(8.0, -3.0, 0.9, 2), (11.0, 1.0, 0.8, 2), (6.0, -5.0, 1.1, 1), (9.0, 4.0, 1.0, 1), (4.0, 2.0, 1.2, 2)]


def star(px, r):
	"""爆点: 白芯圆(0.22r) + 浅金一圈(0.34r) + 十字四芒(根部半宽 2.4 往外收尖) + 斜向四芒(长 0.6r, 根部半宽 1.3)。实心无半透明。"""
	for y in range(HH):
		for x in range(HW):
			dx = x + 0.5 - HCX
			dy = y + 0.5 - HCY
			dist = (dx * dx + dy * dy) ** 0.5
			best = None
			for (along, side) in ((abs(dx), abs(dy)), (abs(dy), abs(dx))):
				if along <= r:
					t = 1.0 - along / r
					w = 0.35 + 2.4 * t ** 1.3
					if side <= w:
						lvl = 0 if (side <= w * 0.5 and t > 0.25) else (1 if t > 0.1 else 2)
						best = lvl if best is None else min(best, lvl)
			ra = r * 0.6
			u = (dx + dy) * 0.7071
			v = (dx - dy) * 0.7071
			for (along, side) in ((abs(u), abs(v)), (abs(v), abs(u))):
				if along <= ra:
					t = 1.0 - along / ra
					w = 0.3 + 1.3 * t
					if side <= w:
						lvl = 1 if t > 0.35 else 2
						best = lvl if best is None else min(best, lvl)
			if dist <= max(1.5, r * 0.22):
				best = 0
			elif dist <= max(2.0, r * 0.34):
				best = 1 if best is None else min(best, 1)
			if best is not None:
				put(px, HW, HH, x, y, (C_CORE, C_MID, C_RIM)[best])


def hit_frame(i):
	im = Image.new("RGBA", (HW, HH), (0, 0, 0, 0))
	px = im.load()
	a0, a1, hw = STREAK[i]
	for y in range(HH):
		for x in range(HW):
			along = (x + 0.5 - HCX) / HALF
			if along < a0 or along > a1:
				continue
			## 两端收尖: 离端点越近越细
			taper = min(1.0, (along - a0) / 0.25, (a1 - along) / 0.12)
			w = hw * max(0.35, taper)
			d = abs(y + 0.5 - HCY)
			if d > w + 0.5:
				continue
			if d <= w * 0.45 + 0.25:
				c = C_CORE
			elif d <= w:
				c = C_MID
			else:
				c = C_RIM
			put(px, HW, HH, x, y, c)
	r = STAR[i]
	if r > 0:
		star(px, r)
	if i >= 1:
		f = float(i - 1)
		for (vx, vy, g, sz) in SHARDS:
			x = int(round(HCX + 4.0 + vx * f))
			y = int(round(HCY + vy * f + 0.5 * g * f * f))
			if i >= 5 and sz == 1:
				continue
			c = C_CORE if i <= 2 else (C_MID if i <= 3 else C_RIM)
			for dy in range(sz):
				for dx in range(sz):
					put(px, HW, HH, x + dx, y + dy, c)
	return im


## ── 落地扬尘 ──
DW, DH = 48, 24
## 每团: (起点 x, 往外的速度, 往上的速度, 起始半宽, 每格变大) —— 扁椭圆(宽 : 高 = 1 : 0.55), 边缘按固定噪声表缺口, 贴地往两边散
PUFFS = [(17.0, -3.0, -0.5, 3.0, 1.3), (31.0, 3.0, -0.5, 3.0, 1.3), (24.0, 0.0, -0.9, 3.4, 1.1), (11.0, -4.5, -0.2, 2.0, 0.8), (37.0, 4.5, -0.2, 2.0, 0.8)]
DUST_FRAMES = 5
NOISE = [0.0, 0.8, 0.3, 1.0, 0.1, 0.6, 0.9, 0.2, 0.7, 0.4, 0.5, 0.05, 0.85, 0.35, 0.65, 0.15]


def dust_frame(i):
	im = Image.new("RGBA", (DW, DH), (0, 0, 0, 0))
	px = im.load()
	ground = DH - 2
	for k, (x0, vx, vy, r0, gr) in enumerate(PUFFS):
		cx = x0 + vx * i
		rx = r0 + gr * i
		ry = rx * 0.55
		cy = ground - ry + vy * i
		keep = 1.0 - 0.18 * max(0, i - 2)          # 后两格变稀
		for y in range(DH):
			for x in range(DW):
				ex = (x + 0.5 - cx) / rx
				ey = (y + 0.5 - cy) / ry
				d = math.hypot(ex, ey)
				nz = NOISE[(x * 7 + y * 3 + k * 5) % len(NOISE)]
				if d > 1.0 - 0.25 * nz or y > ground:
					continue
				if nz > keep:                          # 散开: 按噪声挖掉一部分
					continue
				c = D_LIGHT if (ey < -0.15 and d < 0.7) else (D_MID if d < 0.85 else D_DARK)
				put(px, DW, DH, x, y, c)
	return im


def sheet(frames, fw, fh):
	out = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
	for k, f in enumerate(frames):
		out.paste(f, (k * fw, 0))
	return out


def build():
	return {
		"ninja-dash-trail.png": trail(),
		"ninja-dash-hit.png": sheet([hit_frame(i) for i in range(len(STREAK))], HW, HH),
		"ninja-dash-dust.png": sheet([dust_frame(i) for i in range(DUST_FRAMES)], DW, DH),
	}


def main():
	out = build()
	if "--check" in sys.argv:
		bad = []
		for n, im in out.items():
			p = os.path.join(VFX, n)
			cur = Image.open(p).convert("RGBA") if os.path.exists(p) else None
			if cur is None or cur.size != im.size or cur.tobytes() != im.tobytes():
				bad.append(n)
		print("ALL OK" if not bad else "不一致: 重跑 build_ninja_dash_vfx.py " + " ".join(bad))
		sys.exit(0 if not bad else 1)
	for n, im in out.items():
		im.save(os.path.join(VFX, n), optimize=False)
		print("写好", n, im.size)


if __name__ == "__main__":
	main()
