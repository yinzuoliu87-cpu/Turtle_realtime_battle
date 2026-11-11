extends Node
## verify_swordsman.gd — 剑羁绊【剑士 + 血祭】(用户 2026-08-03 定)
##
## ★三条规则都要有断言守着 —— 它们不是"顺手加的保险", 是实测会出事的三条:
##   ① 追打不走 _basic_attack ⇒ 不自递归(否则一次普攻能炸成无限)
##   ② 追打期间的命中不再点燃剑士(双生匕首 3★ 是"每段伤害 100% 追加一刀")
##   ③ ★连击产生的普攻不触发剑士(用户拍板) —— 赌神龟自己就是连击机制,
##      两个相乘实测 576% vs 272% = 2.1 倍, 剑会变成"赌神专属"
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SW := preload("res://scripts/systems/equip/swordsman_system.gd")

var _n := 0
var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new(); add_child(s)
	await get_tree().process_frame; await get_tree().process_frame
	var ALL9 := ["p2eq_001","p2eq_007","p2eq_005","p2eq_009","p2eq_003","p2eq_083","p2eq_006","p2eq_084","p2eq_010"]
	print("=== 剑士 + 血祭 (批4-2) ===")

	# ── 剑士: 逐档追打次数与伤害 ──
	for cfg in [[3, 1, 0.18], [6, 1, 0.25], [9, 2, 0.40]]:
		var team_n: int = cfg[0]
		var me := _mk(ALL9.slice(0, 3))
		var units: Array = [me]
		var k := 3
		while k < team_n:
			units.append(_mk(ALL9.slice(k, mini(k + 3, team_n)))); k += 3
		_run(s, units)
		s._swordsman._pending.clear()
		s._swordsman.on_basic_attack(me, units[units.size() - 1])
		var want_hits: int = int(cfg[1])
		_ok("剑 %d 件: 排了 %d 次追打" % [team_n, want_hits],
			s._swordsman._pending.size() == want_hits, "实得 %d" % s._swordsman._pending.size())
		if s._swordsman._pending.size() > 0:
			var pct: float = float(s._swordsman._pending[0]["pct"])
			_ok("剑 %d 件带3件: 每次伤害 = %.0f%%×3 = %.0f%%" % [team_n, float(cfg[2]) * 100.0, float(cfg[2]) * 300.0],
				absf(pct - float(cfg[2]) * 3.0) < 0.001, "实得 %.0f%%" % (pct * 100.0))

	# ── ★分母 + 对照: 不到首档一次都不排 ──
	var me2 := _mk(ALL9.slice(0, 2))
	_run(s, [me2])
	s._swordsman._pending.clear()
	s._swordsman.on_basic_attack(me2, me2)
	_ok("★对照: 只有 2 件剑(未达首档) → 一次追打都不排", s._swordsman._pending.is_empty(),
		"实得 %d" % s._swordsman._pending.size())
	# 队里够 9 件但本龟不带剑 → 不排(剑士只给携带者)
	var noswd := _mk([])
	var units2: Array = [noswd]
	var k2 := 0
	while k2 < 9:
		units2.append(_mk(ALL9.slice(k2, k2 + 3))); k2 += 3
	_run(s, units2)
	s._swordsman._pending.clear()
	s._swordsman.on_basic_attack(noswd, units2[1])
	_ok("★顶档但本龟不带剑 → 不排(剑士只给携带者)", s._swordsman._pending.is_empty(),
		"实得 %d" % s._swordsman._pending.size())

	# ── ①② 防递归 ──
	var me3 := _mk(ALL9.slice(0, 3))
	_run(s, [me3, _mk(ALL9.slice(3, 6)), _mk(ALL9.slice(6, 9))])
	s._swordsman._pending.clear()
	me3["_sw_busy"] = true
	s._swordsman.on_basic_attack(me3, me3)
	_ok("① ★追打期间(_sw_busy)不再点燃剑士(防无限递归)", s._swordsman._pending.is_empty(),
		"实得 %d" % s._swordsman._pending.size())
	me3["_sw_busy"] = false
	_ok("② 源码保证: 追打【不调】_basic_attack(剑士挂在它里面, 走它就递归)",
		not FileAccess.get_file_as_string("res://scripts/systems/equip/swordsman_system.gd").contains("._basic_attack(src"))

	# ── ④ 追打算一次攻击, 触发攻击时的装备效果(用户 2026-11-11「剑士的追打应该也算这个普通攻击啊，也能触发攻击特效」) ──
	var me4: Dictionary = s._spawn._make_unit("basic", "left", Vector2(500, 400))
	var eq4: Array = []
	for i4 in ALL9.slice(0, 3):
		eq4.append({"id": str(i4), "star": 1})
	eq4.append({"id": "p2eq_065", "star": 1})   # 鲨肝油: 每次攻击 +1 层(攻速 + 龟能)
	me4["equips"] = eq4
	me4["eq_state"] = {}
	me4["hp"] = 100000.0; me4["maxHp"] = 100000.0; me4["alive"] = true
	var tg4: Dictionary = s._spawn._make_unit("basic", "right", Vector2(560, 400))
	tg4["hp"] = 100000.0; tg4["maxHp"] = 100000.0; tg4["alive"] = true; tg4["dodge"] = 0.0
	_run(s, [me4, _mk(ALL9.slice(3, 6)), _mk(ALL9.slice(6, 9)), tg4])
	s._swordsman._pending.clear()
	s._swordsman.on_basic_attack(me4, tg4)
	var n4: int = s._swordsman._pending.size()
	var o4: int = int((me4["eq_state"].get("p2eq_065", {}) as Dictionary).get("oil_stacks", 0))
	s._t = float(s._t) + 10.0
	s._swordsman.tick(0.0)
	var o5: int = int((me4["eq_state"].get("p2eq_065", {}) as Dictionary).get("oil_stacks", 0))
	_ok("④ 分母: 顶档带 3 件剑 ⇒ 排了 2 次追打, 且都打出去了", n4 == 2 and s._swordsman._pending.is_empty(), "排 %d · 剩 %d" % [n4, s._swordsman._pending.size()])
	_ok("④ ★追打算一次攻击 ⇒ 鲨肝油每次追打 +1 层(%d → %d)" % [o4, o5], o5 == o4 + n4)
	_ok("④ 追打打完 _sw_busy 已放下(不把后面的正常普攻也挡掉)", not bool(me4.get("_sw_busy", false)))
	s._swordsman._pending.clear()

	# ── ③ ★连击不触发剑士(用户拍板) ──
	s._swordsman._pending.clear()
	me3["_chained_atk"] = true
	s._swordsman.on_basic_attack(me3, me3)
	_ok("③ ★★连击产生的普攻不触发剑士(赌神龟)", s._swordsman._pending.is_empty(),
		"实得 %d" % s._swordsman._pending.size())
	me3["_chained_atk"] = false
	s._swordsman._pending.clear()
	s._swordsman.on_basic_attack(me3, me3)
	_ok("③ 对照: 链断后的正常普攻【照常】触发剑士", s._swordsman._pending.size() == 2,
		"实得 %d" % s._swordsman._pending.size())
	_ok("③ 赌神源码真的在掷中时打了标记",
		FileAccess.get_file_as_string("res://scripts/systems/skills/gambler_system.gd").contains('u["_chained_atk"] = true'))

	# ── 血祭: 掉血→涨攻, 回血→跌回去 ──
	var b := _mk([])
	b["_blood_rite"] = 0.5          # 顶档
	b["hp"] = b["maxHp"] * 0.5
	s._blood_rite_refresh(b)
	var half: float = float(b["atk"])
	_ok("血祭 顶档半血: 攻 40 → %.0f (+0.5%%×50)" % half, absf(half - 50.0) < 0.51, "实得 %.1f" % half)
	b["hp"] = b["maxHp"]
	s._blood_rite_refresh(b)
	_ok("★血回满后攻击力跌回 40(不是只涨不跌)", absf(float(b["atk"]) - 40.0) < 0.01,
		"实得 %.1f" % float(b["atk"]))
	var nb := _mk([])              # 没有血祭的单位: 一点都不加
	nb["hp"] = nb["maxHp"] * 0.1
	s._recalc_stats(nb)
	_ok("★对照: 没有血祭的单位掉到 10% 血, 攻击力仍是 40", absf(float(nb["atk"]) - 40.0) < 0.01,
		"实得 %.1f" % float(nb["atk"]))

	s._units.clear(); s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 剑士与血祭" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run(s, units: Array) -> void:
	s._units.clear(); s._units.append_array(units)
	s._synergy._by_side = {"left": {}, "right": {}}
	s._synergy.apply_all()

func _mk(ids: Array) -> Dictionary:
	var e: Array = []
	for i in ids: e.append({"id": str(i), "star": 1})
	return {"id":"basic","side":"left","alive":true,"hp":945.0,"maxHp":945.0,"equips":e,"eq_state":{},
		"base_atk":40.0,"atk":40.0,"base_def":0.0,"def":0.0,"base_mr":0.0,"mr":0.0,"crit":0.0,
		"crit_dmg":1.5,"armor_pen":0.0,"magic_pen":0.0,"lifesteal":0.0,"buffs":{},"atk_interval":1.25,
		"aspd_perm":1.0,"shield":0.0,"pos":Vector2.ZERO}
