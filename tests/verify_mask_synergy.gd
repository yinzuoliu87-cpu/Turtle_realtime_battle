extends Node
## verify_mask_synergy.gd —— 面具羁绊【偷脸】(2026-11-25 · 方案书 docs/plans/20261125c-面具羁绊.md)
##   A 档位偷几只: 1 / 2 / 3; 对面活着的不够就有几只偷几只; 龟蛋 / 召唤物 / 训龟大师 / 别人的复制体不偷
##   B 复制体属性: 最大生命值 / 攻击力 = 原版 50%; 护甲 / 魔抗 / 暴击 / 暴伤 / 减伤 等照抄原版; 同一种龟; 站在我方半场
##   C 装备: 每件星级 −1, 一星的不带; 复制体的装备不算我方羁绊件数
##   D 阵亡: 最大生命值 / 攻击力 / 护甲 / 魔抗 的 10 / 20 / 35% 给最近的一名友军(含召唤物)
##   E 每路一次: 同一路 tick 多次只偷一次; 换路(开打时刻变了)再偷; 不进终极战场幸存名单
##   F 随机挑: 同一个对局种子挑出同一批, 换种子能挑出别的
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MS := preload("res://scripts/systems/equip/mask_synergy_system.gd")

var _n := 0
var _fail := 0
var _s


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, kind: String = "green", dy: float = 0.0, dx: float = 0.0) -> Dictionary:
	var c: Vector2 = _s._arena_center
	return _s._spawn._make_unit(kind, side, c + Vector2((-300.0 if side == "left" else 300.0) + dx, dy))


func _run(units: Array, tiers: Dictionary) -> void:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": tiers.get("left", {}), "right": tiers.get("right", {})}
	_s._mask_syn.reset_match()


func _copies(side: String) -> Array:
	var out: Array = []
	for u in _s._units:
		if u is Dictionary and bool(u.get("_mask_copy", false)) and str(u.get("side", "")) == side:
			out.append(u)
	return out


