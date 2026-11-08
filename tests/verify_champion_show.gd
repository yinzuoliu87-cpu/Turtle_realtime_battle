extends Node
## verify_champion_show.gd —— 周日冠军收盘与长期身份(方案书 docs/plans/20261031c-周日赛事界面重做.md 块 D, §6 第 5 条)
##
## 量需求本身(不量我的钩子), 每条都用**事件发生时刻**判(手动喂时间: auto_advance = false, 每步 1/60 秒, 不依赖 Tween / 帧率):
##   ① 冠军杯收盘各拍按顺序出现: 揭晓中 → 亚军 → 冠军仪式 → 夺冠阵容 → 夺冠之路 → 今晚之最 → 定格卡
##   ② 冠军仪式内部顺序: 白闪(满白)之前奖杯不露面; 白闪之后奖杯出现 →「冠军」大字 → 名字缎带 → 规模「24 人冠军」+「第 4 届 · 11 月 1 日」
##   ③ 总长(开演 → 定格卡落定、按钮出现)冠军杯 12~16 s, 组冠军 8~11 s(有 / 没有阵容两种)
##   ④ 整段(定格卡落定之前)场上没有一颗看得见 / 点得到的按钮; 落定后按钮皮 = card_button、高 ≥ 81
##   ⑤ 点屏 = 只把**这一拍**拨到终态(拍名不变、终态元素到位), 停 SKIP_HOLD 后才进下一拍; 不会一下跳过整段
##   ⑥ 真在动: 奖杯在浮、彩带在落、阵容卡逐只入场(出现时刻递增)、数字滚出来
##   ⑦ 组冠军缩短版: 没有亚军拍; 大字「组冠军」; 定格卡写晋级冠军杯
##   ⑧ 冠军杯开场(G7): 组冠军依次亮相(每人约 1 s, 来历「A 组冠军」), 上届冠军单独挂「卫冕」; 全程无按钮; 结束自删
##   ⑨ 奖励一件一页(G11): 先物件后数字; 按钮在这一页动画播完才出; 深海币**飞到**才入账(飞到之前顶栏数字不涨)
##   ⑩ 冠军墙(G12): 列出往届(新的在上)、届数日期冠军名; 有录像坐标的「决赛录像」能点, 发出 (周, 组, 决赛轮, 0)
##   ⑪ 纯函数: 冠军 / 亚军 / 来历 / 规模 / 夺冠之路(轮空、比分方向)/ 最快一场 / 届数日期 / 头衔「至下周日」/ 奖励页
##   ⑫ 版式: 手机 1560×720 / iPad 逻辑 1280×960 两种比例, 定格卡与各拍文字都在屏内
##   ⑬ 第二轮(主会话 10-31 逐帧审): 缎带字读得出(字 / 描边 / 缎带本体三方对比 + 字号)· 揭晓中有大字、呼吸、光束收拢 ·
##      阵容三只完整立绘、约 200px 高、最终居中、逐只落位 · 夺冠之路行宽行高 + 盖章进场 · 奖励卡大、背后不透明、章砸下回弹 ·
##      开场亮相那位占屏 1/3 高 · 像素标题字规矩(字号 12 倍 / 描边 字号÷3 / 落影 字号÷12)
##   ⑭ 交接: 观战收尾第二拍对组 finals_champion 调 on_cup_final_end(info, host) ⇒ 冠军收盘接手(数据取 info + 缓存)
## 跑法: TURTLE_SUPABASE=" " <godot> --headless --audio-driver Dummy --path . res://tests/verify_champion_show.tscn --quit-after 3000

