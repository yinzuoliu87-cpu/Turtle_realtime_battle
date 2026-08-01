extends Node
## 靶向器 p2eq_055 钩索炸弹 展示台(给用户看特效用, 循环播放)
## 一轮: 挂弹(炸弹贴敌人头顶·脉动) → 每秒跳伤 → 宿主死亡 → 朝全部敌人甩锁链 → 眩晕拉向携带者 → 聚爆
## 跑法: SHIP=1 <godot> --path . res://tests/_show_hookbomb.tscn --resolution 1280x720 --position <x>,<y>
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null
var _tip: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	# ★空场: 不设它的话 RB.new() 会自动出生双方完整阵容, 我的展示单位混进一堆默认龟里,
	#   还会有别的技能特效乱入(自查第一版截图里有个巨大的锤子横在屏幕上)。
	RB.DEBUG_EDIT = true
	_s = RB.new(); add_child(_s)
	for _i in range(40): await get_tree().process_frame
	var cl := CanvasLayer.new(); cl.layer = 90; add_child(cl)
	_tip = Label.new()
	_tip.add_theme_font_size_override("font_size", 22)
	_tip.add_theme_color_override("font_color", Color("#ffd93d"))
	_tip.position = Vector2(24, 96); _tip.size = Vector2(1200, 40)
	cl.add_child(_tip)
	if OS.has_environment("HB_SHOT"):        # 自查模式: 跑一轮, 在关键时刻各抓一张
		await _one_round()
		get_tree().quit(0)
		return
	while true:
		await _one_round()

func _say(t: String) -> void:
	if is_instance_valid(_tip): _tip.text = "靶向器 · " + t

func _one_round() -> void:
	# 清上一轮: 连节点一起收掉(只置 alive=false 会留一屏尸体和特效)
	for u in _s._units.duplicate():
		for k in ["sprite", "shadow", "contact", "ring", "bar_root"]:
			var nd = u.get(k, null)
			if is_instance_valid(nd): (nd as Node).queue_free()
	_s._units.clear()
	await get_tree().process_frame
	for ch in _s._world.get_children():
		if ch.has_meta("hb_tmp"): ch.queue_free()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var car: Dictionary = _s._spawn._make_unit("hunter", "left", c + Vector2(-260, 0))
	car["maxHp"] = 4000.0; car["hp"] = 4000.0
	car["equips"] = [{"id": "p2eq_055", "star": 3}]
	car["eq_state"] = {}
	_s._units.append(car)
	var foes: Array = []
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(200, 0) + Vector2(cos(a), sin(a)) * 150.0)
		e["maxHp"] = 3000.0; e["hp"] = 3000.0
		_s._units.append(e); foes.append(e)
	await _wait(1.2)

	_say("① 携带者累计造成 400 伤害 → 向最近 2 名敌人发射钩索炸弹")
	car["_st_dealt"] = 400
	_s._equip_tick_sys._tick_targeter(car, 0.1)
	await _wait(1.0)
	await _shot("1_挂弹")
	await _wait(1.2)

	_say("② 炸弹附在敌人身上, 每秒扣其最大生命 2%")
	for t in range(4):
		for e in foes:
			if float(e.get("hookbomb_pct", 0.0)) > 0.0: _s._hookbomb_sys._hb_tick(e, 1.05)
		await _wait(0.75)
		await _shot("dot%d" % t)
	_say("③ 带弹的敌人死亡 → 朝【全部】敌人甩钩索, 眩晕 0.5 秒后拉向携带者")
	var host: Dictionary = foes[0]
	for e in foes:
		if float(e.get("hookbomb_pct", 0.0)) > 0.0: host = e; break
	host["hp"] = 1.0
	_s._kill(host)
	# ★HB_SHOT 下: 引爆窗口内【密集连拍】(抽搐→甩须→缠住→收缩→炸开), 逐帧自查触手
	if OS.has_environment("HB_SHOT"):
		for k in range(30):
			await _wait(0.16)
			await _shot("f%02d" % k)
	else:
		await _wait(2.55)
	_say("④ 聚拢引爆: (500 + 10% 目标最大生命) 物理伤害 —— 一轮结束, 重播")
	await _wait(2.2)

func _shot(tag: String) -> void:
	if not OS.has_environment("HB_SHOT"): return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/tmp/hbshow_%s.png" % tag)


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame
