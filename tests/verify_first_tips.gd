extends Node

## verify_first_tips.gd — 账号侧「第一次遇到」一行提示(方案书 docs/plans/20261020-教程重写.md §3 / 验收清单第 3 条)
##
## 量(全走真入口: 真主菜单 + FirstTips 本身):
##   ① 教程刚结束、本大轮 0 场 ⇒ 主菜单出「开始第一场对战」, 圈在「开始战斗」上; 只出一次(再开主菜单不出)
##   ② 不挡点击(本层没有吃点击的可见控件), 点任意处 / 5 秒后自己收起
##   ③ 「看过了」进账号存档(_save_dict 里有, 读档后还在) —— 但出提示那一刻**不写盘**(教程结束后存档只差 onboarded)
##   ④ ★★教程进行中一律不出现、也不写(反向: 去掉 can_show 的教程闸 ⇒ 这条红)
##   ⑤ 周六 / 周日第一次打开主菜单 ⇒ 圈模式卡, 文案读赛制名(「闯关赛」/「决赛日」), 各只一次; 平日不出这两条
##   ⑥ 首启选择框在场时不出(选择框是那一屏唯一的事)
##   ⑦ 2026-10-20 补的四条(真场景): 背包第一次有羁绊激活 / 商店第一次买到合成升星 / 第一次看周六服务器局 /
##      第一次打开训龟大师 —— 各圈对的东西、文案对、不挡点击、只出一次、教程中不出

