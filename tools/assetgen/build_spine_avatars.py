# -*- coding: utf-8 -*-
"""tools/assetgen/build_spine_avatars.py — 外包 11 只龟的头像, 从画师 Spine 原画裁出来(2026-11-05)。

方案书 docs/plans/20261105b-龟美术统一与动作补全.md(用户 11-05「待机的时候只能用这一十一只这个原画，包括头像啥的，可能都需要再重做一下」)。
构图照现有头像(assets/sprites/avatars/*.png): 头部特写 + 一点肩背, 透明底, 龟朝左。
头部在哪 —— 不靠手估: 插槽的加权网格大半权重落在 head 骨子树上(或插槽骨就在子树上)= 头部插槽(头 / 眨眼 / 天使光环 / 凤凰头焰 / 墨镜 / 冰龟头饰);
  只画这些插槽渲第 0 帧, 不透明像素框 = 头部框。
  (先试过「把 head 骨挪走、比两帧差异」: 身体是一整张加权网格, 头一挪整张被拉伸, 差异框把大半个身子都框进来, 弃用。)
裁切框: 脸(head 插槽)框往右(身体那侧)放宽 RIGHT 倍、往下放宽 DOWN 倍(带出脖子与一点壳), 再与头部框(含饰物)取并, 再收紧到实际不透明像素; 龟壳(没有头骨)用整只。
像素: 透明度二值(与待机序列帧同一个规矩), 整数倍 SCALE 最近邻放大(头像框常比原尺寸大, 先放大免得引擎线性过滤糊掉)。
输出: tools/assetgen/avatar_src/<龟id>.png(源图), 再经 build_avatar_heads.py 按 avatar_heads.json 裁成头部特写
  写到 assets/sprites/avatars/<龟id>.png(2026-11-08 用户「头像…表现他这个头部」)。确定性: 重跑逐字节相同。仓库根目录 = 本文件往上三层。
用法: python tools/assetgen/build_spine_avatars.py [--preview 输出.png]
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import spine_eval as S  # noqa: E402
import build_spine_idle as I  # noqa: E402

OUT_DIR = os.path.join(ROOT, "tools", "assetgen", "avatar_src")
import build_avatar_heads as AvatarHeads  # noqa: E402
HEAD_W = 0.5           # 头部插槽的权重门槛(见 head_slots)
RIGHT = 0.55           # 头部框往身体那侧多带出的宽度(× 头宽)
DOWN = 0.30            # 往下多带出的高度(× 头高)
PAD = 1                # 四周留的透明像素(原尺寸)
SCALE = 3


def _binarize(pm: np.ndarray) -> np.ndarray:
	a = pm[..., 3:4]
	rgb = np.where(a > 1e-6, pm[..., :3] / np.maximum(a, 1e-6), 0.0)
	opaque = a[..., 0] >= 0.5
	img = np.zeros(pm.shape[:2] + (4,), dtype=np.uint8)
	img[..., :3] = (np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)
	img[..., 3] = np.where(opaque, 255, 0).astype(np.uint8)
	img[~opaque, :3] = 0
	return img


def _bbox(mask: np.ndarray) -> tuple:
	ys = np.where(mask.any(axis=1))[0]
	xs = np.where(mask.any(axis=0))[0]
	return int(xs[0]), int(ys[0]), int(xs[-1]) + 1, int(ys[-1]) + 1


def head_slots(sk) -> set:
	"""头部插槽: 插槽骨在 head 骨子树上, 或插槽里的加权网格有 ≥ HEAD_W 的权重落在 head 骨子树上。
	探针实测(11-05): 头 / 眨眼 / 光环 / 头焰 / 墨镜 / 冰龟头饰 0.93–1.0, 身体(tummy) 0.21–0.36 —— 分得很开。"""
	par = {b["name"]: b.get("parent") for b in sk.bones}
	names = [b["name"] for b in sk.bones]

	def under_head(n):
		while n:
			if n == "head":
				return True
			n = par.get(n)
		return False
	out = set()
	for s in sk.slots:
		if under_head(s["bone"]):
			out.add(s["name"])
			continue
		for a in sk.skin.get(s["name"], {}).values():
			if a.get("type") != "mesh" or len(a["vertices"]) == len(a["uvs"]):
				continue
			v = a["vertices"]
			i = 0
			tot = hw = 0.0
			while i < len(v):
				n = int(v[i])
				i += 1
				for _ in range(n):
					w = float(v[i + 3])
					tot += w
					if under_head(names[int(v[i])]):
						hw += w
					i += 4
			if tot > 0 and hw / tot >= HEAD_W:
				out.add(s["name"])
				break
	return out


def head_box(sk, origin) -> tuple:
	"""(完整帧 RGBA8, 头部框 或 None, 脸框 或 None)。
	头部框 = 只画头部插槽时的不透明像素框(含饰物); 脸框 = 只画名叫 head 的那个插槽(不含饰物), 放宽量按它算 ——
	凤凰龟头焰把头部框撑高近一倍, 按头部框放宽会把脚带进来(11-05 预览)。"""
	full = _binarize(S.render(sk, I.ANIM, 0.0, (I.CANVAS, I.CANVAS), origin))
	hs = head_slots(sk)
	if not hs:
		return full, None, None
	boxes = []
	for only in (hs, {"head"} & hs):
		if not only:
			boxes.append(None)
			continue
		m = _binarize(S.render(sk, I.ANIM, 0.0, (I.CANVAS, I.CANVAS), origin, only_slots=only))[..., 3] > 0
		boxes.append(_bbox(m) if m.any() else None)
	if boxes[0] is None:
		return full, None, None
	return full, boxes[0], boxes[1] or boxes[0]


def avatar(d: str) -> tuple:
	nn = d.split("_")[0][len("turtle"):]
	sk = S.load(os.path.join(I.SRC, d, "turtle%s.json" % nn))
	sx, sy, sw, sh = [float(sk.sk.get(k, 0)) for k in ("x", "y", "width", "height")]
	origin = (sx + sw / 2 - I.CANVAS / 2, sy + sh / 2 - I.CANVAS / 2)
	full, hb, face = head_box(sk, origin)
	m = full[..., 3] > 0
	cx0, cy0, cx1, cy1 = _bbox(m)
	if hb is None:
		x0, y0, x1, y1 = cx0, cy0, cx1, cy1
	else:
		fx0, fy0, fx1, fy1 = face
		w, h = fx1 - fx0, fy1 - fy0
		x0 = min(hb[0], fx0)
		y0 = min(hb[1], fy0)
		x1 = min(cx1, max(hb[2], fx1 + int(round(w * RIGHT))))
		y1 = min(cy1, max(hb[3], fy1 + int(round(h * DOWN))))
	crop = full[y0:y1, x0:x1]
	tx0, ty0, tx1, ty1 = _bbox(crop[..., 3] > 0)
	crop = crop[ty0:ty1, tx0:tx1]
	out = np.zeros((crop.shape[0] + 2 * PAD, crop.shape[1] + 2 * PAD, 4), dtype=np.uint8)
	out[PAD:PAD + crop.shape[0], PAD:PAD + crop.shape[1]] = crop
	img = Image.fromarray(out, "RGBA")
	img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
	return img, hb, (x0, y0, x1, y1)


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	preview = None
	if "--preview" in sys.argv:
		preview = sys.argv[sys.argv.index("--preview") + 1]
	os.makedirs(OUT_DIR, exist_ok=True)
	imgs = []
	for d in I._dirs():
		tid = d.split("_", 1)[1]
		img, hb, box = avatar(d)
		if preview is None:
			img.save(os.path.join(OUT_DIR, "%s.png" % tid), optimize=False)
			AvatarHeads.build_one(tid)
		imgs.append((tid, img))
		print("%-10s 头部框 %s · 裁切 %s · 头像 %d×%d" % (tid, hb, box, img.width, img.height))
	if preview:
		cell = 300
		cols = 6
		rows = (len(imgs) + cols - 1) // cols
		sheet = Image.new("RGBA", (cell * cols, cell * rows), (60, 60, 70, 255))
		for i, (tid, img) in enumerate(imgs):
			im = img.copy()
			im.thumbnail((cell - 20, cell - 20), Image.NEAREST)
			sheet.alpha_composite(im, ((i % cols) * cell + (cell - im.width) // 2, (i // cols) * cell + (cell - im.height) // 2))
		sheet.save(preview)
		print("预览 →", preview)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
