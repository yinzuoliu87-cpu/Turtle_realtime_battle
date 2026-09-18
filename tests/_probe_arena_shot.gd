extends Node
## _probe_arena_shot.gd — 拍一帧【真实的战斗场景】(探针, 不进门禁)。
##
## 由来: 主菜单背景对标 151 款商业主菜单后, 数出来的第一类来源是
##   「游戏里真实存在的那个地方」(Star Fox 的驾驶舱 / Yoshi 的纸板关卡 /
##    You Suck at Parking 的停车岛 / Zookeeper 的公园 / DRIVE 的真实赛道画面)。
##   本项目"真实的地方"= 深海战场。与其另画一个场景, 不如直接渲它。
##
## ★台子里最前面置 test_mode: 这个场要渲染 ⇒ 不是 headless ⇒ GameState.test_mode 不自动置位,
##   写 GameState 会直接落盘污染玩家存档(memory fb-debug-stage-writes-real-save)。
##
## 跑法: ARENA_SHOT_OUT=<png> SHOT_WAIT=<帧> <godot> --position 5000,5000 --resolution 1280x720 \
##       --path . res://tests/_probe_arena_shot.tscn
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true          # 自由摆位场: 不跑匹配/结算, 只要世界建出来
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var wait: int = int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 300
	for _i in range(wait):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out: String = OS.get_environment("ARENA_SHOT_OUT") if OS.has_environment("ARENA_SHOT_OUT") else "user://arena.png"
	img.save_png(out)
	print("SHOT_SAVED %s  %dx%d" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