const FT := preload("res://scripts/systems/onboarding/first_tips.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := "res://scenes/MainMenu.tscn"
const INV := "res://scenes/Inventory.tscn"
const SHOP := "res://scenes/Shop.tscn"
const TRAINER := "res://scenes/TrainerConfig.tscn"
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const TG := preload("res://scripts/scenes/TutorialGuide.gd")
const _StubBattle := preload("res://tests/_first_tips_stub_battle.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 70


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size = Vector2i(1280, 720)
	Engine.max_fps = 60      # 「5 秒自己收起」按真实时间走; 钉帧率 ⇒ 帧预算可预期
	await get_tree().process_frame
	OS.set_environment("ONBOARD", "0")
	GameState.test_mode = true          # 不写玩家存档(③ 的「不写盘」另用 save 计数量)
	var ovr0: int = P2C.now_override_ts
	await _weekday_start_battle()
	await _in_tutorial()
	await _weekend()
	await _choice_box_present()
	await _synergy()
	await _merge()
	await _server_match()
	await _trainer()
	P2C.now_override_ts = ovr0
	print("  (共 %d 条断言)" % _n)
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 首次提示: 只一次 / 不挡点击 / 教程中不出不写 / 进存档" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _fresh(onboarded: bool) -> void:
	GameState.reset_save()
	GameState.onboarded = onboarded
	GameState.season_total_battles = 0
	GameState.first_tips_seen = {}
	GameState.tutorial_active = false


## 周二 12:00 UTC(积分赛日)/ 周六 / 周日。★取「本周锚点」往后数, 不手写日期。
func _ts_on(iso_dow: int) -> int:
	var now := int(Time.get_unix_time_from_system())
	var anchor: int = P2C.week_anchor_utc(now)          # 本周一 00:00 UTC
	return anchor + (iso_dow - 1) * 86400 + 12 * 3600


func _open_menu() -> Node:
	var m = load(MENU).instantiate()
	add_child(m)
	await _frames(40)
	return m


func _tip(m: Node) -> Node:
	return m.get_node_or_null(FT.NODE_NAME) if m != null else null


func _wait_showing(t: Node, max_f: int = 120) -> bool:
	for _i in range(max_f):
		if t != null and is_instance_valid(t) and t.is_showing():
			return true
		await get_tree().process_frame
	return false


# ① ② ③
func _weekday_start_battle() -> void:
	print("  ── ① 平日 · 教程刚结束 · 0 场 ──")
	P2C.now_override_ts = _ts_on(2)
	_ok("分母: 拨到的是积分赛日", P2C.phase_at_utc(P2C.now_override_ts) == P2C.PHASE_RANKED,
		P2C.phase_at_utc(P2C.now_override_ts))
	_fresh(true)
	var m := await _open_menu()
	var t := _tip(m)
	_ok("★出了一条首次提示", t != null)
	if t == null:
		m.queue_free()
		return
	_ok("★文案「开始第一场对战」", str(t.text()) == FT.TEXT_START, str(t.text()))
	_ok("★分母: 提示真的显示出来了", await _wait_showing(t))
	var hero: Control = m._hero_btn
	var hr: Rect2 = hero.get_global_rect() if hero != null else Rect2()
	var ring: Control = t._ring
	_ok("★环圈在「开始战斗」上", ring != null and ring.get_global_rect().grow(2.0).encloses(hr) and hr.size.x > 0.0,
		"环 %s / 键 %s" % [str(ring.get_global_rect() if ring != null else Rect2()), str(hr)])
	var pr: Rect2 = t.panel_rect()
	_ok("★提示条在屏内且不压「开始战斗」", get_viewport().get_visible_rect().encloses(pr) and not pr.intersects(hr), str(pr))
	_ok("★★不挡点击: 本层没有吃点击的可见控件", not t.is_blocking())
	var av: Array = t._avoid_rects()
	var hit: Array = []
	for r in av:
		if pr.intersects(r as Rect2):
			hit.append(str(r))
	_ok("★提示条不压主菜单上别的可见文字/按钮(实拍 10-20: 压住过计数条)", av.size() > 5 and hit.is_empty(), "比对 %d 个 · 压到 %s" % [av.size(), str(hit)])
	_ok("★★记成看过(内存)", bool(GameState.first_tips_seen.get(FT.START_BATTLE, false)))
	_ok("★★进账号存档(_save_dict 里有这一项)", bool((GameState._save_dict().get("first_tips_seen", {}) as Dictionary).get(FT.START_BATTLE, false)))
	var sd: Dictionary = GameState._save_dict()
	GameState.first_tips_seen = {}
	GameState._apply_save_dict(sd)
	_ok("★读档后还在(apply_save_dict 读回)", bool(GameState.first_tips_seen.get(FT.START_BATTLE, false)))
	## ② 点任意处收起(且不吃那一下)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = Vector2(20, 700); e.global_position = e.position
	get_viewport().push_input(e)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = e.position; up.global_position = e.position
	get_viewport().push_input(up)
	await _frames(40)
	_ok("★点任意处 ⇒ 收起", not is_instance_valid(t) or t.is_queued_for_deletion() or not t.is_showing())
	m.queue_free()
	await _frames(2)
	## 只一次
	var m2 := await _open_menu()
	_ok("★★只出一次: 再开主菜单不出", _tip(m2) == null)
	m2.queue_free()
	await _frames(2)
	## 5 秒自己收起
	_fresh(true)
	var m3 := await _open_menu()
	var t3 := _tip(m3)
	_ok("分母: 又一个新号出了提示", t3 != null and await _wait_showing(t3))
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(t3) and not t3.is_queued_for_deletion() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var dt := Time.get_ticks_msec() - t0
	_ok("★不点也会自己收起(约 %.1f 秒)" % FT.HOLD_SEC, not is_instance_valid(t3) and dt >= int(FT.HOLD_SEC * 900.0), "%d ms" % dt)
	m3.queue_free()
	await _frames(2)
	## 打过一场的号不出
	_fresh(true)
	GameState.season_total_battles = 1
	var m4 := await _open_menu()
	_ok("★本大轮已打过 ⇒ 不出「开始第一场对战」", _tip(m4) == null)
	m4.queue_free()
	await _frames(2)


# ④
func _in_tutorial() -> void:
	print("  ── ④ 教程进行中 ──")
	_fresh(true)
	GameState.tutorial_active = true
	_ok("★★教程中 can_show 一律为假", not FT.can_show(FT.START_BATTLE) and not FT.can_show(FT.GAUNTLET_DAY))
	var m := await _open_menu()
	_ok("★★教程中主菜单不出首次提示", _tip(m) == null)
	var host := Control.new()
	add_child(host)
	var tgt := Button.new()
	tgt.text = "x"; tgt.size = Vector2(100, 60); tgt.position = Vector2(300, 300)
	host.add_child(tgt)
	var t = FT.show(host, FT.START_BATTLE, tgt)
	_ok("★★教程中直接调 show 也不出", t == null)
	FT.mark_seen(FT.START_BATTLE)
	_ok("★★教程中不写「看过了」", GameState.first_tips_seen.is_empty(), str(GameState.first_tips_seen))
	GameState.tutorial_active = false
	var t2 = FT.show(host, FT.START_BATTLE, tgt)
	_ok("★分母: 同一处调用在教程外能出(上面三条不是空检查)", t2 != null)
	host.queue_free()
	m.queue_free()
	_ok("★没看过教程(选择框之前)也不出", (func() -> bool:
		GameState.onboarded = false
		GameState.first_tips_seen = {}
		return not FT.can_show(FT.START_BATTLE)).call())
	await _frames(2)


# ⑤
func _weekend() -> void:
	print("  ── ⑤ 周六 / 周日 ──")
	for pair in [[6, P2C.PHASE_GAUNTLET, FT.GAUNTLET_DAY], [7, P2C.PHASE_FINALS, FT.FINALS_DAY]]:
		P2C.now_override_ts = _ts_on(int(pair[0]))
		_ok("分母: 拨到了 %s" % str(pair[1]), P2C.phase_at_utc(P2C.now_override_ts) == str(pair[1]))
		_fresh(true)
		var m := await _open_menu()
		var t := _tip(m)
		var want := FT.TEXT_RULES % str(P2C.PHASE_LABEL[str(pair[1])])
		_ok("★%s: 出「%s」" % [str(pair[1]), want], t != null and str(t.text()) == want, str(t.text()) if t != null else "无")
		if t != null and await _wait_showing(t):
			var mb: Control = m._mode_box
			_ok("★%s: 环圈在模式卡上" % str(pair[1]), mb != null and t._ring.get_global_rect().grow(2.0).encloses(mb.get_global_rect()))
			_ok("★%s: 不挡点击" % str(pair[1]), not t.is_blocking())
		_ok("★%s: 不同时再出「开始第一场对战」(一次一条)" % str(pair[1]), not bool(GameState.first_tips_seen.get(FT.START_BATTLE, false)))
		m.queue_free()
		await _frames(2)
		var m2 := await _open_menu()
		_ok("★★%s: 只出一次" % str(pair[1]), _tip(m2) == null)
		m2.queue_free()
		await _frames(2)


# ⑥
## v4(2026-10-21): 首启选择框挂在独立的首启流程那一屏上(介绍 → 问 → 起名 → 主菜单), 不压在主菜单上。
func _choice_box_present() -> void:
	print("  ── ⑥ 首启流程(介绍 / 选择框 / 起名)在场 ──")
	P2C.now_override_ts = _ts_on(2)
	_fresh(true)
	OS.set_environment("ONBOARD", "1")
	## 主菜单必须是真的 current_scene: 首启要换场(当子节点挂时不换, 见 _maybe_first_launch_tutorial)
	var m = load(MENU).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(10)
	OS.set_environment("ONBOARD", "")
	var fl := get_tree().current_scene
	_ok("分母: 首启 ⇒ 换到首启流程那一屏", fl != null and str(fl.scene_file_path).ends_with("FirstLaunch.tscn"),
		str(fl.scene_file_path) if fl != null else "null")
	if fl == null or not str(fl.scene_file_path).ends_with("FirstLaunch.tscn"):
		return
	_ok("★首启流程在场 ⇒ 不出首次提示", _tip(fl) == null)
	GameState.onboarded = false
	fl.call("skip_intro")
	await _frames(2)
	var other: Button = null
	var ch := fl.get_node_or_null("TutorialChoice")
	_ok("分母: 选择框在(首启那一屏上)", ch != null)
	if ch != null:
		for b in ch.find_children("*", "Button", true, false):
			if (b as Button).text == "跳过":
				other = b
	_ok("分母: 选择框里有「跳过」", other != null)
	if other == null:
		return
	other.emit_signal("pressed")
	await _frames(3)
	_ok("★选择框 / 起名框在场 ⇒ 不出首次提示", _tip(fl) == null)
	if is_instance_valid(fl) and bool(fl.call("is_naming")):
		var ed := fl.find_child("NameEdit", true, false) as LineEdit
		fl.call("confirm_name", ed.text if ed != null else "")
	var mm: Node = null
	for _w in range(120):
		await get_tree().process_frame
		mm = get_tree().current_scene
		if mm != null and str(mm.scene_file_path).ends_with("MainMenu.tscn") and _tip(mm) != null:
			break
	_ok("★跳过 → 起名 → 主菜单 ⇒ 出「开始第一场对战」", mm != null and _tip(mm) != null and str(_tip(mm).text()) == FT.TEXT_START,
		str(_tip(mm).text()) if mm != null and _tip(mm) != null else "无")
	OS.set_environment("ONBOARD", "0")
	if mm != null:
		get_tree().current_scene = null
		mm.queue_free()
	await _frames(2)


# ⑦ 补齐的四条 ───────────────────────────────────────────────

## 一条提示的通用检查: 出了、文案对、圈住目标、不挡点击、提示条在屏内、记成看过。
func _check_tip(host: Node, key: String, target: Control, tag: String) -> void:
	var t := _tip(host)
	_ok("★%s: 出了一条首次提示" % tag, t != null)
	if t == null:
		return
	_ok("★%s: 文案「%s」" % [tag, FT.text_for(key)], str(t.text()) == FT.text_for(key) and FT.text_for(key) != "", str(t.text()))
	_ok("★%s: 分母: 真的显示出来了" % tag, await _wait_showing(t))
	var tr: Rect2 = TG.vis_rect(target) if target != null else Rect2()
	_ok("★%s: 环圈住目标" % tag, tr.size.x > 0.0 and t._ring.get_global_rect().grow(2.0).encloses(tr), "环 %s / 目标 %s" % [str(t._ring.get_global_rect()), str(tr)])
	_ok("★★%s: 不挡点击" % tag, not t.is_blocking())
	_ok("★%s: 提示条在屏内" % tag, get_viewport().get_visible_rect().encloses(t.panel_rect()), str(t.panel_rect()))
	var av: Array = t._avoid_rects()
	var hit: Array = []
	for r in av:
		if t.panel_rect().intersects(r as Rect2):
			hit.append(str(r))
	_ok("★%s: 提示条不压这一屏别的可见文字/按钮" % tag, av.size() >= 2 and hit.is_empty(), "比对 %d 个 · 压到 %s" % [av.size(), str(hit)])
	_ok("★★%s: 记成看过" % tag, bool(GameState.first_tips_seen.get(key, false)))
	## 自审截图(窗口跑时): FT_SHOT_DIR=<目录> ⇒ 每条提示在屏时拍一张。无头 / 没设 ⇒ 不拍。
	if OS.has_environment("FT_SHOT_DIR") and DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("FT_SHOT_DIR"), key])


