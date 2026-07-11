extends Node
## verify_ninja_shuriken.gd — 手里剑暴击拆两段(红物理+白真伤·1:1回合制)自证
##   ①非暴击=单发物理  ②暴击=物理段+真伤段两段, 真伤=暴击总伤×(40+2%/级)%  ③真伤段不二次暴击(总伤=暴击总伤)
##   逻辑验证(数值/分桶); 飘字两数字的观感由用户 F5 眼验, 本测不涉及渲染。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

func _land_shuriken(scene, ninja: Dictionary, dummy: Dictionary) -> void:
	# 清残留弹道 + 归零目标承伤分桶, 掷镖, 步进到命中
	scene._projectiles.clear()
	dummy["_st_taken"] = 0
	dummy["_st_taken_by_type"] = {}
	dummy["hp"] = dummy["maxHp"]
	scene._sk_ninja_shuriken(ninja, dummy)
	for i in range(20):        # 20×0.05=1s ≥ 弹道dur(≤0.5)
		scene._step_projectiles(0.05)
		if scene._projectiles.is_empty(): break

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false); scene.set_physics_process(false)
	scene._units.clear(); scene._t = 0.0; scene._over = false; scene._edit_mode = false

	var ninja: Dictionary = scene._make_unit("ninja", "left", Vector2(600, 400))
	ninja["atk"] = 100.0
	ninja["crit_dmg"] = 1.5
	ninja["level"] = 1
	ninja["armor_pen"] = 0.0; ninja["armor_pen_pct"] = 0.0; ninja["damage_amp"] = 0.0
	scene._units.append(ninja)
	var dummy: Dictionary = scene._make_unit("basic", "right", Vector2(700, 400))   # 100px 外
	dummy["def"] = 0.0                 # 无护甲→物理不减免(隔离拆分数值)
	dummy["damage_reduction"] = 0.0
	dummy["shield"] = 0.0
	dummy["maxHp"] = 1000000.0; dummy["hp"] = 1000000.0
	dummy["no_basic"] = true; dummy["no_move"] = true; dummy["move_spd"] = 0.0
	scene._units.append(dummy)

	# 期望值 (def=0 → 物理段不减免)
	var base_dmg: float = 100.0 * 1.6                      # 160
	# ── 暴击: crit=1.0 → 必暴 ──
	ninja["crit"] = 1.0
	var crit_mult: float = 1.5                             # crit_dmg1.5 + 溢出0
	var crit_total: int = int(round(base_dmg * crit_mult))  # 240
	var exp_true: int = int(round(float(crit_total) * (40.0 + 2.0 * 1.0) / 100.0))  # round(240×0.42)=101
	var exp_phys: int = crit_total - exp_true              # 139
	_land_shuriken(scene, ninja, dummy)
	var bt: Dictionary = dummy.get("_st_taken_by_type", {})
	var got_phy: int = int(bt.get("phy", 0))
	var got_tru: int = int(bt.get("tru", 0))
	var got_total: int = int(dummy.get("_st_taken", 0))
	_ok("暴击=两段(物理phy桶+真伤tru桶都>0)", got_phy > 0 and got_tru > 0, "phy=%d tru=%d" % [got_phy, got_tru])
	_ok("暴击·物理段=暴击总伤余下(240-101=139)", got_phy == exp_phys, "got=%d exp=%d" % [got_phy, exp_phys])
	_ok("暴击·真伤段=暴击总伤×42%%(=101)", got_tru == exp_true, "got=%d exp=%d" % [got_tru, exp_true])
	_ok("★真伤段不二次暴击(两段之和=暴击总伤240)", got_total == crit_total, "总=%d 暴击总伤=%d" % [got_total, crit_total])

	# ── 非暴击: crit=0.0 → 必不暴 ──
	ninja["crit"] = 0.0
	_land_shuriken(scene, ninja, dummy)
	var bt2: Dictionary = dummy.get("_st_taken_by_type", {})
	var p2: int = int(bt2.get("phy", 0))
	var t2: int = int(bt2.get("tru", 0))
	_ok("非暴击=单发物理(phy=160·无真伤tru)", p2 == int(round(base_dmg)) and t2 == 0, "phy=%d tru=%d" % [p2, t2])

	# ── 等级缩放真伤占比: lv=30 → (40+60)=100%封顶 → 真伤=暴击总伤全部, 物理段=0→保底1(1:1回合制 max(1,calc_damage)) ──
	ninja["crit"] = 1.0
	ninja["level"] = 30
	_land_shuriken(scene, ninja, dummy)
	var bt3: Dictionary = dummy.get("_st_taken_by_type", {})
	_ok("lv30·真伤占比封顶100%%(真伤=240·物理段保底1)", int(bt3.get("tru", 0)) == crit_total and int(bt3.get("phy", 0)) == 1, "phy=%d tru=%d" % [int(bt3.get("phy", 0)), int(bt3.get("tru", 0))])

	print("")
	print(("ALL PASS — 手里剑拆两段 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
