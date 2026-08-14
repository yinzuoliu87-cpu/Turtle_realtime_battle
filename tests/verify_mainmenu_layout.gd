extends Node
## verify_mainmenu_layout.gd — 主菜单版式体检 (2026-08-15)
##
## 由来: 用户「主菜单 UI 需要优化」。先截图, 再把截图上看到的毛病【逐条焊成会红的断言】。
## 截图量到的毛病(改之前的真实数字):
##   · 「训龟大师」(x 90..390, y 621..683) 与左下角「🛠 调试场」(x 16..136, y 666..704)
##     实打实重叠 46×17 px —— 调试构建里点训龟大师的左下角会点到调试场。
##   · 左栏按钮栈跑到 y=683, 右信息板 y=236..543 就没了 ⇒ 右下角空出 560×161 一大块。
##   · 「训龟大师」离 2×2 网格 71px(网格自己行距才 14) ⇒ 看着像掉队的孤儿; 且 300×62 = 4.84:1 全场最扁。
##   · 信息板里战绩行的值落在 x≈880, 而它上面三行的值右对齐到 x≈1230 —— 同一张卡两套对齐。
##   · 触摸目标: ⚙/❓ 磁贴 62px、战绩行 48px, 都低于 44pt(=81 视口像素)。
##
## ★判据一律量【产品自己节点的 get_global_rect()】, 不断言我插的标记、也不"断言公式"。
##   定位节点用结构/文字(比如"文字含开始战斗的那个 Label"), 断言落在真实几何上。
##
## ★触摸线取 81 视口像素, 不是 44 —— 换算见 tests/_probe_ui_layout.gd:
##   视口高恒为 720, iPhone 横屏 390pt ⇒ 1pt = 1.846px ⇒ HIG 的 44pt = 81 视口像素。
##   拿 44 当阈值等于只要求了 24pt, 会把一堆手指点不着的元素判成合格。
##
## 跑法: godot --path . res://tests/verify_mainmenu_layout.tscn --position 5000,5000

const W := 1280.0
const H := 720.0
const MIN_TAP := 81.0          # 44pt, 见上
const SETTLE_MS := 15000       # 等入场 tween 落定的墙钟上限

var _fail := 0
var _menu: Node = null


