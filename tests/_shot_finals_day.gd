extends Node
## _shot_finals_day.gd — 周日决赛日「入口与叫人」实拍台(探针, 不进门禁; 方案书 20261031c 块 M)。
## 走真场景(主菜单 MainMenu.tscn / 对阵图 BracketMap.tscn / 真战斗场看回放), 数据走 tests/_finals_day_fixture.gd
##   (照服务端一场接一场的排法造), 钟钉在 SHOT_TS(UTC 秒; 也可 SHOT_HM=18:10 = 测试周日的那一刻), 后端置空。
## 全局层(autoload FinalsDay)用 test_host 把这一屏当成玩家的屏强制打开。
##
##   SHOT_CASE=menu|bracket|battle|shop  SHOT_HM=17:40  SHOT_KIND=in|plain  SHOT_VAR=out(第 1 轮输了)
##   SHOT_RECAP=1(主菜单开出收盘补看)  SHOT_MARQ=1(拍跑马灯: 往前倒 3 秒起钟, 让它自己播出来)
##   SHOT_OUT=<png>  SHOT_WAIT=<秒, 默认 2.6>
##   WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/_shot_finals_day.tscn

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const MON := 1789344000                  # 2026-09-14 周一 00:00 UTC

var fx
var host: Node = null
var ts := 0


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	fx = FX.new(MON)
	if OS.get_environment("SHOT_VAR") == "out":
		fx.group_wins[FX.MY_GROUP] = {"1-1": 0}
	fx.me_in = OS.get_environment("SHOT_KIND") != "plain"
	ts = int(OS.get_environment("SHOT_TS")) if OS.has_environment("SHOT_TS") else 0
	if OS.has_environment("SHOT_HM"):
		var hm := OS.get_environment("SHOT_HM").split(":")
		var day := 7 if hm.size() < 4 else int(hm[3])
		ts = MON + (day - 1) * 86400 + int(hm[0]) * 3600 + int(hm[1]) * 60 + (int(hm[2]) if hm.size() > 2 else 0)
	var marq := OS.get_environment("SHOT_MARQ") == "1"
	if marq:
		ts -= 3
	P2.now_override_ts = ts
	_state()
	F.override = fx.feeds(ts)
	F.prev_champ = {"name": "风起", "tag": "#P0101", "avatar": "angel", "week": MON - 7 * 86400}
	F.avatars[MON] = {"#T000": "basic", "#T201": "bamboo", "#T102": "stone"}
	## 本周晋级名单(服务端 finals_qualified_list 的形状; 分组前的赛前页 / 主菜单决赛日卡读它)
	load("res://scripts/net/finals_qualified.gd").override = fx.qualified()
	var case := OS.get_environment("SHOT_CASE")
	if case == "bracket":
		host = await _bracket()
	elif case == "shop":
		host = await _plain_scene("Shop")
	elif case == "battle":
		host = await _battle()
	else:
		host = await _menu()
	var fd = get_node("/root/FinalsDay")
	fd.test_host = host
	fd.tick()
	var wait := float(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 2.6
	var t0 := Time.get_ticks_msec()
	var next_s := 1.0
	while Time.get_ticks_msec() - t0 < int(wait * 1000.0):
		await get_tree().process_frame
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if el >= next_s:
			next_s += 1.0
			ts += 1
			P2.now_override_ts = ts
			F.override = fx.feeds(ts)
			if host != null and host.get("clock_override_ts") != null:
				host.clock_override_ts = ts
			## 对阵图自己的钟(set_data 钉的 _now_override)也跟着走, 否则它停在开拍那一秒、和全局小条差几秒
			if host != null and host.get("_now_override") != null and int(host.get("_now_override")) > 0:
				host.set("_now_override", ts)
			fd.tick()
	await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	shot.save_png(out)
	## SHOT_TEXT=<txt>: 顺手把此刻屏上看得见的每一句字写下来(走查逐句判用; 采集器与门禁 verify_finals_copy 同一份)
	if OS.has_environment("SHOT_TEXT"):
		var TP = load("res://tests/_finals_text_probe.gd")
		var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var fh := FileAccess.open(OS.get_environment("SHOT_TEXT"), FileAccess.WRITE)
		fh.store_string(TP.dump(TP.collect(get_tree().root, vp)) + "\n")
		fh.close()
	print("SHOT_SAVED %s %dx%d ts=%d bar=%s slot=%d popup=%s marquee=%s" % [out, shot.get_width(), shot.get_height(), ts,
		str(fd.line.get("body", "")), int(fd.slot), str(fd.popup != null and is_instance_valid(fd.popup)), str(fd.marquee.played)])
	get_tree().quit(0)


func _state() -> void:
	GameState.test_mode = true
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.season_total_battles = 7
	GameState.season_level = 3
	GameState.season_id = 2
	GameState.meta_deepsea_coins = 42
	GameState.ranked_used = 7
	GameState.onboarded = true
	GameState.nickname = "吃货一枚"
	GameState.first_tips_seen = {"finals_day": true, "gauntlet_day": true, "start_battle": true, "first_week": true}
	var kind_in: bool = fx.me_in
	GameState.promoted = kind_in
	GameState.season_wins = int(P2.PROMOTE_WINS) if kind_in else 2
	GameState.gauntlet_wins = int(P2.GAUNTLET_WINS_IN) if kind_in else 0
	GameState.gauntlet_losses = 0
	GameState.finals_champion = false
	GameState.finals_runner_up = false
	GameState.finals_cup_champion = false
	GameState.finals_cup_runner_up = false


func _menu() -> Node:
	StudioIntro.played = true                 # 工作室开场不盖在实拍上
	var mm = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	mm.clock_override_ts = ts
	add_child(mm)
	for _i in range(4):
		await get_tree().process_frame
	mm._wk().fd.feed_override = fx.feeds(ts)
	if OS.get_environment("SHOT_RECAP") == "1":
		var RC = load("res://scripts/ui/finals_day_recap.gd")
		var f: Dictionary = fx.feeds(ts)
		RC.show_for(mm, MON, f["groups"], f["cup"], ts)
	return mm


func _plain_scene(nm: String) -> Node:
	var inst = (load("res://scenes/%s.tscn" % nm) as PackedScene).instantiate()
	add_child(inst)
	for _i in range(90):
		await get_tree().process_frame
	return inst


func _bracket() -> Node:
	var bm = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	var f: Dictionary = fx.feeds(ts)
	## 18:00 分组之前一个组都没有(服务端 finals_week_view 回 buckets: [])⇒ 不喂单组, 只喂空的整周
	if bm.has_method("set_data") and not ((f["group"] as Dictionary).is_empty() and (f["groups"] as Array).is_empty()):
		bm.set_data(f["group"] if not (f["group"] as Dictionary).is_empty() else (f["groups"] as Array)[0], f["cup"], ts)
	elif bm.has_method("set_data"):
		## 联网、问到了: 没报名的人服务端回 not_entered(finals_view), 报了名的回 not_seated
		bm.set_data({"ok": false, "reason": "not_entered" if not fx.me_in else "not_seated"}, f["cup"], ts)
	if bm.has_method("set_week"):
		bm.set_week({"buckets": f["groups"], "cup": f["cup"], "srv_now": ts, "recv_at": ts})
	add_child(bm)
	for _i in range(6):
		await get_tree().process_frame
	return bm


func _battle() -> Node:
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var Backend = load("res://scripts/net/backend.gd")
	GameState.reset_dual_lane()
	GameState.tutorial_active = false
	GameState.season_leaders = ["angel", "stone", "bamboo"]
	GameState.left_team.assign(GameState.season_leaders)
	GameState.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "angel", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []}, {"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var bot: Dictionary = Backend.make_bot(3, rng)
	(bot["profile"] as Dictionary)["name"] = "小辉同学"
	GameState.dual_ghost = bot
	GameState.dual_active = true
	var b = RB.new()
	b.scene_file_path = "res://scenes/RealtimeBattle3D.tscn"   # 产品里这一屏是从场景文件起的(全局层按它认观战页)
	add_child(b)
	b.set_process(false)
	for _i in range(2):
		await get_tree().process_frame
	var last := ""
	var stf := 0
	var fight_at := -1
	var i := 0
	while i < 4000:
		var st := str(b._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			b._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(b._dl_go_btn):
			b._dl_go_btn.pressed.emit()
		if st == "fight" and fight_at < 0:
			fight_at = i
		if fight_at >= 0 and i - fight_at > 40:
			break
		b._process(0.1)
		if i % 6 == 0:
			await get_tree().process_frame
		i += 1
	## 观战页那一套(回放条 / 开播标签)按 C 块的 replay_controls 建
	var RC = load("res://scripts/scenes/battle/replay_controls.gd")
	b._replay.rec = {"end": {"s": 6720}, "state": {"dual_ghost": GameState.dual_ghost.duplicate(true)}}
	var ui = RC.new(b)
	ui.build()
	for _k in range(10):
		await get_tree().process_frame
	return b
