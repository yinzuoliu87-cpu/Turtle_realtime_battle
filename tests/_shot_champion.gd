extends Node
## _shot_champion.gd —— 冠军收盘 / 组冠军 / 冠军杯开场 / 奖励链 / 冠军墙 的实拍与录屏台(探针, 不进门禁)。
## 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 D。数据 = tests/_champion_fixture.gd(24 人 · 6 组 · 第 4 届)。
##
## 关键帧(两比例各跑一次; 每张按「拍名 + 拍内时间」定格, 手动喂时间, 与帧率无关):
##   SHOT_DIR=C:/tmp/sunday_redo/D/shots/1560x720 WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/_shot_champion.tscn
## 录屏(REC=1; Movie Maker 下 游戏秒 = 视频秒; 一律 1280×720):
##   REC=1 WINDOW=1 bash godot-quiet.sh --position 2000,80 --write-movie C:/tmp/sunday_redo/D/reel.avi --fixed-fps 60 res://tests/_shot_champion.tscn

const FIX := preload("res://tests/_champion_fixture.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const SHOW := preload("res://scripts/scenes/bracket/champion_show.gd")
const INTRO := preload("res://scripts/scenes/bracket/champion_intro.gd")
const REW := preload("res://scripts/scenes/bracket/champion_rewards.gd")
const WALL := preload("res://scripts/scenes/bracket/champion_wall.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DT := 1.0 / 60.0

var _dir := ""


func _ready() -> void:
	## 宿主屏的替身: 一张压暗的竞技场(真宿主是对阵图 / 观战页, 它们这会儿各有分身在改)
	var bg := ColorRect.new()
	bg.color = Color("#141018")
	bg.size = get_viewport().get_visible_rect().size
	add_child(bg)
	if OS.get_environment("REC") == "1":
		await _reel()
		get_tree().quit(0)
		return
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = "C:/tmp/sunday_redo/D/shots"
	DirAccess.make_dir_recursive_absolute(_dir)
	await _shots()
	get_tree().quit(0)


func cup_data() -> Dictionary:
	var d: Dictionary = DATA.cup_show(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
	## 演示用第二张(真数据要服务端补 top_dmg, 见报告)
	d["bests"] = (d["bests"] as Array) + [{"kind": "num", "title": "单场最高伤害", "value": "18420", "value_num": 18420,
		"who": "凤凰之羽", "sub": "冠军杯 · 决赛", "turtle": "phoenix"}]
	d["rewards"] = DATA.reward_pages([P2C.TITLE_CHAMPION, P2C.TITLE_SEMIFINAL], 3)
	d["coin_from"] = 40
	d["wall_entries"] = wall_entries()
	return d


func wall_entries() -> Array:
	var out: Array = [DATA.wall_entry(FIX.WEEK, FIX.view(), FIX.rows())]
	var more := [["北极光", "B 组冠军", ["angel", "diamond", "fortune"], "浪花", 21],
		["夜行者", "A 组冠军", ["pirate", "candy", "bubble"], "火山岩", 19], ["深海小龟王", "C 组冠军", ["phoenix", "lava", "shell"], "蓝鲸", 16]]
	for k in range(more.size()):
		var wk: int = FIX.WEEK - (k + 1) * DATA.WEEK_SEC
		var m: Array = more[k]
		out.append({"week": wk, "edition": DATA.edition_of(wk), "date": DATA.date_text(wk), "name": m[0], "origin": m[1],
			"avatar": str(m[2][0]), "lineup": m[2], "runner_up": m[3], "entrants": m[4],
			"replay": {"week": wk, "bucket": 99, "round": 3, "match": 0}})
	return out


func _snap(nm: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [_dir, nm]
	img.save_png(p)
	print("SHOT_SAVED %s %dx%d" % [p, img.get_width(), img.get_height()])


## 把一层喂到「拍名 + 拍内时间」。
func _to(s, beat: String, bt: float) -> void:
	var guard := 0
	while guard < 60 * 40 and not (s.current_beat() == beat and s.bt >= bt):
		s.advance(DT)
		guard += 1


func _shots() -> void:
	var s = SHOW.create(cup_data())
	s.auto_advance = false
	add_child(s)
	await get_tree().process_frame
	for k in [["reveal", 0.5, "cup_01a_reveal_start"], ["reveal", 1.3, "cup_01_reveal"], ["runner", 1.2, "cup_02_runner"], ["crown", 0.8, "cup_03_charge"],
			["crown", 1.03, "cup_04_flash"], ["crown", 1.6, "cup_05_trophy_rise"], ["crown", 3.2, "cup_06_crown"],
			["lineup", 0.62, "cup_07_lineup_first_lands"], ["lineup", 2.5, "cup_08_lineup_row"], ["path", 0.62, "cup_09a_path_stamp"], ["path", 2.05, "cup_09_path"],
			["bests", 1.6, "cup_10_bests"], ["card", 0.7, "cup_11_card"]]:
		_to(s, k[0], k[1])
		await _snap(k[2])
	(s.node("BtnClaim") as Button).pressed.emit()
	await get_tree().process_frame
	var rw = _child_of(REW)
	rw.auto_advance = false
	for _i in range(int(1.47 / DT)):
		rw.advance(DT)
	await _snap("rew_01a_stamp_hit")
	for _i in range(int(0.45 / DT)):
		rw.advance(DT)
	await _snap("rew_01_title")
	(rw.node("BtnNext") as Button).pressed.emit()
	await get_tree().process_frame
	for _i in range(int(1.55 / DT)):
		rw.advance(DT)
	await _snap("rew_02_coins_flying")
	for _i in range(int(1.2 / DT)):
		rw.advance(DT)
	await _snap("rew_03_coins_done")
	(rw.node("BtnNext") as Button).pressed.emit()
	await get_tree().process_frame
	await _snap("cup_12_card_after_claim")
	s.queue_free()
	await get_tree().process_frame
	var g = SHOW.create(DATA.group_show(FIX.view(), 2, FIX.WEEK, FIX.rows(), "", "晋级冠军杯 · 20:00 开赛"))
	g.auto_advance = false
	add_child(g)
	await get_tree().process_frame
	for k in [["crown", 2.8, "grp_01_crown"], ["card", 0.7, "grp_02_card"]]:
		_to(g, k[0], k[1])
		await _snap(k[2])
	g.queue_free()
	await get_tree().process_frame
	var it = INTRO.create(DATA.cup_intro(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0)))
	it.auto_advance = false
	add_child(it)
	await get_tree().process_frame
	for k in [[0.9 + 0.45, "intro_01_first"], [0.9 + 4.5, "intro_02_defending"], [0.9 + 6.0 + 0.6, "intro_03_end"]]:
		while it.t < float(k[0]):
			it.advance(DT)
		await _snap(k[1])
	it.queue_free()
	await get_tree().process_frame
	var w = WALL.create({"entries": wall_entries()})
	add_child(w)
	await get_tree().process_frame
	await _snap("wall_01")
	w.queue_free()


func _child_of(script) -> Node:
	for ch in get_children():
		if ch.get_script() == script:
			return ch
	return null


func _sec(s: float) -> void:
	for _i in range(int(s * 60.0)):
		await get_tree().process_frame


## 录屏: 开场亮相 → 组冠军 → 冠军杯收盘(不点, 真时长)→ 领取奖励 → 冠军墙。
func _reel() -> void:
	var it = INTRO.create(DATA.cup_intro(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0)))
	add_child(it)
	## 段与段之间不留黑场: 下一段在上一段收尾时就叠上来(层级更高, 自己的竞技场背景淡入盖住上一段)
	await _sec(it.total_length() - 0.35)
	var g = SHOW.create(DATA.group_show(FIX.view(), 2, FIX.WEEK, FIX.rows(), "", "晋级冠军杯 · 20:00 开赛"))
	add_child(g)
	await _sec(g.total_length() + 1.6)
	var s = SHOW.create(cup_data())
	add_child(s)
	await _sec(0.5)
	g.queue_free()
	await _sec(s.total_length() + 1.5)
	(s.node("BtnClaim") as Button).pressed.emit()
	await get_tree().process_frame
	var rw = _child_of(REW)
	await _sec(REW.ANIM_TITLE + 1.0)
	(rw.node("BtnNext") as Button).pressed.emit()
	await _sec(REW.ANIM_COINS + 1.0)
	(rw.node("BtnNext") as Button).pressed.emit()
	await _sec(1.2)
	(s.node("BtnWall") as Button).pressed.emit()
	await _sec(3.5)