func _ok(what: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", what, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload"); get_tree().quit(1); return
	gs.test_mode = true
	## ★视口必须【焊死成设计框大小】, 否则本文件所有几何断言都会假红:
	##   视口比 720 高时 UIFrame 会把 1280×720 的设计框【居中】(见 scripts/util/ui_frame.gd),
	##   于是全局坐标整体下移 —— 实测右信息板量到 y=532 而它真实的设计坐标是 252(HERO_CY 302 − 50),
	##   差的正是 280px 的居中偏移。第①条会报「越界 66 个」, 而屏幕上一切正常。
	##   ⇒ 拿全局坐标比 1280×720, 前提就是视口本身必须是 1280×720。
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	# 种出【有进度】的一屏: 全 0 空态下战绩是"暂无战绩"、商店灰锁, 量到的不是玩家真看到的那一屏。
	gs.season_total_battles = 3
	gs.season_id = 2
	gs.season_level = 4
	gs.hearts = 5
	gs.coins = 1240
	gs.meta_deepsea_coins = 380
	gs.battles_won = 7
	gs.battles_total = 11

	print("=== 主菜单版式体检 (%.0f×%.0f) ===" % [W, H])
	var packed := load("res://scenes/MainMenu.tscn")
	if packed == null:
		print("  [FAIL] 载不到 MainMenu.tscn"); get_tree().quit(1); return
	_menu = packed.instantiate()
	get_tree().root.add_child(_menu)
	# 无头视口是方形的 —— 强制按真机 1280×720 口径量, 否则根 Control 会被撑成 1280×1280。
	if _menu is Control:
		(_menu as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(_menu as Control).size = Vector2(W, H)
	await _wait_entrance()

	var content: Control = _menu.get("content_root")
	var page_box: Control = _menu.get("page_box")
	if content == null or page_box == null:
		print("  [FAIL] 拿不到 content_root / page_box —— 场景没建起来, 后面全是空检查")
		_done(); return

	var all: Array = []
	_collect(_menu, all)
	print("  扫到 %d 个可见控件 (★分母)" % all.size())
	_ok("★分母: 可见控件 > 30 (太少说明场景没建全, 后面全是空检查)", all.size() > 30, "%d 个" % all.size())

	# 左栏按钮栈 = page_box 的直接子节点(英雄键 + 2×2 + 训龟大师)
	var stack: Array = []
	for c in page_box.get_children():
		if c is Control and (c as Control).visible:
			stack.append(c)
	print("  左栏按钮栈 %d 个 (★分母: 应为 6 = 英雄 + 2×2 + 训龟大师)" % stack.size())
	_ok("★分母: 左栏按钮栈 = 6 个", stack.size() == 6, "%d 个" % stack.size())
	if stack.size() != 6:
		_done(); return

	# ── ① 谁也别超出 1280×720 ──
	var oob: Array = []
	for c in all:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x >= W - 1.0 and r.size.y >= H - 1.0:
			continue                                     # 背景/遮罩本就该铺满
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > W + 0.5 or r.end.y > H + 0.5:
			oob.append("%s @(%.0f,%.0f) %.0f×%.0f" % [c.get_class(), r.position.x, r.position.y, r.size.x, r.size.y])
	_ok("① 所有控件都在 %.0f×%.0f 内" % [W, H], oob.is_empty(), "越界 %d 个" % oob.size())
	for o in oob.slice(0, 6):
		print("       ★越界: " + o)

	# ── ② ★任意两个可点控件不许重叠 (这条抓的就是 训龟大师 × 调试场 那 46×17) ──
	#    重叠 = 玩家点 A 点到 B。截图上看不出来(两个都在屏内、颜色又接近), 只有量 rect 才现形。
	var taps: Array = _tappables(_menu)
	print("  可点控件 %d 个 (★分母)" % taps.size())
	_ok("★分母: 可点控件 ≥ 8", taps.size() >= 8, "%d 个" % taps.size())
	var clash: Array = []
	for i in range(taps.size()):
		for j in range(i + 1, taps.size()):
			var ra: Rect2 = (taps[i] as Control).get_global_rect()
			var rb: Rect2 = (taps[j] as Control).get_global_rect()
			if _nested(taps[i], taps[j]) or _nested(taps[j], taps[i]):
				continue                                 # 父子(透明 Button 铺在 holder 上)不算撞
			if ra.intersects(rb):
				var it: Rect2 = ra.intersection(rb)
				clash.append("%s @(%.0f,%.0f)%.0f×%.0f  ×  %s @(%.0f,%.0f)%.0f×%.0f  → 压 %.0f×%.0f" % [
					_tag(taps[i]), ra.position.x, ra.position.y, ra.size.x, ra.size.y,
					_tag(taps[j]), rb.position.x, rb.position.y, rb.size.x, rb.size.y,
					it.size.x, it.size.y])
	_ok("② ★可点控件互不重叠(重叠=点 A 点到 B)", clash.is_empty(), "撞 %d 对" % clash.size())
	for cl in clash.slice(0, 6):
		print("       ★压住: " + cl)

	# ── ③ ★触摸目标短边 ≥ 81 视口像素 (=44pt) ──
	#    调试场是开发工具(OS.is_debug_build() 之后才建, 正式包玩家看不到), 显式豁免并打印,
	#    不是"忘了量"。豁免名单只有这一个, 多了就说明我在拿豁免掩盖问题。
	var small: Array = []
	var exempt := 0
	for c in taps:
		var r: Rect2 = (c as Control).get_global_rect()
		var short: float = minf(r.size.x, r.size.y)
		if short < 1.0:
			continue
		if _tag(c).find("调试场") >= 0:
			exempt += 1
			print("       (豁免·开发工具) 调试场 %.0f×%.0f — 正式包不出现" % [r.size.x, r.size.y])
			continue
		if short < MIN_TAP:
			small.append("%s %.0f×%.0f = 短边 %.0fpt" % [_tag(c), r.size.x, r.size.y, short / 1.846])
	_ok("③ ★玩家可点元素短边 ≥ %.0fpx (=44pt)" % MIN_TAP, small.is_empty(), "不达标 %d 个 / 豁免 %d 个" % [small.size(), exempt])
	for sm in small.slice(0, 8):
		print("       ★太小: " + sm)

	# ── ④ ★左右两栏必须是同一条竖直带 (右下角那 560×161 空洞就是这条不成立的后果) ──
	var st := INF
	var sb := -INF
	for c in stack:
		var r: Rect2 = (c as Control).get_global_rect()
		st = minf(st, r.position.y)
		sb = maxf(sb, r.end.y)
	var panel: Control = _find_panel(content)
	if panel == null:
		print("  [FAIL] ④ ★分母: 找不到右信息板(PanelContainer)"); _fail += 1
	else:
		var pr: Rect2 = panel.get_global_rect()
		print("  ④ 左栏按钮栈 y %.0f..%.0f  /  右信息板 y %.0f..%.0f  (板宽 %.0f, 右沿 %.0f)" % [
			st, sb, pr.position.y, pr.end.y, pr.size.x, pr.end.x])
		_ok("④ ★信息板顶沿 = 左栏栈顶沿 (差 ≤2px)", absf(pr.position.y - st) <= 2.0, "差 %.1f" % (pr.position.y - st))
		_ok("④ ★信息板底沿 = 左栏栈底沿 (差 ≤2px)", absf(pr.end.y - sb) <= 2.0, "差 %.1f" % (pr.end.y - sb))
		_ok("④ 信息板右沿贴右墙 (%.0f)" % (W - 16.0), absf(pr.end.x - (W - 16.0)) <= 1.0, "右沿 %.0f" % pr.end.x)

	# ── ⑤ ★训龟大师要【归队】: 与 2×2 网格的间距不许大于网格自己的行距 ──
	#    改之前是 71px vs 行距 14px —— 那不是"独立键", 那是掉队。
	var trainer: Control = _find_button_holder(stack, "训龟大师")
	var rows: Array = []
	for c in stack:
		if c == trainer:
			continue
		rows.append((c as Control).get_global_rect())
	if trainer == null or rows.size() != 5:
		print("  [FAIL] ⑤ ★分母: 找不到训龟大师键 或 其余键数不对(%d)" % rows.size()); _fail += 1
	else:
		var grid_bottom := -INF
		for r in rows:
			grid_bottom = maxf(grid_bottom, (r as Rect2).end.y)
		var tr: Rect2 = trainer.get_global_rect()
		var gap: float = tr.position.y - grid_bottom
		print("  ⑤ 网格下沿 %.0f → 训龟大师顶 %.0f, 间距 %.0f px" % [grid_bottom, tr.position.y, gap])
		_ok("⑤ ★训龟大师紧贴网格 (间距 0..20px, 不是孤零零掉在下面)", gap >= 0.0 and gap <= 20.0, "间距 %.0f" % gap)
		_ok("⑤ ★训龟大师不再又扁又长 (宽高比 ≤ 4.0)", tr.size.x / maxf(1.0, tr.size.y) <= 4.0,
			"%.0f×%.0f = %.2f:1" % [tr.size.x, tr.size.y, tr.size.x / maxf(1.0, tr.size.y)])

	# ── ⑥ ★所有按钮都不许太扁 (用户刚骂过商店「按钮这么扁」) ──
	var flat: Array = []
	for c in stack:
		var r: Rect2 = (c as Control).get_global_rect()
		var ratio: float = r.size.x / maxf(1.0, r.size.y)
		if ratio > 4.0:
			flat.append("%s %.0f×%.0f = %.2f:1" % [_tag(c), r.size.x, r.size.y, ratio])
	_ok("⑥ ★左栏按钮宽高比都 ≤ 4.0", flat.is_empty(), "太扁 %d 个" % flat.size())
	for f in flat:
		print("       ★太扁: " + f)

	# ── ⑦ ★信息板每行的【值】右沿要严格对齐 (含战绩行) ──
	#    定位方式是结构性的: _panel_row 建的 HBox 里, 值 = 倒数第二个孩子(最后一个是尾列)。
	#    不靠名字/标记, 断言落在真实 global_rect 上。
	if panel != null:
		var vals: Array = []
		for h in _find_rows(panel):
			var n := (h as Control).get_child_count()
			if n < 4:
				continue
			var v = (h as Control).get_child(n - 2)
			if v is Control:
				vals.append((v as Control).get_global_rect().end.x)
		print("  ⑦ 值列右沿 %s (★分母: 应为 4 行 = 大轮/命数/深海币/战绩)" % str(vals))
		_ok("⑦ ★分母: 收到 4 行", vals.size() == 4, "%d 行" % vals.size())
		if vals.size() >= 2:
			var lo := INF
			var hi := -INF
			for v2 in vals:
				lo = minf(lo, float(v2)); hi = maxf(hi, float(v2))
			_ok("⑦ ★各行值右沿对齐 (极差 ≤2px)", hi - lo <= 2.0, "极差 %.1f px" % (hi - lo))

	# ── ⑧ ★字号层级要拉得开 (原来 hero27 / 面板标题25 / 次级22 —— 主次只差 5 号) ──
	var f_hero := _font_of(_menu, "开始战斗")
	var f_title := _font_of(_menu, "赛季进度")
	var f_sub := _font_of(_menu, "背包")
	var f_row := _font_of(_menu, "剩余命数")
	print("  ⑧ 字号: 主CTA %d / 面板标题 %d / 次级键 %d / 行文字 %d" % [f_hero, f_title, f_sub, f_row])
	_ok("★分母: 四个字号都量到了(0 = 没找到那个 Label, 下面是空比较)",
		f_hero > 0 and f_title > 0 and f_sub > 0 and f_row > 0)
	_ok("⑧ ★主CTA 明显大于次级键 (≥ +6)", f_hero - f_sub >= 6, "%d vs %d" % [f_hero, f_sub])
	_ok("⑧ ★面板标题夹在主CTA与次级键之间", f_hero > f_title and f_title > f_sub,
		"%d > %d > %d" % [f_hero, f_title, f_sub])

	# ── ⑨ ★版本号仍在右下角且看得见 (verify_version 管四处一致, 这里只管"在不在屏上") ──
	var vstr := str(ProjectSettings.get_setting("application/config/version", ""))
	var vrect := Rect2()
	var vhit := false
	for c in all:
		if c is Label and vstr != "" and str((c as Label).text).contains(vstr):
			vrect = (c as Control).get_global_rect(); vhit = true
	_ok("⑨ ★屏幕上有写着版本号的 Label", vhit and vstr != "", "版本 %s" % vstr)
	if vhit:
		print("  ⑨ 版本号 rect %.0f..%.0f × %.0f..%.0f" % [vrect.position.x, vrect.end.x, vrect.position.y, vrect.end.y])
		_ok("⑨ 版本号在右下角 (右沿 ≥%.0f 且 底沿 ≥%.0f)" % [W * 0.7, H * 0.85],
			vrect.end.x >= W * 0.7 and vrect.end.y >= H * 0.85)

	# ── ⑩ ★右下角那块【曾经全空】的地方现在必须有内容 ──
	#    改之前信息板 236..543 就没了, 于是 x 704..1264 / y 600..650 这块【一个控件都没有】。
	#    ④ 管的是"两栏首尾对齐", 这条管的是"那块洞真的被填上了" —— 只把面板标题字号调大
	#    是骗不过这条的(板底还是到不了 650)。
	var hole := Rect2(704.0, 600.0, W - 16.0 - 704.0, 50.0)
	var fillers: Array = []
	for c in all:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x >= W - 1.0 and r.size.y >= H - 1.0:
			continue                                     # 背景铺满层不算"内容"
		if r.intersects(hole):
			fillers.append("%s @(%.0f,%.0f)%.0f×%.0f" % [c.get_class(), r.position.x, r.position.y, r.size.x, r.size.y])
	print("  ⑩ 右下角 x %.0f..%.0f y %.0f..%.0f 里有 %d 个控件" % [
		hole.position.x, hole.end.x, hole.position.y, hole.end.y, fillers.size()])
	for f2 in fillers.slice(0, 3):
		print("       " + f2)
	_ok("⑩ ★右下角不再是空洞(至少 1 个控件盖住它)", not fillers.is_empty(), "%d 个" % fillers.size())

	# ── ⑪ ★没有花名 / 感叹号推销话术 (用户 2026-08-15 点名要去掉的那类"ai 味") ──
	#    ★只扫【字符串字面量】—— 扫整段代码会被 `!=` 运算符命中(第一版就是这么假红的),
	#      而要管的本来就是"屏幕上出现的字", 不是运算符。
	var src := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	_ok("★分母: 读到源码", src.length() > 1000, "%d 字符" % src.length())
	var lits := _string_literals(src)
	print("  ⑪ 源码里的字符串字面量 %d 条 (★分母)" % lits.size())
	_ok("★分母: 扫到字面量 > 20 (0 条 = 空检查)", lits.size() > 20, "%d 条" % lits.size())
	var hype: Array = []
	for s2 in lits:
		for bad in ["！", "!", "就生效", "就更强", "立刻拥有", "超值", "限时", "神射手"]:
			if str(s2).find(bad) >= 0 and not hype.has(str(s2)):
				hype.append(str(s2))
	_ok("⑪ ★界面文案里没有感叹号推销话术/花名", hype.is_empty(), "命中 %s" % str(hype.slice(0, 4)))

	# ── ⑫ ★删掉的死代码是真删了, 不是留着不调 ──
	for dead in ["_maybe_ask_fullscreen", "_fs_dialog_btn", "layer_modulate_fade", "_show_page", "_card_nodes", "_title_node"]:
		_ok("⑫ 死代码已删净: %s" % dead, src.find("func %s" % dead) < 0 and src.find("%s =" % dead) < 0 and src.find("%s." % dead) < 0)

	_done()


## 等入场 tween 落定 —— 用【墙钟】不是帧数(CLAUDE.md §3.5: 无头帧率极高, 帧数根本不是时间)。
## 再叠 time_scale 加速: tween 走的是 delta×time_scale, 无头下 delta 极小,
## 不加速的话 1.3 秒的入场要跑上万帧, 测到的是半空中的坐标。
## ★没落定就【显式报 FAIL 并说明】, 不静默拿半空中的数字往下量。
func _wait_entrance() -> void:
	Engine.time_scale = 12.0
	var t0 := Time.get_ticks_msec()
	var settled := false
	while Time.get_ticks_msec() - t0 < SETTLE_MS:
		await get_tree().process_frame
		if _entrance_done():
			settled = true
			break
	Engine.time_scale = 1.0
	for _i in range(4):
		await get_tree().process_frame
	print("  入场动画落定: %s (墙钟 %d ms)" % ["是" if settled else "★否(下面量到的是半空中的坐标)", Time.get_ticks_msec() - t0])
	_ok("★前置: 入场动画已落定(没落定则后面所有几何断言都不算数)", settled)


func _entrance_done() -> bool:
	var content: Control = _menu.get("content_root")
	var page_box: Control = _menu.get("page_box")
	if content == null or page_box == null:
		return false
	var kids: Array = []
	kids.append_array(content.get_children())
	kids.append_array(page_box.get_children())
	if kids.size() < 8:
		return false
	for c in kids:
		if c is Control and (c as Control).visible and (c as Control).modulate.a < 0.999:
			return false
	return true


## 可点控件 = BaseButton, 上溯到它所在的 holder(透明 Button 铺满 holder, 量 holder 才是玩家看到的键)
func _tappables(root: Node) -> Array:
	var out: Array = []
	for n in _walk(root):
		if not (n is BaseButton) or not (n as Control).visible:
			continue
		var c: Control = n
		var p := c.get_parent()
		# 透明 Button 是 PRESET_FULL_RECT 铺在 holder 上 ⇒ 尺寸相同时取父 holder
		if p is Control and absf((p as Control).size.x - c.size.x) < 1.0 and absf((p as Control).size.y - c.size.y) < 1.0:
			c = p
		if not out.has(c):
			out.append(c)
	return out


func _nested(a: Node, b: Node) -> bool:
	var p := a.get_parent()
	while p != null:
		if p == b:
			return true
		p = p.get_parent()
	return false


## 给控件起个人看得懂的名字: 优先它自己或子孙 Label 的文字
func _tag(c: Node) -> String:
	if c is Button and str((c as Button).text) != "":
		return str((c as Button).text).substr(0, 12)
	for n in _walk(c):
		if n is Label and str((n as Label).text).strip_edges() != "":
			return str((n as Label).text).substr(0, 12)
	return c.get_class()


## 那个 560 宽的金边信息板
func _find_panel(content: Control) -> Control:
	for c in content.get_children():
		if c is PanelContainer and (c as Control).visible:
			return c
	return null


## 信息板里 _panel_row 建的那些行 (HBox, ≥4 个孩子: 图标/名/值/尾列)
func _find_rows(panel: Control) -> Array:
	var out: Array = []
	for n in _walk(panel):
		if n is HBoxContainer and (n as Control).visible and (n as Control).get_child_count() >= 4:
			out.append(n)
	return out


func _find_button_holder(stack: Array, text: String) -> Control:
	for c in stack:
		if _tag(c).find(text) >= 0:
			return c
	return null


## 某段文字所在 Label 的真实字号 (量控件自己的 theme override, 不读源码字面量)
func _font_of(root: Node, text: String) -> int:
	var best := 0
	for n in _walk(root):
		if n is Label and str((n as Label).text).find(text) >= 0:
			best = maxi(best, (n as Label).get_theme_font_size("font_size"))
	return best


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var ct: Control = c
			if ct.size.x > 0.0 and ct.size.y > 0.0:
				out.append(ct)
		_collect(c, out)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


## 源码里所有【双引号字符串字面量】的内容。
## 注释里的引号不算(先按行剥注释), 所以注释里举例写「买这件就生效！」不会误报;
## 而真正会显示到屏幕上的字都是字面量, 一条不漏。
func _string_literals(block: String) -> Array:
	var out: Array = []
	for l in block.split("\n"):
		var line := str(l)
		var in_q := false
		var cur := ""
		for i in line.length():
			var ch := line[i]
			if in_q:
				if ch == "\"":
					in_q = false
					if cur != "":
						out.append(cur)
					cur = ""
				else:
					cur += ch
			elif ch == "\"":
				in_q = true; cur = ""
			elif ch == "#":
				break                                    # 行内注释之后的都不是代码
	return out


func _done() -> void:
	if _menu != null:
		_menu.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 主菜单版式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
