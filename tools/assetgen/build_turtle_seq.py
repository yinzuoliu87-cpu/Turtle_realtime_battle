# -*- coding: utf-8 -*-
"""tools/assetgen/build_turtle_seq.py — 14 只新形象龟的待机 / 走路 / 普攻 / 技能 / 被动帧条(2026-11-07; 取代 build_pet_actions.py)。

用户 11-06 ~ 11-07: 14 只按「站立、好做动作」的新形象重做, 每只风格不同; 普攻节奏按命中帧重排(蓄力 → 挥动 → 命中 → 停 → 收回)。
输入: tools/assetgen/pet_seq/<龟>/seq.json + avatar.png + <段>/f_NN.png —— 每段是排好顺序的裸帧(不含演示特效), 坐标系见下面 art 坐标。
     段名: idle / run / attack / death / cast_<技能类型> / form_<段名> / state_<状态名>
输出: assets/sprites/pets/pixel/<龟>_idle.png · assets/sprites/pets/animations/<龟>/*.png · assets/sprites/avatars/<龟>.png · data/pets.json(只改 sprite)·
     pet_seq/manifest.json(build_spine_actions.py --gd-only 并进 TurtleActions)
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_turtle_seq.py [龟id ...]

布局(与 verify_spine_actions 同口径):
  · art 坐标 = PixelLab 画布 128×128, 脚底站在第 123 行。seq.json 的 ox / ground 记这一段帧里 art 原点在哪(武器伸出 128 画布的段, 画布更大)。
  · 全部 14 只同一像素密度: 待机格子高 CELL_H ⇒ 2 米 / CELL_H ≈ 0.0192 米/像素(游戏按待机帧高归一到 TARGET_BODY_H)。
    旧版按「旧立绘本体米数」逐只补透明行, 但新形象全站着, 旧的趴姿高度没有意义(旧无头龟 0.84 米)。
  · 方帧边长 S 每只不同(_resolve_action 只认方帧, 归一表按龟一行): 刚好装下这只龟全部动作; 本体中心 = 方帧水平中心, 待机格子底边 = 脚底行。
  · 帧条宽超过手机 GPU 上限(MAX_W)就折行(目前只有糖果锤), 行数写进 TurtleActions.ROWS。
  · 普攻 / 阵亡 / 技能的第 0 帧换成待机第 0 帧: 动作一播不跳(verify_spine_actions ②)。
"""
import json
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "pet_seq")
MANIFEST = os.path.join(SRC, "manifest.json")
PIXEL_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "pixel")
ANIM_DIR = os.path.join(ROOT, "assets", "sprites", "pets", "animations")
AVATAR_DIR = os.path.join(ROOT, "assets", "sprites", "avatars")
PETS = os.path.join(ROOT, "data", "pets.json")

CELL_H = 104          # 待机格子高(全 14 只同一个)
ART_FEET = 124        # art 坐标里脚底下一行(不含): 脚站在第 123 行
MAX_W = 4096          # 手机 GPU 单边上限(verify_sprite_sheets)
DEATH_MIN = 15        # 阵亡帧数下限: 末帧定住, 时长 ≥ 游戏阵亡淡出(0.55 + 0.4 秒)
IDLE_MS = 1000        # 待机 8 帧一轮 1 秒


def _clean(im: Image.Image) -> Image.Image:
	"""二值透明, 透明处清零(像素画零半透明; 重跑逐字节相同)"""
	im = im.convert("RGBA")
	px = im.load()
	for y in range(im.height):
		for x in range(im.width):
			r, g, b, a = px[x, y]
			px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
	return im


def _load(tid: str) -> dict:
	"""{段名: {"frames": [...], "ox", "ground", "rel", "fps"}}"""
	d = os.path.join(SRC, tid)
	meta = json.load(open(os.path.join(d, "seq.json"), encoding="utf-8"))
	out = {}
	for seg, m in meta.items():
		sd = os.path.join(d, seg)
		fs = sorted(f for f in os.listdir(sd) if f.startswith("f_") and f.endswith(".png"))
		if not fs:
			raise SystemExit("%s/%s 没有帧" % (tid, seg))
		out[seg] = dict(m, frames=[_clean(Image.open(os.path.join(sd, f))) for f in fs])
	return out


def _extent(segs: dict) -> tuple:
	"""全部帧相对脚底原点的外框: 左 / 右(art x) · 上 / 下(相对脚底行)"""
	l, r, t, b = 999, -999, 0, 0
	for s in segs.values():
		for im in s["frames"]:
			bb = im.getbbox()
			if bb is None:
				continue
			l = min(l, bb[0] - s["ox"])
			r = max(r, bb[2] - s["ox"])
			t = max(t, s["ground"] - bb[1])
			b = max(b, bb[3] - s["ground"])
	return l, r, t, b


def _up4(v: float) -> int:
	return int(math.ceil(v / 4.0)) * 4


