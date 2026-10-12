extends Node
## shot_bracket_cup.gd — 冠军杯赛页实拍(不是门禁, 给人看的)。数据 = 2026-10-11 冠军杯赛真实签表与结果(6 人, 种子 0/1 轮空)。
##
## 跑法(**不能 --headless**, 无头截不了图; 窗口放屏外):
##   SHOT_TAG=改前 <godot> --path . res://tests/shot_bracket_cup.tscn --position 5000,5000 --resolution 2340x1080
## 产物: docs/plans/img-20261012-对阵图改版/<SHOT_TAG>-<宽>x<高>.jpg
## ★等 90 帧落位再拍(memory fb-screenshot-must-settle-and-multi-ratio)。

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")

const WEEK := 1791158400
const SUN_2130 := WEEK + 6 * 86400 + 20 * 3600 + 30 * 60   # 周日 20:30 UTC: 冠军杯赛已收盘
const OUT_REL := "docs/plans/img-20261012-对阵图改版"


func _week() -> Dictionary:
	var body := JSON.stringify({"ok": true, "week": WEEK, "now": SUN_2130, "buckets": [],
		"cup": {"bucket": 1000000, "n": 6, "round": 3, "closed": true,
			"done": {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 1, "2-0": 1, "2-1": 0, "3-0": 1},
			"entrants": [
				{"seed": 0, "name": "破防了", "account_id": "uid-0"},
				{"seed": 1, "name": "fish31", "account_id": "uid-1"},
				{"seed": 2, "name": "whm2010", "account_id": "uid-2"},
				{"seed": 3, "name": "haohao", "account_id": "uid-3"},
				{"seed": 4, "name": "桃桃", "account_id": "uid-4"},
				{"seed": 5, "name": "小雪", "account_id": "uid-5"}]}})
	return SB.parse_finals_week(true, 200, body, "uid-zz", 1)


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var out := ProjectSettings.globalize_path("res://").path_join(OUT_REL)
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().process_frame
	var m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	## ★冠军杯赛那一张是从网络层缓存 `finals_cup_cached()` 读的(BracketMapScene `_on_poll`), set_week 不带它
	var wk := _week()
	SB._finals_week = wk
	m.set_data({}, wk.get("cup", {}), SUN_2130)
	m.set_week(wk)
	m.set_view(L.VIEW_FINALS)
	for _i in range(90):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var tag := OS.get_environment("SHOT_TAG")
	var p := out.path_join("%s-%dx%d.jpg" % [tag if tag != "" else "shot", img.get_width(), img.get_height()])
	img.save_jpg(p, 0.9)
	print("SHOT %s" % p)
	get_tree().quit(0)