const FIX := preload("res://tests/_champion_fixture.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const SHOW := preload("res://scripts/scenes/bracket/champion_show.gd")
const INTRO := preload("res://scripts/scenes/bracket/champion_intro.gd")
const REW := preload("res://scripts/scenes/bracket/champion_rewards.gd")
const WALL := preload("res://scripts/scenes/bracket/champion_wall.gd")
const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DT := 1.0 / 60.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	print("=== verify_champion_show ===")
	## 无头时窗口是 0×0, 不给根视口一个尺寸的话 push_input 的鼠标事件落不到任何控件上(与 verify_axe_evo_show 同一做法)
	get_tree().root.content_scale_size = Vector2i(1560, 720)
	get_tree().root.size = Vector2i(1560, 720)
	_t_pure()
	await _t_cup_full()
	await _t_skip()
	await _t_group()
	await _t_card_buttons()
	await _t_intro()
	await _t_rewards()
	await _t_wall()
	await _t_layout()
	await _t_round2()
	await _t_hook()
	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n >= 40:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


func _cup_data(vp := Vector2(1560, 720)) -> Dictionary:
	var d: Dictionary = DATA.cup_show(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
	d["bests"] = (d["bests"] as Array) + [{"kind": "num", "title": "单场最高伤害", "value": "18,420", "value_num": 18420,
		"who": "凤凰之羽", "sub": "冠军杯 · 决赛", "turtle": "phoenix"}]
	d["rewards"] = DATA.reward_pages([P2C.TITLE_CHAMPION, P2C.TITLE_SEMIFINAL])
	d["coin_from"] = 40
	d["vp"] = vp
	return d


func _mk(script, d: Dictionary) -> Node:
	var s = script.create(d)
	if "auto_advance" in s:
		s.auto_advance = false
	add_child(s)
	return s


func _vis_buttons(root: Node) -> int:
	var n := 0
	for b in UI.buttons_under(root):
		if (b as Control).is_visible_in_tree() or (b as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			n += 1
	return n


func _text(s: Node, nm: String) -> String:
	var n: Node = s.node(nm)
	if n is Label:
		return (n as Label).text
	if n != null:
		var t := n.find_child("Text", true, false) as Label
		if t != null:
			return t.text
	return ""


# ═══════════════════════════════════════════════════════════════════
func _t_pure() -> void:
	var v := FIX.view()
	## ⑪ 头像补充表(2026-10-31 B 录视频发现仪式全是默认龟: 对阵图开仪式时传 rows = [], 头像只从 rows 取)。
	##   不给 rows、只喂对阵图那份 #ID → 头像 ⇒ 冠军 / 亚军都要拿到; 量完清空, 不污染后面的断言。
	var d0: Dictionary = DATA.cup_show(v, FIX.WEEK, [], FIX.acc(4, 0))
	var c0: Dictionary = d0.get("champion", {})
	var r0: Dictionary = d0.get("runner_up", {})
	DATA.portraits = {str(c0.get("tag", "")): "phoenix", str(r0.get("tag", "")): "lava"}
	var d1: Dictionary = DATA.cup_show(v, FIX.WEEK, [], FIX.acc(4, 0))
	DATA.portraits = {}
	_ok("⑪ ★没有比赛记录时用对阵图喂的头像(冠军 phoenix / 亚军 lava)", str(c0.get("tag", "")) != ""
		and str((d1.get("champion", {}) as Dictionary).get("avatar", "")) == "phoenix"
		and str((d1.get("runner_up", {}) as Dictionary).get("avatar", "")) == "lava",
		"%s / %s" % [str((d1.get("champion", {}) as Dictionary).get("avatar", "")), str((d1.get("runner_up", {}) as Dictionary).get("avatar", ""))])
	var d: Dictionary = DATA.cup_show(v, FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
	var ch: Dictionary = d.get("champion", {})
	_ok("⑪ 冠军 = 杯决赛胜方(E 组冠军「凤凰之羽」), 亚军 = C 组冠军「火山岩」", str(ch.get("name", "")) == "凤凰之羽"
		and str((d.get("runner_up", {}) as Dictionary).get("name", "")) == "火山岩", str(ch))
	_ok("⑪ 来历「E 组冠军」/ 亚军来历「C 组冠军」", str(ch.get("origin", "")) == "E 组冠军"
		and str((d["runner_up"] as Dictionary).get("origin", "")) == "C 组冠军")
	_ok("⑪ 规模 = 各组人数之和 24", int(d.get("entrants", 0)) == 24)
	_ok("⑪ 夺冠阵容 = 冠军那几行的三统领", d.get("lineup", []) == ["hiding", "headless", "rainbow"], str(d.get("lineup")))
	_ok("⑪ 头像 = 行里的 profile 头像", str(ch.get("avatar", "")) == "hiding")
	_ok("⑪ 看的人是冠军本人 ⇒ viewer_is_champion", bool(d.get("viewer_is_champion", false))
		and not bool(DATA.cup_show(v, FIX.WEEK, FIX.rows(), FIX.acc(0, 0)).get("viewer_is_champion", true)))
	var p: Array = d.get("path", [])
	_ok("⑪ 夺冠之路 3 轮: 1/4 决赛 对 北极光 2:0 胜 / 半决赛 对 深海小龟王 2:1 胜 / 决赛 对 火山岩 2:1 胜", p.size() == 3
		and str(p[0]["round"]) == "1/4 决赛" and str(p[0]["foe"]) == "北极光" and p[0]["score"] == [2, 0] and bool(p[0]["won"])
		and str(p[1]["round"]) == "半决赛" and str(p[1]["foe"]) == "深海小龟王" and p[1]["score"] == [2, 1]
		and str(p[2]["round"]) == "决赛" and str(p[2]["foe"]) == "火山岩" and p[2]["score"] == [2, 1] and bool(p[2]["won"]), str(p))
	var p0: Array = DATA.path_of(v["cup"], 0, {}, false)
	_ok("⑪ 轮空那一轮写「轮空」(0 号种子首轮轮空, 半决赛输)", p0.size() == 2 and bool(p0[0]["bye"]) and str(p0[0]["foe"]) == ""
		and not bool(p0[1]["won"]) and p0[1]["score"] == [1, 2], str(p0))
	var bs: Array = DATA.best_cards(v, FIX.rows())
	_ok("⑪ 今晚之最 · 最快结束 = C 组半决赛 1:12(行里 steps 最小那一场)", bs.size() == 1 and str(bs[0]["value"]) == "1:12"
		and str(bs[0]["sub"]).contains("C 组半决赛") and str(bs[0]["who"]) == "暗流", str(bs))
	_ok("⑪ 没有 matches 行 ⇒ 今晚之最 0 张(不编)", DATA.best_cards(v, []).is_empty())
	var rr: Array = FIX.rows()
	var refd: Dictionary = (rr[17] as Dictionary).duplicate(true)
	(refd["result"] as Dictionary)["referee"] = true
	rr.append(refd)
	var bs2: Array = DATA.best_cards(v, rr)
	_ok("⑪ 有裁判写回的行 ⇒ 只认裁判那几行(本机那份更快的 1:12 不算)", bs2.size() == 1 and str(bs2[0]["value"]) != "1:12"
		and str(bs2[0]["sub"]).contains("F 组决赛"), str(bs2))
	## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 届次与日期两个并列名词用全角空格隔开, 不用「·」
	_ok("⑪ 届数 / 日期: 10-26 那一周 = 第 4 届　11 月 1 日", DATA.edition_of(FIX.WEEK) == 4 and DATA.date_text(FIX.WEEK) == "11 月 1 日"
		and DATA.edition_line(FIX.WEEK) == "第 4 届　11 月 1 日")
	_ok("⑪ 头衔写明「至下周日」", DATA.title_until_line().contains("至下周日"))
	var rp: Array = DATA.reward_pages([P2C.TITLE_CHAMPION, P2C.TITLE_SEMIFINAL, P2C.TITLE_FINALS_DAY])
	## ★2026-11-08 用户「为什么获得冠军之后还讲深海币啊？…你每轮每轮就应该发呀」⇒ 不再有「深海币入账」那一页(轮次币每轮出结果就发)
	_ok("⑪ 奖励页: 只放最高那档头衔一页, 没有深海币页", rp.size() == 1 and str(rp[0]["kind"]) == "title"
		and str(rp[0]["name"]) == "冠军" and rp.all(func(pg): return str(pg["kind"]) != "coins"), str(rp))
	var gs: Dictionary = DATA.group_show(v, 2, FIX.WEEK, FIX.rows())
	_ok("⑪ 组冠军: C 组 0 号「火山岩」, 规模 4, 夺冠之路 半决赛 / 组决赛", str((gs.get("champion", {}) as Dictionary).get("name", "")) == "火山岩"
		and int(gs.get("entrants", 0)) == 4 and str(gs.get("group", "")) == "C 组" and (gs.get("path", []) as Array).size() == 2
		and str(gs["path"][1]["round"]) == "组决赛", str(gs.get("path")))
	var prev := FIX.view()
	var it: Dictionary = DATA.cup_intro(v, FIX.WEEK, FIX.rows(), DATA.defending_acc_of(prev))
	var ents: Array = it.get("entrants", [])
	var def_n := 0
	for e in ents:
		if bool(e.get("defending", false)):
			def_n += 1
	_ok("⑪ 开场名单 6 位, 来历 A~F 组冠军, 上届冠军(上周杯冠军 = E 组)恰 1 位标卫冕", ents.size() == 6 and str(ents[0]["origin"]) == "A 组冠军"
		and str(ents[5]["origin"]) == "F 组冠军" and def_n == 1 and bool(ents[4]["defending"]), str(ents))
	var we: Dictionary = DATA.wall_entry(FIX.WEEK, v, FIX.rows())
	_ok("⑪ 冠军墙一届: 录像坐标 = (周, 杯组号, 决赛轮 3, 第 0 场)", str(we.get("name", "")) == "凤凰之羽"
		and we.get("replay", {}) == {"week": FIX.WEEK, "bucket": 99, "round": 3, "match": 0} and str(we.get("runner_up", "")) == "火山岩", str(we))
	_ok("⑪ 决赛没翻面 ⇒ 不演(cup_show 回 {})", DATA.cup_show(FIX.view(false), FIX.WEEK).is_empty())


# ═══════════════════════════════════════════════════════════════════
func _t_cup_full() -> void:
	var s = _mk(SHOW, _cup_data())
	await get_tree().process_frame
	var seen_btn_before := 0
	var flash_peak_t := -1.0
	var trophy_first := -1.0
	var big_first := -1.0
	var banner_first := -1.0
	var trophy_ys: Array = []
	var paper_y0 := -1.0
	var paper_moved := false
	var lineup_first := [-1.0, -1.0, -1.0]
	var roll_mid := ""
	var texts := {}
	var steps := 0
	while not s.is_settled() and steps < 60 * 30:
		s.advance(DT)
		steps += 1
		if not s.is_settled():
			seen_btn_before += _vis_buttons(s)
		var beat: String = s.current_beat()
		var fl := s.node("WhiteFlash") as ColorRect
		if beat == "crown":
			if fl.color.a >= 0.99 and flash_peak_t < 0.0:
				flash_peak_t = s.elapsed
			var tr := s.node("Trophy") as Control
			if tr != null and tr.modulate.a > 0.01 and trophy_first < 0.0:
				trophy_first = s.elapsed
			if tr != null and s.bt > 1.6:
				trophy_ys.append(tr.position.y)
			var bw := s.node("BigWord") as Control
			if bw != null and bw.modulate.a > 0.01 and big_first < 0.0:
				big_first = s.elapsed
			var bn := s.node("NameBanner") as Control
			if bn != null and bn.modulate.a > 0.01 and banner_first < 0.0:
				banner_first = s.elapsed
			if s.bt > 2.5 and not texts.has("crown"):
				texts["crown"] = [_text(s, "BigWord"), _text(s, "NameBanner"), _text(s, "ScaleLine"), _text(s, "DateLine")]
			for q in s._fx.parts:
				if str(q["kind"]) == "paper" and float(q["age"]) > 0.0:
					if paper_y0 < 0.0:
						paper_y0 = (q["p"] as Vector2).y
						q["_probe"] = true
					elif q.has("_probe") and absf((q["p"] as Vector2).y - paper_y0) > 20.0:
						paper_moved = true
		if beat == "reveal" and not texts.has("reveal"):
			texts["reveal"] = [_text(s, "RevealText"), _text(s, "RevealSub")]
		if beat == "runner" and s.bt > 1.0 and not texts.has("runner"):
			texts["runner"] = [_text(s, "RunnerRibbon"), _text(s, "RunnerName"), _text(s, "RunnerSub")]
		if beat == "lineup":
			for i in range(3):
				var cd := s.node("Turtle%d" % i) as Control
				if cd != null and cd.visible and lineup_first[i] < 0.0:
					lineup_first[i] = s.elapsed
		if beat == "path" and s.bt > 1.9 and not texts.has("path"):
			texts["path"] = [_text(s, "PathRound0"), _text(s, "PathFoe0"), _text(s, "PathScore0"), s.node("PathWin2") != null]
		if beat == "bests":
			var v1 := s.node("BestValue1") as Label
			if v1 != null and s.bt > 1.05 and s.bt < 1.2 and roll_mid == "":
				roll_mid = v1.text
	var names: Array = []
	var starts: Array = []
	for x in s.beat_log:
		names.append(x[0])
		starts.append(float(x[1]))
	_ok("① 冠军杯各拍按顺序: %s" % str(names), names == ["reveal", "runner", "crown", "lineup", "path", "bests", "card"])
	var inc := true
	for i in range(1, starts.size()):
		if float(starts[i]) <= float(starts[i - 1]) + 0.3:
			inc = false
	_ok("① 每拍至少停 0.3 s(开始时刻严格递增)", inc, str(starts))
	_ok("③ 冠军杯总长 12~16 s(实测 %.2f s, 计划 %.2f s)" % [s.settled_at, s.total_length()],
		s.settled_at >= 12.0 and s.settled_at <= 16.0 and absf(s.settled_at - s.total_length()) < 0.1)
	_ok("④ 定格卡落定之前场上 0 颗按钮(逐帧量了 %d 帧)" % steps, seen_btn_before == 0 and steps > 600, str(seen_btn_before))
	_ok("① 揭晓中那一拍: 大字「决赛完成」+「揭晓中」", texts.get("reveal", []) == ["决赛完成", "揭晓中"], str(texts.get("reveal")))
	_ok("① 亚军卡: 银缎带「冠军杯赛亚军」+ 名字 + 第 2 名（来历）", texts.get("runner", []) == ["冠军杯赛亚军", "火山岩", "第 2 名（C 组冠军）"],
		str(texts.get("runner")))
	_ok("② ★白闪满白之前奖杯不露面, 白闪那一刻起才出(白闪 %.2f / 奖杯 %.2f)" % [flash_peak_t, trophy_first],
		flash_peak_t > 0.0 and trophy_first >= flash_peak_t - 0.001 and trophy_first - flash_peak_t < 0.1)
	_ok("② 奖杯 → 「冠军」大字 → 名字缎带 依次出现(%.2f / %.2f / %.2f)" % [trophy_first, big_first, banner_first],
		trophy_first > 0.0 and big_first > trophy_first + 0.2 and banner_first > big_first)
	_ok("② 冠军仪式文字: 冠军 / 名字 / 冠军杯赛冠军（24 人参赛）/ 第 4 届　11 月 1 日",
		texts.get("crown", []) == ["冠军", "凤凰之羽", "冠军杯赛冠军（24 人参赛）", "第 4 届　11 月 1 日"], str(texts.get("crown")))
	var ymin := 1e9
	var ymax := -1e9
	for y in trophy_ys:
		ymin = minf(ymin, float(y))
		ymax = maxf(ymax, float(y))
	_ok("⑥ 奖杯落定后在浮动(纵向摆幅 %.1f px, 采样 %d)" % [ymax - ymin, trophy_ys.size()], trophy_ys.size() > 60 and ymax - ymin >= 4.0)
	_ok("⑥ 彩带真在落(同一片纸 y 走了 > 20 px)", paper_moved)
	_ok("⑥ 夺冠阵容逐只入场(出现时刻 %s)" % str(lineup_first), lineup_first[0] > 0.0 and lineup_first[1] > lineup_first[0] + 0.4
		and lineup_first[2] > lineup_first[1] + 0.4)
	_ok("① 夺冠之路一行: 1/4 决赛 · 北极光 · 2 : 0 · 胜章在", texts.get("path", []) == ["1/4 决赛", "北极光", "2 : 0", true], str(texts.get("path")))
	_ok("⑥ 今晚之最数字是滚出来的(中途「%s」≠ 终值)" % roll_mid, roll_mid != "" and roll_mid != "18420" and roll_mid != "18,420"
		and _text(s, "BestValue1") == "18,420")
	var btns := UI.buttons_under(s)
	var skin := not btns.is_empty()
	for b in btns:
		var sb = (b as Button).get_theme_stylebox("normal")
		if not (sb is StyleBoxFlat) or (sb as StyleBoxFlat).bg_color != Color("#6a3f1c") or (b as Control).size.y < 81.0 \
				or not (b as Control).visible or (b as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
			skin = false
	_ok("④ 落定后按钮出现: 皮 = card_button、高 ≥ 81、吃点击(%d 颗)" % btns.size(), skin and btns.size() == 2)
	## 定格卡停住不走
	var at: float = s.elapsed
	for _i in range(300):
		s.advance(DT)
	_ok("① 定格卡常驻(再走 5 s 仍在 card、没自己关)", s.current_beat() == "card" and is_instance_valid(s) and s.elapsed > at + 4.9)
	s.queue_free()
	await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
func _t_skip() -> void:
	var s = _mk(SHOW, _cup_data())
	await get_tree().process_frame
	while s.current_beat() != "crown":
		s.advance(DT)
	for _i in range(18):
		s.advance(DT)                                  # 进 crown 0.3 s, 还没白闪
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(640, 360)
	ev.global_position = ev.position
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	var pressed_skips: int = s.skips
	var ev2: InputEventMouseButton = ev.duplicate()
	ev2.pressed = false
	get_viewport().push_input(ev2)
	await get_tree().process_frame
	var tr := s.node("Trophy") as Control
	var bw := s.node("BigWord") as Control
	_ok("⑤ 只按下不松手 ⇒ 不算(松手才算)", pressed_skips == 0, str(pressed_skips))
	_ok("⑤ 真点一下(松手)⇒ 还是 crown 这一拍, 拍内时间拨到终点", s.current_beat() == "crown" and s.skips == 1
		and absf(s.bt - 2.45) < 0.02, "%s skips=%d bt=%.2f" % [s.current_beat(), s.skips, s.bt])
	_ok("⑤ 终态到位: 奖杯满尺寸可见、「冠军」大字满不透明、名字缎带在", tr != null and tr.modulate.a > 0.99
		and absf(tr.scale.x - 1.0) < 0.01 and bw != null and bw.modulate.a > 0.99 and (s.node("NameBanner") as Control).modulate.a > 0.99)
	var t0: float = s.elapsed
	var moved_at := -1.0
	for _i in range(120):
		s.advance(DT)
		if s.current_beat() != "crown" and moved_at < 0.0:
			moved_at = s.elapsed
	_ok("⑤ 落定后停 %.1f s 才进下一拍(实测 %.2f s), 下一拍 = 夺冠阵容(没跳过整段)" % [SHOW.SKIP_HOLD, moved_at - t0],
		moved_at > 0.0 and moved_at - t0 >= SHOW.SKIP_HOLD - 0.05 and moved_at - t0 <= SHOW.SKIP_HOLD + 0.1 and s.current_beat() == "lineup")
	## 揭晓中那一拍点一下也不会跳到冠军
	var s2 = _mk(SHOW, _cup_data())
	await get_tree().process_frame
	s2.advance(DT)
	s2.skip_beat()
	_ok("⑤ 揭晓中点一下 ⇒ 仍是揭晓中(只落定, 不跳拍)", s2.current_beat() == "reveal")
	s.queue_free()
	s2.queue_free()
	await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
func _t_group() -> void:
	for with_lineup in [true, false]:
		var d: Dictionary = DATA.group_show(FIX.view(), 2, FIX.WEEK, FIX.rows() if with_lineup else [], "", "晋级冠军杯赛（20:00 开赛）")
		d["vp"] = Vector2(1560, 720)
		var s = _mk(SHOW, d)
		await get_tree().process_frame
		var btn_before := 0
		var big := ""
		var steps := 0
		while not s.is_settled() and steps < 60 * 20:
			s.advance(DT)
			steps += 1
			if not s.is_settled():
				btn_before += _vis_buttons(s)
			if s.current_beat() == "crown" and s.bt > 2.0 and big == "":
				big = _text(s, "BigWord")
		var names: Array = []
		for x in s.beat_log:
			names.append(x[0])
		var want := ["reveal", "crown", "lineup", "path", "card"] if with_lineup else ["reveal", "crown", "path", "card"]
		var tag := "有阵容" if with_lineup else "没拿到阵容"
		_ok("⑦ 组冠军(%s)各拍: %s" % [tag, str(names)], names == want)
		_ok("③ 组冠军(%s)总长 8~11 s(实测 %.2f)" % [tag, s.settled_at], s.settled_at >= 8.0 and s.settled_at <= 11.0)
		_ok("⑦ 组冠军(%s)大字「组冠军」、整段 0 颗按钮" % tag, big == "组冠军" and btn_before == 0, "%s %d" % [big, btn_before])
		_ok("⑦ 组冠军(%s)定格卡写晋级冠军杯赛 + 头衔(各一行)" % tag, _text(s, "CardScale").begins_with("晋级冠军杯赛")
			and _text(s, "CardTitleLine").contains("「组冠军」头衔"), _text(s, "CardScale") + " | " + _text(s, "CardTitleLine"))
		s.queue_free()
		await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
func _t_card_buttons() -> void:
	## 冠军本人: 「冠军墙」+「领取奖励」(主按钮在右) → 点领取开奖励链 → 领完换成「关闭」→ 点关闭发 finished
	var s = _mk(SHOW, _cup_data())
	await get_tree().process_frame
	s.skip_beat()
	while not s.is_settled():
		s.advance(DT)
		s.skip_beat()
	var claim := s.node("BtnClaim") as Button
	var wall := s.node("BtnWall") as Button
	_ok("④ 冠军本人定格卡: 「冠军墙」+「领取奖励」, 主按钮在右", claim != null and wall != null and claim.text == "领取奖励"
		and claim.get_global_rect().position.x > wall.get_global_rect().position.x)
	_ok("① 定格卡写来历 + 规模「E 组冠军（24 人参赛）」+ 届数日期", _text(s, "CardScale") == "E 组冠军（24 人参赛）"
		and _text(s, "CardEdition") == "冠军杯赛　第 4 届　11 月 1 日", _text(s, "CardScale") + " | " + _text(s, "CardEdition"))
	_ok("① 定格卡写「获得「冠军」头衔（有效期至下周日）」", _text(s, "CardTitleLine") == "获得「冠军」头衔（有效期至下周日）", _text(s, "CardTitleLine"))
	claim.pressed.emit()
	await get_tree().process_frame
	var rw: Node = null
	for ch in get_children():
		if ch.get_script() == REW:
			rw = ch
	_ok("⑨ 点「领取奖励」⇒ 奖励链那一层开出来、盖在定格卡上面", rw != null and int(rw.layer) > int(s.layer))
	if rw != null:
		rw.auto_advance = false
		var guard := 0
		while is_instance_valid(rw) and guard < 40:
			rw.skip_beat()
			var nb := rw.node("BtnNext") as Button
			if nb != null and nb.visible:
				nb.pressed.emit()
			guard += 1
			await get_tree().process_frame
	var closeb := s.node("BtnClose") as Button
	_ok("⑨ 领完 ⇒ 那颗换成「关闭」", closeb != null and closeb.text == "关闭" and s.node("BtnClaim") == null)
	var got := [false]
	s.finished.connect(func() -> void: got[0] = true)
	closeb.pressed.emit()
	await get_tree().process_frame
	_ok("① 点「关闭」⇒ finished, 层自删", got[0] and not is_instance_valid(s))
	## 别人看: 「冠军墙」+「关闭」; 点冠军墙 ⇒ wall_requested
	var d2 := _cup_data()
	d2["viewer_is_champion"] = false
	var s2 = _mk(SHOW, d2)
	await get_tree().process_frame
	while not s2.is_settled():
		s2.advance(DT)
		s2.skip_beat()
	var asked := [0]
	s2.wall_requested.connect(func() -> void: asked[0] += 1)
	_ok("④ 别人看定格卡: 「冠军墙」+「关闭」, 没有「领取奖励」", s2.node("BtnWall") != null and s2.node("BtnClose") != null
		and s2.node("BtnClaim") == null)
	(s2.node("BtnWall") as Button).pressed.emit()
	_ok("⑩ 点「冠军墙」⇒ wall_requested", asked[0] == 1)
	s2.queue_free()
	await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
func _t_intro() -> void:
	var d: Dictionary = DATA.cup_intro(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
	d["vp"] = Vector2(1560, 720)
	var s = _mk(INTRO, d)
	await get_tree().process_frame
	var done := [false]
	s.finished.connect(func() -> void: done[0] = true)
	var btn := 0
	var steps := 0
	var log: Array = []
	var def_ok := false
	var origin0 := ""
	while not done[0] and steps < 60 * 15:
		s.advance(DT)
		steps += 1
		if done[0]:
			break
		btn += UI.buttons_under(s).size()
		if steps == 60 * 2:
			origin0 = _text(s, "Origin")
			var e4: Node = s.node("Entrant4")
			var e0: Node = s.node("Entrant0")
			def_ok = e4 != null and e4.find_child("Defending", true, false) != null and e0 != null \
				and e0.find_child("Defending", true, false) == null
		if not is_instance_valid(s):
			break
	if is_instance_valid(s):
		log = s.shown_log
	await get_tree().process_frame
	_ok("⑧ 开场: 6 位依次亮相、结束发 finished 并自删(%d 帧)" % steps, done[0] and not is_instance_valid(s) and steps > 400)
	_ok("⑧ 全程 0 颗按钮", btn == 0)
	_ok("⑧ 来历缎带「A 组冠军」; 只有上届冠军那一位挂「卫冕」", origin0 == "A 组冠军" and def_ok, origin0)
	var s2 = _mk(INTRO, d)
	await get_tree().process_frame
	var times: Array = []
	s2.entrant_shown.connect(func(i: int) -> void: times.append([i, s2.elapsed]))
	for _i in range(int(s2.total_length() / DT) - 30):
		s2.advance(DT)
	var order_ok := times.size() == 6
	for i in range(times.size()):
		if int(times[i][0]) != i:
			order_ok = false
		if i > 0 and absf(float(times[i][1]) - float(times[i - 1][1]) - INTRO.T_EACH) > 0.05:
			order_ok = false
	_ok("⑧ 亮相顺序 = 组号, 每人间隔 %.1f s(%s)" % [INTRO.T_EACH, str(times)], order_ok)
	_ok("⑧ 6 位总长 %.1f s(标题 + 6 × 1 s + 收尾)" % s2.total_length(), absf(s2.total_length() - 8.2) < 0.01)
	s2.queue_free()
	await get_tree().process_frame
	## 点一下: 正在亮相的这一位落定, 不跳到下一位
	var s3 = _mk(INTRO, d)
	await get_tree().process_frame
	for _i in range(int((INTRO.T_TITLE + 0.1) / DT)):
		s3.advance(DT)
	s3.skip_beat()
	_ok("⑧ 亮相中点一下 ⇒ 这一位落定(t 到这一位的终点前 %.2f s), 第 2 位还没出" % INTRO.SKIP_HOLD,
		absf(s3.t - (INTRO.T_TITLE + INTRO.T_EACH - INTRO.SKIP_HOLD)) < 0.02 and not (s3.node("Entrant1") as Control).visible, "t=%.2f" % s3.t)
	s3.queue_free()
	await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
func _t_rewards() -> void:
	## 奖励链组件本身仍支持「深海币入账」页(产品 11-08 起不再放, 见 ⑪); 这里手搭一页量组件的飞币 / 滚数字
	var d := {"pages": DATA.reward_pages([P2C.TITLE_CHAMPION]) + [{"kind": "coins", "amount": 24, "sub": "3 轮"}],
		"coin_from": 40, "vp": Vector2(1560, 720)}
	var r = _mk(REW, d)
	await get_tree().process_frame
	var nb := r.node("BtnNext") as Button
	_ok("⑨ 第 1 页 = 头衔: 「获得头衔」+ 金缎带「冠军」+「有效期至下周日」", _text(r, "PageTitle") == "获得头衔"
		and _text(r, "TitleRibbon") == "冠军" and _text(r, "PageSub") == "有效期至下周日" and _text(r, "PageCount") == "奖励 1 / 2")
	var shown_early := false
	for _i in range(int((REW.ANIM_TITLE - 0.1) / DT)):
		r.advance(DT)
		if nb.visible:
			shown_early = true
	_ok("⑨ 这一页动画播完之前没有按钮", not shown_early and not nb.visible)
	for _i in range(12):
		r.advance(DT)
	_ok("⑨ 播完 ⇒「下一个」出现", nb.visible and nb.text == "下一个" and nb.mouse_filter == Control.MOUSE_FILTER_STOP)
	nb.pressed.emit()
	await get_tree().process_frame
	_ok("⑨ 第 2 页 = 深海币入账, 按钮写「完成」", _text(r, "PageTitle") == "深海币入账" and nb.text == "完成" and not nb.visible)
	var chip := r.node("CoinChipValue") as Label
	var landed_n := [0]
	r.coins_landed.connect(func(n: int) -> void: landed_n[0] = n)
	var amt_mid := ""
	var chip_at_roll_end := ""
	var flew := false
	var chip_vals := {}
	for _i in range(int(REW.ANIM_COINS / DT) + 4):
		r.advance(DT)
		if r.t > 0.7 and r.t < 0.75:
			amt_mid = _text(r, "CoinAmount")
		if r.t > 1.15 and r.t < 1.19:
			chip_at_roll_end = chip.text
		var f0 := r.node("FlyCoin0") as Control
		if f0 != null and f0.visible:
			flew = true
		chip_vals[chip.text] = true
	_ok("⑨ 先物件后数字: 数字滚动中途「%s」不是终值" % amt_mid, amt_mid != "" and amt_mid != "+24" and amt_mid.begins_with("+"))
	_ok("⑨ ★数字滚完、币还没飞到时顶栏仍是旧值 40(实测「%s」)" % chip_at_roll_end, chip_at_roll_end == "40")
	_ok("⑨ 币真的在飞, 飞到后顶栏 40 → 64、发 coins_landed(24), 中间一步一步涨(%d 个不同值)" % chip_vals.size(),
		flew and chip.text == "64" and landed_n[0] == 24 and chip_vals.size() >= 5)
	_ok("⑨ 入账后记成「看过的余额」(回主菜单不重飞)", int(load("res://scripts/util/coin_fly.gd").seen) >= 64)
	var done := [false]
	r.finished.connect(func() -> void: done[0] = true)
	nb.pressed.emit()
	await get_tree().process_frame
	_ok("⑨ 最后一页点「完成」⇒ finished, 层自删", done[0] and not is_instance_valid(r))


# ═══════════════════════════════════════════════════════════════════
func _t_wall() -> void:
	var es: Array = [DATA.wall_entry(FIX.WEEK, FIX.view(), FIX.rows())]
	var older: Dictionary = DATA.wall_entry(FIX.WEEK - DATA.WEEK_SEC, FIX.view(), [])
	older["replay"] = {}
	es.append(older)
	es.append({})                                    # 没决出的一周: 不画
	var w = _mk(WALL, {"entries": [older, es[0], {}], "vp": Vector2(1560, 720)})
	await get_tree().process_frame
	_ok("⑩ 冠军墙两届(新的在上): 第 4 届 · 11 月 1 日 / 第 3 届 · 10 月 25 日", _text(w, "WallEdition0") == "第 4 届"
		and _text(w, "WallDate0") == "11 月 1 日" and _text(w, "WallEdition1") == "第 3 届" and _text(w, "WallDate1") == "10 月 25 日"
		and w.node("WallRow2") == null)
	_ok("⑩ 铭牌: 冠军名 / 来历（规模）/ 亚军 / 夺冠阵容三只", _text(w, "WallName0") == "凤凰之羽" and _text(w, "WallInfo0") == "E 组冠军（24 人参赛）"
		and _text(w, "WallRunner0") == "亚军：火山岩" and w.node("WallTurtle0_2") != null and w.node("WallTurtle1_0") == null)
	var b0 := w.node("WallReplay0") as Button
	var b1 := w.node("WallReplay1") as Button
	var asked: Array = []
	w.replay_requested.connect(func(rp: Dictionary) -> void: asked.append(rp))
	b0.pressed.emit()
	_ok("⑩ 「决赛录像」⇒ replay_requested(周, 杯组号, 决赛轮, 0); 没有录像坐标的那届按钮不可点",
		asked.size() == 1 and asked[0] == {"week": FIX.WEEK, "bucket": 99, "round": 3, "match": 0} and b1.disabled and not b0.disabled, str(asked))
	var sb = b0.get_theme_stylebox("normal")
	_ok("⑩ 按钮皮 = card_button, 高 ≥ 81", sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color == Color("#6a3f1c") and b0.size.y >= 81.0)
	var w2 = _mk(WALL, {"entries": [], "vp": Vector2(1560, 720)})
	await get_tree().process_frame
	_ok("⑩ 一届都没有 ⇒ 写「暂无往届冠军」(不画空框)", _text(w2, "WallState") == "暂无往届冠军")
	var done := [false]
	w.finished.connect(func() -> void: done[0] = true)
	(w.node("BtnBack") as Button).pressed.emit()
	await get_tree().process_frame
	_ok("⑩ 「返回」⇒ finished, 层自删", done[0] and not is_instance_valid(w))
	w2.queue_free()
	await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
## 版式: 每一拍走到终态, 量这一拍里所有字和卡的矩形都在屏内。
func _t_layout() -> void:
	var bad: Array = []
	var measured := 0
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		for mode in ["cup", "group"]:
			var d: Dictionary = _cup_data(vp) if mode == "cup" else DATA.group_show(FIX.view(), 2, FIX.WEEK, FIX.rows(), "", "晋级冠军杯赛（20:00 开赛）")
			d["vp"] = vp
			var s = _mk(SHOW, d)
			await get_tree().process_frame
			var guard := 0
			while guard < 40:
				guard += 1
				s.skip_beat()
				var b: String = s.current_beat()
				var stage := s.node("Stage_" + b) as Control
				if stage != null:
					stage.modulate.a = 1.0
					for ch in stage.find_children("*", "Control", true, false):
						var cc := ch as Control
						if not cc.is_visible_in_tree() or not (cc is Label or cc is Button or cc.name.begins_with("Turtle")
								or cc.name.begins_with("PathRow") or cc.name.begins_with("Best") or cc.name == "ChampionCard"):
							continue
						if cc is Label and (cc as Label).text == "":
							continue
						measured += 1
						var r := cc.get_global_rect()
						if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
							bad.append("%s %s %s %s %s" % [str(vp), mode, b, cc.name, str(r)])
				if s.is_settled():
					break
				for _i in range(int(SHOW.SKIP_HOLD / DT) + 2):
					s.advance(DT)
			s.queue_free()
			await get_tree().process_frame
	_ok("⑫ 两种比例 × 冠军杯 / 组冠军, 各拍终态的字与卡都在屏内(量了 %d 块)" % measured, bad.is_empty() and measured >= 150, str(bad.slice(0, 6)))


# ═══════════════════════════════════════════════════════════════════
## WCAG 相对亮度对比。
func _contrast(a: Color, b: Color) -> float:
	var la := 0.2126 * _lin(a.r) + 0.7152 * _lin(a.g) + 0.0722 * _lin(a.b)
	var lb := 0.2126 * _lin(b.r) + 0.7152 * _lin(b.g) + 0.0722 * _lin(b.b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## 缎带本体(放字那一块)的平均色: 从贴图本身量(不信我写的颜色常量)。
func _ribbon_body(path: String) -> Color:
	var im: Image = (load(path) as Texture2D).get_image()
	if im.is_compressed():
		im.decompress()
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for y in range(int(im.get_height() * 0.25), int(im.get_height() * 0.65)):
		for x in range(int(im.get_width() * 0.2), int(im.get_width() * 0.8)):
			var px := im.get_pixel(x, y)
			if px.a > 0.8:
				acc += px
				n += 1
	return Color(acc.r / n, acc.g / n, acc.b / n) if n > 0 else Color.BLACK


func _title_labels(root: Node) -> Array:
	var out: Array = []
	var tf := UISkin.title_font()
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).has_theme_font_override("font") and (l as Label).get_theme_font("font") == tf and (l as Label).text != "":
			out.append(l)
	return out


func _font_rule_bad(l: Label) -> String:
	var fs: int = l.get_theme_font_size("font_size")
	if fs % 12 != 0:
		return "%s 字号 %d" % [l.name, fs]
	var ol: int = l.get_theme_constant("outline_size")
	if ol > 0 and ol % maxi(1, fs / 3) != 0:
		return "%s %d 号描边 %d" % [l.name, fs, ol]
	if l.get_theme_color("font_shadow_color").a > 0.0:
		var sx: int = l.get_theme_constant("shadow_offset_x")
		var sy: int = l.get_theme_constant("shadow_offset_y")
		if sx % maxi(1, fs / 12) != 0 or sy % maxi(1, fs / 12) != 0:
			return "%s %d 号落影 (%d,%d)" % [l.name, fs, sx, sy]
	return ""


func _t_round2() -> void:
	## ⑬-1 缎带字: 三种缎带各建一条, 量字 / 描边 / 缎带本体
	var holder := Control.new()
	add_child(holder)
	var rib_ok := true
	var rib_info: Array = []
	for kind in ["gold", "silver", "red"]:
		var r: Control = UI.ribbon(holder, Vector2(300, 300), 480, "凤凰之羽", 48, kind)
		var tl := r.find_child("Text", true, false) as Label
		var tex := (r.get_child(0) as TextureRect).texture
		var body := _ribbon_body(tex.resource_path)
		var fc := tl.get_theme_color("font_color")
		var oc := tl.get_theme_color("font_outline_color")
		var c1 := _contrast(fc, oc)
		var c2 := maxf(_contrast(oc, body), _contrast(fc, body))
		rib_info.append("%s 字/描边 %.1f 本体 %.1f 字号 %d 描边 %d" % [kind, c1, c2, tl.get_theme_font_size("font_size"), tl.get_theme_constant("outline_size")])
		if c1 < 7.0 or c2 < 4.5 or tl.get_theme_font_size("font_size") < 36 or tl.get_theme_constant("outline_size") < 12:
			rib_ok = false
	var small: Control = UI.ribbon(holder, Vector2(300, 300), 320, "A 组冠军", 24, "red")
	var stl := small.find_child("Text", true, false) as Label
	_ok("⑬ 缎带字读得出: 字/描边 ≥ 7、描边或字/缎带本体 ≥ 4.5、字号 ≥ 36、描边 ≥ 12(%s)" % " | ".join(rib_info),
		rib_ok and stl.get_theme_font_size("font_size") >= 36)
	holder.queue_free()
	## ⑬-2 揭晓中: 呼吸 + 光束收拢
	var s = _mk(SHOW, _cup_data())
	await get_tree().process_frame
	var subs := {}
	var r0 := -1.0
	var r1 := -1.0
	while s.current_beat() == "reveal":
		if s.bt > 0.4:
			subs[snappedf((s.node("RevealSub") as Control).modulate.a, 0.05)] = true
			if r0 < 0.0:
				r0 = s._fx.rays_radius
			r1 = s._fx.rays_radius
		s.advance(DT)
	_ok("⑬ 揭晓中: 「揭晓中」在呼吸(透明度 %d 档)、背后光束在收拢(%.0f → %.0f)" % [subs.size(), r0, r1],
		subs.size() >= 4 and r1 < r0 * 0.75)
	## ⑬-3 阵容: 完整立绘、约 200px、居中、逐只落位
	while s.current_beat() != "lineup":
		s.advance(DT)
	var land_y := {}
	while s.current_beat() == "lineup":
		s.advance(DT)
		for i in range(3):
			var bd: Node = s.node("Turtle%d" % i)
			if bd != null and (bd as Control).visible:
				var b := bd.find_child("BodyHolder", true, false) as Control
				if b != null and not land_y.has(i) and absf(b.position.y - float(s._n["items"][i]["y0"])) < 0.5:
					land_y[i] = s.elapsed
		if s.bt > float(s._beat("lineup")["anim"]):
			break
	var xs: Array = []
	var hs: Array = []
	var full := true
	for i in range(3):
		var b := (s.node("Turtle%d" % i) as Node).find_child("BodyHolder", true, false) as Control
		var spr := b.get_node("Body") as Sprite2D
		xs.append(b.get_global_rect().get_center().x)
		hs.append(b.size.y)
		var pet: Dictionary = DataRegistry.pet_by_id.get(str(s.lineup()[i]), {})
		if spr.texture.resource_path != "res://assets/sprites/%s" % str(pet.get("img", "")) or b.size.x <= 0.0:
			full = false
	var mean := (float(xs[0]) + float(xs[1]) + float(xs[2])) / 3.0
	_ok("⑬ 阵容三只用全身立绘(pets.json 的 img, 按不透明包围盒定高, 不裁)", full)
	_ok("⑬ 阵容每只高 195~215 px(%s)" % str(hs), float(hs.min()) >= 195.0 and float(hs.max()) <= 215.0)
	_ok("⑬ 阵容最终居中: 三只中心均值 %.1f = 屏中 %.1f, 间距相等" % [mean, s.c.x], absf(mean - s.c.x) < 1.0
		and absf((float(xs[1]) - float(xs[0])) - (float(xs[2]) - float(xs[1]))) < 1.0)
	_ok("⑬ 逐只落位(落地时刻 %s), 最后一只落定后还停 ≥ 0.6 s" % str(land_y), land_y.size() == 3
		and float(land_y[1]) > float(land_y[0]) + 0.4 and float(land_y[2]) > float(land_y[1]) + 0.4
		and float(s._beat("lineup")["dur"]) - (0.35 + 0.55 * 2.0 + 0.22) >= 0.6)
	var d2 := _cup_data()
	d2["lineup"] = ["phoenix", "no_such_turtle"]
	var s2 = _mk(SHOW, d2)
	await get_tree().process_frame
	_ok("⑬ 画不出立绘的龟整只不进阵容(不出占位)", s2.lineup() == ["phoenix"])
	s2.queue_free()
	## ⑬-4 夺冠之路: 行宽行高 + 盖章进场
	while s.current_beat() != "path":
		s.advance(DT)
	var max_sc := 0.0
	var dust0: int = s._fx.live_count()
	var dust_seen := false
	while s.current_beat() == "path" and s.bt < float(s._beat("path")["anim"]):
		s.advance(DT)
		var r0n := s.node("PathRow0") as Control
		if r0n != null and r0n.visible:
			max_sc = maxf(max_sc, r0n.scale.x)
		if s._fx.live_count() > dust0 + 10:
			dust_seen = true
	var row := s.node("PathRow0") as Control
	var face := s.node("PathFoeFace0") as Control
	var score := s.node("PathScore0") as Label
	_ok("⑬ 夺冠之路行宽 ≥ 屏宽 70%%、行高 ≥ 96、对手头像 ≥ 80、比分字号 ≥ 48(%.0f / %.0f / %.0f / %d)" % [row.size.x, row.size.y,
		face.size.x, score.get_theme_font_size("font_size")], row.size.x >= s.vp.x * 0.7 and row.size.y >= 96.0 and face.size.x >= 80.0
		and score.get_theme_font_size("font_size") >= 48)
	_ok("⑬ 每行盖章进场: 先放大(最大 %.2f 倍)再落到 1 倍 + 扬尘" % max_sc, max_sc >= 1.2 and absf(row.scale.x - 1.0) < 0.01 and dust_seen)
	## ⑬-5 像素标题字规矩(本层所有挂标题字的标签)
	var bad: Array = []
	var n_lbl := 0
	while not s.is_settled():
		s.advance(DT)
	for l in _title_labels(s):
		n_lbl += 1
		var why := _font_rule_bad(l)
		if why != "":
			bad.append(why)
	s.queue_free()
	await get_tree().process_frame
	## ⑬-6 奖励卡: 大、背后不透明、章砸下回弹
	var r = _mk(REW, {"pages": DATA.reward_pages([P2C.TITLE_CHAMPION]), "coin_from": 40, "vp": Vector2(1560, 720)})
	await get_tree().process_frame
	var bg := r.node("RewardsBg") as TextureRect
	var card: Rect2 = r.card_rect
	var st_max := 0.0
	var shook := false
	for _i in range(int(REW.ANIM_TITLE / DT) + 2):
		r.advance(DT)
		var st := r.node("Stamp") as Control
		if st != null and st.modulate.a > 0.01:
			st_max = maxf(st_max, st.scale.x)
		if (r._box as Control).position.distance_to(card.position) > 1.0:
			shook = true
	var st_end := r.node("Stamp") as Control
	_ok("⑬ 奖励卡背后整屏不透明(竞技场背景铺满、不透明度 1)", bg != null and bg.modulate.a >= 0.999 and bg.size == Vector2(1560, 720)
		and bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_ok("⑬ 奖励卡够大(%.0f×%.0f ≥ 屏宽 45%% × 屏高 60%%), 头衔缎带字号 ≥ 60" % [card.size.x, card.size.y],
		card.size.x >= 1560.0 * 0.45 and card.size.y >= 720.0 * 0.6
		and ((r.node("TitleRibbon") as Node).find_child("Text", true, false) as Label).get_theme_font_size("font_size") >= 60)
	_ok("⑬ 「已获得」章砸下: 最大 %.2f 倍 → 落定 1 倍, 卡片一震" % st_max, st_max >= 2.3 and absf(st_end.scale.x - 1.0) < 0.01 and shook)
	for l in _title_labels(r):
		n_lbl += 1
		var why := _font_rule_bad(l)
		if why != "":
			bad.append(why)
	r.queue_free()
	await get_tree().process_frame
	## ⑬-7 开场亮相那一位占屏 1/3 高
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		var d: Dictionary = DATA.cup_intro(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
		d["vp"] = vp
		var it = _mk(INTRO, d)
		await get_tree().process_frame
		while it.t < INTRO.T_TITLE + 0.5:
			it.advance(DT)
		var e0: Node = it.node("Entrant0")
		var f := e0.find_child("Face", true, false) as Control
		var nm := e0.find_child("Name", true, false) as Label
		var org := e0.find_child("Origin", true, false).find_child("Text", true, false) as Label
		var fh: float = f.get_global_rect().size.y
		_ok("⑬ 开场亮相 %s: 头像 %.0f px ≈ 屏高 1/3, 名字字号 %d ≥ 48, 来历缎带字号 %d ≥ 36" % [str(vp), fh,
			nm.get_theme_font_size("font_size"), org.get_theme_font_size("font_size")],
			absf(fh - vp.y / 3.0) < 3.0 and nm.get_theme_font_size("font_size") >= 48 and org.get_theme_font_size("font_size") >= 36)
		for l in _title_labels(it):
			n_lbl += 1
			var why := _font_rule_bad(l)
			if why != "":
				bad.append(why)
		it.queue_free()
		await get_tree().process_frame
	_ok("⑬ 像素标题字规矩: 字号 12 倍 / 描边 字号÷3 / 落影 字号÷12(量了 %d 个标签)" % n_lbl, bad.is_empty() and n_lbl >= 40, str(bad.slice(0, 5)))


# ═══════════════════════════════════════════════════════════════════
func _end_info() -> Dictionary:
	return {"win": "left", "me": "left", "names": {"left": "凤凰之羽", "right": "火山岩"},
		"pids": {"left": "hiding", "right": "crystal"}, "leaders": {"left": ["hiding", "headless", "rainbow"], "right": ["crystal", "space", "cyber"]},
		"origins": {"left": "E 组冠军", "right": "C 组冠军"}, "score": {"left": 2, "right": 1},
		"stage": {"cup": true, "round": 3, "rounds": 3, "round_name": "决赛"}}


func _t_hook() -> void:
	## 决赛那一刻缓存里的杯还没翻面(去掉决赛那一格): 前两轮取缓存, 决赛那一行取 info
	var v := FIX.view()
	var cup: Dictionary = (v["cup"] as Dictionary).duplicate(true)
	(cup["done"] as Dictionary).erase("3-0")
	(cup["scores"] as Dictionary).erase("3-0")
	v["cup"] = cup
	var d: Dictionary = DATA.cup_show_from_end(_end_info(), v, FIX.WEEK)
	var p: Array = d.get("path", [])
	_ok("⑭ 交接数据: 冠军 / 亚军 / 阵容 / 头像 / 来历取 info", str(d["champion"]["name"]) == "凤凰之羽" and str(d["runner_up"]["name"]) == "火山岩"
		and d["lineup"] == ["hiding", "headless", "rainbow"] and str(d["champion"]["avatar"]) == "hiding" and str(d["champion"]["origin"]) == "E 组冠军"
		and bool(d["viewer_is_champion"]), str(d.get("champion")))
	_ok("⑭ 交接数据: 夺冠之路 = 缓存里的前两轮 + info 的决赛 2 : 1", p.size() == 3 and str(p[0]["round"]) == "1/4 决赛" and str(p[1]["round"]) == "半决赛"
		and str(p[2]["round"]) == "决赛" and str(p[2]["foe"]) == "火山岩" and p[2]["score"] == [2, 1] and int(d["entrants"]) == 24, str(p))
	var d0: Dictionary = DATA.cup_show_from_end(_end_info(), {}, FIX.WEEK)
	_ok("⑭ 缓存里什么都没有 ⇒ 只有决赛一行, 照样能演", (d0.get("path", []) as Array).size() == 1 and int(d0.get("entrants", -1)) == 0)
	## 真走交接入口: 组里有节点 ⇒ call_group 落到它, 在 host 上开出冠军收盘
	var hook = load("res://scripts/scenes/bracket/champion_hook.gd").new()
	add_child(hook)
	var host := Control.new()
	add_child(host)
	await get_tree().process_frame
	_ok("⑭ 交接节点在组 finals_champion 里", get_tree().get_nodes_in_group("finals_champion").has(hook))
	get_tree().call_group("finals_champion", "on_cup_final_end", _end_info(), host)
	await get_tree().process_frame
	var show = hook.last_show
	_ok("⑭ call_group ⇒ 在 host 上开出冠军收盘(冠军本人带奖励页)", show != null and is_instance_valid(show) and show.get_parent() == host
		and str((hook.last_data["champion"] as Dictionary)["name"]) == "凤凰之羽" and not (hook.last_data.get("rewards", []) as Array).is_empty())
	if show != null and is_instance_valid(show):
		show.queue_free()
	hook.queue_free()
	host.queue_free()
	await get_tree().process_frame
