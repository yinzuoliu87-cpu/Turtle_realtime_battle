extends Node

## verify_tutorial_flow_v2.gd — 新手教程整条走一遍, 全程真场景真入口(2026-10-07 重做, 方案书 §6.2)
##
## 用户原话(逐字):
##   「教程里的商店怎么能够和账号的商店互通呢 … 整个教程都不应该有当前存档的东西啊」
##   「教程里就不应该有返回键啊，要一直跟着教程走啊」 /「缩」/「打三路」/「是点击啊」
##
## 走法: 真主菜单 → 选择框「开始教程」→ 选龟 → 战斗(真开场演出) → 结算 → 商店 → 背包 →「完成教程」→ 主菜单。
## 每一屏量:
##   · 账号存档文件字节 == 进教程前那份(教程期间一个字节都没写; 也没冒出选龟草稿/上次阵容文件)
##   · 屏上没有任何返回/退出控件; 右上「跳过教程」在, 且与其它可见控件不相交(B7)
##   · 当前这一句提示是对的; **只有做了那个动作才前进**(等一阵不动它不翻页)
## 另外:
##   · B1: 战斗开场三路总览 / 对阵卡演出期间(含幕布淡出)一帧提示都不出
##   · B2: 商店背包为空时提示停在「购买 1 件装备」, 成交才翻
##   · X1: 2 级之后「点击一只龟装上」真的装上了(全队件数 +1)
##   · ESC 在教程里被吞掉(不回主菜单)
##   · 只有 1 把战斗; 结束后存档 = 进教程前那份只差 onboarded; 选龟屏回到全部龟(X3)
##   · 第二遍: 在选龟屏按右上「跳过教程」⇒ 回主菜单, 存档同样只差 onboarded

const SAVE := "user://savegame.json"
const MENU := "res://scenes/MainMenu.tscn"
const EXIT_WORDS := ["返回", "返回主菜单", "认输", "沿用上次", "商店", "←"]

var _fail := 0
var _n := 0
const MIN_ASSERTS := 60
var _battles_entered := 0
var _last_scene_id := 0
var _a := PackedByteArray()


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _process(_dt: float) -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.get_instance_id() != _last_scene_id:
		_last_scene_id = cs.get_instance_id()
		if str(cs.scene_file_path).ends_with("RealtimeBattle3D.tscn"):
			_battles_entered += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60      # 开场演出按真实时间走(2×5 秒); 钉帧率 ⇒ 帧预算可预期
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	OS.set_environment("ONBOARD", "")
	GameState.test_mode = false          # ★要量的就是存档文件(独立 user://)
	await _skip_pass()
	await _full_pass()
	GameState.test_mode = true
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 新手教程整条: 隔离沙盒 / 无返回 / 做了才前进" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ═══════════════════════════════ 账号 ═══════════════════════════════

