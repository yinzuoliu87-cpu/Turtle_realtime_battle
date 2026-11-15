extends Node
## verify_lane_map_intro.gd —— 三路开场「桌面作战地图」/ 对阵 / 一路战果 / 开战横幅(2026-11-15)。
## 用户 11-15:「三路开战这个…不符合一种商业游戏啊…是否可以通过…地图一样的形式去展现出来」→ 第三轮:
##   「在一个视角上面看到下面一张地图吧…把视角往里面挪动…如果你输了，这一个叉就挥掉…如果到终极战场的话，那就中间这个大战场就亮起来…
##    每次登场就是…三只三只，都得明白」
## 方案书 docs/plans/20261115d-三路战场地图开场.md。实现 scripts/scenes/battle/lane_map_intro.gd(轨道表 + pose(t)) + lane_war_table.gd(独立 3D 世界)。
## 判据(真战斗场 + App Store 截图台那份真实阵容, 无头; 镜头 / 投影是纯数学, 无头也能量):
##   ① 开场地图: 3 块战场台 + 2 个大本营; 3.8 秒(总览, 推近前)三块台子与两端大本营的投影都在屏内, 跟着 3D 点走的字也都在屏内(分母 = 字数)
##   ② ★三对三: 上 / 下两路的立牌数 = 两路双方阵容人数之和(每路每侧 3 只); 终极战场两侧「？」4 个
##   ③ 镜头: 4.95 秒已飞到上路台子跟前(距离 < 9 米、台子投影在屏幕中间 30% 内); 战果幕 0 秒在刚打完那一路跟前、1.0 秒拉回总览
##   ④ ★一路战果: 跳去终极战场的立牌数 = 此刻场上幸存人数; 印章按看的人那一侧(左方赢、看的人是左方 ⇒「本战场胜利」)
##   ⑤ ★输赢的样子: 看的人赢了 ⇒ 这一路亮胜方光圈、不打叉; 输了 ⇒ 台面上两刀打叉
##   ⑥ ★下一路是终极战场 ⇒ 中间大战场亮起来(lit3); 下一路是下路 ⇒ 不亮
##   ⑦ 对阵幕: 双方全身立绘张数 = 本路阵容人数; 1.5 秒看得见的控件全在屏内
##   ⑧ ★开战横幅: 开打那一刻出现、约 1.2 秒后自己收掉; 录流端发 fight_banner、播放端认它(读源码)
## 反向验证(11-15): 印章侧别写反 ⇒ ④ 红; _mark_result3 里 lost 取反 ⇒ ⑤ 红; 不调 show_fight_banner ⇒ ⑧ 红。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const WT := preload("res://scripts/scenes/battle/lane_war_table.gd")

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


func _visible_controls(root: Node) -> Array:
	var out: Array = []
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if not (c is Control) or not (c as Control).is_visible_in_tree():
				continue
			var cc := c as Control
			if cc.modulate.a < 0.5:
				continue
			var r: Rect2 = cc.get_global_rect()
			if r.size.x >= vp.x * 0.9 and r.size.y >= vp.y * 0.9:
				continue
			out.append(cc)
	return out


