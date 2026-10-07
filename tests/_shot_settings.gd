extends Node
## DEV 工具: 设置页各账号状态截图(2026-10-07 设置页重排)。不是门禁(文件名 `_` 开头, 不被自动发现)。
##
##   SHOT_STATE=unbound|bound|lost|conflict|off SHOT_OUT=C:/tmp/setfix/x.png \
##     WINDOW=1 bash godot-quiet.sh --resolution 1280x720 --position 5000,5000 res://tests/_shot_settings.tscn
##
## ★后端在进程内配上(与 verify_ios_ui SETTINGS_NO_OVERLAP 同一个做法), 不用 `acct_override`
##   —— 那个会顺手立起绑定屏把整页藏掉。
## ★不能 --headless: 无头没有真实渲染, 截出来是空图而且不报错。

const SB := preload("res://scripts/net/supabase.gd")


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true       # 截图台不许写玩家真存档
	var st := OS.get_environment("SHOT_STATE")
	if st != "off":
		OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
		ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forshot")
		gs.account_id = "ae08e589-1111-2222-3333-444455556666"
	gs.account_email = "" if st in ["unbound", "off"] else "lisa.chen@example.com"
	if st == "lost":
		SB._session_lost = true
	if st == "conflict":
		SB.apply_push_response(true, 200, '{"ok": false, "reason": "conflict", "rev": 7}', "")
	var inst: Node = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	img.save_png(out)
	print("[SHOT] %s → %s (%dx%d)" % [st, out, img.get_width(), img.get_height()])
	get_tree().quit(0)
