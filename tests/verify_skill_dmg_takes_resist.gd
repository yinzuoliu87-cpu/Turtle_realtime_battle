extends Node
## verify_skill_dmg_takes_resist.gd —— 标成物理/魔法的技能伤害必须真的吃护甲/魔抗(2026-10-11 全项目通读第四条)
##
## ★用户 2026-08-29 铁律(系统机制权威 §7.5):「物理就是要吃护甲啊」—— 写物理就必须被护甲挡,
##   没有例外、不逐件商量; 改成吃抗性要按实测平均倍率补系数(verify_armor_compensation 的口径)。
## ★读码发现一批伤害裸值直接进 `_apply_damage_from(raw=false)`, 而那条路**没有护甲公式**
##   (护甲只在 _resolve_dmg / _phys_after_armor / _dot_after_resist)。
## ★判据: 走产品的技能函数, 同一次施放分别打 0 抗与 300 抗的靶子 ⇒ 高抗那个必须明显少吃(<75%)。
##   只量能同步结算的几处(钻石冲撞/滚动、熔岩重击、双头吸收); 其余几处(弹道/延时结算)由下面的源码扫描守。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _pair(caster_id: String, resist: float, magic: bool) -> Array:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit(caster_id, "left", c)
	var b: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(40, 0))
	a["crit"] = 0.0
	b["maxHp"] = 1.0e6
	b["hp"] = 1.0e6
	b["dodge_bonus"] = 0.0
	if magic:
		b["mr"] = resist
		b["base_mr"] = resist
	else:
		b["def"] = resist
		b["base_def"] = resist
	_s._units.append(a)
	_s._units.append(b)
	_s._over = false
	return [a, b]


## 施放一次, 返回目标掉的血。
func _taken(caster_id: String, resist: float, magic: bool, cast: Callable) -> float:
	var ab := _pair(caster_id, resist, magic)
	var b: Dictionary = ab[1]
	var hp0: float = float(b["hp"])
	cast.call(ab[0], b)
	return hp0 - float(b["hp"])


func _check(label: String, caster_id: String, magic: bool, cast: Callable) -> void:
	var lo := _taken(caster_id, 0.0, magic, cast)
	var hi := _taken(caster_id, 300.0, magic, cast)
	_ok("★★%s: 打 300%s 的靶子明显少吃(<75%%)" % [label, "魔抗" if magic else "护甲"],
		lo > 0.0 and hi < lo * 0.75, "0 抗 %.0f / 300 抗 %.0f" % [lo, hi])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 物理/魔法技能伤害吃抗性 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._edit_mode = false

	_check("钻石龟冲撞(物理)", "diamond", false, func(a, b): _s._diamond_sys._diamond_smash_impact(a, b))
	_check("钻石龟滚动撞击(物理)", "diamond", false, func(a, b): _s._diamond_sys._diamond_roll_impact(a, b["pos"], 1.0))

	# ── 源码扫描: 延时/弹道结算的几处, 伤害参数必须经过抗性函数 ──
	var sites := [
		["res://scripts/systems/skills/gambler_system.gd", "_gambler_throw_hit(u, tgt, per, true, false)", "per"],
		["res://scripts/systems/skills/hiding_system.gd", "接触: 10%目标最大生命", ""],
		["res://scripts/systems/skills/shell_system.gd", "STEALTH_BREAK_MAGIC", ""],
		["res://scripts/systems/skills/stone_system.gd", "_apply_damage_from(uu, oo, ", ""],
		["res://scripts/systems/skills/lava_system.gd", "STRIKE_MAXHP_PCT", ""],
		["res://scripts/systems/skills/lava_system.gd", "PIERCE_MAXHP_PCT", ""],
		["res://scripts/systems/skills/pirate_system.gd", "VOLLEY_MAXHP_PCT", ""],
		["res://scripts/systems/skills/two_head_system.gd", "STRIKE_RANGED_MAXHP", ""],
		["res://scripts/systems/skills/two_head_system.gd", "ABSORB_MAXHP_PCT", ""],
	]
	for st in sites:
		var src := FileAccess.get_file_as_string(str(st[0]))
		var found := false
		var ok := false
		for line in src.split("\n"):
			if line.contains(str(st[1])) and (line.contains("_apply_damage_from(") or line.contains("var dmg")):
				found = true
				ok = ok or line.contains("_phys_after_armor(") or line.contains("_magic_after_mr(")
		if str(st[0]).ends_with("gambler_system.gd"):
			ok = src.contains("_gambler_throw_hit(u, tgt, battle._phys_after_armor(u, per_raw, tgt)")
			found = src.contains("BET_SEGMENTS")
		_ok("★源码: %s 的「%s」那一发经过抗性函数" % [str(st[0]).get_file(), str(st[1])], found and ok, "找到=%s" % str(found))

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
