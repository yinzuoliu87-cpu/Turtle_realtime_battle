extends Node
## verify_save_conflict_nudge.gd — 主菜单「处理存档冲突」提示条(2026-10-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 云存档冲突 = 停推。原来它只在设置页里多一颗「处理存档冲突」, 不进设置就看不到 ——
## LouisT01 的云存档就这样一周没动、没人知道(根因见 `scripts/net/save_own_write.gd`)。
## 现在主菜单齿轮下面那条提示条(与「绑定账号」同一个位置、同一种画法)在冲突时亮出来,
## 点它 ⇒ 去设置页, 进门就是二选一框。
##
## ★走真入口: `change_scene_to_file` 真开主菜单(`_ready` 里的时序手动 add_child 量不到),
##   真点那条提示(输入事件推进视口), 真落到设置页。
## ★「冲突在主菜单开着时才出现」走主菜单自己那颗每秒一次的 Timer(发它的 timeout 信号,
##   不等真实时间 —— 无头帧率极高, 等一秒会烧掉上千帧)。
## ★每条正面都配反面: 没冲突 ⇒ 不在; 冲突解除 ⇒ 消失; 没点过来 ⇒ 设置页不自己弹框。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SETTINGS := preload("res://scenes/Settings.tscn")
const DEAD_URL := "http://127.0.0.1:9"
## 本仓触摸线 81px = 44pt(与 `verify_login_wall.TOUCH_MIN_PX` 同一个数)
const TOUCH_MIN_PX := 81.0
const KEYS := ["account_id", "account_email", "onboarded", "test_mode"]

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _spy(_method, _url, _headers, _body, cb) -> void:
	cb.call({})          # 一律「连不上」: 这份门禁不碰网络, 冲突状态由下面直接摆


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	for k in KEYS:
		_bak[k] = GameState.get(k)
	var vp0 := get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	GameState.test_mode = true
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	OS.set_environment("ONBOARD", "0")
	SB._reset_auth_for_test()
	SB._reset_save_sync_for_test()
	SB._transport_for_test = _spy
	SB._token = "tok-conflict"
	GameState.account_id = "uid-me"
	GameState.account_email = "me@x.co"
	GameState.onboarded = true
	print("=== 主菜单「处理存档冲突」提示条 ===")
	await _t_shown_and_tap()
	await _t_live_toggle()
	await _t_settings_side()
	SB._transport_for_test = Callable()
	SB._reset_save_sync_for_test()
	SB._reset_auth_for_test()
	OS.set_environment("TURTLE_SUPABASE", " ")
	await _drop_scene()
	for k in KEYS:
		GameState.set(k, _bak[k])
	get_tree().root.size = vp0
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	if _ok + _fail < 20:
		print("  [FAIL] ★断言只有 %d 条(<20) —— 有用例中途中止了" % (_ok + _fail))
		_fail += 1
	print("ALL PASS — 主菜单存档冲突提示" if _fail == 0 else "FAIL x%d" % _fail)
	_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 冲突时主菜单上有它, 位置不挡路; 真点 ⇒ 设置页 + 二选一框
