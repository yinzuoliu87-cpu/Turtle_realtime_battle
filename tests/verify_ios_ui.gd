extends Node
## verify_ios_ui.gd — iOS 测试包前自检守卫(用户 2026-07-16「打包之前确认: 调试场能点击到/能测所有龟和装备/按钮不超屏不卡住」)
##
## 断言(布局功能层, 观感仍需真机眼验):
##   A. iPhone 横屏画布(1560×720 ≈ 2.167:1)下: 全部菜单 scene 的可见按钮 rect ⊆ 屏幕
##   B. 主菜单有「🛠 调试场」按钮(debug 构建), 按下把 DEBUG_EDIT 打开
##   C. 调试场编辑器: 摆位面板建齐(可选龟覆盖全 28 只)且面板按钮 rect ⊆ 屏幕
##   D. 正常战斗 HUD(REVIEW_DEMO_DEFAULT=false): 暂停/日志等按钮 rect ⊆ 屏幕
##   E. iPad 4:3 画布(1280×960)复检 A(主菜单+调试场面板)
## 匹配按档位匹快照由 tests/verify_ghost_seed 独立守卫(9档全覆盖)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MENU_SCENES := ["MainMenu", "Matchmaking", "TeamSelect", "Inventory", "Shop", "Codex", "Settings", "Leaderboard", "Record"]

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _visible_buttons(n: Node, out: Array) -> void:
	if n is BaseButton and (n as Control).is_visible_in_tree():
		out.append(n)
	for ch in n.get_children():
		_visible_buttons(ch, out)

## 递归收集可见 Button/Label 文本(选龟卡=按钮+名字Label 组合, 光看Button text不够)
func _all_texts(n: Node) -> String:
	var s := ""
	if n is Button and (n as Control).is_visible_in_tree():
		s += str((n as Button).text) + "|"
	elif n is Label and (n as Control).is_visible_in_tree():
		s += str((n as Label).text) + "|"
	for ch in n.get_children():
		s += _all_texts(ch)
	return s

## 按钮是否在 ScrollContainer 内(滚动可达→不算越界; 弹窗网格cards裁剪待滚是正常态)
func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

## 按钮 rect 是否全在屏幕内(容差2px); 返回越界按钮描述列表
func _offscreen_buttons(root: Node, vp: Vector2) -> Array:
	var btns: Array = []
	_visible_buttons(root, btns)
	var bad: Array = []
	var screen := Rect2(Vector2(-2, -2), vp + Vector2(4, 4))
	for b in btns:
		if _in_scroll(b):
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		if not screen.encloses(r):
			bad.append("%s(%s) rect=%s" % [b.name, (b as Button).text.left(8) if b is Button else "-", str(r)])
	return bad

## 按钮是否被【后画的兄弟节点】盖住 —— 返回被遮的按钮描述列表.
##
## 为什么单查"在屏内"不够(用户2026-07-19「移动端选龟界面的返回键被遮住」):
## 选龟页的返回/清空/上次是在 slotBay/网格/详情区之【前】add_child 的, 手机比例下这几个按钮会被
## 夹边逻辑从屏外拉回 y≈6, 正好落进随后才画的面板矩形里. rect ⊆ 屏幕 → 老断言全绿, 但手指点不到。
##
## 判据: 同一 CanvasItem 父链下, 索引比按钮【大】(=画在上面)且不透明(modulate.a>0.05)的 Control,
## 若其 rect 与按钮 rect 的重叠面积 ≥ 按钮面积的 25%, 且它本身不是按钮的祖先/后代 → 判为遮挡。
##
## ★用【面积重叠】而不是【中心点命中】: 2026-07-19 第一版用中心点, 结果对选龟页给出假阴性 ——
## 无头模式下 DisplayServer.window_get_size() 返回 (0,0), TeamSelectScene._stage_to_screen 的
## 偏移折算 (STAGE_OFFSET * vp/win) 因此走了兜底分支, 舞台整体比真机低算约 30px,
## 木托盘(slotBay)刚好落到返回键中心点下方 14px → 中心点没被命中, 测试全绿, 但真机上按钮被木板压住。
## 面积判据对这 30px 的漂移不敏感, 抓得住。
func _occluded_buttons(root: Node, _vp: Vector2) -> Array:
	var btns: Array = []
	_visible_buttons(root, btns)
	var bad: Array = []
	for b in btns:
		var bc: Control = b as Control
		var blocker := _find_blocker(root, bc)
		if blocker != "":
			bad.append("%s(%s) 被 %s 盖住" % [b.name, (b as Button).text.left(8) if b is Button else "-", blocker])
	return bad

