extends Node
## _shot_strip9.gd — 赛程条九宫格实拍(探针, 不进门禁)。
## 三天各一张: 周四(积分赛) / 周六(闯关赛) / 周日(决赛日 —— 只有这天才有那扇门)。
## ★等落位: 主菜单各键错峰滑入, 140 帧不够, **420 帧**才干净
##   (memory `fb-screenshot-must-settle-and-multi-ratio`)。
## ★窗口静音 + 跑完自退 + 只放屏幕左下角(`--position 0,340`)。
## 跑法:
##   STRIP9_OUT=/c/tmp/mmclock/shot_after <godot> --position 0,340 --resolution 1280x720 \
##     --audio-driver Dummy --path . res://tests/_shot_strip9.tscn
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const MON := 1789344000
const NOON := 43200


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.hearts = 3
		gs.season_id = 1
		gs.season_level = 1
		gs.season_total_battles = 7
		gs.meta_deepsea_coins = 42
		gs.ranked_used = 7
		gs.battles_won = 7
		gs.battles_total = 11
		gs.week_phase = "ranked"
		gs.promoted = true
		gs.gauntlet_wins = 2
		gs.gauntlet_losses = 1
	var dir: String = OS.get_environment("STRIP9_OUT") if OS.has_environment("STRIP9_OUT") else "user://"
	for pair in [["thu", 3], ["sat", 5], ["sun", 6]]:
		var scene = MENU.new()
		scene.clock_override_ts = MON + int(pair[1]) * 86400 + NOON
		add_child(scene)
		for _i in range(420):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/strip9_%s.png" % [dir, str(pair[0])])
		## 条子那一块单独裁 ×2 放大 —— 报版式问题前先放大
		##   (memory `fb-zoom-before-reporting-text-bugs`)。
		var crop: Image = img.get_region(Rect2i(36, 604, 908, 116))
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/strip9_%s_zoom.png" % [dir, str(pair[0])])
		## 今天那一格再裁 ×5 —— 判「字骑没骑在金属边带上」只能靠这个倍数
		var cell_x: int = 60 + int(pair[1]) * 98
		var cell: Image = img.get_region(Rect2i(maxi(0, cell_x - 6), 630, 110, 88))
		cell.resize(cell.get_width() * 5, cell.get_height() * 5, Image.INTERPOLATE_NEAREST)
		cell.save_png("%s/strip9_%s_cell.png" % [dir, str(pair[0])])
		print("SHOT_SAVED %s/strip9_%s.png  %dx%d" % [dir, str(pair[0]), img.get_width(), img.get_height()])
		scene.queue_free()
		await get_tree().process_frame
	print("SHOT DONE")
	get_tree().quit(0)
