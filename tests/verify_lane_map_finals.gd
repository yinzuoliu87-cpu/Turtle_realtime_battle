extends Node
## verify_lane_map_finals.gd —— 周日决赛日那一场: 对阵卡融进桌面地图(2026-11-23 · 方案书 docs/plans/20261122-周日全流程走查与优化.md B2)。
## 用户 11-22:「肯定是那个立体的那个动画…周日就是更加的高级…把这个对阵卡融合到我们的桌面地图呢？…对阵卡完全没有任何动画效果，它像一个游戏吗？」
## 实现 scripts/scenes/battle/lane_map_finals.gd(挂在 lane_map_intro 的地图幕布上; 周日开播 = 战斗场 HUD 挂着建了观战页的 ReplayControls)。
## 判据(真战斗场 + App Store 截图台那份真实阵容, 无头; 全按 pose(t) 摆到某一刻去量, 不靠 tween):
##   ① 开场幕布上有周日那一层: 缎带写轮次「冠军杯赛半决赛 · 第 1 / 2 场」, 左右名牌 = 录像两边名字 + 来历(B 组冠军 / E 组冠军（卫冕）)
##      + 闯关战绩; 大本营上不再写名字(名字在名牌上, 不说两遍)
##   ② ★动起来: 0 秒缎带收成一条线、名牌在屏外、盾徽看不见; 0.9 秒盾徽在中间往下砸; 1.2 秒盾徽落定、冲击环在推; 2.2 秒缎带展开、
##      名牌落位、盾徽已飞走(看不见)
##   ③ 2.2 秒名牌整张在屏内, 且不压底部那一排(退出键 / 全局小条, BOTTOM_BAND)
##   ④ ★战果幕: 记分牌「名字 金字比分 名字」, 0.5 秒还是翻牌前 0 : 0, 2.0 秒赢的那边翻成 1(左 0 右 1)
##   ⑤ ★看别人的比赛 ⇒ 战果章写「小辉同学 赢得上路」(不是录像方视角的「本战场胜利」); 「我方 / 对方」蛋血行不显示
##   ⑥ 平时的对局(没有周日观战页)⇒ 不建这一层, 大本营照旧写名字
## 反向验证(11-23): 翻牌不换数字(pose 里 set_digit 去掉)⇒ ④ 红; _restamp 不改字 ⇒ ⑤ 红; wanted() 恒返回 rc ⇒ ⑥ 红;
##   名牌 BOTTOM_BAND 改 14 ⇒ ③ 红。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const LMF := preload("res://scripts/scenes/battle/lane_map_finals.gd")

var _n := 0
var _fail := 0
var _b = null


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _intro():
	var back = _b._dl_present_root
	if back == null or not is_instance_valid(back):
		return null
	for c in back.get_children():
		if c.get("intro") != null:
			return c.get("intro")
	return null


func _wait_state(st: String, max_frames: int = 3000) -> bool:
	for _i in max_frames:
		if str(_b._dl_state) == st:
			return true
		await get_tree().process_frame
	return false


