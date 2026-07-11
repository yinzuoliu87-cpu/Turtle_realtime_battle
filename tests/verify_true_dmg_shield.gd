extends Node
## verify_true_dmg_shield.gd — 真伤/反伤真伤 要被护盾吸收 (用户2026-07-11「真伤是要被盾档的，反伤的真伤也是」)
##   1:1 回合制 damage.gd「真伤(true)也走护盾」: 真伤只无视护甲/魔抗/减伤, 护盾照吸。唯一穿盾=墨迹(线条被动)。
##   ①真伤被护盾吸(溢出才进血) ②反伤(真伤)被攻击者护盾吸 ③墨迹真伤仍穿盾 ④物理照旧被盾吸(回归)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

func _mk(scene, id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = scene._make_unit(id, side, pos)
	u["crit"] = 0.0                              # 隔离暴击→确定值
	u["maxHp"] = 100000.0; u["hp"] = 100000.0
	u["shield"] = 0.0
	u["_auraShieldVal"] = 0.0
	scene._units.append(u)
	return u

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

	var WHITE := Color("#ffffff")
	var RED := Color("#ff4444")

	# ── ① 真伤(raw)被护盾吸收 ──
	var atk1: Dictionary = _mk(scene, "ninja", "left", Vector2(100, 400))
	var tgt1: Dictionary = _mk(scene, "ninja", "right", Vector2(300, 400))
	tgt1["shield"] = 100.0; tgt1["hp"] = 1000.0; tgt1["maxHp"] = 1000.0
	scene._apply_damage_from(atk1, tgt1, 60, WHITE, 0.0, true)   # 60 真伤
	_ok("真伤被护盾吸(盾100→40·血不掉)", int(tgt1["shield"]) == 40 and int(tgt1["hp"]) == 1000, "shield=%d hp=%d" % [int(tgt1["shield"]), int(tgt1["hp"])])
	scene._apply_damage_from(atk1, tgt1, 60, WHITE, 0.0, true)   # 再60 真伤: 盾40吸40, 余20进血
	_ok("真伤打空盾后溢出进血(盾0·血-20)", int(tgt1["shield"]) == 0 and int(tgt1["hp"]) == 980, "shield=%d hp=%d" % [int(tgt1["shield"]), int(tgt1["hp"])])

	# ── ② 反伤(真伤)被攻击者护盾吸收 ──
	var atk2: Dictionary = _mk(scene, "ninja", "left", Vector2(100, 500))
	atk2["shield"] = 50.0; atk2["hp"] = 1000.0; atk2["maxHp"] = 1000.0
	var tgt2: Dictionary = _mk(scene, "ninja", "right", Vector2(300, 500))
	tgt2["reflect"] = 0.5; tgt2["shield"] = 0.0; tgt2["hp"] = 1000.0; tgt2["maxHp"] = 1000.0
	scene._apply_damage_from(atk2, tgt2, 40, RED, 0.0, false)    # 40物理→tgt2; 反伤50%=20真伤→atk2
	_ok("反伤(真伤20)被攻击者护盾吸(盾50→30·血不掉)", int(atk2["shield"]) == 30 and int(atk2["hp"]) == 1000, "atk2 shield=%d hp=%d" % [int(atk2["shield"]), int(atk2["hp"])])

	# ── ③ 墨迹真伤仍穿盾 (唯一穿盾例外·线条被动) ──
	var atk3: Dictionary = _mk(scene, "ninja", "left", Vector2(100, 600))
	var tgt3: Dictionary = _mk(scene, "ninja", "right", Vector2(300, 600))
	tgt3["shield"] = 100.0; tgt3["hp"] = 1000.0; tgt3["maxHp"] = 1000.0
	tgt3["stacks"] = {"ink": 4}                                  # 4层墨迹 → 每层额外5%真伤穿盾
	scene._apply_damage_from(atk3, tgt3, 40, RED, 0.0, false)    # 40物理→盾吸40(盾100→60); 墨迹8(40×5%×4)穿盾进血
	_ok("墨迹真伤穿盾(盾吸40剩60·墨迹8直接进血)", int(tgt3["shield"]) == 60 and int(tgt3["hp"]) == 992, "shield=%d hp=%d" % [int(tgt3["shield"]), int(tgt3["hp"])])

	# ── ④ 物理照旧被盾吸(回归·没被改坏) ──
	var atk4: Dictionary = _mk(scene, "ninja", "left", Vector2(100, 700))
	var tgt4: Dictionary = _mk(scene, "ninja", "right", Vector2(300, 700))
	tgt4["shield"] = 100.0; tgt4["hp"] = 1000.0; tgt4["maxHp"] = 1000.0
	scene._apply_damage_from(atk4, tgt4, 40, RED, 0.0, false)    # 40物理→盾吸40
	_ok("物理被盾吸(盾100→60·血不掉·回归)", int(tgt4["shield"]) == 60 and int(tgt4["hp"]) == 1000, "shield=%d hp=%d" % [int(tgt4["shield"]), int(tgt4["hp"])])

	print("")
	print(("ALL PASS — 真伤/反伤 被护盾吸 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