def build(tid: str) -> dict:
	segs = _load(tid)
	idle = segs["idle"]
	if len(idle["frames"]) != 8:
		raise SystemExit("%s 待机应 8 帧, 实际 %d" % (tid, len(idle["frames"])))
	bb0 = idle["frames"][0].getbbox()
	cx = (bb0[0] + bb0[2]) // 2 - idle["ox"]   # 本体中心(art x)
	l, r, t, b = _extent(segs)
	half = max(cx - l, r - cx)
	S = _up4(max(2 * half + 2, t + b + 2))
	feet = S - b                               # 待机格子底边 = 这一行(不含)
	## ① 待机格子: 宽 = 待机外框对称 + 边距; 高 = CELL_H
	il, ir, it, _ib = _extent({"idle": idle})
	W = 2 * (max(cx - il, ir - cx) + 1)
	if it + 1 > CELL_H:
		raise SystemExit("%s 待机高 %d 超过格子 %d" % (tid, it, CELL_H))

	def to_frame(im: Image.Image, s: dict) -> Image.Image:
		fr = Image.new("RGBA", (S, S), (0, 0, 0, 0))
		fr.paste(im, (S // 2 - cx - s["ox"], feet - ART_FEET + 123 - s["ground"]))   # paste 自动裁出界部分; 外框已算进 S
		return fr

	def to_cell(fr: Image.Image) -> Image.Image:
		return fr.crop(((S - W) // 2, feet - CELL_H, (S - W) // 2 + W, feet))

	idle_fr = [to_frame(im, idle) for im in idle["frames"]]
	k0 = idle_fr[0]
	sheet = Image.new("RGBA", (W * 9, CELL_H), (0, 0, 0, 0))   # 9 格: 游戏 _sprite_dict_from(drop_last) 丢最后一格
	for i, fr in enumerate(idle_fr):
		sheet.paste(to_cell(fr), (i * W, 0))
	os.makedirs(PIXEL_DIR, exist_ok=True)
	sheet.save(os.path.join(PIXEL_DIR, "%s_idle.png" % tid), optimize=False)
	## ② 动作方帧条
	od = os.path.join(ANIM_DIR, tid)
	os.makedirs(od, exist_ok=True)
	for f in os.listdir(od):
		if f.endswith(".png"):
			os.remove(os.path.join(od, f))
	ent = {"frame": S, "feet": feet, "fps": 15, "casts": {}, "rows": {}}
	bb = k0.getbbox()
	ent["body0"] = bb[3] - bb[1]
	ent["feet_row"] = bb[3]
	for seg, s in sorted(segs.items()):
		if seg == "idle":
			continue
		frames = [to_frame(im, s) for im in s["frames"]]
		kind = seg.split("_", 1)[0]
		if kind in ("attack", "death", "cast"):
			frames[0] = k0.copy()
		if kind == "death":
			frames += [frames[-1].copy() for _ in range(DEATH_MIN - len(frames))]
		name = {"form": seg[5:], "state": seg}.get(kind, seg)
		rel_path = "pets/animations/%s/%s.png" % (tid, name)
		n = len(frames)
		cols = min(n, MAX_W // S)
		rows = int(math.ceil(n / float(cols)))
		st = Image.new("RGBA", (cols * S, rows * S), (0, 0, 0, 0))
		for i, fr in enumerate(frames):
			st.paste(fr, ((i % cols) * S, (i // cols) * S))
		st.save(os.path.join(od, "%s.png" % name), optimize=False)
		if rows > 1:
			ent["rows"][rel_path] = [rows, n]
		if kind in ("attack", "death", "run"):
			ent[kind] = n
			if kind == "attack":
				ent["hit"] = int(s["rel"])
		elif kind == "cast":
			ent["casts"][seg[5:]] = [n, int(s["rel"]), "seq"] + ([int(s["cancel"])] if int(s.get("cancel", -1)) >= 0 else [])
		elif kind == "form":
			ent.setdefault("forms", {})[seg[5:]] = n
			ent.setdefault("form_fps", {})[seg[5:]] = float(s["fps"])
			if int(s.get("rel", -1)) >= 0:   # 普攻的替换帧条(灵魂打击拍爪): 命中帧登记到 HIT
				ent.setdefault("hits", {})[rel_path] = int(s["rel"])
		elif kind == "state":
			ent.setdefault("states", []).append([seg[6:], rel_path, float(s["fps"])])
	## ③ 头像: 头部特写源图(PixelLab Pro Flash 128×128, 见 pet_seq/README.md)裁透明边 ×3 最近邻
	av = _clean(Image.open(os.path.join(SRC, tid, "avatar.png")))
	av = av.crop(av.getbbox())
	av.resize((av.width * 3, av.height * 3), Image.NEAREST).save(os.path.join(AVATAR_DIR, "%s.png" % tid), optimize=False)
	ent["_idle"] = {"frames": 8, "frameW": W, "frameH": CELL_H, "duration": IDLE_MS}
	print("%-9s S=%d feet=%d 待机格 %d×%d 本体 %d 像素 = %.2f 米 · 普攻 %d 帧命中 %d · 技能 %d 段 · 被动段 %s" % (
		tid, S, feet, W, CELL_H, ent["body0"], ent["body0"] * 2.0 / CELL_H, ent.get("attack", 0), ent.get("hit", -1), len(ent["casts"]), sorted(ent.get("forms", {}))))
	return ent


def _patch_pets(tid: str, idle: dict) -> None:
	"""pets.json 只改这只龟的 sprite 字段, 其余逐字节不动"""
	raw = open(PETS, "rb").read().decode("utf-8")
	i0 = raw.index('"id": "%s"' % tid)
	k = raw.index('"sprite":', i0)
	e = raw.index("}", k) + 1
	new = '"sprite": {"frames": %d, "frameW": %d, "frameH": %d, "duration": %d}' % (idle["frames"], idle["frameW"], idle["frameH"], idle["duration"])
	raw = raw[:k] + new + raw[e:]
	open(PETS, "wb").write(raw.encode("utf-8"))


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	ids = sys.argv[1:] or sorted(d for d in os.listdir(SRC) if os.path.exists(os.path.join(SRC, d, "seq.json")))
	man = json.load(open(MANIFEST, encoding="utf-8")) if os.path.exists(MANIFEST) else {}
	for tid in ids:
		ent = build(tid)
		_patch_pets(tid, ent.pop("_idle"))
		man[tid] = ent
	json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
	print("清单 →", os.path.relpath(MANIFEST, ROOT), "(再跑 build_spine_actions.py --gd-only 并进 TurtleActions)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
