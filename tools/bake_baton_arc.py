# -*- coding: utf-8 -*-
"""烘 027 电棍的两张电弧贴图 —— 它原来借的是 electric-zap.png(一张对称放射星爆)。

为什么要换(实测, 不是观感):
  · electric-zap.png 五帧里 frame4 均色 R18 G25 B34、近白像素 0 个 —— 在黑场里读成一团污渍;
    frame3 近白也只有 167 个。而 `_baton_spark` 用的是 `randi() % 5` ⇒ **40% 的就绪火花是黑的**。
  · 那张图的形状是【对称放射星爆】, 不是电弧。文案写的是「电棍 / 电击 / 眩晕」。
  · 它还被赛博侵入/雷电龟/026 共 5 处在用 ⇒ 不能改它(素材不复用铁律: 新内容出新素材)。

形状怎么来的: 电弧的真实形态是**中点位移折线 + 分叉**(不是规则图案) ——
  主干按 midpoint displacement 抖开, 每段有概率长出一条更短更暗的分叉。
调色板只有 4 色(像素风), 全部不透明或全透明, 不做羽化。
"""
import os, math, random
from PIL import Image

W = (255, 255, 255)      # 核心
L = (190, 236, 255)      # 亮
M = ( 95, 200, 255)      # 主
D = ( 16,  38,  92)      # 暗描边(围住整条弧 —— 不是"暗一点的蓝", 是**描边**)


def _midpoint(p0, p1, amp, depth, rnd):
	"""中点位移: 返回从 p0 到 p1 的抖动折线点列。"""
	if depth <= 0:
		return [p0, p1]
	mx = (p0[0] + p1[0]) * 0.5
	my = (p0[1] + p1[1]) * 0.5
	dx, dy = p1[0] - p0[0], p1[1] - p0[1]
	ln = math.hypot(dx, dy) or 1.0
	nx, ny = -dy / ln, dx / ln
	off = rnd.uniform(-amp, amp)
	mid = (mx + nx * off, my + ny * off)
	a = _midpoint(p0, mid, amp * 0.55, depth - 1, rnd)
	b = _midpoint(mid, p1, amp * 0.55, depth - 1, rnd)
	return a[:-1] + b


def _cells(size, pts):
	"""折线经过的像素格(Bresenham), 不做抗锯齿。"""
	out = []
	for i in range(len(pts) - 1):
		x0, y0 = int(round(pts[i][0])), int(round(pts[i][1]))
		x1, y1 = int(round(pts[i + 1][0])), int(round(pts[i + 1][1]))
		dx, dy = abs(x1 - x0), -abs(y1 - y0)
		sx = 1 if x0 < x1 else -1
		sy = 1 if y0 < y1 else -1
		err = dx + dy
		while True:
			if 0 <= x0 < size and 0 <= y0 < size:
				out.append((x0, y0))
			if x0 == x1 and y0 == y1:
				break
			e2 = 2 * err
			if e2 >= dy:
				err += dy; x0 += sx
			if e2 <= dx:
				err += dx; y0 += sy
	return out


## ★晕圈要【围住】芯而不是压住芯: 第一版 w=2 只往 +x/+y 方向铺,
##   于是暗色留在了折线【中间】、亮色被挤到边上 —— 渲出来是暗芯亮边, 和真实电弧反着。
##   现在改成「先把折线八向膨胀成暗晕, 再把芯画回去」, 顺序保证芯永远在最上面。
def _plot(px, size, pts, col, halo=0):
	cs = _cells(size, pts)
	if halo > 0:
		for (x, y) in cs:
			for ox in range(-halo, halo + 1):
				for oy in range(-halo, halo + 1):
					nx, ny = x + ox, y + oy
					if 0 <= nx < size and 0 <= ny < size:
						px[nx, ny] = col + (255,)
	else:
		for (x, y) in cs:
			px[x, y] = col + (255,)


