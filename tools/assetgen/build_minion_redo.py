# -*- coding: utf-8 -*-
"""tools/assetgen/build_minion_redo.py — 远程小将(海螺炮手) / 精英小将(深渊精英) 2026-11-11 重做的帧条 / 立绘。

用户 11-11「远程小将、精英小将都应该按照这个标准，一帧帧看，重新来做」; 标准同近战(build_melee_minion.py 文件头):
  每帧两条腿 · 武器在同一只手 · 相邻格姿势看得出变化(停顿 = 同一张图重复, 不放几张几乎一样的 AI 图) · 不画进去的特效
  (炮口火光 / 烟圈 / 品红拖影 / 光柱 / 烟尘都删) · 空中帧脚对齐地面线(高度由代码抬)。
源帧: tools/assetgen/minion_seq/<ranged|elite>/<段>/f_NN.png(192 方帧, 脚底行 176); 处理记录 .out/ranged_redo / .out/elite_redo。
节拍(格 → 秒)按代码:
  远程 普攻 前摇 0.255 s(间隔 0.85 × 30%) ⇒ 命中格 5 → 19.6 帧/秒; 技能蓄力 = HidingSystem.ROCKET_CHARGE_SEC 1.5 s 15 格 10 帧/秒;
       开火后坐(新, 火箭射出那一刻播) 5 格 12 帧/秒
  精英 普攻 前摇 0.40 s(间隔 1.54 × 30% 夹到上限 0.40) ⇒ 命中格 5 → 12.5 帧/秒; 旋刃 0.42 s / 铁锤 0.43 s(砸地在最后一格) /
       大跳 1.47 s(0.35 起跳 + 1.0 空中 + 0.12 砸) / 吞噬 1.5 s / 铁锁 11 格按拉人时长传 fps(EliteSystem.whip_anim_fps)
本脚本只排格 + 烘刀光 + 裁立绘(无缩放、无重采样), 重跑逐字节相同。跑法: python tools/assetgen/build_minion_redo.py [--check]
"""
import glob
import io
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEQ = os.path.join(ROOT, "tools", "assetgen", "minion_seq")
PETS = os.path.join(ROOT, "assets", "sprites", "pets")
F = 192

CONF = {
	"ranged": {
		"portrait": "minion-back.png",
		"slots": {
			"idle": ("idle", [0, 1, 2, 3]),
			"run": ("run", [0, 1, 2, 3, 4, 5]),
			## 站 / 前压瞄准 ×4 / ★后坐(命中格 5) ×2 / 后坐收 ×2 / 回位 ×2 / 站 —— 命中前 5 格、后 7 格(11-08 规矩 ≥5 / ≥6)
			"attack": ("attack", [0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 0]),
			## 站 / 放炮 / 端炮 / 瞄准 + 呼吸 —— 15 格 = 1.5 s
			"skill": ("skill", [0, 1, 2, 3, 3, 4, 4, 3, 3, 4, 4, 3, 3, 4, 4]),
			## 火箭射出: 后坐 ×2 / 后坐收 ×2 / 回位
			"fire": ("attack", [2, 2, 3, 3, 4]),
		},
	},
	"elite": {
		"portrait": "minion-elite.png",
		"slots": {
			"idle": ("idle", [0, 1, 2, 3]),
			"run": ("run", [0, 1, 2, 3, 4, 5]),
			## 站 / 举过头 ×3 / 斜前上 / ★劈到前下(命中格 5) ×2 / 收 ×2 / 收 ×2 / 站 —— 命中前 5 格、后 7 格
			"attack": ("attack", [0, 1, 1, 1, 2, 3, 3, 4, 4, 5, 5, 0]),
			"whirl": ("whirl", [0, 1, 2, 3, 4, 5]),
			## 站 / 拳前抬 / 举过头 / 举到最高 ×2 / 砸地(最后一格 = 0.43 s 砸到)
			"hammer": ("hammer", [0, 1, 2, 3, 3, 4]),
			## 蹲 ×2 / 起跳 ×2 / 空中举双拳 ×10(两张交替) / 砸地
			"hammer_big": ("hammer_big", [0, 0, 1, 1, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 4]),
			## 后甩(手到地面带出链) / 后拉 / 甩出 ×3(链飞出、扎中、停顿) / 被拽前倾 / 拉平飞 ×4 / 落地砍
			"whip": ("whip", [0, 1, 2, 2, 2, 3, 4, 4, 4, 4, 5]),
			## 站 / 伸手 ×2 / 抓 ×2 / 拉回 ×2 / 弓身吸收 ×4 / 站直 ×3 / 站 —— 15 格 = 1.5 s
			"consume": ("consume", [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5, 5, 0]),
		},
		## 普攻刀光(紫): 刃尖沿以肩为心的圆弧走; 格 → (尾 = 哪张图的刃尖角度, 头 = 哪张图, 宽, 刃芯比例)
		"trail": {
			"pivot": (80.0, 115.0),
			## 刃尖(放大网格手量; 自动找会量到紫色面罩缝 / 头冠): 图 1 举过头 / 图 2 斜前上 / 图 3 劈到前下, 到 pivot 63~75 像素
			"tips": {1: (72.0, 41.0), 2: (24.0, 86.0), 3: (35.0, 175.0)},
			"slots": {4: (1, 2, 9, 0.35), 5: (1, 3, 13, 0.45), 6: (2, 3, 8, 0.0), 7: (2, 3, 4, 0.0)},
			"col": ((244, 226, 255, 255), (186, 104, 250, 255), (86, 36, 148, 255)),
		},
	},
}


