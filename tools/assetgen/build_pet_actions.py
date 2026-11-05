# -*- coding: utf-8 -*-
"""tools/assetgen/build_pet_actions.py — 外包 11 只以外、要从头做的 14 只龟: 像素化定稿 + 全套动作(2026-11-05; 先糖果龟样板)。

方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.4 / §4.1b: 这 14 只现有立绘不是像素画(500×500 帧、上万色) ⇒
  ① 定稿: PixelLab image_to_pixelart(忠实模式)把现有形象转成像素画, 尺度对齐外包 11 只(内容约 170 像素), 抠底 → pet_src/<龟>/keyframe.png
  ② 各段: animate_image 首帧 = 定稿 → pet_src/<龟>/<段>/ai_N.png(idle / run / attack / hurt / death / cast_<技能类型>)
  ③ 本脚本: 锁回定稿调色板, 待机帧条(格子 = 定稿尺寸)+ 动作方帧(与外包 11 只同一布局: S_FRAME 方帧、格子底边 = FEET),
     命中帧 = 第一次伸到最大伸出量 85% 的帧(刚打到), 释放帧 = 与第 0 帧差最多的帧; 头像 = 定稿左侧头部 ×3。
     写 pet_src/pet_manifest.json, build_spine_actions.py 生成 TurtleActions 时并进去(查表 / 门禁对新龟一律生效)。
输出: assets/sprites/pets/pixel/<龟>_idle.png · assets/sprites/pets/animations/<龟>/*.png · assets/sprites/avatars/<龟>.png · data/pets.json(img / sprite)
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_pet_actions.py [龟id ...]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_spine_actions as A  # noqa: E402

SRC = os.path.join(HERE, "pet_src")
MANIFEST = os.path.join(SRC, "pet_manifest.json")
PIXEL_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "pixel")
ANIM_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "animations")
AVATAR_DIR = os.path.join(ROOT, "assets", "sprites", "avatars")
PETS = os.path.join(ROOT, "data", "pets.json")
FPS = 15
IDLE_FPS = 8
COLS = 10
## 头像裁切(定稿内容框的比例): 龟朝左, 头在左侧 —— 每只按定稿看过再登记
AVATAR_BOX = {"candy": (0.0, 0.18, 0.62, 0.84)}


def _ai(d: str, pal: np.ndarray) -> list:
	n = len([f for f in os.listdir(d) if f.startswith("ai_") and f.endswith(".png")])
	return [A._palette_lock(np.asarray(Image.open(os.path.join(d, "ai_%d.png" % k)).convert("RGBA")), pal) for k in range(1, n + 1)]


def build(tid: str) -> dict:
	src = os.path.join(SRC, tid)
	key = np.asarray(Image.open(os.path.join(src, "keyframe.png")).convert("RGBA")).copy()
	key[..., 3] = np.where(key[..., 3] >= 128, 255, 0)
	key[key[..., 3] == 0] = 0
	ch, cw = key.shape[:2]
	pal = np.unique(key[key[..., 3] > 0][:, :3], axis=0)
	## ① 待机帧条(格子 = 定稿尺寸; 多留 1 格 —— 游戏 _sprite_dict_from 的 drop_last 会丢最后一格)
	idle = [key] + (_ai(os.path.join(src, "idle"), pal) if os.path.isdir(os.path.join(src, "idle")) else [])
	cells = len(idle) + 1
	rows = int(math.ceil(cells / float(COLS)))
	sheet = np.zeros((rows * ch, COLS * cw, 4), dtype=np.uint8)
	for k, f in enumerate(idle):
		r, c = divmod(k, COLS)
		sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = f
	os.makedirs(PIXEL_DIR, exist_ok=True)
	Image.fromarray(sheet, "RGBA").save(os.path.join(PIXEL_DIR, "%s_idle.png" % tid), optimize=False)
	## ② 动作方帧
	S, FEET = A.S_FRAME, A.FEET
	ox, oy = (S - cw) // 2, FEET - ch

	def place(cell: np.ndarray) -> np.ndarray:
		fr = np.zeros((S, S, 4), dtype=np.uint8)
		fr[oy:oy + ch, ox:ox + cw] = cell
		return fr
	k0 = place(key)
	od = os.path.join(ANIM_DIR, tid)
	os.makedirs(od, exist_ok=True)
	ent = {"frame": S, "fps": FPS, "casts": {}}
	segs = {}
	for nm in sorted(os.listdir(src)):
		d = os.path.join(src, nm)
		if not os.path.isdir(d) or nm == "idle":
			continue
		frames = [k0] + [place(f) for f in _ai(d, pal)]
		if nm == "death":
			while len(frames) < int(A.DEATH["frames"]):
				frames.append(frames[-1].copy())
		segs[nm] = frames
		Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(od, "%s.png" % nm), optimize=False)
	for nm in ("attack", "hurt", "death", "run"):
		if nm in segs:
			ent[nm] = len(segs[nm])
	if "attack" in segs:
		lefts = [(A._bbox(f)[0] if (f[..., 3] > 0).any() else 999) for f in segs["attack"]]
		ext = [lefts[0] - x for x in lefts]
		ent["hit"] = next(i for i, e in enumerate(ext) if e >= 0.85 * max(ext)) if max(ext) > 0 else A.ATTACK_HIT
	for nm, frames in segs.items():
		if nm.startswith("cast_"):
			ent["casts"][nm[5:]] = [len(frames), A.peak_frame(frames), "pixellab"]
	bx0, by0, bx1, by1 = A._bbox(k0)
	ent["body0"] = by1 - by0
	ent["feet_row"] = by1
	## ③ 头像
	ys, xs = np.where(key[..., 3] > 0)
	x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
	fx0, fy0, fx1, fy1 = AVATAR_BOX.get(tid, (0.0, 0.0, 0.6, 0.8))
	box = (int(x0 + (x1 - x0) * fx0), int(y0 + (y1 - y0) * fy0), int(x0 + (x1 - x0) * fx1), int(y0 + (y1 - y0) * fy1))
	av = key[box[1]:box[3], box[0]:box[2]]
	m = av[..., 3] > 0
	ays, axs = np.where(m)
	av = av[ays.min():ays.max() + 1, axs.min():axs.max() + 1]
	pad = np.zeros((av.shape[0] + 2, av.shape[1] + 2, 4), dtype=np.uint8)
	pad[1:-1, 1:-1] = av
	Image.fromarray(pad, "RGBA").resize((pad.shape[1] * 3, pad.shape[0] * 3), Image.NEAREST).save(os.path.join(AVATAR_DIR, "%s.png" % tid), optimize=False)
	ent["_idle"] = {"img": "pets/pixel/%s_idle.png" % tid, "frames": len(idle), "frameW": cw, "frameH": ch,
		"duration": int(round(len(idle) * 1000.0 / IDLE_FPS))}
	print("%-8s 待机 %d 帧(%d×%d)· %s · 命中帧 %s · 技能 %s" % (tid, len(idle), cw, ch,
		" ".join("%s %d" % (k, ent[k]) for k in ("attack", "hurt", "death", "run") if k in ent), ent.get("hit"), sorted(ent["casts"])))
	return ent


def _patch_pets(tid: str, idle: dict) -> None:
	"""pets.json 只改这只龟的 img / sprite 两个字段, 其余逐字节不动(按原文替换, 不重写整个 json)。"""
	raw = open(PETS, "rb").read().decode("utf-8")
	data = json.loads(raw)
	pets = data["pets"] if isinstance(data, dict) else data
	p = next(x for x in pets if x["id"] == tid)
	old_img = '"img": "%s"' % p["img"]
	new_img = '"img": "%s"' % idle["img"]
	i0 = raw.index('"id": "%s"' % tid)
	j = raw.index(old_img, i0)
	raw = raw[:j] + new_img + raw[j + len(old_img):]
	sp_new = '"sprite": {"frames": %d, "frameW": %d, "frameH": %d, "duration": %d}' % (idle["frames"], idle["frameW"], idle["frameH"], idle["duration"])
	if "sprite" in p:
		k = raw.index('"sprite":', i0)
		e = raw.index("}", k) + 1
		raw = raw[:k] + sp_new + raw[e:]
	else:
		j = raw.index(new_img, i0) + len(new_img)
		raw = raw[:j] + ", " + sp_new + raw[j:]
	open(PETS, "wb").write(raw.encode("utf-8"))


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	ids = sys.argv[1:] or sorted(d for d in os.listdir(SRC) if os.path.exists(os.path.join(SRC, d, "keyframe.png")))
	man = json.load(open(MANIFEST, encoding="utf-8")) if os.path.exists(MANIFEST) else {}
	for tid in ids:
		ent = build(tid)
		_patch_pets(tid, ent.pop("_idle"))
		man[tid] = ent
	json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
	print("清单 →", os.path.relpath(MANIFEST, ROOT), "(再跑 build_spine_actions.py 并进 TurtleActions)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