func _find_blocker(root: Node, btn: Control) -> String:
	var br: Rect2 = btn.get_global_rect()
	var barea: float = br.size.x * br.size.y
	if barea <= 1.0:
		return ""
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Control) or n == btn:
			continue
		var c: Control = n as Control
		if not c.is_visible_in_tree() or c.modulate.a <= 0.05:
			continue
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue                                  # 不吃鼠标的纯装饰层不算遮挡
		if btn.is_ancestor_of(c) or c.is_ancestor_of(btn):
			continue                                  # 自己的子孙/祖先(按钮内的图标、包着它的容器)不算
		var inter: Rect2 = c.get_global_rect().intersection(br)
		if inter.size.x * inter.size.y < barea * 0.25:
			continue                                  # 只是蹭到边不算; 盖掉四分之一以上才算遮住
		if not _draws_above(c, btn):
			continue
		return "%s%s" % [c.name, ("/" + str((c as Button).text).left(6)) if c is Button else ""]
	return ""

## a 是否画在 b 上面: 先比 z_index, 同 z 再比【共同父节点下的子索引】(Godot 后加的画在上面).
func _draws_above(a: Control, b: Control) -> bool:
	var pa: Node = a
	while pa != null and not pa.is_ancestor_of(b):
		pa = pa.get_parent()
	if pa == null:
		return false
	var ca: Node = a
	while ca != null and ca.get_parent() != pa:
		ca = ca.get_parent()
	var cb: Node = b
	while cb != null and cb.get_parent() != pa:
		cb = cb.get_parent()
	if ca == null or cb == null or ca == cb:
		return false
	if ca is CanvasItem and cb is CanvasItem and (ca as CanvasItem).z_index != (cb as CanvasItem).z_index:
		return (ca as CanvasItem).z_index > (cb as CanvasItem).z_index
	return ca.get_index() > cb.get_index()

## 选龟页贴边按钮(返回/清空/上次/开始)必须画在最上层 —— 结构断言, 不做几何模拟.
##
## 【为什么不靠几何】用户2026-07-19实机反馈「返回键被木板遮住」, 木板 = _build_slots 的 slotBay 暗托盘,
## 它在这四个按钮【之后】add_child, 手机比例下按钮又被 _place_clamped 夹到屏幕上沿, 正好落进托盘里。
## 但无头测试复现不了: DisplayServer.window_get_size() 返回 (0,0) → _stage_to_screen 的偏移折算
## (STAGE_OFFSET * vp/win) 走兜底, 整个舞台比真机低约 30px, 托盘刚好滑到按钮下面。
## 我先后用「中心点命中」和「面积重叠≥25%」两版几何判据, 都被这 30px 漂移骗成假阴性。
## 所以这里改断【结构不变式】: _raise_edge_btns() 把它们移到 root 末尾 = 最后绘制 = 谁也压不住,
## 与视口尺寸、舞台缩放、窗口尺寸全都无关, 无头环境同样成立。
func _check_teamselect_edge_btns(inst: Node) -> void:
	var root: Control = inst.get_node_or_null("UI/Root")
	if root == null:
		_ok("TeamSelect: 贴边按钮在最上层", false, "找不到 UI/Root")
		return
	var n := root.get_child_count()
	var tail: Array = []
	for i in range(maxi(0, n - 4), n):
		var c := root.get_child(i)
		tail.append(str((c as Button).text) if c is Button else c.get_class())
	var want := ["‹ 返回", "⊘ 清空", "🔄 上次阵容"]
	var missing: Array = []
	for w in want:
		var hit := false
		for t in tail:
			if str(t).begins_with(w.substr(0, 3)):
				hit = true
		if not hit:
			missing.append(w)
	_ok("TeamSelect: 贴边按钮在 root 末尾(画在最上层, 不会被木托盘压住)",
		missing.is_empty(), "末4个子节点=%s 缺=%s" % [str(tail), str(missing)])