func _count_tracks(it, kind: String, node = null) -> int:
	var n := 0
	for tr in it.tracks:
		if str(tr["k"]) == kind and (node == null or is_same(tr["node"], node)):
			n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	print("=== 三路开场: 桌面作战地图 / 对阵 / 战果 / 开战横幅 ===")
	## 手机横屏比例(无头默认是 1280×1280 正方形, 量不出手机上的取景); LM_WIN=1280x960 换成 iPad 的可视区再跑一遍
	var win := Vector2i(1560, 720)
	if OS.get_environment("LM_WIN").contains("x"):
		var pr: PackedStringArray = OS.get_environment("LM_WIN").split("x")
		win = Vector2i(int(pr[0]), int(pr[1]))
	get_window().size = win
	await get_tree().process_frame
	load("res://tests/_setup_appstore.gd").run()
	GameState.dual_active = true   # 双路对局(门禁不带 DUALLANE 环境变量跑)
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var scr := Rect2(Vector2(-2, -2), vp + Vector2(4, 4))
	print("  [分母] 屏幕 %s" % str(vp))
	## ── ① ② 开场地图 ──
	_ok("分母: 进场就是开场地图幕", await _wait_state("overview", 600), str(_b._dl_state))
	var it = _intro()
	_ok("分母: 幕布下挂着演出对象(Clock.intro)且建了桌面地图", it != null and it.table != null)
	if it == null or it.table == null:
		_finish()
		return
	var tb = it.table
	_ok("① 3 块战场台(上 / 下 / 终极) + 2 个大本营", tb.isl.size() == 3 and tb.bases.size() == 2)
	var want_st: int = 0
	for ln in ["top", "bottom"]:
		want_st += _b._dl_sys._dl_lane_specs(ln).size() + _b._dl_sys._dl_foe_specs(ln).size()
	var n_st := 0
	for st in tb.standees:
		if str(st["lane"]) in ["top", "bottom"]:
			n_st += 1
	_ok("② ★三对三: 上下两路立牌数 = 两路双方阵容人数(%d)" % want_st, n_st == want_st and want_st == 12, "实际 %d" % n_st)
	var n_q := 0
	for c in it.root.find_children("*", "Label", true, false):
		if (c as Label).text == "?":
			n_q += 1
	_ok("② 终极战场两侧「？」4 个", n_q == 4, "实际 %d" % n_q)
	it.pose(3.8)
	var outside: Array = []
	for p3 in [WT.LANE_POS["top"], WT.LANE_POS["bottom"], WT.LANE_POS["final"], WT.BASE_POS["left"], WT.BASE_POS["right"]]:
		var sp: Vector2 = tb.project(p3)
		if not scr.has_point(sp):
			outside.append("%s→%s" % [str(p3), str(sp)])
	_ok("① 3.8 秒总览: 三块台子与两端大本营都在画面里", outside.is_empty(), str(outside))
	var anchored_out: Array = []
	for an in it.anchors:
		var nd: Control = an["node"]
		if nd.is_visible_in_tree() and nd.modulate.a >= 0.5 and not scr.encloses(nd.get_global_rect()):
			anchored_out.append("%s %s" % [nd.get_class(), str(nd.get_global_rect())])
	_ok("① 3.8 秒跟着 3D 点走的字全在屏内(分母 %d)" % it.anchors.size(), it.anchors.size() >= 10 and anchored_out.is_empty(), str(anchored_out.slice(0, 4)))
	## ── ③ 推近 ──
	it.pose(4.95)
	var top_c: Vector3 = WT.LANE_POS["top"]
	var d_cam: float = tb.cam.position.distance_to(top_c)
	## 量立牌身体中段(台面上 0.65 米)的投影: 推近终点要把三对三放在画面中间那一块
	var sp_top: Vector2 = tb.project(top_c + Vector3(0, WT.TOP_Y + 0.65, 0))
	_ok("③ 4.95 秒已飞到上路台子跟前(距离 %.1f 米 < 9, 三对三在画面中间)" % d_cam,
		d_cam < 9.0 and absf(sp_top.x - vp.x * 0.5) < vp.x * 0.15 and sp_top.y > vp.y * 0.25 and sp_top.y < vp.y * 0.75, str(sp_top))
	## ── ⑦ 对阵幕 ──
	_ok("分母: 开场地图 5 秒后进对阵幕", await _wait_state("preview", 900), str(_b._dl_state))
	var iv = _intro()
	var want_body: int = _b._dl_sys._dl_lane_specs("top").size() + _b._dl_sys._dl_foe_specs("top").size()
	var n_body := 0
	for c in iv.map.find_children("*", "TextureRect", true, false):
		if (c as TextureRect).texture is AtlasTexture and (c as Control).size.y >= 100.0:
			n_body += 1
	_ok("⑦ 双方全身立绘张数 = 上路双方阵容人数(%d)" % want_body, n_body == want_body and want_body >= 2, "实际 %d" % n_body)
	iv.pose(1.5)
	var out_vs: Array = []
	var vis_vs: Array = _visible_controls(_b._dl_present_root)
	for c in vis_vs:
		if not scr.encloses((c as Control).get_global_rect()):
			out_vs.append("%s %s" % [(c as Control).get_class(), str((c as Control).get_global_rect())])
	_ok("⑦ 1.5 秒看得见的控件全在屏内(分母 %d)" % vis_vs.size(), vis_vs.size() >= 10 and out_vs.is_empty(), str(out_vs.slice(0, 4)))
	## ── ⑧ 开战横幅 ──
	_ok("分母: 对阵幕 5 秒后开打", await _wait_state("fight", 900), str(_b._dl_state))
	var fb: Node = _b._ui_layer.find_child("FightBanner", false, false)
	_ok("⑧ ★开打那一刻 UI 层出现开战横幅", fb != null)
	var gone := false
	for _i in 200:
		await get_tree().process_frame
		if fb == null or not is_instance_valid(fb) or fb.is_queued_for_deletion():
			gone = true
			break
	_ok("⑧ 横幅约 1.2 秒后自己收掉(没留在战场上)", gone)
	var src_dl: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var src_sp: String = FileAccess.get_file_as_string("res://scripts/systems/stream/stream_player.gd")
	_ok("⑧ 录流端发 fight_banner 事件、播放端认它(手机直播也出横幅)",
		src_dl.contains("StreamRecorder.cur.ev(\"fight_banner\"") and src_sp.contains("\"fight_banner\":") and src_sp.contains("show_fight_banner("))
	## ── ③ ④ ⑤ ⑥ 一路战果(上路, 左方赢) ──
	for _i in 60:
		await get_tree().process_frame
	var alive := 0
	for u in _b._units:
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_summon", false) or u.get("is_trainer", false):
			continue
		if _b._eff_side(u) in ["left", "right"]:
			alive += 1
	_b._dl_pending_loser = "right"
	_b._dl_sys._dl_enter_present("lane_settle")
	var is_ = _intro()
	var hops := _count_tracks(is_, "hop3")
	_ok("④ ★跳去终极战场的立牌数 = 此刻场上幸存人数(%d)" % alive, hops == alive and hops >= 2, "跳了 %d" % hops)
	var res := _b._dl_present_root.find_child("LaneSettleResult", true, false) as Label
	_ok("④ ★印章: 左方赢、看的人是左方 ⇒「本战场胜利」", res != null and res.text == "本战场胜利", res.text if res != null else "无")
	var top_d: Dictionary = is_.table.isl["top"]
	var n_slash_won: int = _count_tracks(is_, "slash3", (top_d["slash"] as Array)[0]) + _count_tracks(is_, "slash3", (top_d["slash"] as Array)[1])
	_ok("⑤ ★看的人赢了这一路 ⇒ 亮胜方光圈、不打叉", _count_tracks(is_, "fade3", top_d["glow_mat"]) == 1 and n_slash_won == 0, "叉 %d" % n_slash_won)
	_ok("⑥ 下一路是下路 ⇒ 终极战场不亮", _count_tracks(is_, "lit3") == 0)
	is_.pose(0.0)
	var d0: float = is_.table.cam.position.distance_to(top_c)
	is_.pose(1.0)
	var d1: float = is_.table.cam.position.distance_to(top_c)
	_ok("③ 战果幕: 0 秒在上路跟前(%.1f 米), 1.0 秒拉回总览(%.1f 米)" % [d0, d1], d0 < 12.0 and d1 > d0 + 8.0)
	## ── ⑤ ⑥ 再演一次: 下路输了(看的人是左方, 左方输)⇒ 打叉; 下一路是终极战场 ⇒ 中间亮起来 ──
	GameState.current_lane = "bottom"
	_b._dl_pending_loser = "left"
	_b._dl_sys._dl_build_present_overlay("lane_settle")
	var ib = _intro()
	var bot_d: Dictionary = ib.table.isl["bottom"]
	var n_slash: int = _count_tracks(ib, "slash3", (bot_d["slash"] as Array)[0]) + _count_tracks(ib, "slash3", (bot_d["slash"] as Array)[1])
	_ok("⑤ ★看的人输了这一路 ⇒ 台面上两刀打叉", n_slash == 2, "叉 %d" % n_slash)
	ib.pose(1.4)
	var prog: float = float(((bot_d["slash"] as Array)[1] as ShaderMaterial).get_shader_parameter("prog"))
	_ok("⑤ 1.4 秒两刀都划完(第二刀 prog %.2f)" % prog, prog >= 0.99)
	_ok("⑥ ★下一路是终极战场 ⇒ 中间大战场亮起来", _count_tracks(ib, "lit3") == 1)
	ib.pose(3.6)
	var lit: float = float((ib.table.isl["final"]["top_mat"] as ShaderMaterial).get_shader_parameter("lit"))
	_ok("⑥ 3.6 秒终极战场台面已亮(lit %.2f)" % lit, lit > 0.9)
	_finish()


func _finish() -> void:
	if _b != null and is_instance_valid(_b):
		_b.queue_free()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
