extends Node
## _probe_ig_scrollreach.gd — 结算屏【到底有几行永远看不到】。
##
## ══════════════════════════════════════════════════════════════════════
##  用户原话(2026-09-29):「每场打完后结算界面能下滑吗, 不能啊, 有很多单位看不到啊」
## ══════════════════════════════════════════════════════════════════════
##
## 这支探针不推理, 只干三件事:
##   ① 造一份长名单 → 开结算;
##   ② 把**每一个** ScrollContainer 都推到它自己的滚动极限(能滚的都滚到底);
##   ③ 对每一行名字 Label, 算它的矩形是否落在【全部祖先 clip_contents 矩形的交集】里。
##     —— 落不进去 = 玩家怎么滑都看不到。
##
## ★为什么要算"祖先 clip 的交集"而不是只看一个容器:
##   结算卡是**两层嵌套** ScrollContainer(外层卡片 + 内层战报表)。
##   内层自己以为有 400px 视口, 可它的下沿被外层的 clip 裁在半路 ⇒
##   内层滚到底, 最后那几行仍然被裁在外层的边界外面。
##   只看某一个容器的 `v_max - v_page` 会得出"能滚啊"的假结论。
##
## ★同时用引擎自己的命中测试回答「玩家的手指能摸到哪个滚动容器」——
##   不自己写"找最上层"(memory [[fb-hand-rolled-copies-drift]])。
##
## 跑法:
##   IG_UNITS=14 IG_W=1280 IG_H=720 APPDATA=<私有> NO_SAVE=1 SHIP=1 TURTLE_SUPABASE=" " \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_ig_scrollreach.tscn --quit-after 2600

const SCENE_BATTLE := "res://scenes/RealtimeBattle3D.tscn"