def _bolt(px, size, p0, p1, rnd, amp, depth, core=True, forks=2, fork_scale=0.45):
	pts = _midpoint(p0, p1, amp, depth, rnd)
	## ★★配色三版才对, 记下来省得再绕:
	##   v1 暗色只往 +x/+y 铺 ⇒ 暗留在折线中间、亮被挤到边上, 和真电弧反着。
	##   v2 改成【中蓝】八向膨胀当辉光 ⇒ 3px 的中蓝把 1px 的芯压死, 渲成一条蓝虫;
	##      更要命的是**载体小龟本身就是亮青色(0,240,207)**, 亮蓝弧贴在亮青身上等于没画
	##      (实测 3.50s 那帧电弧均色 R87 G167 B178, 和龟皮几乎同一族)。
	##   v3(现在) 用【深蓝描边 + 亮芯】: 描边把弧从任何底色上切出来, 芯保持最亮。
	##      这就是像素画的通用解, 也是我自己从 948 张 mod 图标里量出来的那条(描边闭合度)。
	_plot(px, size, pts, D, halo=1)     # 描边: 深蓝, 八向膨胀 1 格, 围住整条弧
	_plot(px, size, pts, L)             # 芯外圈
	if core:
		# 最亮只点在折线的中段, 让亮度沿弧变化(不是整条一样白)
		mids = pts[len(pts) // 4: len(pts) * 3 // 4]
		_plot(px, size, mids, W)
	for _ in range(forks):
		k = rnd.randrange(1, max(2, len(pts) - 1))
		a = pts[k]
		ang = rnd.uniform(0, math.tau)
		ln = size * fork_scale * rnd.uniform(0.5, 1.0)
		b = (a[0] + math.cos(ang) * ln, a[1] + math.sin(ang) * ln)
		fp = _midpoint(a, b, amp * 0.7, depth - 1, rnd)
		## 分叉是次级弧: 描边 + 中蓝芯(比主干暗一档) —— 否则分叉和主干一样重, 主次全平
		_plot(px, size, fp, D, halo=1)
		_plot(px, size, fp, M)


def bake_arc(path, size=24, frames=8, seed=20270913):
	"""就绪态: 棍身上噼啪跳的短弧。每帧 2~3 条互不相同的短弧。"""
	rnd = random.Random(seed)
	sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
	for f in range(frames):
		im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
		px = im.load()
		## ★密度: 第一版每帧 2~3 条、每条长到 0.8 个格子, 加上辉光后占满 30% 的格 ——
		##   渲出来是【一团蓝疙瘩】而不是【几道跳弧】。就绪态本来就该稀, 改成 1~2 条短弧。
		n = 1 + (f % 2)
		for _ in range(n):
			ang = rnd.uniform(0, math.tau)
			ln = size * rnd.uniform(0.34, 0.56)
			cx = size * 0.5 + rnd.uniform(-size * 0.2, size * 0.2)
			cy = size * 0.5 + rnd.uniform(-size * 0.2, size * 0.2)
			p0 = (cx - math.cos(ang) * ln * 0.5, cy - math.sin(ang) * ln * 0.5)
			p1 = (cx + math.cos(ang) * ln * 0.5, cy + math.sin(ang) * ln * 0.5)
			_bolt(px, size, p0, p1, rnd, amp=size * 0.13, depth=3, forks=1, fork_scale=0.22)
		sheet.paste(im, (f * size, 0))
	sheet.save(path)
	return sheet


def bake_strike(path, size=56, frames=8, seed=1027):
	"""命中态: 一道从上方劈下来的分叉主弧 + 触地炸开的支弧。
	   八帧是【一次放电的过程】: 0-1 起弧 / 2-4 最盛 / 5-7 余辉衰减(不是八个随机样子)。

	   ★格子边长定成 56: 游戏里按【整数倍】缩放(像素风硬约束), 1 texel = 0.0426 m
	     ⇒ 56 texel = 2.39 m ≈ 1.2 个龟高。40 的话只有 0.85 龟高, 劈不过它的身子。"""
	rnd = random.Random(seed)
	sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
	growth = [0.45, 0.75, 1.0, 1.0, 0.95, 0.7, 0.45, 0.22]
	for f in range(frames):
		im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
		px = im.load()
		g = growth[f]
		hit = (size * 0.5, size * 0.62)
		top = (size * 0.5 + rnd.uniform(-size * 0.18, size * 0.18), size * 0.5 - size * 0.5 * g - size * 0.02)
		_bolt(px, size, top, hit, rnd, amp=size * 0.14 * g, depth=4,
			core=(g > 0.5), forks=int(3 * g), fork_scale=0.30 * g)
		# 触地支弧: 从命中点朝外炸开几道, 随 g 变长
		for k in range(int(5 * g)):
			ang = math.pi * (0.1 + 0.8 * (k + rnd.random()) / max(1, int(5 * g)))
			ln = size * 0.34 * g * rnd.uniform(0.5, 1.0)
			b = (hit[0] + math.cos(ang) * ln, hit[1] + math.sin(ang) * ln * 0.55)
			fp = _midpoint(hit, b, size * 0.07 * g, 3, rnd)
			_plot(px, size, fp, D)
			_plot(px, size, fp, M)
		sheet.paste(im, (f * size, 0))
	sheet.save(path)
	return sheet


def bake_shock(path, size=24, frames=6, seed=27027):
	"""027 眩晕期间【挂在被电中的目标身上】的持续电击。

	★用户 2026-09-13:「027 在命中敌人的时候会有一段时间眩晕对吧, 这一段时间内我希望
	  持续目标的电击特效, 直到这个电击眩晕结束」。
	★与 `baton-arc`(携带者就绪时棍身上跳的弧)**刻意做成两个样子**:
	  就绪是「零星几道短弧」, 中电是「顺着身体上下窜的两三道长弧 + 溅出的火星」——
	  一眼要能分出「他蓄好了」和「它被电住了」。
	★循环播放, 所以首尾要接得上: 弧的位置固定在三条竖轨上, 只有长短与亮暗在变。
	"""
	rnd = random.Random(seed)
	rails = [0.28, 0.52, 0.76]                  # 三条竖轨(身体左/中/右)
	sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
	for f in range(frames):
		im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
		px = im.load()
		for i, rx in enumerate(rails):
			phase = ((f + i * 2) % frames) / float(frames)
			## ★第一版 half 只有 0.20~0.36 个格 ⇒ 弧长 10~17px 而描边就占 3px 宽,
			##   渲出来是几坨深蓝疙瘩。弧要**更长更细**才读得成"电流顺着身体窜"。
			half = size * (0.30 + 0.12 * math.sin(phase * math.tau))
			cy = size * (0.46 + 0.08 * math.cos(phase * math.tau))
			p0 = (size * rx, cy - half)
			p1 = (size * rx + rnd.uniform(-2.0, 2.0), cy + half)
			_bolt(px, size, p0, p1, rnd, amp=size * 0.09, depth=3,
				core=True, forks=(1 if phase < 0.5 else 0), fork_scale=0.20)
		sheet.paste(im, (f * size, 0))
	sheet.save(path)


if __name__ == "__main__":
	root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	a = os.path.join(root, "assets", "sprites", "vfx", "baton-arc.png")
	b = os.path.join(root, "assets", "sprites", "vfx", "baton-strike.png")
	c = os.path.join(root, "assets", "sprites", "vfx", "baton-shock.png")
	bake_arc(a); bake_strike(b); bake_shock(c)
	print("baked:", a)
	print("baked:", b)
	print("baked:", c)