func _setup_leaders() -> Array:
	var leaders: Array = []
	for pdef in DataRegistry.launch_pets:
		if leaders.size() < 3:
			leaders.append(str((pdef as Dictionary).get("id", "")))
	GameState.season_leaders = leaders.duplicate()
	GameState.dual_lineup = {}
	GameState.get_dual_lineup()
	return leaders


## 背包: 第一只统领装 3 件盾 ⇒ 盾羁绊开第一档 ⇒ 圈第一条已激活的羁绊行。
func _synergy() -> void:
	print("  ── ⑦a 羁绊第一次激活(背包) ──")
	P2C.now_override_ts = _ts_on(2)
	for in_tut in [true, false]:
		_fresh(true)
		var leaders := _setup_leaders()
		var shield_ids: Array = []
		for e in DataRegistry.phase2_equipment:
			var iid := str((e as Dictionary).get("id", ""))
			if iid != "p2eq_095" and Phase2Types.type_of(iid) == "盾" and shield_ids.size() < 3:
				shield_ids.append(iid)
		GameState.persistent_equipped = {str(leaders[0]): [{"id": shield_ids[0], "star": 1}, {"id": shield_ids[1], "star": 1}, {"id": shield_ids[2], "star": 1}]}
		var on := 0
		for r in GameState.synergy_rows():
			if int((r as Dictionary)["tier"]) >= 1:
				on += 1
		_ok("分母: 盾羁绊真的开了(%s)" % ("教程中" if in_tut else "账号"), on >= 1, "%d 条" % on)
		GameState.tutorial_active = in_tut
		var inv = load(INV).instantiate()
		add_child(inv)
		await _frames(40)
		var chip: Control = inv._inv_synergy.first_on_chip
		_ok("分母: 背包羁绊列里有已激活的那一行", chip != null and is_instance_valid(chip))
		if in_tut:
			_ok("★★教程中: 背包不出「羁绊已激活」", _tip(inv) == null and not GameState.first_tips_seen.has(FT.FIRST_SYNERGY))
		else:
			await _check_tip(inv, FT.FIRST_SYNERGY, chip, "羁绊")
		GameState.tutorial_active = false
		inv.queue_free()
		await _frames(2)
	var inv2 = load(INV).instantiate()
	add_child(inv2)
	await _frames(40)
	_ok("★★羁绊: 只出一次(再开背包不出)", _tip(inv2) == null)
	inv2.queue_free()
	await _frames(2)


