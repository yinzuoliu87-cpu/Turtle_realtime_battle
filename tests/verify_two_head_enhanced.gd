extends Node
## verify_two_head_enhanced.gd — 双头双生B案「强化下1下普攻」自证(用户2026-07-11)
##   切形态挂 _th_enh → 下1下普攻把旧"切形态那一下"的伤害+效果搬进来(就1下)
##   近战强化: +0.6A魔法 + 自己1.1A盾 / 远程强化: +1.4A物理 + 命中目标-25%护甲(破甲)
##   位移/顿/衔接观感留用户 F5(走tween·headless不推进)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)
	sc._units.clear(); sc._t = 0.0; sc._over = false; sc._edit_mode = false

	var dh: Dictionary = sc._make_unit("two_head", "left", Vector2(200, 400))
	dh["atk"] = 100.0; dh["crit"] = 0.0; dh["armor_pen"] = 0.0; dh["armor_pen_pct"] = 0.0; dh["damage_amp"] = 0.0
	dh["shield"] = 0.0
	sc._units.append(dh)
	var tgt: Dictionary = sc._make_unit("basic", "right", Vector2(300, 400))
	tgt["def"] = 0.0; tgt["base_def"] = 0.0; tgt["mr"] = 0.0; tgt["base_mr"] = 0.0
	tgt["damage_reduction"] = 0.0; tgt["shield"] = 0.0; tgt["maxHp"] = 100000.0; tgt["hp"] = 100000.0
	tgt["no_basic"] = true; tgt["no_move"] = true; tgt["_st_taken"] = 0
	sc._units.append(tgt)

	# ── 近战强化普攻: 目标 +0.6A魔法(=60), 双头获 1.1A盾(=110) ──
	sc._two_head_enhanced_basic(dh, tgt, "melee")
	_ok("近战强化: 目标受 0.6A魔法 = 60", int(tgt["_st_taken"]) == 60, "taken=%d" % int(tgt["_st_taken"]))
	_ok("近战强化: 双头获 1.1A护盾 = 110", int(round(float(dh["shield"]))) == 110, "shield=%.0f" % float(dh["shield"]))

	# ── 远程强化普攻: 目标 +1.4A物理(=140, def0无减免) + 施破甲(-25%护甲buff) ──
	tgt["_st_taken"] = 0
	sc._two_head_enhanced_basic(dh, tgt, "ranged")
	_ok("远程强化: 目标受 1.4A物理 = 140", int(tgt["_st_taken"]) == 140, "taken=%d" % int(tgt["_st_taken"]))
	var has_break := false
	for bf in tgt.get("buffs", []):
		if str(bf.get("stat", "")) == "def" and float(bf.get("amount", 0.0)) < 0.0:
			has_break = true
	_ok("★远程强化: 命中施 -25%护甲破甲buff", has_break)

	# ── 切形态挂标(_th_enh): melee→ranged 挂"ranged"; ranged→melee 挂"melee" ──
	dh["melee"] = true; dh["_th_enh"] = ""
	sc._two_head_after_cast(dh, tgt)
	_ok("切远程后 _th_enh=ranged 且形态=远程", str(dh.get("_th_enh", "")) == "ranged" and dh["melee"] == false, "enh=%s melee=%s" % [str(dh.get("_th_enh", "")), str(dh["melee"])])
	dh["melee"] = false; dh["_th_enh"] = ""
	sc._two_head_after_cast(dh, tgt)
	_ok("切近战后 _th_enh=melee 且形态=近战", str(dh.get("_th_enh", "")) == "melee" and dh["melee"] == true, "enh=%s melee=%s" % [str(dh.get("_th_enh", "")), str(dh["melee"])])

	print("")
	print(("ALL PASS — 双头双生强化普攻 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
