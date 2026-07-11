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

	var ninja: Dictionary = scene._make_unit("ninja", "left", Vector2(400, 400))
	ninja["atk"] = 100.0
	ninja["crit"] = 0.0                         # 隔离暴击→确定值
	ninja["armor_pen"] = 0.0; ninja["armor_pen_pct"] = 0.0; ninja["damage_amp"] = 0.0
	scene._units.append(ninja)
	var ds: Array = []
	for i in range(3):
		var d: Dictionary = scene._make_unit("basic", "right", Vector2(700, 300 + i * 100))
		d["base_def"] = 40.0; d["def"] = 40.0
		d["damage_reduction"] = 0.0; d["shield"] = 0.0
		d["maxHp"] = 1000000.0; d["hp"] = 1000000.0
		d["no_basic"] = true; d["no_move"] = true; d["move_spd"] = 0.0
		d["_st_taken"] = 0
		scene._units.append(d); ds.append(d)

	# ── A. 爆炸落地结算(=_sk_ninja_bomb 在爆炸回调里调的同一函数/同一 opts) ──
	# 顺序: 先施 -25%护甲(def 40→30) 再打伤害 → 伤害吃已减后的 def=30
	# 每发 = round(100×1.1 × (1 - 30/(30+40))) = round(110×0.5714) = 63
	scene._sk_dmg(ninja, null, {"phys": 1.1, "hits": 1, "aoe": true, "defDown": 0.25, "color": Color("#ff9a3c")})
	var all_hit: bool = true
	var vals: Array = []
	for d in ds:
		var t: int = int(d.get("_st_taken", 0))
		vals.append(t)
		if t <= 0: all_hit = false
	_ok("炸弹AOE=3假人全受伤", all_hit, "承伤=%s" % str(vals))
	_ok("每发=63(先-25%护甲def30再打)", vals[0] == 63 and vals[1] == 63 and vals[2] == 63, "vals=%s" % str(vals))
	_ok("自带-25%护甲(def 40→30)", int(round(float(ds[0]["def"]))) == 30, "def=%.1f" % float(ds[0]["def"]))

	# ── B. 投掷炸弹 no-crash + 生成弹体精灵(帧动画/爆炸走 tween, headless 不推进但设置不该崩) ──
	var wc0: int = scene._world.get_child_count()
	scene._sk_ninja_bomb(ninja, ds[0])
	_ok("投掷 _sk_ninja_bomb 不崩+生成弹体精灵", scene._world.get_child_count() > wc0, "world child %d→%d" % [wc0, scene._world.get_child_count()])

	print("")
	print(("ALL PASS — 忍者炸弹 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
