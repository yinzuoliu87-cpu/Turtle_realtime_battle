extends Node

## verify_tutorial_flow_v3.gd — 新手教程 v3 整条走一遍, 全程真场景真入口
##   (方案书 docs/plans/20261020-教程重写.md §1 / §2 / 验收清单第 2 条; 取代 verify_tutorial_flow_v2)
##
## 用户原话(逐字):
##   「教程里的商店怎么能够和账号的商店互通呢 … 整个教程都不应该有当前存档的东西啊」(10-07)
##   「教程里就不应该有返回键啊，要一直跟着教程走啊」 /「缩」/「打三路」/「是点击啊」(10-07)
##   「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」(10-19) ⇒ 教程要教「站位」在哪
##
## 走法: 真主菜单 → 选择框「开始教程」→ 选龟 → 战斗(真开场演出 + 两句不阻塞提示) → 结算 → 商店(经验 / 点卡 / 购买 / 背包)
##       → 背包(点装备 / 点龟 / 真点「站位」/ 真拖一只龟 / 真点「完成」/ 真点「完成教程」) → 主菜单。
## 每一屏量:
##   · 账号存档文件字节 == 进教程前那份(教程期间一个字节都没写)
##   · 屏上没有任何返回/退出控件; 右上「跳过教程」在, 且与其它可见控件不相交(B7)
##   · 当前这一句提示是对的; **只有做了那个动作才前进**
## v3 新增:
##   · 战斗: 演出期间一帧提示都不出(B1); 开打后两句提示依次出现, **不挡点击**(本层无吃点击的控件),
##     提示条不压战斗 HUD 的任何可见控件(R2), 到点自己淡出
##   · 商店: 「点击一件装备」点卡才翻、「点击购买」成交才翻(原来一步里藏着两下点击)
##   · 站位: 教程里顶栏「站位」在; **真鼠标事件**拖一只龟 ⇒ 沙盒里的阵容改了, 而**存档文件一个字节都没变**
##   · ★★教程期间对服务器的写请求 = 0(假传输记下每一条真发出去的请求; 分母: 教程外同一入口确实发得出写请求)
##   · 第二遍: 选龟屏按「跳过教程」⇒ 存档只差 onboarded; 第三遍(完成)与跳过逐字节相同

