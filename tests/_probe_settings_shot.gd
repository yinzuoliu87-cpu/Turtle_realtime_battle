extends Node
## _probe_settings_shot.gd — 设置页实拍(探针, 不进门禁)。
## 由来: 2026-09-17 把「🛠 调试场」从主菜单挪进设置(用户:「调试场可以塞到设置里,
##   正式上线的不会要调试场」)。挪完必须实拍 —— 算矩形不能代替实拍
##   (memory fb-screenshot-must-settle-and-multi-ratio), 而且这页原来 580 那格被占了,
##   重置键要下移, 会不会压住底部提示只有看才知道。
## 跑法: SET_SHOT_OUT=<png> <godot> --position 5000,5000 --resolution WxH \
##       --path . res://tests/_probe_settings_shot.tscn
const SET := preload("res://scripts/scenes/SettingsScene.gd")

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true                      # 台子一律先置位, 绝不写玩家存档
	var scene = SET.new()
	add_child(scene)
	var wait: int = int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 180
	for _i in range(wait):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out: String = OS.get_environment("SET_SHOT_OUT") if OS.has_environment("SET_SHOT_OUT") else "user://settings.png"
	img.save_png(out)
	print("SHOT_SAVED %s  %dx%d" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
