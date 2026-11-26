extends Node
## verify_spear_items.gd —— 长矛 10 件逐件门禁(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md §4)
##   每件单独生效(双方羁绊档位都是 0)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SB := preload("res://scripts/systems/equip/eq_spear_batch.gd")

var _n := 0
var _fail := 0
var _s
var _b


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, dy: float = 0.0) -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, dy))
	for k in ["shield", "crit", "dodge_bonus", "damage_reduction", "damage_amp", "armor_pen", "armor_pen_pct"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	u["airborne"] = false
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_b.clear_all()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_b.tick(step)
		for u in units:
			_b.tick_unit(u, step)
		_s._ballistics._step_flights(step)
		t += step


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._t = 3000.0
	_b = _s._equip_sys._spear_sys
	print("=== 长矛 10 件 ===")

	## 137 竹矛(11-26 夜改): 第 3 下 ⇒ 朝最远的敌人方向推出一道竹刺浪, 按速度走, 路径上每个敌人各吃一次
	_s._battle_rng.seed = 1234
	var me := _mk("left", ["p2eq_137"])
	var t1 := _mk("right", [], 0.0, 0.0)
	var t2 := _mk("right", [], 0.0, 0.0)
	var off := _mk("right", [], 0.0, 0.0)
	_field([me, t1, t2, off])
	t1["pos"] = Vector2(me["pos"]) + Vector2(80.0, 0.0)
	t2["pos"] = Vector2(me["pos"]) + Vector2(400.0, 0.0)
	off["pos"] = Vector2(me["pos"]) + Vector2(200.0, 200.0)
	_s._basic_attack(me, t1)
	_s._basic_attack(me, t1)
	var w0 := int(_b.stat["bamboo"])
	var h_t2 := float(t2["hp"])
	var h_off := float(off["hp"])
	_s._basic_attack(me, t1)
	var at_once := h_t2 - float(t2["hp"])
	_adv(0.8, [me])
	_ok("137 竹矛: 前两下没有浪, 第 3 下出手时 400 码外还没挨, 浪推过去才吃 60% 攻击力, 线外的不吃",
		w0 == 0 and int(_b.stat["bamboo"]) == 1 and at_once == 0.0 and absf(h_t2 - float(t2["hp"]) - float(_s._phys_after_armor(me, 0.6 * float(me["atk"]), t2))) < 1.5 and float(off["hp"]) == h_off,
		"浪 %d→%d · 出手时 %.0f · 推过去 %.0f · 线外 %.0f" % [w0, int(_b.stat["bamboo"]), at_once, h_t2 - float(t2["hp"]), h_off - float(off["hp"])])

	## 138 鱼叉: 每 10 秒(一星)射向本场伤害最多的敌人; 飞到才中: 魔法伤害 + 眩晕 1.5 秒 + 每 0.5 秒拉近
	me = _mk("left", ["p2eq_138"])
	var low := _mk("right", [], 0.0, -100.0)
	var high := _mk("right", [], 300.0, 100.0)
	_field([me, low, high])
	high["_st_dealt"] = 5000
	low["_st_dealt"] = 100
	_adv(10.02, [me])
	var hh0 := float(high["hp"])
	var d0 := DetMath.dist(Vector2(high["pos"]), Vector2(me["pos"]))
	_adv(0.5, [me])
	var hit_dmg := hh0 - float(high["hp"])
	var stunned: bool = float(high.get("stun_until", 0.0)) > _s._t
	_adv(1.6, [me])
	var pulled := d0 - DetMath.dist(Vector2(high["pos"]), Vector2(me["pos"]))
	var want_m: int = _s._resolve_dmg(me, 40.0, high, true, false)
	_ok("138 鱼叉: 第 10 秒射向伤害最多的那只, 飞到后 40 魔法伤害 + 眩晕, 1.5 秒里被拉近约 120 码, 另一只不挨",
		int(_b.stat["harpoon_hit"]) == 1 and absf(hit_dmg - float(want_m)) < 1.5 and stunned and absf(pulled - 120.0) < 25.0 and float(low["hp"]) == 5000.0,
		"命中 %d · 伤 %.0f · 眩晕 %s · 拉近 %.0f" % [int(_b.stat["harpoon_hit"]), hit_dmg, str(stunned), pulled])
	## 11-27: 目标免控(153 黄色筹码 / 免控窗口) ⇒ 眩晕打不上, 也不往回拽(原来照拽)
	me = _mk("left", ["p2eq_138"])
	high = _mk("right", [], 300.0, 100.0)
	_field([me, high])
	high["cc_immune_until"] = 1.0e12
	high["_st_dealt"] = 5000
	var nh0 := int(_b.stat["harpoon_hit"])
	_adv(10.02, [me])
	var d1 := DetMath.dist(Vector2(high["pos"]), Vector2(me["pos"]))
	_adv(2.1, [me])
	var pulled1 := d1 - DetMath.dist(Vector2(high["pos"]), Vector2(me["pos"]))
	_ok("138 鱼叉: 目标免控 ⇒ 叉中了但不晕、不被拽(拉近 %.0f)" % pulled1,
		int(_b.stat["harpoon_hit"]) == nh0 + 1 and absf(pulled1) < 1.0 and float(high.get("stun_until", 0.0)) <= _s._t, "命中 %d" % int(_b.stat["harpoon_hit"]))

	## 139 标枪: 每 6 秒最远的; 飞到才打: 150% 物理 + 流血
	me = _mk("left", ["p2eq_139"])
	var nearf := _mk("right", [], 0.0, 0.0)
	var farf := _mk("right", [], 600.0, 0.0)
	_field([me, nearf, farf])
	var fh := float(farf["hp"])
	_adv(6.02, [me])
	var thrown := int(_b.stat["jav"])
	var instant := fh - float(farf["hp"])
	_adv(1.0, [me])
	var bleed := int((farf.get("dot_stacks", {}) as Dictionary).get("bleed", 0))
	_ok("139 标枪: 第 6 秒掷向最远的, 出手时没伤害, 飞到才打 150% 物理并挂上 50 层流血",
		thrown == 1 and instant == 0.0 and fh - float(farf["hp"]) >= 1.5 * float(me["atk"]) - 1.0 and bleed > 0,
		"掷 %d · 出手 %.0f · 到后 %.0f · 流血 %d" % [thrown, instant, fh - float(farf["hp"]), bleed])

	## 140 骑枪: 走够 400 码攒满 ⇒ 下一击多 120% 物理 + 击飞眩晕 + 回 15 龟能; 再下一击回到普通
	me = _mk("left", ["p2eq_140"])
	t1 = _mk("right")
	_field([me, t1])
	_b.on_spawn(me, "p2eq_140", 0)
	var half_way := 0.0
	for k in range(9):
		me["pos"] = Vector2(me["pos"]) + Vector2(-50.0, 0.0)
		_adv(0.05, [me])
		if k == 3:
			half_way = _b._acc(me, "lance:" + _s._equip_sys.key_of(me, "p2eq_140"))
	me["pos"] = Vector2(t1["pos"]) - Vector2(80.0, 0.0)
	me["_lance_from"] = Vector2(me["pos"])
	me["energy"] = 0.0
	var h0 := float(t1["hp"])
	_s._basic_attack(me, t1)
	var with_lance := h0 - float(t1["hp"])
	var stun_ok: bool = float(t1.get("stun_until", 0.0)) > _s._t
	var en_got := float(me.get("energy", 0.0)) + float(me.get("energy_bank", 0.0))
	h0 = float(t1["hp"])
	_s._basic_attack(me, t1)
	var plain := h0 - float(t1["hp"])
	_ok("140 骑枪: 走 200 码只攒一半, 走够 400 码下一击多 120% + 眩晕 + 回龟能, 再下一击回到普通",
		absf(half_way - 200.0) < 1.0 and absf((with_lance - plain) - 1.2 * float(me["atk"])) < 2.0 and stun_ok and en_got >= 15.0,
		"半程 %.0f · 冲阵 %.0f / 普通 %.0f · 眩晕 %s · 龟能 %.0f" % [half_way, with_lance, plain, str(stun_ok), en_got])

	## 141 长戟: 每隔一次攻击间隔朝最近的敌人横扫前方 120° 扇形(半径 = 射程, 近战 +100), 只这一个效果
	me = _mk("left", ["p2eq_141"])
	t1 = _mk("right", [], 0.0, 0.0)
	var side_f := _mk("right", [], 0.0, 0.0)
	var back_f := _mk("right", [], 0.0, 0.0)
	_field([me, t1, side_f, back_f])
	t1["pos"] = Vector2(me["pos"]) + Vector2(60.0, 0.0)
	side_f["pos"] = Vector2(me["pos"]) + Vector2(60.0, 60.0)
	back_f["pos"] = Vector2(me["pos"]) - Vector2(90.0, 0.0)
	var hs := float(side_f["hp"])
	var hk := float(back_f["hp"])
	var guard := 0
	while int(_b.stat["halb"]) == 0 and guard < 200:
		guard += 1
		_adv(0.05, [me])
	_ok("141 长戟: 到攻击间隔横扫一次, 前方扇形里的吃 35%, 身后的不吃",
		int(_b.stat["halb"]) == 1 and absf(hs - float(side_f["hp"]) - 0.35 * float(me["atk"])) < 1.5 and hk == float(back_f["hp"]),
		"扫 %d · 前 %.0f · 后 %.0f" % [int(_b.stat["halb"]), hs - float(side_f["hp"]), hk - float(back_f["hp"])])

	## 142 盾矛: 第 8 秒举盾 4 秒(每段减 15 并存下); 放盾: 存下的 30% 转护盾 + 冲击波(存下的 50% 魔法, 前方敌人分摊)
	me = _mk("left", ["p2eq_142"])
	var front := _mk("right", [], 0.0, 0.0)
	_field([me, front])
	front["pos"] = Vector2(me["pos"]) + Vector2(150.0, 0.0)
	_adv(8.02, [me])
	var raised := int(_b.stat["shsp_raise"])
	var hm := float(me["hp"])
	_s._damage._apply_damage_from(front, me, 100, Color.WHITE)
	var blocked := hm - float(me["hp"])
	var hf0 := float(front["hp"])
	_adv(4.0, [me])
	var sh_got := float(me.get("shield", 0.0))
	_adv(0.5, [me])
	_ok("142 盾矛: 第 8 秒举盾, 100 伤害只掉 85; 放盾得 30 护盾, 冲击波飞到前面那只打 50 魔法",
		raised == 1 and absf(blocked - 85.0) < 1.0 and absf(sh_got - 30.0) < 1.5 and absf(hf0 - float(front["hp"]) - 50.0) < 1.5,
		"举 %d · 掉 %.0f · 盾 %.0f · 波 %.0f" % [raised, blocked, sh_got, hf0 - float(front["hp"])])

	## 143 方天画戟: 受到最大生命 30% 的伤害攒满 ⇒ 1 秒后(蓄力 + 跃起)砸地: 半径内吃 100% 物理并击飞; 之后 4 秒攻击带一圈横扫并回血
	me = _mk("left", ["p2eq_143"])
	var a1 := _mk("right", [], 0.0, 0.0)
	var a2 := _mk("right", [], 0.0, 0.0)
	_field([me, a1, a2])
	a1["pos"] = Vector2(me["pos"]) + Vector2(80.0, 0.0)
	a2["pos"] = Vector2(me["pos"]) + Vector2(0.0, 200.0)
	for _i in range(16):
		_s._damage._apply_damage_from(a1, me, 100, Color.WHITE)
	var started := int(_b.stat["ftj"])
	var ha2 := float(a2["hp"])
	_adv(0.9, [me])
	var early := ha2 - float(a2["hp"])
	_adv(0.2, [me])
	var slam := ha2 - float(a2["hp"])
	var air: bool = bool(a2.get("airborne", false))
	me["hp"] = 2000.0
	var meh0 := float(me["hp"])
	var ha1 := float(a1["hp"])
	_s._basic_attack(me, a1)
	var spin_extra := ha1 - float(a1["hp"]) - float(me["atk"])
	_ok("143 方天画戟: 挨满 1500 才起跳, 落地前不结算, 落地 200 码外那只吃 100% 并被击飞; 之后攻击多一圈 30% 横扫 + 回 30 生命",
		started == 1 and early == 0.0 and absf(slam - float(me["atk"])) < 1.5 and air and absf(spin_extra - 0.3 * float(me["atk"])) < 2.0 and float(me["hp"]) - meh0 >= 29.0,
		"起跳 %d · 落地前 %.0f · 砸 %.0f · 击飞 %s · 横扫 %.0f · 回 %.0f" % [started, early, slam, str(air), spin_extra, float(me["hp"]) - meh0])

	## 144 投矛器: 第 10 秒朝最密集的那只周围落 8 根矛(落点全在 180 码内); 落地前不结算, 落地才中
	_s._battle_rng.seed = 4321
	me = _mk("left", ["p2eq_144"])
	var grp: Array = [_mk("right"), _mk("right"), _mk("right"), _mk("right")]
	_field([me] + grp)
	for gi in range(3):
		grp[gi]["pos"] = Vector2(me["pos"]) + Vector2(300.0 + 20.0 * float(gi), -20.0 + 20.0 * float(gi))
	grp[3]["pos"] = Vector2(me["pos"]) + Vector2(0.0, -400.0)
	_adv(10.02, [me])
	var nd := (_b._drops as Array).size()
	var c0: Vector2 = Vector2(_b._drops[0]["at"]) if nd > 0 else Vector2.ZERO   # 第一根正落在被选中的那只身上
	var far_ok := false
	for gi2 in range(3):
		if DetMath.dist(c0, Vector2(grp[gi2]["pos"])) < 1.0:
			far_ok = true   # 圆心是扎堆那三只之一(不是离群那只)
	for d in _b._drops:
		if DetMath.dist(Vector2(d["at"]), c0) > 130.0 + 25.0:
			far_ok = false
	var hits0 := int(_b.stat["atl_hit"])
	_adv(1.5, [me])
	_ok("144 投矛器: 第 10 秒在敌群那一圈落 8 根矛(第一根正落在目标身上), 出手时不结算, 落地后命中, 离群那只不挨",
		int(_b.stat["atl"]) == 1 and nd == 8 and far_ok and hits0 == 0 and int(_b.stat["atl_hit"]) >= 2 and float(grp[3]["hp"]) == 5000.0,
		"批 %d · 矛 %d · 落点都在圈内 %s · 出手时 %d · 落地后 %d" % [int(_b.stat["atl"]), nd, str(far_ok), hits0, int(_b.stat["atl_hit"])])

	## 145 永恒之枪
	me = _mk("left", ["p2eq_145"])
	var small := _mk("right", [], 0.0, -80.0)
	var big := _mk("right", [], 300.0, 80.0)
	_field([me, small, big])
	big["maxHp"] = 9000.0
	big["hp"] = 9000.0
	_adv(8.02, [me])
	var hb2 := float(big["hp"])
	_adv(1.0, [me])
	var want: int = _s._phys_after_armor(me, 9000.0 * 0.08, big)
	_ok("145 永恒之枪: 第 8 秒掷向血最多的, 飞到才打: 目标最大生命 8% 物理 + 钉住 1.5 秒",
		int(_b.stat["eternal_hit"]) == 1 and absf(hb2 - float(big["hp"]) - float(want)) < 1.5 and float(big.get("stun_until", 0.0)) > _s._t and float(small["hp"]) == 5000.0,
		"命中 %d · 掉 %.0f(应 %d)" % [int(_b.stat["eternal_hit"]), hb2 - float(big["hp"]), want])

	## 146 圣枪: 11-26 晚重做成坦克装, 单独一份门禁 tests/verify_holy_spear.gd(17 条)

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 长矛 10 件 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
