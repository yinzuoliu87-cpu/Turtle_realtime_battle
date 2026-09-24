extends Node
## shot_titles_row.gd — 实拍: 主菜单那一行挂上头衔之后还装得下吗 (E-B5)
##
## ★为什么要实拍: 那一行宽 **382px**, 而「📜 战绩 12 胜 3 负 › 」本身就吃掉大半。
##   `verify_mainmenu_layout` 算的是矩形, **算不出字被挤没了**
##   (memory `fb-screenshot-must-settle-and-multi-ratio`: 门禁算矩形不能代替实拍)。
## ★拍**最坏情况**: 四档全拿过、战绩是两位数 —— 不拍最长的那种等于没拍。
##
## 跑法(★不能 --headless, 无头截不了图):
##   NO_SAVE=1 <godot> --path . res://tests/shot_titles_row.tscn \
##     --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --quit-after 900

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const OUT := "user://shot_titles_row"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await _settle(60)
	## ★挪出「会被换掉」那个位置 —— 本脚本自己就是 current_scene
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	GameState.onboarded = true          # 否则会被直接送去新手教程的选龟界面
	GameState.battles_won = 12
	GameState.battles_total = 15
	## ★最坏情况: 四档全有、冠军拿过两次
	GameState.titles = [
		P2C.title_row(P2C.TITLE_CHAMPION, 1), P2C.title_row(P2C.TITLE_CHAMPION, 2),
		P2C.title_row(P2C.TITLE_SEMIFINAL, 3), P2C.title_row(P2C.TITLE_FINALS_DAY, 4),
		P2C.title_row(P2C.TITLE_FULL_QUOTA, 5)]
	print("=== 实拍: 主菜单头衔行 ===")
	print("  最高一档: 「%s」 / 完整串: 「%s」"
		% [P2C.title_top(GameState.titles), P2C.title_line(GameState.titles)])
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await _settle(300)                  # ★等落位: 主菜单有入场 tween
	var img := get_viewport().get_texture().get_image()
	var p := "%s/menu.png" % OUT
	img.save_png(p)
	print("  图: %s" % ProjectSettings.globalize_path(p))
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
