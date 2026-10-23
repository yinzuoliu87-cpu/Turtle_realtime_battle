extends Node
## _shot_friends.gd — 好友 / 切磋实拍(探针, 不进门禁; 2026-10-24 · 方案书 docs/plans/20261023-好友切磋.md §6「实拍」)。
## 拍: 主菜单(左列 5 颗方键)/ 好友页(好友 + 申请 + 查找结果)/ 玩家菜单「加好友」/ 切磋结算屏。
## 跑法(右屏、静音): WINDOW=1 SHOT_OUT=<目录> bash godot-quiet.sh --position 2000,80 --resolution 1560x720 \
##   res://tests/_shot_friends.tscn
## 数据全是假服务端(`SB._transport_for_test`), 不连任何服务器。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const PM := preload("res://scripts/scenes/social/player_menu.gd")
const BE := preload("res://scripts/net/backend.gd")

var _dir := "user://"
var _key0 = ""


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, name])
	print("[shot] ", name)


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _card(acc: String, nm: String, lead: String, has := true, upd := "2026-10-24T06:00:00+00:00") -> Dictionary:
	return {"account": acc, "name": nm, "tag": P2C.player_tag(acc), "lead": lead, "has_lineup": has, "updated_at": upd}


func _spy(method, url, headers, body, cb) -> void:
	var fn := str(url).get_file()
	var out := {}
	match fn:
		"put_lineup":
			out = {"ok": true}
		"friend_list":
			out = {"ok": true, "tag": BE.my_tag(), "cap": 100, "friends": [
				_card("a1111111-0000-4000-8000-000000000001", "潮头龟王", "lava"),
				_card("a1111111-0000-4000-8000-000000000002", "珊瑚之影", "phoenix", true, "2026-10-23T20:00:00+00:00"),
				_card("a1111111-0000-4000-8000-000000000003", "铁背大师", "stone", false),
			], "incoming": [_card("b2222222-0000-4000-8000-000000000001", "浪里白条", "pirate")],
			"outgoing": [_card("c3333333-0000-4000-8000-000000000001", "霜甲先生", "ice")]}
		"friend_lookup":
			out = {"ok": true, "people": [_card("d4444444-0000-4000-8000-000000000001", "碧波统领", "cyber")]}
		_:
			out = {"ok": true}
	cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})


func _ready() -> void:
	_dir = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://"
	await get_tree().process_frame
	GameState.test_mode = true
	GameState.tutorial_active = false
	GameState.season_leaders = ["ninja", "stone", "basic"]
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._token = "shot-token"
	SB._expires_at = 0
	SB._transport_for_test = _spy

	# ① 主菜单
	var mm: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	await _wait(2.0)
	await _shot("friends_mainmenu")
	mm.queue_free()
	await _wait(0.3)

	# ② 好友页 + 查找结果
	var fp: Node = (load("res://scenes/Friends.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(fp)
	await _wait(1.0)
	var ed: LineEdit = fp.find_child("IdEdit", true, false)
	ed.text = P2C.player_tag("d4444444-0000-4000-8000-000000000001")
	(fp.find_child("FindBtn", true, false) as Button).pressed.emit()
	await _wait(1.0)
	await _shot("friends_page")

	# ③ 玩家菜单「加好友」(挂在好友页上)
	PM.open(fp, {"name": "潮头龟王", "tag": P2C.player_tag("a1111111-0000-4000-8000-000000000009"), "ctx": "leaderboard"})
	await _wait(0.6)
	await _shot("friends_player_menu")
	fp.queue_free()
	await _wait(0.3)

	# ④ 切磋结算屏
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var g: Dictionary = BE.make_bot(3, rng)
	g["profile"] = {"name": "潮头龟王", "avatar": "lava", "id": "x", "tag": P2C.player_tag("a1111111-0000-4000-8000-000000000001")}
	Spar.begin(g, {"name": "潮头龟王"})
	var sc = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	get_tree().root.add_child(sc)
	await _wait(1.0)
	sc.set_process(false)
	sc.set_physics_process(false)
	sc._units.clear()
	GameState.lane_results = {"top": "left", "bottom": "right", "final": "left"}
	sc._settle_season(true)
	sc._settled = false
	sc._hud._show_banner(true)
	await _wait(1.5)
	await _shot("friends_spar_settle")
	sc.queue_free()
	await _wait(0.3)

	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
	SB._transport_for_test = Callable()
	get_tree().quit(0)
