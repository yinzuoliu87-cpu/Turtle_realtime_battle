extends Node
## _probe_menu_arena_shot.gd — 主菜单擂台背景实拍(探针, 不进门禁)。
## 由来: 2026-10-05 主菜单「擂台 + 看台」背景。草图阶段这个探针把磁盘上的草图 PNG 换进背景;
##   精修接进 MainMenuScene 之后不用换了 —— 拍的就是真主菜单。
## 会动的东西拍一张不算数(方案书 R2「验收必须看连续帧, 不能只看一张静图」)⇒ 落位后按间隔连拍 N 张。
## 跑法(窗口只开右屏, 后端一律置空, 别碰生产库):
##   TURTLE_BACKEND=" " TURTLE_SUPABASE=" " QUIET=1 SHOT_OUT=<前缀> SHOT_N=4 SHOT_GAP=20 \
##   <godot> --audio-driver Dummy --position 2000,80 --resolution WxH --path . res://tests/_probe_menu_arena_shot.tscn
##   ⇒ <前缀>-0.png … <前缀>-(N-1).png
##   SHOT_TS=<UTC 秒> 可选: 钉死主菜单的「现在」(周六闯关赛 / 周日决赛日那一屏)
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
	if OS.has_environment("SHOT_TS"):            # 钉死「现在」(看周六/周日那一屏): UTC 纪元秒
		scene.clock_override_ts = int(OS.get_environment("SHOT_TS"))
	add_child(scene)
	for _i in range(420):                        # 入场动画要等落位(140 帧不够, 420 才干净)
		await RenderingServer.frame_post_draw
	## SHOT_POPUP=1: 真按一下右下角「今天」模式卡(走它自己那颗按钮的 pressed), 拍弹出来的本周赛程。
	if OS.get_environment("SHOT_POPUP") == "1":
		var tap = scene.find_child("ModeTap", true, false)
		if tap is BaseButton:
			(tap as BaseButton).pressed.emit()
		for _i in range(30):
			await RenderingServer.frame_post_draw
	var pre: String = OS.get_environment("SHOT_OUT")
	var n: int = int(OS.get_environment("SHOT_N")) if OS.has_environment("SHOT_N") else 1
	var gap: int = int(OS.get_environment("SHOT_GAP")) if OS.has_environment("SHOT_GAP") else 20
	for k in range(n):
		var shot: Image = get_viewport().get_texture().get_image()
		shot.save_png("%s-%d.png" % [pre, k])
		print("SHOT_SAVED %s-%d.png  %dx%d" % [pre, k, shot.get_width(), shot.get_height()])
		for _i in range(gap):
			await RenderingServer.frame_post_draw
	get_tree().quit(0)