func _labels(root: Node) -> Array:
	var out: Array = []
	for l in root.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日决赛日: 对阵卡融进桌面地图 ===")
	get_window().size = Vector2i(1560, 720)
	await get_tree().process_frame
	load("res://tests/_setup_appstore.gd").run()
	GameState.dual_active = true
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_ok("分母: 进场就是开场地图幕", await _wait_state("overview", 600), str(_b._dl_state))
	_b.set_process(false)
	## ── ⑥ 平时: 没有周日观战页 ──
	var it0 = _intro()
	_ok("⑥ 平时的对局不建周日那一层", it0 != null and it0.fin == null and _b._dl_present_root.find_child(LMF.N_LAYER, true, false) == null)
	## 普通回放(有回放操作条、没建周日观战页)也不建
	var rc0 = RC.new(_b)
	_b._hud._replay_ui = rc0
	_b._dl_sys._dl_build_present_overlay("overview")
	_ok("⑥ 普通回放(没有周日观战页)也不建", _intro() != null and _intro().fin == null and _b._dl_present_root.find_child(LMF.N_LAYER, true, false) == null)
	_b._hud._replay_ui = null
	## ── 周日开播: 看别人的冠军杯半决赛 ──
	ReplayRecorder.play_names = {"l": "吃货一枚", "r": "小辉同学", "pair": ["吃货一枚", "小辉同学"], "me": -1,
		"stage": {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2},
		"cards": [{"group": 1, "record": "闯关 9 胜 2 负"}, {"group": 4, "record": "闯关 8 胜 3 负", "title": "卫冕"}]}
	ReplayRecorder.viewer_name = "看客"
	var rc = RC.new(_b)
	rc._names = {"l": "吃货一枚", "r": "小辉同学"}
	rc.hud = RefCounted.new()            # 「建了观战页」(lane_map_finals.wanted 只认它在不在)
	_b._hud._replay_ui = rc
	_b._dl_sys._dl_build_present_overlay("overview")
	var it = _intro()
	var lay: Control = _b._dl_present_root.find_child(LMF.N_LAYER, true, false) as Control
	_ok("分母: 周日开场幕布建了周日那一层", it != null and it.fin != null and lay != null)
	if lay == null:
		_finish()
		return
	var tl := lay.find_child(LMF.N_TITLE, true, false) as Label
	_ok("① 缎带写轮次「冠军杯赛半决赛 · 第 1 / 2 场」", tl != null and tl.text == "冠军杯赛半决赛 · 第 1 / 2 场", tl.text if tl != null else "无")
	var pl := lay.find_child(LMF.N_PLATE + "left", true, false) as Control
	var pr := lay.find_child(LMF.N_PLATE + "right", true, false) as Control
	var tl_l: Array = _labels(pl) if pl != null else []
	var tl_r: Array = _labels(pr) if pr != null else []
	_ok("① ★左右名牌: 名字 + 来历 + 闯关战绩", tl_l.has("吃货一枚") and tl_l.has("B 组冠军") and tl_l.has("闯关 9 胜 2 负")
		and tl_r.has("小辉同学") and tl_r.has("E 组冠军（卫冕）") and tl_r.has("闯关 8 胜 3 负"), "%s | %s" % [str(tl_l), str(tl_r)])
	var n_name := 0
	for t in _labels(it.root):
		if t == "吃货一枚":
			n_name += 1
	_ok("① 大本营上不再写名字(名字只在名牌上出现一次)", n_name == 1, "「吃货一枚」%d 处" % n_name)
	## ── ② 动起来 ──
	var rib := lay.find_child(LMF.N_RIBBON, true, false) as Control
	var cr := lay.find_child(LMF.N_CREST, true, false) as Control
	var to_l := Vector2(16.0, vp.y - LMF.PLATE_H - LMF.BOTTOM_BAND)   # 名牌落点(左下, 底部那一排上面)
	it.pose(0.0)
	var p0 := pl.position
	_ok("② 0 秒: 缎带收成一条线、名牌在屏外、盾徽看不见", rib.scale.x < 0.1 and p0.x + pl.size.x <= 0.0 and cr.modulate.a <= 0.01,
		"缎带 %.2f 名牌 x %.0f 盾徽 a %.2f" % [rib.scale.x, p0.x, cr.modulate.a])
	it.pose(0.9)
	var c09: Vector2 = cr.position + cr.size * 0.5
	var s09: float = cr.scale.x
	it.pose(1.2)
	var c12: Vector2 = cr.position + cr.size * 0.5
	_ok("② 0.9 秒盾徽还在往下砸(更大、更高), 1.2 秒落在屏幕中间", s09 > 1.3 and c09.y < c12.y - 20.0 and absf(c12.x - vp.x * 0.5) < 2.0
		and cr.modulate.a > 0.99, "0.9: %.2f 倍 y %.0f; 1.2: y %.0f" % [s09, c09.y, c12.y])
	var ring_on := false
	for c in lay.get_children():
		if c is LMF.Ring and (c as LMF.Ring).prog > 0.0 and (c as LMF.Ring).prog < 1.0:
			ring_on = true
	_ok("② 1.2 秒冲击环在往外推", ring_on)
	it.pose(2.2)
	_ok("② ★2.2 秒缎带展开、名牌落位、盾徽已飞走", absf(rib.scale.x - 1.0) < 0.02 and pl.position.distance_to(to_l) < 1.0 and cr.modulate.a <= 0.01,
		"缎带 %.2f 名牌 %s→%s 盾徽 a %.2f" % [rib.scale.x, str(pl.position), str(to_l), cr.modulate.a])
	## ── ③ 名牌在屏内、不压底部那一排 ──
	var scr := Rect2(Vector2.ZERO, vp)
	var bad: Array = []
	for p in [pl, pr]:
		var r: Rect2 = (p as Control).get_global_rect()
		if not scr.encloses(r) or r.end.y > vp.y - LMF.BOTTOM_BAND + 0.5:
			bad.append(str(r))
	_ok("③ 2.2 秒名牌整张在屏内、不压底部那一排(%.0f px)" % LMF.BOTTOM_BAND, bad.is_empty() and LMF.BOTTOM_BAND >= 60.0, str(bad))
	## ── ④ ⑤ 战果幕: 上路右方(小辉同学)赢 ──
	GameState.lane_results = {}
	GameState.current_lane = "top"
	_b._dl_pending_loser = "left"
	_b._dl_state = "lane_settle"
	_b._dl_sys._dl_build_present_overlay("lane_settle")
	var is_ = _intro()
	var lay2: Control = _b._dl_present_root.find_child(LMF.N_LAYER, true, false) as Control
	var dl := lay2.find_child(LMF.N_DIGIT + "left", true, false) as Label if lay2 != null else null
	var dr := lay2.find_child(LMF.N_DIGIT + "right", true, false) as Label if lay2 != null else null
	_ok("分母: 战果幕建了记分牌", lay2 != null and dl != null and dr != null)
	if dl == null:
		_finish()
		return
	is_.pose(0.5)
	var b05 := "%s:%s" % [dl.text, dr.text]
	is_.pose(2.0)
	var b20 := "%s:%s" % [dl.text, dr.text]
	_ok("④ ★记分牌翻牌: 0.5 秒 0:0, 2.0 秒赢的那边翻成 1(0:1)", b05 == "0:0" and b20 == "0:1", "%s → %s" % [b05, b20])
	_ok("④ 记分牌两侧写名字", _labels(lay2.find_child(LMF.N_SCORE, true, false)).has("吃货一枚") and _labels(lay2.find_child(LMF.N_SCORE, true, false)).has("小辉同学"))
	var res := _b._dl_present_root.find_child("LaneSettleResult", true, false) as Label
	_ok("⑤ ★看别人的比赛 ⇒ 战果章「小辉同学 赢得上路」", res != null and res.text == "小辉同学 赢得上路", res.text if res != null else "无")
	var eg := _b._dl_present_root.find_child("LaneSettleEggs", true, false) as Label
	_ok("⑤ 「我方 / 对方」蛋血行不显示(字留着)", eg == null or eg.self_modulate.a <= 0.01)
	_b._hud._replay_ui = null
	_finish()


func _finish() -> void:
	if _b != null and is_instance_valid(_b):
		_b.queue_free()
	ReplayRecorder.play_names = {}
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
