# -*- coding: utf-8 -*-
"""近战小将(珊瑚骑士)接线 —— 一次性补丁(2026-11-11)。CRLF 文件二进制读写, 每处替换断言恰好命中一次; 主文件行数不变(arch_budget)。"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs, keep_lines=False):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	n0 = b.count(b"\n")
	for old, new in pairs:
		o = old.replace("\n", "\r\n").encode("utf-8")
		w = new.replace("\n", "\r\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次 ≠ 1:\n%s" % (rel, c, old[:120]))
		b = b.replace(o, w)
	if keep_lines and b.count(b"\n") != n0:
		raise SystemExit("%s: 行数 %d → %d(主文件必须行数不变)" % (rel, n0, b.count(b"\n")))
	open(p, "wb").write(b)
	print("改好", rel, n0, "→", b.count(b"\n"), "行")


MAIN = "scripts/scenes/RealtimeBattle3DScene.gd"
patch(MAIN, [
	('	"__minion_front__": ["pets/animations/melee/attack.png", 16.0],   # 12 帧 / 0.75s(原 9 帧 × 12)',
	 '	"__minion_front__": ["pets/animations/melee/attack.png", 19.6],   # 11-11 珊瑚骑士: 13 格 / 0.66s(命中格 5 ÷ 前摇 0.255s)'),
	('	"leap":  ["pets/animations/melee/leap.png", 6.25],    # 4帧 / 0.64s(0.00-0.64 蓄力+起跳)',
	 '	"leap":  ["pets/animations/melee/leap.png", 14.7],    # 11-11: 10格 / 0.68s(蹲 0~0.30 + 起跳; 0.68 出链)'),
	('	"throw": ["pets/animations/melee/throw.png", 6.25],   # 4帧 / 0.64s(0.64-1.28 滞空甩索)',
	 '	"throw": ["pets/animations/melee/throw.png", 10.0],   # 11-11: 6格 / 0.60s(0.68-1.28 刺头射出·手腕空着悬停)'),
	('	"dive":  ["pets/animations/melee/dive.png", 13.0],    # 4帧 / 0.31s ≈ 节拍 0.30s',
	 '	"dive":  ["pets/animations/melee/dive.png", 13.0],    # 8格; 运行时按拉人秒数传 fps(hiding_system: 8 ÷ dive_sec)'),
	('	"surf":  ["pets/animations/melee/surf.png", 4.8],     # 4帧 / 0.833s = 每帧208ms(保持平衡姿势, 不是高频抖)',
	 '	"surf":  ["pets/animations/melee/surf.png", 4.8],     # 4格 / 0.833s: 一张蹲稳姿势 + 呼吸下沉 0/1/2/1 像素'),
	('	"land":  ["pets/animations/melee/land.png", 13.0],    # 4帧 / 0.31s ≈ 落地 0.30s',
	 '	"land":  ["pets/animations/melee/land.png", 13.3],    # 4格 / 0.30s: 蹬离 / 下落 / 触地(专属动作挡普攻 ⇒ 不许长于 0.30s)'),
	('	"__minion_front__": [45.0, 65.0, 60.0],',
	 '	"__minion_front__": [99.0, 176.0, 99.0, 1.5],   # 11-11 珊瑚骑士: 192 方帧本体 99 脚底 176; 第 4 项 = 本体米数(帧里留白多, 不按帧高归一)'),
], keep_lines=True)

patch("scripts/systems/skills/hiding_system.gd", [
	('	var img: String = "pets/minion-elite.png" if is_elite else ("pets/minion-back.png" if is_back else "pets/minion.png")\n',
	 '	## 近战小将(11-11 珊瑚骑士)待机是一条帧表(呼吸 4 格), 与动作同一种 192 方帧 ⇒ 立绘 = 动作第 0 帧(verify_minion_idle_align)\n'
	 '	if not is_elite and not is_back and ResourceLoader.exists(battle.SPRITE_DIR + MELEE_IDLE_SHEET):\n'
	 '		var it: Texture2D = load(battle.SPRITE_DIR + MELEE_IDLE_SHEET)\n'
	 '		var ih: int = it.get_height()\n'
	 '		var nf: int = maxi(1, it.get_width() / ih)\n'
	 '		return {"tex": it, "frames": nf, "fps": MELEE_IDLE_FPS, "frame_h": ih, "hframes": nf, "vframes": 1, "loop": true}\n'
	 '	var img: String = "pets/minion-elite.png" if is_elite else ("pets/minion-back.png" if is_back else "pets/minion.png")\n'),
	('const SURF_PULL_MIN := 0.12            # 贴脸时的保底时长(秒), 免得动作一闪而过\n',
	 'const SURF_PULL_MIN := 0.12            # 贴脸时的保底时长(秒), 免得动作一闪而过\n'
	 '## 近战小将待机帧表(11-11 珊瑚骑士: 一张图 + 腰带以上下沉 0/1/2/1 像素, 每格 0.2 秒)\n'
	 'const MELEE_IDLE_SHEET := "pets/animations/melee/idle.png"\n'
	 'const MELEE_IDLE_FPS := 5.0\n'
	 '## 俯冲帧条格数(tools/assetgen/build_melee_minion.py SLOTS["dive"]): 播放速度 = 格数 ÷ 拉人秒数\n'
	 'const MELEE_DIVE_SLOTS := 8.0\n'),
	('	battle._melee_anim(u, "dive", 4.0 / dive_sec)           # dive.png 4 帧拉长到整段飞行, 播完才不会半空回站姿',
	 '	battle._melee_anim(u, "dive", MELEE_DIVE_SLOTS / dive_sec)   # dive.png 8 格拉长到整段飞行, 播完才不会半空回站姿'),
])

patch("scripts/scenes/battle/battle_spawn.gd", [
	('		if _nk != null and tex != null:\n'
	 '			u["idle_offy"] = float(_nk[1]) - float(frame_h) * 0.5\n'
	 '			spr.offset = Vector2(0.0, float(u["idle_offy"]))\n',
	 '		if _nk != null and tex != null:\n'
	 '			u["idle_offy"] = float(_nk[1]) - float(frame_h) * 0.5\n'
	 '			spr.offset = Vector2(0.0, float(u["idle_offy"]))\n'
	 '			## 第 4 项 = 本体米数(11-11 近战小将 192 方帧, 本体只占 99 像素): 按本体高归一, 不按帧高(那样人只有 1 米)\n'
	 '			if (_nk as Array).size() >= 4:\n'
	 '				u["idle_px"] = float(_nk[3]) / maxf(1.0, float(_nk[2]))\n'
	 '				spr.pixel_size = float(u["idle_px"])\n'),
])

## 小将按种类叫全名(用户 11-11「为什么精英小将、远程小将…都没有名字啊？怎么全是小将？不应该分类好吗？」)
patch("scripts/gamedata/minion_codex.gd", [
	('	return {"name": "小将", "rarity": "C", "crit": 0.0,',
	 '	## 名字按种类(用户 11-11「怎么全是小将？不应该分类好吗？」): 单位字典的 name 就是全名, 统计面板 / 结算 / 头像框读到的都对\n'
	 '	return {"name": "近战小将" if front else "远程小将", "rarity": "C", "crit": 0.0,'),
])
patch("scripts/scenes/battle/dual_lane_flow.gd", [
	('		return "精英小将" if bool(spec.get("elite", false)) else "小将"',
	 '		return str(MinionCodex.info(MinionCodex.kind_of(spec)).get("name", "小将"))   # 近战 / 远程 / 精英按种类叫全名(用户 11-11)'),
])
patch("scripts/scenes/InventoryScene.gd", [
	('		title = "精英小将" if elite else "小将"',
	 '		title = "精英小将" if elite else ("近战小将" if front else "远程小将")   # 按种类叫全名(用户 11-11)'),
])
