extends Node
## _shot_bracket_words.gd — 实拍: 周日对阵图**改词之后**屏幕上到底写着什么 (2026-09-28)
##
## 跑法(**不能 --headless**, 无头截不了图; 窗口静音 + 跑完自退 + 只放屏幕左下角):
##   APPDATA=/c/tmp/bm/ad TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
##     "$GODOT" --audio-driver Dummy --path . res://tests/_shot_bracket_words.tscn \
##     --position 0,312 --resolution 1280x720
##
## ★为什么要单独拍这一份(已经有 `shot_bracket_map.gd` 了): 那一份拍的是**版式**
##   (4 人 / 32 人 / 已翻面), 而这一轮改的是**空态那几句话** —— 而空态恰恰是
##   `shot_bracket_map` 只覆盖了一种(冠军赛未开)的地方。没晋级的人整个周日
##   看到的就只有空态那一屏, 它必须逐种拍过。
##
## ★等落位 420 帧, 不是 140 —— memory `fb-screenshot-must-settle-and-multi-ratio`:
##   140 帧拍出来过"还在飞"的坐标, 差点被当 bug 修。

const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")
const _SB := preload("res://scripts/net/supabase.gd")

const OUT := "C:/tmp/bm/shot"
const NAMES8 := ["小龟", "石头龟", "冰龟", "火龟", "电龟", "风龟", "毒龟", "铁龟"]
## 周日上午 10 点(冠军赛还没到点) —— 让「冠军赛」那一页走到 FINALS 那一支。
const SUN_AM := 1789862400 + 10 * 3600

var _shots: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame

	## ① 真图: 8 人一组 · 第 1 轮已翻面 · 当前第 2 轮 —— 看页签「我这一组」
	await _shot("1_对阵图_我这一组", {"size": 8, "round": 2, "me": 2, "names": NAMES8,
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}}, {}, "")

	## ② 空态·【本周没有你这一组】—— 没晋级的人整个周日只看得到这一屏
	await _shot("2_空态_没有你这一组", {}, {}, "")

	## ③ 空态·【冠军赛那一页】—— 原来这里印着「跨组总决赛还没做出来」(开发状态)
	await _shot("3_空态_冠军赛怎么算", {"size": 8, "round": 1, "me": 2, "names": NAMES8,
		"done": {}}, {}, _L.VIEW_FINALS)

	## ④ 空态·【连不上】—— 这一句**必须**与②是两句不同的话(对已晋级的人不能说谎)
	await _shot("4_空态_连不上", {"reason": _SB.UNREACHABLE}, {}, "")

	## ⑤ 空态·【人太少没开起来】
	await _shot("5_空态_人太少", {"reason": "too_few", "entered": 1}, {}, "")

	## ⑥ 空态·【还在找】—— 走「没人喂数据、也还没问到回音」那一格
	await _shot_wait("6_空态_还在找")

	print("")
	print("截了 %d 张 → %s" % [_shots.size(), OUT])
	for s in _shots:
		print("  " + str(s))
	get_tree().quit(0)


## 空态那句话一起打出来 —— 截图看不清的时候, 这一行就是原文。
func _say(m) -> void:
	if m._empty_lb != null and m._empty_lb.visible:
		print("    kind=%-12s 「%s」" % [str(m._empty_kind()), str(m._empty_lb.text)])
	else:
		print("    (不是空态: 画的是真图)  页签[0]=「%s」" % str((m._tabs.get_child(0) as Button).text))


func _shot(tag: String, bucket: Dictionary, finals: Dictionary, view: String) -> void:
	var m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	m.set_data(bucket, finals, SUN_AM)
	if view != "":
		m.set_view(view)
	await _settle(m, tag)


## 「还没问到回音」那一格: 不能用 `set_data()`(它会把 `_injected` 标上),
## ⇒ 直接把那两个前提摆成真实那一刻的样子, 再让它自己重画一次。
func _shot_wait(tag: String) -> void:
	var m = SCENE.new()
	get_tree().root.add_child(m)
	await get_tree().process_frame
	_SB.finals_clear()
	m._injected = false
	m._rebuild()
	await _settle(m, tag)


func _settle(m, tag: String) -> void:
	## ★420 帧: 140 帧不够(实拍抓到过没落位的)
	for _i in range(420):
		await get_tree().process_frame
	_say(m)
	var img: Image = get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [OUT, tag]
	img.save_png(p)
	_shots.append("%s  %dx%d" % [p, img.get_width(), img.get_height()])
	m.queue_free()
	await get_tree().process_frame
