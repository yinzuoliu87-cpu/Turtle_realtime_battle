# -*- coding: utf-8 -*-
"""精英铁锁「后甩带出一节链」与人物图对齐(11-11 实录逐帧: 第 74 帧人物已甩到前方, 链头还在身后多躺 2 帧)。
① 出链时刻 = whip.png 播到第 3 格「甩出」那刻 = 2 ÷ 动作帧率(帧率随拉人距离变, 不是固定 WHIP_WINDUP_SEC);
   飞行时间 = 命中时刻 WHIP_HIT_SEC − 出链时刻(夹在 0.06 ~ WHIP_CHAIN_FLY), 链头仍在晕 / 闪那刻扎到。
② 身后拳头按格切换(第 1 格往地上甩 / 第 2 格后拉), 不平滑插值 —— 人物图是逐格换的。
③ 命中时刻提成常量 WHIP_HIT_SEC(值不变 = 0.2 + 0.14), 主文件引用它(行数不变)。CRLF 二进制读写。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	for old, new in pairs:
		o = old.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		w = new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次:\n%s" % (rel, c, old[:160]))
		b = b.replace(o, w)
	open(p, "wb").write(b)
	print("改好", rel)


patch("scripts/systems/skills/elite_system.gd", [
	("const WHIP_WINDUP_SEC := 0.2\n",
	 "const WHIP_WINDUP_SEC := 0.2\n"
	 "const WHIP_HIT_SEC := WHIP_WINDUP_SEC + 0.14   # 链头扎中(目标晕 + 闪)的时刻, 从出招算; _tick_elite_whip 用\n"),
	("	## 后甩(前摇 WHIP_WINDUP_SEC 秒): 链头拖在身后地面, 一头连身后的拳头 —— 用户「往回这个地上甩一下，把这个链子带出来」\n"
	 "	## 拳头按 whip.png 前两张走: 第 1 张(往地上甩)→ 第 2 张(后拉蓄力), q = 前摇进度 0 ~ 1\n",
	 "	## 后甩: 链头拖在身后地面, 一头连身后的拳头 —— 用户「往回这个地上甩一下，把这个链子带出来」\n"
	 "	## 拳头按 whip.png 前两格走(人物图逐格换, 链端也逐格跳): 第 1 格往地上甩 / 第 2 格后拉蓄力; q = 后甩进度 0 ~ 1\n"),
	("		var back: float = lerpf(WHIP_BACK_HAND_0, WHIP_BACK_HAND_1, q)\n"
	 "		var up: float = lerpf(WHIP_BACK_UP_0, WHIP_BACK_UP_1, q)\n",
	 "		var back: float = WHIP_BACK_HAND_0 if q < 0.5 else WHIP_BACK_HAND_1\n"
	 "		var up: float = WHIP_BACK_UP_0 if q < 0.5 else WHIP_BACK_UP_1\n"),
	("	st[\"chain\"] = PierceChainVfx.fire(battle, \"elite-chain\", WHIP_CHAIN_PX, false, fist, chest, WHIP_CHAIN_FLY, WHIP_PIERCE_OUT, life + WHIP_WINDUP_SEC,\n"
	 "		WHIP_WINDUP_SEC, back_hand, back_tip)\n",
	 "	## 出链 = 动作播到第 3 格「甩出」那刻(帧率随拉人距离变, 与 _tick_elite_whip 同一个 d); 链头仍在 WHIP_HIT_SEC 扎到\n"
	 "	var pre: float = 2.0 / whip_anim_fps(DetMath.dist((tgt[\"pos\"] as Vector2), u[\"pos\"]))\n"
	 "	var fly: float = clampf(WHIP_HIT_SEC - pre, 0.06, WHIP_CHAIN_FLY)\n"
	 "	st[\"chain\"] = PierceChainVfx.fire(battle, \"elite-chain\", WHIP_CHAIN_PX, false, fist, chest, fly, WHIP_PIERCE_OUT, life + pre,\n"
	 "		pre, back_hand, back_tip)\n"),
])
patch("scripts/scenes/RealtimeBattle3DScene.gd", [
	("	var whip_links: Array = _elite_sys.whip_chain(u, tgt,   # 穿刺链(11-11): 后甩前摇 WHIP_WINDUP_SEC 后从拳头射出\n",
	 "	var whip_links: Array = _elite_sys.whip_chain(u, tgt,   # 穿刺链(11-11): 后甩带出一节拖地, 甩出那格从拳头射出\n"),
	("	_pending_shots.append({\"delay\": EliteSystem.WHIP_WINDUP_SEC + 0.14, \"fn\": func() -> void:   # 命中(链头扎中): 顿一下+目标眩晕0.4s\n",
	 "	_pending_shots.append({\"delay\": EliteSystem.WHIP_HIT_SEC, \"fn\": func() -> void:   # 命中(链头扎中): 顿一下+目标眩晕0.4s\n"),
])
print("ok")
