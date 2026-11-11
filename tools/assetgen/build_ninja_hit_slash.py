# -*- coding: utf-8 -*-
"""tools/assetgen/build_ninja_hit_slash.py — 忍者龟普攻命中刀痕(2026-11-11)。

用户 11-11:「蒲公英(普攻)这种特效呢？攻击的命中特效。」「之后其实就不要有这种什么通用命中特效，之后每个角色将有自己的…
  普攻和技能命中特效」「肯定参考别人的呀」。忍者普攻打中时原来只有通用的目标闪白 + 小火星。
参考(外部商业游戏, 逐帧研究 docs/studies/20261111b-忍者普攻命中刀痕逐帧.md):
  LoL「Battle Boss 亚索」普攻命中(像素主题皮肤, 60 帧逐帧)+ Katana ZERO 刀斩命中。共同点三条:
  ① 一条又细又亮的直线斜穿目标、伸出目标很远, 出现那一帧就是全长, 之后从起手那端缩短变暗(亚索亮线 6 帧 ≈ 100 毫秒);
  ② 命中点一个尖锐闪光, 1 ~ 2 帧;
  ③ 方形 / 菱形像素碎片沿刀的方向迸出、有的往下落, 约 300 毫秒散完。
落到忍者: 方向 = 新普攻刀路在目标处的走向(build_ninja_slash.py: 从头顶劈到正前方再往前下 ⇒ 在目标身上右上 → 左下, 约 35°);
  颜色 = 刀身白 + 刀光浅金(接命中后原有的金色斩击); 画的是「出手方朝左」, 朝右时游戏里 flip_h。
6 格 96×64, 每格 1/30 秒(共 0.2 秒), 游戏里固定像素尺寸逐格切(不连续缩放, vfx_discipline A); 实心无半透明。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_ninja_hit_slash.py [--check]
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "sprites", "vfx", "ninja-hit-slash.png")
FW, FH = 96, 64
CX, CY = 48.0, 30.0                       # 命中点(目标胸口)在帧里的位置
ANG = math.radians(35.0)                  # 刀痕走向: 右上 → 左下, 低于水平 35°
DX, DY = -math.cos(ANG), math.sin(ANG)   # 单位方向(往左下)
HALF = 42.0                               # 刀痕半长(像素): 全长 84 ≈ 2.6 米, 伸出目标两边
C_CORE = (255, 255, 255)
C_MID = (255, 236, 168)
C_RIM = (236, 178, 84)
C_DEEP = (198, 132, 52)
## 每格刀痕: (从哪(沿走向, -1 = 起手端右上, 1 = 收尾端左下)到哪, 半宽像素, 颜色层数)
STREAK = [(-1.0, 1.0, 1.6, 3), (-0.8, 1.0, 1.3, 3), (-0.35, 1.0, 1.0, 2), (0.15, 1.0, 0.7, 1), None, None]
## 命中点星闪: (半径像素) —— 前两格
STAR = [14, 9, 0, 0, 0, 0]
## 碎片: (沿走向的速度, 垂直走向的速度, 下落加速度, 大小) —— 每格位置 = 起点 + 速度 × 格 + 0.5 × 加速度 × 格²
SHARDS = [(9.0, -3.0, 1.0, 2), (7.0, 4.0, 1.2, 2), (11.0, 1.0, 0.8, 2), (5.0, -6.0, 1.4, 1), (6.0, 7.0, 1.0, 1),
	(-4.0, -5.0, 1.2, 1), (3.0, 9.0, 1.6, 2)]


def put(px, x, y, c):
	if 0 <= x < FW and 0 <= y < FH:
		px[x, y] = c + (255,)


def frame(i):
	im = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
	px = im.load()
	s = STREAK[i]
	if s is not None:
		a0, a1, hw, layers = s
		nx, ny = -DY, DX                                     # 法向
		for y in range(FH):
			for x in range(FW):
				vx, vy = x + 0.5 - CX, y + 0.5 - CY
				along = (vx * DX + vy * DY) / HALF          # -1 .. 1
				if along < a0 or along > a1:
					continue
				## 两头尖: 越靠近端点越细
				taper = min(1.0, (along - a0) / 0.25, (a1 - along) / 0.15) if a1 - a0 > 0.4 else 1.0
				w = hw * max(0.35, taper)
				d = abs(vx * nx + vy * ny)
				if d > w + 0.5:
					continue
				if d <= w * 0.45:
					c = C_CORE if layers >= 2 else C_MID
				elif d <= w * 0.9:
					c = C_MID if layers >= 2 else C_RIM
				else:
					c = C_RIM if layers >= 3 else C_DEEP
				put(px, x, y, c)
	r = STAR[i]
	if r > 0:
		## 四角星(内凹四边, |u|^0.62 + |v|^0.62 ≤ 1): 两条轴 = 刀痕走向与它的垂直; 中心白、外圈金
		for y in range(FH):
			for x in range(FW):
				vx, vy = x + 0.5 - CX, y + 0.5 - CY
				u = abs(vx * DX + vy * DY) / r
				v = abs(vx * (-DY) + vy * DX) / (r * 0.75)
				k = u ** 0.62 + v ** 0.62
				if k <= 1.0:
					put(px, x, y, C_CORE if k <= 0.62 else C_MID)
	if 1 <= i <= 5:
		f = float(i)
		for (va, vp, g, sz) in SHARDS:
			x = CX + DX * va * f + (-DY) * vp * f
			y = CY + DY * va * f + DX * vp * f + 0.5 * g * f * f
			size = sz if i <= 3 else 1
			col = C_CORE if i <= 2 else (C_MID if i <= 4 else C_RIM)
			for oy in range(size):
				for ox in range(size):
					put(px, int(math.floor(x)) + ox, int(math.floor(y)) + oy, col)
	return im


def build():
	sheet = Image.new("RGBA", (FW * len(STREAK), FH), (0, 0, 0, 0))
	for i in range(len(STREAK)):
		sheet.paste(frame(i), (i * FW, 0))
	return sheet


def main():
	sheet = build()
	if "--check" in sys.argv:
		cur = Image.open(OUT).convert("RGBA")
		same = cur.size == sheet.size and cur.tobytes() == sheet.tobytes()
		print("ALL OK" if same else "不一致: 重跑 build_ninja_hit_slash.py")
		sys.exit(0 if same else 1)
	sheet.save(OUT, optimize=False)
	print("写好", OUT, sheet.size)


if __name__ == "__main__":
	main()
