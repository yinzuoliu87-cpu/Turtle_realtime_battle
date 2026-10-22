extends Node
## DEV 工具(不是门禁): 主菜单「处理存档冲突」提示条 + 点进去的二选一框(2026-10-23 加提示条时自查用)。
## 跑法(窗口只开右屏, 不能 --headless):
##   SHOT_DIR=<目录> SHOT_TAG=<比例名> ONBOARD=0 TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_conflict_nudge.tscn
## ★不碰网络: 后端指向连不上的地址 + 传输层截住; 冲突状态直接摆。

const SB := preload("res://scripts/net/supabase.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _save(nm: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := "%s/conflict_%s_%s.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("SHOT_TAG"), nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] ", path)


func _spy(_m, _u, _h, _b, cb) -> void:
	cb.call({})


func _settle() -> void:
	for tw in get_tree().get_processed_tweens():
		if tw.is_valid() and tw.is_running() and tw.get_loops_left() != -1:
			tw.custom_step(10.0)


func _ready() -> void:
	await _frames(2)
	GameState.test_mode = true
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._transport_for_test = _spy
	## 真登录形态(只摆 token 的话设置页账号行会显示「登录已失效」, 盖住冲突那一档)
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-shot","email":"me@x.co"}}')
	GameState.account_id = "uid-shot"
	GameState.account_email = "me@x.co"
	GameState.onboarded = true
	SB._save_conflict_rev = 8
	get_tree().current_scene = null          # 换屏时不把本节点删掉
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await _frames(20)
	_settle()
	await _frames(10)
	await _save("menu")
	var cur := get_tree().current_scene
	var n := cur.find_child(MM.CONFLICT_NUDGE_NAME, true, false) as Control
	if n != null:
		var p: Vector2 = n.get_global_rect().position + Vector2(n.size.x / 2.0, 20.0)
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = p
			e.global_position = p
			get_viewport().push_input(e)
	await _frames(20)
	_settle()
	await _save("settings")
	get_tree().quit()
