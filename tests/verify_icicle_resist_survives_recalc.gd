extends Node
## verify_icicle_resist_survives_recalc.gd —— 冰锥给的双抗不许被「重算属性」抹掉(2026-10-11 全项目通读第五条后半)
##
## ★读码疑点: `_ice_gain_icicle` 直接写 `u["def"]/u["mr"]`; 而任何 buff/debuff 都会调 `_recalc_stats`,
##   它从 base_def/base_mr 重新算 def/mr ⇒ 冰锥加成被整个抹掉。
## ★判据: 攒 3 层冰锥 ⇒ 护甲/魔抗涨了; 再挂一个无关 buff(触发重算) ⇒ 涨的那部分必须还在。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 冰锥双抗经得起重算 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._units.clear()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("ice", "left", c)
	s._units.append(u)
	s._recalc_stats(u)
	var d0: float = float(u["def"])
	var m0: float = float(u["mr"])
	for i in range(3):
		s._ice_sys._ice_gain_icicle(u)
	var d3: float = float(u["def"])
	var m3: float = float(u["mr"])
	_ok("★分母: 3 层冰锥后护甲/魔抗确实涨了", d3 > d0 + 0.01 and m3 > m0 + 0.01,
		"护甲 %.2f→%.2f 魔抗 %.2f→%.2f" % [d0, d3, m0, m3])
	s._damage._buff(u, "atk", 0.10, true, 5.0)     # 无关 buff ⇒ 触发 _recalc_stats
	_ok("★★挂一个攻击 buff(触发重算)后, 冰锥给的护甲还在", absf(float(u["def"]) - d3) < 0.01,
		"护甲 %.2f(应为 %.2f)" % [float(u["def"]), d3])
	_ok("★★同上, 魔抗还在", absf(float(u["mr"]) - m3) < 0.01, "魔抗 %.2f(应为 %.2f)" % [float(u["mr"]), m3])
	_ok("★攻击 buff 本身也生效了(没被冰锥那条路盖掉)", float(u["atk"]) > float(u["base_atk"]) * 1.05,
		"atk %.2f base %.2f" % [float(u["atk"]), float(u["base_atk"])])

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
