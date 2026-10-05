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
## ★★2026-10-05 第三轮「手游大厅骨架」整体换判据(ⓐ~ⓕ), 旧的左栏木牌 / 贴底赛程条那几节随版式删掉:
##   ⓐ 左上玩家卡 · ⓑ 右上货币 + ?⚙ · ⓒ 左列方键 · ⓓ 右下开始战斗最大且唯一亮黄 · ⓔ 它左边模式卡 · ⓕ 点模式卡弹出整周赛程。
##   每一条都反向验证过(改坏产品一处 ⇒ 对应那条红), 记录在方案书 20260917 第三轮。
##
## 跑法: godot --path . res://tests/verify_mainmenu_layout.tscn --position 5000,5000

const W := 1280.0
const H := 720.0
const MIN_TAP := 81.0          # 44pt, 见上
## ★状态行那一块的节点名从**产品的常量**取, 不抄字面量(抄一次就永远落后一次)。
const MENU_S := preload("res://scripts/scenes/MainMenuScene.gd")
const SETTLE_MS := 15000       # 等入场 tween 落定的墙钟上限
const _P2A := preload("res://scripts/gamedata/phase2_config.gd")

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
	# ══════════════════════════════════════════════════════════════════════
	#  2026-10-05 第三轮「手游大厅骨架」—— 判据整体换掉(不是放宽): 旧版式的左栏木牌/贴底赛程条已经不在了,
	#  量它们等于量空气。新骨架来自 6 张手游主大厅参考(docs/plans/ref/20261005-手游大厅/):
	#    左上玩家卡 / 右上货币 + ?⚙ / 左列方键 / 中间擂台 / 右下开始战斗(最大、唯一亮黄) / 它左边模式卡(点开整周赛程)
	#  ★每条都量产品自己的节点(名字从产品常量取), 不量我插的标记。
	# ══════════════════════════════════════════════════════════════════════
	var stack: Array = []
	for c in page_box.get_children():
		if c is Control and (c as Control).visible:
			stack.append(c)
	print("  page_box 栈 %d 个 (★分母: 应为 7 = 左列 5 颗方键 + 训龟大师 + 开始战斗)" % stack.size())
	_ok("★分母: page_box 栈 = 7 个", stack.size() == 7, "%d 个" % stack.size())
	if stack.size() != 7:
		_done(); return

	# ── ① 谁也别超出 1280×720(只量看得见的; 弹层的内容在 ⓕ 打开后单独量) ──
	var oob: Array = []
	## ★擂台背景是一张 390×180 的原生画布按 ×4 放大、**居中裁边**铺满视口 —— 画布伸出屏幕两侧是被裁掉的画。
	##   ⇒ 背景子树不算越界; 但「背景自己裁边 + 盖满视口」由 ⑮b 单独断言。
	var bd_node: Node = _find_named(_menu, "ArenaBackdrop")
	for c in all:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x >= W - 1.0 and r.size.y >= H - 1.0:
			continue                                     # 背景/遮罩本就该铺满
		if bd_node != null and (bd_node as Node).is_ancestor_of(c):
			continue
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > W + 0.5 or r.end.y > H + 0.5:
			oob.append("%s %s @(%.0f,%.0f) %.0f×%.0f" % [c.get_class(), str(c.name), r.position.x, r.position.y, r.size.x, r.size.y])
	_ok("① 所有看得见的控件都在 %.0f×%.0f 内" % [W, H], oob.is_empty(), "越界 %d 个" % oob.size())
	for o in oob.slice(0, 6):
		print("       ★越界: " + o)

	# ── ② ★任意两个可点控件不许重叠 (重叠 = 点 A 点到 B) ──
	var taps: Array = _tappables(_menu)
	print("  可点控件 %d 个 (★分母)" % taps.size())
	_ok("★分母: 可点控件 ≥ 11(5 方键 + 训龟大师 + 开始战斗 + 玩家卡 + 模式卡 + ? + ⚙)", taps.size() >= 11, "%d 个" % taps.size())
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
	var small: Array = []
	var exempt := 0
	for c in taps:
		var r: Rect2 = (c as Control).get_global_rect()
		var short: float = minf(r.size.x, r.size.y)
		if short < 1.0:
			continue
		if _tag(c).find("调试场") >= 0:
			exempt += 1
			continue
		if short < MIN_TAP:
			small.append("%s %.0f×%.0f = 短边 %.0fpt" % [_tag(c), r.size.x, r.size.y, short / 1.846])
	_ok("③ ★玩家可点元素短边 ≥ %.0fpx (=44pt)" % MIN_TAP, small.is_empty(), "不达标 %d 个" % small.size())
	_ok("③b ★触摸线豁免名单已清零(调试场只在设置页)", exempt == 0, "还有 %d 个豁免" % exempt)
	for sm in small.slice(0, 8):
		print("       ★太小: " + sm)

	var trainer: Control = _find_button_holder(stack, "训龟大师")
	var hero: Control = _find_button_holder(stack, "开始战斗")

	# ── ⓐ ★左上 = 玩家信息卡(一整张卡, 不是散字) ──
	var card: Control = _find_named(_menu, str(MENU_S.CARD_NAME)) as Control
	_ok("ⓐ ★分母: 玩家卡在场(`%s`)" % str(MENU_S.CARD_NAME), card != null)
	if card != null:
		var cr: Rect2 = card.get_global_rect()
		print("  ⓐ 玩家卡 @(%.0f,%.0f) %.0f×%.0f" % [cr.position.x, cr.position.y, cr.size.x, cr.size.y])
		_ok("ⓐ ★玩家卡贴左上角(左沿 ≤ 32 · 顶沿 ≤ 24)", cr.position.x <= 32.0 and cr.position.y <= 24.0, str(cr))
		_ok("ⓐ ★玩家卡只占左上(右沿 < 屏宽一半 · 底沿 < 屏高 1/5)", cr.end.x < W * 0.5 and cr.end.y < H * 0.2, str(cr))
		## 一张卡 = 有自己的底板(贴图), 而且底板盖住整张卡 —— 不是几行字飘在看台上
		var plate_ok := false
		for n_a in _walk(card):
			if n_a is NinePatchRect and (n_a as NinePatchRect).texture != null:
				var pr: Rect2 = (n_a as Control).get_global_rect()
				if pr.encloses(cr.grow(-1.0)):
					plate_ok = true
		_ok("ⓐ ★是一整张卡: 有一块贴图底板盖满整张卡", plate_ok)
		var av: Node = _find_named(card, "Avatar")
		_ok("ⓐ ★头像槽在卡里(有贴图, 在卡的左端)", av is TextureRect and (av as TextureRect).texture != null
			and (av as Control).get_global_rect().get_center().x < cr.position.x + cr.size.x * 0.25)
		var ctxt: Array = []
		for n_a in _walk(card):
			if n_a is Label and str((n_a as Label).text).strip_edges() != "" and not ctxt.has(str((n_a as Label).text)):
				ctxt.append(str((n_a as Label).text))
		var cj := " | ".join(PackedStringArray(ctxt))
		print("  ⓐ 卡里的字: %s" % cj)
		var BE_M = load("res://scripts/net/backend.gd")
		var want_name: String = str(BE_M.player_display_name())
		var want_tag: String = str(BE_M.my_tag())
		_ok("ⓐ ★昵称 == Backend.player_display_name()", want_name != "" and ctxt.has(want_name), "要「%s」" % want_name)
		_ok("ⓐ ★玩家 ID == Backend.my_tag()", want_tag != "" and cj.find(want_tag) >= 0, "要「%s」" % want_tag)
		_ok("ⓐ ★大轮 · Lv 在卡里", cj.find("大轮") >= 0 and cj.find("Lv") >= 0, cj)
		var today_a := str(_menu._phase_status_line(_menu._now_ts()))
		if today_a == "":
			_ok("ⓐ ★本周 x/%d 在卡里(积分赛口径)" % int(_P2A.RANKED_QUOTA),
				cj.find("本周") >= 0 and cj.find("/%d" % int(_P2A.RANKED_QUOTA)) >= 0, cj)
		else:
			_ok("ⓐ ★今天的读数在卡里「%s」" % today_a, cj.find(today_a) >= 0, cj)
		_ok("ⓐ ★战绩在卡里", cj.find("战绩") >= 0, cj)
		_ok("ⓐ ★整张卡可点(→战绩)", taps.has(card))
		## ⓐ2 返工(主会话看图): 字太小 / 「战绩-还没上过场」那道横线 / 卡又宽又空
		var fnt_bad: Array = []
		var ink_end := 0.0
		var nick_fs := 0
		for n_a in _walk(card):
			if not (n_a is Label) or str((n_a as Label).text).strip_edges() == "":
				continue
			var la: Label = n_a
			var fs_a: int = la.get_theme_font_size("font_size")
			if str(la.name) == "Nickname":
				nick_fs = fs_a
			elif fs_a < 17:
				fnt_bad.append("「%s」%d" % [la.text.substr(0, 8), fs_a])
			var fa: Font = la.get_theme_font("font")
			var ink_w: float = fa.get_string_size(la.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_a).x if fa != null else 0.0
			ink_end = maxf(ink_end, la.get_global_rect().position.x + ink_w)
		## 「战绩-还没上过场」那道横线的真因: 战绩那行压在卡底边的铜线上, 铜线从字缝里露出来。
		##   ⇒ 每行字的墨迹(竖向居中, 高≈字号)都要落在卡底边那圈木框(18px)之上。
		var low: Array = []
		for n_l in _walk(card):
			if n_l is Label and str((n_l as Label).text).strip_edges() != "":
				var lr_l: Rect2 = (n_l as Control).get_global_rect()
				var ink_bot: float = lr_l.get_center().y + float((n_l as Label).get_theme_font_size("font_size")) * 0.5
				if ink_bot > cr.end.y - 18.0:
					low.append("「%s」%.0f" % [(n_l as Label).text.substr(0, 6), ink_bot])
		_ok("ⓐ2 ★每行字都落在卡底边铜线之上(墨迹底 ≤ 卡底 − 18)", low.is_empty(), "%s / 卡底 %.0f" % [str(low), cr.end.y])
		_ok("ⓐ2 ★昵称 ≥ 22 号", nick_fs >= 22, "%d" % nick_fs)
		_ok("ⓐ2 ★卡里其余各行 ≥ 17 号", fnt_bad.is_empty(), str(fnt_bad))
		## 「战绩」与读数之间那道横线: 同一段字里的空格被画成了线/点 ⇒ 拆成两段, 中间是真空白(≥ 6px), 读数里不带「-·」打头
		var rh_a: Label = _find_named(card, "RecordHead") as Label
		var rt_a: Label = _find_named(card, "RecordText") as Label
		var gap_a := -1.0
		if rh_a != null and rt_a != null:
			var fh: Font = rh_a.get_theme_font("font")
			gap_a = rt_a.get_global_rect().position.x - (rh_a.get_global_rect().position.x
				+ fh.get_string_size(rh_a.text, HORIZONTAL_ALIGNMENT_LEFT, -1, rh_a.get_theme_font_size("font_size")).x)
		_ok("ⓐ2 ★「战绩」与读数是两段字、中间真空白 ≥ 6px(不靠空格, 空格实拍画成了横线)", rh_a != null and rt_a != null
			and rh_a.text == "战绩" and gap_a >= 6.0 and not rt_a.text.begins_with("-") and not rt_a.text.begins_with("·") and not rt_a.text.begins_with(" "),
			"间隔 %.0f" % gap_a)
		var rib_a: Node = _find_named(card, str(MENU_S.STATUS_RIBBON_NAME))
		if rib_a is Control:
			ink_end = maxf(ink_end, (rib_a as Control).get_global_rect().end.x)   # 绶带也是内容
		_ok("ⓐ2 ★卡宽贴合内容(最长那行字/绶带的右端到卡右沿 ≤ 40px)", ink_end > 0.0 and cr.end.x - ink_end <= 40.0,
			"字到 %.0f / 卡到 %.0f" % [ink_end, cr.end.x])
		## Logo 不再占左上角
		var logo: Control = _find_named(_menu, "Logo") as Control
		_ok("ⓐ ★分母: Logo 在场", logo != null)
		if logo != null:
			var lr: Rect2 = logo.get_global_rect()
			print("  ⓐ Logo @(%.0f,%.0f) %.0f×%.0f" % [lr.position.x, lr.position.y, lr.size.x, lr.size.y])
			_ok("ⓐ ★Logo 让出左上角: 在顶部居中(中心 x 落在屏宽 40%..60%)", lr.get_center().x >= W * 0.4 and lr.get_center().x <= W * 0.6, str(lr))
			_ok("ⓐ ★Logo 缩小了(宽 ≤ 200)、不压玩家卡", lr.size.x <= 200.0 and not lr.intersects(cr), str(lr))

	# ── ⓑ ★右上 = 两种货币一行 + ? / ⚙ 小图标键 ──
	var chips: Array = []
	for n_b in _walk(content):
		if n_b is NinePatchRect and (n_b as NinePatchRect).texture != null \
				and str((n_b as NinePatchRect).texture.resource_path).get_file() == "chip.png":
			chips.append((n_b as Control).get_global_rect())
	_ok("ⓑ ★分母: 两块货币牌在场", chips.size() == 2, "%d 块" % chips.size())
	var icon_taps: Array = []
	for t_b in taps:
		var tg_b: String = _tag(t_b)
		if tg_b.find("⚙") >= 0:
			icon_taps.append(t_b)
		elif t_b is Control and _find_frame_square(t_b) != null and tg_b.find("⚙") < 0:
			icon_taps.append(t_b)
	_ok("ⓑ ★分母: ? 与 ⚙ 两颗都找到了", icon_taps.size() == 2, "%d 颗" % icon_taps.size())
	if chips.size() == 2 and icon_taps.size() == 2:
		var c0: Rect2 = chips[0]
		var c1: Rect2 = chips[1]
		_ok("ⓑ ★两块货币牌在同一行(顶沿差 ≤2)", absf(c0.position.y - c1.position.y) <= 2.0, "%s / %s" % [str(c0), str(c1)])
		_ok("ⓑ ★货币在右上(都在屏宽右半 · 底沿 ≤ 130)", minf(c0.position.x, c1.position.x) >= W * 0.5 and maxf(c0.end.y, c1.end.y) <= 130.0,
			"%s / %s" % [str(c0), str(c1)])
		var chips_end: float = maxf(c0.end.x, c1.end.x)
		var vis_max := 0.0
		for t_b in icon_taps:
			var tr_b: Rect2 = (t_b as Control).get_global_rect()
			_ok("ⓑ ★「%s」在货币右边、同一行(中心 y 与货币牌差 ≤8)" % _tag(t_b),
				tr_b.position.x >= chips_end - 1.0 and absf(tr_b.get_center().y - c0.get_center().y) <= 8.0, str(tr_b))
			var fr_b: Control = _find_frame_square(t_b)
			if fr_b != null:
				vis_max = maxf(vis_max, fr_b.get_global_rect().size.x)
		_ok("ⓑ ★? / ⚙ 看得见的方框缩小了(≤ 60px; 原来 82)", vis_max > 0.0 and vis_max <= 60.0, "%.0f" % vis_max)
		var rmost := 0.0
		for t_b in icon_taps:
			rmost = maxf(rmost, (t_b as Control).get_global_rect().end.x)
		_ok("ⓑ ★右上这一排收在右沿(≥ %.0f)" % (W - 24.0), rmost >= W - 24.0, "%.0f" % rmost)

	# ── ⓒ ★左侧 = 一列方形图标键(图标在上、字在下, 带红点槽) ──
	var squares: Array = []
	for c in stack:
		if str(c.name).begins_with(str(MENU_S.SQ_NAME_PREFIX)) or str(c.name) == str(MENU_S.RECORD_ENTRY_NAME):
			squares.append(c)
	squares.sort_custom(func(a, b): return (a as Control).global_position.y < (b as Control).global_position.y)
	var sq_names: Array = []
	for c in squares:
		sq_names.append(_sq_label(c))
	_ok("ⓒ ★分母: 左列 5 颗方键 = 背包/商店/图鉴/排行榜/战绩", sq_names == ["背包", str(MENU_S.SHOP_LABEL), "图鉴", "排行榜", "战绩"], str(sq_names))
	var not_sq: Array = []
	var lefts: Array = []
	var gaps_c: Array = []
	var icon_ok := 0
	var badge_ok := 0
	var skin_ok := 0
	for i_c in range(squares.size()):
		var r_c: Rect2 = (squares[i_c] as Control).get_global_rect()
		if absf(r_c.size.x - r_c.size.y) > 1.0:
			not_sq.append("%s %.0f×%.0f" % [_sq_label(squares[i_c]), r_c.size.x, r_c.size.y])
		lefts.append(r_c.position.x)
		if i_c > 0:
			gaps_c.append(r_c.position.y - (squares[i_c - 1] as Control).get_global_rect().end.y)
		var ic_c: TextureRect = null
		var lb_c: Label = null
		for n_c in _walk(squares[i_c]):
			if n_c is TextureRect and ic_c == null and (n_c as TextureRect).texture != null:
				ic_c = n_c
			if n_c is Label and str((n_c as Label).text) == _sq_label(squares[i_c]):
				lb_c = n_c
			if n_c is NinePatchRect and (n_c as NinePatchRect).texture != null \
					and str((n_c as NinePatchRect).texture.resource_path).get_file() == "sqbtn.png":
				skin_ok += 1
		if ic_c != null and lb_c != null and ic_c.get_global_rect().get_center().y < lb_c.get_global_rect().get_center().y:
			icon_ok += 1
		var bd_c: Node = _find_named(squares[i_c], str(MENU_S.BADGE_NAME))
		if bd_c is Control:
			var br_c: Rect2 = (bd_c as Control).get_global_rect()
			if br_c.get_center().x > r_c.get_center().x and br_c.get_center().y < r_c.get_center().y:
				badge_ok += 1
	_ok("ⓒ ★五颗都是正方形(宽高差 ≤1)", squares.size() == 5 and not_sq.is_empty(), str(not_sq))
	_ok("ⓒ ★五颗共用一条左沿(极差 ≤1)、贴左边(≤ 32)", lefts.size() == 5 and lefts.max() - lefts.min() <= 1.0 and lefts.min() <= 32.0, str(lefts))
	_ok("ⓒ ★竖排等距(间距极差 ≤1, 不重叠)", gaps_c.size() == 4 and gaps_c.max() - gaps_c.min() <= 1.0 and gaps_c.min() >= 0.0, str(gaps_c))
	_ok("ⓒ ★五颗都是图标在上、字在下", icon_ok == 5, "%d / 5" % icon_ok)
	_ok("ⓒ ★五颗都用方木块底(sqbtn.png)", skin_ok == 5, "%d / 5" % skin_ok)
	_ok("ⓒ ★五颗都带红点槽(右上角, 默认藏着)", badge_ok == 5, "%d / 5" % badge_ok)
	if card != null and squares.size() == 5:
		_ok("ⓒ 方键列在玩家卡下面(不压卡)", (squares[0] as Control).get_global_rect().position.y >= card.get_global_rect().end.y, "")

	# ── ⓓ ★右下 = 开始战斗: 最大, 而且是全屏唯一的实心亮黄 ──
	var mode: Control = _find_named(_menu, str(MENU_S.MODE_CARD_NAME)) as Control
	if hero == null or trainer == null:
		_ok("ⓓ ★分母: 找到开始战斗 / 训龟大师", false)
	else:
		var hr: Rect2 = hero.get_global_rect()
		print("  ⓓ 开始战斗 @(%.0f,%.0f) %.0f×%.0f" % [hr.position.x, hr.position.y, hr.size.x, hr.size.y])
		_ok("ⓓ ★开始战斗在右下角(右沿 ≥ %.0f · 底沿 ≥ %.0f)" % [W - 24.0, H - 32.0], hr.end.x >= W - 24.0 and hr.end.y >= H - 32.0, str(hr))
		var bigger: Array = []
		for t_d in taps:
			if t_d == hero:
				continue
			var tr_d: Rect2 = (t_d as Control).get_global_rect()
			if tr_d.size.x * tr_d.size.y >= hr.size.x * hr.size.y:
				bigger.append("%s %.0f×%.0f" % [_tag(t_d), tr_d.size.x, tr_d.size.y])
		_ok("ⓓ ★开始战斗是全屏最大的可点元素", bigger.is_empty(), str(bigger))
		## 「唯一实心亮黄」: 量每块看得见的**面**(贴图 / 九宫格 / 色块)里亮黄像素的占比。
		##   亮黄 = 色相 40°..62° · 饱和度 ≥0.70 · 明度 ≥0.85(乘上节点自己和祖先的 modulate)。
		##   ★光晕(MenuCtaGlow)是叠加发光不是面, 不算; 背景子树不算(它在 ⑮ 里另管)。
		var yel: Array = []
		var face_frac := -1.0
		var painters_d := 0
		var other_max := 0.0
		var other_who := ""
		for c in all:
			if bd_node != null and ((bd_node as Node).is_ancestor_of(c) or c == bd_node):
				continue
			if c is MenuCtaGlow:
				continue
			var fr_d: float = _yellow_frac(c)
			if fr_d < 0.0:
				continue
			painters_d += 1
			if str(c.name) == str(MENU_S.HERO_FACE_NAME):
				face_frac = fr_d
			elif fr_d > other_max:
				other_max = fr_d
				other_who = "%s %s" % [c.get_class(), str(c.name)]
			if str(c.name) != str(MENU_S.HERO_FACE_NAME) and fr_d >= 0.20:
				yel.append("%s %s %.0f%%" % [c.get_class(), str(c.name), fr_d * 100.0])
		print("  ⓓ 量了 %d 块面 · 开始战斗的面亮黄 %.0f%% · 其余最黄的一块 %s %.0f%%" % [painters_d, face_frac * 100.0, other_who, other_max * 100.0])
		_ok("ⓓ ★分母: 量到的面 ≥ 15 块", painters_d >= 15, "%d" % painters_d)
		_ok("ⓓ ★开始战斗的面是实心亮黄(亮黄像素 ≥ 60%)", face_frac >= 0.60, "%.0f%%" % (face_frac * 100.0))
		_ok("ⓓ ★全屏只有它一块亮黄面(别的面亮黄 < 20%)", yel.is_empty(), str(yel))
		var face_n: Node = _find_named(hero, str(MENU_S.HERO_FACE_NAME))
		_ok("ⓓ ★亮黄面在木框里面(R2: 木框保留)", face_n is Control and hr.encloses((face_n as Control).get_global_rect())
			and (face_n as Control).get_global_rect().size.x < hr.size.x, "")
		## 训龟大师: 明显低一档, 贴在主 CTA 正上方、右沿同轴, 换一种皮
		var tr: Rect2 = trainer.get_global_rect()
		_ok("ⓓ ★训龟大师与主 CTA 右沿同轴 (差 ≤2px)", absf(tr.end.x - hr.end.x) <= 2.0, "差 %.1f" % (tr.end.x - hr.end.x))
		_ok("ⓓ ★训龟大师贴在主 CTA 正上方 (间距 4..12px)", hr.position.y - tr.end.y >= 4.0 and hr.position.y - tr.end.y <= 12.0,
			"间距 %.0f" % (hr.position.y - tr.end.y))
		_ok("ⓓ ★主 CTA 面积 ≥ 训龟大师 1.8 倍", (hr.size.x * hr.size.y) >= (tr.size.x * tr.size.y) * 1.8,
			"%.2f 倍" % ((hr.size.x * hr.size.y) / maxf(1.0, tr.size.x * tr.size.y)))
		var t_tex := ""
		for n5 in _walk(trainer):
			if n5 is NinePatchRect and (n5 as NinePatchRect).texture != null:
				t_tex = str((n5 as NinePatchRect).texture.resource_path).get_file()
		var h_tex := ""
		for n5 in _walk(hero):
			if n5 is TextureRect and not (n5 is MenuCtaGlow) and (n5 as TextureRect).texture != null and h_tex == "":
				h_tex = str((n5 as TextureRect).texture.resource_path).get_file()
		_ok("ⓓ ★训龟大师与主 CTA 不是同一张皮", t_tex != "" and h_tex != "" and t_tex != h_tex, "「%s」/「%s」" % [t_tex, h_tex])

		# ── ⓔ ★开始战斗左边 = 「今天」模式卡: 今天的赛制 + 一句规矩 + 倒计时 ──
		_ok("ⓔ ★分母: 模式卡在场(`%s`)" % str(MENU_S.MODE_CARD_NAME), mode != null)
		if mode != null:
			var mr: Rect2 = mode.get_global_rect()
			print("  ⓔ 模式卡 @(%.0f,%.0f) %.0f×%.0f" % [mr.position.x, mr.position.y, mr.size.x, mr.size.y])
			_ok("ⓔ ★模式卡在开始战斗左边、读成一组(右沿 ≤ 主 CTA 左沿 · 间距 ≤ 12)", mr.end.x <= hr.position.x and hr.position.x - mr.end.x <= 12.0, str(mr))
			_ok("ⓔ ★模式卡高度接近开始战斗(≥ 85%)", mr.size.y >= hr.size.y * 0.85, "%.0f / %.0f" % [mr.size.y, hr.size.y])
			var mt: Label = _find_named(mode, "ModeTitle") as Label
			var mrl: Label = _find_named(mode, "ModeRule") as Label
			var mcd: Label = _find_named(mode, "ModeCountdown") as Label
			_ok("ⓔ ★分母: 赛制 / 规矩 / 倒计时三行都在", mt != null and mrl != null and mcd != null)
			if mt != null and mrl != null and mcd != null:
				_ok("ⓔ ★赛制名大字(≥ 26 号)", mt.get_theme_font_size("font_size") >= 26, "%d" % mt.get_theme_font_size("font_size"))
				_ok("ⓔ ★规矩 ≥ 17 号", mrl.get_theme_font_size("font_size") >= 17, "%d" % mrl.get_theme_font_size("font_size"))
				_ok("ⓔ ★倒计时单独一行(在规矩下面、不同一行) 且 ≥ 17 号", mcd.get_global_rect().position.y >= mrl.get_global_rect().get_center().y
					and mcd.get_theme_font_size("font_size") >= 17, "")
				_ok("ⓔ ★倒计时高亮(字色与规矩那行不同)", mcd.get_theme_color("font_color") != mrl.get_theme_color("font_color"), "")
			var hint_ok := false
			for n_h in _walk(mode):
				if n_h is Label and str((n_h as Label).text).find("▸") >= 0 \
						and (n_h as Control).get_global_rect().end.x >= mr.end.x - 30.0:
					hint_ok = true
			_ok("ⓔ ★右边有「▸」提示能点(贴着卡右沿)", hint_ok)
			_ok("ⓔ ★与开始战斗底沿对齐(差 ≤2)", absf(mr.end.y - hr.end.y) <= 2.0, "%.0f / %.0f" % [mr.end.y, hr.end.y])
			_ok("ⓔ ★模式卡比开始战斗小", mr.size.x * mr.size.y < hr.size.x * hr.size.y, "")
			var mtxt: Array = []
			for n_e in _walk(mode):
				if n_e is Label and str((n_e as Label).text).strip_edges() != "":
					mtxt.append(str((n_e as Label).text))
			var now_e: int = int(_menu._now_ts())
			var want_e: Array = _menu.mode_card_lines(now_e)
			var ph_e: String = str(_P2A.PHASE_LABEL.get(_P2A.phase_at_utc(now_e), "?"))
			print("  ⓔ 模式卡的字: %s" % str(mtxt))
			_ok("ⓔ ★卡上写着今天的赛制「%s」(查表, 不问被测函数)" % ph_e, mtxt.has(ph_e), str(mtxt))
			_ok("ⓔ ★卡上三行 == mode_card_lines(现在)", want_e.size() == 3 and mtxt.has(str(want_e[0])) and mtxt.has(str(want_e[1])) and mtxt.has(str(want_e[2])),
				"要 %s" % str(want_e))
			_ok("ⓔ ★一句规矩非空、倒计时非空", str(want_e[1]) != "" and str(want_e[2]) != "", str(want_e))
			## 七天每天都说对: 喂七个已知日期, 第一行 == 那天的赛制(查表)
			var wrong_e: Array = []
			var cds: Dictionary = {}
			for d_e in range(7):
				var ts_e: int = 1789862400 + d_e * 86400 + 12 * 3600
				var ln_e: Array = _menu.mode_card_lines(ts_e)
				var want_ph: String = str(_P2A.PHASE_LABEL.get(_P2A.phase_of_weekday(7 if d_e == 0 else d_e), "?"))
				if str(ln_e[0]) != want_ph:
					wrong_e.append("%d:%s≠%s" % [d_e, str(ln_e[0]), want_ph])
				cds[str(ln_e[2])] = true
			_ok("ⓔ ★七天各喂一次: 卡上的赛制 == 那天的赛制", wrong_e.is_empty(), str(wrong_e))
			_ok("ⓔ ★分母: 七天的倒计时行至少 4 种(一种 = 没跟着时间走)", cds.size() >= 4, str(cds.keys()))

	# ── ⓕ ★点模式卡 ⇒ 弹出整周赛程(原来那条赛程条, 组件原样复用) ──
	var pop: Control = _find_named(_menu, str(MENU_S.WEEK_POPUP_NAME)) as Control
	var strip: Control = _find_named(_menu, "WeekStrip") as Control
	_ok("ⓕ ★分母: 赛程弹层与赛程条都在场", pop != null and strip != null)
	if pop != null and strip != null and mode != null:
		_ok("ⓕ ★赛程条住在弹层里(不再贴底常驻)", pop.is_ancestor_of(strip))
		_ok("ⓕ ★平时弹层藏着(主屏上看不见赛程条)", not pop.is_visible_in_tree() and not strip.is_visible_in_tree())
		## ★压暗色块量它**自己的** visible(弹层藏着时 is_visible_in_tree 恒假 = 空检查; 变异 N15 第一版就是这么漏的)。
		var dim0: Node = _find_named(pop, str(MENU_S.WEEK_DIM_NAME))
		_ok("ⓕ2 ★平时压暗色块自己也藏着(不当一块铺满屏的拦截层)", dim0 is Control and not (dim0 as Control).visible)
		var wide_vis: Array = []
		for c in all:
			if c is PanelContainer and (c as Control).get_global_rect().size.x >= W * 0.5:
				wide_vis.append(str(c.name))
		_ok("ⓕ ★主屏上没有横贯半屏以上的长条(满宽赛程条已收起)", wide_vis.is_empty(), str(wide_vis))
		var mtap: BaseButton = null
		for n_f in _walk(mode):
			if n_f is BaseButton:
				mtap = n_f
		_ok("ⓕ ★分母: 模式卡上有可点的按钮", mtap != null)
		if mtap != null:
			mtap.pressed.emit()
			for _i_f in range(3):
				await get_tree().process_frame
			_ok("ⓕ ★★点模式卡 ⇒ 弹层与赛程条都看得见了", pop.is_visible_in_tree() and strip.is_visible_in_tree())
			var srf: Rect2 = strip.get_global_rect()
			print("  ⓕ 弹出的赛程条 @(%.0f,%.0f) %.0f×%.0f" % [srf.position.x, srf.position.y, srf.size.x, srf.size.y])
			_ok("ⓕ ★弹出的赛程条整条在屏内", Rect2(0, 0, W, H).encloses(srf), str(srf))
			var day_n := 0
			for n_f in _walk(strip):
				if n_f is Button and str(n_f.name).begins_with(str(MENU_S.DAY_TAP_PREFIX)):
					day_n += 1
			_ok("ⓕ ★弹出的就是七天赛程(七格都在)", day_n == 7, "%d 格" % day_n)
			## 弹层盖在所有入口上面: 弹层在 content_root 子节点里排最后
			_ok("ⓕ ★弹层排在内容层最上面(不被入口盖住)", content.get_child(content.get_child_count() - 1) == pop)
			## 关得回去: 走「收起」那颗真按钮
			var close_b: Node = _find_named(pop, "WeekPopupClose")
			var cb_btn: BaseButton = null
			if close_b != null:
				for n_f in _walk(close_b):
					if n_f is BaseButton:
						cb_btn = n_f
			_ok("ⓕ ★分母: 弹层里有「收起」键", cb_btn != null)
			if cb_btn != null:
				cb_btn.pressed.emit()
				await get_tree().process_frame
				_ok("ⓕ ★按「收起」⇒ 弹层藏回去", not pop.is_visible_in_tree())
			## ⓕ2 返工: 表头一行(标题左、收起右, 紧贴条子上沿) + 点压暗处也能关
			var ttl: Control = _find_named(pop, "WeekPopupTitle") as Control
			_ok("ⓕ2 ★分母: 弹层标题在场", ttl != null and close_b != null)
			if ttl != null and close_b != null:
				var tr2: Rect2 = ttl.get_global_rect()
				var cr2: Rect2 = (close_b as Control).get_global_rect()
				_ok("ⓕ2 ★标题与「收起」同一行(竖向中心差 ≤ 4)", absf(tr2.get_center().y - cr2.get_center().y) <= 4.0, "%s / %s" % [str(tr2), str(cr2)])
				_ok("ⓕ2 ★标题在左端、「收起」在右端(各对齐条子左右沿 ≤ 8)", absf(tr2.position.x - srf.position.x) <= 8.0 and absf(cr2.end.x - srf.end.x) <= 8.0,
					"条 %s" % str(srf))
				_ok("ⓕ2 ★表头紧贴条子上沿(间距 0..8)", srf.position.y - cr2.end.y >= 0.0 and srf.position.y - cr2.end.y <= 8.0, "%.0f" % (srf.position.y - cr2.end.y))
			var dim: Control = _find_named(pop, str(MENU_S.WEEK_DIM_NAME)) as Control
			_ok("ⓕ2 ★分母: 压暗色块在场", dim != null)
			if dim != null:
				mtap.pressed.emit()
				await get_tree().process_frame
				var dr: Rect2 = dim.get_global_rect()
				_ok("ⓕ2 ★压暗盖住宽屏两侧(左右各外扩 ≥ 140)", dr.position.x <= -140.0 and dr.end.x >= W + 140.0 and dr.position.y <= 0.0 and dr.end.y >= H, str(dr))
				_ok("ⓕ2 ★压暗处吃点击(不是摆设)", dim.mouse_filter == Control.MOUSE_FILTER_STOP and dim.is_visible_in_tree())
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				ev.position = Vector2(30.0, 30.0)
				dim.gui_input.emit(ev)
				await get_tree().process_frame
				_ok("ⓕ2 ★★点弹层外面的压暗处 ⇒ 弹层关上", not pop.is_visible_in_tree())

	# ── ⑧ ★主 CTA 的字号仍要压过次级入口 ──
	var f_hero := _font_of(content, "开始战斗")
	var f_sub := _font_of(content, "图鉴")
	_ok("★分母: 两个字号都量到了(0 = 没找到那个 Label)", f_hero > 0 and f_sub > 0,
		"hero %d / sub %d" % [f_hero, f_sub])
	_ok("⑧ ★主CTA 字号明显大于次级入口 (≥ +4)", f_hero - f_sub >= 4, "%d vs %d" % [f_hero, f_sub])

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
		var vcov: Array = []
		for t9 in taps:
			if (t9 as Control).get_global_rect().intersects(vrect.grow(-2.0)):
				vcov.append(_tag(t9))
		_ok("⑨ ★版本号不被任何可点元素盖住(右下角现在是主 CTA)", vcov.is_empty(), str(vcov))
		_ok("⑨ ★版本号整行在屏内(底沿离屏底 ≥ 2px, 不贴边被切)", vrect.end.y <= H - 2.0, "底沿 %.0f" % vrect.end.y)

	# ── ⑬ ★赛程条的内容: 七天齐全 + 四个阶段名 + 恰好一天标「今天」──
	#    2026-09-18 改口径: 原来这条量的是「左右两栏【中间】那条空档里有没有赛程条」,
	#    而赛程条已按方案挪到【贴底】(中间那块还给了背景的龟群像)。
	#    ★位置的判据已经在 ④ 里了; 这里只管【内容对不对】, 两件事分开量。
	#    这三条与"今天是星期几"无关, 任何一天跑都该绿; 日期/时区的判定在 verify_week_season ⑥。
	var strip_txt: Array = []
	if strip != null:
		var q: Array = [strip]
		while not q.is_empty():
			var nd = q.pop_back()
			for ch in nd.get_children():
				q.append(ch)
				if ch is Label and str((ch as Label).text).strip_edges() != "":
					strip_txt.append(str((ch as Label).text).strip_edges())
	print("  ⑬ 赛程条里有 %d 条文字: %s" % [strip_txt.size(), str(strip_txt)])
	_ok("⑬ ★分母: 赛程条里量到文字 (0 条 = 条子是空的, 下面全是空检查)",
		strip_txt.size() >= 10, "%d 条" % strip_txt.size())
	var miss_d: Array = []
	for d3 in ["一", "二", "三", "四", "五", "六", "日"]:
		if not strip_txt.has(d3):
			miss_d.append(d3)
	_ok("⑬ ★七天一天不少", miss_d.is_empty(), "缺 %s" % str(miss_d))
	var joined := "
