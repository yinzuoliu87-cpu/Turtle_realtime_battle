# -*- coding: utf-8 -*-
"""tools/assetgen/build_attack_rhythm.py — 小将与幽灵的普攻帧条按「蓄力 → 挥动 → 命中 → 停 → 收回」重排(2026-11-08)。

用户 11-08:「三个四个小将的…普通攻击有没有按照我们昨天说的，就是攻击前摇，攻击后摇，然后中间就是就慢一点…
  包括我们自己的忍者龟、变脸龟…幽灵龟。」—— 11-07 给 14 只新形象定的节奏是
  第 0 帧站姿 → 蓄力 2 → 挥动 2 ~ 3 → 命中 → 停 2 → 收回 4(build_turtle_seq.py 的普攻段都是这个形状)。
逐帧量(11-08)这几张旧帧条: 援军前 4 帧几乎一样、命中后只有 1 帧; 远程 / 精英命中后没有收回帧; 精英第 0 帧就举着镰刀。

做法: 原帧一律保留; 缺的中间帧用 PixelLab animate_image 补, 首尾都钉在原帧上(小幅插值, 造型不走样;
  AI 返回的末帧是重画的, 不用, 两端一律取原帧), 再锁回这个单位原帧条用过的颜色。只缺时长的(近战 / 幽灵)只重排、不出图。
素材: tools/assetgen/ai_src/attack_rhythm/<单位>/
  orig.png      重排前的原帧条(第一次运行时从游戏帧条存下; 之后游戏帧条已被覆盖, 以它为准)
  extra_*.png   原帧条以外要用到的原画帧(精英: 跑动第 0 帧 = 同尺度站姿)
  ai_<段>_<k>.png  AI 补帧原始输出(段 = wind 起手 / swing 挥动 / rec 收回)
  ai_key_*.png  AI 出的关键姿势(忍者: 原普攻是 7 月旧画风, 与现在的待机不是同一个形象, 整段从新形象待机重做)
帧序表 SEQ: "o3" = 原帧第 3 帧, "w2" = ai_wind_2, "s1" = ai_swing_1, "r4" = ai_rec_4, "x:run0" = extra_run0.png(原画),
  "k:slash" = ai_key_slash.png(AI, 锁色)。
命中帧 HIT 抄进 scripts/gamedata/attack_hits.gd(门禁 verify_attack_rhythm 核登记、verify_attack_rhythm_shape 核形状)。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_attack_rhythm.py
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_spine_actions as A  # noqa: E402

ANIM = os.path.join(ROOT, "assets", "sprites", "pets", "animations")
SRC = os.path.join(HERE, "ai_src", "attack_rhythm")

## 单位 → (游戏帧条, 帧序, 命中帧在新帧条里的下标, 取调色板的其他帧条)
UNITS = {
	## 援军小将: 站姿 → 抬手 3 帧(AI)→ 瞄准(原 4)→ 开火(原 5)→ 停 2(AI)→ 收回 4(AI 3 帧 + 站姿)
	"reserve": ("reserve/attack.png", ["o0", "w1", "w2", "w3", "o4", "o5", "r1", "r2", "r3", "r4", "r5", "o0"], 5,
		["reserve/idle.png", "reserve/run.png"]),
	## 远程小将: 站姿 → 蓄力(原 1 ×2)→ 前倾(原 2 ×2)→ 开火(原 3)→ 后坐(原 4)+ 停 1(AI)→ 收回(AI 3 帧 + 站姿)
	##   AI 收回第 5 帧手上的光又亮回去(像再开一枪), 不用。
	"ranged": ("ranged/attack.png", ["o0", "o1", "o1", "o2", "o2", "o3", "o4", "r1", "r2", "r3", "r4", "o0"], 5,
		["ranged/run.png", "ranged/skill.png"]),
	## 精英小将: 跑动第 0 帧站姿(与普攻同一像素尺度)→ 拉镰 3 帧(AI)→ 举镰(原 0)→ 起挥(原 1)→ 横扫(原 2)
	##   → 停 2(原 3 + AI)→ 收回 4(AI)。原来第 0 帧就举着镰刀 ⇒ 一进前摇姿势就跳。
	"elite": ("elite/attack.png", ["x:run0", "w1", "w2", "w3", "o0", "o1", "o2", "o3", "r1", "r2", "r3", "r4", "r5"], 6,
		["elite/run.png"]),
	## 忍者龟: 新形象待机第 0 帧 → 拔刀蹲身 2(AI)→ 刀拉过肩(关键姿势)→ 挥 2(AI)→ 横斩带刀光(关键姿势, 命中)
	##   → 停 2(刀光收尾, AI)→ 收回 4(起身收刀回背上, AI 3 帧 + 站姿)。原 slash.png 3 帧是旧画风, 一出刀就换了个长相。
	"ninja": ("ninja/slash.png", ["x:idle0", "w2", "w3", "k:wind", "s2", "s3", "k:slash", "r1", "r2", "r3", "r4", "r5", "x:idle0"], 6,
		["ninja/idle.png", "ninja/run.png", "ninja/dash.png", "ninja/death.png"]),
	## 近战小将(11-05 已重做 9 帧: 0~3 蓄力 → 4 刺到 → 5~6 定住 → 7~8 收回): 蓄力补一拍、收回每帧停两拍
	"melee": ("melee/attack.png", ["o0", "o1", "o2", "o3", "o3", "o4", "o5", "o6", "o7", "o7", "o8", "o8"], 5, []),
	## 幽灵龟: 0~2 站姿 → 3 抬爪 → 4 前探 → 5 拍到 → 6~8 收回; 命中后定住 2 拍、收回放慢
	"ghost": ("ghost/attack.png", ["o0", "o1", "o2", "o3", "o4", "o5", "o5", "o5", "o6", "o7", "o7", "o8"], 5, ["ghost/idle.png"]),
}


def _frames(path: str) -> list:
	im = np.asarray(Image.open(path).convert("RGBA"))
	h = im.shape[0]
	return [im[:, k * h:(k + 1) * h].copy() for k in range(im.shape[1] // h)]


def _binarize(fr: np.ndarray) -> np.ndarray:
	out = fr.copy()
	m = out[..., 3] >= 128
	out[m, 3] = 255
	out[~m] = 0
	return out


def build(unit: str) -> dict:
	rel, seq, hit, pal_from = UNITS[unit]
	d = os.path.join(SRC, unit)
	sheet = os.path.join(ANIM, rel)
	orig_p = os.path.join(d, "orig.png")
	if not os.path.exists(orig_p):
		os.makedirs(d, exist_ok=True)
		Image.open(sheet).convert("RGBA").save(orig_p, optimize=False)
	orig = _frames(orig_p)
	h = orig[0].shape[0]
	cols = [f[f[..., 3] >= 128][:, :3] for f in orig]
	for p in pal_from:
		pp = os.path.join(ANIM, p)
		if os.path.exists(pp):
			a = np.asarray(Image.open(pp).convert("RGBA"))
			cols.append(a[a[..., 3] >= 128][:, :3])
	pal = np.unique(np.concatenate(cols), axis=0)
	out = []
	for tok in seq:
		if tok.startswith("o"):
			fr = orig[int(tok[1:])]
		elif tok.startswith("x:"):
			fr = np.asarray(Image.open(os.path.join(d, "extra_%s.png" % tok[2:])).convert("RGBA"))
		elif tok.startswith("k:"):
			fr = A._palette_lock(np.asarray(Image.open(os.path.join(d, "ai_key_%s.png" % tok[2:])).convert("RGBA")), pal)
		else:
			seg = {"w": "wind", "s": "swing", "r": "rec"}[tok[0]]
			ai = np.asarray(Image.open(os.path.join(d, "ai_%s_%s.png" % (seg, tok[1:]))).convert("RGBA"))
			fr = A._palette_lock(ai, pal)
		if fr.shape[:2] != (h, h):
			raise SystemExit("%s %s 尺寸 %s ≠ %d" % (unit, tok, fr.shape[:2], h))
		out.append(_binarize(fr))
	Image.fromarray(np.concatenate(out, axis=1), "RGBA").save(sheet, optimize=False)
	return {"unit": unit, "frames": len(out), "hit": hit, "before": hit, "after": len(out) - hit - 1}


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	for unit in UNITS:
		r = build(unit)
		print("%-8s %2d 帧 · 命中帧 %d(前 %d 帧 / 后 %d 帧)" % (unit, r["frames"], r["hit"], r["before"], r["after"]))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
