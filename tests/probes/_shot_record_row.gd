extends Control
## 截图探针(11-08): 闯关赛战绩卡「4 胜 1 负」那一行数字与「胜 / 负」是否在同一条基线上(用户实机截图「这个四和一是故意的吗？」)。不是门禁。
## 用法(屏幕外静音窗口; 两个比例各跑一次):
##   <godot> --path . --audio-driver Dummy --resolution 1560x720 --position 5000,5000 res://tests/probes/_shot_record_row.tscn
## 环境变量 SHOT_OUT = 输出 png(默认 res://.out/shots/record_row.png)。

const WCC := preload("res://scripts/scenes/week_close_card.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#2a2420")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var d := {"title": "闯关赛战绩", "ribbon": WCC.RIBBON_GOLD, "record": [int(OS.get_environment("REC_W") if OS.get_environment("REC_W") != "" else "4"), 1],
		"status": "已晋级周日决赛日", "body": ["决赛日小组赛：周日 18:00 开始。"],
		"primary": ["查看对阵图", WCC.DOOR_BRACKET], "secondary": ["关闭", WCC.DOOR_NONE]}
	WCC.open(self, d, func(_door, _p): pass)
	for _i in range(12):
		await get_tree().process_frame
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = "res://.out/shots/record_row.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out))
	print("[SHOT] ", out)
	get_tree().quit()
