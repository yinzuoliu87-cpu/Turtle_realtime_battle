# -*- coding: utf-8 -*-
"""近战小将人体浪板: 链子换成穿刺链(PierceChainVfx) + 晕 / 命中挪到链头到达那一刻(2026-11-11 一次性补丁, CRLF 二进制读写)。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	n0 = b.count(b"\n")
	for old, new in pairs:
		o = old.replace("\n", "\r\n").encode("utf-8")
		w = new.replace("\n", "\r\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次 ≠ 1:\n%s" % (rel, c, old[:160]))
		b = b.replace(o, w)
	open(p, "wb").write(b)
	print("改好", rel, n0, "→", b.count(b"\n"), "行")


H = "scripts/systems/skills/hiding_system.gd"
patch(H, [
	## 常量
	('const MELEE_DIVE_SLOTS := 8.0\n',
	 'const MELEE_DIVE_SLOTS := 8.0\n'
	 '## 穿刺链(11-11 用户「链头应该是那种尖的穿刺…穿刺过敌人的身体」「当他把自己拽过去的时候，这个铁链的尖头在哪里？」):\n'
	 '##   链头 = 手上那个三刺头(vfx/melee-chain-head.png, build_melee_minion.py 从动作帧原样裁), 0.68 离开手腕、\n'
	 '##   SURF_CHAIN_FLY 秒飞到敌人胸口扎穿、拉人时钉住不动, 撞上前 SURF_CHAIN_RETRACT 秒拔出收回手腕。\n'
	 'const SURF_CHAIN_FLY := 0.1\n'
	 'const SURF_CHAIN_RETRACT := 0.1\n'
	 'const SURF_CHAIN_PX := 1.5 / 99.0      # 链环 / 链头每像素米数 = 人物图(本体 99 像素 = 1.5 米), 不出现粗细两种像素\n'
	 'const SURF_PIERCE_OUT := 0.6          # 尖端越过目标胸口多少米(从背后透出)\n'
	 'const SURF_WRIST_FWD := 24.0          # 手腕在身体前方多少码(出链帧: 护手端在腰带扣前 38 像素 ≈ 0.58 米)\n'
	 'const SURF_WRIST_UP := 0.74           # 手腕离脚底多高(米; 出链帧护手中线在脚底上 49 像素)\n'
	 'const SURF_CHEST_UP := 0.9            # 目标胸口离脚底多高(米)\n'),
	## 0.68: 免控分支 —— 链头到达才结算
	('		if battle._damage._is_cc_immune(tref):\n'
	 '			battle._surf_chain_shoot(uu["pos"], float(uu.get("height", 0.0)) + 0.6, tref["pos"], Color(0.6, 0.15, 0.15, 0.95))\n'
	 '			var _ib: float = float(tref.get("maxHp", 0.0)) * IMMUNE_BRANCH_MAXHP_PCT + float(uu.get("atk", 0.0)) * IMMUNE_BRANCH_ATK_COEF\n'
	 '			battle._damage._apply_damage_from(uu, tref,\n'
	 '				maxi(1, int(battle._resolve_dmg(uu, _ib, tref, false))), Color("#ff4444"))\n'
	 '			battle._vfx._hit_spark(tref)\n'
	 '			_minion_abort_fall(uu)                               # 不拉自己过去, 原地掉回地面\n'
	 '			return\n',
	 '		## 11-11: 伤害 / 晕都在链头到达那一刻(SURF_CHAIN_FLY 秒后)结算, 不再是射出那一刻(画面上链头还在半空敌人就已经晕了)\n'
	 '		var chain := _fire_surf_chain(uu, tref, 0.6 + surf_pull_sec(uu["pos"], tref["pos"]) + 0.5)\n'
	 '		rope.append(chain)\n'
	 '		if battle._damage._is_cc_immune(tref):\n'
	 '			battle._pending_shots.append({"delay": SURF_CHAIN_FLY, "fn": func() -> void:\n'
	 '				chain.release()\n'
	 '				if uu.get("alive", false) and tref.get("alive", false):\n'
	 '					var _ib: float = float(tref.get("maxHp", 0.0)) * IMMUNE_BRANCH_MAXHP_PCT + float(uu.get("atk", 0.0)) * IMMUNE_BRANCH_ATK_COEF\n'
	 '					battle._damage._apply_damage_from(uu, tref,\n'
	 '						maxi(1, int(battle._resolve_dmg(uu, _ib, tref, false))), Color("#ff4444"))\n'
	 '					battle._vfx._hit_spark(tref)\n'
	 '				_minion_abort_fall(uu)                               # 不拉自己过去, 原地掉回地面\n'
	 '			, "src": uu})\n'
	 '			return\n'),
	('		## 从小将(空中·当前 height)射铁索向目标: 由近到远 0.1 秒伸到, 一直留到被拽过去(11-08: 原来射出 0.42 秒就淡掉, 拉人第 1.28 秒才开始)\n'
	 '		rope.append_array(PullRopeVfx.shoot(battle, uu["pos"], float(uu.get("height", 0.0)) + 0.6, tref["pos"], 0.8,\n'
	 '			load(SURF_ROPE_TEX), SURF_ROPE_THICK, SURF_ROPE_SPACING, 0.1, 0.6 + surf_pull_sec(uu["pos"], tref["pos"]) + 0.5))\n'
	 '		battle._damage._stun(tref, SURF_STUN_SEC, "_sk_minion_bodysurf", true)   # 晕住覆盖整个空中顿+俯冲\n'
	 '		battle._vfx._hit_spark(tref)\n',
	 '		battle._pending_shots.append({"delay": SURF_CHAIN_FLY, "fn": func() -> void:   # 链头扎进胸口那一刻\n'
	 '			if uu.get("alive", false) and tref.get("alive", false):\n'
	 '				battle._damage._stun(tref, SURF_STUN_SEC, "_sk_minion_bodysurf", true)   # 晕住覆盖整个空中顿+俯冲\n'
	 '				battle._vfx._hit_spark(tref)\n'
	 '		, "src": uu})\n'),
	('			PullRopeVfx.release(battle, rope)\n'
	 '			_minion_abort_fall(uu)\n'
	 '			return\n'
	 '		_unstoppable_apply(uu)\n',
	 '			_chain_release(rope)\n'
	 '			_minion_abort_fall(uu)\n'
	 '			return\n'
	 '		_unstoppable_apply(uu)\n'),
	('		if battle._damage._is_cc_immune(tref):\n'
	 '			PullRopeVfx.release(battle, rope)\n'
	 '			_minion_abort_fall(uu)\n'
	 '			return\n'
	 '		_minion_bodysurf_ride(uu, tref, rope)',
	 '		if battle._damage._is_cc_immune(tref):\n'
	 '			_chain_release(rope)\n'
	 '			_minion_abort_fall(uu)\n'
	 '			return\n'
	 '		_minion_bodysurf_ride(uu, tref, rope)'),
	('		PullRopeVfx.reel(rope, PullCurve.frac(kk))                       # 已经被拽过的那段绳收掉(画面)\n'
	 '	PullRopeVfx.release(battle, rope)                    # 到了 / 作废: 剩下的绳段淡出\n',
	 '		if dive_sec - d <= SURF_CHAIN_RETRACT:                           # 撞上前拔出刺头收回手腕(画面; 链子随人往前飞自己变短)\n'
	 '			for c in rope:\n'
	 '				c.retract(SURF_CHAIN_RETRACT)\n'
	 '	_chain_release(rope)                                 # 到了 / 作废: 剩下的淡出\n'),
	## 辅助函数: 放在 _minion_bodysurf_ride 前面
	('func _minion_bodysurf_ride(u: Dictionary, tref: Dictionary, rope: Array = []) -> void:',
	 '## 射穿刺链(画面): 手腕 → 目标胸口, 两端每帧从单位的 pos / height 推(sim 不读)\n'
	 'func _fire_surf_chain(uu: Dictionary, tref: Dictionary, life: float) -> PierceChainVfx:\n'
	 '	var wrist := func() -> Vector3:\n'
	 '		var dv: Vector2 = (tref["pos"] as Vector2) - (uu["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return battle._world_pos((uu["pos"] as Vector2) + dn * SURF_WRIST_FWD, float(uu.get("height", 0.0)) + SURF_WRIST_UP)\n'
	 '	var chest := func() -> Vector3:\n'
	 '		return battle._world_pos(tref["pos"], float(tref.get("height", 0.0)) + SURF_CHEST_UP)\n'
	 '	return PierceChainVfx.fire(battle, "melee-chain", SURF_CHAIN_PX, true, wrist, chest, SURF_CHAIN_FLY, SURF_PIERCE_OUT, life)\n'
	 '\n'
	 '\n'
	 'func _chain_release(rope: Array) -> void:\n'
	 '	for c in rope:\n'
	 '		if c is PierceChainVfx:\n'
	 '			(c as PierceChainVfx).release()\n'
	 '	rope.clear()\n'
	 '\n'
	 '\n'
	 'func _minion_bodysurf_ride(u: Dictionary, tref: Dictionary, rope: Array = []) -> void:'),
])
