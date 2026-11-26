extends Node
## verify_mask_items.gd —— 面具 10 件逐件门禁(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md §3)
##   每件单独生效(不激活【偷脸】也有效果) —— 本测试里双方羁绊档位全是 0。
##   A 127 纸面具   物理护盾 = 最大生命值 25%(一星), 只挡物理 · 挨一段攻击朝攻击者飞纸刃, 飞到才结算(护甲 × 30% 物理)
##   B 128 狐狸面具 最大生命值差 1000 ⇒ 增伤一半, 差 ≥ 2000 ⇒ 到顶, 比自己低 ⇒ 0
##   C 129 京剧脸谱 开打红脸 → 8 秒黑脸(每段减伤 + 双抗) → 16 秒白脸(攻速) → 24 秒回红脸, 属性逐一卸干净; 红脸真伤 / 白脸偷龟能
##   D 130 舞狮头   舞狮 900 生命 · 龟能满蓄力后以 360/秒冲撞 · 途经敌人吃 200% 舞狮攻击力 + 眩晕
##   E 131 小丑面具 消耗 150 龟能的技能 ⇒ 附近敌人嘲讽 3 秒(一星) · 护盾 10% 最大生命值; 远处的敌人不嘲讽
##   F 132 鬼面     降到 50% ⇒ 潜行(不可选中) · 潜行期间回血 · 攻击现形 · 每路一次
##   G 133 防毒面具 灼烧 / 中毒 / 流血不上层 · 损失 50% 生命 ⇒ 移速 +50%, 回满血 ⇒ 还原
##   H 134 威尼斯面具 致命一击后不死 · 倒地期间不可选中 · 2.5 秒后血量 = 30% · 第二次致命照死
##   J 136 千面     第 8 秒拽人进里世界 · 两个世界互不敌对 · 每秒偷 3% · 12 秒或一方全灭回来 · 多个千面共用一个里世界
##   I 135 黄金面具 1 秒延时才落地 · 每秒真伤递增 · 一直钉到死 · 打死出 1 枚深海币 + 这件 +1 层(+20 生命 +2 攻击) · 冷却 8 秒再找下一个
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MB := preload("res://scripts/systems/equip/eq_mask_batch.gd")

var _n := 0
var _fail := 0
var _s
var _m


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array = [], dx: float = 0.0, dy: float = 0.0, kind: String = "green") -> Dictionary:
	var c: Vector2 = _s._arena_center
	var u: Dictionary = _s._spawn._make_unit(kind, side, c + Vector2((-150.0 if side == "left" else 150.0) + dx, dy))
	for k in ["shield", "flat_dr", "crit", "dodge_bonus", "armor_pen", "armor_pen_pct", "damage_reduction", "damage_amp"]:
		u[k] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	u["base_atk"] = 100.0
	u["buffs"] = []
	_s._recalc_stats(u)
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _field(units: Array) -> void:
	_s._mask_syn.reset_match()
	_s._equip_sys._mask_sys.clear_all()
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	for u in units:
		if not (u.get("equips", []) as Array).is_empty():
			_s._equip_sys._stats.apply_unit(u)


func _phys(src: Dictionary, tgt: Dictionary, base: float) -> void:
	var d: int = _s._resolve_dmg(src, base, tgt, false, false)
	_s._damage._apply_damage_from(src, tgt, d, Color.WHITE)


func _magic(src: Dictionary, tgt: Dictionary, base: float) -> void:
	var d: int = _s._resolve_dmg(src, base, tgt, true, false)
	_s._damage._apply_damage_from(src, tgt, d, Color.WHITE)