func _check_scene_buttons(scene_name: String, vp: Vector2) -> void:
	var ps = load("res://scenes/%s.tscn" % scene_name)
	if ps == null:
		_ok("%s 载入" % scene_name, false, "load失败")
		return
	var inst = ps.instantiate()
	add_child(inst)
	await get_tree().create_timer(1.7).timeout   # 等入场动画落定(主菜单右栏磁贴滑入到1.39s才完; 1.1s抓中间帧误报)
	var btns: Array = []
	_visible_buttons(inst, btns)
	var bad := _offscreen_buttons(inst, vp)
	_ok("%s: %d 个可见按钮全在屏内" % [scene_name, btns.size()], bad.is_empty(), "; ".join(bad) if not bad.is_empty() else "")
	var occ := _occluded_buttons(inst, vp)
	_ok("%s: 无按钮被后画的面板盖住" % scene_name, occ.is_empty(), "; ".join(occ) if not occ.is_empty() else "")
	if scene_name == "TeamSelect":
		_check_teamselect_edge_btns(inst)
	inst.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	# ── A. iPhone 横屏画布: 全菜单按钮不越界 ──
	var vp_iphone := Vector2(1560, 720)   # 2.167:1(iPhone 14/15 横屏)·canvas_items+expand 口径
	get_tree().root.size = Vector2i(vp_iphone)
	await get_tree().process_frame
	var vp_real := Vector2(get_tree().root.size)
	print("  (画布=", vp_real, ")")
	for sn in MENU_SCENES:
		await _check_scene_buttons(sn, vp_real)

	# ── B. 主菜单调试场按钮存在 + 入口开 DEBUG_EDIT ──
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	var dbg_btn: Button = null
	var all_b: Array = []
	_visible_buttons(mm, all_b)
	for b in all_b:
		if b is Button and str((b as Button).text).contains("调试场"):
			dbg_btn = b
			break
	_ok("主菜单有🛠调试场按钮(debug构建)", dbg_btn != null)
	if dbg_btn != null:
		var r := dbg_btn.get_global_rect()
		_ok("调试场按钮在屏内可点", Rect2(Vector2.ZERO, vp_real).encloses(r), str(r))
		var wired := false
		for c in dbg_btn.pressed.get_connections():   # ⛔不真按: _open_debug_arena 会 change_scene 把本测试杀掉
			if str(c["callable"].get_method()) == "_open_debug_arena":
				wired = true
		_ok("按钮接线到_open_debug_arena(点了就进调试场)", wired)
	mm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── C. 调试场编辑器(子节点实例化·DEBUG_EDIT=true): 面板齐 + 28龟全可选 + 按钮不越界 ──
	RTScene.DEBUG_EDIT = true
	var cs = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(cs)
	await get_tree().create_timer(1.0).timeout
	var is_arena: bool = cs != null
	_ok("调试场场景已进入(DEBUG_EDIT实例化)", is_arena)
	if is_arena:
		var pal_btns: Array = []
		_visible_buttons(cs, pal_btns)
		_ok("调试场面板按钮已建(≥15)", pal_btns.size() >= 15, "共 %d" % pal_btns.size())
		var bad_c := _offscreen_buttons(cs, vp_real)
		_ok("调试场面板按钮全在屏内", bad_c.is_empty(), "; ".join(bad_c) if not bad_c.is_empty() else "")
		cs._edit_open_turtle_grid()                  # 「选龟」二级网格: 28龟全可选
		await get_tree().process_frame
		await get_tree().process_frame
		var texts := _all_texts(cs)
		var missing: Array = []
		var reg = get_node_or_null("/root/DataRegistry")
		if reg != null:
			for p in reg.all_pets:
				var pname := str((p as Dictionary).get("name", ""))
				if pname != "" and not texts.contains(pname):
					missing.append(pname)
		_ok("选龟网格28龟全可选(含每龟名)", missing.is_empty(), "缺: " + str(missing))
		var bad_g := _offscreen_buttons(cs, vp_real)
		_ok("选龟网格全在屏内", bad_g.is_empty(), "; ".join(bad_g.slice(0, 4)) if not bad_g.is_empty() else "")
		cs._edit_close_popup()
		await get_tree().process_frame
		var uu = cs._edit_place_unit("basic", "right", Vector2(600.0, 400.0))   # 装备网格: 选中单位→开
		cs._edit_sel_unit = uu
		cs._edit_open_equip_grid()
		await get_tree().process_frame
		await get_tree().process_frame
		var eq_n: int = cs._dbg_equip_ids().size()
		_ok("装备网格可开且有货(装备数=%d≥10)" % eq_n, eq_n >= 10)
		var bad_e := _offscreen_buttons(cs, vp_real)
		_ok("装备网格全在屏内", bad_e.is_empty(), "; ".join(bad_e.slice(0, 4)) if not bad_e.is_empty() else "")
		cs._edit_close_popup()
		await get_tree().process_frame
		cs.queue_free()
		await get_tree().process_frame
	RTScene.DEBUG_EDIT = false

	# ── D. 正常战斗 HUD 按钮不越界(非评审: REVIEW_DEMO_DEFAULT 已翻 false) ──
	_ok("REVIEW_DEMO_DEFAULT=false(iOS测试包不劫持战斗)", RTScene.REVIEW_DEMO_DEFAULT == false)
	var bt = RTScene.new()
	add_child(bt)
	await get_tree().process_frame
	await get_tree().process_frame
	bt.set_process(false)
	bt.set_physics_process(false)
	var bad_d := _offscreen_buttons(bt, vp_real)
	_ok("战斗HUD按钮全在屏内", bad_d.is_empty(), "; ".join(bad_d) if not bad_d.is_empty() else "")
	_ok("暂停按钮已建", bt._pause_btn != null)
	bt.queue_free()
	await get_tree().process_frame

	# ── E. iPad 4:3 画布复检(主菜单) ──
	get_tree().root.size = Vector2i(1280, 960)
	await get_tree().process_frame
	await _check_scene_buttons("MainMenu", Vector2(get_tree().root.size))

	_check_teamselect_stage()

	_done()


