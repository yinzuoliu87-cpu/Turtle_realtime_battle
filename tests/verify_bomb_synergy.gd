extends Node
## verify_bomb_synergy.gd —— 炸弹羁绊【导弹轰炸】(2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.1)
##
## 用户 11-24：每一路开打第 10 秒，导弹落到战场中心，对所有敌方单位造成「固定 + 目标最大生命 %」物理伤害并击飞 1 秒；
##   三档 3 / 6 / 10 件，只递增伤害：100 + 8% / 200 + 15% / 400 + 40%。
## 用真的 10 件炸弹装备（097~106，data/p2eq-types.json 归「炸弹」）；伤害对账时拿掉它们的登场效果（只测羁绊本身）。
## 判据：
##   A 档位：3 / 6 / 10 件不同装备 ⇒ 1 / 2 / 3 档；9 件仍是 2 档（顶档要集齐 10 件）
##   B 时机：开打 9.99 秒不落、10 秒落；同一路只落一发；换路（_sd_t0 变）重新计时再落一发
##   C 伤害：护甲 0、出手方暴击率 100% ⇒ 恰好 固定 + 比例 × 目标真实 maxHp（不暴击、不除 HP_MULT）；三档逐档对账
##   D 对象：对方存活单位全挨；自己一方不挨；龟蛋不挨
##   E 击飞：挨炸的单位腾空，腾空时间 = 1 秒（按上抛速度与重力算）
##   F 没炸弹的一方不落；两方都有 ⇒ 各落各的
##   G 物理伤害过护甲、吃携带者的护甲穿透（羁绊每件给护穿）
## 反向（2026-11-24 实测）：DMG_MAXHP 改成按「maxHp / HP_MULT」算 ⇒ C 红；FIRE_AT 判断改成 > 11 ⇒ B 红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const T := preload("res://scripts/gamedata/phase2_types.gd")
const BS := preload("res://scripts/systems/equip/bomb_synergy_system.gd")
## 10 件炸弹装备
const FAKE := ["p2eq_097", "p2eq_098", "p2eq_099", "p2eq_100", "p2eq_101", "p2eq_102", "p2eq_103", "p2eq_104", "p2eq_105", "p2eq_106"]

