extends Node
## shot_feedback_panel.gd — 设置页 + 「问题反馈」面板实拍(不是门禁, 给人看的)。
## 跑法(不能 --headless): <godot> --path . res://tests/shot_feedback_panel.tscn --position 5000,5000 --resolution 2340x1080
## 产物: docs/plans/img-20261012-问题反馈/<宽>x<高>-设置.jpg / -面板.jpg
## ★设置页要作为当前场景才画得出来(当子节点挂上去只拍到全局背景) ⇒ 由挂在根上的帮手切场景、拍照。

const OUT_REL := "docs/plans/img-20261012-问题反馈"
var helper := false


func _ready() -> void:
	if helper:
		_run()
		return
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var h = (get_script() as GDScript).new()
	h.helper = true
	get_tree().root.add_child.call_deferred(h)


func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")
	for _i in range(120):
		await get_tree().process_frame
	var out := ProjectSettings.globalize_path("res://").path_join(OUT_REL)
	DirAccess.make_dir_recursive_absolute(out)
	_shot(out, "设置")
	var b: Node = get_tree().current_scene.find_child("Feedback", true, false)
	if b is BaseButton:
		(b as BaseButton).pressed.emit()
	for _i in range(60):
		await get_tree().process_frame
	_shot(out, "面板")
	get_tree().quit(0)


func _shot(out: String, tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var p := out.path_join("%dx%d-%s.jpg" % [img.get_width(), img.get_height(), tag])
	img.save_jpg(p, 0.9)
	print("SHOT %s" % p)