".join(PackedStringArray(strip_txt))
	var miss_p: Array = []
	for p3 in ["休赛", "积分赛", "闯关赛", "决赛日"]:
		if joined.find(p3) < 0:
			miss_p.append(p3)
	_ok("⑬ ★四个阶段名都在(缺一个就说明赛程表漏了一段)", miss_p.is_empty(), "缺 %s" % str(miss_p))
	var todays := 0
	for t3 in strip_txt:
		if str(t3).ends_with(" 今"):     # 横条上今天那格的阶段名后缀「今」(格子只有 92px, 光靠金边读不出)
			todays += 1
	_ok("⑬ ★恰好一天被标成今天(0=看不出今天 · >1=算错了)", todays == 1, "%d 个" % todays)

	# ── ⑬b ★收盘块说的话必须是**今天真能做到的事** (2026-09-22) ──
	#    闯关赛/决赛日/休赛的玩法还没上线, 那三天实际走的是积分赛规则(照常开局、吃配额)。
	#    在此之前周日写「决赛日 本地 X 点开打」、周一写「本日维护」—— 两句都做不到。
	#    ★判据**跟着纯函数走**, 不在这里另写一份"今天该说什么":
	#      `phase_pending_note()` 是 UI 与门禁共用的那一个答案(七天全量在 verify_week_season ⑦)。
	#    ★任何一天跑都成立: 周二~周五 → 要有倒计时/封盘; 周一六日 → 要有那句「开发中」。
	var _P2M := preload("res://scripts/gamedata/phase2_config.gd")
	var now_ts: int = int(Time.get_unix_time_from_system())
	var today_ph: String = _P2M.phase_at_utc(now_ts)
	var note_today: String = _P2M.phase_pending_note(today_ph)
	if note_today != "":
		_ok("⑬b ★今天是「%s」(玩法还没上线) → 收盘块必须直说" % today_ph,
			joined.find(note_today) >= 0, "条子里没有「%s」: %s" % [note_today, str(strip_txt)])
		## ★★2026-09-28 这条分母原来是 `note_today.find("开发中") >= 0` ——
		##   拿**开发状态词**当「这句话来自产品」的证据。而「开发中」这类词
		##   正是这一轮要从玩家面前摘掉的东西(玩家不需要知道我们还没做完,
		##   只需要知道**现在按什么规则打**)⇒ 产品一改对, 这条分母就红。
		##   典型的「门禁把 bug 钉在原地」: 判据替那个缺陷站了岗。
		## ★改成量它**本来想证明的那件事**: 这句话得是产品纯函数算出来的、
		##   而且**说清了今天按谁的规矩打**。后者用 `PHASE_LABEL` 那张表取,
		##   **不在门禁里抄一份字面量** —— 抄了就又变成一份会落后的副本。
		var _rk_name: String = str(_P2M.PHASE_LABEL.get(_P2M.PHASE_RANKED, ""))
		_ok("⑬b ★分母: 那句话是产品纯函数给的, 且说清了今天按谁的规矩打",
			_rk_name != "" and note_today.find(_rk_name) >= 0,
			"规矩名「%s」/ 那句话「%s」" % [_rk_name, note_today])
		## ★同时守住: 屏幕上**不许**出现开发状态词。
		##   (原判据是「必须含开发中」, 现在是「不许含」—— 方向反过来了,
		##    因为当初那个「必须」本身就是在替缺陷站岗。)
		var _devw: Array = ["开发中", "打磨", "待做", "TODO", "占位", "未实现", "暂按", "暂锁", "还没做"]
		var _hit_dev: Array = []
		for _w in _devw:
			if note_today.find(str(_w)) >= 0:
				_hit_dev.append(_w)
		_ok("⑬b ★收盘块不许把开发状态说给玩家听",
			_hit_dev.is_empty(), "命中: %s ← 「%s」" % [str(_hit_dev), note_today])
	elif today_ph == _P2M.PHASE_FINALS:
		## ★★★2026-09-27 补上这一支。原来 else 那一支写着「今天是积分赛」, 而
		##   `phase_pending_note()` 为空的条件是**玩法已上线** —— 周六闯关赛(2026-09-22 上线)
		##   与周日决赛日(2026-09-25 上线)从那以后也会落进来, 而它们的收盘块根本不是倒计时。
		##   ⇒ 判据一直是错的, 只是**一周里只有周六周日碰得到**, 今天(周日)才第一次红。
		##   又一条「判据挂在星期几上」(同族已修四条, 见 v0.19.446)。
		## ★周日收盘块 = **进对阵图的门**(`close_block_kind` 返回 BK_BRACKET_DOOR)。
		## ★★判据要量**按钮**, 不是文字: 上面那个 `strip_txt` 只收 Label,
		##   而决赛日那扇门 `_finals_entry()` 返回的是 Button ⇒ 它的字根本不在 strip_txt 里。
		##   (我第一版就是拿 strip_txt 找「对阵图」, 当场红 —— 判据没卡在被测的那个量上。)
		var door_ok := false
		if strip != null:
			var q2: Array = [strip]
			while not q2.is_empty():
				var nd2 = q2.pop_back()
				for ch2 in nd2.get_children():
					q2.append(ch2)
					if ch2 is Button and str((ch2 as Button).text).find("对阵图") >= 0:
						door_ok = true
		_ok("⑬b ★今天是决赛日(已上线) → 收盘块里有一个【进对阵图】的按钮",
			door_ok, "条里的文字: %s" % str(strip_txt))
	elif today_ph == _P2M.PHASE_GAUNTLET:
		## 周六闯关赛(已上线): 与积分赛一样有收盘(WEEK_CLOSE_HOUR_UTC), 所以照旧是倒计时/封盘
		## ★★2026-10-04: 原来接受「维护」二字 ⇒ 收盘后那句错话「休赛日 · 周二开赛 · **本日维护**」反而让它绿
		##   (门禁替 bug 站岗)。改成按收盘前/后分开判, 维护只认真正的维护态「维护中」。
		if _P2M.close_left_sec(now_ts) < 0:
			_ok("⑬b ★今天是闯关赛(已上线)、已过收盘 → 「今日已收盘」并说明天",
				joined.find("今日已收盘") >= 0 and joined.find("明天") >= 0 and joined.find("休赛日") < 0
				or joined.find("维护中") >= 0, str(strip_txt))
		else:
			_ok("⑬b ★今天是闯关赛(已上线) → 收盘块给的是倒计时或封盘提示",
				joined.find("距收盘") >= 0 or joined.find("已封盘") >= 0
				or joined.find("维护中") >= 0, str(strip_txt))
	else:
		## 积分赛那几天照旧: 要么在倒计时, 要么已进封盘窗口(收盘前 10 分钟)
		## ★★2026-10-04: 原来接受「维护」二字 ⇒ 收盘后那句错话「休赛日 · 周二开赛 · **本日维护**」反而让它绿
		##   (门禁替 bug 站岗)。改成按收盘前/后分开判, 维护只认真正的维护态「维护中」。
		if _P2M.close_left_sec(now_ts) < 0:
			_ok("⑬b ★今天是积分赛、已过收盘 → 「今日已收盘」并说明天",
				joined.find("今日已收盘") >= 0 and joined.find("明天") >= 0 and joined.find("休赛日") < 0
				or joined.find("维护中") >= 0, str(strip_txt))
		else:
			_ok("⑬b ★今天是积分赛 → 收盘块给的是倒计时或封盘提示",
				joined.find("距收盘") >= 0 or joined.find("已封盘") >= 0
				or joined.find("维护中") >= 0, str(strip_txt))

	# ── ⑬c ★**四个阶段各喂一个已知日期**, 别只量"今天"那一格 ──
	#    上面 ⑬b 量的是今天 —— 一周里有四天走不到周末那半, 等于那几天它是空检查
	#    (跑门禁的日子决定判据强弱 = 判据本身不可靠)。
	#    `_week_close_block(now)` 本来就收时间戳 ⇒ 直接喂四个已知日期, **调产品那个真函数**。
	#    ★★判据**不问 `phase_pending_note()` 这一天要不要挂提示** —— 那是拿被测函数当尺子:
	#      它若退化成"永远返回空串", 判据会跟着走进 else 分支、然后全绿
	#      (实测: 变异 M3 第一版没红, 就是栽在这里; 同一份文件 ⑥ 的注释早写过这条)。
	#      「哪几天要挂」由**星期几 + 开关**决定, 写死在下面这张表里。
	#    ★★2026-09-22 E-A: 周六闯关赛**已上线** ⇒ 它那格不再挂「还没上线」, 改成照常倒计时。
	#      表里第二列就是期望值本身, 跟着 `PHASE_MODE_LIVE` 手动同步 ——
	#      **故意不写成 `not phase_mode_live(...)`**: 那是拿被测函数当尺子(今天栽过一次)。
	var DAYS := {                      # 显示名: [时间戳, 这天要不要挂「还没上线」提示]
		## 第二列 = 这天那一格**应该长什么样**, 三档:
		##   "note"      —— 玩法没上线, 要说清暂按什么规则
		##   "countdown" —— 有收盘概念, 给倒计时/封盘提示
		##   "door"      —— ★★2026-09-25 新增: 周日决赛日上线后这一格是
		##                 **进对阵图的门**(一个 Button, 不是两行字)。
		##                 原来只有前两档 ⇒ 翻开关那天「建不出文字」+「没倒计时」两条假红。
		"周一休赛": [1789344000, "note"],
		"周四积分赛": [1789603200, "countdown"],
		## ★★2026-10-04 周末看回放: 周六那一格变成**赛况板的门**, 门上第一行仍是倒计时
		##   (docs/plans/20261004-周末看回放.md)。原来是 "countdown" 两行字。
		"周六闯关赛": [1789776000, "board_door"],
		## ★★2026-09-25 用户「周日要打开」 ⇒ PHASE_MODE_LIVE[FINALS] 翻成 true,
		##   周日那格不再挂「还没上线」, 改成照常倒计时(与周六同)。
		##   下一个阶段上线时还是手动同步这一列 —— 故意不写成
		##   `not phase_mode_live(...)`(拿被测函数当尺子, 见上方长注释)。
		"周日决赛日": [1789862400, "door"],
	}
	for dn in DAYS.keys():
		var ts_d: int = int((DAYS[dn] as Array)[0])
		var want_kind: String = str((DAYS[dn] as Array)[1])
		var blk = _menu._week_close_block(ts_d)
		var btxt: Array = []
		var bq: Array = [blk]
		while not bq.is_empty():
			var bn = bq.pop_back()
			for bc in bn.get_children():
				bq.append(bc)
				if bc is Label:
					btxt.append(str((bc as Label).text).strip_edges())
		var bj := " / ".join(PackedStringArray(btxt))
		var want_note: String = _P2M.phase_pending_note(_P2M.phase_at_utc(ts_d))
		if want_kind == "door" or want_kind == "board_door":
			## ★★★周日决赛日上线之后这一格是**门**不是字。判据卡三件:
			##   ① 真的建出了一个能按的 Button(不是摆一行字冒充)
			##   ② 上面写着通到哪(玩家得看得懂按下去会发生什么)
			##   ③ **接了处理函数** —— 「点了没反应比按钮是灰的糟得多」是本仓原则,
			##      而「有按钮」不证明「按了有用」(zero_caller 那一族)。
			## ★根节点自己也可能就是那个 Button ⇒ 从 blk 起遍历、**只数一次**。
			##   (第一版在循环外又 append 了一次 blk, 分母打成「Button 2 个」
			##    而其实只有 1 个 —— 分母算错的判据看着更"强"其实在骗人。)
			var btns: Array = []
			var q2: Array = [blk]
			while not q2.is_empty():
				var n2 = q2.pop_back()
				if n2 is Button:
					btns.append(n2)
				for c2 in n2.get_children():
					q2.append(c2)
			_ok("⑬c ★★分母(%s): 真建出了一个能按的门" % dn, btns.size() >= 1,
				"Button %d 个 / 文字 %s" % [btns.size(), bj])
			if btns.size() >= 1:
				var bt: Button = btns[0]
				if want_kind == "board_door":
					## 周六: 门上第一行**照常给倒计时**(原 "countdown" 那条判据搬到门上), 第二行说通到哪
					## 门是「牌子 + 透明按钮」, 字在牌子上的 Label 里(bj)
					_ok("⑬c ★%s: 门上照常给倒计时" % dn,
						bj.find("距收盘") >= 0 or bj.find("已封盘") >= 0, bj)
					_ok("⑬c ★%s: 门上写着通到哪(全场赛况)" % dn, bj.find("全场赛况") >= 0, bj)
				else:
					_ok("⑬c ★%s: 门上写着通到哪(玩家看得懂)" % dn,
						str(bt.text).find("对阵图") >= 0, str(bt.text).replace("\n", "⏎"))
				_ok("⑬c ★★%s: 门**接了处理函数**(有按钮 ≠ 按了有用)" % dn,
					bt.pressed.get_connections().size() >= 1,
					"连了 %d 个" % bt.pressed.get_connections().size())
			blk.queue_free()
			continue
		_ok("⑬c ★分母(%s): 收盘块真建出了文字" % dn, btxt.size() >= 2, bj)
		if want_kind == "note":
			## ① 屏幕上必须说清**实际会发生什么** —— 判据不引 `phase_pending_note()`
			##   (拿被测函数当尺子: 它退化成空串时, 判据会跟着走进 else 分支然后全绿)。
			## ★★2026-09-27 needle 从「暂按积分赛规则」换成**这天实际按哪个赛制的规矩打**,
			##   取 `PHASE_LABEL[PHASE_RANKED]`(玩家看到的那个阶段名) —— 那是一张**数据表**、
			##   不是被测函数, 而且它就是"按谁的规矩"这条信息本身。
			##   换的原因: 「暂按」「开发中」是**开发备注印给了玩家**, 已从产品里摘掉
			##   (见 `phase2_config.PHASE_PENDING_NOTE` 头注 2026-09-27 那段)。
			##   判据不许把那几个词焊回去 —— 否则它会替那个缺陷站岗。
			## ★只换 needle 是半条: 换完还得守住"别人再把开发状态词加回来" ⇒ 多一条。
			_ok("⑬c ★%s: 条子上必须说清这天按【哪个赛制】的规矩打" % dn,
				bj.find(str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED])) >= 0,
				"要出现「%s」· 条子上是「%s」" % [str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED]), bj])
			var devnote: Array = []
			for w in ["开发中", "暂按", "待做", "TODO", "占位", "未实现"]:
				if bj.find(str(w)) >= 0:
					devnote.append(str(w))
			_ok("⑬c ★★%s: 屏幕上不许出现开发状态词(玩家不需要知道我们做到哪了)" % dn,
				devnote.is_empty(), "撞上 %s · 条子上是「%s」" % [str(devnote), bj])
			## ② 而且必须**就是产品那个纯函数给的那一句**(否则 UI 自己抄了一份, 必然漂)
			_ok("⑬c ★%s: 条子上那句 == phase_pending_note() 给的那句" % dn,
				want_note != "" and bj.find(want_note) >= 0,
				"函数给「%s」· 条子上是「%s」" % [want_note, bj])
			## ★同时**不许**再出现那两句做不到的话 —— 只查"有没有加新句子"是半条判据
			_ok("⑬c ★%s: 不再说「本日维护」/「开打」这类做不到的话" % dn,
				bj.find("维护") < 0 and bj.find("开打") < 0, bj)
		else:
			## 玩法已上线的阶段: 积分赛(周五 23:00 收盘)与闯关赛(周六 23:00 收盘)
			## 都有收盘概念 ⇒ 必须给倒计时或封盘提示, 不许是别的话。
			_ok("⑬c ★%s: 照常给倒计时" % dn,
				bj.find("距收盘") >= 0 or bj.find("已封盘") >= 0, bj)
		blk.queue_free()

	# ── ⑬e ★BK_PENDING 的【兜底那一句】也不许把开发状态说给玩家听 (2026-09-28) ──
	#  ★由来: `MainMenuScene._week_close_block` 里 BK_PENDING 那一支有一条兜底,
	#    原文是「玩法开发中, 暂按积分赛规则」—— 而 ⑬b/⑬c **一条都走不到它**:
	#    它只在「kind=BK_PENDING 而 `phase_pending_note()` 给空串」时才上屏,
	#    那要 `strip_finals_live_override` 把决赛日手动按成"没上线"
	#    (`PHASE_MODE_LIVE[FINALS]` 已是 true ⇒ 纯函数返回 "")。
	#    ⇒ 在此之前唯一守它的只有文案快照(而快照只证明"字没变", 不证明"字是对的")。
	#    这里把那个局面**真的造出来**再量, 判据与 ⑬c 的 note 档同一条口径。
	var _ov0: int = int(_menu.strip_finals_live_override)
	_menu.strip_finals_live_override = 0          # 0 = 手动按成「玩法没上线」
	var sun_ts: int = 1789862400                  # 周日(与 ⑬c 同一个时刻)
	_ok("⑬e ★分母①: 这个局面真是 BK_PENDING(纯静态函数穷举得到)",
		MENU_S.close_block_kind(_P2M.PHASE_FINALS, false, false, -1, false) == MENU_S.BK_PENDING,
		str(MENU_S.close_block_kind(_P2M.PHASE_FINALS, false, false, -1, false)))
	_ok("⑬e ★分母②: 纯函数这时给的是空串 ⇒ 走的正是那条兜底",
		_P2M.phase_pending_note(_P2M.PHASE_FINALS) == "",
		"给了「%s」" % _P2M.phase_pending_note(_P2M.PHASE_FINALS))
	var blk_e = _menu._week_close_block(sun_ts)
	var etxt: Array = []
	var eq: Array = [blk_e]
	while not eq.is_empty():
		var en = eq.pop_back()
		for ec in en.get_children():
			eq.append(ec)
			if ec is Label:
				etxt.append(str((ec as Label).text).strip_edges())
	var ej := " / ".join(PackedStringArray(etxt))
	_ok("⑬e ★分母③: 兜底那一格真建出了文字", etxt.size() >= 2, ej)
	_ok("⑬e 兜底那句也说清了这天按【哪个赛制】的规矩打",
		ej.find(str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED])) >= 0,
		"要出现「%s」· 条子上是「%s」" % [str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED]), ej])
	var edev: Array = []
	for ew in ["开发中", "打磨", "暂按", "暂锁", "待做", "TODO", "占位", "未实现", "还没做"]:
		if ej.find(str(ew)) >= 0:
			edev.append(str(ew))
	_ok("⑬e ★★兜底那句不许出现开发状态词(玩家不需要知道我们做到哪了)",
		edev.is_empty(), "撞上 %s · 条子上是「%s」" % [str(edev), ej])
	blk_e.queue_free()
	_menu.strip_finals_live_override = _ov0

	# ── ⑬d ★两条拦截提示说的也得是**今天真会发生的事** (2026-09-22) ──
	#    原文案「等周六闯关赛(开赛观战)」在闯关赛玩法没上线时是做不到的事。
	#    ★走**真入口**(`_start_battle_flow()` / `_open_shop()`), 量真的飘出来的那行字 ——
	#      只调 `_msg_*()` 等于测我自己新写的函数, 证明不了产品那两处真在用它
	#      (memory `fb-verify-must-run-the-real-path`)。
	#    ⚠ 这两个入口**没被拦住时会 change_scene** ⇒ 当场拆掉门禁自己。
	#      所以每次调用前先断言「确实处在被拦的状态」(这条同时就是分母)。
	var gs_m = get_node_or_null("/root/GameState")
	if gs_m == null:
		print("  [FAIL] ⑬d ★分母: 拿不到 GameState"); _fail += 1
	else:
		var kp_h: int = int(gs_m.hearts)
		var kp_u: int = int(gs_m.ranked_used)
		var kp_pr = gs_m.promoted
		var kp_gw: int = int(gs_m.gauntlet_wins)
		var kp_gl: int = int(gs_m.gauntlet_losses)
		## ★★提示语现在跟**玩家真实状态**走(晋级了就说"周六闯关赛见"), 不再跟开关走。
		##   所以这一组要先把状态钉死成「没晋级」, 否则下面那条判据在晋级时会假红。
		## ★★★2026-09-26 把「现在是哪一刻」钉死成**周四(积分赛)**。
		##   不钉的话这一整段跟着今天星期几变: UTC 周六时已晋级的 0 命玩家**可以**打闯关赛
		##   ⇒ `_start_battle_flow()` 一路走到 `change_scene_to_file` ⇒ **当场把门禁拆掉**
		##   (`get_tree()` 变 null), 后面所有断言连跑都没跑, 而且**没打 ALL PASS**、rc 还是 0。
		##   ⇒ 这份门禁一周里有两天(周六/周日)是**整份不算数**的, 而平时看不见。
		## ★1789603200 = 2026-09-24 周四 00:00 UTC(与 ⑬c 那张表同一个时间戳)。
		_menu.clock_override_ts = 1789603200
		gs_m.promoted = false
		gs_m.gauntlet_wins = 0
		gs_m.gauntlet_losses = 0
		_ok("⑬d ★分母: 已钉成「没晋级」(否则「不许说闯关赛」那条会假红)",
			not gs_m.gauntlet_eligible(), "promoted=%s" % str(gs_m.promoted))
		for case_name in ["出局", "配额打满"]:
			if case_name == "出局":
				gs_m.hearts = 0
			else:
				gs_m.hearts = 8
				gs_m.ranked_used = int(_P2M.RANKED_QUOTA)
			var blocked: bool = gs_m.is_eliminated() if case_name == "出局" \
				## ★把钉死的那一刻也传给 `ranked_quota_full()` —— 它同样默认走真实时铟,
				##   而它内部先问 `phase_uses_ranked_quota(phase_at_utc(ts))`:
				##   UTC 周六/周日不吃积分赛配额 ⇒ 恒返回 false ⇒ 这条分母在周末必红,
				##   而红的原因与被测行为无关(判据挂在星期几上)。
				else gs_m.ranked_quota_full(_menu.clock_override_ts)
			_ok("⑬d ★分母(%s): 确实处在被拦的状态(否则下面会切场景拆掉门禁)" % case_name,
				blocked, "hearts=%d ranked_used=%d" % [int(gs_m.hearts), int(gs_m.ranked_used)])
			if not blocked:
				continue
			## ★只看【这次调用新增的】子节点 —— 主菜单本来就有直属 Label,
			##   "取最后一个 Label" 会撞到它们(判据要刚好卡住那个形状)。
			var before_kids: Array = _menu.get_children()
			if case_name == "出局":
				_menu._start_battle_flow()
			else:
				_menu._open_shop()
			var toast_txt := ""
			var new_kids: Array = []
			for ch_t in _menu.get_children():
				if not before_kids.has(ch_t):
					new_kids.append(ch_t)
					if ch_t is Label:
						toast_txt = str((ch_t as Label).text)
			_ok("⑬d ★分母(%s): 真多出了一个子节点且是一行字" % case_name,
				new_kids.size() == 1 and toast_txt != "",
				"新增 %d 个子节点, 文字「%s」" % [new_kids.size(), toast_txt])
			var want_msg: String = _menu._msg_eliminated() if case_name == "出局" \
				else _menu._msg_quota_full()
			_ok("⑬d ★%s: 飘的就是 _msg_*() 那一句(两个入口不许各写一份)" % case_name,
				toast_txt == want_msg, "飘出「%s」· 函数给「%s」" % [toast_txt, want_msg])
			## ★★没晋级的人**不许**被指向闯关赛(他周六根本打不了), 也不许提「观战」
			##   (观赛入口是 F 阶段, 一行都没有)。这条判据写死, 不问被测函数。
			##   ⚠ 前提: 上面把 `promoted` 置成了 false, 见那一行的分母断言。
			_ok("⑬d ★%s: 没晋级 → 不许说「闯关赛」「观战」" % case_name,
				toast_txt.find("闯关赛") < 0 and toast_txt.find("观战") < 0, toast_txt)
			for ch_c in new_kids:
				ch_c.queue_free()
		## ★★晋级了的人**应该**被指向周六 —— 反过来也验一遍, 否则
		##   「永远不说闯关赛」也能让上面那条绿(一条判据只卡住一个方向 = 半条判据)。
		gs_m.promoted = true
		gs_m.hearts = 0
		var promo_txt := ""
		var kids0: Array = _menu.get_children()
		_menu._start_battle_flow()
		for ch_p in _menu.get_children():
			if not kids0.has(ch_p) and ch_p is Label:
				promo_txt = str((ch_p as Label).text)
				ch_p.queue_free()
		_ok("⑬d ★分母: 晋级态下真飘出了提示", promo_txt != "", promo_txt)
		_ok("⑬d ★★0 命但已晋级 → 要说周六闯关赛(不是「下周一」)",
			promo_txt.find("闯关赛") >= 0 and promo_txt.find("下周一") < 0, promo_txt)

		gs_m.hearts = kp_h
		gs_m.ranked_used = kp_u
		gs_m.promoted = kp_pr
		gs_m.gauntlet_wins = kp_gw
		gs_m.gauntlet_losses = kp_gl
		_menu.clock_override_ts = 0            # ★还原: 不还原会波及同文件后面的用例

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

	# ── ⑬z 货币区不含按钮材质(方案书 20260917 P0-2 / 验收「frame-coin.png 零引用」) ──
	#   量真建出来的节点: 全屏每张 TextureRect 的贴图路径。
	#   分母: 全屏确实扫到了按钮族木框(frame-rect, 训龟大师/开始战斗用的那张) ⇒ 扫描器看得见这一族。
	var tex_paths: Array = []
	for n_t in _walk(_menu):
		if n_t is TextureRect and (n_t as TextureRect).texture != null:
			tex_paths.append(str((n_t as TextureRect).texture.resource_path))
	var n_btn_frame := 0
	var n_coin_frame := 0
	for tp in tex_paths:
		if str(tp).find("menu/frame-rect") >= 0:
			n_btn_frame += 1
		if str(tp).find("frame-coin") >= 0:
			n_coin_frame += 1
	_ok("⑬z ★分母: 扫到了按钮族木框(frame-rect)", n_btn_frame > 0, "TextureRect %d 张, frame-rect %d" % [tex_paths.size(), n_btn_frame])
	_ok("⑬z ★货币芯片不再垫按钮族木框(frame-coin 零引用)", n_coin_frame == 0, "frame-coin %d 张" % n_coin_frame)

	# ── ⑮ ★擂台背景 + 主 CTA 呼吸光晕 (2026-10-05 · 方案书 20260917 R1 / R1-a / R1-b / R2) ──
	#
	# 由来: 背景从「28 只龟立绘拼的群像墙」换成「擂台 + 看台」场景, 会动; 主 CTA 加呼吸光晕 + 金边。
	#   用户的三句话是这一节的判据来源(逐字): R1「擂台 + 看台」/ R1-a「尽量不要复用好吗」/
	#   R1-b「不能用现有的龟立绘」/ R2「保留木框 + 呼吸光晕/金边」。
	# ★旧版式的判据(群像墙那几条)没有放宽, 是换掉: 那张图不在了, 量它等于量空气。
	# ★「会动」不看节点在不在, 看**状态真的变了** —— 直接喂确定的 dt 推 `step()`(帧率跟机器挂钩, 钟不该),
	#   另配一条「真入口的 _process 也在推钟」, 防止只有测试在喂、产品里是一张静图。
	var bds_15: Array = []
	for n_b_15 in _walk(_menu):
		if n_b_15 is MenuArenaBackdrop:
			bds_15.append(n_b_15)
	_ok("⑮a ★分母: 场景里恰有 1 个擂台背景(MenuArenaBackdrop)", bds_15.size() == 1, "%d 个" % bds_15.size())
	if bds_15.size() == 1:
		var bd_15: MenuArenaBackdrop = bds_15[0]
		var vr_15 := Rect2(Vector2.ZERO, Vector2(W, H))
		## ⑮b 盖满视口 + 自己裁边(① 不再逐层量背景, 前提就是这两条)
		var bd_r_15 := bd_15.get_global_rect()
		var stage_15: Control = bd_15.get_node_or_null("Stage")
		_ok("⑮b ★分母: 背景里有那块原生画布(Stage)", stage_15 != null)
		_ok("⑮b 背景控件盖满视口", bd_r_15.encloses(vr_15), str(bd_r_15))
		_ok("⑮b 背景裁边(clip_contents) —— 伸出屏外的画不许漏到别的层上", bd_15.clip_contents)
		if stage_15 != null:
			var st_r_15: Rect2 = stage_15.get_global_transform() * Rect2(Vector2.ZERO, stage_15.size)
			_ok("⑮b ★放大后的原生画布盖满视口(不留底色边)", st_r_15.encloses(vr_15), str(st_r_15))
			_ok("⑮b 等比放大(横竖同一倍率, 像素不变形)", absf(stage_15.scale.x - stage_15.scale.y) < 0.001,
				str(stage_15.scale))
		## ⑮c R1-a / R1-b: 背景里每一张贴图都是 arena/ 下新烘的, 一张旧图都没有
		var tps_15: Array = bd_15.texture_paths()
		var foreign_15: Array = []
		for tp_15 in tps_15:
			var sp_15 := str(tp_15)
			if not sp_15.begins_with("res://assets/sprites/menu/arena/baked/") \
					or sp_15.find("/pets/") >= 0 or sp_15.find("/map/") >= 0 or sp_15.find("menu-bg-crowd") >= 0:
				foreign_15.append(sp_15)
		_ok("⑮c ★分母: 背景用到的贴图 ≥ 20 张(看台/灯/火/旗/主角分层)", tps_15.size() >= 20, "%d 张" % tps_15.size())
		_ok("⑮c ★★R1-a/R1-b 背景只用新画的素材(不许出现龟立绘/地图件/旧群像)", foreign_15.is_empty(),
			str(foreign_15.slice(0, 3)))
		var crowd_on_screen_15 := 0
		for n_t2_15 in _walk(_menu):
			if n_t2_15 is TextureRect and (n_t2_15 as TextureRect).texture != null \
					and str((n_t2_15 as TextureRect).texture.resource_path).find("menu-bg-crowd") >= 0:
				crowd_on_screen_15 += 1
		_ok("⑮c 旧群像墙不在主菜单上了", crowd_on_screen_15 == 0, "%d 张" % crowd_on_screen_15)
		## ⑮d' 真入口在推钟(入场那几秒 _process 已经跑过)
		var lite_15: bool = bool(get_node("/root/GameState").perf_lite)
		var s_real_15: Dictionary = bd_15.debug_state()
		_ok("⑮d' ★真入口: 背景的 _process 开着(低画质才关)", bd_15.is_processing() == (not lite_15),
			"processing=%s perf_lite=%s" % [str(bd_15.is_processing()), str(lite_15)])
		_ok("⑮d' ★真入口: 背景的钟已经被 _process 推过(不是只有测试在喂)", float(s_real_15["t"]) > 0.0,
			"t=%.3f" % float(s_real_15["t"]))
		## ⑮d 会动: 喂 6 秒(> 一个出手循环 3.4 秒), 每 0.05 秒采一次
		var s0_15: Dictionary = bd_15.debug_state()
		var n_crowd_15: int = (s0_15["crowd_y"] as Array).size()
		var crowd_seen_15: Array = []
		for _i_15 in range(n_crowd_15):
			crowd_seen_15.append({})
		var flame_seen_15: Array = [{}, {}]
		var la_lo_15: Array = []
		var la_hi_15: Array = []
		for _i_15 in range((s0_15["light_a"] as Array).size()):
			la_lo_15.append(1.0)
			la_hi_15.append(0.0)
		var poses_15 := {}
		var dposes_15 := {}
		var steps_15 := 120
		for _k_15 in range(steps_15):
			bd_15.step(0.05)
			var st_15: Dictionary = bd_15.debug_state()
			for i_15 in range(n_crowd_15):
				(crowd_seen_15[i_15] as Dictionary)[float(st_15["crowd_y"][i_15])] = true
			for i_15 in range(mini(2, (st_15["flame_idx"] as Array).size())):
				(flame_seen_15[i_15] as Dictionary)[int(st_15["flame_idx"][i_15])] = true
			for i_15 in range(la_lo_15.size()):
				la_lo_15[i_15] = minf(float(la_lo_15[i_15]), float(st_15["light_a"][i_15]))
				la_hi_15[i_15] = maxf(float(la_hi_15[i_15]), float(st_15["light_a"][i_15]))
			poses_15[str(st_15["atk_pose"])] = true
			dposes_15[str(st_15["def_pose"])] = true
		var s1_15: Dictionary = bd_15.debug_state()
		var hopping_15 := 0
		for d_15 in crowd_seen_15:
			if (d_15 as Dictionary).has(0.0) and (d_15 as Dictionary).has(-1.0):
				hopping_15 += 1
		_ok("⑮d ★分母: 看台分层 ≥ 10 层", n_crowd_15 >= 10, "%d 层" % n_crowd_15)
		_ok("⑮d ★看台观众在蹦: ≥ 80%% 的层 6 秒内都到过「原位」和「上 1 格」", hopping_15 * 5 >= n_crowd_15 * 4,
			"%d / %d 层" % [hopping_15, n_crowd_15])
		_ok("⑮d ★两个火盆都在换帧(各 ≥ 3 种帧)", (flame_seen_15[0] as Dictionary).size() >= 3 and (flame_seen_15[1] as Dictionary).size() >= 3,
			"%d / %d 种" % [(flame_seen_15[0] as Dictionary).size(), (flame_seen_15[1] as Dictionary).size()])
		var flat_lights_15 := 0
		for i_15 in range(la_lo_15.size()):
			if float(la_hi_15[i_15]) - float(la_lo_15[i_15]) < 0.10:
				flat_lights_15 += 1
		_ok("⑮d ★分母: 顶沿灯分组 ≥ 2", la_lo_15.size() >= 2, "%d 组" % la_lo_15.size())
		_ok("⑮d 顶沿的灯每组都在明暗(幅度 ≥ 0.10)", flat_lights_15 == 0, "不动的 %d 组" % flat_lights_15)
		_ok("⑮d 旗子的摆动钟在走", float(s1_15["banner_t"]) - float(s0_15["banner_t"]) > 5.0,
			"%.2f → %.2f" % [float(s0_15["banner_t"]), float(s1_15["banner_t"])])
		_ok("⑮d ★进攻方三个姿势都出现过(架势/蓄力/突刺)", poses_15.has("stance") and poses_15.has("windup") and poses_15.has("thrust"),
			str(poses_15.keys()))
		_ok("⑮d ★防守方两个姿势都出现过(架盾/顶盾)", dposes_15.has("guard") and dposes_15.has("brace"), str(dposes_15.keys()))
		## ⑮e 主角是这张图的焦点 —— 不许被任何可点控件、赛程条盖住, 也不许出屏
		var frs_15: Array = bd_15.fighter_rects()
		print("  ⑮e 两只角斗龟 %s" % str(frs_15))
		_ok("⑮e ★分母: 量到两只角斗龟的框", frs_15.size() == 2, "%d 个" % frs_15.size())
		var covered_15: Array = []
		var strip_c_15: Control = strip if (strip != null and strip.is_visible_in_tree()) else null
		for fr_15 in frs_15:
			var fr2_15: Rect2 = fr_15
			if not vr_15.encloses(fr2_15):
				covered_15.append("出屏 %s" % str(fr2_15))
			for tp2_15 in _tappables(_menu):
				var tr2_15: Rect2 = (tp2_15 as Control).get_global_rect()
				if tr2_15.intersects(fr2_15):
					covered_15.append("%s 盖住 %s" % [_tag(tp2_15), str(fr2_15)])
			if strip_c_15 != null and strip_c_15.get_global_rect().intersects(fr2_15):
				covered_15.append("赛程条盖住 %s" % str(fr2_15))
		_ok("⑮e ★两只角斗龟完整露出(不压按钮/赛程条, 不出屏)", covered_15.is_empty(), str(covered_15.slice(0, 3)))
	## ⑮f R2: 主 CTA 的呼吸光晕 —— 全屏恰一个, 挂在「开始战斗」上, 真在呼吸, 金边在木框外沿
	var glows_15: Array = []
	for n_g_15 in _walk(_menu):
		if n_g_15 is MenuCtaGlow:
			glows_15.append(n_g_15)
	_ok("⑮f ★全屏恰 1 个呼吸光晕(主 CTA 的材质独一份)", glows_15.size() == 1, "%d 个" % glows_15.size())
	if glows_15.size() == 1:
		var gl_15: MenuCtaGlow = glows_15[0]
		var hero_h_15 := _entry_holder(page_box, "开始战斗")
		_ok("⑮f ★光晕挂在「开始战斗」那颗键上(不是训龟大师)", hero_h_15 != null and hero_h_15.is_ancestor_of(gl_15))
		if hero_h_15 != null:
			var hr2_15 := hero_h_15.get_global_rect()
			var gr2_15 := gl_15.get_global_rect()
			_ok("⑮f 金边在木框外沿一圈(光晕框包住按钮且四边都外扩)", gr2_15.encloses(hr2_15)
				and gr2_15.position.x < hr2_15.position.x and gr2_15.end.x > hr2_15.end.x
				and gr2_15.position.y < hr2_15.position.y and gr2_15.end.y > hr2_15.end.y, "%s vs %s" % [str(gr2_15), str(hr2_15)])
			_ok("⑮f 光晕垫在木框底下(不盖住字)", hero_h_15.get_children().find(gl_15) == 0)
		_ok("⑮f 叠加混合(发光, 不是一块不透明金色色块)", gl_15.material is CanvasItemMaterial
			and (gl_15.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)
		var a_lo_15 := 9.0
		var a_hi_15 := -9.0
		for _k_15 in range(60):
			gl_15.step(0.05)
			a_lo_15 = minf(a_lo_15, gl_15.modulate.a)
			a_hi_15 = maxf(a_hi_15, gl_15.modulate.a)
		_ok("⑮f ★在呼吸: 3 秒内透明度起伏 ≥ 0.4", a_hi_15 - a_lo_15 >= 0.4, "%.2f ~ %.2f" % [a_lo_15, a_hi_15])
		_ok("⑮f ★真入口: 光晕的 _process 开着(低画质才关)",
			gl_15.is_processing() == (not bool(get_node("/root/GameState").perf_lite)))

	# ── ⑭ ★★PLAY_LOCK_SAME_SOURCE: 画在按钮上的锁 == 那扇门自己的判据 ──
	#
	# 由来 (2026-09-29 台账 ④·真手点出来的): 打满 24 场之后同一屏上
	#   「商店」正确挂了 🔒, 而「开始战斗」**还是亮的** —— 点下去只飘一行 1.9 秒的字。
	#   根因: 商店的锁在 `_build_page_buttons` 里**就地又写了一遍**三条公式,
	#   而「开始战斗」画的锁只看 `is_eliminated()`, 它自己的门 `_battle_block_msg()`
	#   却还管配额打满与周末阶段 ⇒ **画的锁与真正的门相反**。
	#
	# ★判据的形状: 不重写公式, 而是**问那扇门**(`_battle_block_msg` / `_shop_block_msg`)
	#   再比对**玩家看得到的那把锁**(按钮上有没有 🔒)。两边只要有一格对不上就红。
	#   ⇒ 以后谁再在画按钮那里就地写一份公式, 这条当场红。
	# ★★分母是这条判据的命(memory `fb-changing-a-param-meaning-makes-gates-tautological`):
	#   四种状态里**两颗按钮都必须各出现过锁上与没锁**, 否则"两边都恒为 false"也全绿。
	#   第四格(没打过第一场)还专门证明两颗**不是同一条公式的复制**: 商店锁、开打不锁。
	var gs_l = get_node_or_null("/root/GameState")
	if gs_l == null:
		_ok("⑭ ★分母: 拿不到 GameState", false)
	else:
		var k_h: int = int(gs_l.hearts)
		var k_u: int = int(gs_l.ranked_used)
		var k_b: int = int(gs_l.season_total_battles)
		## ★把"现在是哪一刻"钉死成周四(积分赛日) —— 与 ⑬d 同一个时间戳。
		##   不钉的话周六/周日走的是闯关赛/决赛日那两支闸, 这一整节跟着星期几变。
		_menu.clock_override_ts = 1789603200
		## 每格: [名字, hearts, ranked_used, season_total_battles, 期望开打锁, 期望商店锁]
		var cases: Array = [
			["能打", 5, 0, 3, false, false],
			["配额打满", 5, int(_P2M.RANKED_QUOTA), 3, true, true],
			["命尽出局", 0, 0, 3, true, true],
			["还没打第一场", 5, 0, 0, false, true],
		]
		var seen_play := {"locked": 0, "open": 0}
		var seen_shop := {"locked": 0, "open": 0}
		var seen_reason := 0
		for cs in cases:
			gs_l.hearts = int(cs[1])
			gs_l.ranked_used = int(cs[2])
			gs_l.season_total_battles = int(cs[3])
			for ch_l in page_box.get_children():
				page_box.remove_child(ch_l)
				ch_l.queue_free()
			await get_tree().process_frame
			_menu._build_page_buttons(_menu.clock_override_ts)
			await get_tree().process_frame
			await get_tree().process_frame
			## 门自己怎么说 —— 判据不重写公式, 只比对
			var judge_play: bool = str(_menu._battle_block_msg(_menu.clock_override_ts)) != ""
			var judge_shop: bool = str(_menu._shop_block_msg(_menu.clock_override_ts)) != ""
			var paint_play: bool = _has_lock_glyph(_entry_holder(page_box, "开始战斗"))
			var paint_shop: bool = _has_lock_glyph(_entry_holder(page_box, str(MENU_S.SHOP_LABEL)))
			print("  ⑭ [%s] 开打: 门=%s 画=%s / 商店: 门=%s 画=%s" % [
				str(cs[0]), str(judge_play), str(paint_play), str(judge_shop), str(paint_shop)])
			_ok("⑭ [%s] 开打: 门的判据 == 拍板的期望" % str(cs[0]), judge_play == bool(cs[4]),
				"门说 %s, 期望 %s" % [str(judge_play), str(cs[4])])
			_ok("⑭ [%s] 商店: 门的判据 == 拍板的期望" % str(cs[0]), judge_shop == bool(cs[5]),
				"门说 %s, 期望 %s" % [str(judge_shop), str(cs[5])])
			_ok("⑭ ★★[%s] PLAY_LOCK_SAME_SOURCE: 开打按钮上画的锁 == 它自己那扇门" % str(cs[0]),
				paint_play == judge_play, "画=%s 门=%s" % [str(paint_play), str(judge_play)])
			_ok("⑭ ★★[%s] PLAY_LOCK_SAME_SOURCE: 商店那行画的锁 == 它自己那扇门" % str(cs[0]),
				paint_shop == judge_shop, "画=%s 门=%s" % [str(paint_shop), str(judge_shop)])
			## ⑭b ★锁的**理由**常驻在屏幕上(方案书 20260917 验收「不点不弹 toast 也看得见」)。
			##   量玩家看得到的那行字: 商店那行子树里名为 LOCK_REASON_NAME 的块,
			##   锁着 ⇒ 必须在且非空、且就是产品那条短句; 没锁 ⇒ 必须不在。
			var shop_h := _entry_holder(page_box, str(MENU_S.SHOP_LABEL))
			var rs_txt := _reason_text(shop_h)
			var rs_want: String = str(_menu._shop_lock_reason(_menu.clock_override_ts))
			print("  ⑭b [%s] 商店锁理由(屏幕上) = 「%s」" % [str(cs[0]), rs_txt])
			if judge_shop:
				_ok("⑭b ★[%s] 商店锁着 ⇒ 理由常驻显示在那一行" % str(cs[0]),
					rs_txt != "" and rs_txt == rs_want, "屏幕=「%s」 期望=「%s」" % [rs_txt, rs_want])
				## ⑭c ★理由那行**读得清**(2026-10-05 UI 重做): 它不在木牌上, 直接压在看台上 ⇒
				##   必须 ≥17 号字且实心描边 ≥4(原来 4 个 ±1 偏移副本, 实拍在看台上读不出)。
				var rs_lab: Label = null
				for n_r in _walk(shop_h):
					if str(n_r.name) == str(MENU_S.LOCK_REASON_NAME) and n_r is Label:
						rs_lab = n_r
				_ok("⑭c ★[%s] 锁理由 ≥17 号字 + 实心描边 ≥4" % str(cs[0]),
					rs_lab != null and rs_lab.get_theme_font_size("font_size") >= 17 and rs_lab.get_theme_constant("outline_size") >= 4,
					"字 %s 描边 %s" % [str(rs_lab.get_theme_font_size("font_size")) if rs_lab != null else "-",
						str(rs_lab.get_theme_constant("outline_size")) if rs_lab != null else "-"])
				seen_reason += 1
			else:
				_ok("⑭b [%s] 商店没锁 ⇒ 不显示理由" % str(cs[0]), rs_txt == "", rs_txt)
			## ⑮g ★R2 的光晕只挂在【能点】的主 CTA 上: 锁着(灰框)时不许发光 —— 灰框配金光是在说「快点我」。
			var hg_n := 0
			for n_g2 in _walk(_entry_holder(page_box, "开始战斗")):
				if n_g2 is MenuCtaGlow:
					hg_n += 1
			_ok("⑮g ★[%s] 主 CTA 光晕 有/无 == 开打 没锁/锁着" % str(cs[0]), (hg_n == 1) == (not paint_play),
				"光晕 %d 个, 开打锁=%s" % [hg_n, str(paint_play)])
			seen_play["locked" if paint_play else "open"] += 1
			seen_shop["locked" if paint_shop else "open"] += 1
		print("  ⑭ [分母] 开打 锁上 %d 格 / 没锁 %d 格; 商店 锁上 %d 格 / 没锁 %d 格" % [
			int(seen_play["locked"]), int(seen_play["open"]),
			int(seen_shop["locked"]), int(seen_shop["open"])])
		_ok("⑭ ★分母: 开打按钮**两种态都出现过**(只出现一种 ⇒ 上面四条恒真)",
			int(seen_play["locked"]) > 0 and int(seen_play["open"]) > 0)
		_ok("⑭ ★分母: 商店那行**两种态都出现过**",
			int(seen_shop["locked"]) > 0 and int(seen_shop["open"]) > 0)
		_ok("⑭b ★分母: 三种锁因都量过理由那行(出局/配额/没打第一场)", seen_reason == 3,
			"%d 格" % seen_reason)
		## ★两颗**不是同一条公式的复制** —— 有一格它们必须分道扬镳(商店锁而开打不锁),
		##   否则"共用判据"会被误解成"合并成一条", 而商店确实多一条「本大轮打完第一场才开店」。
		_ok("⑭ ★★两颗按钮不是同一条公式: 「还没打第一场」那格商店锁而开打不锁",
			int(seen_shop["locked"]) > int(seen_play["locked"]),
			"商店锁 %d 格 / 开打锁 %d 格" % [int(seen_shop["locked"]), int(seen_play["locked"])])
		## ★源码纪律: 公式只许住在那两个 `_*_block_msg` 里。画按钮那里再写一遍就是第二份事实源。
		var bpb := _func_body(src, "_build_page_buttons")
		_ok("⑭ ★分母: 切出了 _build_page_buttons 的函数体", bpb.length() > 200, "%d 字符" % bpb.length())
		_ok("⑭ ★★画按钮处不许再就地写一份公式(ranked_quota_full / is_eliminated)",
			bpb.find("ranked_quota_full") < 0 and bpb.find("is_eliminated") < 0,
			"公式只许住在 _battle_block_msg / _shop_block_msg 里")
		_ok("⑭ 画按钮处读的就是那两扇门",
			bpb.find("_battle_block_msg(") >= 0 and bpb.find("_shop_block_msg(") >= 0)
		var osb := _func_body(src, "_open_shop")
		_ok("⑭ ★商店入口走的是同一条判据(不是自己再判一遍)",
			osb.find("_shop_block_msg(") >= 0 and osb.find("ranked_quota_full") < 0, osb.strip_edges())
		gs_l.hearts = k_h
		gs_l.ranked_used = k_u
		gs_l.season_total_battles = k_b
		_menu.clock_override_ts = 0
		for ch_r in page_box.get_children():
			page_box.remove_child(ch_r)
			ch_r.queue_free()
		await get_tree().process_frame
		_menu._build_page_buttons(0)
		await get_tree().process_frame

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
		if not (n is BaseButton) or not (n as Control).is_visible_in_tree():
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


## 按**节点名**找一个节点。★不按"第几个子节点"定位 —— 那种抓法一加节点就漂, 漂了还是绿的。
func _find_named(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r: Node = _find_named(c, nm)
		if r != null:
			return r
	return null


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
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


## page_box 里"子树中有哪个 Label 的文字含 text"的那块按钮。
## ★按文字找不按下标 —— 下标一加节点就漂, 漂了还是绿的。
func _entry_holder(box: Control, text: String) -> Control:
	for c in box.get_children():
		if not (c is Control):
			continue
		for n in _walk(c):
			if n is Label and str((n as Label).text).find(text) >= 0:
				return c as Control
	return null


## 商店那行下面常驻的锁理由: 子树里名为 LOCK_REASON_NAME 的块里的字(没有 ⇒ "")。
func _reason_text(holder: Control) -> String:
	if holder == null:
		return ""
	for n in _walk(holder):
		if str(n.name) == str(MENU_S.LOCK_REASON_NAME):
			for m in _walk(n):
				if m is Label and str((m as Label).text) != "":
					return str((m as Label).text)
	return ""


## 玩家看得到的那把锁: 这块按钮的子树里有没有 🔒。
## ★量的是**玩家看得到的东西**, 不是我自己插的标记
##   (memory `fb-gate-must-measure-requirement-not-my-hook`): 🔒 要么是
##   `_add_lock_badge` 挂的角标(主 CTA), 要么是 `_text_entry` 给文字加的前缀(左栏)。
func _has_lock_glyph(holder: Control) -> bool:
	if holder == null:
		return false
	for n in _walk(holder):
		if n is Label and str((n as Label).text).find("🔒") >= 0:
			return true
	return false


## 源码里某个函数的函数体(到下一个顶层 `func ` 为止), **注释已剥掉**。
## ★必须剥注释: 这个函数体的注释里就写着"原来在这里写了一遍 quota_full", 不剥就自己把自己判红。
## ★剥注释要认引号 —— `#` 也出现在字符串里(`Color("#f0c27a")`), 那是 2026-09-29
##   `verify_dead_params` 刚修掉的同一个坑。
func _func_body(block: String, fname: String) -> String:
	var nl := char(10)
	var i := block.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := block.find(nl + "func ", i + 1)
	var body := block.substr(i, (j - i) if j > i else -1)
	var out := ""
	for l in body.split(nl):
		var line := str(l)
		var in_q := false
		var q := ""
		var cut := line.length()
		for k in line.length():
			var ch := line[k]
			if in_q:
				if ch == q and (k == 0 or line[k - 1] != char(92)):
					in_q = false
			elif ch == char(34) or ch == char(39):
				in_q = true
				q = ch
			elif ch == "#":
				cut = k
				break
		out += line.substr(0, cut) + nl
	return out


## 方键上那个入口名: holder 直属的第一个 Label(底板/图标/红点/锁/理由都不是它)。
func _sq_label(holder: Node) -> String:
	for ch in holder.get_children():
		if ch is Label and str(ch.name) != str(MENU_S.BADGE_NAME) and str(ch.name) != str(MENU_S.LOCK_REASON_NAME) \
				and str((ch as Label).text).find("🔒") < 0:
			return str((ch as Label).text)
	return ""


## ? / ⚙ 那颗键里看得见的方框(frame-square.png)。没有 ⇒ null。
func _find_frame_square(holder: Node) -> Control:
	for n in _walk(holder):
		if n is TextureRect and (n as TextureRect).texture != null \
				and str((n as TextureRect).texture.resource_path).get_file() == "frame-square.png":
			return n as Control
	return null


## 一块看得见的「面」里亮黄像素的占比(0..1)。不是面(贴图/九宫格/色块) ⇒ -1。
## 亮黄 = 色相 40°..62° · 饱和度 ≥0.70 · 明度 ≥0.85, 颜色先乘上 自己的 self_modulate 与 自己+祖先的 modulate。
## ★量的是贴图本身的像素(无头渲染器拍不了屏), 所以 modulate 要自己乘 —— 压灰的锁态面不该算亮黄。
func _yellow_frac(c: Node) -> float:
	var m := Color(1, 1, 1, 1)
	if c is CanvasItem:
		m = (c as CanvasItem).self_modulate
	var p: Node = c
	while p != null:
		if p is CanvasItem:
			m = m * (p as CanvasItem).modulate
		p = p.get_parent()
	if c is ColorRect:
		var cc: Color = (c as ColorRect).color * m
		return 1.0 if _is_bright_yellow(cc) else 0.0
	var tex: Texture2D = null
	if c is TextureRect:
		tex = (c as TextureRect).texture
	elif c is NinePatchRect:
		tex = (c as NinePatchRect).texture
	elif c is TextureButton:
		tex = (c as TextureButton).texture_normal
	if tex == null:
		return -1.0
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return -1.0
	if img.is_compressed():
		img.decompress()
	var step: int = maxi(1, img.get_width() / 96)
	var opaque := 0
	var hit := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var px: Color = img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			opaque += 1
			if _is_bright_yellow(px * m):
				hit += 1
	if opaque == 0:
		return -1.0
	return float(hit) / float(opaque)


func _is_bright_yellow(col: Color) -> bool:
	var h: float = col.h * 360.0
	return col.a >= 0.5 and h >= 40.0 and h <= 62.0 and col.s >= 0.70 and col.v >= 0.85