# ─────────────────────────────────────────────────────────────
func _t_shown_and_tap() -> void:
	print("── ① 有冲突 ⇒ 主菜单亮出提示条, 点了直接到二选一框 ──")
	SB._save_conflict_rev = 8
	_chk("① ★分母: 冲突状态真的立起来了", SB.save_conflict())
	_chk("① ★分母: 这个号绑了邮箱 ⇒ 绑定提示那一条不该出(两条不会同时在)",
		not P2C.bind_needed(SB.enabled(), str(GameState.account_email)))
	var cur := await _open_menu()
	_chk("① ★分母: 主菜单真的建起来了", cur != null and str(cur.name).begins_with("MainMenu"),
		str(cur.name) if cur != null else "<null>")
	var nudge := _find_named(cur, MM.CONFLICT_NUDGE_NAME) as Control
	_chk("① ★★有冲突 ⇒ 主菜单上那条「处理存档冲突」**在屏幕上**",
		nudge != null and nudge.is_visible_in_tree(), str(nudge.get_global_rect()) if nudge != null else "<不在>")
	_chk("① 绑定提示那一条不在(同一个位置, 两条叠在一起就看不清)", _find_named(cur, MM.NUDGE_NAME) == null)
	if nudge == null:
		return
	_chk("① 写的字 == `save_conflict_nudge_text()`(产品那一处, 不在测试里拼)",
		_has_text(nudge, str(P2C.save_conflict_nudge_text())), str(P2C.save_conflict_nudge_text()))
	var nr: Rect2 = nudge.get_global_rect()
	_chk("① 整块在 %d×%d 设计框内" % [int(MM.W), int(MM.H)],
		nr.position.x >= -0.5 and nr.position.y >= -0.5
			and nr.end.x <= float(MM.W) + 0.5 and nr.end.y <= float(MM.H) + 0.5, str(nr))
	_chk("① 短边 ≥44pt(81px) —— 它是可点的, 就得过触摸线", minf(nr.size.x, nr.size.y) >= TOUCH_MIN_PX, str(nr.size))
	var hot := _hot(cur)
	_chk("① ★分母: 主菜单上扫到了 ≥8 个可点元素", hot.size() >= 8, "%d 个" % hot.size())
	var clash: Array = []
	for c in hot:
		var cc := c as Control
		if cc == nudge or nudge.is_ancestor_of(cc):
			continue
		if nr.intersects(cc.get_global_rect()):
			clash.append("%s %s" % [str(cc.name), str(cc.get_global_rect())])
	_chk("① ★★不压住主菜单上任何一个可点元素(压住 = 点别的点到它)", clash.is_empty(), str(clash))
	var pc: Vector2 = Rect2(nr.position, Vector2(nr.size.x, 38.0)).get_center()   # 看得见的那条(尖角 + 30 高)
	var hh := _hover_at(pc)
	_chk("① ★分母: 提示条中心那一点是它自己吃到的", hh != null and (hh == nudge or nudge.is_ancestor_of(hh)),
		"%s @ %s" % [str(hh), str(pc)])
	_tap(pc)
	var waited := await _wait_scene_named("Settings", 300)
	var s := get_tree().current_scene
	_chk("① ★★真点 ⇒ 到了设置页(等了 %d 帧)" % waited,
		s != null and str(s.name).begins_with("Settings"), str(s.name) if s != null else "<null>")
	await _wf(6)
	var layer = s.get("_confirm_layer") if s != null else null
	_chk("① ★★★进门就是二选一框(不用再找「处理存档冲突」那颗键)",
		layer != null and is_instance_valid(layer) and _has_text(layer, "存档冲突"), str(layer))
	_chk("① 一次性旗子读完就清", not SET.open_conflict_on_entry)


# ─────────────────────────────────────────────────────────────
# ② 冲突在主菜单开着时才出现 / 解除 ⇒ 每秒那一拍对上账
# ─────────────────────────────────────────────────────────────
func _t_live_toggle() -> void:
	print("── ② 冲突中途出现 / 解除 ──")
	SB._save_conflict_rev = -1
	var cur := await _open_menu()
	_chk("② ★反面: 没冲突 ⇒ 没有那条提示", _find_named(cur, MM.CONFLICT_NUDGE_NAME) == null)
	var tick := _poll_timer(cur)
	_chk("② ★分母: 主菜单那颗每秒一次的 Timer 接的就是 `_sb_poll`", tick != null)
	if tick == null:
		return
	SB._save_conflict_rev = 9          # 推送回包里才知道冲突 ⇒ 主菜单开着时出现
	tick.timeout.emit()
	await _wf(2)
	var n1 := _find_named(cur, MM.CONFLICT_NUDGE_NAME)
	_chk("② ★★冲突在主菜单开着时出现 ⇒ 下一拍就亮出来(不用退出再进)", n1 != null and (n1 as Control).is_visible_in_tree())
	tick.timeout.emit()
	await _wf(2)
	_chk("② 再一拍不会叠出第二条", _count_named(cur, MM.CONFLICT_NUDGE_NAME) == 1,
		"%d 条" % _count_named(cur, MM.CONFLICT_NUDGE_NAME))
	SB._save_conflict_rev = -1         # 玩家在别处(设置页)处理掉了
	tick.timeout.emit()
	await _wf(3)
	_chk("② ★★冲突解除 ⇒ 那条提示收掉", _find_named(cur, MM.CONFLICT_NUDGE_NAME) == null)