func _three_foes() -> Array:
	return [_mk("right", "green", -150.0), _mk("right", "fire", 0.0), _mk("right", "ice", 150.0)]


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s.set_process(false)
	_s.set_physics_process(false)
	_s._battle_rng.seed = 12345
	print("=== 面具羁绊【偷脸】 ===")

	## ── A 档位偷几只 ──
	var got := {}
	for tier in [1, 2, 3]:
		_run([_mk("left")] + _three_foes(), {"left": {"面具": tier}})
		_s._sd_t0 = 1000.0 * tier
		_s._mask_syn.tick(0.0)
		got[tier] = [_copies("left").size(), _copies("right").size()]
	_ok("A 一档偷 1 / 二档偷 2 / 三档偷 3(对面三只); 对面没有面具 ⇒ 不偷", got[1] == [1, 0] and got[2] == [2, 0] and got[3] == [3, 0], str(got))
	var r2 := _mk("right", "green", -150.0)
	var dead := _mk("right", "fire", 0.0)
	dead["alive"] = false
	var egg := _mk("right", "ice", 150.0)
	egg["_isEgg"] = true
	var sm := _mk("right", "ice", 250.0)
	sm["is_summon"] = true
	var oc := _mk("right", "fire", -250.0)
	oc["_mask_copy"] = true
	_run([_mk("left"), r2, dead, egg, sm, oc], {"left": {"面具": 3}})
	_s._sd_t0 = 5000.0
	_s._mask_syn.tick(0.0)
	var cs: Array = _copies("left")
	var cs_ids: Array = []
	for x in cs:
		cs_ids.append(str(x.get("_mask_of_id", "")))
	_ok("A 三档但对面只活一只可偷 ⇒ 只偷 1 只; 阵亡 / 龟蛋 / 召唤物 / 别人的复制体不偷", cs.size() == 1 and cs_ids == ["green"], "%d 只 · %s" % [cs.size(), str(cs_ids)])

	## ── B 复制体属性 ──
	var o := _mk("right", "fire", 0.0, 80.0)
	o["maxHp"] = 3000.0
	o["hp"] = 1200.0
	o["base_atk"] = 200.0
	o["base_def"] = 55.0
	o["base_mr"] = 33.0
	o["crit"] = 0.37
	o["crit_dmg"] = 1.9
	o["damage_reduction"] = 0.12
	o["lifesteal"] = 0.08
	_s._recalc_stats(o)
	_run([_mk("left"), o], {"left": {"面具": 1}})
	var c: Dictionary = _s._mask_syn.make_copy(o, "left", 1)
	_ok("B 同一种龟、归我方、站我方半场(x < 中线)", str(c.get("id", "")) == "fire" and str(c.get("side", "")) == "left" and Vector2(c["pos"]).x < _s._arena_center.x,
		"%s · %s · x %.0f / 中线 %.0f" % [str(c.get("id")), str(c.get("side")), Vector2(c["pos"]).x, _s._arena_center.x])
	_ok("B 最大生命值 = 原版最大值的 50%(满血出场) · 攻击力 = 原版 50%",
		absf(float(c["maxHp"]) - 1500.0) < 1e-3 and absf(float(c["hp"]) - 1500.0) < 1e-3 and absf(float(c["base_atk"]) - 100.0) < 1e-3 and absf(float(c["atk"]) - 100.0) < 1e-3,
		"生命 %.0f/%.0f · 攻击 %.0f" % [float(c["hp"]), float(c["maxHp"]), float(c["atk"])])
	_ok("B 护甲 / 魔抗 / 暴击 / 暴伤 / 减伤 / 吸血 照抄原版",
		absf(float(c["def"]) - float(o["def"])) < 1e-3 and absf(float(c["mr"]) - float(o["mr"])) < 1e-3 and absf(float(c["crit"]) - 0.37) < 1e-6
		and absf(float(c["crit_dmg"]) - 1.9) < 1e-6 and absf(float(c["damage_reduction"]) - 0.12) < 1e-6 and absf(float(c["lifesteal"]) - 0.08) < 1e-6,
		"甲 %.0f/%.0f 抗 %.0f/%.0f 暴 %.2f 伤 %.2f 减 %.2f 吸 %.2f" % [float(c["def"]), float(o["def"]), float(c["mr"]), float(o["mr"]), float(c["crit"]), float(c["crit_dmg"]), float(c["damage_reduction"]), float(c["lifesteal"])])

	## ── C 装备 ──
	o = _mk("right", "fire")
	o["equips"] = [{"id": "p2eq_001", "star": 2}, {"id": "p2eq_003", "star": 1}, {"id": "p2eq_096", "star": 3}]
	_run([_mk("left"), o], {"left": {"面具": 1}})
	c = _s._mask_syn.make_copy(o, "left", 1)
	var eq_s: Array = []
	for e in c.get("equips", []):
		eq_s.append("%s★%d" % [str(e["id"]), int(e["star"])])
	_ok("C 每件星级 −1, 一星的不带(2★→1★ · 1★ 不带 · 3★→2★)", eq_s == ["p2eq_001★1", "p2eq_096★2"], str(eq_s))
	var me := _mk("left")
	_run([me, c], {})
	var cnt: Dictionary = _s._synergy._calc_tiers("left")
	var types_c: Array = []
	for e in c.get("equips", []):
		for t in _s.Phase2Types.types_of(str(e["id"])):
			types_c.append(t)
	var leak := false
	for t in types_c:
		if int(cnt.get(t, 0)) > 0:
			leak = true
	_ok("C 复制体带的装备不计入我方羁绊件数(场上口径; 复制体装备类型 %s)" % str(types_c), not types_c.is_empty() and not leak, str(cnt))

	## ── D 阵亡转属性 ──
	var gave := {}
	for tier in [1, 2, 3]:
		var near := _mk("left", "green", 40.0)
		near["is_summon"] = true   # 召唤物也能收
		near["maxHp"] = 1000.0
		near["hp"] = 500.0
		near["base_atk"] = 50.0
		near["base_def"] = 10.0
		near["base_mr"] = 10.0
		near["buffs"] = []
		_s._recalc_stats(near)
		var far := _mk("left", "green", 300.0, -400.0)
		var cp := _mk("left", "fire")
		cp["_mask_copy"] = true
		cp["_mask_tier"] = tier
		cp["maxHp"] = 2000.0
		cp["base_atk"] = 100.0
		cp["base_def"] = 40.0
		cp["base_mr"] = 20.0
		cp["pos"] = Vector2(near["pos"]) + Vector2(30.0, 0.0)
		_run([near, far, cp], {})
		var far_hp0 := float(far["maxHp"])
		_s._mask_syn.on_death(cp)
		var k: float = MS.GIVE_PCT[tier - 1]
		gave[tier] = absf(float(near["maxHp"]) - (1000.0 + 2000.0 * k)) < 1e-3 and absf(float(near["hp"]) - (500.0 + 2000.0 * k)) < 1e-3 \
			and absf(float(near["atk"]) - (50.0 + 100.0 * k)) < 1e-3 and absf(float(near["def"]) - (10.0 + 40.0 * k)) < 1e-3 \
			and absf(float(near["mr"]) - (10.0 + 20.0 * k)) < 1e-3 and float(far["maxHp"]) == far_hp0
		if not gave[tier]:
			print("    档 %d: 生命 %.1f/%.1f 攻 %.1f 甲 %.1f 抗 %.1f 远处 %.1f→%.1f" % [tier, float(near["hp"]), float(near["maxHp"]), float(near["atk"]), float(near["def"]), float(near["mr"]), far_hp0, float(far["maxHp"])])
	_ok("D 复制体阵亡 ⇒ 最近的友军(召唤物也算)拿到它生命 / 攻击 / 护甲 / 魔抗的 10 / 20 / 35%; 远的不拿", gave[1] and gave[2] and gave[3], str(gave))
	var plain := _mk("left", "fire")
	var nb := _mk("left", "green", 40.0)
	_run([plain, nb], {})
	var nb0 := float(nb["maxHp"])
	_s._mask_syn.on_death(plain)
	_ok("D 不是复制体的阵亡 ⇒ 不转", float(nb["maxHp"]) == nb0)

	## ── E 每路一次 / 换路再偷 / 不进幸存名单 ──
	_run([_mk("left")] + _three_foes(), {"left": {"面具": 1}})
	_s._sd_t0 = 7000.0
	for _i in range(5):
		_s._mask_syn.tick(0.0)
	var once := _copies("left").size()
	_s._sd_t0 = 7100.0
	_s._mask_syn.tick(0.0)
	var twice := _copies("left").size()
	_ok("E 同一路 tick 5 次只偷 1 次; 换路(开打时刻变了)再偷 1 次", once == 1 and twice == 2, "%d → %d" % [once, twice])
	var gs = get_node_or_null("/root/GameState")
	var surv_ok := false
	if gs != null:
		var keep = gs.dual_survivors
		gs.dual_survivors = {"left": [], "right": []}
		_s._dl_sys._dl_snapshot_survivors()
		var nl: int = (gs.dual_survivors["left"] as Array).size()
		surv_ok = nl == 1
		print("    幸存名单 左 %d 条(场上左方 %d 只, 其中复制体 %d)" % [nl, 1 + twice, twice])
		gs.dual_survivors = keep
	_ok("E 复制体不进终极战场幸存名单", surv_ok)

	## ── F 随机 ──
	var picks := {}
	var mismatch := false
	for sd in [1, 2, 3, 4, 5, 6, 1]:
		_run([_mk("left")] + _three_foes(), {"left": {"面具": 1}})
		_s._battle_rng.seed = sd
		var st: Array = _s._mask_syn.steal("left", 1)
		var who: String = str(st[0].get("_mask_of_id", "")) if not st.is_empty() else ""
		if picks.has(sd) and picks[sd] != who:
			mismatch = true
		picks[sd] = who
	var kinds := {}
	for sd in [1, 2, 3, 4, 5, 6]:
		kinds[picks[sd]] = true
	_ok("F 同种子挑同一只, 不同种子能挑到别的(6 个种子挑到 %d 种)" % kinds.size(), not mismatch and kinds.size() >= 2, str(picks))

	print("分母: %d 条断言 · 本进程生成复制体 %d 只 · 转属性 %d 次" % [_n, _s._mask_syn.stolen, _s._mask_syn.gifted])
	if _fail == 0:
		print("ALL PASS — 面具羁绊【偷脸】 (%d 条)" % _n)
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