func _ready() -> void:
	await get_tree().process_frame
	var w: int = int(OS.get_environment("IG_W")) if OS.get_environment("IG_W") != "" else 1280
	var h: int = int(OS.get_environment("IG_H")) if OS.get_environment("IG_H") != "" else 720
	get_tree().root.content_scale_size = Vector2i(w, h)
	get_tree().root.size = Vector2i(w, h)
	for _q in range(4):
		await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var sc = load(SCENE_BATTLE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	var per: int = int(OS.get_environment("IG_UNITS")) if OS.get_environment("IG_UNITS") != "" else 14
	var made := 0
	for side in ["left", "right"]:
		for k in range(per):
			var u = sc._spawn._make_unit("green", side, sc.ARENA.position + sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if u is Dictionary:
				u["_st_dealt"] = 1000 + 137 * k
				u["_st_taken"] = 500 + 91 * k
				u["_st_heal"] = 40 * k
				u["_st_kills"] = k % 3
				if not sc._arr_has_unit(sc._units, u):
					sc._units.append(u)
				made += 1
	for _i in range(8):
		await get_tree().process_frame
	sc._hud._show_banner(true)
	var _t := 0.0
	while _t < 1.2:
		await get_tree().process_frame
		_t += get_process_delta_time()
	for _i in range(20):
		await get_tree().process_frame

	var vp: Vector2 = sc.get_viewport().get_visible_rect().size
	print("")
	print("══════════ 视口 %s · 名单 %d 单位(造 %d) ══════════" % [str(vp), sc._units.size(), made])

	# ── 找结算卡 ───────────────────────────────────────────────────
	var shell: Control = _find_shell(sc._ui_layer)
	if shell == null:
		print("  结算卡没建出来 —— 本轮不算数(分母 0)")
		get_tree().quit(1)
		return
	print("  结算卡 shell rect=%s   视口内? %s"
		% [str(shell.get_global_rect()),
		   str(shell.get_global_rect().position.y >= 0.0 and shell.get_global_rect().end.y <= vp.y)])

	# ── 全部 ScrollContainer: 先记"滚之前", 再全部推到底 ────────────
	var scrolls: Array = []
	_collect(shell, "ScrollContainer", scrolls)
	print("  卡内 ScrollContainer 共 %d 个" % scrolls.size())
	for s in scrolls:
		var sco: ScrollContainer = s
		var vb: VScrollBar = sco.get_v_scroll_bar()
		print("    [滚前] %s rect=%s  v_max=%.0f v_page=%.0f 可滚=%.0f  条可见=%s 条宽=%.0fpx"
			% [sco.name, str(sco.get_global_rect()), vb.max_value, vb.page,
			   maxf(0.0, vb.max_value - vb.page), str(vb.visible), vb.size.x])
	# ── ★把"滚到底"改成"穷举滚动组合" ───────────────────────────────
	## 第一版只推到底就数不可见行, 数出"6 行看不到" —— **那是假的**:
	## 滚到底时看不见的正是被滚上去的**顶部**那几行, 任何能滚的列表都这样。
	## 真问题是「有没有哪一行, 在**任何**滚动组合下都看不全」⇒ 必须取并集。
	var grids: Array = []
	_collect(shell, "GridContainer", grids)
	var rows_of: Dictionary = {}          ## grid -> [HBox...]
	for g in grids:
		var rs: Array = []
		for ch in (g as Node).get_children():
			if ch is HBoxContainer:
				rs.append(ch)
		if not rs.is_empty():
			rows_of[g] = rs
	print("  找到 %d 张表(GridContainer), 其中 %d 张有行" % [grids.size(), rows_of.size()])
	var ever: Dictionary = {}             ## 行 -> 至少一次完整可见
	var states: Array = []
	var o_max := 0
	var i_max := 0
	if scrolls.size() >= 1:
		var b0: VScrollBar = (scrolls[0] as ScrollContainer).get_v_scroll_bar()
		o_max = int(maxf(0.0, b0.max_value - b0.page))
	if scrolls.size() >= 2:
		var b1: VScrollBar = (scrolls[1] as ScrollContainer).get_v_scroll_bar()
		i_max = int(maxf(0.0, b1.max_value - b1.page))
	print("  可滚量: 外层卡片 %d px / 内层战报 %d px" % [o_max, i_max])
	var oset: Array = [0, o_max]
	var iset: Array = []
	var iv := 0
	while iv <= i_max:
		iset.append(iv)
		iv += 12
	if not iset.has(i_max):
		iset.append(i_max)
	for ov in oset:
		for ivv in iset:
			if scrolls.size() >= 1:
				(scrolls[0] as ScrollContainer).scroll_vertical = ov
			if scrolls.size() >= 2:
				(scrolls[1] as ScrollContainer).scroll_vertical = ivv
			await get_tree().process_frame
			await get_tree().process_frame
			var nvis := 0
			var ntot := 0
			for g in rows_of.keys():
				var clip: Rect2 = _clip_rect(g, vp)
				for r in (rows_of[g] as Array):
					ntot += 1
					if clip.encloses((r as Control).get_global_rect()):
						nvis += 1
						ever[r] = true
			states.append({"o": ov, "i": ivv, "vis": nvis, "tot": ntot})
	var first: Dictionary = states[0]
	print("  ★【刚进结算屏, 一下都没滑】%d 行里看得全 %d 行 ⇒ 看不到 %d 行"
		% [first["tot"], first["vis"], int(first["tot"]) - int(first["vis"])])
	var best: Dictionary = states[0]
	for st in states:
		if int(st["vis"]) > int(best["vis"]):
			best = st
	print("  ★【最好的那个滚动组合】外层=%d 内层=%d ⇒ 一屏最多看得全 %d / %d 行"
		% [best["o"], best["i"], best["vis"], best["tot"]])
	var tot2 := 0
	var never: Array = []
	for g in rows_of.keys():
		for r in (rows_of[g] as Array):
			tot2 += 1
			if not ever.has(r):
				var nm := ""
				for ch in (r as Node).get_children():
					if ch is Label:
						nm = (ch as Label).text
						break
				never.append(nm)
	print("  ★★【穷举 %d 种滚动组合后, 一次都没完整露出过的行】%d / %d  %s"
		% [states.size(), never.size(), tot2, str(never).substr(0, 300)])
	var only_inner := 0
	var oi: Dictionary = {}
	for st in states:
		if int(st["o"]) == 0 and int(st["vis"]) > only_inner:
			only_inner = int(st["vis"]); oi = st
	print("  ★【只滑内层战报(外层没滚动条, 玩家未必知道能拖)】最多 %d / %d 行, 组合 %s"
		% [only_inner, tot2, str(oi)])
	## 复位, 让下面的命中测试在"刚进屏"的状态下量
	for s2 in scrolls:
		(s2 as ScrollContainer).scroll_vertical = 0
	await get_tree().process_frame

	# ── 玩家的手指摸到哪个容器: 引擎命中测试 ─────────────────────────
	print("  ── 命中测试: 卡上竖着扫一列点, 看引擎把事件交给谁 ──")
	var vpt: Viewport = sc.get_viewport()
	var cx: float = shell.get_global_rect().get_center().x
	var y0: float = shell.get_global_rect().position.y
	var y1: float = shell.get_global_rect().end.y
	var yy: float = y0 + 6.0
	while yy < y1:
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(cx, yy)
		mm.global_position = mm.position
		vpt.push_input(mm)
		await get_tree().process_frame
		var hov: Control = vpt.gui_get_hovered_control()
		var owner_sc := "—"
		var p: Node = hov
		while p != null:
			if p is ScrollContainer:
				owner_sc = str(p.name)
				break
			p = p.get_parent()
		print("     y=%4.0f → %-26s (%s)   所属滚动容器: %s"
			% [yy, (hov.name if hov != null else "<null>"),
			   (hov.get_class() if hov != null else "-"), owner_sc])
		yy += 40.0
	get_tree().quit(0)


## 全部祖先 clip_contents 矩形的交集(含自己所在滚动容器与视口)
func _clip_rect(c: Control, vp: Vector2) -> Rect2:
	var r := Rect2(Vector2.ZERO, vp)
	var p: Node = c
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _collect(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children(true):
		_collect(c, cls, out)


func _find_shell(n: Node) -> Control:
	## 结算卡 = CenterContainer 下那个 PanelContainer
	for c in n.get_children():
		if c is CenterContainer:
			for d in (c as Node).get_children():
				if d is PanelContainer:
					return d
	return null
