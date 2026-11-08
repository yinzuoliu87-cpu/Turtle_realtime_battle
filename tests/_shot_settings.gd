extends Node
## DEV 工具: 设置页各账号状态截图(2026-10-07 设置页重排)。不是门禁(文件名 `_` 开头, 不被自动发现)。
##
##   SHOT_STATE=unbound|bound|lost|conflict|off|ml_unbound|ml_pending|ml_bound|ml_internal|ml_switch SHOT_OUT=res://.out/shots/x.png \
##     WINDOW=1 bash godot-quiet.sh --resolution 1280x720 --position 5000,5000 res://tests/_shot_settings.tscn
##
## ★后端在进程内配上(与 verify_ios_ui SETTINGS_NO_OVERLAP 同一个做法), 不用 `acct_override`
##   —— 那个会顺手立起绑定屏把整页藏掉。
## ★不能 --headless: 无头没有真实渲染, 截出来是空图而且不报错。

const SB := preload("res://scripts/net/supabase.gd")
const ML := preload("res://scripts/net/mainsite_link.gd")


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
	## 龟投账号那一行(2026-11-08): ml_unbound / ml_pending / ml_bound / ml_switch(换号确认框)。
	##   请求一律当连不上(不出网), 状态直接摆好。
	if st.begins_with("ml_"):
		gs.account_email = "lisa.chen@example.com" if st == "ml_bound" else ""
		if st == "ml_internal":
			gs.account_email = str(gs.account_id) + "@link.turtlearena.xyz"   # 服务器给绑定的号补的内部邮箱: 不许露出来
		SB._transport_for_test = func(_m, _u, _h, _b, cb: Callable) -> void: cb.call({"ok": false, "code": 0, "body": ""})
		SB._token = "shot-token"
		SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
		ML._reset_for_test()
		ML._note(str(gs.account_id), st == "ml_bound" or st == "ml_internal")
		if st == "ml_pending":
			ML._code = "abcd1234"
			ML._deadline = Time.get_unix_time_from_system() + 300.0
			ML._go(ML.ST_PENDING)
		if st == "ml_switch":
			ML._switch_acc = {"ok": true, "account_id": "0b7e3c1a-2222-4333-8444-555566667777", "token": "t", "email": "", "refresh": "r", "expires_at": 0}
			ML._go(ML.ST_SWITCH_ASK)
	var inst: Node = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	img.save_png(out)
	SB._transport_for_test = Callable()
	print("[SHOT] %s → %s (%dx%d)" % [st, out, img.get_width(), img.get_height()])
	get_tree().quit(0)
