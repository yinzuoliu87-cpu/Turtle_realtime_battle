extends Node
## shot_bracket_spectate.gd — 周日对阵图三种情况的手机尺寸实拍(不是门禁, 给人看的)
##
## 跑法(**不能 --headless**, 无头截不了图; 窗口放屏外):
##   <godot> --path . res://tests/shot_bracket_spectate.tscn --position 5000,5000 --resolution 2340x1080
## 产物: docs/plans/img-20261004-对阵图观赛/
##   1 没晋级(观赛接口还没上线) / 2 没晋级·观赛 / 3 本周冠军页
## ★每张等 90 帧落位再拍(memory fb-screenshot-must-settle-and-multi-ratio)。

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")

const SUN_NOON := 1789862400 + 12 * 3600
const OUT_REL := "docs/plans/img-20261004-对阵图观赛"

var _out := ""


func _week() -> Dictionary:
	var body := JSON.stringify({"ok": true, "week": 1789862400, "now": SUN_NOON, "buckets": [
		{"bucket": 0, "n": 4, "round": 2, "closed": true,
			"done": {"1-0": 0, "1-1": 1, "2-0": 1},
			"entrants": [
				{"seed": 0, "name": "阿龟", "account_id": "uid-a"},
				{"seed": 1, "name": "小乙", "account_id": "uid-b"},
				{"seed": 2, "name": "老丙", "account_id": "uid-c"},
				{"seed": 3, "name": "丁丁", "account_id": "uid-d"}]},
		{"bucket": 1, "n": 3, "round": 2, "closed": true, "done": {"1-1": 0, "2-0": 0},
			"entrants": [
				{"seed": 0, "name": "戊龟", "account_id": "uid-e"},
				{"seed": 1, "name": "己龟", "account_id": "uid-f"},
				{"seed": 2, "name": "庚龟", "account_id": "uid-g"}]}]})
	return SB.parse_finals_week(true, 200, body, "uid-zz", 1)


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_out = ProjectSettings.globalize_path("res://").path_join(OUT_REL)
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	await _shot("1-没晋级-接口未上线-2340x1080", {}, false, "")
	await _shot("2-没晋级-观赛-2340x1080", _week(), true, "")
	await _shot("3-本周冠军-2340x1080", _week(), true, L.VIEW_FINALS)
	get_tree().quit(0)


func _shot(tag: String, week: Dictionary, with_week: bool, view: String) -> void:
	var m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.set_data({}, {}, SUN_NOON)
	if with_week:
		m.set_week(week)
	if view != "":
		m.set_view(view)
	for _i in range(90):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var p := _out.path_join(tag + ".jpg")
	img.save_jpg(p, 0.9)
	print("SHOT %s  %dx%d" % [p, img.get_width(), img.get_height()])
	m.queue_free()
	await get_tree().process_frame
