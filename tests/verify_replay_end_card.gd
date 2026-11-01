extends Node
## verify_replay_end_card.gd — 每场结束分三拍(2026-10-31 重做, 方案书 docs/plans/20261031c-周日赛事界面重做.md P1 / C 块 ②③④⑧ · G8 G18 G25 P16)
##
## 由来: 用户「比如这个框，这是商业游戏吗」—— 原来看完一场只弹「X 获胜 / A 对 B / 返回对阵图」三行字, 三种情况同一张卡。
##   商业做法(研究笔记 §二.2): 标语 → 双方结果(阵容卡: 阵亡划掉、赢家发光、三路比分)→ 我的处境与奖励; 自动前进, 点一下只跳到这一拍终态。
## 量需求本身(不量我的钩子):
##   ① 三种情况的标语: 看别人 = 横幅「X 获胜」/ 自己赢 = 「胜利」(普通结算那张美术字)/ 自己输 = 「惜败」(不用红字); 中断 = 一颗按钮
##   ② ★时长落在 G8 区间: 看别人约 4 秒 / 自己赢约 7 秒 / 自己输约 6 秒; 第一拍只压一条带(整屏不暗、双方卡还没出来)
##   ③ ★点一下只跳到这一拍的终态(不是跳完整段); 不点也会每帧自己往前走
##   ④ 第二拍: 比分从 0 逐路加; 三路灯一路一盏、灯在赢下它的那一边; 阵亡的统领划掉(按收尾那一刻的单位表); 赢家发光、输家压灰下沉
##   ⑤ 第三拍: 自己赢 = 晋级那一行 + 本轮奖励(+8 深海币 +2 经验, 数字滚到终值); 自己输 = 出局卡「止步半决赛，不敌 X」+ 名次 + 奖励
##   ⑥ ★出局卡主按钮 =「去看 X 对 Y」(下一场, G25); 按下 ⇒ 回对阵图并挂上那一场(对阵图到点自动开播, G18); 下一场到点自动跟过去
##   ⑦ ★P16: 「返回对阵图」回到刚才在看的那一组(挂上 view / bucket); 看别人(决赛日)三拍走完自动回, 顺带挂上下一场
##   ⑧ 按钮: 一开始不可见且不吃点击; 皮 = card_button, 高 ≥ 81; 回放有「再看一遍」在左
##   ⑨ ★版式: 手机 1560×720 / iPad iPad 逻辑 1280×960 × 三种情况, 实建节点两两不重叠、不出屏
##   ⑩ 不出现胜率 / 本场还剩 / 观看人数
##   ⑪ 冠军杯决赛: 第二拍落定交给冠军仪式(组 finals_champion 里有节点 ⇒ 它接管、卡收起)
##   ⑫ 纯函数: 认我是哪一边 / 补定局那一路 / 名次 / 晋级行 / 阵亡 / 跳拍
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_replay_end_card.tscn

const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const EB := preload("res://scripts/scenes/battle/finals_end_beats.gd")
const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const BRACKET := "res://scenes/BracketMap.tscn"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


class FakeReplay extends RefCounted:
	var mode := "play"
	var live = null
	var rec: Dictionary = {}
	var finished := false
	var diverged_at := -1
	var speed := 1.0
	var paused := false
	var player = null
	func is_live() -> bool:
		return live != null and mode == "play"
	func total_steps() -> int:
		return int((rec.get("end", {}) as Dictionary).get("s", -1))
	func fight_steps() -> Array:
		return [0, 2400, 4800]
	func cycle_speed() -> float:
		return speed


class FakeHud extends RefCounted:
	var exits := 0
	func _replay_exit() -> void:
		exits += 1


class FakeBattle extends Node:
	var _replay
	var _hud
	var _dmg_stats = null
	var _ui_layer: CanvasLayer = null
	var _sim_step_n := 0
	var _units: Array = []
	var _dl_state := "fight"
	var _dl_pending_loser := ""


class ChampProbe extends Node:
	var calls := 0
	func on_cup_final_end(_info: Dictionary, _host: Control) -> void:
		calls += 1


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


const STAGE := {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2}
const NEXT := {"a": "甲乙丙", "b": "丁戊己", "at": 0, "r": 2, "m": 1}


func _make(c: Dictionary) -> Array:
	var gs = get_node("/root/GameState")
	gs.lane_results = (c["lr"] as Dictionary).duplicate()
	gs.current_lane = str(c["cur"])
	gs.season_leaders = (c["leaders"] as Array).duplicate()
	gs.dual_lineup = {"top": [{"kind": "leader", "slot": 0}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "slot": 1}, {"kind": "leader", "slot": 2}]}
	gs.dual_ghost = {"leaders": c["foe_leaders"], "lane_assign": {"top": [c["foe_leaders"][0]], "bottom": [c["foe_leaders"][1], c["foe_leaders"][2]]},
		"profile": {"name": c["foe"], "avatar": c["foe_leaders"][0]}}
	ReplayRecorder.play_names = (c["pn"] as Dictionary).duplicate(true)
	ReplayRecorder.viewer_name = str(c["viewer"])
	ReplayRecorder.return_scene = str(c.get("back", BRACKET))
	var fb := FakeBattle.new()
	fb._replay = FakeReplay.new()
	fb._replay.rec = {"end": {"s": 6720}, "state": {"dual_ghost": gs.dual_ghost.duplicate(true)}}
	fb._hud = FakeHud.new()
	fb._ui_layer = CanvasLayer.new()
	fb._ui_layer.layer = 10
	fb._units = (c.get("units", []) as Array).duplicate(true)
	fb.add_child(fb._ui_layer)
	add_child(fb)
	var ui = RC.new(fb)
	ui.build()
	if bool(c.get("broken", false)):
		ui.show_mismatch()
	else:
		ui._end_card(bool(c["won"]), false)
	return [fb, ui]


