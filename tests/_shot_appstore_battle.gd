extends Node
## App Store 战斗截图台(2026-10-20): 先跑 `_setup_appstore.gd` 种好真实玩家与对手, 再切进双路战斗场。
## 截图由战斗场自己的 SELFSHOT / SHOT_BURST / SHOT_STEP / SHOT_OUT 完成(见 RealtimeBattle3DScene._self_screenshot)。
##   DUALLANE=1 SHIP=1 SELFSHOT=8 SHOT_BURST=30 SHOT_STEP=0.5 SHOT_OUT=<dir>/b.png QUIET=1 \
##   TURTLE_SUPABASE=" " TURTLE_BACKEND=" " <godot> --audio-driver Dummy --position 5000,5000 \
##     --resolution 1311x603 --path . res://tests/_shot_appstore_battle.tscn
## ★不能 --headless(无头不渲染, 截出空图且不报错)。


func _ready() -> void:
	var scr: GDScript = load("res://tests/_setup_appstore.gd")
	if scr == null or not scr.can_instantiate():
		push_error("_setup_appstore.gd 加载失败")
		get_tree().quit(1)
		return
	scr.run()
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
