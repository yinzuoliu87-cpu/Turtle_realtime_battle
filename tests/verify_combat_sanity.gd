extends Node
## verify_combat_sanity.gd — 诊断用户 v7 反馈: ①近战打不到人 ②失败没扣心
## 手动驱动战斗 tick, 不依赖渲染/dual流程.

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false); scene.set_physics_process(false)

	# ── A. 近战攻击方 → 静止假人, 8 秒内应造成伤害 ──
	scene._units.clear()
	scene._t = 0.0
	scene._over = false
	scene._edit_mode = false
	scene._dl_state = "fight"
	var atk: Dictionary = scene._make_unit("stone", "left", Vector2(600, 400))   # 石头=近战
	atk["active_skills"] = []          # 只普攻(隔离近战命中)
	scene._units.append(atk)
	var dummy: Dictionary = scene._make_unit("basic", "right", Vector2(820, 400))  # 220px 外(近战射程已抬到≥100·站位~85→仍需靠近才打得到)
	dummy["active_skills"] = []
	dummy["no_basic"] = true
	dummy["no_move"] = true
	dummy["move_spd"] = 0.0
	dummy["maxHp"] = 100000.0; dummy["hp"] = 100000.0
	scene._units.append(dummy)         # ★上次漏了这行→假人不在_units→攻击方无敌可索(测试bug非游戏bug)
	_ok("攻击方是近战(melee=true)", bool(atk.get("melee", false)), "melee=%s range=%s" % [atk.get("melee"), atk.get("atk_range")])
	var hp0: float = float(dummy["hp"])
	var d0: float = atk["pos"].distance_to(dummy["pos"])
	for i in range(200):               # 200×0.05 = 10 sim 秒
		scene._t += 0.05
		for u in scene._units.duplicate():
			if u.get("alive", false):
				scene._tick_unit(u, 0.05)
		scene._apply_separation_pass(0.05)
		scene._step_pending_shots(0.05)
		scene._step_projectiles(0.05)
	var dmg: float = hp0 - float(dummy["hp"])
	var d1: float = atk["pos"].distance_to(dummy["pos"])
	_ok("★近战攻击方靠近了假人(间距缩小)", d1 < d0, "起 %.0f → 终 %.0f" % [d0, d1])
	_ok("★近战对假人造成了伤害", dmg > 0.0, "10秒造成 %d 伤害 (间距 %.0f, atk_cd=%.2f, state=%s)" % [int(dmg), d1, atk.get("atk_cd", -1), atk.get("state", "?")])

	# ── B. 失败扣心 / 胜利不扣 ──
	gs.season_start_ts = int(Time.get_unix_time_from_system())   # 防赛季过期滚动清心
	gs.season_leaders = ["basic", "stone", "ice"]                # _had_season=true
	gs.hearts = 8
	scene._settle_season(false)        # 输一场
	_ok("★失败扣 1 心 (8→7)", int(gs.hearts) == 7, "hearts=%d" % int(gs.hearts))
	gs.hearts = 8
	scene._settle_season(true)         # 赢一场
	_ok("胜利不扣心 (保持8)", int(gs.hearts) == 8, "hearts=%d" % int(gs.hearts))

	_done()


func _done() -> void:
	print("")
	print(("ALL PASS — 近战/扣心 正常" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
