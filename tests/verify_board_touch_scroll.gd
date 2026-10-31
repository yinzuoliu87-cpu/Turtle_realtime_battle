extends Node
## verify_board_touch_scroll.gd — 闯关赛况左栏「战绩榜」手指按在行上能滑(2026-10-31)
##
## 用户 2026-10-31(iPhone, TestFlight 0.22.6):「观赛区的左边，手机这个用手指滑动根本滑动不了啊。」
##   2026-10-10 报过同一件事(「左侧滑动我在手机端很难操作啊」), 当时只把盖满整行的透明按钮改成 PASS ——
##   **没有任何测试真的拿手指拖过这张表**, 于是那次修没修好没人知道。
## 根因(探针实测, 手指按在第 3 行上拖 200px): 原样 ScrollContainer 收到 **0** 个事件、滚动 Δ=0;
##   按在行与行之间的缝 ⇒ 收到全部事件、Δ≈600。差别在行框 PanelContainer —— 它**默认 STOP**,
##   按钮 PASS 透上来的事件到它这一层就停了。⇒ `_player_row` 把行框设成 IGNORE(右栏三种卡本来就是)。
##
## ★走真触摸: `Input.parse_input_event(InputEventScreenTouch / ScreenDrag)` ⇒ 引擎照手机那样经
##   emulate_mouse_from_touch 生成模拟鼠标(ScrollContainer 的拖动与按钮的按下都靠它)。
##   `emulate_touch_from_mouse` 打开 ⇒ `DisplayServer.is_touchscreen_available()` 为真, ScrollContainer 才走
##   触屏拖动分支(手机上就是真; 桌面无头默认假, 那条分支根本不跑 —— 这正是以前量不出来的原因)。
##   (与 verify_debug_equip_pick 同一套手指。)
## ★两种比例: 1280×720(设计尺寸) 与 2340×1080(iPhone 横屏一类, 设计框居中、整体缩放)。
##
## 判据(每种比例):
##   ① 分母: 触屏分支开着 / 45 行 / 可滚范围 > 1000px / 起手那一下真的按在那一行的整行按钮上(button_down 恰 1 次)
##   ② ★★手指按在行上往上拖 200px ⇒ 松手那一刻已经滚了 ≥ 100px(不算松手后的惯性)
##   ③ ★滑过的那一下不算点: 榜没被点成「只看他」(focus_tag 仍空)
##   ④ 手指点一下(带 2~4px 抖动)仍是点: 右栏换成他的对局; 触摸抬起到达时那颗按钮还在树上
##      (当场重画会把它摘下 ⇒ 引擎报 `Condition "!is_inside_tree()" … can_process`, 同 verify_scene_change_on_release)
##   ⑤ 手指按在行框的边距上(按钮外、行框内)拖 ⇒ 也能滑
##   ⑥ 右栏: 手指按在「观看」上拖 ⇒ 滚了, 且没开回放(_busy / last_replay_code 都空)

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BOARD_SCENE := "res://scenes/GauntletBoard.tscn"
const N_ROWS := 45
const DRAG_PX := 200.0
const MIN_SCROLL := 100

var _fail := 0
var _n := 0
var _xf: Transform2D = Transform2D.IDENTITY
var _tpos: Vector2 = Vector2.ZERO
## 触摸抬起到达时被点的按钮: 1 = 已离树 / 0 = 还在树上 / -1 = 没量到
var _watch_btn: Button = null
var _gone_at_release := -1


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


## 输入先过 `_input` 再进 GUI: 在这里看触摸抬起到达时那颗按钮还在不在树上。
func _input(event: InputEvent) -> void:
	if _watch_btn == null or not (event is InputEventScreenTouch) or (event as InputEventScreenTouch).pressed:
		return
	_gone_at_release = 1 if (is_instance_valid(_watch_btn) and not _watch_btn.is_inside_tree()) else 0
	if _gone_at_release == 1:
		get_viewport().set_input_as_handled()     # 已量到; 不让它进 GUI 真打出那条报错(门禁致命正则认它)


