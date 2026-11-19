extends Node
## _shot_spar_exit.gd —— 切磋对局左下角「退出」实拍(探针, 不进门禁)。门禁是 tests/verify_spar_exit.gd。
## 跑法(离屏、静音):
##   SHOT_OUT=res://.out/spar_exit SHOT_TAG=phone APPDATA=<临时> XDG_DATA_HOME=<临时> TURTLE_SUPABASE=" " \
##     <godot> --position 5000,5000 --resolution 1560x720 --audio-driver Dummy --path . res://tests/probes/_shot_spar_exit.tscn
## 拍: 开场幕布上 / 开打后 / 点了退出的问框。

const Backend := preload("res://scripts/net/backend.gd")
const SE := preload("res://scripts/scenes/battle/spar_exit.gd")
var _dir := ""
var _tag := ""


func _shot(name: String) -> void:
	for _i in range(4):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_dir, name, _tag])
	print("shot ", name)


func _ready() -> void:
	_dir = ProjectSettings.globalize_path(OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "res://.out/spar_exit")
	_tag = OS.get_environment("SHOT_TAG") if OS.has_environment("SHOT_TAG") else "x"
	DirAccess.make_dir_recursive_absolute(_dir)
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	load("res://tests/_setup_appstore.gd").run()
	var gs = get_node("/root/GameState")
	gs.tutorial_active = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	var g: Dictionary = Backend.make_bot(3, rng)
	g["profile"] = {"name": "好友甲", "avatar": "stone", "id": "FRND01"}
	if not Spar.begin(g, {"name": "好友甲", "tag": "FRND01"}):
		print("切磋没挂上: ", Spar.my_side_check())
		get_tree().quit(1)
		return
	var b: Node = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(b)
	for _i in range(90):
		await get_tree().process_frame
	await _shot("curtain")
	for _i in range(3000):
		if str(b._dl_state) == "fight":
			break
		await get_tree().process_frame
	for _i in range(120):
		await get_tree().process_frame
	await _shot("fight")
	var k: Button = b.find_child(SE.N_EXIT, true, false) as Button
	if k != null:
		k.pressed.emit()
	await _shot("ask")
	get_tree().quit(0)
