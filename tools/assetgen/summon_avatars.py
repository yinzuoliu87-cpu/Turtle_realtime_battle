# -*- coding: utf-8 -*-
"""summon_avatars.py —— 图鉴「角色」栏召唤物 / 战场单位的列表头像(方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md)。

做法(如实): 从单位现有的待机序列第 0 帧(或静态立绘)**裁一块方形特写**, 不重画。
  · 百夫长: 手定的 52×52 头部框(11-27 第一版)。
  · 其余: 按不透明像素包围盒自动取方框 —— 矮胖的(炸弹 / 虫 / 盒子 / 船)取整身, 高个人形(骷髅 / 忍者 / 武士 / 训龟大师)取上半身。
  · 原图边长 ≤ 128 的保持像素硬边(整数倍最近邻放大到 ≥ 52); 大图(PixelLab 原图 400~1024)先裁再缩到 128 (LANCZOS)。
与深海小将头像(avatars/minion*.png)同一种东西。重跑逐字节相同。
用法: python tools/assetgen/summon_avatars.py   (仓库根目录按往上三层算)
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S = "assets/sprites/"

## id → (源图, 帧宽(None = 整张), 取法 "full" 整身 / "upper" 上半身 / (l,t,r,b) 帧内手定框)
SRC = {
	"centurion": (S + "vfx/eq-centurion-idle.png", 192, (74, 64, 126, 116)),   # 头盔红缨 + 面甲 + 盾牌上沿, 52×52
	"egg": (S + "pets/egg.png", 79, "full"),
	"trainer": (S + "trainer/trainer-villager.png", None, "upper"),
	"candybomb": (S + "pets/candy-bomb.png", None, "full"),
	"crystalball": (S + "pets/crystal-ball.png", None, "full"),
	"ship": (S + "skills/pirate-ship.png", None, "full"),
	"mech": (S + "pets/mech.png", None, "upper"),
	"skeleton": (S + "pets/skeleton.png", None, "upper"),
	"worm": (S + "pets/conch-worm.png", None, "full"),
	"bear": (S + "vfx/bear-walk.png", 96, "upper"),
	"cakebox": (S + "vfx/eq072-cake-box.png", None, "full"),
	"pistol": (S + "vfx/eq-pistol-idle.png", 40, "full"),
	"medtower": (S + "vfx/eq-coraltower-idle.png", 64, "upper"),
	"axe": (S + "vfx/eq096-axe-wood-idle.png", 112, "full"),
	"cannon": (S + "vfx/eq-cannon-idle.png", 64, "full"),
	"remote_bomb": (S + "vfx/eq-remote-bomb-idle.png", 64, "full"),
	"katana": (S + "vfx/eq-katana-idle.png", 112, "upper"),
	"shadow_ninja": (S + "vfx/eq-ninja-idle.png", 112, "upper"),
	"skel_warrior": (S + "vfx/eq-skelw-idle.png", 112, "upper"),
	"skel_mage": (S + "vfx/eq-skelm-idle.png", 112, "upper"),
	"skel_priest": (S + "vfx/eq-skelp-idle.png", 112, "upper"),
	"mask_lion": (S + "vfx/eq-masklion-idle.png", 112, "upper"),
	"wraith": (S + "pets/wraith.png", None, "full"),
}


def _square(im, mode):
	bb = im.getbbox()
	if bb is None:
		return im
	l, t, r, b = bb
	w, h = r - l, b - t
	if mode == "upper" and h > w:
		side = max(w, int(h * 0.6))
		cx = (l + r) // 2
		box = (cx - side // 2, t, cx - side // 2 + side, t + side)
	else:
		side = max(w, h)
		cx, cy = (l + r) // 2, (t + b) // 2
		box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
	out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	out.alpha_composite(im.crop((max(0, box[0]), max(0, box[1]), min(im.width, box[2]), min(im.height, box[3]))),
		(max(0, -box[0]), max(0, -box[1])))
	return out


def main():
	for sid, (src, fw, mode) in SRC.items():
		im = Image.open(os.path.join(ROOT, src)).convert("RGBA")
		if fw:
			im = im.crop((0, 0, fw, min(im.height, fw if im.height >= fw else im.height)))
		if isinstance(mode, tuple):
			im = im.crop(mode)
		else:
			im = _square(im, mode)
			if im.width > 128:
				im = im.resize((128, 128), Image.LANCZOS)
			elif im.width < 52:
				k = -(-52 // im.width)
				im = im.resize((im.width * k, im.height * k), Image.NEAREST)
		## 半透明边收成硬边(图鉴头像同龟头像: 不留半透明像素; 缩过的大图和自带柔边的原图都要收)
		px = im.load()
		for y in range(im.height):
			for x in range(im.width):
				c = px[x, y]
				px[x, y] = (c[0], c[1], c[2], 255 if c[3] >= 128 else 0)
		out = os.path.join(ROOT, "assets", "sprites", "avatars", "summon-%s.png" % sid)
		im.save(out)
		print("ok", sid, im.size)


if __name__ == "__main__":
	main()