## F. 选龟舞台几何 (2026-07-22 用户「选龟界面画面无法匹配 ios 屏幕…画布大小很奇怪」)
##
## ★为什么 A~E 段抓不到这个 bug: 它们只断言"按钮 rect ⊆ 屏幕 / 按钮不被遮挡 / 贴边按钮在末尾",
##   而 contain 之后按钮本来就都在屏内 → 全绿。真正错的是【舞台本身】:
##     ① 竖直余量 slack=0 却仍无条件加 +76px 下移 → 底边被推出屏外
##     ② contain 在 2.167:1 的 iPhone 上左右各留 20.4% 的死板纯色条
##
## 这里是【纯几何断言, 不实例化场景】—— 因为无头下 DisplayServer.window_get_size() 返回 (0,0),
## 真去实例化算出来的舞台会比真机低算约 30px(tests/verify_ios_ui.gd:74 与 TeamSelectScene 里都记过
## 这个坑)。所以直接按公式验, 不受窗口尺寸影响。
func _check_teamselect_stage() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd")
	if src == "":
		_ok("选龟舞台", false, "读不到 TeamSelectScene.gd")
		return
	# ① 偏移必须按可用余量夹住
	var body := src.substr(maxi(0, src.find("\nfunc _stage_to_screen(")), 900)
	_ok("选龟·偏移按余量夹住", body.find("clampf(off.y") >= 0,
		"_stage_to_screen 无条件加 STAGE_OFFSET → slack=0 时必切底")
	# ② 死常量 STAGE_ZOOM 不该再有【活的】定义
	var has_live_zoom := false
	for l in src.split("\n"):
		var s2 := str(l).strip_edges()
		if s2.begins_with("const STAGE_ZOOM"):
			has_live_zoom = true
	_ok("选龟·死常量已删", not has_live_zoom, "STAGE_ZOOM 全仓库零引用, 留着误导")
	# ③ 缩放必须"尽量铺满但不裁内容带"(用户2026-07-22「整个画布和按钮是不能放大吗」)
	_ok("选龟·按内容带缩放", src.find("func _content_band(") >= 0 and src.find("cover") >= 0,
		"_stage_scale 仍是纯 contain → 屏幕两侧留大片死板, 画布看着很小")
	# ④ 公式自检: 三种屏比下 ①内容带必须完整在屏内 ②不该白白留一大片边
	var poc := Vector2(1647.0, 955.0)
	var band_pos := Vector2(160.0, 74.0)      # 与 RL 实测一致(grid.x=160 / back.y=74)
	var band_size := Vector2(1312.0, 709.0)   # x 到 start 右缘 1472, y 到 start 底 783
	for vp in [Vector2(1560, 720), Vector2(1280, 720), Vector2(1280, 960)]:
		var s3: float = minf(maxf(vp.x / poc.x, vp.y / poc.y),
			minf(vp.x / band_size.x, vp.y / band_size.y))
		var bc := band_pos + band_size * 0.5
		var slack: Vector2 = (vp - band_size * s3) * 0.5
		var off := Vector2(clampf(0.0, -maxf(0.0, slack.x), maxf(0.0, slack.x)),
			clampf(76.0, -maxf(0.0, slack.y), maxf(0.0, slack.y)))
		# 内容带在屏幕上的矩形
		var bl: Vector2 = vp * 0.5 + off + (band_pos - bc) * s3
		var br: Vector2 = bl + band_size * s3
		_ok("选龟·%dx%d 内容带完整" % [int(vp.x), int(vp.y)],
			bl.x >= -0.5 and bl.y >= -0.5 and br.x <= vp.x + 0.5 and br.y <= vp.y + 0.5,
			"内容带 x∈[%.0f,%.0f] y∈[%.0f,%.0f] 超出 %.0fx%.0f —— 会丢按钮" % [bl.x, br.x, bl.y, br.y, vp.x, vp.y])
		# 铺满度: 画面至少要被舞台覆盖 88%(否则又变成"中间一小块")
		var cov: float = minf(1.0, (poc.x * s3) / vp.x) * minf(1.0, (poc.y * s3) / vp.y)
		_ok("选龟·%dx%d 铺满度 %.0f%%" % [int(vp.x), int(vp.y), cov * 100.0], cov >= 0.88,
			"舞台只盖住 %.0f%% 屏幕 → 死板留白过大" % (cov * 100.0))
		# ★舞台某轴盖得住就【不许留缝】。上一版只验"内容带完整", 抓不到这个 ——
		#   PC 1280×720 顶部露了 103px 黑缝(PoC 烤死的 STAGE_OFFSET=76 没被夹掉), 全绿照过。
		var stage: Vector2 = poc * s3
		var org: Vector2 = vp * 0.5 + off - bc * s3
		for ax in [0, 1]:
			if stage[ax] >= vp[ax]:
				org[ax] = clampf(org[ax], vp[ax] - stage[ax], 0.0)
			else:
				org[ax] = (vp[ax] - stage[ax]) * 0.5
		var gap_t: float = maxf(0.0, org.y)
		var gap_b: float = maxf(0.0, vp.y - (org.y + stage.y))
		var gap_l: float = maxf(0.0, org.x)
		var gap_r: float = maxf(0.0, vp.x - (org.x + stage.x))
		var must_fill_y: bool = stage.y >= vp.y
		var must_fill_x: bool = stage.x >= vp.x
		_ok("选龟·%dx%d 无黑缝" % [int(vp.x), int(vp.y)],
			(not must_fill_y or (gap_t < 0.5 and gap_b < 0.5)) and (not must_fill_x or (gap_l < 0.5 and gap_r < 0.5)),
			"舞台盖得住却留缝: 上%.0f 下%.0f 左%.0f 右%.0f" % [gap_t, gap_b, gap_l, gap_r])

func _done() -> void:
	get_tree().paused = false
	print("")
	if _fail == 0:
		print("ALL PASS — iOS测试包UI守卫(全菜单按钮不越界/调试场可入28龟可选/战斗HUD不越界)通过")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)
