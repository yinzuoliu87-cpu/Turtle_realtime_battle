extends Node
## _shot_battle_log.gd — 战绩页重做实拍(探针, 不进门禁)。方案书 docs/plans/20261118-对局记录重做.md。
## 数据: 环境 FIXTURE=<json 文件>(my_battle_log 回包形状; 本机由 scratchpad 的只读脚本从正式服拼, 放 .out/battle_log/)。
##   假传输层只回 my_battle_log, 不连任何外部服务。
## 跑法(离屏、静音):
##   FIXTURE=<json> SHOT_OUT=<目录> SHOT_TAG=<比例名> APPDATA=<临时> XDG_DATA_HOME=<临时> TURTLE_SUPABASE=" " \
##     <godot> --position 5000,5000 --resolution 1560x720 --audio-driver Dummy --path . res://tests/_shot_battle_log.tscn
## 拍: 全部 / 偷袭 / 决赛 / 闯关赛 四个页签 + 全部页往下滑一屏。

const SB := preload("res://scripts/net/supabase.gd")
var _dir := ""
var _tag := ""
var _fixture := "[]"


func _shot(name: String, settle: int = 4) -> void:
	for _i in range(settle):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("shot ", name)


func _fake(method, url, _headers, _body, cb) -> void:
	if str(url).ends_with("/rest/v1/rpc/my_battle_log"):
		cb.call({"ok": true, "code": 200, "body": _fixture})
		return
	cb.call({"ok": true, "code": 200, "body": "{}"})


func _ready() -> void:
	_dir = OS.get_environment("SHOT_OUT")
	_tag = OS.get_environment("SHOT_TAG")
	_fixture = FileAccess.get_file_as_string(OS.get_environment("FIXTURE"))
	await get_tree().process_frame
	GameState.test_mode = true
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-shot","email":"e@x.co"}}')
	SB._transport_for_test = _fake
	var rs: Node = (load("res://scenes/Record.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(rs)
	for _i in range(40):
		await get_tree().process_frame
	await _shot("all")
	for key in ["raid", "finals", "gauntlet"]:
		var b: Button = rs.find_child("Tab_" + key, true, false)
		if b != null:
			b.pressed.emit()
			for _i in range(6):
				await get_tree().process_frame
			await _shot(key)
	var ba: Button = rs.find_child("Tab_all", true, false)
	ba.pressed.emit()
	for _i in range(6):
		await get_tree().process_frame
	var sc: ScrollContainer = rs.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 480
	await _shot("all_scrolled")
	SB._transport_for_test = Callable()
	get_tree().quit(0)
