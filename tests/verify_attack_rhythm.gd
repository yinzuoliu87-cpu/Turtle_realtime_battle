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
##   ⑤ 节奏形状(用户 11-08「三个四个小将的…普通攻击有没有按照我们昨天说的，就是攻击前摇，攻击后摇，然后中间就是就慢一点…
##      包括我们自己的忍者龟、变脸龟…幽灵龟」): 这 7 个单位命中前 ≥ 5 帧(站姿 + 蓄力 2 + 挥动 2)、命中后 ≥ 6 帧(停 2 + 收回 4);
##      变脸龟走自己的驱动(two_head_art.gd), 量命中后那几帧播完的秒数 ≥ 6 / 16(= 16 帧每秒下「停 2 + 收回 4」)。
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
	## ⑤ 节奏形状(数字写需求字面: 前 5 后 6)
	var aa: Dictionary = cs.get("ACTION_ATTACK", {})
	for k in ["__minion_front__", "__minion_back__", "__minion_elite__", "__minion_reserve__", "ghost", "ninja"]:
		var p5: String = str((aa.get(k, [""]) as Array)[0])
		var tx: Texture2D = load("res://assets/sprites/" + p5) if p5 != "" else null
		var nf: int = (tx.get_width() / tx.get_height()) if tx != null else 0
		var hf: int = AttackHits.hit_frame(p5, nf)
		_ok("⑤ %s 普攻: 命中前 %d 帧 ≥ 5、命中后 %d 帧 ≥ 6(共 %d 帧)" % [k, hf, nf - hf - 1, nf], nf > 0 and hf >= 5 and nf - hf - 1 >= 6, p5)
	for clip in ["melee_attack", "ranged_attack"]:
		var ent: Array = TwoHeadArt.CLIPS[clip]
		var tx2: Texture2D = load(TwoHeadArt.DIR + clip + ".png")
		var nf2: int = tx2.get_width() / TwoHeadArt.FRAME
		var post: float = float(nf2 - int(ent[0]) - 1) / float(ent[1])
		_ok("⑤ 变脸龟 %s: 命中后 %d 帧 × 1/%.0f 秒 = %.3f 秒 ≥ 0.375" % [clip, nf2 - int(ent[0]) - 1, float(ent[1]), post], post >= 0.375 - 1.0e-6)

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
	var dm0: Vector2 = dm["pos"]
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
		atk.append({"nm": str(sp[0]), "u": a, "p0": a["pos"], "hits": 0, "bad": [], "start_ok": 0, "start_bad": 0, "juice": 0,
			"prev_state": "", "prev_wind": false, "sheet": AttackRhythm.sheet_path(scn, a)})
	## ★11-08: 原来固定看 900 帧。交互模式下每帧的 sim 时间 = 真实帧间隔, 机器越快 900 帧里 sim 时间越短 ⇒ 钻石龟有时只出手 1 次(预检里偶发红)。
	##   改成「每个攻击方都观察到 ≥ 3 次结算就停, 最多 20000 帧」: 判据只看次数够不够, 不跟机器快慢挂钩(CLAUDE.md §2)。
	for _f in range(20000):
		var enough := true
		for e0 in atk:
			if int(e0["hits"]) < 3:
				enough = false
		if enough:
			break
		await get_tree().process_frame
		## ★每帧钉回原位: 全场软分离会把挤在靶子边上的攻击方慢慢推开, 推出近战射程后就卡在 state=move 再也不出手
		##   (11-08 探针: 战斗钟 138 秒只结算 2 次, 小龟 / 钻石龟都停在 move)。这里要量的是普攻节奏, 不是站位。
		for e1 in atk:
			(e1["u"] as Dictionary)["pos"] = e1["p0"]
		dm["pos"] = dm0   # 靶子也钉住(同一个推挤: 靶子被推走, 钉住的近战攻击方就够不着, 只剩远程的幽灵还在打)
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
				var act: String = str(u.get("anim_action", ""))
				if act in ["whirl", "consume"]:
					pass   # 精英第 5 击旋刃 / 低血吞噬取代这一下普攻, 播它自己的动作(玩法如此; 11-08 观察窗拉长后撞上)
				elif act != "attack" or absi(spr.frame - want) > 1:
					e["bad"].append("显示第 %d 帧, 命中帧 %d, 动作 %s" % [spr.frame, want, str(u.get("anim_action", ""))])
			elif bool(e["prev_wind"]) and not wind:
				e["hits"] += 1
			e["prev_state"] = st
			e["prev_wind"] = wind
	for e in atk:
		var uq: Dictionary = e["u"]
		print("  [量] %s 结算 %d 次 · state=%s pending=%s 前摇中=%s 眩晕到 %.2f · 战斗钟 %.2f · 攻击间隔 %.2f · 动作 %s" % [e["nm"], int(e["hits"]),
			str(uq.get("state", "")), str(uq.get("pending", "")), str(uq.get("_atk_wind", false)), float(uq.get("stun_until", 0.0)),
			float(scn._t), float(uq.get("atk_interval", 0.0)), str(uq.get("anim_action", ""))])
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
