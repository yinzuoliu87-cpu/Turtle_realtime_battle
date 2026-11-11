# -*- coding: utf-8 -*-
"""近战小将批次的预检修补(2026-11-11 一次性, CRLF 二进制读写)。"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	n0 = b.count(b"\n")
	for old, new in pairs:
		o = old.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		w = new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次 ≠ 1:\n%s" % (rel, c, old[:160]))
		b = b.replace(o, w)
	open(p, "wb").write(b)
	print("改好", rel, n0, "→", b.count(b"\n"), "行")


## ① _make_unit 超 250 行: 小将归一那几行收成小函数
patch("scripts/scenes/battle/battle_spawn.gd", [
	('		if _nk != null and tex != null:\n'
	 '			u["idle_offy"] = float(_nk[1]) - float(frame_h) * 0.5\n'
	 '			spr.offset = Vector2(0.0, float(u["idle_offy"]))\n'
	 '			## 第 4 项 = 本体米数(11-11 近战小将 192 方帧, 本体只占 99 像素): 按本体高归一, 不按帧高(那样人只有 1 米)\n'
	 '			if (_nk as Array).size() >= 4:\n'
	 '				u["idle_px"] = float(_nk[3]) / maxf(1.0, float(_nk[2]))\n'
	 '				spr.pixel_size = float(u["idle_px"])\n',
	 '		if _nk != null and tex != null:\n'
	 '			_apply_minion_norm(u, spr, _nk, frame_h)\n'),
	('func _spawn_hiding_minion(u: Dictionary) -> void:',
	 '## 小将立绘按 ANIM_NORM 归一(_make_unit 抽出, 11-11): 脚底对齐 = 脚底行 - 半帧高;\n'
	 '##   第 4 项 = 本体米数(11-11 起三种小将 192 方帧、本体只占一半): 按本体高归一, 不按帧高(那样人只有 1 米)\n'
	 'func _apply_minion_norm(u: Dictionary, spr: Sprite3D, nk: Array, frame_h: int) -> void:\n'
	 '	u["idle_offy"] = float(nk[1]) - float(frame_h) * 0.5\n'
	 '	spr.offset = Vector2(0.0, float(u["idle_offy"]))\n'
	 '	if nk.size() >= 4:\n'
	 '		u["idle_px"] = float(nk[3]) / maxf(1.0, float(nk[2]))\n'
	 '		spr.pixel_size = float(u["idle_px"])\n'
	 '\n'
	 '\n'
	 'func _spawn_hiding_minion(u: Dictionary) -> void:'),
])

## ② 旧链子(_surf_chain_shoot, ImmediateMesh 线)没人调了: 人体浪板 11-11 换成 PierceChainVfx
p = os.path.join(ROOT, "scripts/scenes/RealtimeBattle3DScene.gd")
b = open(p, "rb").read()
i = b.index(b"func _surf_chain_shoot(")
j = b.index(b"func _skill_vfx_tex(", i)
b = b[:i] + b[j:]
open(p, "wb").write(b)
print("删掉 _surf_chain_shoot,", b.count(b"\n"), "行")

## ③ 援军门禁: 小将按种类叫全名(用户 11-11「怎么全是小将？不应该分类好吗？」)
patch("tests/verify_reserve_minion_ui.gd", [
	('	_ok("④ 对照: 对方幸存的普通 / 精英小将卡名不变", cur_txt.has("小将") and cur_txt.has("精英小将"))',
	 '	_ok("④ 对照: 对方幸存的近战 / 精英小将按种类叫全名(11-11 原来近战 / 远程一律写「小将」)", cur_txt.has("近战小将") and cur_txt.has("精英小将"))'),
	('		and s._dl_sys._dl_spec_name({"kind": "minion", "role": "back"}) == "小将"',
	 '		and s._dl_sys._dl_spec_name({"kind": "minion", "role": "back"}) == "远程小将"\n'
	 '		and s._dl_sys._dl_spec_name({"kind": "minion", "role": "front"}) == "近战小将"'),
])