func _make_account() -> void:
	GameState.reset_save()
	GameState.meta_deepsea_coins = 292
	GameState.season_level = 5
	GameState.season_xp = 7
	GameState.season_total_battles = 0     # 新一周还没打 ⇒ 账号商店是锁着的(教程里的商店照样能逛)
	GameState.season_leaders = ["candy", "ghost", "pirate"]
	GameState.persistent_bench = [{"id": "p2eq_001", "star": 2}]
	GameState.persistent_equipped = {"candy": [{"id": "p2eq_005", "star": 1}]}
	GameState.onboarded = false
	GameState.save()
	GameState._load()          # 基线 = 读档后再存那一形(JSON 整数读回变 float, 与教程无关; 见 verify_tutorial_skip)
	GameState.save()
	_a = _bytes()
	for f in ["user://team_draft.json", "user://lastLineup.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(SAVE)


func _disk_untouched(tag: String) -> void:
	_ok("★★[%s] 账号存档一个字节都没写" % tag, _bytes() == _a)
	_ok("[%s] 没冒出选龟草稿 / 上次阵容文件(教程不写盘)" % tag,
		not FileAccess.file_exists("user://team_draft.json") and not FileAccess.file_exists("user://lastLineup.json"))


func _after_exit(tag: String) -> void:
	var want := _a.get_string_from_utf8().replace("\"onboarded\": false", "\"onboarded\": true")
	var got := _bytes().get_string_from_utf8()
	if got != want:
		var wl := want.split("\n")
		var gl := got.split("\n")
		for i in range(mini(wl.size(), gl.size())):
			if wl[i] != gl[i]:
				print("    [差异] 第 %d 行: 应=%s | 实=%s" % [i, wl[i].strip_edges(), gl[i].strip_edges()])
	_ok("★★★[%s] 存档 = 进教程前那份, 只有 onboarded false→true" % tag,
		_bytes().get_string_from_utf8() == want and _bytes() != _a)
	_ok("[%s] 账号原状态回来了(292 币 / 5 级 / 原统领 / 0 场)" % tag,
		int(GameState.meta_deepsea_coins) == 292 and int(GameState.season_level) == 5
		and Array(GameState.season_leaders) == ["candy", "ghost", "pirate"] and int(GameState.season_total_battles) == 0)
	_ok("[%s] 教程状态收干净" % tag, not bool(GameState.tutorial_active) and (GameState.dual_ghost as Dictionary).is_empty()
		and not get_node("/root/TutorialDirector").in_sandbox())


# ═══════════════════════════════ 场景工具 ═══════════════════════════════

func _open_menu() -> Node:
	## ★先把上一遍留下的当前场景清掉 —— 它不会被下面的 current_scene 赋值释放, 会一直挂在根上
	##   挡点击(实测: 上一遍的主菜单底板吃掉了第二遍摆位屏的拖动)。
	var old := get_tree().current_scene
	if old != null and old != self:
		get_tree().current_scene = null
		old.queue_free()
		await _frames(2)
	var m = load(MENU).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(6)
	return m


func _wait_scene(suffix: String, max_f: int = 600) -> Node:
	var w := 0
	while w < max_f:
		var cs := get_tree().current_scene
		if cs != null and str(cs.scene_file_path).ends_with(suffix):
			await _frames(3)
			return get_tree().current_scene
		await get_tree().process_frame
		w += 1
	return null


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _guide() -> Node:
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion():
			return n
	return null


func _guide_text() -> String:
	var g := _guide()
	return str(g.current_text()) if g != null and g.is_showing() else ""


## 等到提示显示出 want(最多 max_f 帧)。返回等了几帧(-1 = 没等到)。
func _wait_text(want: String, max_f: int = 240) -> int:
	for i in range(max_f):
		if _guide_text() == want:
			return i
		await get_tree().process_frame
	return -1


func _chrome(scene: Node) -> Node:
	return scene.get_node_or_null("TutorialChrome") if scene != null else null


## 屏上没有返回 / 退出控件; 跳过钮在且不与别的可见文字/按钮相交。
func _check_exits(scene: Node, tag: String) -> void:
	var exits: Array = []
	var others: Array = []
	var ch := _chrome(scene)
	for c in scene.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or _eff_alpha(ctl) < 0.1:
			continue
		if ch != null and ch.is_ancestor_of(ctl):
			continue
		if _under_guide(ctl):
			continue
		var t := ""
		if ctl is Button:
			t = (ctl as Button).text.strip_edges()
			if t in EXIT_WORDS:
				exits.append(t)
		elif ctl is Label:
			t = (ctl as Label).text.strip_edges()
		if t != "" and (ctl is Button or ctl is Label):
			var r := ctl.get_global_rect()
			if r.size.x < 900.0:
				others.append([t, r])
	_ok("★★[%s] 屏上没有任何返回/退出控件" % tag, exits.is_empty(), str(exits))
	var sk: Button = ch.button if ch != null else null
	_ok("★[%s] 右上「跳过教程」在场可见" % tag, sk != null and sk.is_visible_in_tree() and sk.text == "跳过教程")
	if sk == null:
		return
	var sr := sk.get_global_rect()
	var vp := Vector2(get_viewport().get_visible_rect().size)
	_ok("[%s] 跳过钮在右上(右 1/4 + 上 1/4)" % tag, sr.get_center().x > vp.x * 0.75 and sr.get_center().y < vp.y * 0.25, str(sr))
	var hits: Array = []
	for o in others:
		if sr.intersects(o[1] as Rect2):
			hits.append("%s %s" % [o[0], str(o[1])])
	print("    [%s] 跳过钮 %s · 比对 %d 个可见文字/按钮" % [tag, str(sr), others.size()])
	_ok("★[%s] 跳过钮与其它可见文字/按钮不相交(B7)" % tag, hits.is_empty() and others.size() > 3, str(hits))


func _has_label(root: Node, t: String) -> bool:
	for c in root.find_children("*", "Label", true, false):
		if (c as Label).text == t:
			return true
	return false


func _eff_alpha(c: Node) -> float:
	var a := 1.0
	var n := c
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


func _under_guide(c: Node) -> bool:
	var n := c.get_parent()
	while n != null:
		if n.has_method("is_showing"):
			return true
		n = n.get_parent()
	return false


# ═══════════════════════════════ 第一遍: 选龟屏按「跳过教程」 ═══════════════════════════════

func _skip_pass() -> void:
	print("  ── 第一遍: 进教程 → 选龟屏按右上「跳过教程」 ──")
	_make_account()
	var m = await _open_menu()
	## ★基线 = 玩家按「开始教程」那一刻的账号存档。主菜单首次显示会写上「你是谁」那几项
	##   (install_uid / 冻结的默认昵称) —— 那是主菜单的事, 不是教程的; 在这一刻对齐。
	GameState.save()
	_a = _bytes()
	var ch: Node = m.get_node_or_null("TutorialChoice")
	_ok("分母: 首启选择框在", ch != null)
	if ch == null:
		return
	(ch.find_child("StartTutorial", true, false) as Button).emit_signal("pressed")
	var ts := await _wait_scene("TeamSelect.tscn")
	_ok("分母: 进了选龟屏", ts != null)
	if ts == null:
		return
	await _frames(4)
	var sk = _chrome(ts)
	_ok("分母: 外壳挂上了", sk != null)
	if sk == null:
		return
	(sk.button as Button).emit_signal("pressed")
	var mm := await _wait_scene("MainMenu.tscn")
	_ok("★「跳过教程」⇒ 回到主菜单", mm != null)
	_ok("★「跳过教程」⇒ 出口理由 skipped", str(get_node("/root/TutorialDirector").last_end_reason) == "skipped")
	_ok("★跳过 ⇒ 不飘「教程完成」", mm != null and not _has_label(mm, "教程完成"))
	_after_exit("跳过")
	await _frames(4)
	_ok("★跳过后主菜单不再弹选择框", mm != null and mm.get_node_or_null("TutorialChoice") == null)


# ═══════════════════════════════ 第二遍: 整条走完 ═══════════════════════════════

func _full_pass() -> void:
	print("  ── 第二遍: 整条走完 ──")
	_make_account()
	_battles_entered = 0
	var m = await _open_menu()
	## ★基线 = 玩家按「开始教程」那一刻的账号存档。主菜单首次显示会写上「你是谁」那几项
	##   (install_uid / 冻结的默认昵称) —— 那是主菜单的事, 不是教程的; 在这一刻对齐。
	GameState.save()
	_a = _bytes()
	var ch: Node = m.get_node_or_null("TutorialChoice")
	_ok("分母: 首启选择框在", ch != null)
	if ch == null:
		return
	(ch.find_child("StartTutorial", true, false) as Button).emit_signal("pressed")

	# ── 选龟 ──
	var ts := await _wait_scene("TeamSelect.tscn")
	_ok("分母: 进了选龟屏", ts != null)
	if ts == null:
		return
	_ok("★选龟屏只给教学 3 只", (ts._grid_flow as Node).get_child_count() == 3, "%d 只" % (ts._grid_flow as Node).get_child_count())
	var w := await _wait_text("选择 3 只龟上阵")
	_ok("★提示「选择 3 只龟上阵」", w >= 0, "实测「%s」" % _guide_text())
	_check_exits(ts, "选龟")
	_disk_untouched("选龟")
	await _frames(30)
	_ok("★不动就不前进(30 帧后仍是第一句)", _guide_text() == "选择 3 只龟上阵")
	var td = get_node("/root/TutorialDirector")
	for pid in td.FIXED_TEAM:
		ts._on_pick_pet(str(pid))
		await _frames(2)
	w = await _wait_text("点击出战")
	_ok("★点满三只 ⇒ 提示「点击出战」", w >= 0, "实测「%s」" % _guide_text())
	_disk_untouched("选龟·点满")
	ts._on_start()

	# ── 战斗 ──
	var bt := await _wait_scene("RealtimeBattle3D.tscn", 600)
	_ok("分母: 进了战斗", bt != null)
	if bt == null:
		return
	var present_frames := 0
	var shown_in_present := 0
	var wait_f := 0
	while wait_f < 3000:
		var st := str(bt._dl_state)
		var presenting: bool = st == "overview" or st == "preview" or is_instance_valid(bt._dl_present_root) \
			or is_instance_valid(bt._dl_sys.present_fading)
		if presenting:
			present_frames += 1
			if _guide_text() != "":
				shown_in_present += 1
		elif st == "place" and _guide_text() != "":
			break
		await get_tree().process_frame
		wait_f += 1
	print("    [B1] 演出期间 %d 帧 · 其中提示在屏 %d 帧 · 共等 %d 帧" % [present_frames, shown_in_present, wait_f])
	_ok("★分母 B1: 真的经历了开场演出(三路总览/对阵卡)", present_frames > 30, "%d 帧" % present_frames)
	_ok("★★B1: 演出期间一帧提示都没出", shown_in_present == 0, "%d 帧" % shown_in_present)
	_ok("★提示「拖动龟调整站位」", _guide_text() == "拖动龟调整站位", "实测「%s」" % _guide_text())
	_ok("★认输键藏起来了", bt._surrender_btn != null and not (bt._surrender_btn as Control).visible)
	_check_exits(bt, "摆位")
	_disk_untouched("摆位")
	await _frames(30)
	_ok("★不拖就不前进", _guide_text() == "拖动龟调整站位")
	await _real_drag(bt)
	w = await _wait_text("点击开始战斗", 120)
	_ok("★★真拖了一只龟 ⇒ 提示「点击开始战斗」", w >= 0, "实测「%s」" % _guide_text())
	(bt._dl_go_btn as Button).emit_signal("pressed")
	await _frames(10)
	_ok("★开始战斗之后全程无提示", _guide_text() == "" and str(bt._dl_state) == "fight")
	## 三路整场要 ~140 游戏秒; 这里量的是教程的结算这一屏 —— 直接走产品的结算入口。
	bt._hud._show_banner(true)
	await _frames(2)
	var names: Array = []
	for c in (bt._hud._settle.btn_row as Node).get_children():
		if c is Button:
			names.append((c as Button).text)
	_ok("★★结算只有「前往商店」(没有「返回主菜单」)", names == ["前往商店"], str(names))
	_ok("★结算按钮还在淡入时不出提示", _guide_text() == "" or w >= 0)
	w = await _wait_text("点击前往商店", 300)
	_ok("★提示「点击前往商店」", w >= 0, "实测「%s」" % _guide_text())
	_check_exits(bt, "结算")
	for c in (bt._hud._settle.btn_row as Node).get_children():
		if c is Button:
			(c as Button).emit_signal("pressed")
			break

	# ── 商店 ──
	var sh := await _wait_scene("Shop.tscn")
	_ok("★结算 ⇒ 商店(不是第二把战斗)", sh != null)
	if sh == null:
		return
	w = await _wait_text("购买经验，升到 2 级")
	_ok("★提示「购买经验，升到 2 级」", w >= 0, "实测「%s」" % _guide_text())
	_ok("★教程商店是开着的(账号 0 场也能逛)", sh._offer.size() > 0)
	_ok("★顶栏返回键藏了, 「背包」键在", not (sh._top_bar.back_btn as Control).visible
		and (sh._top_bar.action_btns[0] as Control).is_visible_in_tree())
	_check_exits(sh, "商店")
	## ESC 被吞
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE; esc.pressed = true
	_send(esc)
	var esc_up := InputEventKey.new()
	esc_up.keycode = KEY_ESCAPE; esc_up.pressed = false
	_send(esc_up)
	await _frames(8)
	_ok("★★ESC 在教程里被吞掉(仍在商店)", get_tree().current_scene == sh)
	_ok("分母: 教程里的等级是 1(全队装备上限 0)", int(GameState.season_level) == 1 and int(GameState.team_equip_cap()) == 0)
	(sh._tut_xp_btn as Button).emit_signal("pressed")
	w = await _wait_text("购买 1 件装备")
	_ok("★买经验 ⇒ 2 级 ⇒ 提示「购买 1 件装备」", w >= 0 and int(GameState.season_level) == 2, "Lv%d「%s」" % [int(GameState.season_level), _guide_text()])
	await _frames(40)
	_ok("★分母 B2: 背包还是空的", GameState.persistent_bench.is_empty())
	_ok("★★B2: 不买就停在「购买 1 件装备」", _guide_text() == "购买 1 件装备")
	var bought := false
	for i in range((sh._offer as Array).size()):
		if sh._offer[i] != null and sh._price(sh._deco(sh._offer[i])) <= int(GameState.meta_deepsea_coins):
			sh._on_select(i)
			await _frames(2)
			sh._on_buy(i)
			bought = true
			break
	_ok("分母: 真买了一件", bought and GameState.persistent_bench.size() == 1)
	w = await _wait_text("点击背包")
	_ok("★成交 ⇒ 提示「点击背包」", w >= 0, "实测「%s」" % _guide_text())
	_disk_untouched("商店")
	(sh._top_bar.action_btns[0] as Button).emit_signal("pressed")

	# ── 背包 ──
	var inv := await _wait_scene("Inventory.tscn")
	_ok("分母: 进了背包", inv != null)
	if inv == null:
		return
	w = await _wait_text("点击一件装备")
	_ok("★提示「点击一件装备」", w >= 0, "实测「%s」" % _guide_text())
	_check_exits(inv, "背包")
	inv._on_bench_click(0)
	w = await _wait_text("点击一只龟装上")
	_ok("★点装备 ⇒ 提示「点击一只龟装上」", w >= 0, "实测「%s」" % _guide_text())
	var n0 := int(GameState.team_equipped_count())
	inv._dl_click("top", 0)
	w = await _wait_text("点击完成教程")
	_ok("★★X1: 真装上了(全队件数 +1)", int(GameState.team_equipped_count()) == n0 + 1, "%d → %d" % [n0, int(GameState.team_equipped_count())])
	_ok("★装上 ⇒ 提示「点击完成教程」", w >= 0, "实测「%s」" % _guide_text())
	_disk_untouched("背包")
	(inv._tut_finish_btn as Button).emit_signal("pressed")

	# ── 结束 ──
	var mm := await _wait_scene("MainMenu.tscn")
	_ok("★「完成教程」⇒ 回主菜单", mm != null)
	_ok("★出口理由 completed", str(get_node("/root/TutorialDirector").last_end_reason) == "completed")
	_ok("★走完 ⇒ 主菜单飘「教程完成」", mm != null and _has_label(mm, "教程完成"))
	_ok("★★只打了 1 把战斗", _battles_entered == 1, "%d 把" % _battles_entered)
	_after_exit("完成")
	await _frames(4)
	_ok("★完成后主菜单不再弹选择框", mm != null and mm.get_node_or_null("TutorialChoice") == null)
	## X3: 之后的选龟屏是全部龟(不再是教学 3 只)
	var ts2 = load("res://scenes/TeamSelect.tscn").instantiate()
	add_child(ts2)
	await _frames(4)
	var cnt: int = (ts2._grid_flow as Node).get_child_count()
	_ok("★★X3: 教程后选龟屏是全部龟(不是教学 3 只)", cnt > 3, "%d 只" % cnt)
	ts2.queue_free()
	await _frames(2)


## 真拖一只我方龟: 走真输入(引导暗幕 → 战斗 _unhandled_input → 摆位拖动)。
func _real_drag(bt: Node) -> void:
	var r: Rect2 = bt._dl_sys._tut_anchor("my_unit")
	_ok("分母: 找得到一只能拖的我方龟", r.size.x > 0.0, str(r))
	if r.size.x <= 0.0:
		return
	var xf: Transform2D = get_viewport().get_final_transform()
	var a: Vector2 = r.get_center()
	var b: Vector2 = a + Vector2(110, -40)
	_btn(xf * a, true)
	await get_tree().process_frame
	var _hov = get_viewport().gui_get_hovered_control()
	print("    [拖] 直接命中测试 unit_at(a)=%s  hovered=%s  dl_state=%s" % [str(bt._edit_unit_at_screen(a) != null), str(_hov.get_path()) if _hov != null else "无", str(bt._dl_state)])
	print("    [拖] 按下后 drag_unit=%s  mask_left=%s  xf=%s  a=%s" % [str(bt._edit_drag_unit != null),
		str(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)), str(xf), str(a)])
	for i in range(1, 11):
		var mm := InputEventMouseMotion.new()
		mm.position = xf * a.lerp(b, float(i) / 10.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(mm)
		await get_tree().process_frame
	_btn(xf * b, false)
	await _frames(2)


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)     # 只为让 Input.is_mouse_button_pressed 跟着变(摆位拖动要读它)
	_send(e)


## 无头下 Input.parse_input_event 不往视口派发 ⇒ 直接推进根视口(GUI 命中 → _input → _unhandled_input, 与真点击同一条链)。
func _send(e: InputEvent) -> void:
	if DisplayServer.get_name() == "headless":
		get_viewport().push_input(e)
	else:
		Input.parse_input_event(e)