# ─────────────────────────────── 手指 ───────────────────────────────
func _t_ev(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _t_down(p: Vector2) -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = _xf * p
	_tpos = p
	await _t_ev(t)


func _t_move(p: Vector2) -> void:
	var d := InputEventScreenDrag.new(); d.index = 0; d.position = _xf * p
	d.relative = _xf.basis_xform(p - _tpos); d.screen_relative = d.relative
	_tpos = p
	await _t_ev(d)


func _t_up() -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = false; t.position = _xf * _tpos
	await _t_ev(t)


## 手指往上拖 DRAG_PX(10 步)。返回松手那一刻的滚动量变化(惯性之前)。
func _swipe_up(sc: ScrollContainer, p: Vector2) -> int:
	var v0: int = sc.scroll_vertical
	await _t_down(p)
	for k in range(10):
		await _t_move(p - Vector2(0, DRAG_PX * float(k + 1) / 10.0))
	var v1: int = sc.scroll_vertical
	await _t_up()
	return v1 - v0


# ─────────────────────────────── 数据 ───────────────────────────────
## N 个人, 每人自己传过一局(只以对手身份出现的人不进榜) ⇒ 战绩榜 N 行、右栏 N 张卡。
func _rows(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var j := (i + 1) % n
		var lp := {"name": "龟%02d" % i, "tag": P2C.player_tag("acct:touch%d" % i), "avatar": "basic", "id": "g_x"}
		var rp := {"name": "龟%02d" % j, "tag": P2C.player_tag("acct:touch%d" % j), "avatar": "basic", "id": "g_x"}
		out.append({"match_id": "%08x-0000-4000-8000-%012x" % [i + 1, i + 1],
			"created_at": "2026-10-31T10:%02d:00+00:00" % (i % 60), "lp": lp, "rp": rp, "rw": i % 3, "rl": i % 2,
			"result": {"won": i % 2 == 0, "steps": 100, "surrendered": false, "gw": 1 + i % 4, "gl": i % 3}})
	return out


func _sc_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## 可见区里、头顶还留得下 DRAG_PX 的那一颗(手指往上拖全程都在列表里)。
func _pick(btns: Array, sc: ScrollContainer) -> Button:
	var r: Rect2 = sc.get_global_rect()
	var best: Button = null
	for b in btns:
		var c: Vector2 = (b as Control).get_global_rect().get_center()
		if c.y > r.position.y + DRAG_PX + 20.0 and c.y < r.end.y - 30.0:
			if best == null or c.y < best.get_global_rect().get_center().y:
				best = b
	return best


# ─────────────────────────────── 主流程 ───────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	OS.set_environment(SB.ENV_URL, " ")
	var em0: bool = Input.emulate_touch_from_mouse
	var em1: bool = Input.emulate_mouse_from_touch
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	await get_tree().process_frame
	_ok("分母: 后端关着(不往外发请求)", not SB.enabled())
	await _flow(Vector2i(1280, 720), "1280×720", false)
	await _flow(Vector2i(2340, 1080), "2340×1080", true)
	Input.emulate_touch_from_mouse = em0
	Input.emulate_mouse_from_touch = em1
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	print("ALL PASS — 赛况板手指滑动" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 每一次量都开一张新的赛况板: 松手后的惯性(无头下帧快, 算出来的速度能滑十几秒)会把上一次的滚动
##   带进下一次 —— 下一次的手指若到不了 ScrollContainer(正是要抓的那种回退), 惯性照样让 Δ 变大 ⇒ 假绿。
func _open_board() -> Node:
	var bs: Node = (load(BOARD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(bs)
	get_tree().current_scene = bs
	await _frames(3)
	bs.set_rows(_rows(N_ROWS))
	await _frames(3)
	return bs


func _close(bs: Node) -> void:
	bs.queue_free()
	await _frames(2)


func _flow(win: Vector2i, tag: String, full: bool) -> void:
	print("── %s ──" % tag)
	get_tree().root.size = win
	await _frames(3)
	_xf = get_tree().root.get_final_transform()
	_ok("① %s 分母: 触屏分支开着(ScrollContainer 走手指拖动)" % tag, DisplayServer.is_touchscreen_available())
	## ── ② ③ 手指按在整行按钮上往上拖 ──
	var bs: Node = await _open_board()
	var btns: Array = bs.find_children("PlayerBtn", "Button", true, false)
	var sc: ScrollContainer = _sc_of(btns[0]) if not btns.is_empty() else null
	var range_px := 0.0
	if sc != null:
		range_px = sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page
	_ok("① %s 分母: 战绩榜 %d 行、可滚范围 > 1000px" % [tag, N_ROWS], btns.size() == N_ROWS and range_px > 1000.0,
		"行=%d 可滚=%.0fpx" % [btns.size(), range_px])
	var b: Button = _pick(btns, sc) if sc != null else null
	_ok("① %s 分母: 找到起手那一行(头顶留得下 %dpx)" % [tag, int(DRAG_PX)], b != null)
	if b == null:
		await _close(bs)
		return
	var downs := [0]
	b.button_down.connect(func() -> void: downs[0] += 1)
	var d: int = await _swipe_up(sc, b.get_global_rect().get_center())
	await _frames(2)
	_ok("① %s 分母: 起手那一下真按在那一行的整行按钮上(button_down=%d)" % [tag, downs[0]], downs[0] == 1)
	_ok("② %s ★★手指按在行上拖 %dpx ⇒ 战绩榜滚了 ≥ %dpx(松手那一刻, 不算惯性)" % [tag, int(DRAG_PX), MIN_SCROLL],
		d >= MIN_SCROLL, "Δ=%d / 可滚 %.0f" % [d, range_px])
	_ok("③ %s ★滑过的那一下不算点(没被点成只看他)" % tag, str(bs.focus_tag) == "", "focus='%s'" % bs.focus_tag)
	await _close(bs)
	## ── ④ 手指点一下仍是点 ──
	bs = await _open_board()
	btns = bs.find_children("PlayerBtn", "Button", true, false)
	sc = _sc_of(btns[0])
	var tb: Button = _pick(btns, sc)
	var want := str(tb.get_meta("key", ""))
	_watch_btn = tb
	_gone_at_release = -1
	var p: Vector2 = tb.get_global_rect().get_center()
	await _t_down(p)
	await _t_move(p + Vector2(2, 1))
	await _t_move(p + Vector2(3, 3))
	await _t_up()
	await _frames(2)
	_watch_btn = null
	_ok("④ %s ★手指点一下(带 4px 抖动) ⇒ 仍是点: 右栏换成他的对局" % tag, want != "" and str(bs.focus_tag) == want,
		"focus='%s' want='%s'" % [bs.focus_tag, want])
	_ok("④ %s ★触摸抬起到达时那颗按钮还在树上(当场重画 ⇒ 引擎报 can_process)" % tag, _gone_at_release == 0,
		"gone=%d" % _gone_at_release)
	await _close(bs)
	if not full:
		return
	## ── ⑤ 行框边距(按钮外、行框内) ──
	bs = await _open_board()
	btns = bs.find_children("PlayerBtn", "Button", true, false)
	sc = _sc_of(btns[0])
	var eb: Button = _pick(btns, sc)
	var row_r: Rect2 = (eb.get_parent() as Control).get_global_rect()
	var btn_r: Rect2 = eb.get_global_rect()
	var ep := Vector2(row_r.position.x + 3.0, row_r.get_center().y)
	_ok("⑤ %s 分母: 那一点在行框内、按钮外" % tag, row_r.has_point(ep) and not btn_r.has_point(ep), "%s / %s" % [ep, btn_r])
	var d5: int = await _swipe_up(sc, ep)
	await _frames(2)
	_ok("⑤ %s 手指按在行框边距上拖 ⇒ 也滚了 ≥ %dpx" % [tag, MIN_SCROLL], d5 >= MIN_SCROLL, "Δ=%d" % d5)
	_ok("⑤ %s 没被点成只看他" % tag, str(bs.focus_tag) == "", "focus='%s'" % bs.focus_tag)
	await _close(bs)
	## ── ⑥ 右栏: 按在「观看」上拖 ──
	bs = await _open_board()
	var gbtns: Array = bs.find_children("GameBtn", "Button", true, false)
	var gsc: ScrollContainer = _sc_of(gbtns[0]) if not gbtns.is_empty() else null
	var gb: Button = _pick(gbtns, gsc) if gsc != null else null
	_ok("⑥ %s 分母: 右栏有「观看」、头顶留得下 %dpx" % [tag, int(DRAG_PX)], gb != null, "观看 %d 颗" % gbtns.size())
	if gb != null:
		var gd := [0]
		gb.button_down.connect(func() -> void: gd[0] += 1)
		var d6: int = await _swipe_up(gsc, gb.get_global_rect().get_center())
		await _frames(2)
		_ok("⑥ %s 分母: 起手按在「观看」上(button_down=%d)" % [tag, gd[0]], gd[0] == 1)
		_ok("⑥ %s 手指按在「观看」上拖 ⇒ 右栏滚了 ≥ %dpx" % [tag, MIN_SCROLL], d6 >= MIN_SCROLL, "Δ=%d" % d6)
		_ok("⑥ %s ★滑过的那一下没开回放" % tag, str(bs._busy) == "" and str(bs.last_replay_code) == "",
			"busy='%s' code='%s'" % [bs._busy, bs.last_replay_code])
	await _close(bs)
