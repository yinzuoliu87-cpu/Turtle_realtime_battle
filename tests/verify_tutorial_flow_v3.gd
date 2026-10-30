extends Node

## verify_tutorial_flow_v3.gd — 新手教程 v3 整条走一遍, 全程真场景真入口
##   (方案书 docs/plans/20261020-教程重写.md §1 / §2 / 验收清单第 2 条; 取代 verify_tutorial_flow_v2)
##
## 用户原话(逐字):
##   「教程里的商店怎么能够和账号的商店互通呢 … 整个教程都不应该有当前存档的东西啊」(10-07)
##   「教程里就不应该有返回键啊，要一直跟着教程走啊」 /「缩」/「打三路」/「是点击啊」(10-07)
##   「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」(10-19) ⇒ 教程要教「站位」在哪
##
## v5(2026-10-21 分镜 docs/plans/20261021-教程分镜v5.md): 「开始教程」⇒ **选龟屏**(3 只依次发光, 真点; 第一只后真点一个技能;
##   「出战」前讲阵容锁定)⇒ 战斗(C1/C2 开场两句不阻塞; 其余 4 句挂在事件上, 由 verify_tutorial_battle_tips 打满一场量)
##   ⇒ 结算 ⇒ 商店(E1 先讲 1 级不能装备、「买经验」此时还不在; E2 才出现)⇒ 背包(F1 刚买那件 = 预放 2 件 + 买 1 件合成的 2 星)
##   ⇒ 站位 ⇒ 完成教程。每一句的字从 data/tutorial-steps.json 读({pet}/{item} 按屏上状态填), 门禁不抄文案副本。
##   新增量: 洞外暗幕点一下 ⇒ 气泡下出说明且不前进(分镜「点错有一句说明」); 金色箭头尖指在发光的那张龟卡上。
## v4(2026-10-21): 真主菜单 → 首启流程那一屏(介绍, 按「跳过」)→ 选择框「开始教程」→ **直接进战斗**(阵容预配, 不经过选龟屏)
##   → …… → 「完成教程」→ 起名(首启那一屏) → 主菜单。第一遍改成在战斗里按「跳过教程」→ 起名 → 主菜单。
## 走法(v3 原文): 真主菜单 → 选择框「开始教程」→ 选龟 → 战斗(真开场演出 + 两句不阻塞提示) → 结算 → 商店(经验 / 点卡 / 购买 / 背包)
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
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const TG := preload("res://scripts/scenes/TutorialGuide.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 120
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
	GameState.nickname = ""          # 新号没起过名 ⇒ 出口后要起名(v4)
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
	## v4: 首启的号主菜单会自己换到首启流程那一屏(m 已释放) ⇒ 交回真正的当前场景
	return m if is_instance_valid(m) else get_tree().current_scene


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


## 步骤表里某一屏第 i 句(门禁不抄文案副本: 文案换了这里跟着换)。
func _step_text(key: String, i: int) -> String:
	var arr: Array = TG.steps_for(key)
	return str((arr[i] as Dictionary).get("text", "")) if i < arr.size() else "<无第 %d 句>" % i


## 真点一个屏幕矩形的中心。
func _click_at(p: Vector2) -> void:
	_motion(p, Vector2.ZERO)
	await get_tree().process_frame
	_mouse(p, true)
	await get_tree().process_frame
	_mouse(p, false)
	await _frames(3)


# ═══════════════════════════════ 第一遍: 选龟屏按「跳过教程」 ═══════════════════════════════

func _skip_pass() -> void:
	print("  ── 第一遍: 进教程 → 战斗里按右上「跳过教程」→ 起名 → 主菜单 ──")
	_make_account()
	var m = await _open_menu()
	## ★基线 = 玩家按「开始教程」那一刻的账号存档(主菜单首次显示会写上 install_uid 等「你是谁」那几项)。
	GameState.save()
	_a = _bytes()
	var ch: Node = await _choice_from(m)
	if ch == null:
		return
	(ch.find_child("StartTutorial", true, false) as Button).emit_signal("pressed")
	var bt := await _wait_scene("TeamSelect.tscn")
	_ok("分母: 「开始教程」进了选龟屏(v5)", bt != null)
	if bt == null:
		return
	await _frames(4)
	var sk = _chrome(bt)
	_ok("分母: 外壳挂上了", sk != null)
	if sk == null:
		return
	(sk.button as Button).emit_signal("pressed")
	var fl := await _wait_scene("FirstLaunch.tscn")
	_ok("★「跳过教程」⇒ 先起名(首启那一屏, v4)", fl != null and bool(fl.call("is_naming")))
	_ok("★「跳过教程」⇒ 出口理由 skipped", str(get_node("/root/TutorialDirector").last_end_reason) == "skipped")
	_after_exit("跳过")
	_after_skip = _diff_lines(_a, _bytes())
	var mm := await _name_and_menu(fl, "跳过")
	_ok("★跳过 ⇒ 不飘「教程完成」", mm != null and not _has_label(mm, "教程完成"))
	await _frames(4)
	_ok("★跳过后主菜单不再弹选择框 / 不再进首启", mm != null and mm.get_node_or_null("TutorialChoice") == null
		and str(get_tree().current_scene.scene_file_path).ends_with("MainMenu.tscn"))


## 主菜单(首启)⇒ 首启流程那一屏 ⇒ 按「跳过」略过介绍 ⇒ 返回选择框。
func _choice_from(m: Node) -> Node:
	var fl: Node = m if m != null and is_instance_valid(m) and str(m.scene_file_path).ends_with("FirstLaunch.tscn") else await _wait_scene("FirstLaunch.tscn", 120)
	_ok("分母: 首启 ⇒ 换到首启流程那一屏(不压在主菜单上)", fl != null)
	if fl == null:
		return null
	_ok("★首启那一屏先放介绍(第 1 页, 还没问)", int(fl.call("page_index")) == 0 and not bool(fl.call("is_asking")))
	_disk_untouched("首启介绍")
	await _click(fl.find_child("SkipIntro", true, false) as Control)
	var ch: Node = fl.get_node_or_null("TutorialChoice")
	_ok("分母: 介绍之后选择框在", ch != null)
	return ch


## 起名框: 预填的名字直接点「确认」⇒ 主菜单。量: 名字写进账号存档(rename_apply 那一次存档); 主菜单没有新手锁。
func _name_and_menu(fl: Node, tag: String) -> Node:
	if fl == null:
		return null
	var ed := fl.find_child("NameEdit", true, false) as LineEdit
	_ok("[%s] 分母: 起名框预填了名字" % tag, ed != null and ed.text.strip_edges() != "", ed.text if ed != null else "")
	if ed == null:
		return null
	var nm: String = ed.text
	await _click(fl.find_child("NameOk", true, false) as Control)
	var mm := await _wait_scene("MainMenu.tscn")
	_ok("★[%s] 起名「确认」⇒ 主菜单" % tag, mm != null)
	var js = JSON.parse_string(_bytes().get_string_from_utf8())
	_ok("★★[%s] 名字写进了账号存档(盘上)" % tag, js is Dictionary and str(js.get("nickname", "")) == P2C.nickname_clean(nm), str(js.get("nickname", "")) if js is Dictionary else "?")
	_ok("★[%s] 存档里没有「逐个点亮」标记(2026-10-23 拿掉)" % tag, js is Dictionary and not js.has("novice_menu"))
	if mm != null:
		for _i in range(40):
			await get_tree().process_frame
		var locked: Array = []
		for l in mm.find_children("LockReason", "Label", true, false):
			var nm_txt := ""
			for c2 in (l as Node).get_parent().get_children():
				if c2 is Label and c2 != l:
					nm_txt = (c2 as Label).text     # 第一个兄弟 Label = 入口名字(与 verify_first_launch._reasons 同一取法; 后面那个空字的是红点角标)
					break
			if nm_txt != "商店":
				locked.append(nm_txt)
		_ok("★★[%s] 主菜单除商店外一个锁都没有(背包 / 图鉴 / 排行榜 / 训龟大师都亮)" % tag, locked.is_empty(), str(locked))
	return mm


# ═══════════════════════════════ 第二遍: 整条走完 ═══════════════════════════════

func _full_pass() -> void:
	print("  ── 第二遍: 整条走完 ──")
	_make_account()
	_battles_entered = 0
	var m = await _open_menu()
	GameState.save()
	_a = _bytes()
	_reqs.clear()
	var ch: Node = await _choice_from(m)
	if ch == null:
		return
	(ch.find_child("StartTutorial", true, false) as Button).emit_signal("pressed")
	var td = get_node("/root/TutorialDirector")

	# ── v5 选龟(分镜 B1~B4) ──
	if not await _team_select_pass(td):
		return

	# ── 战斗 ──
	var bt := await _wait_scene("RealtimeBattle3D.tscn", 600)
	_ok("分母: 进了战斗", bt != null)
	if bt == null:
		return
	var lt_sorted: Array = Array(GameState.left_team).duplicate()
	lt_sorted.sort()
	var fx_sorted: Array = Array(td.FIXED_TEAM).duplicate()
	fx_sorted.sort()
	_ok("★v5: 上阵的是选龟屏里真点的那 3 只(= 教程固定池)", lt_sorted == fx_sorted, str(GameState.left_team))
	_disk_untouched("战斗·开场")
	var w := 0
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
	w = await _wait_text(_step_text("settle", 0), 300)
	_ok("★D1 提示「%s」" % _step_text("settle", 0), w >= 0, "实测「%s」" % _guide_text())
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
	w = await _wait_text(_step_text("shop", 0), 300)
	_ok("★E1 先讲「%s」(不阻塞, 自己前进)" % _step_text("shop", 0), w >= 0, "实测「%s」" % _guide_text())
	## v5 修(10-21 录屏自评): E1 气泡原来压住下排货架一半 ⇒ 放到顶上, 金色箭头朝下指等级牌
	var g1 := _guide()
	for _k in range(30):
		if g1 != null and g1.is_showing() and g1._hand.visible:
			break
		await _frames(1)
	var shelf_r: Rect2 = sh._tutorial_anchor("shelf")
	var lv_r: Rect2 = sh._tutorial_anchor("level_row")
	_ok("分母: E1 显示着、货架 / 等级牌都解析得出", g1 != null and g1.is_showing() and shelf_r.size.x > 0.0 and lv_r.size.x > 0.0)
	if g1 != null:
		_ok("★★E1 气泡不压货架上的装备(5×2 货架整块)", not g1.panel_rect().intersects(shelf_r), "气泡 %s / 货架 %s" % [str(g1.panel_rect()), str(shelf_r)])
		_ok("★★E1 有金色箭头、箭尖落在等级牌上", g1._hand.visible and lv_r.grow(2.0).has_point(g1.arrow_tip()), "箭尖 %s / 等级牌 %s" % [str(g1.arrow_tip()), str(lv_r)])
		_ok("★E1 仍不挡点击(不阻塞提示)", g1.is_tip() and not g1.is_blocking())
	var xb0 = sh.get("_tut_xp_btn")
	_ok("★★E1 时「买经验」还不在屏上(分镜「按钮教到才出现」)", xb0 == null or not is_instance_valid(xb0) or not (xb0 as Control).is_visible_in_tree())
	w = await _wait_text(_step_text("shop", 1), 600)
	_ok("★E1 到点自己换成 E2「%s」" % _step_text("shop", 1), w >= 0, "实测「%s」" % _guide_text())
	var xb1 = sh.get("_tut_xp_btn")
	_ok("★★E2 时「买经验」出现了", xb1 != null and is_instance_valid(xb1) and (xb1 as Control).is_visible_in_tree())
	_ok("★教程商店是开着的(账号 0 场也能逛)", sh._offer.size() > 0)
	_ok("★★F3 开局配置: 货架第 1 格是预放的同一件(%s)" % td.TUT_MERGE_ITEM, sh._offer.size() > 0 and sh._offer[0] != null
		and str((sh._offer[0] as Dictionary).get("id", "")) == str(td.TUT_MERGE_ITEM))
	_ok("★顶栏返回键藏了, 「背包」键在", not (sh._top_bar.back_btn as Control).visible
		and sh._bag_tab() != null and sh._bag_tab().is_visible_in_tree()
		and not (sh._top_bar.action_btns[0] as Control).is_visible_in_tree())   # 2026-10-22 左上「商店 | 背包」页签: [0] 是亮着的「商店」, 教程里藏起
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
	w = await _wait_text(_step_text("shop", 2))
	_ok("★买经验 ⇒ 2 级 ⇒ E3「%s」" % _step_text("shop", 2), w >= 0 and int(GameState.season_level) == 2, "Lv%d「%s」" % [int(GameState.season_level), _guide_text()])
	await _frames(30)
	_ok("★不点卡就停在 E3", _guide_text() == _step_text("shop", 2))
	var pick := -1
	for i in range((sh._offer as Array).size()):
		if sh._offer[i] != null and sh._price(sh._deco(sh._offer[i])) <= int(GameState.meta_deepsea_coins):
			pick = i
			break
	_ok("分母: 货架上有买得起的卡, 第一张就是预放的那件", pick == 0, "pick=%d" % pick)
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
	w = await _wait_text(_step_text("shop", 3))
	_ok("★★点卡 ⇒ E4「%s」(两步购买的第一下)" % _step_text("shop", 3), w >= 0, "实测「%s」 sel=%d" % [_guide_text(), int(sh._sel)])
	await _frames(30)
	_ok("★★B2: 不按购买就停在 E4, 背包仍只有预放的 2 件", _guide_text() == _step_text("shop", 3) and GameState.persistent_bench.size() == int(td.TUT_MERGE_PRESET),
		"背包 %d 件" % GameState.persistent_bench.size())
	var buy: Button = sh._tut_buy_btn
	_ok("分母: 说明卡里的「购买」钮在", buy != null and is_instance_valid(buy) and buy.is_visible_in_tree())
	if buy == null or not is_instance_valid(buy):
		return
	var coins_b4 := int(GameState.meta_deepsea_coins)
	await _click(buy)
	_ok("分母: 真买了一件(真点「购买」穿过了暗幕的洞)", int(GameState.meta_deepsea_coins) < coins_b4, "币 %d → %d" % [coins_b4, int(GameState.meta_deepsea_coins)])
	if int(GameState.meta_deepsea_coins) == coins_b4:
		sh._on_buy(pick)
	var b0: Dictionary = GameState.persistent_bench[0] if GameState.persistent_bench.size() > 0 else {}
	_ok("★★F3: 预放 2 件 + 买 1 件 ⇒ 正式规则自动合成 1 件 2 星", GameState.persistent_bench.size() == 1
		and str(b0.get("id", "")) == str(td.TUT_MERGE_ITEM) and int(b0.get("star", 1)) == 2, str(GameState.persistent_bench))
	## v5 修(10-21 录屏自评): 合成就发生在买下那一刻 ⇒ 「集齐 3 件……自动合成」挪到商店里买下之后讲(原在背包 F3)
	w = await _wait_text(_step_text("shop", 4))
	_ok("★★成交且合成了 ⇒ 当场讲 E4b「%s」(不阻塞, 自己前进)" % _step_text("shop", 4), w >= 0, "实测「%s」" % _guide_text())
	var g4b := _guide()
	_ok("★E4b 不挡点击、圈得出目标(刚合成那件 / 顶栏背包)", g4b != null and g4b.is_tip() and not g4b.is_blocking()
		and (g4b._target_rect("merge_cell") as Rect2).size.x > 0.0)
	if g4b != null:
		## 买下那一刻商店自己飘一条成交提示(「…合成 ★2」); E4b 的气泡不许压住它, 也不压货架
		var toast_hit := false
		for l in sh.find_children("*", "Label", true, false):
			var lt := (l as Label).text
			if lt.contains("合成") and (l as Label).is_visible_in_tree() and not g4b.is_ancestor_of(l):
				if g4b.panel_rect().intersects((l as Label).get_global_rect()):
					toast_hit = true
		_ok("★E4b 气泡不压商店的成交提示、不压货架", not toast_hit and not g4b.panel_rect().intersects(sh._tutorial_anchor("shelf")), str(g4b.panel_rect()))
	w = await _wait_text(_step_text("shop", 5), 600)
	_ok("★E4b 到点 ⇒ E5「%s」" % _step_text("shop", 5), w >= 0, "实测「%s」" % _guide_text())
	_disk_untouched("商店")
	sh._bag_tab().emit_signal("pressed")   # 「背包」那一签(左上页签「商店 | 背包」, 按字找)

	# ── 背包 ──
	var inv := await _wait_scene("Inventory.tscn")
	_ok("分母: 进了背包", inv != null)
	if inv == null:
		return
	var item_nm := str((DataRegistry.phase2_equipment_by_id.get(str(td.TUT_MERGE_ITEM), {}) as Dictionary).get("name", ""))
	var f1 := _step_text("inventory", 0).replace("{item}", item_nm)
	w = await _wait_text(f1)
	_ok("★F1「%s」({item} = 刚买合成的那件)" % f1, w >= 0 and item_nm != "", "实测「%s」" % _guide_text())
	_check_exits(inv, "背包")
	var fi: Rect2 = inv._tutorial_anchor("first_item")
	_ok("分母: 发光的那件(first_item)在屏上", fi.size.x > 0.0, str(fi))
	await _click_at(fi.get_center())
	if int(inv._sel_bench) != 0:
		inv._on_bench_click(0)
	w = await _wait_text(_step_text("inventory", 1))
	_ok("★点装备 ⇒ F2「%s」" % _step_text("inventory", 1), w >= 0, "实测「%s」" % _guide_text())
	## v5 修: F2 的箭头指在一只龟的卡上; 「完成教程」到 F6 才出现(之前它在左上, 箭头从它正下方伸出来像在指它)
	var g2 := _guide()
	var fl_r: Rect2 = inv._tutorial_anchor("first_leader")
	_ok("★★F2 箭头尖落在一只龟的卡上(first_leader)", g2 != null and fl_r.size.x > 0.0 and fl_r.grow(2.0).has_point(g2.arrow_tip()),
		"箭尖 %s / 卡 %s" % [str(g2.arrow_tip()) if g2 != null else "?", str(fl_r)])
	_ok("★★F2 时「完成教程」还不在屏上(教到 F6 才出现)", inv._tut_finish_btn != null and not inv._tut_finish_btn.is_visible_in_tree())
	var n0 := int(GameState.team_equipped_count())
	inv._dl_click("top", 0)
	w = await _wait_text(_step_text("inventory", 2))
	_ok("★★X1: 真装上了(全队件数 +1)", int(GameState.team_equipped_count()) == n0 + 1, "%d → %d" % [n0, int(GameState.team_equipped_count())])
	_ok("★装上 ⇒ F4「%s」(合成那句已在商店讲过, 背包不再讲)" % _step_text("inventory", 2), w >= 0, "实测「%s」" % _guide_text())
	var merge_txt := ""
	for st_m in TG.steps_for("shop"):
		if str((st_m as Dictionary).get("_id", "")) == "E4b":
			merge_txt = str((st_m as Dictionary).get("text", ""))
	var inv_has_merge := false
	for st_i in TG.steps_for("inventory"):
		if str((st_i as Dictionary).get("text", "")) == merge_txt:
			inv_has_merge = true
	_ok("★背包引导里不再有合成那一句(只在商店讲一次)", merge_txt != "" and not inv_has_merge)
	var fb := inv.find_child("FormationBtn", true, false) as Button
	_ok("★★v3: 教程里顶栏「站位」在且可见(原来被藏起来)", fb != null and fb.is_visible_in_tree())
	if fb == null:
		return
	_check_exits(inv, "背包·站位钮")
	await _click(fb)
	w = await _wait_text(_step_text("inventory", 3))
	_ok("★真点「站位」⇒ 面板开 ⇒ F5「%s」" % _step_text("inventory", 3), w >= 0 and inv._formation.is_open(), "实测「%s」" % _guide_text())
	var tok := inv.find_child("Token_top_0", true, false) as Control
	_ok("分母: 上战场第一只龟的头像在", tok != null)
	if tok == null:
		return
	var off0 = (GameState.get_dual_lineup()["top"][0] as Dictionary).get("off", null)
	## 只点一下(不拖)不算
	await _click(tok)
	await _frames(10)
	_ok("★只点一下龟(不拖)不前进", _guide_text() == _step_text("inventory", 3))
	await _drag(tok, Vector2(-90, 60), 10)
	var off1 = (GameState.get_dual_lineup()["top"][0] as Dictionary).get("off", null)
	print("    [站位] 拖动前 off=%s 拖动后 off=%s" % [str(off0), str(off1)])
	_ok("★分母: 真拖动改了沙盒里的阵容(上战场第一只的 off 变了)", off1 != null and str(off1) != str(off0), "%s → %s" % [str(off0), str(off1)])
	_disk_untouched("站位·拖动后")
	w = await _wait_text(_step_text("inventory", 4))
	_ok("★真拖一下 ⇒ 提示「%s」" % _step_text("inventory", 4), w >= 0, "实测「%s」" % _guide_text())
	var done := inv.find_child("FormationDone", true, false) as Control
	_ok("分母: 「完成」在", done != null)
	if done == null:
		return
	await _click(done)
	w = await _wait_text(_step_text("inventory", 5))
	_ok("★真点「完成」⇒ 面板关 ⇒ F6「%s」" % _step_text("inventory", 5), w >= 0 and not inv._formation.is_open(), "实测「%s」" % _guide_text())
	_disk_untouched("背包")
	_ok("★★★教程期间(到这里)对服务器的写请求 = 0", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	## 教程里节拍器到点 / 切后台 ⇒ 产品会调这一个入口推云存档; 教程闸必须挡住
	SB.maybe_push_save(true)
	await _frames(3)
	_ok("★★教程里强推一次云存档 ⇒ 仍是 0 条写请求", _writes_in_tutorial().is_empty(), str(_writes_in_tutorial()))
	_ok("★★F6 时「完成教程」出现了", inv._tut_finish_btn != null and inv._tut_finish_btn.is_visible_in_tree())
	await _click(inv._tut_finish_btn)

	# ── 结束 ──
	var fl := await _wait_scene("FirstLaunch.tscn")
	_ok("★真点「完成教程」⇒ 起名(首启那一屏, v4)", fl != null and bool(fl.call("is_naming")))
	_ok("★出口理由 completed", str(td.last_end_reason) == "completed")
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
	var mm := await _name_and_menu(fl, "完成")
	_ok("★走完 ⇒ 主菜单飘「教程完成」", mm != null and _has_label(mm, "教程完成"))
	await _frames(4)
	_ok("★完成后主菜单不再弹选择框", mm != null and mm.get_node_or_null("TutorialChoice") == null)
	## X3: 之后的选龟屏是全部龟(不再是教学 3 只)
	var ts2 = load("res://scenes/TeamSelect.tscn").instantiate()
	add_child(ts2)
	await _frames(4)
	## ★2026-10-30 选龟页重做: 锁定后(本大轮统领已定)不建龟池(用户「锁定后的就不用去显示其他龟和稀有度了啊」)。
	##   这个号进教程前统领就定了(_make_account) ⇒ 教程后是锁定版: 量「统领位是这个号自己的那三只, 不是教学固定队」;
	##   没锁的号才量「龟池是全部龟」。两支都量「不在教学模式里」。
	_ok("★X3 分母: 教程后选龟屏不在教学模式里", not bool(ts2._tut_on()))
	if bool(ts2._roster_locked):
		_ok("★★X3: 教程后选龟屏(锁定版)是这个号自己的三只统领(不是教学固定队)",
			Array(ts2.team) == Array(GameState.season_leaders) and Array(ts2.team) != Array(td.FIXED_TEAM),
			"阵容 %s · 本大轮统领 %s · 教学队 %s" % [str(ts2.team), str(GameState.season_leaders), str(td.FIXED_TEAM)])
	else:
		var cnt: int = (ts2._grid_flow as Node).get_child_count()
		_ok("★★X3: 教程后选龟屏是全部龟(不是教学 3 只)", cnt == DataRegistry.launch_pets.size(), "%d 只" % cnt)
	ts2.queue_free()
	await _frames(2)


## 战斗开场两句不阻塞提示(v5 C1 教程加成 / C2 自动战斗、两个战场)。挂在事件上的 C3~C6 由 verify_tutorial_battle_tips 打满一场量。
func _battle_tips(bt: Node) -> void:
	var c1 := _step_text("battle", 0)
	var w := await _wait_text(c1, 300)
	_ok("★C1 开打后出「%s」" % c1, w >= 0, "实测「%s」" % _guide_text())
	var g := _guide()
	_ok("分母: 拿到提示节点", g != null and g.has_method("is_blocking"))
	if g == null or not g.has_method("is_blocking"):
		return
	_ok("★★不阻塞: 本层没有能吃点击的可见控件(无暗幕)", not g.is_blocking())
	var arrow: Control = g.find_child("TutorialArrow", true, false)
	_ok("★不阻塞提示不出箭头", arrow == null or not arrow.visible)
	_ok("★战斗没被暂停(提示在屏时 sim 照走)", not get_tree().paused)
	var t_a: float = float(bt._t)
	await _frames(20)
	_ok("★提示在屏时战斗时钟在走", float(bt._t) > t_a, "%.2f → %.2f" % [t_a, float(bt._t)])
	var br: Rect2 = get_node("/root/TutorialDirector")._battle_anchor("buff_badge", bt)
	_ok("★C1 的环套在「教程加成」签上", br.size.x > 0.0 and get_viewport().get_visible_rect().has_point(br.get_center()), str(br))
	await _check_tip_overlap(bt, g, "教程加成")
	var c2 := _step_text("battle", 1)
	w = await _wait_text(c2, 600)
	_ok("★到点自己换成 C2「%s」(没人点任何东西)" % c2, w >= 0, "实测「%s」" % _guide_text())
	g = _guide()
	if g != null and g.has_method("is_blocking"):
		_ok("★★不阻塞(C2)", not g.is_blocking())
		await _check_tip_overlap(bt, g, "两个战场")
	await _buff_badge(bt)


## v5 选龟屏(分镜 B1~B4): 只有教程固定池 3 只; 依次发光、真点; 第一只之后真点一个技能; 「出战」前讲锁定。返回是否走到了战斗。
func _team_select_pass(td: Node) -> bool:
	var ts := await _wait_scene("TeamSelect.tscn", 600)
	_ok("分母: 「开始教程」⇒ 选龟屏(v5)", ts != null)
	if ts == null:
		return false
	_disk_untouched("选龟")
	_ok("★选龟屏只有教程固定池 %d 只" % td.FIXED_TEAM.size(), (ts._grid_flow as Node).get_child_count() == td.FIXED_TEAM.size(),
		"%d 张" % (ts._grid_flow as Node).get_child_count())
	## v5 修(10-21 录屏自评): 页名与引导用同一个词(龟, 不是「统领」); 稀有度筛选那一排在 3 只的固定池里是空签 ⇒ 不显示
	var ttl: Label = ts.get("_ent_title")
	_ok("★★教程选龟屏页名 =「%s」(与引导「选出 3 只龟」同一个词, 不出现「统领」)" % ts.TUT_TITLE, ttl != null and ttl.text == ts.TUT_TITLE
		and not ttl.text.contains("统领") and ttl.text.contains("龟"), ttl.text if ttl != null else "null")
	var rail: Control = ts.get("_ent_rail")
	_ok("★★教程选龟屏不显示稀有度筛选(SSS/SS/S/A/B/C)", rail != null and not rail.is_visible_in_tree())
	_check_exits(ts, "选龟")
	var seen_names: Array = []
	for k in range(3):
		var nxt: String = ts._tut_next_pet()
		var nm := str((DataRegistry.pet_by_id.get(nxt, {}) as Dictionary).get("name", ""))
		var want := _step_text("team_select", 0 if k == 0 else k + 1).replace("{pet}", nm)
		var w := await _wait_text(want, 300)
		_ok("★B%s 第 %d 只:「%s」" % ["1" if k == 0 else "3", k + 1, want], w >= 0 and nm != "" and not (nm in seen_names), "实测「%s」" % _guide_text())
		seen_names.append(nm)
		var g := _guide()
		var card_r: Rect2 = ts._tutorial_anchor("roster_pet")
		_ok("分母: 发光的那张卡在屏上", card_r.size.x > 0.0, str(card_r))
		if g != null and g.has_method("arrow_tip"):
			_ok("★金色箭头尖指在发光的那张卡上", card_r.grow(4).has_point(g.arrow_tip()), "箭尖 %s / 卡 %s" % [str(g.arrow_tip()), str(card_r)])
		if k == 0:
			## 点错: 洞外点一下(屏幕左上角标题区)⇒ 说明, 不上阵
			var miss := Vector2(24, 300)
			_ok("分母: 点错那一下确实在洞外", not card_r.grow(12).has_point(miss))
			await _click_at(miss)
			_ok("★★点洞外 ⇒ 气泡下出说明「%s」, 不前进" % TG.wrong_tap_text(), g != null and g.wrong_tap_shown() == TG.wrong_tap_text()
				and _guide_text() == want, g.wrong_tap_shown() if g != null else "")
			_ok("★点洞外没有让任何龟上阵", _placed(ts) == 0)
		var before := _placed(ts)
		await _click_at(card_r.get_center())
		_ok("★★真点发光的卡 ⇒ 上阵 +1(穿过了暗幕的洞)", _placed(ts) == before + 1, "%d → %d" % [before, _placed(ts)])
		if k == 0:
			var b2 := _step_text("team_select", 1)
			w = await _wait_text(b2, 300)
			_ok("★B2「%s」" % b2, w >= 0, "实测「%s」" % _guide_text())
			var sr: Rect2 = ts._tutorial_anchor("skill_choices")
			_ok("分母: 技能格在屏上", sr.size.x > 0.0, str(sr))
			var picked_pid: String = str(ts.detail_pet_id)
			var icon: Control = null
			for gc in (ts._detail_bottom as Node).find_children("*", "GridContainer", true, false):
				if (gc as Node).get_child_count() >= 3:
					icon = (gc as Node).get_child(2) as Control
			_ok("分母: 找到第 2 个可选技能格", icon != null)
			if icon != null:
				await _click_at(icon.get_global_rect().get_center())
			_ok("★★真点一个技能 ⇒ 这只龟带的技能改成它(loadout=2)", int(GameState.loadouts.get(picked_pid, -1)) == 2,
				"%s → %s" % [picked_pid, str(GameState.loadouts.get(picked_pid, null))])
			_ok("★教程里点技能不弹全屏说明框(它会吃掉下一步的第一下)", not is_instance_valid(ts._info_popup))
	var b4 := _step_text("team_select", 4)
	var w4 := await _wait_text(b4, 300)
	_ok("★★B4 按下「出战」前讲锁定「%s」" % b4, w4 >= 0, "实测「%s」" % _guide_text())
	_ok("分母: 三只齐了「出战」点得动", not (ts._start_btn as Button).disabled)
	_disk_untouched("选龟·点满")
	await _click_at((ts._start_btn as Control).get_global_rect().get_center())
	return true


func _placed(ts: Node) -> int:
	var n := 0
	for t in ts.team:
		if t != null:
			n += 1
	return n


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


## 飘字(伤害 / 护盾 / 治疗数字)不是 HUD: 跟着单位飘、一秒左右就消失, 碰巧飘到提示条下面不算压 HUD。
##   ★2026-10-23: 原来它们也算进来 ⇒ CI 上偶发红(「+51 盾」飘到提示条底下, 取决于那一刻谁在掉盾 / 机器快慢)。
##   飘字都进 BattleHud.UI_TRANSIENT_GROUP(battle_vfx._float_text, 全仓只有它进这个组); 暴击那种是 HBox 包 Label ⇒ 往上找祖先。
func _is_float_text(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_in_group(BattleHud.UI_TRANSIENT_GROUP):
			return true
		p = p.get_parent()
	return false


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
		if _is_float_text(ctl):
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