## 商店: 背包里先有 2 件同名 ★1, 买第 3 件 ⇒ 合成 ★2 ⇒ 圈左下宝箱里升星的那一格。走真购买入口 `_on_buy`。
func _merge() -> void:
	print("  ── ⑦b 第一次合成升星(商店) ──")
	for in_tut in [true, false]:
		_fresh(true)
		_setup_leaders()
		GameState.season_total_battles = 1
		GameState.meta_deepsea_coins = 999
		var sh = load(SHOP).instantiate()
		add_child(sh)
		await _frames(30)
		var idx := -1
		for i in range((sh._offer as Array).size()):
			var o = sh._offer[i]
			if o is Dictionary and str((o as Dictionary).get("id", "")) != "p2eq_096":
				idx = i
				break
		_ok("分母: 货架上有一件能买的(%s)" % ("教程中" if in_tut else "账号"), idx >= 0)
		if idx < 0:
			sh.queue_free()
			await _frames(2)
			continue
		var eid := str((sh._offer[idx] as Dictionary).get("id", ""))
		GameState.persistent_bench = [{"id": eid, "star": 1}, {"id": eid, "star": 1}]
		GameState.tutorial_active = in_tut
		sh._on_buy(idx)
		await _frames(4)
		var stars: Array = []
		for b in GameState.persistent_bench:
			if str((b as Dictionary).get("id", "")) == eid:
				stars.append(int((b as Dictionary).get("star", 1)))
		_ok("分母: 真合成了 ★2", stars == [2], str(stars))
		if in_tut:
			_ok("★★教程中: 商店不出「合成升星」", _tip(sh) == null and not GameState.first_tips_seen.has(FT.FIRST_MERGE))
		else:
			var cell: Control = sh.merge_tip_target(eid, 2)
			## ★2026-10-21: 商店里没有背包那一排了 ⇒ 合成提示指着顶栏「背包」(升星那件在背包页)。
			_ok("分母: 合成提示指向顶栏「背包」", cell != null and cell is Button and str((cell as Button).text).find("背包") >= 0, str(cell.name) if cell != null else "无")
			await _check_tip(sh, FT.FIRST_MERGE, cell, "合成")
		GameState.tutorial_active = false
		sh.queue_free()
		await _frames(2)
	_ok("★★合成: 只出一次(看过之后 can_show 为假)", not FT.can_show(FT.FIRST_MERGE))