func _labels(n: Node) -> Array:
	var out: Array = []
	for l in n.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	for b in n.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func _btns(card: Node) -> Array:
	var out: Array = []
	for b in card.find_children("*", "Button", true, false):
		out.append(b)
	return out


func _ready() -> void:
	print("=== 每场结束分三拍(看别人 / 自己赢 / 自己输 / 中断) ===")
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	var keep := {"lr": gs.lane_results, "cur": gs.current_lane, "ld": gs.season_leaders, "dg": gs.dual_ghost, "lu": gs.dual_lineup,
		"pn": ReplayRecorder.play_names, "vn": ReplayRecorder.viewer_name, "rs": ReplayRecorder.return_scene}
	_t_pure()
	await _t_bar_dock()
	await _t_cases()
	await _t_layout()
	await _t_champion()
	gs.lane_results = keep["lr"]
	gs.current_lane = keep["cur"]
	gs.season_leaders = keep["ld"]
	gs.dual_ghost = keep["dg"]
	gs.dual_lineup = keep["lu"]
	ReplayRecorder.play_names = keep["pn"]
	ReplayRecorder.viewer_name = keep["vn"]
	ReplayRecorder.return_scene = keep["rs"]
	Ctx.follow = {}
	print("=== %d 项, %d FAIL ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


# ⑫ ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	_ok("⑫ 状态流·上路碎蛋(各路结果还没到)⇒ 1:0", str(EB.end_lanes({}, "right", "top", true)) == str([["top", "right"]]))
	_ok("⑫ 状态流·终极战场(只到上下路)⇒ 2:1", str(EB.end_lanes({"top": "left", "bottom": "right"}, "right", "final", true))
		== str([["top", "left"], ["bottom", "right"], ["final", "right"]]))
	_ok("⑫ 胜方已拿满两路 ⇒ 不再补", EB.end_lanes({"top": "left", "bottom": "left"}, "left", "final", true).size() == 2)
	_ok("⑫ 本机重算的回放不补", EB.end_lanes({"top": "left"}, "left", "top", false).size() == 1)
	var sc2: Dictionary = EB.end_score([], "left", 1)
	_ok("⑫ 没有各路结果 ⇒ 用入口给的比分代码(1 = 2:1)", int(sc2["left"]) == 2 and int(sc2["right"]) == 1, str(sc2))
	_ok("⑫ 名次: 8 签半决赛 = 第 3~4 名 / 首轮 = 第 5~8 名 / 决赛 = 亚军 / 小组首轮 = 小组第 3~4 名",
		EB.place_text(2, 3, true) == "第 3~4 名" and EB.place_text(1, 3, true) == "第 5~8 名" and EB.place_text(3, 3, true) == "亚军"
		and EB.place_text(1, 2, false) == "小组第 3~4 名")
	_ok("⑫ 晋级行: 「晋级决赛」/ 赢下决赛「冠军杯赛冠军」/ 没给轮次不写", EB.advance_line(STAGE) == "晋级决赛"
		and EB.advance_line({"cup": true, "round": 3, "rounds": 3}) == "冠军杯赛冠军" and EB.advance_line({}) == "")
	var nm := {"l": "甲", "r": "乙"}
	_ok("⑫ 认我是哪一边: 战绩页 = 左 / side b = 右 / 入口 me = pair 里那一个 / 不在这一场 = 看别人",
		EB.me_side_of(nm, {}, "") == "left" and EB.me_side_of(nm, {"l": "甲", "r": "乙", "side": "b"}, "") == "right"
		and EB.me_side_of(nm, {"pair": ["乙", "甲"], "me": 0}, "丙") == "right"
		and EB.me_side_of(nm, {"pair": ["甲", "乙"], "me": -1}, "甲") == "")
	var units := [{"id": "a", "side": "left", "alive": false}, {"id": "b", "side": "left", "alive": true}]
	_ok("⑫ ★阵亡: 场上死了 ⇒ 划; 场上活着 ⇒ 不划; 不在场上 ⇒ 输的一方划、赢的一方不划",
		str(EB.fallen(["a", "b", "c"], "left", units, "left")) == str([true, false, false])
		and str(EB.fallen(["a", "b", "c"], "left", units, "right")) == str([true, false, true]))
	_ok("⑫ ★跳拍: 第一拍里点 ⇒ 跳到第一拍终点(不是整段); 最后一拍里点 ⇒ 全长",
		is_equal_approx(EB.skip_to("win", 0.3), 1.4) and is_equal_approx(EB.skip_to("win", 2.0), 4.0)
		and is_equal_approx(EB.skip_to("win", 5.0), EB.total_of("win")))
	_ok("⑫ ★G8 时长: 看别人 %.1f 秒(3.5~4.5)/ 自己赢 %.1f 秒(6.5~7.5)/ 自己输 %.1f 秒(5.5~6.5)" % [EB.total_of("watch"),
		EB.total_of("win"), EB.total_of("lose")], EB.total_of("watch") >= 3.5 and EB.total_of("watch") <= 4.5
		and EB.total_of("win") >= 6.5 and EB.total_of("win") <= 7.5 and EB.total_of("lose") >= 5.5 and EB.total_of("lose") <= 6.5)


# ①~⑧ ─────────────────────────────────────────────────────────────
func _cases() -> Array:
	return [
		{"tag": "看别人", "won": false, "viewer": "吃货一枚", "leaders": ["stone", "basic", "bamboo"], "foe": "头发多多",
			"foe_leaders": ["angel", "candy", "ninja"], "lr": {"top": "right", "bottom": "left", "final": "right"}, "cur": "final",
			"pn": {"l": "头发多多", "r": "头发多多", "pair": ["ykx1314", "头发多多"], "me": -1, "stage": STAGE, "next": NEXT,
				"view": "finals", "bucket": 1000000},
			"units": [{"id": "angel", "side": "right", "alive": true}, {"id": "candy", "side": "right", "alive": false}],
			"title": "头发多多 获胜", "case": "watch", "score": [1, 2]},
		{"tag": "自己赢", "won": true, "viewer": "吃货一枚", "leaders": ["ninja", "basic", "bamboo"], "foe": "小辉同学",
			"foe_leaders": ["candy", "stone", "angel"], "lr": {"top": "left", "bottom": "left"}, "cur": "bottom",
			"pn": {"l": "吃货一枚", "r": "小辉同学", "pair": ["吃货一枚", "小辉同学"], "me": 0, "stage": STAGE, "next": NEXT,
				"view": "finals", "bucket": 1000000},
			"units": [{"id": "basic", "side": "left", "alive": true}, {"id": "bamboo", "side": "left", "alive": false}],
			"title": "胜利", "case": "win", "score": [2, 0]},
		{"tag": "自己输", "won": false, "viewer": "吃货一枚", "leaders": ["ghost", "basic", "bamboo"], "foe": "头发多多",
			"foe_leaders": ["angel", "candy", "ninja"], "lr": {"top": "left", "bottom": "right", "final": "right"}, "cur": "final",
			"pn": {"l": "头发多多", "r": "头发多多", "pair": ["吃货一枚", "头发多多"], "me": 0, "stage": STAGE, "next": NEXT,
				"view": "group:3", "bucket": 2},
			"units": [{"id": "angel", "side": "right", "alive": true}],
			"title": "惜败", "case": "lose", "score": [1, 2]},
	]


func _t_cases() -> void:
	for c in _cases():
		await _t_one(c)
	await _t_broken()
	await _t_record_replay()


func _t_one(c: Dictionary) -> void:
	var tag := str(c["tag"])
	Ctx.follow = {}
	var made: Array = _make(c)
	var fb: Node = made[0]
	var ui = made[1]
	var card: ColorRect = ui.card
	var bt = ui.beats
	_ok("%s 分母: 出了收尾(三拍那一层)" % tag, card != null and is_instance_valid(card) and bt != null)
	if card == null or bt == null:
		fb.queue_free()
		return
	var cs := str(c["case"])
	var times: Array = EB.beat_times(cs)
	## ① 标语
	var res := card.find_child(EB.N_RESULT, true, false) as Label
	_ok("%s ① 标语「%s」" % [tag, str(c["title"])], res != null and res.text == str(c["title"]), res.text if res != null else "<无>")
	_ok("%s ① 情况 = %s" % [tag, cs], str(bt.info["case"]) == cs)
	if cs == "watch":
		var wr := card.find_child("EndWinner", true, false)
		_ok("%s ① ★看别人 = 缎带里「胜者名字 +『获胜』美术字」(大字不拿小字放大)" % tag, card.find_child(EB.N_RIBBON, true, false) != null
			and wr != null and wr.find_child(Ctx.ART_NODE, true, false) != null and (res as CanvasItem).self_modulate.a < 0.01)
	if cs == "win":
		_ok("%s ① 「胜利」贴的是普通结算那张美术字" % tag, res.get_node_or_null(BigTitle.ART_NODE) != null)
	if cs == "lose":
		var art := res.get_node_or_null(Ctx.ART_NODE) as TextureRect
		_ok("%s ① ★「惜败」是冷色美术字(bt-xibai), 不用红" % tag, art != null and art.texture != null
			and art.texture.resource_path.get_file() == "bt-xibai.png" and res.self_modulate.a < 0.01)
	## ② 第一拍: 只压一条带, 整屏不暗、双方卡还没出来
	bt.pose(float(times[0][1]) + 0.5)
	var side_l := card.find_child(EB.N_SIDE + "left", true, false) as Control
	_ok("%s ② ★第一拍(%.1f 秒)只有标语: 整屏不暗(a=%.2f)、双方卡不可见" % [tag, float(times[0][2]), card.color.a],
		card.color.a < 0.05 and side_l != null and side_l.modulate.a < 0.05)
	## ③ 点一下: 只跳到这一拍终点
	bt.t = 0.3
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.gui_input.emit(ev)
	_ok("%s ③ ★第一拍里点一下 ⇒ t = %.2f(第一拍终点 %.2f, 不是全长 %.2f)" % [tag, float(bt.t), float(times[0][2]), EB.total_of(cs)],
		is_equal_approx(float(bt.t), float(times[0][2])))
	## ④ 第二拍: 比分逐路加 + 灯
	var t2: float = float(times[1][1])
	bt.pose(t2 + 0.05)
	var dl := card.find_child(EB.N_SCORE + "left", true, false) as Label
	var dr := card.find_child(EB.N_SCORE + "right", true, false) as Label
	_ok("%s ④ 第二拍刚开始: 比分 0 : 0" % tag, dl.text == "0" and dr.text == "0")
	var lr: Dictionary = c["lr"]
	var first_lane := ""
	for ln in ["top", "bottom", "final"]:
		if lr.has(ln):
			first_lane = ln
			break
	bt.pose(EB.lamp_t(t2, 0) + 0.05)
	var fs := str(lr[first_lane])
	var one_up: bool = (card.find_child(EB.N_SCORE + fs, true, false) as Label).text == "1" \
		and (card.find_child(EB.N_SCORE + ("right" if fs == "left" else "left"), true, false) as Label).text == "0"
	_ok("%s ④ ★第一盏灯亮那一刻只有赢下它的那一边是 1" % tag, one_up)
	bt.pose(float(times[1][2]))
	var want: Array = c["score"]
	_ok("%s ④ ★第二拍终了比分 %d : %d" % [tag, int(want[0]), int(want[1])], dl.text == str(want[0]) and dr.text == str(want[1]),
		"%s : %s" % [dl.text, dr.text])
	var art_l := dl.get_node_or_null(Ctx.ART_NODE) as TextureRect
	var art_r := dr.get_node_or_null(Ctx.ART_NODE) as TextureRect
	var wi := "left" if bool(c["won"]) else "right"
	var gold_ok: bool = art_l != null and art_r != null \
		and art_l.texture.resource_path.get_file() == ("bt-n%d.png" if wi == "left" else "bt-g%d.png") % int(want[0]) \
		and art_r.texture.resource_path.get_file() == ("bt-n%d.png" if wi == "right" else "bt-g%d.png") % int(want[1])
	_ok("%s ④ 比分是美术字数字: 赢的一边金、另一边冷灰" % tag, gold_ok)
	var lamp_bad: Array = []
	var cx: float = 780.0
	for ln in ["top", "bottom", "final"]:
		var lp := card.find_child(EB.N_LAMP + ln, true, false) as Control
		if lp == null:
			lamp_bad.append(ln + " 没有灯")
			continue
		var sd := str(lp.get_meta("side", ""))
		if sd != str(lr.get(ln, "")) or (sd != "" and float(lp.get_meta("lit", 0.0)) < 0.99) or (sd == "" and float(lp.get_meta("lit", 0.0)) > 0.0):
			lamp_bad.append("%s→%s lit %.2f" % [ln, sd, float(lp.get_meta("lit", 0.0))])
	_ok("%s ④ ★三路灯: 打过的路一盏一盏亮(灯 = 赢下那一路的那一边), 没打的不亮" % tag, lamp_bad.is_empty(), str(lamp_bad))
	## 阵亡划掉
	var chips: Array = card.find_children(EB.N_CHIP + "*", "", true, false)
	var fall_bad: Array = []
	var nfall := 0
	var win_side := "left" if bool(c["won"]) else "right"
	var exp_fall: Dictionary = {"left": EB.fallen(c["leaders"], "left", c["units"], win_side),
		"right": EB.fallen(c["foe_leaders"], "right", c["units"], win_side)}
	for ch in chips:
		var nmx := str((ch as Node).name).trim_prefix(EB.N_CHIP)
		var sd := nmx.get_slice("_", 0)
		var i := int(nmx.get_slice("_", 1))
		var f: bool = bool((ch as Node).get_meta("fallen", false))
		if f != bool((exp_fall[sd] as Array)[i]):
			fall_bad.append(nmx)
		if f:
			nfall += 1
			var xm := (ch as Node).get_node_or_null("Cross")
			if xm == null or float(xm.get_meta("p", 0.0)) < 0.99:
				fall_bad.append(nmx + " 没划完")
	_ok("%s ④ ★阵亡的统领划掉(%d 只头像, 划了 %d 只, 与单位表一致且到第二拍终了已划完)" % [tag, chips.size(), nfall],
		chips.size() == 6 and nfall >= 1 and fall_bad.is_empty(), str(fall_bad))
	var sw := card.find_child(EB.N_SIDE + win_side, true, false) as Control
	var sl := card.find_child(EB.N_SIDE + ("right" if win_side == "left" else "left"), true, false) as Control
	_ok("%s ④ ★赢家那张发光放大、输家压灰下沉(glow %.2f, 输家亮度 %.2f, 下沉 %.0f)" % [tag, float(sw.get_meta("glow", 0.0)),
		sl.modulate.r, sl.position.y - float(sw.position.y)],
		float(sw.get_meta("glow", 0.0)) > 0.3 and sw.scale.x > 1.02 and sl.modulate.r < 0.7 and sl.position.y > sw.position.y + 5.0)
	var hero := card.find_child(EB.N_HERO + win_side, true, false) as Control
	_ok("%s ④ 卡上是龟的立绘(不是名字首字)" % tag, hero != null and hero.find_child("Body", true, false) != null)
	## 名字带「（我）」
	var me_tag := 0
	for sd in ["left", "right"]:
		var nl := card.find_child(EB.N_NAME + sd, true, false) as Label
		if nl != null and nl.text.ends_with(EB.TXT_ME):
			me_tag += 1
	_ok("%s ④ 我的名字带「（我）」(看别人 0 个, 自己 1 个)" % tag, me_tag == (0 if cs == "watch" else 1))
	## ⑧ 按钮刚开始不可见、不吃点击
	bt.pose(0.0)
	var btns := _btns(card)
	var hid := true
	for b in btns:
		if (b as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			hid = false
	_ok("%s ⑧ 刚出来: 按钮全透明且不吃点击" % tag, hid and (card.find_child(EB.N_BTNS, true, false) as Control).modulate.a < 0.01
		and not btns.is_empty())
	## ⑤ 第三拍终态
	bt.t = EB.total_of(cs)
	bt.pose(bt.t)
	if cs == "win":
		var rk := card.find_child(EB.N_RANK, true, false) as Label
		_ok("%s ⑤ 晋级那一行「晋级决赛」(美术字)" % tag, rk != null and rk.text == "晋级决赛" and rk.get_node_or_null(Ctx.ART_NODE) != null,
			rk.text if rk != null else "<无>")
		_ok("%s ⑤ 自己赢的第三拍说自己(晋级 / 奖励), 不挂别人的下一场条" % tag, card.find_child(EB.N_NEXT, true, false) == null)
	if cs != "watch":
		var co := card.find_child("EndCoins", true, false) as Label
		var xp := card.find_child("EndXp", true, false) as Label
		_ok("%s ⑤ ★本轮奖励滚到终值「+8 深海币 / +2 经验」" % tag, co != null and co.text == "+8 深海币" and xp != null and xp.text == "+2 经验",
			("%s / %s" % [co.text, xp.text]) if co != null and xp != null else "<无>")
		bt.pose(float(times[2][1]) + 0.46)
		_ok("%s ⑤ 奖励是滚出来的(中途不是终值: %s)" % [tag, co.text if co != null else ""], co != null and co.text != "+8 深海币")
		var icons: Array = []
		for tr in (card.find_child(EB.N_REWARD, true, false) as Node).find_children("*", "TextureRect", true, false):
			icons.append(((tr as TextureRect).texture.resource_path.get_file()) if (tr as TextureRect).texture != null else "<空>")
		_ok("%s ⑤ 奖励图标 = 深海币 / 经验那两张(全游戏同一张货币图标)" % tag, icons == ["ic-deepsea.png", "icon-xp.png"], str(icons))
		bt.pose(bt.t)
	if cs == "lose":
		var ou := card.find_child(EB.N_OUT, true, false) as Label
		_ok("%s ⑤ ★出局卡「止步半决赛，不敌 头发多多」" % tag, ou != null and ou.text == "止步半决赛，不敌 头发多多", ou.text if ou != null else "<无>")
		var rk2 := card.find_child(EB.N_RANK, true, false) as Label
		_ok("%s ⑤ 名次「第 3~4 名」" % tag, rk2 != null and rk2.text == "第 3~4 名")
		var go := card.find_child(EB.N_GO, true, false) as Button
		var bk := card.find_child(EB.N_BACK, true, false) as Button
		await _frames(1)                      # 横排容器下一帧才排位置
		_ok("%s ⑥ ★出局卡主按钮「观看 甲乙丙 对 丁戊己」在右、比「返回对阵图」高且宽(主次分明)" % tag, go != null and go.text == "观看 甲乙丙 对 丁戊己"
			and bk != null and bk.text == "返回对阵图" and bk.get_global_rect().position.x < go.get_global_rect().position.x
			and bool(go.get_meta("primary", false)) and not bool(bk.get_meta("primary", false))
			and go.size.y > bk.size.y + 8.0 and go.size.x > bk.size.x)
		go.pressed.emit()
		_ok("%s ⑥ ★按「去看」⇒ 离场回对阵图, 挂上那一场(r 2 m 1)与刚才在看的组(group:3 / 2)" % tag, int(fb._hud.exits) == 1
			and int(Ctx.follow.get("r", -1)) == 2 and int(Ctx.follow.get("m", -1)) == 1 and str(Ctx.follow.get("view", "")) == "group:3"
			and int(Ctx.follow.get("bucket", -1)) == 2, str(Ctx.follow))
	if cs == "watch":
		var nx := card.find_child(EB.N_NEXT, true, false) as Label
		_ok("%s ⑤ 下一场条「下一场：甲乙丙 对 丁戊己」" % tag, nx != null and nx.text == "下一场：甲乙丙 对 丁戊己", nx.text if nx != null else "<无>")
		var ab := card.find_child(EB.N_AUTO, true, false) as Control
		_ok("%s ⑦ 决赛日看别人: 有自动回对阵图的进度条" % tag, ab != null)
		bt.t = EB.total_of(cs) + EB.AUTO_HOLD - 0.1
		bt._check_auto()
		_ok("%s ⑦ 还没到点不回" % tag, int(fb._hud.exits) == 0)
		bt.t = EB.total_of(cs) + EB.AUTO_HOLD + 0.01
		bt._check_auto()
		_ok("%s ⑦ ★三拍走完 + %.1f 秒自动回对阵图, 挂上刚才在看的组 + 下一场(P16 / G18)" % [tag, EB.AUTO_HOLD], int(fb._hud.exits) == 1
			and str(Ctx.follow.get("view", "")) == "finals" and int(Ctx.follow.get("r", -1)) == 2, str(Ctx.follow))
	if cs == "win":
		## ⑦ P16: 「返回对阵图」挂上刚才在看的组(不带下一场)
		var bk2 := card.find_child(EB.N_BACK, true, false) as Button
		bk2.pressed.emit()
		_ok("%s ⑦ ★「返回对阵图」⇒ 回刚才在看的组(view finals / bucket 1000000), 不挂下一场" % tag, int(fb._hud.exits) == 1
			and str(Ctx.follow.get("view", "")) == "finals" and int(Ctx.follow.get("bucket", -1)) == 1000000 and not Ctx.follow.has("r"),
			str(Ctx.follow))
		bk2.pressed.emit()
		_ok("%s ⑦ 离场只走一次(连点不重复换场景)" % tag, int(fb._hud.exits) == 1)
	## ⑧ 皮: 都是 card_button 那一套(StyleBoxFlat 实心底); 主按钮一颗、更大更亮、会呼吸; 其余降一级(card_button 原色、≥ 81 高)
	btns = _btns(card)
	var skin_ok := true
	var prim: Array = []
	for b in btns:
		var sb = (b as Button).get_theme_stylebox("normal")
		var p: bool = bool((b as Node).get_meta("primary", false))
		if p:
			prim.append(b)
		if not (sb is StyleBoxFlat) or (b as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
			skin_ok = false
		elif p and ((sb as StyleBoxFlat).bg_color != EB.PRIMARY_BG or (b as Control).size.y < EB.PRIMARY_H - 1.0):
			skin_ok = false
		elif not p and ((sb as StyleBoxFlat).bg_color != Color("#6a3f1c") or (b as Control).size.y < 81.0):
			skin_ok = false
	_ok("%s ⑧ 按钮皮 = card_button(实心底); 主按钮恰好一颗(亮底 / 高 %d), 次按钮原色 ≥ 81, 落定后吃点击(%d 颗)" % [tag, int(EB.PRIMARY_H), btns.size()],
		skin_ok and prim.size() == 1)
	if prim.size() == 1:
		var pb: Control = prim[0]
		var lo := 9.0
		var hi := 0.0
		for k in range(8):
			bt.pose(bt.t + 0.2 * float(k))
			lo = minf(lo, pb.scale.x)
			hi = maxf(hi, pb.scale.x)
		_ok("%s ⑧ ★主按钮在呼吸(1.4 秒里缩放 %.3f ~ %.3f)" % [tag, lo, hi], hi - lo > 0.03)
		bt.pose(bt.t)
	## ⑩
	var banned := ["胜率", "本场还剩", "观看人数", "人在看"]
	var hit: Array = []
	for s in _labels(card):
		for w in banned:
			if str(s).find(w) >= 0:
				hit.append(s)
	_ok("%s ⑩ 不出现胜率 / 本场还剩 / 观看人数" % tag, hit.is_empty(), str(hit))
	## ③ 不点也会走
	var t_before := float(bt.t)
	bt.t = 0.0
	await _frames(6)
	_ok("%s ③ 每帧自己往前走(t = %.3f > 0)" % [tag, float(bt.t)], float(bt.t) > 0.0)
	bt.t = t_before
	fb.queue_free()
	await _frames(2)


func _t_broken() -> void:
	var made: Array = _make({"broken": true, "won": false, "viewer": "吃货一枚", "leaders": ["basic", "stone", "bamboo"], "foe": "乙",
		"foe_leaders": ["stone", "angel", "candy"], "lr": {}, "cur": "top", "pn": {"l": "甲", "r": "乙"}})
	var fb: Node = made[0]
	var ui = made[1]
	var card: Control = ui.card
	ui.beats.skip_all()
	var res := card.find_child(EB.N_RESULT, true, false) as Label if card != null else null
	var btns := _btns(card) if card != null else []
	_ok("中断 ① 「回放中断」+ 一句原因, 只有一颗「返回对阵图」, 没有双方卡 / 比分", res != null and res.text == "回放中断"
		and btns.size() == 1 and (btns[0] as Button).text == "返回对阵图" and card.find_child(EB.N_SIDE + "left", true, false) == null
		and _labels(card).has("回放异常，无法继续播放"), str(_labels(card)) if card != null else "<无卡>")
	fb.queue_free()
	await _frames(2)


## 战绩页看自己的录像: 不是决赛日 ⇒ 不写奖励 / 不自动离场; 有「再看一遍」在左。
func _t_record_replay() -> void:
	Ctx.follow = {}
	var made: Array = _make({"won": true, "viewer": "吃货一枚", "leaders": ["basic", "stone", "bamboo"], "foe": "乙",
		"foe_leaders": ["stone", "angel", "candy"], "lr": {"top": "left", "bottom": "left"}, "cur": "bottom", "pn": {},
		"back": "res://scenes/Record.tscn"})
	var fb: Node = made[0]
	var ui = made[1]
	var card: Control = ui.card
	ui.beats.skip_all()
	await _frames(1)
	var ag := card.find_child(EB.N_AGAIN, true, false) as Button
	var bk := card.find_child(EB.N_BACK, true, false) as Button
	_ok("战绩页 ⑧ 「再看一遍」在左 +「返回战绩」; 没有奖励行 / 没有自动离场条", ag != null and bk != null and bk.text == "返回战绩"
		and ag.get_global_rect().position.x < bk.get_global_rect().position.x and card.find_child(EB.N_REWARD, true, false) == null
		and card.find_child(EB.N_AUTO, true, false) == null)
	ui.beats.t = 99.0
	ui.beats._check_auto()
	_ok("战绩页 ⑦ 不自动离场", int(fb._hud.exits) == 0)
	_ok("战绩页 ⑤ 全场时长「全场 1:52」", _labels(card).has("全场 1:52"), str(_labels(card)))
	bk.pressed.emit()
	_ok("战绩页 ⑦ 「返回」不挂对阵图跟播(不是决赛日)", int(fb._hud.exits) == 1 and Ctx.follow.is_empty(), str(Ctx.follow))
	fb.queue_free()
	await _frames(2)


# ⑨ ─────────────────────────────────────────────────────────────
## 两种比例 × 三种情况: 实建(直接按那个视口尺寸建)、落定到全长, 量关键块两两不重叠、不出屏。
func _t_layout() -> void:
	var bad: Array = []
	var nrect := 0
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		for c in _cases():
			var made: Array = _make(c)
			var fb: Node = made[0]
			var ui = made[1]
			var host := Control.new()
			host.size = vp
			add_child(host)
			var bt := EB.new(fb)
			var info: Dictionary = bt.end_info(bool(c["won"]), false, {"l": str(ui._names.get("l", "")), "r": str(ui._names.get("r", ""))}, false, false)
			var card := bt.build(host, info, vp)
			bt.skip_all()
			bt.pose(EB.total_of(str(info["case"])))
			await _frames(1)
			var eb := card.find_child("EndBody", true, false) as Control
			if eb == null or absf(eb.position.y - roundf((vp.y - minf(vp.y, 720.0)) * 0.5)) > 0.5:
				bad.append("%s %s 版心没有竖向居中" % [str(vp), c["tag"]])
			var rects: Array = []
			for nm in [EB.N_SIDE + "left", EB.N_SIDE + "right", EB.N_SCORE + "left", EB.N_SCORE + "right", EB.N_OUT, EB.N_RANK,
					EB.N_REWARD, EB.N_NEXT, EB.N_HEAD, EB.N_KICKER, EB.N_BAR_DOCK]:
				var nd := card.find_child(nm, true, false) as Control
				if nd != null and nd.visible:
					rects.append([nm, _ink_rect(nd)])
			for ln in ["top", "bottom", "final"]:
				var lp := card.find_child(EB.N_LAMP + ln, true, false) as Control
				if lp != null:
					rects.append([EB.N_LAMP + ln, lp.get_global_rect()])
			for b in _btns(card):
				rects.append([(b as Node).name, (b as Control).get_global_rect()])
			var scr := Rect2(Vector2.ZERO, vp)
			for i in range(rects.size()):
				nrect += 1
				var ri: Rect2 = rects[i][1]
				if not scr.encloses(ri.grow(-1.0)):
					bad.append("%s %s %s 出屏 %s" % [str(vp), c["tag"], rects[i][0], str(ri)])
				for j in range(i + 1, rects.size()):
					var rj: Rect2 = rects[j][1]
					if ri.grow(-1.0).intersects(rj.grow(-1.0)):
						bad.append("%s %s %s × %s" % [str(vp), c["tag"], rects[i][0], rects[j][0]])
			host.queue_free()
			fb.queue_free()
			await _frames(2)
	_ok("⑨ ★两种比例(1560×720 / iPad 逻辑 1280×960)× 三种情况: 双方卡 / 比分 / 三路灯 / 第三拍各行 / 按钮两两不重叠、不出屏(量了 %d 块)" % nrect,
		bad.is_empty() and nrect >= 60, str(bad))


## 一个块真正占的范围: 标签按字的墨迹宽(居中排在整行宽的框里, 框本身占满一行, 量框会误报)。
func _ink_rect(nd: Control) -> Rect2:
	var r := nd.get_global_rect()
	if nd is Label:
		var l := nd as Label
		var w: float = l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		var x0: float = r.position.x + (r.size.x - w) * 0.5 if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER else r.position.x
		return Rect2(x0, r.position.y, w, r.size.y)
	if nd is HBoxContainer:
		var mn := (nd as Control).get_combined_minimum_size()
		return Rect2(r.position.x + (r.size.x - mn.x) * 0.5, r.position.y, mn.x, r.size.y)
	return r


# ⑬ ─────────────────────────────────────────────────────────────
## 全局决赛日小条(autoload FinalsDay)在场时: 手机(版心上方没空)⇒ 小条停在赛事小字那一行正中, 赛事小字让出来、标语不压它;
##   iPad(逻辑 1280×960, 版心上方有 120 的空)⇒ 停在那一条里, 赛事小字照旧。小条不在场 ⇒ 不留停靠位(其余各条量的就是这一种)。
func _t_bar_dock() -> void:
	var fd = get_node_or_null("/root/FinalsDay")
	if fd == null:
		_ok("⑬ 分母: 全局决赛日小条在场(autoload FinalsDay)", false)
		return
	var was: bool = fd.bar.visible
	fd.bar.visible = true
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		var c: Dictionary = _cases()[1]
		var made: Array = _make(c)
		var fb: Node = made[0]
		var ui = made[1]
		var c0: Node = ui.card             # _make 按无头视口出的那一张先摘掉(只量按这个比例建的这一张)
		c0.get_parent().remove_child(c0)
		c0.queue_free()
		var host := Control.new()
		host.size = vp
		fb.add_child(host)
		fd.bar.visible = true              # _make 出卡时会让小条重新判一次在不在场(无头进程判不在), 这里再按「在场」摆回去
		var bt := EB.new(fb)
		var info: Dictionary = bt.end_info(true, false, {"l": "吃货一枚", "r": "小辉同学"}, false, false)
		var card := bt.build(host, info, vp)
		bt.skip_all()
		await _frames(1)
		var dk := card.find_child(EB.N_BAR_DOCK, true, false) as Control
		var hd := card.find_child(EB.N_HEAD, true, false) as Control
		var kk := card.find_child(EB.N_KICKER, true, false)
		fd.test_host = fb
		var picked: Rect2 = fd.dock_rect()
		fd.test_host = null
		var tall: bool = vp.y > 720.0
		_ok("⑬ ★%s 全局小条停靠位: %s(小条认的是它: %s); 赛事小字%s; 不压标语" % [str(vp), "版心上方那一条" if tall else "赛事小字那一行",
			str(picked), "照旧" if tall else "让出来"], dk != null and hd != null and picked.is_equal_approx(dk.get_global_rect())
			and (kk != null) == tall and not dk.get_global_rect().intersects(_ink_rect(hd)), str(dk.get_global_rect() if dk != null else null))
		fb.queue_free()
		await _frames(2)
	fd.bar.visible = was


# ⑪ ─────────────────────────────────────────────────────────────
func _t_champion() -> void:
	var probe := ChampProbe.new()
	probe.add_to_group(EB.CHAMPION_GROUP)
	add_child(probe)
	var st := {"cup": true, "round": 3, "rounds": 3, "round_name": "决赛"}
	var made: Array = _make({"won": true, "viewer": "看客", "leaders": ["basic", "stone", "bamboo"], "foe": "乙",
		"foe_leaders": ["stone", "angel", "candy"], "lr": {"top": "left", "bottom": "left"}, "cur": "bottom",
		"pn": {"l": "甲", "r": "乙", "pair": ["甲", "乙"], "me": -1, "stage": st, "view": "finals", "bucket": 1000000}})
	var fb: Node = made[0]
	var ui = made[1]
	var bt = ui.beats
	bt.pose(float(EB.beat_times("watch")[1][1]) + 0.5)
	_ok("⑪ 冠军杯决赛: 第二拍落定之前不交", probe.calls == 0)
	bt.pose(float(EB.beat_times("watch")[1][2]) + 0.01)
	_ok("⑪ ★冠军杯决赛: 第二拍落定交给冠军仪式(组里那个节点被调 1 次), 这一层收起", probe.calls == 1 and not (ui.card as Control).visible)
	_ok("⑪ 冠军杯决赛不自动回对阵图(冠军仪式接着放)", not bt._auto_back())
	probe.queue_free()
	fb.queue_free()
	await _frames(2)
