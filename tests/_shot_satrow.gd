extends Node
## _shot_satrow.gd — 状态行两行版式实拍(探针, 不进门禁)。
## 三天各拍一张: 周四(积分赛) / 周六(闯关赛·原来顶穿 111px 的那天) / 周日(决赛日)。
## ★等落位: 主菜单各键错峰滑入, 140 帧不够, 420 帧才干净(memory fb-screenshot-must-settle-and-multi-ratio)。
## 跑法: SATROW_OUT=/c/tmp/satrow <godot> --position 0,340 --resolution 1280x720 \
##         --audio-driver Dummy --path . res://tests/_shot_satrow.tscn
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
	var dir: String = OS.get_environment("SATROW_OUT") if OS.has_environment("SATROW_OUT") else "user://"
	for pair in [["thu", 3], ["sat", 5], ["sun", 6]]:
		var scene = MENU.new()
		scene.clock_override_ts = MON + int(pair[1]) * 86400 + NOON
		add_child(scene)
		for _i in range(420):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var out: String = "%s/satrow_%s.png" % [dir, str(pair[0])]
		img.save_png(out)
		## 左栏状态行那一块单独裁 ×3 放大 —— 报文案/版式问题前先放大(memory fb-zoom-before-reporting-text-bugs)
		var crop: Image = img.get_region(Rect2i(40, 190, 400, 120))
		crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/satrow_%s_zoom.png" % [dir, str(pair[0])])
		print("SHOT_SAVED %s  %dx%d" % [out, img.get_width(), img.get_height()])
		scene.queue_free()
		await get_tree().process_frame
	print("SHOT DONE")
	get_tree().quit(0)
