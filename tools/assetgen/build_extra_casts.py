# -*- coding: utf-8 -*-
"""tools/assetgen/build_extra_casts.py — 外包 11 只以外的龟的技能释放动作(2026-11-05; 先忍者 / 幽灵)。

方案书 docs/plans/20261105b-龟美术统一与动作补全.md §4.4: 忍者 / 幽灵 / 变脸**形象不动**(用户点名), 只给没有身体动作的技能补段,
  以它们现有形象为首帧生成, 画风一致。忍者「手里剑」接仓库里一直没接的 ninja/throw.png(11-05 实查全仓无引用)。
做法: 第 0 帧 = 这只龟待机第 0 帧原样 + PixelLab animate_image 帧(tools/assetgen/ai_src/<龟>/<技能类型>/ai_N.png),
  锁回这只龟待机 + 普攻帧条用过的颜色; 释放帧 = 与第 0 帧差得最多的那帧(build_spine_actions.peak_frame)。
输出: assets/sprites/pets/animations/<龟>/cast_<技能类型>.png + scripts/gamedata/cast_sheets.gd(生成, 别手改)。
确定性: 重跑逐字节相同。用法: python tools/assetgen/build_extra_casts.py
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
AI = os.path.join(HERE, "ai_src")
GD = os.path.join(ROOT, "scripts", "gamedata", "cast_sheets.gd")
FPS = 12.0
## 龟 → 技能类型 → 来源: ("ai", None) 走 ai_src/<龟>/<技能>; ("sheet", 现成帧条相对 animations/ 的路径)
ENTRIES = {
	"ninja": {"ninjaShuriken": ("sheet", "ninja/throw.png"), "ninjaBomb": ("ai", None)},
	"ghost": {"ghostPhantom": ("ai", None), "ghostStorm": ("ai", None)},
}
## 持续状态循环(状态期间替代待机; AttackRhythm.state_sd 读): 龟 → [状态名, 来源目录]
STATES = {
	"ghost": [["ghostPhase", "ghostPhase"]],
}


def _frames_of(path: str) -> list:
	a = np.asarray(Image.open(path).convert("RGBA"))
	h = a.shape[0]
	return [a[:, k * h:(k + 1) * h] for k in range(a.shape[1] // h)]


def _pal(tid: str) -> np.ndarray:
	cols = []
	for nm in ("idle.png", "attack.png", "slash.png"):
		p = os.path.join(ANIM, tid, nm)
		if os.path.exists(p):
			a = np.asarray(Image.open(p).convert("RGBA"))
			cols.append(a[a[..., 3] > 0][:, :3])
	return np.unique(np.concatenate(cols), axis=0)


def _has_ai(tid: str, sub: str) -> bool:
	d = os.path.join(AI, tid, sub)
	return os.path.isdir(d) and any(f.startswith("ai_") and f.endswith(".png") for f in os.listdir(d))


def _ai_strip(tid: str, sub: str, with_f0: bool = True) -> list:
	f0 = _frames_of(os.path.join(ANIM, tid, "idle.png"))[0]
	pal = _pal(tid)
	d = os.path.join(AI, tid, sub)
	n = len([f for f in os.listdir(d) if f.startswith("ai_") and f.endswith(".png")])
	out = [f0] if with_f0 else []
	for k in range(1, n + 1):
		ai = np.asarray(Image.open(os.path.join(d, "ai_%d.png" % k)).convert("RGBA"))
		if ai.shape[:2] != f0.shape[:2]:
			raise SystemExit("%s/%s 第 %d 帧尺寸 %s ≠ 待机 %s" % (tid, sub, k, ai.shape[:2], f0.shape[:2]))
		out.append(A._palette_lock(ai, pal))
	return out


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	L = ["class_name CastSheets",
		"extends RefCounted",
		"## 外包 11 只以外的龟的技能释放动作 / 持续状态循环 —— 由 tools/assetgen/build_extra_casts.py 生成, **别手改**。",
		"## 与 TurtleActions.CAST 同口径: [相对 assets/sprites/ 的路径, 帧率, 释放帧]; AttackRhythm.cast_entry 先查 TurtleActions 再查这里。",
		"## 忍者 / 幽灵形象不动(用户点名), 只给没有身体动作的技能补段(方案书 20261105b §4.4)。",
		"",
		"const CAST := {"]
	for tid in sorted(ENTRIES):
		L.append("\t\"%s\": {" % tid)
		for st in sorted(ENTRIES[tid]):
			kind, rel = ENTRIES[tid][st]
			if kind == "sheet":
				frames = _frames_of(os.path.join(ANIM, rel))
				path = "pets/animations/" + rel
			else:
				if not _has_ai(tid, st):
					print("跳过 %s/%s(AI 帧还没下)" % (tid, st))
					continue
				frames = _ai_strip(tid, st)
				path = "pets/animations/%s/cast_%s.png" % (tid, st)
				Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(ROOT, "assets", "sprites", path), optimize=False)
			rel_f = A.peak_frame(frames)
			L.append("\t\t\"%s\": [\"%s\", %.1f, %d],   # %d 帧 · %s" % (st, path, FPS, rel_f, len(frames), kind))
			print("%-6s %-14s %d 帧 · 释放帧 %d · %s" % (tid, st, len(frames), rel_f, kind))
		L.append("\t},")
	L.append("}")
	L.append("## 持续状态循环 [状态名, 路径, 帧率](状态期间替代待机)")
	L.append("const STATE := {")
	for tid in sorted(STATES):
		rows = []
		for name, sub in STATES[tid]:
			if not _has_ai(tid, sub):
				print("跳过状态 %s/%s(AI 帧还没下)" % (tid, sub))
				continue
			frames = _ai_strip(tid, sub, with_f0=False)
			path = "pets/animations/%s/state_%s.png" % (tid, name)
			Image.fromarray(np.concatenate(frames, axis=1), "RGBA").save(os.path.join(ROOT, "assets", "sprites", path), optimize=False)
			rows.append("[\"%s\", \"%s\", %.1f]" % (name, path, 8.0))
			print("%-6s 状态 %-10s %d 帧" % (tid, name, len(frames)))
		if rows:
			L.append("\t\"%s\": [%s]," % (tid, ", ".join(rows)))
	L.append("}")
	open(GD, "wb").write(("\n".join(L) + "\n").encode("utf-8"))
	print("写出", os.path.relpath(GD, ROOT))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
