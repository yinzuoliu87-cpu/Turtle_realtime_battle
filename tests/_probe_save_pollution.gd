extends Node
## 探针: 在【场景脚本能拿到控制权的最早时刻】问一句 —— 存档文件已经被写出来了吗?
## 若是, 说明写入发生在 autoload `_ready` 里, 任何场景侧的 test_mode 都来不及。
## 跑法: APPDATA=<全新空目录> <godot> --path . res://tests/_probe_save_pollution.tscn --position 5000,5000

func _ready() -> void:
	var exists := FileAccess.file_exists("user://savegame.json")
	var gs = get_node_or_null("/root/GameState")
	var tm := "无 GameState"
	if gs != null:
		tm = "test_mode=%s" % str(gs.test_mode)
	print("[探针] 场景 _ready 时刻: user://savegame.json 存在=%s · %s · headless=%s"
		% [str(exists), tm, str(DisplayServer.get_name() == "headless")])
	print("[探针] user:// 实际路径 = %s" % ProjectSettings.globalize_path("user://"))
	print("[探针] cmdline_args = %s" % str(OS.get_cmdline_args()))
	print("[探针] main_scene = %s" % str(ProjectSettings.get_setting("application/run/main_scene")))
	get_tree().quit(0)