def src(kind, seg):
	fs = sorted(glob.glob(os.path.join(SEQ, kind, seg, "f_*.png")))
	if not fs:
		raise SystemExit("缺源帧 %s/%s" % (kind, seg))
	return [Image.open(f).convert("RGBA") for f in fs]


def ang_r(p, c):
	dx, dy = p[0] - c[0], c[1] - p[1]
	return math.degrees(math.atan2(dy, dx)) % 360.0, math.hypot(dx, dy)


def trail_layer(kind, conf, imgs, slot):
	tc = conf.get("trail")
	if not tc or slot not in tc["slots"]:
		return None
	c = tc["pivot"]
	tips = tc["tips"]
	a_from, a_to, wmax, core = tc["slots"][slot]
	(a0, r0), (a1, r1) = ang_r(tips[a_from], c), ang_r(tips[a_to], c)
	## 朝前劈 = 角度从「头顶(~90°)」经「前方(~180°)」到「前下(~230°)」递增
	if a1 < a0:
		a1 += 360.0
	lay = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	d = ImageDraw.Draw(lay)
	n = 48

	def band(widthf):
		outer, inner = [], []
		for k in range(n + 1):
			s = k / n
			a = math.radians(a0 + (a1 - a0) * s)
			r = r0 + (r1 - r0) * s
			w = widthf(s)
			outer.append((c[0] + r * math.cos(a), c[1] - r * math.sin(a)))
			inner.append((c[0] + (r - w) * math.cos(a), c[1] - (r - w) * math.sin(a)))
		return outer + inner[::-1]

	def wf(s):
		return wmax * min(1.0, s / 0.88) if s < 0.88 else wmax * (1.0 - (s - 0.88) / 0.12 * 0.6)
	core_c, glow_c, edge_c = tc["col"]
	d.polygon(band(lambda s: wf(s) + 1.0), fill=edge_c)
	d.polygon(band(wf), fill=glow_c)
	if core > 0:
		d.polygon(band(lambda s: wf(s) * core if s > 0.3 else 0.0), fill=core_c)
	return lay


def strip(kind, conf, name):
	seg, slots = conf["slots"][name]
	imgs = src(kind, seg)
	out = Image.new("RGBA", (F * len(slots), F), (0, 0, 0, 0))
	for k, i in enumerate(slots):
		fr = imgs[i]
		if name == "attack":
			lay = trail_layer(kind, conf, imgs, k)
			if lay is not None:
				lay.alpha_composite(fr)
				fr = lay
		out.alpha_composite(fr, (k * F, 0))
	return out


def portrait(kind):
	im = src(kind, "idle")[0]
	bb = im.getbbox()
	c = im.crop((bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2))
	s = max(c.width, c.height)
	sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	sq.alpha_composite(c, ((s - c.width) // 2, s - c.height))
	return sq


def outputs():
	out = {}
	for kind, conf in CONF.items():
		d = os.path.join(PETS, "animations", kind)
		for name in conf["slots"]:
			out[os.path.join(d, name + ".png")] = strip(kind, conf, name)
		out[os.path.join(PETS, conf["portrait"])] = portrait(kind)
	return out


def png_bytes(im):
	b = io.BytesIO()
	im.save(b, format="PNG", optimize=False)
	return b.getvalue()


def main():
	sys.stdout.reconfigure(encoding="utf-8")
	check = "--check" in sys.argv
	bad = 0
	for p, im in outputs().items():
		data = png_bytes(im)
		if check:
			ok = os.path.exists(p) and open(p, "rb").read() == data
			bad += 0 if ok else 1
			print(("OK   " if ok else "DIFF ") + os.path.relpath(p, ROOT))
		else:
			os.makedirs(os.path.dirname(p), exist_ok=True)
			open(p, "wb").write(data)
			print("写出 %s  %dx%d" % (os.path.relpath(p, ROOT), im.width, im.height))
	if check:
		print("ALL OK" if bad == 0 else "有 %d 个文件与脚本输出不一致" % bad)
		return 1 if bad else 0
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