# ─────────────────────────────────────────────────────────────
# ③ 设置页那一侧: 只有「从提示点过来 + 真有冲突」才自己开框
# ─────────────────────────────────────────────────────────────
func _t_settings_side() -> void:
	print("── ③ 设置页进门开框的条件 ──")
	await _drop_scene()
	SB._save_conflict_rev = 8
	SET.open_conflict_on_entry = false
	var s1 := await _open_settings()
	_chk("③ ★反面: 有冲突但不是从提示点过来 ⇒ 不自己弹框(照旧只亮「处理存档冲突」那颗键)",
		s1.get("_confirm_layer") == null and _has_text(s1, "处理存档冲突"), str(s1.get("_confirm_layer")))
	s1.queue_free()
	await _wf(2)
	SB._save_conflict_rev = -1
	SET.open_conflict_on_entry = true
	var s2 := await _open_settings()
	_chk("③ ★反面: 点过来时冲突已经没了 ⇒ 不开框(没有可选的)", s2.get("_confirm_layer") == null)
	_chk("③ 旗子照样清掉", not SET.open_conflict_on_entry)
	s2.queue_free()
	await _wf(2)


# ─────────────────────────────────────────────────────────────
func _open_menu() -> Node:
	await _drop_scene()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await _wf(16)
	_settle_intro()
	await _wf(2)
	return get_tree().current_scene


func _open_settings() -> Node:
	var s = SETTINGS.instantiate()
	add_child(s)
	await _wf(12)
	return s


## 把当前场景清掉再换 —— `current_scene = null` 先置空, 引擎换屏时就不会把门禁自己删掉
##   (`verify_login_wall._drop_scene` 同一个做法与理由)。
func _drop_scene() -> void:
	var old = get_tree().current_scene
	get_tree().current_scene = null
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _wf(2)


func _wf(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _settle_intro() -> void:
	for tw in get_tree().get_processed_tweens():
		if tw.is_valid() and tw.is_running() and tw.get_loops_left() != -1:
			tw.custom_step(10.0)


func _wait_scene_named(nm: String, cap: int) -> int:
	var w := 0
	while w < cap:
		var c = get_tree().current_scene
		if c != null and is_instance_valid(c) and str(c.name).begins_with(nm):
			return w
		await get_tree().process_frame
		w += 1
	return w


func _poll_timer(cur: Node) -> Timer:
	if cur == null:
		return null
	for ch in cur.get_children():
		if ch is Timer and (ch as Timer).timeout.is_connected(Callable(cur, "_sb_poll")):
			return ch as Timer
	return null


func _find_named(root: Node, nm: String) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if str(root.name) == nm:
		return root
	for ch in root.get_children():
		var r := _find_named(ch, nm)
		if r != null:
			return r
	return null


func _count_named(root: Node, nm: String) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var n := 1 if str(root.name) == nm else 0
	for ch in root.get_children():
		n += _count_named(ch, nm)
	return n


func _has_text(root: Node, txt: String) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if (root is Label or root is Button) and str(root.get("text")).find(txt) >= 0:
		return true
	if root is RichTextLabel and (root as RichTextLabel).get_parsed_text().find(txt) >= 0:
		return true
	for ch in root.get_children():
		if _has_text(ch, txt):
			return true
	return false


func _hot(root) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			if c is BaseButton or c is Range or c is LineEdit or c is TextEdit:
				out.append(c)
		for ch in (n as Node).get_children():
			stack.append(ch)
	return out


func _hover_at(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	get_viewport().push_input(mm)
	var h = get_viewport().gui_get_hovered_control()
	return h as Control if h is Control else null


func _tap(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		get_viewport().push_input(e)
