extends Node
## verify_scroll_touch_sweep.gd — 全游戏滚动列表「手指按在条目上就能滑」运行时哨兵(2026-10-31)
##
## 由来: 用户 2026-10-31(iPhone):「观赛区的左边，手机这个用手指滑动根本滑动不了啊。」
##   根因是行框 PanelContainer 默认 STOP —— 行里的按钮 PASS 透上来的事件到它这一层就停了,
##   ScrollContainer 一个事件都收不到(探针: 0 个事件、Δ=0)。那一处修在 GauntletBoardScene(verify_board_touch_scroll)。
##   **这一份找的是同一类的全部**: 任何玩家看得见的滚动框里, 手指按下那一点到 ScrollContainer 之间
##   只要有一层 STOP(或按下的那颗本身就是 STOP), 那一点起手就滑不动。
##
## ★为什么桌面上永远看不出来: 滚轮事件带 force_pass_scroll_events 能穿过 STOP; 手指拖动不能。
##   而 ScrollContainer 的手指拖动分支只在 `DisplayServer.is_touchscreen_available()` 为真时才跑 ——
##   桌面无头默认是假, 那条分支根本不跑。⇒ 开 `emulate_touch_from_mouse`(手机上就是真)。
## ★为什么不用静态扫: 行是运行时拼出来的(默认值就是 STOP 的控件不写 mouse_filter 那一行, 源码里看不见),
##   而且「按下那一点命中的是谁」只有引擎的命中测试说了算。⇒ 两层运行时证据:
##   ① 扫: 每个滚动框可见区按 STEP 网格逐点移鼠标, 读引擎的 `gui_get_hovered_control()`(= 手指按下会落到的那一个),
##      从它往上走到 ScrollContainer, 途中任何 STOP / top_level ⇒ 记一处拦截。每个滚动框看到底(最多 MAX_POS 屏)。
##   ② 拖: 每个可滚的滚动框挑几处(干净的 + 每一种拦截各一处)真拿手指拖 —— InputEventScreenTouch / ScreenDrag
##      经 `Input.parse_input_event`(引擎自己按 emulate_mouse_from_touch 生成模拟鼠标), 量松手前那一刻的滚动量、
##      到达 ScrollContainer 的事件数、拖动期间有没有按钮被点(pressed)/ 屏幕状态变没变。
## ★惯性: 松手后的惯性在物理帧里走, 会把上一次的滚动带进下一次(下一次手指若到不了 ScrollContainer, 惯性照样让 Δ 变大 ⇒ 假绿)。
##   ⇒ 松手同一调用栈里 `set_physics_process_internal(false)` 冻住它; 下一次按下若真到了滚动框, 引擎自己重开。
##   不用等物理帧 ⇒ 帧数与机器快慢无关。
## ★入场动画: 图鉴每切一次页签列表从左边滑进来(0.57 秒) —— 扫的时候在 A 处、拖的时候已经滑走(实测: 起手点命中的是背景)。
##   ⇒ 每屏扫之前把**有限次**的 tween 快进到底(`custom_step`), 再等滚动框位置连续几帧不动;
##   拖之前再验一次「起手点命中的还是扫到的那一个」, 不是就判红(量的不是扫到的那一处)。
## ★两种比例: 1280×720 与 2340×1080(iPhone 横屏一类)。
##
## 判据:
##   ① 分母: 每屏建出来了、可滚的滚动框个数 ≥ 期望、每个可滚的滚动框真扫到了条目、挑到了起手点、真拖了
##   ② ★★扫: 不在 KNOWN 里的拦截点 = 0
##   ③ ★★拖: 干净起手点(按钮优先)⇒ 列表**跟手**: 松手前滚了 ≥ 拖距 − FOLLOW_SLACK(只许落后一个死区, 半路断掉不算)
##      且事件到了 ScrollContainer; 两种手法: 匀速(10×16px)与快甩(4px 起步再一大步)
##   ④ ★拖的那一下不算点: 起手那一下真按在那颗控件上(收到左键按下)、但没有按钮 pressed、屏幕状态没变
##   ⑤ KNOWN(文件归别人, 本轮不能改)照样量、照样打印; 不再复现 ⇒ 红(提醒把那一条删掉, 别让清单烂掉)
##   ⑥ 改成 PASS / 松手才算点之后, 手指点一下仍是点(好友「删除」/ 黑名单「移出」/ 举报入口 / 图鉴热区与列表行 / 背包格与羁绊条)
## 帧数: 两种比例全跑约 4900 帧(本机 ~90 秒), 与机器快慢基本无关(不等物理帧, 只有入场动画快进那一段按帧轮询)。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BE := preload("res://scripts/net/backend.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const BLP := preload("res://scripts/scenes/settings/blocklist_panel.gd")
const BL := preload("res://scripts/util/blocklist.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const INV_SEED := preload("res://tests/_setup_inv_demo.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

const STEP := 16.0
const DRAG_PX := 160.0
const MIN_SCROLL := 60
## 跟手的余量: 滚动落后手指至多一个死区(项目 gui/common/default_scroll_deadzone = 18)+ 两像素取整。
const FOLLOW_SLACK := 20
const MAX_POS := 6
const AXE := "p2eq_096"

## 本来就该自己吃拖动的控件: 不算拦截(输入框要选字、滑条要拖值、滚动条就是滚动本身)。
const EXEMPT := ["LineEdit", "TextEdit", "Slider", "SpinBox", "ScrollBar"]

## 已知、本轮不能改的(文件归别人, 有未提交的改动在做)。判据键里含这一段 ⇒ 没过时记作已知(不含比例):
##   ② 拦截: `② 屏 | 滚动框路径 | 种类 拦截者路径`;  ③ 跟手 / ④ 拖成了点: `③/④ 屏 | 滚动框路径 | 起手命中的控件`。
## (空 = 现在没有已知未修的。2026-10-31 唯一一条 —— 选龟龟池卡片按局部坐标判点、一滑就把龟点进阵容 —— 已改用 TapSlop 修掉。)
const KNOWN := {}

## 设计上不滚的滚动框(键 = `屏 | 滚动框路径`): 里面点开描述的槽位是 STOP, 只要这个框**真的不滚**就碍不着手指。
##   ★豁免是有条件的: 每次都量它的可滚范围, 可滚了(内容超出)⇒ 豁免失效、里面的拦截照常判红。
const NO_SCROLL := {
	"战斗·信息面板 | CanvasLayer:UIOverlay/PanelContainer:InfoPanel/ScrollContainer:ScrollContainer":
		"设计上不许上下滑(用户 2026-08-16「不要向下撑开，不希望有要上下滑动的」), verify_info_panel_fits 守着 28 只龟都装得下",
}

var _fail := 0
var _n := 0
var _xf: Transform2D = Transform2D.IDENTITY
var _tpos: Vector2 = Vector2.ZERO
var _taps := 0
var _tag := ""

## 分母
var _n_screens := 0
var _n_sc := 0
var _n_sc_live := 0
var _n_items := 0
var _n_points := 0
var _n_drags := 0
var _found := {}
var _known_seen := {}

## 好友页的假服务器
var _friends: Array = []
var _incoming: Array = []
var _outgoing: Array = []
var _key0 = ""

var _bak := {}
const KEYS := ["test_mode", "tutorial_active", "match_history", "season_leaders", "season_wins", "season_total_battles",
	"persistent_bench", "persistent_equipped", "dual_lineup", "meta_deepsea_coins", "season_level", "season_xp",
	"meta_shop_locked", "meta_shop_offer", "meta_shop_battles", "candy_jar_count", "candy_jar_broken", "account_id",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "equip_pool", "battles_total", "battles_won",
	"lane_results", "dual_active", "finals_pending_reveal"]


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


func _alive(id: int) -> Object:
	var o: Object = instance_from_id(id) if id != 0 else null
	return o if is_instance_valid(o) else null


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


## 松手 + 同一调用栈里冻住这个滚动框的惯性(见头注「惯性」)。
func _t_up_freeze(sc: ScrollContainer) -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = false; t.position = _xf * _tpos
	Input.parse_input_event(t)
	Input.flush_buffered_events()
	if is_instance_valid(sc):
		sc.set_physics_process_internal(false)
	await get_tree().process_frame


## 手指点一下(按下 → 2px 抖动 → 抬起)。
func _t_tap(p: Vector2) -> void:
	await _t_down(p)
	await _t_move(p + Vector2(2, 1))
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = false; t.position = _xf * _tpos
	await _t_ev(t)


## 鼠标移到 p(无按键) ⇒ 引擎同步做一次命中测试, 返回悬停的那一个 = 手指按在这里会落到的控件。
func _hover(p: Vector2) -> Control:
	var mm := InputEventMouseMotion.new()
	mm.position = _xf * p
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	Input.flush_buffered_events()
	return get_viewport().gui_get_hovered_control()


## 扫完一处把鼠标挪到屏幕左上角(别让上一处的悬停效果留着)。
## ★不许挪出视口: 鼠标一出视口, 下一次进来的那个事件引擎只发「进入视口」、不更新悬停 ⇒
##   紧跟着的手指按下落在一颗「没被悬停」的按钮上, 按钮不认这一下(BaseButton 按下要求 hovering)。
##   第一版挪到 (-60,-60), 结果「拖的那一下不算点」对按钮全是空检查(按钮压根没被按下), 而「点一下仍是点」全红。
func _hover_away() -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _xf * Vector2(2, 2)
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	Input.flush_buffered_events()


# ─────────────────────────────── 结构 ───────────────────────────────
## 名字里的引擎自动编号 / 尾部序号去掉, 让同一种控件归成一类。
func _sig(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "-"
	var nm := str(n.name)
	if nm.begins_with("@"):
		var parts := nm.split("@", false)
		nm = parts[0] if parts.size() > 0 else nm
	var re := RegEx.new()
	re.compile("\\d+$")
	nm = re.sub(nm, "#")
	return "%s:%s" % [n.get_class(), nm]


func _path(from: Node, to: Node) -> String:
	var parts: Array = []
	var c: Node = to
	while c != null and c != from:
		parts.push_front(_sig(c))
		c = c.get_parent()
	return "/".join(parts)


## 控件真正看得见的那块(被祖先 clip 裁掉的不算, 视口外的不算)。
func _vis_rect(c: Control) -> Rect2:
	var r: Rect2 = c.get_global_rect()
	var p: Node = c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r.intersection(get_viewport().get_visible_rect())


func _is_bar(sc: ScrollContainer, n: Node) -> bool:
	var vb := sc.get_v_scroll_bar()
	var hb := sc.get_h_scroll_bar()
	return n == vb or n == hb or vb.is_ancestor_of(n) or hb.is_ancestor_of(n)


## 手指按在 hit 上 ⇒ 事件从 hit 往上冒到 sc 的路上谁把它截了。返回 [种类, 截住它的控件]。
##   种类: ok / stop(途中 STOP) / top(top_level 或断开的父链, 冒泡在那里停) / covered(命中的根本不在这个滚动框里)
##        / bar(滚动条本身) / exempt(输入框一类) / none(什么都没命中)
func _verdict(hit: Control, sc: ScrollContainer) -> Array:
	if hit == null:
		return ["none", null]
	if hit == sc:
		return ["ok", null]
	if not sc.is_ancestor_of(hit):
		return ["covered", hit]
	if _is_bar(sc, hit):
		return ["bar", hit]
	var c: Node = hit
	while c != sc:
		if c is Control:
			var cc := c as Control
			for ex in EXEMPT:
				if cc.is_class(ex):
					return ["exempt", cc]
			if cc.mouse_filter == Control.MOUSE_FILTER_STOP:
				return ["stop", cc]
			if cc.top_level:
				return ["top", cc]
		var par: Node = c.get_parent()
		if not (par is CanvasItem):
			return ["top", c]
		c = par
	return ["ok", null]


## 列表的「条目层」: 滚动内容往下穿过只有一个可见孩子的包装层。
func _list_root(sc: ScrollContainer) -> Node:
	var c: Node = null
	for ch in sc.get_children():
		if ch is Control and (ch as Control).visible:
			c = ch
			break
	var guard := 0
	while c != null and guard < 6:
		var vis: Array = c.get_children().filter(func(x) -> bool: return x is Control and (x as Control).visible)
		if vis.size() == 1:
			c = vis[0]
			guard += 1
		else:
			break
	return c


## 条目 = 条目层里**几何上**盖住这一点的那个孩子(条目自己 IGNORE 时命中的是列表容器, 不能按命中找)。
func _item_at(lr: Node, p: Vector2) -> Node:
	if lr == null:
		return null
	for ch in lr.get_children():
		if ch is Control and (ch as Control).visible and (ch as Control).get_global_rect().has_point(p):
			return ch
	return lr if (lr is Control and (lr as Control).get_global_rect().has_point(p)) else null


func _vert(sc: ScrollContainer) -> bool:
	return sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _bar(sc: ScrollContainer) -> ScrollBar:
	return sc.get_v_scroll_bar() if _vert(sc) else sc.get_h_scroll_bar()


func _range(sc: ScrollContainer) -> float:
	var b := _bar(sc)
	return maxf(0.0, b.max_value - b.page)


func _sval(sc: ScrollContainer) -> int:
	return sc.scroll_vertical if _vert(sc) else sc.scroll_horizontal


func _set_scroll(sc: ScrollContainer, v: float) -> void:
	if _vert(sc):
		sc.scroll_vertical = int(v)
	else:
		sc.scroll_horizontal = int(v)


func _hook_buttons(root: Node) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		if not (b as Node).has_meta("_sweep_hooked"):
			(b as Node).set_meta("_sweep_hooked", true)
			(b as BaseButton).pressed.connect(func() -> void: _taps += 1)


func _scrolls(root: Node) -> Array:
	var out: Array = []
	for s in root.find_children("*", "ScrollContainer", true, false):
		var sc := s as ScrollContainer
		if not sc.is_visible_in_tree() or sc.is_queued_for_deletion():
			continue
		var r := _vis_rect(sc)
		if r.size.x < 24.0 or r.size.y < 24.0:
			continue
		out.append(sc)
	return out


## 入场动画快进到底, 再等滚动框位置连续 3 帧不动(见头注「入场动画」)。返回是否稳住了。
func _settle(root: Node) -> bool:
	var last := ""
	var same := 0
	for _round in range(40):
		for tw in get_tree().get_processed_tweens():
			if tw.is_valid() and tw.is_running() and tw.get_loops_left() >= 0:
				tw.custom_step(5.0)
		await get_tree().process_frame
		var sig := ""
		for sc in _scrolls(root):
			sig += str((sc as Control).get_global_rect()) + str(_range(sc))
		if sig == last:
			same += 1
			if same >= 3:
				return true
		else:
			same = 0
			last = sig
	return false


# ─────────────────────────────── 扫 + 拖 ───────────────────────────────
## 量一屏。`want_live` = 这一屏至少要有几个**可滚**的滚动框(分母); `state` = 屏幕状态快照(拖完比对, 变了 = 拖成了点)。
## `only` 非空 = 只量路径里含这一段的滚动框(同一屏里别的弹框/列表另有一次量)。
func _audit(scr: String, root: Node, want_live: int, state: Callable = Callable(), only: String = "") -> void:
	_n_screens += 1
	var st := await _settle(root)
	var scs: Array = _scrolls(root)
	if only != "":
		scs = scs.filter(func(s) -> bool: return _path(root, s).contains(only))
	var live := 0
	for sc in scs:
		if _range(sc) >= float(MIN_SCROLL) + 20.0:
			live += 1
	print("── [%s] %s: 滚动框 %d 个(可滚 %d)%s" % [_tag, scr, scs.size(), live, "" if st else "  ⚠ 位置没稳住"])
	_ok("① [%s] %s 分母: 可滚的滚动框 ≥ %d" % [_tag, scr, want_live], live >= want_live, "可滚 %d / 共 %d" % [live, scs.size()])
	var ids: Array = scs.map(func(s) -> int: return (s as Object).get_instance_id())
	for id in ids:
		var sc := _alive(id) as ScrollContainer
		if sc == null or not is_instance_valid(root) or not root.is_inside_tree():
			break
		await _audit_sc(scr, root, sc, state)
	_hover_away()


func _audit_sc(scr: String, root: Node, sc: ScrollContainer, state: Callable) -> void:
	_n_sc += 1
	var sc_id := sc.get_instance_id()
	var scp := _path(root, sc)
	var rng := _range(sc)
	var live := rng >= float(MIN_SCROLL) + 20.0
	if live:
		_n_sc_live += 1
	## 看哪几屏: 0、每次往下 0.9 屏, 直到底(最多 MAX_POS 屏)
	var page: float = _bar(sc).page
	var poss: Array = [0.0]
	if rng > 1.0 and page > 1.0:
		var k := 1
		while k < MAX_POS and float(k) * page * 0.9 < rng:
			poss.append(float(k) * page * 0.9)
			k += 1
		if not poss.has(rng):
			poss.append(rng)
	var items := {}
	var pts := 0
	var stops := {}       # 键 → {n, pos, p, blk_sig, blk_mf, size, hit_sig, hit_path}
	var clean: Array = [] # [pos, p, hit_sig, hit_path, is_button, is_sc_itself]
	for pos in poss:
		sc = _alive(sc_id) as ScrollContainer
		if sc == null:
			return
		_set_scroll(sc, pos)
		await _frames(2)
		var lr := _list_root(sc)
		var view := _vis_rect(sc)
		if view.size.x < 8.0 or view.size.y < 8.0:
			continue
		var x := view.position.x + STEP * 0.5
		while x < view.end.x:
			var y := view.position.y + STEP * 0.5
			while y < view.end.y:
				var p := Vector2(x, y)
				var hit := _hover(p)
				var v := _verdict(hit, sc)
				var kind := str(v[0])
				if kind != "bar" and kind != "none":
					pts += 1
					var it := _item_at(lr, p)
					if it != null:
						items[it.get_instance_id()] = true
				if kind == "stop" or kind == "top" or kind == "covered":
					var blk: Node = v[1]
					var key := "%s | %s | %s %s" % [scr, scp, kind, _path(sc, blk) if sc.is_ancestor_of(blk) else _path(root, blk)]
					if not stops.has(key):
						stops[key] = {"n": 0, "pos": pos, "p": p, "blk_sig": _sig(blk),
							"blk_mf": (blk as Control).mouse_filter if blk is Control else -1,
							"size": (blk as Control).size if blk is Control else Vector2.ZERO,
							"hit_sig": _sig(hit), "hit_path": _path(root, hit)}
					stops[key]["n"] = int(stops[key]["n"]) + 1
				elif kind == "ok" and float(pos) == 0.0:
					clean.append([pos, p, _sig(hit), _path(root, hit), hit is BaseButton, hit == sc])
				y += STEP
			x += STEP
	_hover_away()
	_n_items += items.size()
	_n_points += pts
	var blocked := 0
	for k in stops:
		blocked += int(stops[k]["n"])
	var ns_key := "%s | %s" % [scr, scp]
	var no_scroll: bool = NO_SCROLL.has(ns_key)
	if no_scroll:
		_ok("② [%s] %s 设计上不滚, 真的不滚(豁免的前提; 可滚了 ⇒ 下面的拦截照常判红)" % [_tag, ns_key], rng < 1.0, "可滚 %.0fpx" % rng)
		no_scroll = rng < 1.0
	print("   · %s  可滚 %.0fpx · 看了 %d 屏 · 条目 %d · 采样点 %d · 拦截点 %d" % [scp, rng, poss.size(), items.size(), pts, blocked])
	if live:
		_ok("① [%s] %s 分母: %s 扫到了条目" % [_tag, scr, scp], items.size() > 0 and pts > 0, "条目 %d 点 %d" % [items.size(), pts])
	## ── 拖: 干净的(按命中的种类各挑一处, 按钮优先) ──
	sc = _alive(sc_id) as ScrollContainer
	if sc == null:
		return
	_set_scroll(sc, 0.0)
	await _frames(2)
	var picked: Array = []
	var seen_sig := {}
	var view0 := _vis_rect(sc)
	## 三轮: 先按钮(验「拖动取消点按」)、再条目上的别的控件、最后才是落在滚动框本身(内容全 IGNORE 时只有这一种)
	for want in ["btn", "item", "sc"]:
		for c in clean:
			if picked.size() >= 3:
				break
			var kind_c := "sc" if bool(c[5]) else ("btn" if bool(c[4]) else "item")
			if kind_c != want:
				continue
			if want == "sc" and not picked.is_empty():
				continue
			if seen_sig.has(str(c[2])):
				continue
			var p: Vector2 = c[1]
			## 起手点离顶(横向: 离左)留半个拖距, 离底留一点 —— 手指的路在列表里
			if _vert(sc) and (p.y < view0.position.y + DRAG_PX * 0.5 or p.y > view0.end.y - 12.0):
				continue
			if not _vert(sc) and (p.x < view0.position.x + DRAG_PX * 0.5 or p.x > view0.end.x - 12.0):
				continue
			seen_sig[str(c[2])] = true
			picked.append(c)
	if live:
		_ok("① [%s] %s 分母: %s 挑到了干净起手点" % [_tag, scr, scp], not picked.is_empty(), "%d 处" % picked.size())
		for c in picked:
			for pat in ["匀速", "快甩"]:
				var r: Dictionary = await _drag(root, sc_id, float(c[0]), c[1], str(c[3]), state, pat)
				if r.is_empty():
					_ok("③ [%s] %s 屏还在(拖完没被换掉)" % [_tag, scr], false)
					return
				var hs := str(c[2])
				_ok("③ [%s] ★%s 起手点命中的还是扫到的那一个(%s)" % [_tag, scp, hs], bool(r["same_hit"]), str(r["hit_now"]))
				if not bool(c[5]):
					_ok("④ [%s] 分母: 起手那一下真按在 %s 上(收到左键按下 %d 次)" % [_tag, hs, int(r["downs"])], int(r["downs"]) >= 1)
				## ★要「跟手」不是「动了」: 滚动只该落后手指一个死区(匀速 16 / 快甩 4), 不能半路断掉。
				##   第一版只要 ≥ 60 ⇒ 排行榜「手指按着的那一行一滚出窗口就被拆掉、拖动当场断掉」(160 只滚了 128)照样绿。
				var want_d: int = mini(int(DRAG_PX) - FOLLOW_SLACK, int(rng - float(c[0])))
				_judge("③ %s | %s | %s" % [scr, scp, hs], int(r["d"]) >= want_d and int(r["ev"]) > 0,
					"③ [%s] ★%s 手指按在 %s 上%s拖 %dpx ⇒ 列表跟着手指滚(≥ %d)且事件到了滚动框" % [_tag, scp, hs, pat, int(DRAG_PX), want_d],
					"Δ=%d 事件=%d" % [int(r["d"]), int(r["ev"])])
				_judge("④ %s | %s | %s" % [scr, scp, hs], int(r["taps"]) == 0 and bool(r["same"]),
					"④ [%s] ★%s 按在 %s 上%s拖的那一下不算点" % [_tag, scp, hs, pat],
					"pressed=%d 状态 %s" % [int(r["taps"]), "未变" if bool(r["same"]) else ("变了: %s → %s" % [r["s0"], r["s1"]])])
	## ── 拦截: 记账 + 每一种真拖一次(证据: 手指按在那里拖不动) ──
	for k in stops:
		var e: Dictionary = stops[k]
		var dr := {}
		if live and rng - float(e["pos"]) >= float(MIN_SCROLL) + 20.0:
			dr = await _drag(root, sc_id, float(e["pos"]), e["p"], str(e["hit_path"]), state, "匀速")
		var line := "%s  ×%d点  拦截者 %s(mouse_filter=%d 大小 %s) 命中 %s%s" % [k, int(e["n"]),
			str(e["blk_sig"]), int(e["blk_mf"]), str(e["size"]), str(e["hit_sig"]),
			("  实拖: Δ=%d 事件=%d pressed=%d" % [int(dr["d"]), int(dr["ev"]), int(dr["taps"])]) if not dr.is_empty() else "  (不可滚/余量不够, 未实拖)"]
		if no_scroll:
			print("  [不滚·豁免] [%s] %s   —— %s" % [_tag, line, NO_SCROLL[ns_key]])
		elif not _judge("② " + k, false, "② [%s] ★★拦截: %s" % [_tag, line], ""):
			_found[k + " @" + _tag] = line
		if not is_instance_valid(root) or not root.is_inside_tree():
			return


## 手指的两种走法(合计都是 DRAG_PX):
##   匀速 = 10 × 16px。
##   ★快甩 = 4px 起步、紧接着一大步 40px(手指加速)。ScrollContainer 过死区那一下把累计量重置成「最后一步」,
##     于是滚动只落后手指「过死区之前那一点」(这里 4px)⇒ 条目跟着手指走, 松手时**相对条目自己**的位移只有 4px。
##     拿条目自己的局部坐标判「位移小 = 点」的写法(< 14 / < 16)匀速时恰好躲过(落后 16), 快甩时必然误判成点。
const PATTERNS := {"匀速": [16, 16, 16, 16, 16, 16, 16, 16, 16, 16], "快甩": [4, 40, 40, 40, 36]}


## 判一条; 键里含 KNOWN 的某一条且这次没过 ⇒ 记作「已知」(打印、不算红)。返回 true = 是已知的那一种。
func _judge(key: String, cond: bool, name: String, detail: String) -> bool:
	var kn := ""
	for kk in KNOWN:
		if key.contains(str(kk)):
			kn = str(kk)
	if kn != "" and not cond:
		_known_seen[kn] = true
		print("  [KNOWN] %s   %s   —— %s" % [name, detail, KNOWN[kn]])
		return true
	_ok(name, cond, detail)
	return false


## 真拿手指在 p 拖一下。返回 {d: 松手前滚动量, ev: 到达滚动框的事件数, taps: 期间 pressed 次数, same: 屏幕状态没变,
##   same_hit: 起手点命中的还是扫到的那一个(按路径比: 排行榜一类滚动时会重建行)}。
func _drag(root: Node, sc_id: int, pos: float, p: Vector2, hit_path: String, state: Callable, pat: String) -> Dictionary:
	var sc := _alive(sc_id) as ScrollContainer
	if sc == null or not sc.is_inside_tree():
		return {}
	_set_scroll(sc, pos)
	await _frames(2)
	_hook_buttons(root)
	var s0 = state.call() if state.is_valid() else ""
	var t0 := _taps
	var hv := _hover(p)          # 鼠标先停在起手点上(手机上手指按下那一刻模拟鼠标也在这里)
	var hit_now := _path(root, hv) if hv != null else "null"
	var same_hit: bool = hit_now == hit_path
	## 起手那一下真按在命中的控件上了吗(按钮: button_down; 别的: 收到左键按下)。没按上 ⇒「拖的那一下不算点」是空检查。
	var downs := [0]
	var dcb := func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			downs[0] += 1
	if hv != null:
		hv.gui_input.connect(dcb)
	var ev := [0]
	var cb := func(_e: InputEvent) -> void: ev[0] += 1
	sc.gui_input.connect(cb)
	var v0 := _sval(sc)
	var dir := Vector2(0, -1) if _vert(sc) else Vector2(-1, 0)
	await _t_down(p)
	var walked := 0.0
	for stp in PATTERNS[pat]:
		walked += float(stp)
		await _t_move(p + dir * walked)
	sc = _alive(sc_id) as ScrollContainer
	var v1 := _sval(sc) if sc != null else v0
	await _t_up_freeze(sc)
	await _frames(2)
	_n_drags += 1
	sc = _alive(sc_id) as ScrollContainer
	if sc != null and sc.gui_input.is_connected(cb):
		sc.gui_input.disconnect(cb)
	if hv != null and is_instance_valid(hv) and hv.gui_input.is_connected(dcb):
		hv.gui_input.disconnect(dcb)
	if not is_instance_valid(root) or not root.is_inside_tree():
		return {}
	var s1 = state.call() if state.is_valid() else ""
	if sc != null:
		_set_scroll(sc, 0.0)
	## ★等排版把内容挪回去再交还: 滚动值是当场改的, 内容的位置要到下一次排版(延迟)才跟上 ——
	##   不等的话下一步按「看见的位置」点下去, 一帧之后那颗按钮就被挪走了(第一版「点一下仍是点」全红的真因:
	##   按下时按钮在 y=110, 下一帧回到 y=375, 手指那 2px 抖动已经落在按钮外, 引擎当然不算点)。
	await _frames(2)
	return {"d": v1 - v0, "ev": ev[0], "taps": _taps - t0, "same": str(s0) == str(s1), "s0": str(s0), "s1": str(s1),
		"same_hit": same_hit, "hit_now": hit_now, "downs": downs[0]}


# ─────────────────────────────── 主流程 ───────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	for k in KEYS:
		var v = GameState.get(k)
		_bak[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	OS.set_environment(SB.ENV_URL, " ")
	var em0: bool = Input.emulate_touch_from_mouse
	var em1: bool = Input.emulate_mouse_from_touch
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	GameState.test_mode = true
	GameState.tutorial_active = false
	await get_tree().process_frame
	_ok("分母: 触屏分支开着(ScrollContainer 走手指拖动)", DisplayServer.is_touchscreen_available())
	_ok("分母: 后端关着(不往外发请求)", not SB.enabled())
	for vp in [Vector2i(1280, 720), Vector2i(2340, 1080)]:
		get_tree().root.size = vp
		await _frames(3)
		_xf = get_tree().root.get_final_transform()
		_tag = "%d×%d" % [vp.x, vp.y]
		print("════════ %s ════════" % _tag)
		await _s_record()
		await _s_leaderboard()
		await _s_friends()
		await _s_codex()
		await _s_settings_blocklist()
		await _s_board(false)
		await _s_board(true)
		await _s_bracket()
		await _s_mainmenu()
		await _s_teamselect()
		await _s_inventory()
		await _s_shop()
		await _s_battle()
	for kn in KNOWN:
		_ok("⑤ KNOWN 仍复现(不复现 = 已修好, 把这一条从 KNOWN 删掉): %s" % kn, _known_seen.has(kn))
	## 还原
	Input.emulate_touch_from_mouse = em0
	Input.emulate_mouse_from_touch = em1
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	for k in KEYS:
		GameState.set(k, _bak[k])
	get_tree().root.size = Vector2i(1280, 720)
	print("")
	print("  分母: 屏 %d · 滚动框 %d(可滚 %d) · 条目 %d · 采样点 %d · 实拖 %d" % [_n_screens, _n_sc, _n_sc_live, _n_items, _n_points, _n_drags])
	print("  拦截 %d 种(不含 KNOWN)" % _found.size())
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	print("ALL PASS — 全游戏滚动列表手指能滑" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _open(path: String) -> Node:
	var inst: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	await _frames(4)
	return inst


func _close(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()
	get_tree().current_scene = self
	await _frames(3)


## ⑥ 改成 PASS / 松手才算点之后, **点一下仍然是点**: 手指真点那一块(按下 → 2px 抖动 → 抬起)。
##   先验命中测试真落在它(或它的子孙)上 —— 落在别处的点等于没测。返回 false = 没点到它。
func _tap_on(c: Control) -> bool:
	await _frames(2)
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return false
	var p: Vector2 = _vis_rect(c).get_center()
	var h := _hover(p)
	var on: bool = h != null and (h == c or c.is_ancestor_of(h))
	await _t_tap(p)
	await _frames(3)
	return on


func _first_visible(root: Node, nm: String, cls: String = "") -> Control:
	for c in root.find_children(nm, cls, true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion() \
				and _vis_rect(c as Control).size.y > 8.0:
			return c
	return null


# ─────────────────────────────── 各屏 ───────────────────────────────
## 战绩: 20 场, 每场都挂一个本机有录像的回放 id ⇒ 每张卡都有「观看」入口(整行热区 + 行尾签牌), 拖在它上面也要能滑。
##   录像文件只要「在」就出入口(`ReplayFetcher.has_replay` → local_available), 内容不读; 量完删掉。
func _s_record() -> void:
	var synth: Array = []
	var ids: Array = []
	DirAccess.make_dir_recursive_absolute("user://replays/")
	for i in range(20):
		var rid := "00000000-0000-4000-8000-%012d" % (900 + i)
		ids.append(rid)
		var f := FileAccess.open("user://replays/%s.rpl" % rid, FileAccess.WRITE)
		if f != null:
			f.store_buffer(PackedByteArray([0x78, 0x9c]))
			f.close()
		synth.append({"result": "win" if i % 2 == 0 else "lose", "lineup": ["basic", "fire", "ice"], "mode": "实时",
			"turn": 30 + i, "foe_name": "对手%02d" % i, "foe": ["stone", "ninja", "lava"], "replay_id": rid})
	GameState.match_history = synth
	var r := await _open("res://scenes/Record.tscn")
	_ok("① [%s] 战绩 分母: 每张卡都有「观看」入口" % _tag, r.find_children("ReplayBtn", "Button", true, false).size() >= 10,
		"%d 个" % r.find_children("ReplayBtn", "Button", true, false).size())
	await _audit("战绩", r, 1, func() -> String: return "%s|%s" % [str(r.get("last_replay_code")), str(get_tree().current_scene == r)])
	await _close(r)
	for rid in ids:
		DirAccess.remove_absolute("user://replays/%s.rpl" % rid)


func _s_leaderboard() -> void:
	BE.pool_override = {BE.POOL_KEY: {}}
	var r := await _open("res://scenes/Leaderboard.tscn")
	var leads := ["stone", "ninja", "phoenix", "lava", "pirate", "ice", "basic", "angel"]
	var rows: Array = []
	for i in range(40):
		rows.append({"rank": i + 1, "name": "排行龟%02d" % i, "tag": P2C.player_tag("uid-sw-%d" % i), "account_id": "uid-sw-%d" % i,
			"wins": 40 - i, "hearts": int(P2C.HEARTS_MAX) - (i % 3), "sweeps": 0, "battles": 14 + i, "title": "",
			"is_self": false, "lead": leads[i % leads.size()]})
	var me := {"rank": 41, "name": "我自己龟", "tag": BE.my_tag(), "account_id": "uid-sw-me", "wins": 0, "hearts": 3,
		"sweeps": 0, "battles": 11, "title": "", "is_self": true, "lead": "ice"}
	r.call("_render", rows, LB.SRC_SERVER, 41, me, 41)
	await _audit("排行榜", r, 1)
	await _close(r)
	BE.pool_override = {}


## 好友页: 假服务器回 20 个好友 + 6 个收到的申请 + 4 个发出的(两栏都要可滚)。形状照 verify_friends_flow。
func _fcard(acc: String, nm: String, lead: String) -> Dictionary:
	return {"account": acc, "name": nm, "tag": P2C.player_tag(acc), "lead": lead, "has_lineup": true,
		"updated_at": "2026-10-24T08:00:00.000+00:00"}


func _spy(_method, url, _headers, _body, cb) -> void:
	var fn := str(url).get_file()
	var out := {}
	match fn:
		"put_lineup":
			out = {"ok": true, "tag": P2C.player_tag("acct:sweepme")}
		"friend_list":
			out = {"ok": true, "tag": P2C.player_tag("acct:sweepme"), "friends": _friends, "incoming": _incoming,
				"outgoing": _outgoing, "cap": 100}
		_:
			cb.call({"ok": false, "code": 404, "body": ""})
			return
	cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})


func _s_friends() -> void:
	_friends = []
	_incoming = []
	_outgoing = []
	for i in range(20):
		_friends.append(_fcard("%08d-2222-4222-8222-222222222222" % i, "好友%02d" % i, "lava"))
	for i in range(6):
		_incoming.append(_fcard("%08d-4444-4444-8444-444444444444" % i, "申请%02d" % i, "ninja"))
	for i in range(4):
		_outgoing.append(_fcard("%08d-5555-4555-8555-555555555555" % i, "等待%02d" % i, "basic"))
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._token = "gate-token"
	SB._expires_at = 0
	SB._transport_for_test = _spy
	GameState.account_id = "11111111-1111-4111-8111-111111111111"
	GameState.season_leaders = ["ninja", "stone", "basic"]
	var r := await _open("res://scenes/Friends.tscn")
	await _frames(10)
	await _audit("好友", r, 2, func() -> String: return "%s|%s" % [str(r.get("_del_armed")), str(r.get("_busy"))])
	## ⑥ 点「删除」(两步确认的第一步: 只是把这一行武装起来, 不发请求)
	var fb: Node = r.find_child("Friends", true, false)
	var del := _first_visible(fb, "DelBtn", "Button") if fb != null else null
	var acc := ""
	if del != null:
		var row: Node = del
		while row != null and not row.has_meta("account"):
			row = row.get_parent()
		acc = str(row.get_meta("account")) if row != null else ""
	var hit_ok := await _tap_on(del)
	_ok("⑥ [%s] 好友 ★手指点「删除」仍是点(第一下武装这一行)" % _tag, hit_ok and acc != "" and str(r.get("_del_armed")) == acc,
		"命中=%s armed='%s' want='%s'" % [str(hit_ok), str(r.get("_del_armed")), acc])
	await _close(r)
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
	SB._transport_for_test = Callable()
	SB._token = ""


func _s_codex() -> void:
	var r := await _open("res://scenes/Codex.tscn")
	var rr = r
	for tab in ["pets", "equips", "synergies", "status"]:
		r.call("_switch_tab", tab)
		await _frames(4)
		## 选一条详情超高要滚的(技能卡 / 被动条 / 选档签牌这些热区都在详情滚动框里; 不滚就量不到手指拖它们)。
		##   找不到就退回第 4 条(状态页的详情本来就不滚)。
		var items: Array = r.get("_items")
		var pick := mini(3, items.size() - 1)
		for i in range(mini(items.size(), 40)):
			r.call("_select", i)
			await _frames(3)
			var ds: ScrollContainer = rr._detail_scroll
			if ds != null and _range(ds) >= float(MIN_SCROLL) + 40.0:
				pick = i
				break
		if not items.is_empty():
			r.call("_select", pick)
		await _frames(4)
		var want := 2 if (tab == "equips" or tab == "synergies") else 1
		await _audit("图鉴·%s" % tab, r, want, func() -> String: return "%s#%d|%s|%s" % [str(r.get("current_tab")), int(r.get("_sel_idx")),
			str(not (rr._codex_skill_detail as Dictionary).is_empty()), str(rr._codex_passive_view)])
		if tab == "pets":
			## ⑥ 点技能卡 / 普攻条 / 被动条(详情里那几块热区) ⇒ 仍进技能详情(或展开被动)
			var hit: Control = null
			for ch in (rr.detail as Node).get_children():
				if ch.get_class() == "Control" and not (ch as Control).gui_input.get_connections().is_empty() \
						and (ch as Control).size.x >= 150.0 and (ch as Control).size.y >= 34.0 and _vis_rect(ch as Control).size.y > 20.0:
					hit = ch
					break
			var on := await _tap_on(hit)
			await _frames(3)
			_ok("⑥ [%s] 图鉴 ★手指点详情里的热区(技能卡 / 普攻条 / 被动条)仍是点" % _tag,
				on and (not (rr._codex_skill_detail as Dictionary).is_empty() or bool(rr._codex_passive_view)),
				"命中=%s 技能详情=%s 被动展开=%s" % [str(on), str(not (rr._codex_skill_detail as Dictionary).is_empty()), str(rr._codex_passive_view)])
			## ⑥ 点列表里另一行 ⇒ 选中那一行
			var s0 := int(r.get("_sel_idx"))
			var row: Control = null
			for ch in r.find_children("*", "Panel", true, false):
				if (ch as Node).get_parent() != null and (ch as Node).get_parent().get_parent() == rr.list_vbox \
						and not (ch as Control).gui_input.get_connections().is_empty() and _vis_rect(ch as Control).size.y > 30.0:
					var rid: int = (ch as Node).get_parent().get_index()
					if rid > 2:
						row = ch
						break
			var on2 := await _tap_on(row)
			_ok("⑥ [%s] 图鉴 ★手指点列表行仍是点(换了选中)" % _tag, on2 and int(r.get("_sel_idx")) != s0,
				"命中=%s 选中 %d → %d" % [str(on2), s0, int(r.get("_sel_idx"))])
			## 被动展开 / 技能详情那一页正文更长: 再扫一遍(不要求可滚, 只验链)
			r.call("_select", 0)
			await _frames(3)
			rr._codex_passive_view = true
			rr._codex_detail._redraw()
			await _frames(4)
			await _audit("图鉴·pets·被动展开", r, 0)
		if tab == "equips":
			## 选档签牌: 换一件会升星的(052, 与 verify_codex_equip_star 同一件)
			for i in range(items.size()):
				if str((items[i] as Dictionary).get("id", "")) == "p2eq_052":
					r.call("_select", i)
			await _frames(4)
			await _settle(r)
			var star3: Control = _first_visible(r, "EqStarHit3")
			_ok("⑥ [%s] 图鉴 分母: 这件装备有选档签牌 ★3" % _tag, star3 != null)
			if star3 != null:
				var on3 := await _tap_on(star3)
				_ok("⑥ [%s] 图鉴 ★手指点选档签牌 ★3 仍是点" % _tag, on3 and int(rr._codex_detail._eq_star) == 3,
					"命中=%s 档=%d" % [str(on3), int(rr._codex_detail._eq_star)])
	await _close(r)


func _s_settings_blocklist() -> void:
	BL._reset_cache_for_test()
	for i in range(14):
		BL.add(P2C.player_tag("acct:blk%d" % i), "拉黑龟%02d" % i)
	var r := await _open("res://scenes/Settings.tscn")
	BLP.open(r as Control)
	await _frames(3)
	await _audit("设置·黑名单", r, 1, func() -> int: return BL.count())
	var n0 := BL.count()
	var on := await _tap_on(_first_visible(r, BLP.BTN_REMOVE, "Button"))
	_ok("⑥ [%s] 黑名单 ★手指点「移出」仍是点(少一个)" % _tag, on and BL.count() == n0 - 1, "命中=%s %d → %d" % [str(on), n0, BL.count()])
	await _close(r)
	BL.clear_all()


## 闯关赛况板。focus = 选中一个人(右栏顶上出「举报 / 拉黑」入口 + 他自己那几场)。
func _s_board(focus: bool) -> void:
	var rows: Array = []
	var n := 45
	for i in range(n):
		var j := (i + 1) % n
		var a := 0 if (focus and i < 12) else i
		var lp := {"name": "龟%02d" % a, "tag": P2C.player_tag("acct:sweep%d" % a), "avatar": "basic", "id": "g_x"}
		var rp := {"name": "龟%02d" % j, "tag": P2C.player_tag("acct:sweep%d" % j), "avatar": "basic", "id": "g_x"}
		rows.append({"match_id": "%08x-0000-4000-8000-%012x" % [i + 1, i + 1],
			"created_at": "2026-10-31T10:%02d:00+00:00" % (i % 60), "lp": lp, "rp": rp,
			"rw": (7 if (focus and a == 0) else i % 3), "rl": (2 if (focus and a == 0) else i % 2),
			"result": {"won": i % 2 == 0, "steps": 100, "surrendered": false, "gw": 1 + i % 4, "gl": i % 3}})
	var r := await _open("res://scenes/GauntletBoard.tscn")
	r.call("set_rows", rows)
	await _frames(3)
	if focus:
		r.call("_on_player_pressed", P2C.player_tag("acct:sweep0"))
		await _frames(3)
		_ok("① [%s] 赛况板·选中 分母: 右栏顶上有「举报 / 拉黑」入口" % _tag,
			not r.find_children("PlayerMenuEntry", "Button", true, false).is_empty())
	await _audit("赛况板%s" % ("·选中一人" if focus else ""), r, 1 if focus else 2,
		func() -> String: return "%s|%s|%s" % [str(r.get("focus_tag")), str(r.get("_busy")), str(r.get("last_replay_code"))])
	if focus:
		var on := await _tap_on(_first_visible(r, "PlayerMenuEntry", "Button"))
		_ok("⑥ [%s] 赛况板 ★手指点「举报 / 拉黑」仍是点(玩家菜单开了)" % _tag, on and r.get_node_or_null("PlayerMenuLayer") != null,
			"命中=%s" % str(on))
	await _close(r)


func _s_bracket() -> void:
	var r := await _open("res://scenes/BracketMap.tscn")
	if r.has_method("set_data"):
		r.call("set_data", {"size": 8, "round": 2, "me": 2,
			"names": ["甲龟", "乙龟", "丙龟", "丁龟", "戊龟", "己龟", "庚龟", "辛龟"],
			"done": {"1:0": 0, "1:1": 1, "1:2": 0, "1:3": 1}}, {}, 1789862400 + 19 * 3600)
	await _audit("对阵图", r, 0)
	await _close(r)


func _s_mainmenu() -> void:
	var r := await _open("res://scenes/MainMenu.tscn")
	await _frames(10)
	await _audit("主菜单", r, 0)
	await _close(r)


## 选龟: 龟池卡片在桌面上挂着原生拖放(拖进编队槽), 手机上不挂(`SafeArea.is_mobile()`, pet_grid.gd)。
##   原生拖放一启动就接管手指 ⇒ 桌面上量到的是「拖起来了」不是「滑列表」。⇒ 照手机那样把卡片的拖放摘掉再量。
## ★点一张卡会把阵容草稿写进 `user://team_draft.json`(不看 test_mode)⇒ 开之前清掉(两种比例都从空阵容起步, 拖成了点才看得出来),
##   量完原样还回去(门禁本来就给每个测试一份独立 user://, 这里是给单跑的人兜底)。
const TEAM_DRAFT := "user://team_draft.json"


func _s_teamselect() -> void:
	GameState.season_leaders = []
	var had_draft := FileAccess.file_exists(TEAM_DRAFT)
	var draft0 := FileAccess.get_file_as_string(TEAM_DRAFT) if had_draft else ""
	if had_draft:
		DirAccess.remove_absolute(TEAM_DRAFT)
	var r := await _open("res://scenes/TeamSelect.tscn")
	await _frames(6)
	var n_cards := 0
	for c in r.find_children("*", "Control", true, false):
		if (c as Node).has_meta("pet_id"):
			(c as Control).set_drag_forwarding(Callable(), Callable(), Callable())
			n_cards += 1
	_ok("① [%s] 选龟 分母: 龟池卡片照手机摘掉了原生拖放(%d 张)" % [_tag, n_cards], n_cards >= 20)
	## 拖成了点看「阵容 + 右栏详情」: 开局阵容是空的、详情不是被按的那一只 ⇒ 一被误判成点, 那只龟就进了阵容、详情换过去。
	await _audit("选龟", r, 1, func() -> String: return "%s|%s" % [str(r.get("team")), str(r.get("detail_pet_id"))])
	await _close(r)
	if had_draft:
		var f := FileAccess.open(TEAM_DRAFT, FileAccess.WRITE)
		if f != null:
			f.store_string(draft0)
			f.close()
	elif FileAccess.file_exists(TEAM_DRAFT):
		DirAccess.remove_absolute(TEAM_DRAFT)


func _inv_state(r: Node) -> String:
	var dr = r.get("_drag")
	return "%d|%s|%s|%s" % [int(r.get("_sel_bench")), str(r.get("_sel_jar")), str(r.get("_sel_worn")),
		str(dr.dragging) if dr != null else ""]


## 背包种子 + 统领身上装满**不同羁绊**的装备(一种一件) ⇒ 下面那条羁绊横条超出一屏、要横着滑。
func _inv_seed_many_types() -> void:
	INV_SEED.run()
	GameState.season_level = 30
	var seen := {}
	var picks: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid := str((e as Dictionary).get("id", ""))
		var ts: Array = Phase2Types.types_of(eid)
		if ts.size() != 1 or seen.has(str(ts[0])) or eid == AXE:
			continue
		seen[str(ts[0])] = true
		picks.append({"id": eid, "star": 1})
	var leaders: Array = GameState.season_leaders
	GameState.persistent_equipped = {}
	for i in range(leaders.size()):
		GameState.persistent_equipped[str(leaders[i])] = picks.slice(i * 3, i * 3 + 3)


func _s_inventory() -> void:
	_inv_seed_many_types()
	var ids := ["p2eq_001", "p2eq_004", "p2eq_005", "p2eq_007", "p2eq_009", "p2eq_011", "p2eq_013", "p2eq_014"]
	for i in range(60):
		GameState.persistent_bench.append({"id": ids[i % ids.size()], "star": (i % 3) + 1})
	var r := await _open("res://scenes/Inventory.tscn")
	await _frames(6)
	await _audit("背包", r, 2, func() -> String: return _inv_state(r))
	## ⑥ 点背包里一件装备 ⇒ 选中它
	var cell: Control = null
	for c in r.find_children("*", "Panel", true, false):
		var par: Node = (c as Node).get_parent()
		## 装备格 = 挂着「名字 ★星 费」那段说明的格子(产品自己写的 tooltip, 不是测试加的标记)
		if par != null and par.get_parent() is ScrollContainer and str((c as Control).tooltip_text).begins_with("[b]") \
				and _vis_rect(c as Control).size.y > 40.0:
			cell = c
			break
	var on := await _tap_on(cell)
	_ok("⑥ [%s] 背包 ★手指点一件装备仍是点(选中)" % _tag, on and int(r.get("_sel_bench")) >= 0, "命中=%s 选中=%d" % [str(on), int(r.get("_sel_bench"))])
	await _close(r)
	## ⑥ 点羁绊条里的一块 ⇒ 弹羁绊详情
	_inv_seed_many_types()
	r = await _open("res://scenes/Inventory.tscn")
	await _frames(6)
	await _settle(r)
	var chip: Control = null
	for c in r.find_children("*", "Panel", true, false):
		if str((c as Control).tooltip_text).begins_with("查看羁绊详情") and _vis_rect(c as Control).size.x > 60.0:
			chip = c
			break
	var on2 := await _tap_on(chip)
	_ok("⑥ [%s] 背包 ★手指点羁绊条仍是点(弹出羁绊详情)" % _tag, on2 and r.find_child("SynergyPopupScroll", true, false) != null, "命中=%s" % str(on2))
	## 装备详情(小木斧全文 ⇒ 正文要滚)
	r.call("_show_equip_detail", {"id": AXE, "star": 3})
	await _frames(6)
	await _audit("背包·装备详情", r, 1, Callable(), "EquipDetailScroll")
	await _close(r)
	## 说明小卡超长 ⇒ 卡内滚动(verify_inspect_card_hosts ③ 同一个探针卡)
	INV_SEED.run()
	r = await _open("res://scenes/Inventory.tscn")
	await _frames(6)
	var lines := PackedStringArray()
	for k in range(40):
		lines.append("探针第 %d 行" % k)
	var rr = r
	rr._insp.open("probe:tall", null, {"title": "探针长卡", "body": "\n".join(lines), "width": rr.ITEM_CARD_W, "min_px": rr.MIN_FONT_PX})
	await _frames(8)
	await _audit("背包·说明小卡", r, 1, Callable(), InspectCard.N_SCROLL)
	await _close(r)
	## 羁绊弹框(正文超长才滚; 不要求可滚, 只验链)
	INV_SEED.run()
	r = await _open("res://scenes/Inventory.tscn")
	await _frames(6)
	var syn = r.get("_inv_synergy")
	syn._show_synergy_popup("剑", 1)
	await _frames(6)
	await _audit("背包·羁绊弹框", r, 0, Callable(), "SynergyPopupScroll")
	await _close(r)


func _shop_seed() -> void:
	GameState.test_mode = true
	GameState.tutorial_active = false
	GameState.meta_deepsea_coins = 999
	GameState.season_level = 5
	GameState.season_xp = 0
	GameState.season_total_battles = 3
	GameState.meta_shop_locked = false
	GameState.persistent_bench = []
	GameState.persistent_equipped = {}
	GameState.axe_exp_bar = 0
	GameState.axe_exp_total = 0
	GameState.axe_stage = 0
	GameState.axe_final = ""
	GameState.equip_pool = {}
	GameState.season_leaders = ["basic", "stone", "ninja"]
	GameState.candy_jar_count = 0
	var offer: Array = []
	for _i in range(10):
		offer.append({"id": AXE})
	GameState.meta_shop_offer = offer
	GameState.meta_shop_battles = int(GameState.season_total_battles)


## 商店: 点货架第 0 格(小木斧) ⇒ 说明卡正文超高 ⇒ 卡内滚动框(CardBodyScroll)。
func _s_shop() -> void:
	_shop_seed()
	var r := await _open("res://scenes/Shop.tscn")
	await _frames(3)
	r.call("_rebuild")
	await _frames(4)
	await _settle(r)
	var cell: Control = null
	for c in r.find_children("ShelfItem0", "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion():
			cell = c
	_ok("① [%s] 商店 分母: 货架第 0 格在" % _tag, cell != null)
	if cell != null:
		await _t_tap(cell.get_global_rect().get_center())
		await _frames(8)
	await _audit("商店·说明卡", r, 1, Callable(), "CardBodyScroll")
	await _close(r)


## 战斗: 结算屏(双路 8 行 + 上路 8 只召唤物 ⇒ 队伍表要滚)+ 点龟出的信息面板(设计上不滚, 只验链)。
func _st_row(id: String, nm: String, d: int, summon := false) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": summon, "_st_multi": summon, "rarity": "C",
		"alive": d % 2 == 0, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": 500, "_st_heal": 0, "_st_crit": 0, "_st_kills": 0,
		"_st_shield": 0, "_st_dealt_by_type": {"phy": d - d / 3 - d / 10, "mag": d / 3, "tru": d / 10}}


func _st_hist() -> Array:
	var out: Array = []
	for lane in ["top", "bottom"]:
		var snap := {"lane": lane}
		for side in ["left", "right"]:
			var rows: Array = []
			for pid in ["stone", "bamboo", "hunter"]:
				rows.append(_st_row(pid, pid, 900))
			rows.append(_st_row("egg", "龟蛋", 0))
			rows.append(_st_row("trainer", "训龟大师", 40))
			if lane == "top" and side == "left":
				for i in range(8):
					rows.append(_st_row("_summon_turret", "炮台", 60 + i, true))
			snap[side] = rows
		out.append(snap)
	return out


func _s_battle() -> void:
	var s: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(s)
	get_tree().current_scene = s
	await _frames(30)
	s.set_process(false)
	s.set_physics_process(false)
	## 信息面板(点龟)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("stone", "left", c)
	s._hud._show_unit_info_panel(u)
	await _frames(6)
	await _audit("战斗·信息面板", s, 0)
	s._hud._close_info_panel()
	await _frames(3)
	## 结算屏
	if s._hud._settle != null and is_instance_valid(s._hud._settle):
		s._hud._settle.queue_free()
	await _frames(2)
	s._st_lane_hist = _st_hist()
	s._units.clear()
	GameState.dual_active = true
	GameState.lane_results = {"top": "right", "bottom": "left"}
	GameState.finals_pending_reveal = {}
	s._settled = false
	s._hud._show_banner(true)
	await _frames(12)
	var st = s._hud._settle
	_ok("① [%s] 结算屏 分母: 建出来了、三页" % _tag, st != null and is_instance_valid(st) and (st.pages as Array).size() == 3)
	if st != null and is_instance_valid(st):
		for pg in [1, 2]:
			st.show_page(pg)
			await _frames(4)
			await _audit("战斗·结算屏第%d页" % (pg + 1), s, 1 if pg == 1 else 0,
				func() -> String: return "%d|%s" % [int(st.cur_page) if is_instance_valid(st) else -1, str(get_tree().current_scene == s)])
	await _close(s)