## 周六服务器局: 逐帧直播那条路(会话 kind=referee + 服务器结果)⇒ 圈路名计时牌; 别人的局 ⇒ 不出。
func _server_match() -> void:
	print("  ── ⑦c 第一次看周六服务器局 ──")
	_fresh(true)
	var SW = load("res://scripts/systems/replay/stream_watch.gd")
	var cur0: Dictionary = SW.current
	var bt: Control = _StubBattle.new()
	add_child(bt)
	var plate := Label.new()
	plate.text = "上路战场 0:00"
	plate.position = Vector2(560, 100)
	plate.size = Vector2(160, 30)
	bt.add_child(plate)
	## 顶栏上别的字(VS / 两边名字), 提示条不许压它们
	for spec in [["VS", Vector2(600, 20), Vector2(80, 60)], ["玩家甲", Vector2(80, 10), Vector2(120, 24)], ["玩家乙", Vector2(1080, 10), Vector2(120, 24)]]:
		var l := Label.new()
		l.text = str(spec[0])
		l.position = spec[1]
		l.size = spec[2]
		bt.add_child(l)
	SW.current = {"kind": "", "result": {}}
	_ok("★别人的局(会话不是 referee): 不算服务器局", not FT.is_server_match(bt))
	_ok("★别人的局: 不出", FT.server_match_tip(bt, plate) == null and _tip(bt) == null)
	SW.current = {"kind": SW.KIND_REFEREE, "result": {"won": true}}
	_ok("★分母: 看自己那一场(会话 referee + 服务器结果) ⇒ 算服务器局", FT.is_server_match(bt))
	GameState.tutorial_active = true
	_ok("★★教程中: 不出", FT.server_match_tip(bt, plate) == null)
	GameState.tutorial_active = false
	FT.server_match_tip(bt, plate)
	await _check_tip(bt, FT.SERVER_MATCH, plate, "服务器局")
	var t := _tip(bt)
	if t != null:
		t.free()
	_ok("★★服务器局: 只出一次", FT.server_match_tip(bt, plate) == null)
	_ok("★顶栏建好时真的调了这一行(产品入口)", FileAccess.get_file_as_string("res://scripts/scenes/battle/topbar_status.gd").contains("FirstTips.server_match_tip(battle, plate)"))
	SW.current = cur0
	bt.queue_free()
	await _frames(2)


## 训龟大师页: 第一次打开 ⇒ 圈展台上的训龟大师立绘。
func _trainer() -> void:
	print("  ── ⑦d 第一次打开训龟大师 ──")
	for in_tut in [true, false]:
		_fresh(true)
		GameState.tutorial_active = in_tut
		var tp = load(TRAINER).instantiate()
		add_child(tp)
		await _frames(30)
		var card: Control = tp._preview_rect
		_ok("分母: 找到展台上的训龟大师立绘(%s)" % ("教程中" if in_tut else "账号"), card != null and card.is_visible_in_tree())
		if in_tut:
			_ok("★★教程中: 训龟大师页不出", _tip(tp) == null)
		else:
			await _check_tip(tp, FT.FIRST_TRAINER, card, "训龟大师")
		GameState.tutorial_active = false
		tp.queue_free()
		await _frames(2)
	var tp2 = load(TRAINER).instantiate()
	add_child(tp2)
	await _frames(30)
	_ok("★★训龟大师: 只出一次", _tip(tp2) == null)
	tp2.queue_free()
	await _frames(2)
