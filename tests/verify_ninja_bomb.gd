extends Node
## verify_ninja_bomb.gd — 忍者·炸弹(ninjaBomb·AOE)自证
##   炸弹改造只换视觉(抛掷+爆炸帧动画), 伤害/减益走原 _sk_dmg 不变。本测验:
##   ①爆炸落地结算=全体敌都受伤(AOE) ②自带-25%护甲(在伤害前生效·def×0.75) ③投掷 _sk_ninja_bomb 不崩+生成弹体
##   炸弹抛物线/爆炸帧观感由用户 F5 眼验; 落地伤害走 tween 回调(headless 无 _process 不推进)→本测直接验爆炸时的 _sk_dmg 结算。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

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

	var ninja: Dictionary = scene._make_unit("ninja", "left", Vector2(200, 400))
	ninja["atk"] = 100.0
	ninja["crit"] = 0.0                         # 隔离暴击→确定值
	ninja["armor_pen"] = 0.0; ninja["armor_pen_pct"] = 0.0; ninja["damage_amp"] = 0.0
	scene._units.append(ninja)
	# 落点 land = (700,400)。近敌2个(400码内)+远敌1个(500码>400·圈外)
	var land := Vector2(700.0, 400.0)
	var near1: Dictionary = scene._make_unit("basic", "right", Vector2(700, 400))     # 距land 0
	var near2: Dictionary = scene._make_unit("basic", "right", Vector2(900, 400))     # 距land 200 (圈内)
	var far1: Dictionary = scene._make_unit("basic", "right", Vector2(1200, 400))     # 距land 500 (圈外)
	for d in [near1, near2, far1]:
		d["base_def"] = 40.0; d["def"] = 40.0
		d["damage_reduction"] = 0.0; d["shield"] = 0.0
		d["maxHp"] = 1000000.0; d["hp"] = 1000000.0
		d["no_basic"] = true; d["no_move"] = true; d["move_spd"] = 0.0
		d["_st_taken"] = 0
		scene._units.append(d)

	# ── A. 爆炸落地结算(直接调 _bomb_explode = _sk_ninja_bomb 抛物线到点后的回调; spr=null 跳精灵动画) ──
	#   顺序: 圈内敌先施 -25%护甲(def 40→30) 再打伤害 → 每发 round(100×1.1 × (1-30/70)) = 63; 圈外敌 0
	scene._bomb_explode(ninja, land, {"phys": 1.1, "defDown": 0.25, "color": Color("#ff9a3c")})
	var t1: int = int(near1.get("_st_taken", 0))
	var t2: int = int(near2.get("_st_taken", 0))
	var tf: int = int(far1.get("_st_taken", 0))
	_ok("圈内(≤400码)2敌受伤·每发63", t1 == 63 and t2 == 63, "near1=%d near2=%d" % [t1, t2])
	_ok("★圈外(>400码)敌 0 伤害(半径截断)", tf == 0, "far=%d (距land 500码)" % tf)
	_ok("圈内自带-25%护甲(def 40→30)", int(round(float(near1["def"]))) == 30, "near def=%.1f" % float(near1["def"]))
	_ok("★圈外护甲不动(def=40)", int(round(float(far1["def"]))) == 40, "far def=%.1f" % float(far1["def"]))

	# ── B. 投掷炸弹 no-crash + 生成弹体精灵(帧动画/爆炸走 tween, headless 不推进但设置不该崩) ──
	var wc0: int = scene._world.get_child_count()
	scene._sk_ninja_bomb(ninja, near1)
	_ok("投掷 _sk_ninja_bomb 不崩+生成弹体精灵", scene._world.get_child_count() > wc0, "world child %d→%d" % [wc0, scene._world.get_child_count()])

	print("")
	print(("ALL PASS — 忍者炸弹 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