const SAVE := "user://savegame.json"
const MENU := "res://scenes/MainMenu.tscn"
const EXIT_WORDS := ["返回", "返回主菜单", "认输", "沿用上次", "商店", "←"]
const SB := preload("res://scripts/net/supabase.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 90
var _battles_entered := 0
var _last_scene_id := 0
var _a := PackedByteArray()
## 假传输记下的每一条请求: {m, u, tut(发出那一刻是否在教程里), write}
var _reqs: Array = []
var _after_skip := ""  # 跳过那一遍: 出口相对基线改了哪几行


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


func _transport(m, u, _h, _b, cb) -> void:
	_reqs.append({"m": str(m), "u": str(u), "tut": bool(GameState.tutorial_active),
		"write": SB.is_write_request(str(m), str(u))})
	cb.call({"ok": false, "code": 503, "body": ""})


func _writes_in_tutorial() -> Array:
	var out: Array = []
	for r in _reqs:
		if bool(r["tut"]) and bool(r["write"]):
			out.append("%s %s" % [r["m"], str(r["u"]).get_slice("?", 0)])
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60      # 开场演出按真实时间走(2×5 秒); 钉帧率 ⇒ 帧预算可预期
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	OS.set_environment("ONBOARD", "")
	GameState.test_mode = false          # ★要量的就是存档文件(独立 user://)
	## ── 假服务器: 后端「开着」, 每条真发出去的请求都经过 _transport ──
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	_ok("★分母: 后端真的打开了(否则「写请求 = 0」是空检查)", SB.enabled())
	await _skip_pass()
	await _full_pass()
	await _network_denominator()
	SB._transport_for_test = Callable()
	GameState.test_mode = true
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 新手教程 v3 整条: 隔离沙盒 / 无返回 / 做了才前进 / 站位真拖不落盘 / 零写请求" if _fail == 0 else "FAILED: %d" % _fail)
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
	## 已登录的绑定号: 云存档同步的前提全齐(账号 / 邮箱 / 令牌) ⇒ 「教程里不推」靠的是教程闸, 不是没登录
	GameState.account_id = "gate-acc-tut"
	GameState.account_email = "gate@turtle.test"
	SB._token = "tok-gate"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	GameState.save()
	GameState._load()          # 基线 = 读档后再存那一形(JSON 整数读回变 float, 与教程无关; 见 verify_tutorial_skip)
	GameState.save()
	_a = _bytes()
	for f in ["user://team_draft.json", "user://lastLineup.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## 两份存档逐行比, 返回变了的行(行号 + 前后两面)。
func _diff_lines(a: PackedByteArray, b: PackedByteArray) -> String:
	var al := a.get_string_from_utf8().split("
")
	var bl := b.get_string_from_utf8().split("
")
	var out: Array = []
	for i in range(maxi(al.size(), bl.size())):
		var x: String = al[i] if i < al.size() else "<无>"
		var y: String = bl[i] if i < bl.size() else "<无>"
		if x != y:
			out.append("%d:%s→%s" % [i, x.strip_edges(), y.strip_edges()])
	return "|".join(out)


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
		got == want and _bytes() != _a)
	_ok("[%s] 账号原状态回来了(292 币 / 5 级 / 原统领 / 0 场)" % tag,
		int(GameState.meta_deepsea_coins) == 292 and int(GameState.season_level) == 5
		and Array(GameState.season_leaders) == ["candy", "ghost", "pirate"] and int(GameState.season_total_battles) == 0)
	_ok("[%s] 教程状态收干净" % tag, not bool(GameState.tutorial_active) and (GameState.dual_ghost as Dictionary).is_empty()
		and not get_node("/root/TutorialDirector").in_sandbox())


# ═══════════════════════════════ 场景工具 ═══════════════════════════════

func _open_menu() -> Node:
	## ★先把上一遍留下的当前场景清掉 —— 它不会被下面的 current_scene 赋值释放, 会一直挂在根上挡点击。
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


## 当前在屏上的那一条引导(战斗里可能同时挂着已放完的提示节点 ⇒ 只认正在显示的)。
func _guide() -> Node:
	var any: Node = null
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion():
			if n.is_showing():
				return n
			any = n
	return any


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


## ── 真鼠标事件(无头下直接推进根视口: GUI 命中 → _input → _unhandled_input, 与真点击同一条链) ──
func _scr(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _scr(p)
	e.global_position = _scr(p)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	get_viewport().push_input(e)


func _motion(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _scr(p)
	m.global_position = _scr(p)
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)


## 真点一个控件的中心(要穿过引导的暗幕洞才点得到 —— 洞挖错了这一下就被暗幕吃掉)。
func _click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	_motion(p, Vector2.ZERO)
	await get_tree().process_frame
	_mouse(p, true)
	await get_tree().process_frame
	_mouse(p, false)
	await _frames(3)


func _drag(c: Control, delta: Vector2, steps: int) -> void:
	var p0: Vector2 = c.get_global_rect().get_center()
	_motion(p0, Vector2.ZERO)
	await get_tree().process_frame
	_mouse(p0, true)
	await get_tree().process_frame
	for i in range(1, steps + 1):
		_motion(p0 + delta * (float(i) / float(steps)), delta / float(steps))
		await get_tree().process_frame
	_mouse(p0 + delta, false)
	await _frames(3)


func _send(e: InputEvent) -> void:
	get_viewport().push_input(e)


# ═══════════════════════════════ 第一遍: 选龟屏按「跳过教程」 ═══════════════════════════════

func _skip_pass() -> void:
	print("  ── 第一遍: 进教程 → 选龟屏按右上「跳过教程」 ──")
	_make_account()
	var m = await _open_menu()
	## ★基线 = 玩家按「开始教程」那一刻的账号存档(主菜单首次显示会写上 install_uid 等「你是谁」那几项)。
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
	_after_skip = _diff_lines(_a, _bytes())
	await _frames(4)
	_ok("★跳过后主菜单不再弹选择框", mm != null and mm.get_node_or_null("TutorialChoice") == null)


# ═══════════════════════════════ 第二遍: 整条走完 ═══════════════════════════════

func _full_pass() -> void:
	print("  ── 第二遍: 整条走完 ──")
	_make_account()
	_battles_entered = 0
	var m = await _open_menu()
	GameState.save()
	_a = _bytes()
	_reqs.clear()
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
		elif st == "fight":
			break
		await get_tree().process_frame
		wait_f += 1
	print("    [B1] 演出期间 %d 帧 · 其中提示在屏 %d 帧 · 共等 %d 帧" % [present_frames, shown_in_present, wait_f])
	_ok("★分母 B1: 真的经历了开场演出(三路总览/对阵卡)", present_frames > 30, "%d 帧" % present_frames)
	_ok("★★B1: 演出期间一帧提示都没出", shown_in_present == 0, "%d 帧" % shown_in_present)
	_ok("★★演出完直接开打(不停在摆位)", str(bt._dl_state) == "fight", "state=%s" % str(bt._dl_state))
	_check_exits(bt, "战斗")
	_disk_untouched("战斗")
	await _battle_tips(bt)
	## 三路整场要 ~140 游戏秒; 这里量的是教程的结算这一屏 —— 直接走产品的**收尾入口** `_dl_finish`
	##   (它会跑 `_settle_season`: 赛季账 / 快照上传 / 录像那一串都在它后面, 教程闸必须在这里挡住)。
	bt._dl_sys._dl_finish(true)
	await _frames(2)
	_disk_untouched("结算")
	_ok("★★★结算这一刻(含 _settle_season)对服务器的写请求 = 0", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	var names: Array = []
	for c in (bt._hud._settle.btn_row as Node).get_children():
		if c is Button:
			names.append((c as Button).text)
	_ok("★★结算只有「前往商店」(没有「返回主菜单」)", names == ["前往商店"], str(names))
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
	w = await _wait_text("点击一件装备")
	_ok("★买经验 ⇒ 2 级 ⇒ 提示「点击一件装备」", w >= 0 and int(GameState.season_level) == 2, "Lv%d「%s」" % [int(GameState.season_level), _guide_text()])
	await _frames(30)
	_ok("★不点卡就停在「点击一件装备」", _guide_text() == "点击一件装备")
	var pick := -1
	for i in range((sh._offer as Array).size()):
		if sh._offer[i] != null and sh._price(sh._deco(sh._offer[i])) <= int(GameState.meta_deepsea_coins):
			pick = i
			break
	_ok("分母: 货架上有买得起的卡", pick >= 0)
	if pick < 0:
		return
	## 手势指针指的就是那张卡(锚点 offer_card), 真点它
	var card_r: Rect2 = sh._tutorial_anchor("offer_card")
	_ok("★「点击一件装备」的指针指在第 1 张买得起的卡上", card_r.size.x > 0.0)
	_motion(card_r.get_center(), Vector2.ZERO)
	await get_tree().process_frame
	_mouse(card_r.get_center(), true)
	await get_tree().process_frame
	_mouse(card_r.get_center(), false)
	await _frames(4)
	if int(sh._sel) != pick:
		sh._on_select(pick)    # 卡的点击区若被卡面子控件吃掉, 退回产品自己的点卡入口(仍发同一事件)
	w = await _wait_text("点击购买")
	_ok("★★点卡 ⇒ 提示「点击购买」(两步购买的第一下)", w >= 0, "实测「%s」 sel=%d" % [_guide_text(), int(sh._sel)])
	await _frames(30)
	_ok("★★B2: 不按购买就停在「点击购买」, 背包仍空", _guide_text() == "点击购买" and GameState.persistent_bench.is_empty())
	var buy: Button = sh._tut_buy_btn
	_ok("分母: 说明卡里的「购买」钮在", buy != null and is_instance_valid(buy) and buy.is_visible_in_tree())
	if buy == null or not is_instance_valid(buy):
		return
	await _click(buy)
	_ok("分母: 真买了一件(真点「购买」穿过了暗幕的洞)", GameState.persistent_bench.size() == 1, "背包 %d 件" % GameState.persistent_bench.size())
	if GameState.persistent_bench.is_empty():
		sh._on_buy(pick)
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
	w = await _wait_text("点击站位")
	_ok("★★X1: 真装上了(全队件数 +1)", int(GameState.team_equipped_count()) == n0 + 1, "%d → %d" % [n0, int(GameState.team_equipped_count())])
	_ok("★装上 ⇒ 提示「点击站位」", w >= 0, "实测「%s」" % _guide_text())
	var fb := inv.find_child("FormationBtn", true, false) as Button
	_ok("★★v3: 教程里顶栏「站位」在且可见(原来被藏起来)", fb != null and fb.is_visible_in_tree())
	if fb == null:
		return
	_check_exits(inv, "背包·站位钮")
	await _click(fb)
	w = await _wait_text("拖动龟调整站位")
	_ok("★真点「站位」⇒ 面板开 ⇒ 提示「拖动龟调整站位」", w >= 0 and inv._formation.is_open(), "实测「%s」" % _guide_text())
	var tok := inv.find_child("Token_top_0", true, false) as Control
	_ok("分母: 上战场第一只龟的头像在", tok != null)
	if tok == null:
		return
	var off0 = (GameState.get_dual_lineup()["top"][0] as Dictionary).get("off", null)
	## 只点一下(不拖)不算
	await _click(tok)
	await _frames(10)
	_ok("★只点一下龟(不拖)不前进", _guide_text() == "拖动龟调整站位")
	await _drag(tok, Vector2(-90, 60), 10)
	var off1 = (GameState.get_dual_lineup()["top"][0] as Dictionary).get("off", null)
	print("    [站位] 拖动前 off=%s 拖动后 off=%s" % [str(off0), str(off1)])
	_ok("★分母: 真拖动改了沙盒里的阵容(上战场第一只的 off 变了)", off1 != null and str(off1) != str(off0), "%s → %s" % [str(off0), str(off1)])
	_disk_untouched("站位·拖动后")
	w = await _wait_text("点击完成")
	_ok("★真拖一下 ⇒ 提示「点击完成」", w >= 0, "实测「%s」" % _guide_text())
	var done := inv.find_child("FormationDone", true, false) as Control
	_ok("分母: 「完成」在", done != null)
	if done == null:
		return
	await _click(done)
	w = await _wait_text("点击完成教程")
	_ok("★真点「完成」⇒ 面板关 ⇒ 提示「点击完成教程」", w >= 0 and not inv._formation.is_open(), "实测「%s」" % _guide_text())
	_disk_untouched("背包")
	_ok("★★★教程期间(到这里)对服务器的写请求 = 0", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	## 教程里节拍器到点 / 切后台 ⇒ 产品会调这一个入口推云存档; 教程闸必须挡住
	SB.maybe_push_save(true)
	await _frames(3)
	_ok("★★教程里强推一次云存档 ⇒ 仍是 0 条写请求", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	await _click(inv._tut_finish_btn)

	# ── 结束 ──
	var mm := await _wait_scene("MainMenu.tscn")
	_ok("★真点「完成教程」⇒ 回主菜单", mm != null)
	_ok("★出口理由 completed", str(td.last_end_reason) == "completed")
	_ok("★走完 ⇒ 主菜单飘「教程完成」", mm != null and _has_label(mm, "教程完成"))
	_ok("★★只打了 1 把战斗", _battles_entered == 1, "%d 把" % _battles_entered)
	_after_exit("完成")
	## 两遍的基线各自含 install_uid 等「你是谁」 ⇒ 比的是「出口相对基线改了什么」逐行相同
	var full_diff := _diff_lines(_a, _bytes())
	_ok("★★★完成 == 跳过(相对进教程前, 两种出口改动的存档行逐字节相同)", full_diff == _after_skip and not full_diff.is_empty(),
		"完成 %s / 跳过 %s" % [str(full_diff), str(_after_skip)])
	_ok("★★★整条教程对服务器的写请求 = 0", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	var n_tut := 0
	for r in _reqs:
		if bool(r["tut"]):
			n_tut += 1
	print("    [网络] 教程期间发出的请求 %d 条(读) · 全程 %d 条" % [n_tut, _reqs.size()])
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


## 战斗里两句不阻塞提示(v3 第 3、4 步)。
func _battle_tips(bt: Node) -> void:
	var w := await _wait_text("赢两个战场获胜，1:1 进入终极战场", 240)
	_ok("★v3 开打后出提示「赢两个战场获胜，1:1 进入终极战场」", w >= 0, "实测「%s」" % _guide_text())
	var g := _guide()
	_ok("分母: 拿到提示节点", g != null and g.has_method("is_blocking"))
	if g == null or not g.has_method("is_blocking"):
		return
	_ok("★★不阻塞: 本层没有能吃点击的可见控件(无暗幕)", not g.is_blocking())
	var hand: TextureRect = g.find_child("TutorialHand", true, false)
	_ok("★不阻塞提示不出手势", hand == null or not hand.visible)
	_ok("★战斗没被暂停(提示在屏时 sim 照走)", not get_tree().paused)
	var t_a: float = float(bt._t)
	await _frames(20)
	_ok("★提示在屏时战斗时钟在走", float(bt._t) > t_a, "%.2f → %.2f" % [t_a, float(bt._t)])
	await _check_tip_overlap(bt, g, "三路")
	w = await _wait_text("击碎敌方的蛋直接获胜", 600)
	_ok("★到点自己换成「击碎敌方的蛋直接获胜」(没人点任何东西)", w >= 0, "实测「%s」" % _guide_text())
	g = _guide()
	if g != null and g.has_method("is_blocking"):
		_ok("★★不阻塞(第 2 句)", not g.is_blocking())
		var er: Rect2 = get_node("/root/TutorialDirector")._battle_anchor("foe_egg", bt)
		_ok("★环套在敌方蛋上(锚点解析出屏内矩形)", er.size.x > 0.0 and get_viewport().get_visible_rect().has_point(er.get_center()), str(er))
		await _check_tip_overlap(bt, g, "碎蛋")
	var gone := -1
	for i in range(600):
		if _guide_text() == "":
			gone = i
			break
		await get_tree().process_frame
	_ok("★两句放完自己收起(之后战斗里无提示)", gone >= 0, "等了 %d 帧" % gone)
	await _buff_badge(bt)


## 教程加成(用户 10-20): 我方全员带 增伤 / 减伤, 敌方不带; 战斗里看得见(「教程加成」签, 点开出说明句)。
func _buff_badge(bt: Node) -> void:
	var TB = load("res://scripts/systems/onboarding/tutorial_buff.gd")
	var TD = load("res://autoload/tutorial_director.gd")
	var nl := 0
	var nr := 0
	var bad: Array = []
	for u in bt._units:
		if not bool(u.get("alive", false)) or bool(u.get("is_trainer", false)):
			continue
		var has: bool = bool(u.get(TB.MARK, false))
		if str(u.get("side", "")) == "left":
			nl += 1
			if not has or float(u.get("damage_amp", 0.0)) < TD.TUTORIAL_DMG_AMP - 1e-6 or float(u.get("damage_reduction", 0.0)) < TD.TUTORIAL_DR - 1e-6:
				bad.append("我方 %s" % str(u.get("id", "?")))
		elif str(u.get("side", "")) == "right":
			nr += 1
			if has:
				bad.append("敌方 %s" % str(u.get("id", "?")))
	_ok("分母: 场上有我方 %d / 敌方 %d 个单位" % [nl, nr], nl >= 3 and nr >= 3)
	_ok("★★教程加成: 我方全员带(增伤 %d%% / 减伤 %d%%), 敌方一个都不带" % [int(TD.TUTORIAL_DMG_AMP * 100), int(TD.TUTORIAL_DR * 100)], bad.is_empty(), str(bad))
	var bn: Node = bt.get_node_or_null(TB.BADGE_NAME)
	_ok("★教程加成签挂上了", bn != null)
	if bn == null:
		return
	var badge: Control = bn.badge
	_ok("★签在屏上可见、写「%s」" % TB.BADGE_TEXT, badge.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(badge.get_global_rect()) 		and (badge.get_child(0) as Label).text == TB.BADGE_TEXT, str(badge.get_global_rect()))
	var col: Control = bt._team_panel_left
	_ok("★签在我方头像栏正上方、不压它", badge.get_global_rect().end.y <= col.get_global_rect().position.y + 0.5, "%s / %s" % [str(badge.get_global_rect()), str(col.get_global_rect())])
	await _click(badge)
	await _frames(3)
	var want: String = TB.text()
	_ok("★点签 ⇒ 出「%s」(数字读常量)" % want, bn.popup.visible and bn.popup_text() == want 		and want == "新手教程：增伤 %d%%，减伤 %d%%" % [int(round(TD.TUTORIAL_DMG_AMP * 100)), int(round(TD.TUTORIAL_DR * 100))], bn.popup_text())
	await _click(badge)
	await _frames(3)
	_ok("★再点 ⇒ 收起", not bn.popup.visible)


## R2: 提示条不压战斗 HUD 上任何可见的按钮 / 文字(10-07 B1 同类: 提示条压在「三路开战」卡上)。
func _check_tip_overlap(bt: Node, g: Node, tag: String) -> void:
	await _frames(2)
	var pr: Rect2 = g.panel_rect()
	var hits: Array = []
	var n := 0
	for c in bt.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or _eff_alpha(ctl) < 0.1 or _under_guide(ctl):
			continue
		if _chrome(bt) != null and _chrome(bt).is_ancestor_of(ctl):
			continue
		var t := ""
		if ctl is Button:
			t = (ctl as Button).text
		elif ctl is Label:
			t = (ctl as Label).text
		if t.strip_edges() == "":
			continue
		var r := ctl.get_global_rect()
		if r.size.x <= 0.0 or r.size.x > 900.0:
			continue
		n += 1
		if pr.intersects(r):
			hits.append("%s %s @%s" % [t.strip_edges().left(12), str(r), str(bt.get_path_to(ctl))])
	print("    [R2·%s] 提示条 %s · 比对 %d 个 HUD 文字/按钮" % [tag, str(pr), n])
	_ok("★分母[%s]: 提示条有尺寸, 且比对了 HUD 控件" % tag, pr.size.x > 0.0 and n > 3, "n=%d" % n)
	_ok("★★R2[%s]: 提示条不压战斗 HUD 的可见文字/按钮" % tag, hits.is_empty(), str(hits))


# ═══════════════════════════════ 分母: 写请求这把尺子量得到写 ═══════════════════════════════

## 教程外同一入口(云存档强推)确实会发出写请求 ⇒ 上面的「0 条」不是因为尺子瞎。
func _network_denominator() -> void:
	var before := _reqs.size()
	GameState.meta_deepsea_coins = int(GameState.meta_deepsea_coins) + 1
	GameState.save()
	SB.maybe_push_save(true)
	await _frames(5)
	var w := 0
	for i in range(before, _reqs.size()):
		if bool(_reqs[i]["write"]) and not bool(_reqs[i]["tut"]):
			w += 1
	_ok("★★分母: 教程外强推云存档 ⇒ 假传输记到写请求(尺子能看见写)", w > 0, "%d 条" % w)