var _n := 0
var _fail := 0
var _scene


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _mk(side: String, ids: Array, hp: float = 10000.0, dx: float = 0.0) -> Dictionary:
	var c: Vector2 = _scene.ARENA.position + _scene.ARENA.size * 0.5
	var off := Vector2(-200.0 + dx, 0.0) if side == "left" else Vector2(200.0 + dx, 0.0)
	var u: Dictionary = _scene._spawn._make_unit("green", side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["base_def"] = 0.0
	u["mr"] = 0.0
	u["base_mr"] = 0.0
	u["crit"] = 1.0
	u["dodge"] = 0.0
	u["airborne"] = false
	var eq: Array = []
	for id in ids:
		eq.append({"id": id, "star": 1})
	u["equips"] = eq
	return u


func _run(units: Array) -> void:
	_scene._units.clear()
	_scene._units.append_array(units)
	_scene._synergy._by_side = {"left": {}, "right": {}}
	_scene._synergy.apply_all()
	for u in units:
		u["def"] = 0.0
		u["crit"] = 1.0
		## 公式对账先隔离护甲穿透(羁绊给的护穿会把 0 护甲压成负数 ⇒ 伤害放大); 护穿另有 G 条专门验
		u["armor_pen"] = 0.0
		u["armor_pen_pct"] = 0.0


## 开一路：时钟对齐到这一路开打时刻 t0 + el
func _at(t0: float, el: float) -> void:
	_scene._sd_t0 = t0
	_scene._t = t0 + el
	_scene._bomb_syn.tick(0.0)


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_scene = RB.new()
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	print("=== 炸弹羁绊【导弹轰炸】===")
	T._ensure_loaded()
	var real := 0
	for id in FAKE:
		if T.types_of(id).has("炸弹"):
			real += 1
	_ok("0 数据表里 10 件都归「炸弹」", real == 10, "%d / 10" % real)

	## A 档位
	var tiers := {}
	for n in [2, 3, 5, 6, 9, 10]:
		var me := _mk("left", FAKE.slice(0, n))
		_run([me, _mk("right", [])])
		tiers[n] = int(_scene._synergy.tier_for(me, "炸弹"))
	_ok("A ★门槛 3 / 6 / 10：2→0 3→1 5→1 6→2 9→2 10→3", tiers == {2: 0, 3: 1, 5: 1, 6: 2, 9: 2, 10: 3}, str(tiers))

	## B + C + D + E：1 档
	var t0 := 100.0
	var me1 := _mk("left", FAKE.slice(0, 3))
	var ally := _mk("left", [], 10000.0, -60.0)
	var foe1 := _mk("right", [], 10000.0)
	var foe2 := _mk("right", [], 5000.0, 60.0)
	var egg := _mk("right", [], 8000.0, 120.0)
	egg["_isEgg"] = true
	_run([me1, ally, foe1, foe2, egg])
	_at(t0, 9.99)
	_ok("B 开打 9.99 秒：还没落", float(foe1["hp"]) == 10000.0 and _scene._bomb_syn.strikes == 0, "hp %.0f" % float(foe1["hp"]))
	_at(t0, 10.0)
	var want1 := 100.0 + 0.08 * 10000.0
	var want2 := 100.0 + 0.08 * 5000.0
	_ok("C ★1 档：固定 100 + 8%% 目标最大生命 ⇒ 1 万血挨 %.0f、5 千血挨 %.0f（护甲 0、出手方暴击率 100%% 也不暴击）" % [want1, want2],
		absf((10000.0 - float(foe1["hp"])) - want1) < 1.5 and absf((5000.0 - float(foe2["hp"])) - want2) < 1.5,
		"实得 %.0f / %.0f" % [10000.0 - float(foe1["hp"]), 5000.0 - float(foe2["hp"])])
	_ok("D 自己一方不挨、龟蛋不挨", float(me1["hp"]) == 10000.0 and float(ally["hp"]) == 10000.0 and float(egg["hp"]) == 8000.0,
		"me %.0f ally %.0f egg %.0f" % [float(me1["hp"]), float(ally["hp"]), float(egg["hp"])])
	var air_t: float = 2.0 * float(foe1.get("vy", 0.0)) / absf(float(_scene.GRAVITY))
	_ok("E ★挨炸的单位腾空，腾空时间 = 1 秒（上抛 %.2f · 重力 %.0f）" % [float(foe1.get("vy", 0.0)), float(_scene.GRAVITY)],
		bool(foe1["airborne"]) and bool(foe2["airborne"]) and absf(air_t - BS.AIR_SEC) < 0.01 and not bool(egg["airborne"]),
		"腾空 %.3f 秒" % air_t)
	var hp_after := float(foe1["hp"])
	foe1["airborne"] = false
	_at(t0, 13.0)
	_ok("B 同一路只落一发（13 秒不再落）", float(foe1["hp"]) == hp_after and _scene._bomb_syn.strikes == 1, "strikes %d" % _scene._bomb_syn.strikes)
	foe1["hp"] = 10000.0
	_at(t0 + 60.0, 10.0)
	_ok("B 换路（开打时刻变了）⇒ 重新计时、再落一发", absf((10000.0 - float(foe1["hp"])) - want1) < 1.5 and _scene._bomb_syn.strikes == 2,
		"strikes %d · 挨 %.0f" % [_scene._bomb_syn.strikes, 10000.0 - float(foe1["hp"])])

	## C 2 档 / 3 档
	for case in [[6, 200.0, 0.15], [10, 400.0, 0.40]]:
		var me := _mk("left", FAKE.slice(0, int(case[0])))
		var foe := _mk("right", [], 10000.0)
		foe["airborne"] = false
		_run([me, foe])
		_at(t0 + 200.0 + float(case[0]), 10.0)
		var w := float(case[1]) + float(case[2]) * 10000.0
		_ok("C ★%d 件 ⇒ %.0f + %.0f%% ⇒ 挨 %.0f" % [int(case[0]), float(case[1]), float(case[2]) * 100.0, w],
			absf((10000.0 - float(foe["hp"])) - w) < 1.5, "实得 %.0f" % (10000.0 - float(foe["hp"])))

	## G 导弹吃携带者的护甲穿透(物理伤害过护甲): 目标护甲 100、携带者护穿 60 ⇒ 按游戏同一套公式
	var gm := _mk("left", FAKE.slice(0, 3))
	var gf := _mk("right", [], 10000.0)
	_run([gm, gf])
	gf["def"] = 100.0
	gm["armor_pen"] = 60.0
	_at(t0 + 300.0, 10.0)
	var gw: float = (100.0 + 0.08 * 10000.0) * DamageMath.resist_multiplier(DamageMath.effective_resist(100.0, 0.0, 60.0))
	var gw0: float = (100.0 + 0.08 * 10000.0) * DamageMath.resist_multiplier(DamageMath.effective_resist(100.0, 0.0, 0.0))
	_ok("G ★物理伤害过护甲、吃携带者护穿：护甲 100 / 护穿 60 ⇒ 挨 %.0f（没护穿应是 %.0f）" % [gw, gw0],
		absf((10000.0 - float(gf["hp"])) - gw) < 1.5 and absf(gw - gw0) > 5.0, "实得 %.0f" % (10000.0 - float(gf["hp"])))

	## F 没炸弹不落 / 两方都有各落各的
	var a := _mk("left", [])
	var b := _mk("right", [])
	_run([a, b])
	var s0: int = _scene._bomb_syn.strikes
	_at(t0 + 400.0, 10.0)
	_ok("F 两方都没炸弹 ⇒ 不落", _scene._bomb_syn.strikes == s0 and float(b["hp"]) == 10000.0)
	var l := _mk("left", FAKE.slice(0, 3))
	var r := _mk("right", FAKE.slice(3, 6))
	_run([l, r])
	_at(t0 + 500.0, 10.0)
	_ok("F 两方都有 ⇒ 各落一发、各挨一发", _scene._bomb_syn.strikes == s0 + 2 and float(l["hp"]) < 10000.0 and float(r["hp"]) < 10000.0,
		"strikes +%d" % (_scene._bomb_syn.strikes - s0))

	print("")
	print("ALL PASS — 炸弹羁绊导弹轰炸 (%d 条)" % _n if _fail == 0 and _n >= 13 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
