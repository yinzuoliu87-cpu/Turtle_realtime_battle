extends Node
## UI 布局审计器 —— 在指定视口尺寸下实例化一个界面, 【量真实 Control 的 get_global_rect()】。
##
## 用户 2026-08-01:「不只是甩在外面，而是有些画面都没有居中」
##
## ★为什么不用截图+颜色判据: 我试过, 背景平铺的暗斑会被算成内容、两个颜色判据还会命中同一块,
##   量出来的"内容边界"根本不可信 —— 那是在用像素猜。引擎给的 rect 才是事实。
##   (同一条教训在 HUD 按钮那次也吃过: 用公式模拟矩形 → 把按钮改回写死坐标照样全绿。)
##
## 报三样:
##   ① 溢出: 哪些可见 Control 的 global_rect 超出视口(左/右/上/下各多少)
##   ② 居中: 全部可见内容的包围盒中心 vs 视口中心, 差多少
##   ③ 触控热区: 可点元素(按钮/有 pressed 信号的)里, 短边 < 44px 的(iOS HIG 44pt / Material 48dp)
##
## 跑法: UI_SCENE=MainMenu <godot> --path . res://tests/_probe_ui_layout.tscn --resolution 960x720

## 手机上的最小可点尺寸, 单位是【视口像素】不是 pt —— 这个换算我第一版就搞错了, 直接拿 44 当阈值。
##
## 换算: iPhone 14 横屏逻辑尺寸 844×390 pt, 而视口高恒为 720(expand 锁高) →
##       1 pt = 720/390 = 1.846 视口像素 ⇒ iOS HIG 的 44pt = 【81 视口像素】。
##       Android: 典型横屏 ~411dp 高 → 720/411 = 1.75 px/dp ⇒ Material 48dp = 84 视口像素。
## 取两者中较宽松的 81 当红线(短边)。
## ★拿 44 当阈值 = 实际只要求了 24pt, 会把一堆手指点不着的元素判成合格。
const SMALL_TAP := 81.0
## 严重档: 短边不到红线一半(=22pt 以下), 手指基本点不中, 优先修。
const TINY_TAP := 40.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var scn := OS.get_environment("UI_SCENE")
	if scn == "":
		scn = "MainMenu"
	var path := "res://scenes/%s.tscn" % scn
	if not ResourceLoader.exists(path):
		print("[UI] 场景不存在 %s" % path); get_tree().quit(1); return
	var inst = (load(path) as PackedScene).instantiate()
	add_child(inst)
	var _t0 := Time.get_ticks_msec()
	for _i in range(360):
		await get_tree().process_frame

	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var nodes: Array = []
	_walk(inst, nodes)
	var bb := Rect2()
	var have := false
	var over: Array = []
	var tiny: Array = []
	for n in nodes:
		var c := n as Control
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		# ★跳过【满铺背景/遮罩层】: 菜单背景是故意做成 视口+512 的平铺图(MainMenuScene._on_menu_resize),
		#   算进来会既污染包围盒又刷屏"溢出" —— 我第一版 64 条溢出里绝大多数是它。
		#   ★这段必须在 merge 之前 —— 我第二版插到了 merge 后面, 包围盒照样被撑成 -561~2544。
		if r.size.x * r.size.y >= vp.x * vp.y * 0.95:
			continue
		# ★跳过【设计框本身】: UIFrame 建的 1280×720 容器是"内容装在哪"的骨架, 不是内容。
		#   不排掉的话它会主导包围盒 —— 大视口下它不再算满铺, 于是每屏都报"偏移 +0"(因为量到的是
		#   居中的框而不是内容)。这已经是本次第四个测量假象了, 排掉才看得见真实构图。
		if c.name == "DesignFrame":
			continue
		if not have:
			bb = r; have = true
		else:
			bb = bb.merge(r)
		var l: float = -r.position.x
		var t: float = -r.position.y
		var rr: float = r.end.x - vp.x
		var bo: float = r.end.y - vp.y
		# ★跳过【被裁区里的内容】: ScrollContainer / clip_contents 的子节点本来就该超出父容器,
		#   那是滚动, 不是溢出。图鉴一屏 88 条"溢出"全是这个 —— 不排掉的话真问题一条都看不见。
		if _in_clipped(c, inst):
			continue
		if maxf(maxf(l, t), maxf(rr, bo)) > 1.0:
			over.append("%s(%s) 超出 左%.0f 右%.0f 上%.0f 下%.0f  尺寸%.0fx%.0f" % [
				String(inst.get_path_to(c)), c.get_class(),
				maxf(0, l), maxf(0, rr), maxf(0, t), maxf(0, bo), r.size.x, r.size.y])
		if _clickable(c):
			var short: float = minf(r.size.x, r.size.y)
			if short < SMALL_TAP:
				tiny.append("%s%s(%s) %.0f×%.0f = 短边 %.0fpt" % [
					"★严重 " if short < TINY_TAP else "",
					String(inst.get_path_to(c)), _btn_text(c), r.size.x, r.size.y, short / 1.846])

	print("[UI] === %s @ %dx%d ===" % [scn, int(vp.x), int(vp.y)])
	print("[UI] 可见 Control %d 个" % nodes.size())
	if have:
		var cx: float = bb.position.x + bb.size.x * 0.5
		print("[UI] 内容包围盒 x %.0f~%.0f (中心 %.0f) · 视口中心 %.0f · 偏移 %+.0f"
			% [bb.position.x, bb.end.x, cx, vp.x * 0.5, cx - vp.x * 0.5])
	print("[UI] 溢出视口的节点: %d" % over.size())
	for o in over.slice(0, 8):
		print("[UI]    " + o)
	print("[UI] 触控热区 < %dpx 的可点元素: %d" % [int(SMALL_TAP), tiny.size()])
	for t2 in tiny.slice(0, 8):
		print("[UI]    " + t2)
	get_tree().quit(0)


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if c.visible and c.get_combined_minimum_size() != null:
			# 只收【自己画东西】的叶子/面板, 跳过纯容器(容器铺满会把包围盒撑成全屏, 掩盖真实构图)
			if not (c is Container) and not (c is MarginContainer):
				out.append(c)
	for ch in n.get_children():
		if ch is Node:
			_walk(ch, out)


## 有没有【会裁剪的祖先】(ScrollContainer 或 clip_contents=true)。有就说明它是滚动内容, 超出是正常的。
func _in_clipped(c: Control, root: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer:
			return true
		if p is Control and (p as Control).clip_contents:
			return true
		p = p.get_parent()
	return false


func _btn_text(c: Control) -> String:
	if c is Button:
		var t: String = (c as Button).text
		return t if t != "" else c.get_class()
	return c.get_class()


func _clickable(c: Control) -> bool:
	if c is BaseButton:
		return true
	return c.mouse_filter == Control.MOUSE_FILTER_STOP and c.has_signal("gui_input") \
		and c.get_signal_connection_list("gui_input").size() > 0