func _adv(sec: float, units: Array = [], step: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 1e-6:
		_s._t += step
		_m.tick(step)
		for u in units:
			_m.tick_unit(u, step)
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
	_s._t = 1000.0
	_m = _s._equip_sys._mask_sys
	print("=== 面具 10 件 ===")

	## ── A 127 纸面具 ──
	var me := _mk("left", ["p2eq_127"])
	var foe := _mk("right", [], 0.0, 0.0)
	_field([me, foe])
	var ps0 := float(me.get("phys_shield", 0.0))
	_ok("A 登场物理护盾 = 最大生命值 25%%(%.0f)" % (float(me["maxHp"]) * 0.25), absf(ps0 - float(me["maxHp"]) * MB.PAPER_SHIELD_PCT[0]) < 1e-3, "%.1f" % ps0)
	var hp0 := float(me["hp"])
	var c0: int = int(_m.stat["paper_counter"])
	_magic(foe, me, 200.0)
	var after_mag := float(me.get("phys_shield", 0.0))
	_ok("A 魔法伤害不碰物理护盾、直接掉血", after_mag == ps0 and float(me["hp"]) < hp0, "盾 %.0f→%.0f · 血 %.0f→%.0f" % [ps0, after_mag, hp0, float(me["hp"])])
	hp0 = float(me["hp"])
	_phys(foe, me, 200.0)
	_ok("A 物理伤害先扣物理护盾, 血不掉", float(me.get("phys_shield", 0.0)) < ps0 and absf(float(me["hp"]) - hp0) < 1e-3,
		"盾 %.0f→%.0f · 血 %.0f→%.0f" % [ps0, float(me.get("phys_shield", 0.0)), hp0, float(me["hp"])])
	var fh0 := float(foe["hp"])
	var hit_at := -1.0
	var t_start := float(_s._t)
	for i in range(60):
		_adv(0.05)
		if float(foe["hp"]) < fh0 and hit_at < 0.0:
			hit_at = float(_s._t) - t_start
	var want_c: float = float(me["def"]) * MB.PAPER_COUNTER[0]
	_ok("A 挨两段(魔法 + 物理)各掷一片纸刃 ⇒ 飞过去才结算(用时 %.2f 秒, 距离 %.0f / 速度 %.0f), 每片 = 护甲 %.0f × 30%%(过对方护甲, 至少 1)" % [hit_at, 300.0, MB.PAPER_SPD, float(me["def"])],
		int(_m.stat["paper_counter"]) == c0 + 2 and hit_at > 0.2 and fh0 - float(foe["hp"]) > 0.5 and fh0 - float(foe["hp"]) <= 2.0 * (want_c + 1.0),
		"反击 %d 次 · 敌掉血 %.1f(上限 %.1f)" % [int(_m.stat["paper_counter"]) - c0, fh0 - float(foe["hp"]), want_c])

	## ── B 128 狐狸面具 ──
	me = _mk("left", ["p2eq_128"])
	var big := _mk("right")
	_field([me, big])
	me["maxHp"] = 3000.0
	var amps := {}
	for diff in [-500.0, 0.0, 1000.0, 2000.0, 4000.0]:
		big["maxHp"] = 3000.0 + diff
		amps[diff] = MB.fox_amp(me, big)
	_ok("B 差 1000 ⇒ 一半(7.5%) · 差 2000 / 4000 ⇒ 到顶 15% · 不比自己高 ⇒ 0",
		amps[-500.0] == 0.0 and amps[0.0] == 0.0 and absf(amps[1000.0] - 0.075) < 1e-6 and absf(amps[2000.0] - 0.15) < 1e-6 and absf(amps[4000.0] - 0.15) < 1e-6, str(amps))
	big["maxHp"] = 5000.0
	var d_fox: int = _s._resolve_dmg(me, 1000.0, big, true, false)
	me.erase("_fox_max")
	var d_plain: int = _s._resolve_dmg(me, 1000.0, big, true, false)
	_ok("B 真走伤害结算: 1000 ⇒ ×1.15", absf(float(d_fox) / float(d_plain) - 1.15) < 0.01, "%d / %d" % [d_fox, d_plain])

	## ── C 129 京剧脸谱 ──
	me = _mk("left", ["p2eq_129"])
	foe = _mk("right")
	_field([me, foe])
	var ck: String = _s._equip_sys.key_of(me, "p2eq_129")
	var f0 := int(me["_mask_acc"].get("face:" + ck, -1))
	var def0 := float(me["def"])
	var asp0 := float(me.get("aspd_perm", 1.0))
	_adv(8.02, [me])
	var f1 := int(me["_mask_acc"].get("face:" + ck, -1))
	var blk := [float(me.get("flat_dr", 0.0)), float(me["def"]) - def0]
	_adv(8.0, [me])
	var f2 := int(me["_mask_acc"].get("face:" + ck, -1))
	var wht := [float(me.get("flat_dr", 0.0)), float(me["def"]) - def0, float(me.get("aspd_perm", 1.0)) - asp0]
	_adv(8.0, [me])
	var f3 := int(me["_mask_acc"].get("face:" + ck, -1))
	_ok("C 红(0) → 8 秒黑(1) → 16 秒白(2) → 24 秒红(0)", [f0, f1, f2, f3] == [0, 1, 2, 0], str([f0, f1, f2, f3]))
	_ok("C 黑脸: 每段减伤 5 + 护甲 10 · 换白脸卸掉、加攻速 15% · 回红脸全还原",
		blk == [5.0, 10.0] and absf(wht[0]) < 1e-6 and absf(wht[1]) < 1e-6 and absf(wht[2] - 0.15) < 1e-6
		and absf(float(me.get("flat_dr", 0.0))) < 1e-6 and absf(float(me["def"]) - def0) < 1e-6 and absf(float(me.get("aspd_perm", 1.0)) - asp0) < 1e-6,
		"黑 %s · 白 %s" % [str(blk), str(wht)])
	foe["hp"] = 5000.0
	_m.on_basic(me, foe, "p2eq_129", 0)
	var want_red: float = roundf(float(me["atk"]) * 0.08)
	_ok("C 红脸攻击额外真伤 = 攻击力 %.0f × 8%% = %.0f" % [float(me["atk"]), want_red], absf(5000.0 - float(foe["hp"]) - want_red) < 1e-3, "%.1f" % (5000.0 - float(foe["hp"])))
	_adv(16.0, [me])
	foe["energy"] = 50.0
	me["energy"] = 0.0
	_m.on_basic(me, foe, "p2eq_129", 0)
	_ok("C 白脸攻击偷 3 点龟能(用户「改成三五八」)", absf(float(foe["energy"]) - 47.0) < 1e-6 and absf(float(me["energy"]) - 3.0) < 1e-6,
		"敌 %.0f · 我 %.0f" % [float(foe["energy"]), float(me["energy"])])

	## ── D 130 舞狮头 ──
	me = _mk("left", ["p2eq_130"], -200.0)
	foe = _mk("right", [], -150.0)
	foe["pos"] = Vector2(me["pos"]) + Vector2(250.0, 0.0)
	_field([me, foe])
	var L: Dictionary = _m.lion_state(0)
	var lion: Dictionary = L.get("u", {})
	_ok("D 召唤舞狮: 生命 900(用户定)、攻击 20", not lion.is_empty() and absf(float(lion["maxHp"]) - 900.0) < 1e-3 and absf(float(lion["base_atk"]) - 20.0) < 1e-3,
		"%s" % ("无" if lion.is_empty() else "%.0f / %.0f" % [float(lion["maxHp"]), float(lion["base_atk"])]))
	lion["pos"] = Vector2(me["pos"]) + Vector2(20.0, 0.0)
	lion["target"] = foe
	L["en"] = MB.LION_EN_MAX
	var p0 := Vector2(lion["pos"])
	_adv(MB.LION_WINDUP + 0.05)
	var p_wind := Vector2(lion["pos"])
	_adv(0.5)
	var moved: float = Vector2(lion["pos"]).distance_to(p_wind)
	_adv(1.0)
	var fdmg := 5000.0 - float(foe["hp"])
	_ok("D 蓄力期间不动 · 冲起来 0.5 秒走 %.0f(≈ 360 × 0.5, 不是一闪而过)" % moved, p_wind.distance_to(p0) < 1.0 and moved > 150.0 and moved < 200.0, "蓄力位移 %.1f" % p_wind.distance_to(p0))
	var want_l: int = _s._resolve_dmg(lion, 2.0 * float(lion["atk"]), foe, false, false)
	_ok("D 途经的敌人吃一次冲撞(%d ≈ 200%% 舞狮攻击力过护甲) + 眩晕" % want_l, int(_m.stat["lion_hit"]) == 1 and fdmg > 0.0 and float(foe.get("stun_until", 0.0)) > 1000.0,
		"命中 %d · 掉血 %.0f · 眩晕到 %.2f" % [int(_m.stat["lion_hit"]), fdmg, float(foe.get("stun_until", 0.0))])

	## ── E 131 小丑面具 ──
	me = _mk("left", ["p2eq_131"])
	var near := _mk("right", [], -200.0)
	near["pos"] = Vector2(me["pos"]) + Vector2(200.0, 0.0)
	var far := _mk("right", [], 0.0, 0.0)
	far["pos"] = Vector2(me["pos"]) + Vector2(900.0, 0.0)
	_field([me, near, far])
	var sh0 := float(me.get("shield", 0.0))
	_m.on_unit_cast(me, near, "x", 150.0, false)
	_ok("E 150 龟能 ⇒ 附近敌人嘲讽 3 秒(一星 2 秒 / 100 龟能), 远处的不嘲讽 · 护盾 = 10%% 最大生命值",
		is_same(near.get("taunt_by"), me) and absf(float(near["taunt_until"]) - (_s._t + 3.0)) < 1e-6 and not is_same(far.get("taunt_by"), me)
		and absf(float(me.get("shield", 0.0)) - sh0 - float(me["maxHp"]) * 0.1) < 1.0,
		"近 %.2f 秒 · 远 %s · 盾 +%.0f" % [float(near.get("taunt_until", 0.0)) - _s._t, str(far.get("taunt_by") != null), float(me.get("shield", 0.0)) - sh0])

	## ── F 132 鬼面 ──
	me = _mk("left", ["p2eq_132"])
	foe = _mk("right")
	_field([me, foe])
	me["hp"] = float(me["maxHp"]) * 0.49
	var h1 := float(me["hp"])
	_adv(1.0, [me])
	var hidden: bool = bool(me.get("_ghost_hidden", false)) and _s._is_untargetable(me)
	var regen := float(me["hp"]) - h1
	_m.on_any_basic(me, foe)
	var revealed: bool = not bool(me.get("_ghost_hidden", false)) and not _s._is_untargetable(me)
	me["hp"] = float(me["maxHp"]) * 0.3
	_adv(0.5, [me])
	_ok("F 降到 50%% ⇒ 潜行不可选中 · 1 秒回 %.0f(≈ 3%% 最大生命值) · 攻击现形 · 再掉血不会第二次潜行" % regen,
		hidden and regen > 120.0 and regen < 180.0 and revealed and not bool(me.get("_ghost_hidden", false)), "潜 %s · 现 %s" % [str(hidden), str(revealed)])

	## ── G 133 防毒面具 ──
	me = _mk("left", ["p2eq_133"])
	foe = _mk("right")
	_field([me, foe])
	for ty in ["burn", "poison", "bleed"]:
		_s._damage._apply_dot_stacks(me, ty, 20, foe)
	var stacks: Dictionary = me.get("dot_stacks", {})
	var mp0 := float(me.get("move_perm", 1.0))
	me["hp"] = float(me["maxHp"]) * 0.5
	_adv(0.05, [me])
	var mp_half := float(me.get("move_perm", 1.0)) - mp0
	me["hp"] = float(me["maxHp"])
	_adv(0.05, [me])
	_ok("G 灼烧 / 中毒 / 流血都不上层 · 损失 50%% ⇒ 移速 +%.0f%% · 回满还原" % (mp_half * 100.0),
		int(stacks.get("burn", 0)) == 0 and int(stacks.get("poison", 0)) == 0 and int(stacks.get("bleed", 0)) == 0 and absf(mp_half - 0.5) < 1e-6
		and absf(float(me.get("move_perm", 1.0)) - mp0) < 1e-6, str(stacks))

	## ── H 134 威尼斯面具 ──
	me = _mk("left", ["p2eq_134"])
	foe = _mk("right")
	_field([me, foe])
	me["hp"] = 100.0
	_s._damage._apply_damage_from(foe, me, 999, Color.WHITE, 0.0, true)
	var down_alive := bool(me.get("alive", false))
	var down_untg: bool = _s._is_untargetable(me)
	_adv(1.25)
	var mid := float(me["hp"])
	_adv(1.3)
	var up := float(me["hp"])
	_s._damage._apply_damage_from(foe, me, 999999, Color.WHITE, 0.0, true)
	_ok("H 致命一击不死、倒地不可选中 · 1.25 秒时 %.0f(涨到一半) · 2.5 秒后 %.0f = 30%% · 第二次致命照死" % [mid, up],
		down_alive and down_untg and mid > 600.0 and mid < 900.0 and absf(up - float(me["maxHp"]) * 0.3) < 1.0 and not bool(me.get("alive", true)),
		"活 %s · 不可选 %s" % [str(down_alive), str(down_untg)])

	## ── I 135 黄金面具 ──
	me = _mk("left", ["p2eq_135"])
	foe = _mk("right", [], 200.0)
	var foe2 := _mk("right", [], 300.0, 100.0)
	_field([me, foe, foe2])
	var hp_me0 := float(me["maxHp"])
	var atk_me0 := float(me["base_atk"])
	me["target"] = foe
	foe["maxHp"] = 4000.0
	foe["hp"] = 4000.0
	_adv(0.5)
	var early := 4000.0 - float(foe["hp"])
	_adv(0.55)
	var B: Dictionary = _m.beam_state(0)
	_ok("I 金光 1 秒延时: 0.5 秒时没伤害 · 1.05 秒时落地钉住当前攻击目标", early == 0.0 and str(B.get("state", "")) == "beam" and is_same(B.get("tgt"), foe),
		"0.5 秒掉 %.0f · 状态 %s" % [early, str(B.get("state", ""))])
	var h_a := float(foe["hp"])
	_adv(1.0)
	var s1 := h_a - float(foe["hp"])
	h_a = float(foe["hp"])
	_adv(1.0)
	var s2 := h_a - float(foe["hp"])
	var base_dps: float = MB.GOLD_FLAT[0] + MB.GOLD_PCT[0] * 4000.0
	_ok("I 每秒真伤(%.0f) 逐秒递增(第二秒 ≈ ×1.2)" % base_dps, s1 > base_dps * 0.95 and s2 > s1 * 1.1, "第一秒 %.0f · 第二秒 %.0f" % [s1, s2])
	var coins0: int = EquipTickSystem.match_minted(_s, "left")
	for i in range(400):
		_adv(0.25)
		if not foe.get("alive", false):
			break
	B = _m.beam_state(0)
	_ok("I 一直钉到死 · 打死出 1 枚深海币(进本场铸币出口) · 这件 +1 层(+20 生命 +2 攻击) · 进 8 秒冷却",
		not foe.get("alive", false) and EquipTickSystem.match_minted(_s, "left") == coins0 + 1 and absf(float(me["maxHp"]) - hp_me0 - 20.0) < 1e-3
		and absf(float(me["base_atk"]) - atk_me0 - 2.0) < 1e-3 and str(B.get("state", "")) == "cd",
		"币 %d→%d · 生命 +%.0f · 攻击 +%.0f · %s" % [coins0, EquipTickSystem.match_minted(_s, "left"), float(me["maxHp"]) - hp_me0, float(me["base_atk"]) - atk_me0, str(B.get("state", ""))])
	_adv(7.5)
	var still_cd := str(_m.beam_state(0).get("state", "")) == "cd"
	_adv(1.0)
	B = _m.beam_state(0)
	_ok("I 冷却 8 秒内不出手 · 之后钉下一个(foe2)", still_cd and is_same(B.get("tgt"), foe2), "7.5 秒仍冷却 %s · 新目标 %s" % [str(still_cd), str(is_same(B.get("tgt"), foe2))])

	## ── J 136 千面【里世界】 ──
	me = _mk("left", ["p2eq_136"])
	var e1 := _mk("right", [], 0.0, -150.0)
	var e2 := _mk("right", [], 0.0, 0.0)
	var e3 := _mk("right", [], 0.0, 150.0)
	var stay := _mk("left", [], -200.0, 250.0)   # 留在主世界的队友(否则携带者一进去, 主世界我方就空了 ⇒ 按 11-26 规则里世界当场关)
	_field([me, e1, e2, e3, stay])
	var ow = _m.ow
	_s._sd_t0 = _s._t
	_adv(7.9)
	var before: bool = bool(ow.active)
	_adv(0.4)
	var grabbing: bool = not bool(ow.active) and not bool(me.get("_ow", false))
	_adv(0.4)
	var vic = null
	for o in [e1, e2, e3]:
		if bool(o.get("_ow", false)):
			vic = o
	var others: Array = []
	for o in [e1, e2, e3]:
		if not is_same(o, vic):
			others.append(o)
	_ok("J 开打第 8 秒(7.9 秒还没有)先抓 0.6 秒(8.3 秒还在主世界), 8.7 秒把一名敌人拽进里世界, 自己也进去",
		not before and grabbing and bool(ow.active) and bool(me.get("_ow", false)) and vic is Dictionary,
		"7.9 秒 %s · 8.3 秒抓取中 %s · 拽 %s" % [str(before), str(grabbing), str(vic is Dictionary)])
	_ok("J 主世界的敌人不再把它当敌人(选不到、范围伤害也打不到) · 里世界里两人互为敌人",
		not _s._is_hostile(others[0], me) and not _s._is_hostile(me, others[0]) and _s._is_hostile(me, vic) and _s._is_hostile(vic, me)
		and not _s._targeting._enemies_of(others[0]).has(me))
	var a_me0 := float(me["base_atk"])
	var a_v0 := float((vic as Dictionary)["base_atk"])
	var d_v0 := float((vic as Dictionary)["base_def"])
	_adv(1.0)
	_ok("J 每秒偷对方 3%% 攻击力(一星): 我 +%.1f · 对方 -%.1f" % [float(me["base_atk"]) - a_me0, a_v0 - float((vic as Dictionary)["base_atk"])],
		absf(float(me["base_atk"]) - a_me0 - a_v0 * 0.03) < 1e-3 and absf(a_v0 - float((vic as Dictionary)["base_atk"]) - a_v0 * 0.03) < 1e-3)
	_adv(11.2)
	var after_atk := float(me["base_atk"])
	_ok("J 12 秒到 ⇒ 两人回主世界(偷到的留着: 攻击力仍比进去前高 %.1f)" % (after_atk - a_me0),
		not bool(ow.active) and not bool(me.get("_ow", false)) and not bool((vic as Dictionary).get("_ow", false)) and ow.last_close_reason == "time"
		and after_atk > a_me0 + a_v0 * 0.25 and _s._is_hostile(others[0], me), "原因 %s" % ow.last_close_reason)
	## 两边各带一件 + 一方在里面全灭 ⇒ 提前结束
	me = _mk("left", ["p2eq_136"])
	var fo := _mk("right", ["p2eq_136"])
	var m2 := _mk("left", [], 0.0, 200.0)
	var fo2 := _mk("right", [], 0.0, 200.0)
	var sl := _mk("left", [], -300.0, -250.0)
	var sr := _mk("right", [], 300.0, -250.0)
	sl["_isEgg"] = false
	_field([me, fo, m2, fo2, sl, sr])
	## 留守的两只不许被拽: 先挂上 _egg_fence(千面不挑它们), 只为让主世界两边都还有人
	sl["_egg_fence"] = true
	sr["_egg_fence"] = true
	ow = _m.ow
	var open0: int = int(ow.stat["open"])
	_s._sd_t0 = _s._t
	_adv(8.7)
	## 两边各拽一个随机敌人: 挑中的可能正是对面的携带者(那就只有 2 人), 也可能是别人(3~4 人) —— 都合法。
	##   判据只看规则本身: 只开了一个里世界, 两个携带者都在里面(11-26 夜: 原来要求 ≥ 3 人, 随机序列一变就红)
	var both_in := WS_has(ow.members, me) and WS_has(ow.members, fo)
	_ok("J 两边各带千面 ⇒ 只开一个里世界, 两个携带者和各自拽的人全进来(%d 人)" % ow.members.size(), int(ow.stat["open"]) == open0 + 1 and both_in and ow.members.size() >= 2, str(ow.members.size()))
	for mm in ow.members:
		if str(mm.get("side", "")) == "right":
			mm["hp"] = 0.0
			_s._kill(mm)
	_adv(0.1)
	_ok("J 里世界里一方全灭 ⇒ 决斗提前结束, 剩下的回主世界", not bool(ow.active) and ow.last_close_reason == "wipe", "原因 %s" % ow.last_close_reason)

	## 主世界一方打完 ⇒ 里世界马上消失, 人全部出来(用户 11-26)
	me = _mk("left", ["p2eq_136"])
	var ea := _mk("right", [], 0.0, -100.0)
	var eb := _mk("right", [], 0.0, 100.0)
	var stay2 := _mk("left", [], -200.0, 250.0)
	_field([me, ea, eb, stay2])
	ow = _m.ow
	_s._sd_t0 = _s._t
	_adv(8.7)
	var opened: bool = bool(ow.active)
	for o in [ea, eb]:
		if not bool(o.get("_ow", false)):
			o["hp"] = 0.0
			_s._kill(o)
	_adv(0.1)
	_ok("J 主世界那边一方全灭(里世界里还有人) ⇒ 里世界马上关、人全部出来", opened and not bool(ow.active) and ow.last_close_reason == "main_over"
		and not bool(me.get("_ow", false)), "原因 %s" % ow.last_close_reason)

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 面具 10 件 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


static func WS_has(arr: Array, u: Dictionary) -> bool:
	for x in arr:
		if is_same(x, u):
			return true
	return false
