extends Node
## verify_attack_rhythm.gd — 普攻三段: 前摇一开始就出手动作, 伤害结算那一刻正好是命中帧(2026-11-05)。
##
## 用户 2026-11-05:「英雄在平 A 的时候，应该是有一个攻击前摇，然后命中，然后攻击后摇…比方说盖伦…先是举起来这个剑，
##   然后砍到一半…敌方身上出现命中特效…继续挥剑…直到收手…近战小将…站位待机动画，然后突然戳一下…又回到待机动画」。
## 根因: 帧条在前摇**结束**(结算)才从第 0 帧开播。修法: scripts/scenes/battle/attack_rhythm.gd(前摇开始开播, 帧率 = 命中帧 / 前摇秒数)。
## 判据(真场景、交互模式: sim 与立绘动画同一串真实 delta):
##   ① 进入普攻前摇(state "windup" + pending "B")的那一帧, 帧条单位 anim_action 已是 "attack"(不是待机站着)
##   ② 伤害结算那一帧(_atk_wind 由真变假 = _basic_attack 跑过), 精灵显示的帧 == 登记的命中帧(±1)
##   ③ 没有帧条的单位: 前摇期间形变在蓄力(windup_t > 0 且 _windup_total = 前摇秒数)
##   ④ 每张主表 / 生成表里的普攻帧条都在 AttackHits 登记了命中帧(没登记 = 按 40% 估, 不许)
## 分母: 每个攻击方至少观察到 2 次结算。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 普攻三段: 前摇开播 + 命中帧对上结算 ===")
	## ④ 登记
	var rbs: Script = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var cs: Dictionary = rbs.get_script_constant_map()
	var unreg: Array = []
	var nreg := 0
	for tbl in [cs.get("ACTION_ATTACK", {}), TurtleActions.ATTACK]:
		for k in (tbl as Dictionary):
			nreg += 1
			var p: String = str(((tbl as Dictionary)[k] as Array)[0])
			if not AttackHits.is_registered(p):
				unreg.append(p)
	_ok("★分母: 普攻帧条 %d 张" % nreg, nreg >= 15)
	_ok("④ 每张普攻帧条都登记了命中帧", unreg.is_empty(), str(unreg))

	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	for u0 in scn._units.duplicate():
		var sp0 = u0.get("sprite", null)
		if sp0 != null and is_instance_valid(sp0):
			sp0.queue_free()
	scn._units.clear()
	## ★不用 det 模式: det 下 sim 每帧固定走 SIM_DT, 而立绘动画按真实帧间隔走 ⇒ 无头跑得快时动画落后、量出的是测试环境的假象
	##   (11-05 探针: 结算时小龟停在第 1 帧)。交互模式下 sim 与动画吃同一串真实 delta, 量的就是玩家看到的那条时间线。
	scn._deterministic = false
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5
	## 靶子: 打不死、不动、不还手
	var dm: Dictionary = scn._spawn._make_unit("stone", "right", Vector2(cx + 40.0, cy))
	for k in ["no_move", "no_basic"]:
		dm[k] = true
	dm["move_spd"] = 0.0
	dm["maxHp"] = 9.0e7
	dm["hp"] = 9.0e7
	dm["deathfloor_until"] = 1.0e9
	dm["active_skills"] = []
	scn._units.append(dm)
	var specs := [
		["小龟(外包·骨骼帧条)", "basic", {}],
		["幽灵(主表帧条)", "ghost", {}],
		["近战小将", "__minion__", {"minion": true, "role": "front"}],
		["精英小将", "__minion__", {"minion": true, "role": "front", "elite": true}],
		["钻石龟(无帧条·形变)", "diamond", {}],
	]
	var atk: Array = []
	for i in range(specs.size()):
		var sp: Array = specs[i]
		## 围着靶子一圈、半径 45(近战射程 70 以内; 移速为 0, 不在射程里就会卡住不出手)
		var ang: float = PI * 0.5 + PI * float(i) / float(specs.size() - 1)
		var a: Dictionary = scn._spawn._make_unit(str(sp[1]), "left", Vector2(cx + 40.0, cy) + Vector2(cos(ang), sin(ang)) * 45.0, sp[2])
		a["active_skills"] = []
		a["energy_cost"] = {}
		a["move_spd"] = 0.0
		a["maxHp"] = 9.0e7
		a["hp"] = 9.0e7
		scn._units.append(a)
		atk.append({"nm": str(sp[0]), "u": a, "hits": 0, "bad": [], "start_ok": 0, "start_bad": 0, "juice": 0,
			"prev_state": "", "prev_wind": false, "sheet": AttackRhythm.sheet_path(scn, a)})
	for _f in range(900):
		await get_tree().process_frame
		for e in atk:
			var u: Dictionary = e["u"]
			var st := str(u.get("state", ""))
			var wind: bool = bool(u.get("_atk_wind", false))
			## ① 刚进普攻前摇
			if st == "windup" and str(e["prev_state"]) != "windup" and str(u.get("pending", "")) == "B":
				if str(e["sheet"]) != "":
					if str(u.get("anim_action", "")) == "attack":
						e["start_ok"] += 1
					else:
						e["start_bad"] += 1
				elif float(u.get("windup_t", 0.0)) > 0.0 and float(u.get("_windup_total", 0.0)) > 0.0:
					e["juice"] += 1
			## ② 结算那一帧
			if bool(e["prev_wind"]) and not wind and str(e["sheet"]) != "":
				e["hits"] += 1
				var spr: Sprite3D = u["sprite"]
				var want: int = int(u.get("_atk_hit_frame", -1))
				if str(u.get("anim_action", "")) != "attack" or absi(spr.frame - want) > 1:
					e["bad"].append("显示第 %d 帧, 命中帧 %d, 动作 %s" % [spr.frame, want, str(u.get("anim_action", ""))])
			elif bool(e["prev_wind"]) and not wind:
				e["hits"] += 1
			e["prev_state"] = st
			e["prev_wind"] = wind
	for e in atk:
		_ok("★分母: %s 观察到 ≥2 次普攻结算" % e["nm"], int(e["hits"]) >= 2, "%d 次" % int(e["hits"]))
		if str(e["sheet"]) != "":
			_ok("① %s 进前摇那一帧就在播普攻动作(不是站着)" % e["nm"], int(e["start_ok"]) >= 2 and int(e["start_bad"]) == 0,
				"开播 %d · 站着 %d" % [int(e["start_ok"]), int(e["start_bad"])])
			_ok("②★★ %s 伤害结算那一帧显示命中帧" % e["nm"], (e["bad"] as Array).is_empty(), str(e["bad"]).left(300))
		else:
			_ok("③ %s 没有帧条: 前摇期间形变蓄力" % e["nm"], int(e["juice"]) >= 2, "%d 次" % int(e["juice"]))
	scn.queue_free()
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 普攻前摇开播、命中帧对上结算" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
