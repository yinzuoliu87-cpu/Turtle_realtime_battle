extends Node
## _probe_menu_bg_draft.gd — 主菜单背景草图实拍(探针, 不进门禁, 不改游戏代码)。
## 由来: 2026-10-05 擂台+看台背景草图要叠【真的】主菜单 UI 看效果, 而不是在图上手画假按钮。
##   做法: 照常建 MainMenuScene, 等落位后把背景 TextureRect 的贴图换成磁盘上的草图 PNG。
##   ⇒ 不碰 assets/sprites/menu/menu-bg-crowd.png(那张有 menu_crowd_sync_audit 守着)。
## 跑法: MENU_BG=<草图png绝对路径> MENU_SHOT_OUT=<png> <godot> --position 5000,5000 \
##       --resolution WxH --path . res://tests/_probe_menu_bg_draft.tscn
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true                      # 绝不写玩家存档
		gs.hearts = 6
		gs.season_total_battles = 7
		gs.season_level = 3
		gs.meta_deepsea_coins = 42
		gs.ranked_used = 7
		gs.week_phase = "ranked"
	var scene = MENU.new()
	add_child(scene)
	for _i in range(60):
		await RenderingServer.frame_post_draw
	var bg_path: String = OS.get_environment("MENU_BG")
	var img := Image.load_from_file(bg_path)
	if img == null or img.is_empty():
		push_error("MENU_BG 读不到: %s" % bg_path)
		get_tree().quit(1)
		return
	var tr: TextureRect = scene.get("_bg_tile")
	if tr == null:
		push_error("场景里没有 _bg_tile")
		get_tree().quit(1)
		return
	tr.texture = ImageTexture.create_from_image(img)
	for _i in range(360):
		await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	var out: String = OS.get_environment("MENU_SHOT_OUT")
	shot.save_png(out)
	print("SHOT_SAVED %s  %dx%d" % [out, shot.get_width(), shot.get_height()])
	get_tree().quit(0)
