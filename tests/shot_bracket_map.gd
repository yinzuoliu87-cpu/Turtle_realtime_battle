extends Node
## shot_bracket_map.gd — 桶地图自截图（不是门禁，是给人看的）
##
## 跑法（**不能 --headless**，无头截不了图）:
##   <godot> --path . res://tests/shot_bracket_map.tscn --position 5000,5000 --resolution 1280x720
##
## ★等落位再拍（memory `fb-screenshot-must-settle-and-multi-ratio`）:
##   140 帧拍出来过四个木牌互相重叠、差点被当 bug 修；这里每张等 90 帧。
## ★拍**四种真实状态**，不是只拍一张好看的：
##   4 人桶(当前能玩到的规模) / 32 人桶(满桶·要拖) / 已翻面 / 冠军赛空态。

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")

const OUT := "C:/tmp/shot_bracket"
const NAMES8 := ["小龟", "石头龟", "冰龟", "火龟", "电龟", "风龟", "毒龟", "铁龟"]

var _shots: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame

	var n32: Array = []
	for i in range(32):
		n32.append("龟%02d" % (i + 1))

	## ① 4 人桶 —— 当前测试人数真能玩到的规模
	await _shot("1_4人桶", {"size": 4, "round": 1, "me": 1,
		"names": ["小龟", "石头龟", "冰龟", "火龟"], "done": {}}, {})

	## ② 8 人桶 · 第一轮已翻面, 当前第 2 轮(不剧透)
	await _shot("2_8人桶_第2轮", {"size": 8, "round": 2, "me": 2, "names": NAMES8,
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}}, {})

	## ③ 32 人满桶 —— 镜像布局到底放不放得下
	await _shot("3_32人满桶", {"size": 32, "round": 3, "me": 17, "names": n32,
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1, "1-4": 0, "1-5": 1,
			"1-6": 0, "1-7": 1, "1-8": 0, "1-9": 1, "1-10": 0, "1-11": 1,
			"1-12": 0, "1-13": 1, "1-14": 0, "1-15": 1,
			"2-0": 0, "2-1": 1, "2-2": 0, "2-3": 1,
			"2-4": 0, "2-5": 1, "2-6": 0, "2-7": 1}}, {})

	## ④ 冠军赛空态(上午切过去) —— 带倒计时那一版
	await _shot("4_冠军赛未开", {"size": 8, "round": 1, "me": 2, "names": NAMES8, "done": {}},
		{}, _L.VIEW_FINALS)

	print("")
	print("截了 %d 张 → %s" % [_shots.size(), OUT])
	for s in _shots:
		print("  " + str(s))
	get_tree().quit(0)


func _shot(tag: String, bucket: Dictionary, finals: Dictionary, view: String = "") -> void:
	var m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.set_bucket(bucket) if finals.is_empty() and view == "" else m.set_data(bucket, finals, 0)
	if view != "":
		m.set_view(view)
	## ★等落位 —— 90 帧。拍早了会量到"还在飞"的坐标(本仓栽过)。
	for _i in range(90):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [OUT, tag]
	img.save_png(p)
	_shots.append("%s  %dx%d" % [p, img.get_width(), img.get_height()])
	m.queue_free()
	await get_tree().process_frame
