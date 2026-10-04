extends Node
## _shot_weekend_replay.gd — 周末看回放实拍(探针, 不进门禁)。方案书 docs/plans/20261004-周末看回放.md。
## 四张: 主菜单周六那扇门 / 赛况板全部 / 赛况板点了一个人 / 对阵图观众点了已揭晓那一格。
## ★等落位 420 帧(memory fb-screenshot-must-settle-and-multi-ratio)。
## 跑法(离屏、不开可见窗口):
##   SHOT_OUT=<目录> SHOT_TAG=<比例名> <godot> --position 5000,5000 --resolution 1560x720 \
##     --audio-driver Dummy --path . res://tests/_shot_weekend_replay.tscn
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")

var _dir := "user://"
var _tag := "x"


func _shot(name: String) -> void:
	for _i in range(420):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("[shot] ", name)


func _ready() -> void:
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.account_id = "11111111-2222-4333-8444-555555555555"
	gs.season_id = 1
	gs.season_level = 6
	gs.promoted = true
	gs.gauntlet_wins = 2
	gs.gauntlet_losses = 1
	gs.week_phase = "gauntlet"
	var mon: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sat: int = mon + 5 * 86400 + 15 * 3600

	## ① 主菜单(周六 15:00 UTC)
	var mm = MENU.new()
	mm.clock_override_ts = sat
	mm.strip_now_override = sat
	add_child(mm)
	await _shot("menu_sat")
	mm.queue_free()
	await get_tree().process_frame

	## ② 赛况板(喂行, 不联网)
	var bs = (load("res://scenes/GauntletBoard.tscn") as PackedScene).instantiate()
	add_child(bs)
	await get_tree().process_frame
	bs.set_rows(_rows(sat))
	await _shot("board_all")
	var focus := ""
	for p in bs.data.get("players", []):
		if int(p["w"]) == 4:
			focus = str(p["tag"])
	bs._on_player_pressed(focus)
	await _shot("board_player")
	bs.queue_free()
	await get_tree().process_frame

	## ③ 对阵图(观众, 第 2 轮进行中), 点已揭晓那一格 —— 服务端函数没上线时那句话
	var now := int(Time.get_unix_time_from_system())
	var ents: Array = []
	var nm := ["石头统领", "海风小将", "阿龟", "竹林隐士", "老船长", "浪里白条", "夜光贝", "铁甲先生"]
	for i in range(8):
		ents.append({"seed": i, "name": nm[i], "account_id": "acct-%d" % i})
	var wv: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": mon, "now": now,
		"buckets": [{"bucket": 1, "n": 8, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents}]}), "", now)
	var m = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	add_child(m)
	await get_tree().process_frame
	m.set_data({}, {}, now)
	m.set_week(wv)
	m._show_replay_msg("这场的回放还没开放", Color("#ff9b7a"))
	await _shot("bracket_spectate")
	get_tree().quit(0)


func _prof(nm: String, who: String, av: String) -> Dictionary:
	return {"name": nm, "tag": P2C.player_tag(who), "avatar": av, "id": "g_x"}


func _iso(t: int) -> String:
	return Time.get_datetime_string_from_unix_time(t) + "+00:00"


## 一份像样的周六: 8 个人、14 场。对手里有 3 个是机器人(名字与号来自 make_bot, 与真人同一种长相)。
func _rows(sat: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var me := {"name": Backend.player_display_name(), "tag": Backend.my_tag(), "avatar": "basic", "id": "g_me"}
	var a := _prof("石头统领", "a", "stone")
	var b := _prof("海风小将", "b", "bamboo")
	var c := _prof("竹林隐士", "c", "angel")
	var d := _prof("老船长", "d", "basic")
	var bots: Array = []
	for i in range(3):
		var bt: Dictionary = Backend.make_bot(8, rng, i, 1)
		bots.append(bt["profile"])
	var rows: Array = []
	var t := sat - 6 * 3600
	var seq := [
		[a, b, true, 1, 0, 0, 0], [me, c, true, 1, 0, 0, 0], [b, d, false, 0, 1, 0, 0],
		[a, bots[0], true, 2, 0, 1, 1], [c, d, true, 1, 1, 0, 1], [me, bots[1], false, 1, 1, 1, 1],
		[a, me, true, 3, 0, 2, 0], [d, b, false, 0, 2, 0, 1], [me, bots[2], true, 2, 1, 2, 1],
		[a, c, false, 3, 1, 3, 0], [b, d, true, 1, 2, 0, 2], [a, me, true, 4, 1, 3, 1],
		[c, b, true, 2, 1, 1, 1], [d, c, false, 0, 3, 2, 2],
	]
	var k := 0
	for s in seq:
		k += 1
		var res := {"won": bool(s[2]), "steps": 3000, "surrendered": false, "gw": int(s[3]), "gl": int(s[4])}
		rows.append({"match_id": "%08x-0000-4000-8000-%012x" % [k, k], "created_at": _iso(t + k * 1500),
			"result": res, "lp": s[0], "rp": s[1], "rw": s[5], "rl": s[6]})
	return rows
