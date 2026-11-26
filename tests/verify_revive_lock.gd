extends Node
## verify_revive_lock.gd — 复活 2.5 秒里不移动、不出手、不转身(用户 11-27「复活的话，为什么角色还可以移动？复活角色不是不移动了吗？」)
##   真 sim(确定性: 每帧恰一步)。复活那一刻把敌人挪到龟身后(另一侧), 走 2.3 秒:
##     位置不变 · 朝向不变(原来定身也照样转身朝目标) · 敌人一滴血没掉(没出手)
##   再走 0.6 秒(复活结束): 转过身去 + 打到敌人 ⇒ 证明上面不是空检查
##   ① revive_begin(protect=false)= 凤凰 / 驯服 / 威尼斯那类自己管保护的入口(原来没有定身)
##   ② revive_begin(protect=true) = 天使 / 宝箱雕像
##   ③ 驯服重生真入口(_kill → _tame_try_revive)
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0


func _ok(name: String, cond: bool, info = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if cond else "FAIL", name, str(info)])
	if not cond:
		_fail += 1


func _case(tag: String, how: String) -> void:
	var s = RB.new(); add_child(s)
	await get_tree().process_frame; await get_tree().process_frame
	s._units.clear(); s._over = false; s._edit_mode = false; s._deterministic = true
	s._pending_shots.clear()
	var u: Dictionary = s._spawn._make_unit("basic", "left", Vector2(300, 400))
	var e: Dictionary = s._spawn._make_unit("stone", "right", Vector2(400, 400))
	e["maxHp"] = 1e7; e["hp"] = 1e7
	for k in ["atk", "base_atk"]:
		e[k] = 0.0
	e["no_basic"] = true; e["no_move"] = true; e["active_skills"] = []
	u["active_skills"] = []; u["skill_cd"] = {}
	s._units.append(u); s._units.append(e)
	for i in 30:
		await get_tree().process_frame   # 先打起来: 朝向已锁定朝右(敌人在右)
	var face0: bool = bool(u.get("face_right", true))
	match how:
		"open":
			u["hp"] = 1.0
			s._damage.revive_begin(u, float(u["maxHp"]) * 0.3, false)
		"protect":
			u["hp"] = 1.0
			s._damage.revive_begin(u, float(u["maxHp"]) * 0.25, true)
		"tame":
			u["tame_pending"] = true; u["tame_used"] = false; u["tame_by_side"] = "left"
			s._kill(u)
	e["pos"] = Vector2(200, 400)   # 挪到龟身后
	e["_face_x"] = 200.0
	var p0: Vector2 = u["pos"]
	var eh0: float = float(e["hp"])
	var moved := 0.0
	var turned := false
	for i in 138:   # 2.3 秒
		await get_tree().process_frame
		moved = maxf(moved, (Vector2(u["pos"]) - p0).length())
		if bool(u.get("face_right", true)) != face0:
			turned = true
	var hit_in: float = eh0 - float(e["hp"])
	_ok("%s 复活后还活着(分母)" % tag, bool(u.get("alive", false)) and float(u["hp"]) > 1.0, u["hp"])
	_ok("%s 2.3 秒内不移动 / 不转身 / 不出手" % tag, moved < 0.5 and not turned and hit_in == 0.0,
		"位移 %.2f · 转身 %s · 敌掉血 %.0f" % [moved, str(turned), hit_in])
	for i in 36:   # 再 0.6 秒: 复活结束
		await get_tree().process_frame
	var faced: bool = bool(u.get("face_right", true)) != face0
	var hit_after: float = eh0 - float(e["hp"])
	_ok("%s 复活结束后转身打人(非空检查)" % tag, faced or hit_after > 0.0, "转身 %s · 敌掉血 %.0f" % [str(faced), hit_after])
	s.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	await _case("① revive_begin(不带保护)", "open")
	await _case("② revive_begin(带保护)", "protect")
	await _case("③ 驯服重生(真入口)", "tame")
	print("ALL PASS — 复活期间定身" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
