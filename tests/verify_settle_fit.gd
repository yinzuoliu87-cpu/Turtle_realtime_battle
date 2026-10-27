extends Node
## verify_settle_fit.gd — 结算屏【内容不越出可视区】门禁 (2026-10-27)
##
## 由来: 用户 iPad 实机截图(TestFlight 0.22.2, 积分赛失败结算, 「自己看看什么问题」):
##   · 「本场 MVP」那一行只露出上半截, 被按钮那一排的上沿切掉 —— 积分赛比练习赛多「消耗生命 / 阵容已上传 / 五格数据」,
##     而发版前只拍过练习赛; verify_settle_pages ① 也只量练习赛那一版、只量无安全区的桌面视口。
##   · 左上「失败」压在战斗 HUD 的头像和名字上、右边缘透出单位栏 —— 结算底只淡到 0.92, HUD 透出来。
##   · 我方 / 敌方页在 iPad 窗口里右边被切: iPad 窗口模式左右各报 ~47 的安全区, 8 列表横向放不下。
##
## 每种【视口 × 安全区】× 每种【结算变体】× 三页, 量屏上每一件字与图(Label / 按钮字 / 头像等贴图; 贴了大字图的量图本身):
##   ① 矩形落在「它所有裁剪祖先的交集 ∩ 安全区」里 —— 不被页体切、不出屏、不进刘海 / 手势条
##      (★正文页体是裁剪区 ⇒ MVP 那一行被按钮排切掉 = 它不在页体里 = 红)
##   ①b 战果页每一块(大字 / 说明 / 各路 / 数据 / MVP)整块在页体里
##   ② 金属框里的字(正文 + 按钮行)不出金属框
##   ③ 我方 / 敌方页滚动区里压在下面的行: 只有滚动区真能滚、按钮左边写着「▼ 另有 N 个单位」才放行(设计好的滚动);
##      横向一律不放行(表格不许横向切)
##   ④ 盖住战斗界面: 结算底不透明、铺满整个视口; 同层别的东西(含子孙)绝对 z 都比结算屏低, 更高的画布层没有可见的东西
##   ⑤ 左栏胜负只在我方 / 敌方页亮(战果页正中已有大字, 同一屏不写两遍)
##   分母: 每一组量了多少个字逐条打印, 任何一组 0 个 = 红; 变体本身(三路三块牌 / 五格数据 / MVP / 两行说明)逐个确认建出来了
##
## 视口: 用户点名的四种 1560×720 / 1289×720 / 1280×800 / 1280×960, 每种跑「无安全区」与「真机安全区」两遍,
##   另加最窄最矮的 1280×720 + iPad 窗口安全区。安全区数值:
##   · iPad 窗口模式 (47, 0, 48, 38): 从用户截图量的(金属框青线 / 左栏页签的位置反推, 与实拍逐像素对上)
##   · iPhone 横屏 (108, 0, 108, 38): 刘海边 59pt / 手势条 21pt × (720 ÷ 393pt)
##   · iPad 全屏 4:3 (0, 0, 0, 25): 手势条 20pt × (960 ÷ 768pt)
##
## 跑法: bash godot-quiet.sh res://tests/verify_settle_fit.tscn --quit-after 8000(钉 60fps, 实测见 run-tests.sh frames_for)

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
const SS := preload("res://scripts/scenes/battle/settle_screen.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RP := preload("res://scripts/net/remote_pool.gd")

const IPAD_WIN := Vector4(47, 0, 48, 38)
const PHONE := Vector4(108, 0, 108, 38)
const IPAD_FULL := Vector4(0, 0, 0, 25)
const CASES := [
	[Vector2i(1560, 720), PHONE, "手机横屏"],
	[Vector2i(1289, 720), IPAD_WIN, "iPad 窗口(用户那一台)"],
	[Vector2i(1280, 800), IPAD_WIN, "16:10 窗口"],
	[Vector2i(1280, 960), IPAD_FULL, "iPad 全屏 4:3"],
	[Vector2i(1560, 720), Vector4.ZERO, "无安全区"],
	[Vector2i(1289, 720), Vector4.ZERO, "无安全区"],
	[Vector2i(1280, 800), Vector4.ZERO, "无安全区"],
	[Vector2i(1280, 960), Vector4.ZERO, "无安全区"],
	[Vector2i(1280, 720), IPAD_WIN, "最窄最矮"],
]
## [名字, 赢了吗, 种类]。种类: ranked 积分赛三路 / ranked6 积分赛 + 「阵容上传 失败」第六格 / gauntlet 闯关赛晋级那一局(两行说明)
##   / sealed 周日封存 / practice 练习赛两路
const VARIANTS := [
	["积分赛·负", false, "ranked"],
	["积分赛·胜", true, "ranked"],
	["积分赛·负·六格", false, "ranked6"],
	["闯关赛·晋级", true, "gauntlet"],
	["决赛日·封存", true, "sealed"],
	["练习赛·胜", true, "practice"],
	["练习赛·负", false, "practice"],
]
const TOL := 0.5

var _n := 0
var _fail := 0
var _texts_total := 0
var _below_total := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _ready() -> void:
	## ★钉 60fps: 要按墙钟等胜负大字滑入落位 / 结算底淡入, 无头不限帧时一秒能跑几千帧, --quit-after 的帧预算没个准
	Engine.max_fps = 60
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true                                  # 不许写真存档
	var keys := ["lane_results", "dual_active", "finals_pending_reveal", "week_phase", "hearts", "season_wins",
		"ranked_used", "season_level", "gauntlet_wins", "gauntlet_losses", "gauntlet_backfill_paid", "current_lane"]
	var bak := {}
	for k in keys:
		var v = gs.get(k)
		bak[k] = v.duplicate() if v is Dictionary else v
	var rp_bak := [RP.fail_count, RP.ok_count]
	for c in CASES:
		await _run(c[0], c[1], str(c[2]))
	SafeArea.override_insets = Vector4(-1.0, -1.0, -1.0, -1.0)
	RP.fail_count = rp_bak[0]
	RP.ok_count = rp_bak[1]
	for k in keys:
		gs.set(k, bak[k])
	_ok("★分母: 一共量了 %d 件字 / 图(其中 %d 件在滚动区下面, 靠滚动看得到)" % [_texts_total, _below_total], _texts_total >= 1000)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("  (用了 %d 帧)" % Engine.get_process_frames())
	print("ALL PASS — 结算屏内容不越出可视区" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _run(v: Vector2i, ins: Vector4, label: String) -> void:
	var tag := "%d×%d %s" % [v.x, v.y, label]
	print("── %s 安全区 %s ──" % [tag, str(ins)])
	SafeArea.override_insets = ins
	get_tree().root.content_scale_size = v
	get_tree().root.size = v
	for _q in range(4):
		await get_tree().process_frame
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	sc.set_process(false)                # 停掉 sim: 名单是这里摆的
	sc.set_physics_process(false)
	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	_ok("[%s] ★分母: 视口真的是 %dx%d" % [tag, v.x, v.y], vp.is_equal_approx(Vector2(v)), str(vp))
	var safe := Rect2(Vector2(ins.x, ins.y), vp - Vector2(ins.x + ins.z, ins.y + ins.w))
	var first := true
	for vr in VARIANTS:
		var scr = await _open(sc, str(vr[2]), bool(vr[1]))
		var vt := "%s · %s" % [tag, vr[0]]
		_ok("[%s] ★分母: 结算屏建出来了, 三页" % vt, scr != null and (scr.pages as Array).size() == 3)
		if scr == null:
			continue
		_check_variant(scr, str(vr[2]), vt)
		_check_rail(scr, v, ins, vt)
		if first:
			await _check_cover(sc, scr, vp, tag)
			first = false
		for pi in range(3):
			scr.show_page(pi)
			for _i in range(4):
				await get_tree().process_frame
			_check_page(scr, pi, safe, vt)
			var rw: Label = scr.rail_word
			var want_a := 0.0 if pi == 0 else 1.0
			_ok("[%s] ⑤ 第 %d 页左栏胜负%s" % [vt, pi + 1, "透明(正中已有大字)" if pi == 0 else "亮着"],
				rw != null and absf(rw.modulate.a - want_a) < 0.01 and rw.is_visible_in_tree(), "a=%.2f" % (rw.modulate.a if rw != null else -1.0))
	sc.queue_free()
	for _i in range(3):
		await get_tree().process_frame


## 变体真的是那一版(分母): 积分赛三块牌 + 五格(或六格) + MVP; 闯关赛两行说明; 封存不画各路; 练习赛两块牌没有数据格
func _check_variant(scr, kind: String, vt: String) -> void:
	var p1: Control = scr.pages[0]
	var lanes: Node = p1.find_child("LaneResults", true, false)
	var nl: int = lanes.get_child_count() if lanes != null else 0
	var chips := 0
	for c in p1.get_children():
		if c is HBoxContainer and str(c.name) != "LaneResults" and str(c.name) != "MvpRow":
			chips = c.get_child_count()
	var mvp: Node = p1.find_child("MvpRow", true, false)
	var det: Label = p1.find_child("ResultDetail", true, false) as Label
	var flash: Label = scr.find_child("UploadFlash", true, false) as Label
	var want_l: int = {"ranked": 3, "ranked6": 3, "gauntlet": 3, "sealed": 0, "practice": 2}[kind]
	## 周末两站的格数随「这一站上线没有」变(本周场次那一格), 只要求 ≥ 3; 其余是确数
	var want_c: int = {"ranked": 5, "ranked6": 6, "gauntlet": -3, "sealed": -3, "practice": 0}[kind]
	var c_ok: bool = chips == want_c if want_c >= 0 else chips >= -want_c
	var ok := nl == want_l and c_ok and mvp != null and flash != null and flash.is_visible_in_tree() == (kind != "practice")
	if kind == "gauntlet":
		ok = ok and det != null and det.get_line_count() >= 2
	_ok("[%s] ★分母: 这一版的内容都在(各路 %d / 数据 %s 格 / MVP / 上传提示%s)" % [vt, want_l, str(want_c) if want_c >= 0 else "≥%d" % -want_c,
		" / 两行说明" if kind == "gauntlet" else ""], ok,
		"各路 %d 数据 %d MVP %s 上传 %s 说明 %d 行" % [nl, chips, str(mvp != null), str(flash.is_visible_in_tree() if flash != null else null),
			det.get_line_count() if det != null else 0])


## 左栏宽: 宽屏(1560 无安全区)上就是原来的 220 一点没让; 别处在 [RAIL_MIN, RAIL_W] 里、页签与左栏同宽
func _check_rail(scr, v: Vector2i, ins: Vector4, vt: String) -> void:
	var rail: Control = scr.find_child("SettleRail", true, false)
	var w: float = rail.size.x if rail != null else -1.0
	var tabs_ok := true
	for b in scr.tab_btns:
		tabs_ok = tabs_ok and absf((b as Control).size.x - w) <= TOL
	var want_full := v.x >= 1560 and ins == Vector4.ZERO
	_ok("[%s] 左栏宽 %.0f(%s)、三个页签同宽" % [vt, w, "宽屏不让" if want_full else "%.0f~%.0f" % [SS.RAIL_MIN, SS.RAIL_W]],
		rail != null and tabs_ok and (absf(w - SS.RAIL_W) <= TOL if want_full else (w >= SS.RAIL_MIN - TOL and w <= SS.RAIL_W + TOL)))


## ④ 盖住战斗界面
func _check_cover(sc, scr, vp: Vector2, tag: String) -> void:
	var t0 := Time.get_ticks_msec()
	var bd := scr.find_child("SettleBackdrop", false, false) as ColorRect
	while bd != null and bd.color.a < 0.999 and Time.get_ticks_msec() - t0 < 3000:   # 淡入 0.35 秒(墙钟)
		await get_tree().process_frame
	_ok("[%s] ④ 结算底不透明、铺满视口" % tag, bd != null and bd.color.a >= 0.999
		and bd.get_global_rect().grow(TOL).encloses(Rect2(Vector2.ZERO, vp)),
		"a=%.3f rect=%s" % [bd.color.a if bd != null else -1.0, str(bd.get_global_rect()) if bd != null else "null"])
	## 画序: 绝对 z 大的在上; z 相同按树序, 排在结算屏后面的在上
	var z_me := _abs_z(scr)
	var above: Array = []
	var nseen := 0
	for c in sc._ui_layer.get_children():
		if c == scr:
			continue
		var later: bool = (c as Node).get_index() > scr.get_index()
		for n in [c] + (c as Node).find_children("*", "CanvasItem", true, false):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				nseen += 1
				var z := _abs_z(n)
				if z > z_me or (z == z_me and later):
					above.append("%s z=%d%s" % [str(n.name), z, " 树序在后" if later else ""])
	_ok("[%s] ④ 同层 %d 个可见件都画在结算屏下面(结算屏 z=%d)" % [tag, nseen, z_me], nseen > 0 and above.is_empty(), str(above.slice(0, 6)))
	var lay: int = int(sc._ui_layer.layer)
	var over: Array = []
	for cl in sc.find_children("*", "CanvasLayer", true, false):
		if (cl as CanvasLayer).layer > lay and (cl as CanvasLayer).visible:
			for n in (cl as Node).find_children("*", "CanvasItem", true, false):
				if (n as CanvasItem).is_visible_in_tree():
					over.append("%s(层 %d)" % [str(n.name), (cl as CanvasLayer).layer])
					break
	_ok("[%s] ④ 比结算屏更高的画布层上没有可见的东西" % tag, over.is_empty(), str(over))


func _abs_z(n: Node) -> int:
	var z := 0
	var p: Node = n
	while p != null and p is CanvasItem:
		z += (p as CanvasItem).z_index
		if not (p as CanvasItem).z_as_relative:
			break
		p = p.get_parent()
	return z


## ①②③ 一页上每一件字与图
func _check_page(scr, pi: int, safe: Rect2, vt: String) -> void:
	var frame: Control = scr.find_child("SettleFrame", true, false)
	var fr: Rect2 = frame.get_global_rect().grow(TOL)
	var bad: Array = []
	var nt := 0
	var below := 0
	var sc_team: ScrollContainer = scr._scrolls[pi - 1] if pi >= 1 else null
	for n in scr.find_children("*", "", true, false):
		var r := _drawn_rect(n)
		if r.size == Vector2.ZERO:
			continue
		nt += 1
		var clip := _clip_of(n as Control, safe)
		if clip.grow(TOL).encloses(r):
			if frame.is_ancestor_of(n) and not fr.encloses(r):
				bad.append("②「%s」%s 出了金属框 %s" % [_txt(n), str(r), str(fr)])
			continue
		## ③ 我方 / 敌方表格里压在下面的行: 横向必须在可视区内, 纵向在下沿以外 ⇒ 要能滚、要有提示
		if sc_team != null and sc_team.is_ancestor_of(n):
			var c2 := clip.grow(TOL)
			var bar := sc_team.get_v_scroll_bar()
			var x_in := r.position.x >= c2.position.x and r.end.x <= c2.end.x
			if x_in and r.end.y > c2.end.y and bar.max_value > bar.page + TOL and str(scr.more_hint.text) != "" and scr.more_hint.is_visible_in_tree():
				below += 1
				continue
		bad.append("①「%s」%s 不在可视区 %s" % [_txt(n), str(r), str(clip)])
	## 战果页: 每一块(大字 / 说明 / 各路 / 数据 / MVP)整块都在页体里 —— 块比块里的字更早露馅
	if pi == 0:
		var p1: Control = scr.pages[0]
		var body_r: Rect2 = (p1.get_parent() as Control).get_global_rect().grow(TOL)
		for c in p1.get_children():
			if c is Control and (c as Control).visible and not body_r.encloses((c as Control).get_global_rect()):
				bad.append("①b 战果页这一块「%s」%s 出了页体 %s" % [str(c.name), str((c as Control).get_global_rect()), str(body_r)])
	_texts_total += nt
	_below_total += below
	_ok("[%s] ①②③ 第 %d 页 %d 件字 / 图都在可视区里(%d 件在表格下面, 可滚)" % [vt, pi + 1, nt, below],
		nt >= 8 and bad.is_empty(), str(bad.slice(0, 4)))


## 一件「画出来的东西」的矩形: 字(Label / 按钮)与图(头像等 TextureRect)。贴了大字图的标签量图(标签自己的字是透明的,
##   图本身是标签的子节点, 不重复量)。不可见 / 空字 / 没贴图 ⇒ ZERO。
##   ★图也要量(2026-10-27 反向验证时发现): 只量字时把 MVP 头像放大到 120, MVP 那一行溢出页体、头像被切掉下半,
##   可名字和伤害是竖直居中的、还在页体里 ⇒ 门禁照样全绿 —— 「MVP 那一行被切」恰恰先切的是头像。
func _drawn_rect(n: Node) -> Rect2:
	if not (n is Control) or not (n as Control).is_visible_in_tree():
		return Rect2()
	if n is TextureRect:
		if (n as TextureRect).texture == null or str(n.name) == BigTitle.ART_NODE:
			return Rect2()
		return (n as Control).get_global_rect()
	if n is Label:
		if str((n as Label).text).strip_edges() == "":
			return Rect2()
		var art := (n as Node).get_node_or_null(BigTitle.ART_NODE) as Control
		if art != null:
			return art.get_global_rect()
		return (n as Control).get_global_rect()
	if n is Button and str((n as Button).text).strip_edges() != "":
		return (n as Control).get_global_rect()
	return Rect2()


func _txt(n: Node) -> String:
	return str(n.get("text")).replace("\n", "/")


## 全部祖先 clip_contents 矩形 ∩ 安全区 —— 玩家真正看得见的那一块
func _clip_of(c: Control, safe: Rect2) -> Rect2:
	var r := safe
	var p: Node = c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _open(sc, kind: String, won: bool) -> Node:
	var gs = get_node_or_null("/root/GameState")
	if sc._hud._settle != null and is_instance_valid(sc._hud._settle):
		sc._hud._settle.queue_free()
	await get_tree().process_frame
	var three := kind != "practice"
	sc._st_lane_hist = _make_hist(three)
	sc._units.clear()
	gs.dual_active = true
	gs.current_lane = "final" if three else "bottom"
	if three:
		gs.lane_results = {"top": "left", "bottom": "right", "final": "left" if won else "right"}
	else:
		gs.lane_results = {"top": "right" if won else "left", "bottom": "left" if won else "right"}
	gs.finals_pending_reveal = {"round": 1, "match": 0, "bucket": 0} if kind == "sealed" else {}
	gs.week_phase = P2C.PHASE_GAUNTLET if kind == "gauntlet" else (P2C.PHASE_FINALS if kind == "sealed" else P2C.PHASE_RANKED)
	gs.hearts = 5
	gs.season_wins = 3
	gs.ranked_used = 1
	gs.season_level = 2
	gs.gauntlet_wins = 4 if kind == "gauntlet" else 0
	gs.gauntlet_losses = 1 if kind == "gauntlet" else 0
	gs.gauntlet_backfill_paid = 1 if kind == "gauntlet" else 0    # 提前晋级奖励 ⇒ 说明是两行(最高的那一版)
	RP.fail_count = 1 if kind == "ranked6" else 0                  # 「阵容上传 · 上传失败」第六格
	RP.ok_count = 0
	sc._had_season = kind != "practice"
	sc._last_was_exhibition = false
	sc._last_reward = 15
	sc._last_settle_kind = {"ranked": P2C.SETTLE_RANKED, "ranked6": P2C.SETTLE_RANKED, "gauntlet": P2C.SETTLE_GAUNTLET,
		"sealed": P2C.SETTLE_FINALS, "practice": ""}[kind]
	sc._settled = false
	sc._hud._show_banner(won)
	var scr = sc._hud._settle
	if scr == null:
		return null
	## 晋级那一局先演整屏仪式(它有自己的门禁) ⇒ 收掉, 量下面的战果页
	var cer: Node = scr.find_child(StageCeremony.NODE_NAME, true, false)
	if cer != null:
		cer.free()
	## 「阵容已上传」回执到了才亮 ⇒ 这里直接点亮(量的是它亮着时的版式; 亮不亮的逻辑归 verify_upload_flash)
	var fl := scr.find_child("UploadFlash", true, false) as Label
	if fl != null and kind != "practice":
		fl.visible = true
	## 等排版 + 等胜负大字从左边滑进来落位(T_TAP 延迟 + T_BASE, 墙钟; 滑到一半时它在槽里偏左 240)
	for _i in range(12):
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 360:
		await get_tree().process_frame
	return scr


## 一行快照(键名与产品 `_st_row` 一致)
func _row(id: String, nm: String, multi: bool, d: int, alive: bool) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": false, "_st_multi": multi, "rarity": "C",
		"alive": alive, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": 12345, "_st_heal": 2345, "_st_crit": 0, "_st_kills": 3,
		"_st_shield": 1234, "_st_dealt_by_type": {"phy": d - d / 3, "mag": d / 3, "tru": 0}}


## 三路(积分赛)/ 两路(练习赛)。每路: 统领 + 小将 + 龟蛋 + 训龟大师; 合计每侧 9~10 行(小将按路分身份) ⇒ 表要滚, ③ 那条有东西可量。
##   最宽的名字格: 四字名 + 阵亡 + MVP(MVP 给死掉的那只)。
func _make_hist(three: bool) -> Array:
	var out: Array = []
	var lanes: Array = ["top", "bottom", "final"] if three else ["top", "bottom"]
	for lane in lanes:
		var snap := {"lane": lane}
		snap["left"] = [_row("hiding", "缩头乌龟", false, 98765, false), _row("two_head", "双头龟", false, 9000, true),
			_row("minion", "小将", true, 3000, true), _row("egg", "龟蛋", false, 0, true), _row("trainer", "训龟大师", false, 400, false)]
		snap["right"] = [_row("hunter", "猎人龟", false, 8000, true), _row("minion", "精英小将", true, 3000, false),
			_row("minion", "小将", true, 1200, true), _row("egg", "龟蛋", false, 0, true), _row("trainer", "训龟大师", false, 400, true)]
		out.append(snap)
	return out
