extends Node
## _probe_menu_shot.gd — 主菜单实拍(探针, 不进门禁)。
## 由来: 用户 2026-09-17「主页面你也可以看着怎么动, 要加什么要减什么」——
##   照代码描述不算看见(memory fb-clean-vfx-stage-not-squint), 必须实拍。
## ★等落位再拍: 主菜单各键是错峰滑入的, 拍早了会拍到半路(memory fb-screenshot-must-settle-and-multi-ratio)。
## 跑法: MENU_SHOT_OUT=<png> SHOT_WAIT=<帧> <godot> --position 5000,5000 --resolution WxH \
##       --path . res://tests/_probe_menu_shot.tscn
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true                      # 台子一律先置位, 绝不写玩家存档
		## 摆一个"打了几场的正常玩家"局面 —— 全新存档会走上锁屏, 拍不到真实主菜单
		gs.hearts = 6
		gs.season_total_battles = 7
		gs.season_level = 3
		gs.meta_deepsea_coins = 42
		gs.ranked_used = 7
		gs.week_phase = "ranked"
	var scene = MENU.new()
	add_child(scene)
	var wait: int = int(OS.get_environment("SHOT_WAIT")) if OS.has_environment("SHOT_WAIT") else 420
	for _i in range(wait):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out: String = OS.get_environment("MENU_SHOT_OUT") if OS.has_environment("MENU_SHOT_OUT") else "user://menu.png"
	img.save_png(out)
	print("SHOT_SAVED %s  %dx%d" % [out, img.get_width(), img.get_height()])
	get_tree().quit(0)
