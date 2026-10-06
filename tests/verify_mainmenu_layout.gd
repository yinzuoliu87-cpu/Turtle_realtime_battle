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
	## ★周一休赛(2026-10-05 起「开始战斗」周一锁住、不发光) ⇒ 本文件量的是「能打的那一屏」;
	##   真实今天是周一时把钟钉到次日(周二)同一时刻。其余六天行为不变。
	var _p2c0 = load("res://scripts/gamedata/phase2_config.gd")
	var _now0: int = int(_p2c0.now_utc())
	if str(_p2c0.phase_at_utc(_now0)) == str(_p2c0.PHASE_REST):
		_menu.clock_override_ts = _now0 + 86400
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
	print("  page_box 栈 %d 个 (★分母: 应为 6 = 左列 4 颗方键 + 训龟大师 + 开始战斗)" % stack.size())
	_ok("★分母: page_box 栈 = 6 个", stack.size() == 6, "%d 个" % stack.size())
	if stack.size() != 6:
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
	_ok("★分母: 可点控件 ≥ 10(4 方键 + 训龟大师 + 开始战斗 + 玩家卡 + 模式卡 + ? + ⚙)", taps.size() >= 10, "%d 个" % taps.size())
	## ★2026-10-06 改口径(要求没变: 「点 A 不许点到 B」):
	##   右上 ?/⚙ 看得见的键 50px、间距 8px, 点击区按触摸线 81px 居中外扩 ⇒ 两块**点击区**按设计
	##   重叠 23px。点击区搭边本身不算撞; 算撞的是**看得见的键**互相压(压了玩家就分不清点的是谁)。
	##   ⇒ 两块点击区相交时: 两边都是「看得见的键 + 外扩点击区」那种(有 iconbtn 方块), 且看得见的
	##      两块不相交、各自点击区仍 ≥ 81 ⇒ 记成「设计内搭边」; 否则照旧是撞。
	var clash: Array = []
	var margin_pairs: Array = []        # 设计内搭边: [说明, 看得见的两颗键之间的缝]
	for i in range(taps.size()):
		for j in range(i + 1, taps.size()):
			var ra: Rect2 = (taps[i] as Control).get_global_rect()
			var rb: Rect2 = (taps[j] as Control).get_global_rect()
			if _nested(taps[i], taps[j]) or _nested(taps[j], taps[i]):
				continue                                 # 父子(透明 Button 铺在 holder 上)不算撞
			if ra.intersects(rb):
				var va: Control = _find_frame_square(taps[i])
				var vb: Control = _find_frame_square(taps[j])
				if va != null and vb != null \
						and va.get_global_rect().size.x < ra.size.x and vb.get_global_rect().size.x < rb.size.x \
						and not va.get_global_rect().intersects(vb.get_global_rect()) \
						and minf(ra.size.x, ra.size.y) >= MIN_TAP and minf(rb.size.x, rb.size.y) >= MIN_TAP:
					var vgap: float = maxf(vb.get_global_rect().position.x - va.get_global_rect().end.x,
						va.get_global_rect().position.x - vb.get_global_rect().end.x)
					margin_pairs.append(["%s×%s 点击区搭 %.0f · 看得见的键间距 %.0f" % [_tag(taps[i]), _tag(taps[j]),
						ra.intersection(rb).size.x, vgap], vgap])
					continue
				var it: Rect2 = ra.intersection(rb)
				clash.append("%s @(%.0f,%.0f)%.0f×%.0f  ×  %s @(%.0f,%.0f)%.0f×%.0f  → 压 %.0f×%.0f" % [
					_tag(taps[i]), ra.position.x, ra.position.y, ra.size.x, ra.size.y,
					_tag(taps[j]), rb.position.x, rb.position.y, rb.size.x, rb.size.y,
					it.size.x, it.size.y])
	_ok("② ★可点控件互不重叠(重叠=点 A 点到 B; ?/⚙ 外扩点击区搭边除外, 但看得见的键不许碰)", clash.is_empty(), "撞 %d 对" % clash.size())
	## ★分母: 那条豁免真的只用在 ?/⚙ 那一对上(0 对 = 豁免没走到, 上一条对 ?/⚙ 是空检查; >1 对 = 豁免放宽了)。
	_ok("② ★分母: 设计内搭边恰 1 对(?×⚙)", margin_pairs.size() == 1
		and str(margin_pairs[0][0]).find("⚙") >= 0, str(margin_pairs))
	if margin_pairs.size() == 1:
		_ok("② ★?/⚙ 看得见的两颗键不碰、之间留缝 ≥ 4px", float(margin_pairs[0][1]) >= 4.0, str(margin_pairs[0][0]))
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
		## ⓐ 2026-10-05 第四轮(标准写法): [大等级徽章] 昵称 #ID / 经验条 x/y / 第 N 大轮。没有头像、没有战绩行、没有命与本周。
		_ok("ⓐ ★没有头像(本作没有头像系统, 龟壳是占位)", _find_named(card, "Avatar") == null)
		var bdg: Node = _find_named(card, str(MENU_S.LV_BADGE_NAME))
		var lvn: Label = _find_named(card, str(MENU_S.LV_TEXT_NAME)) as Label
		_ok("ⓐ ★分母: 等级徽章 + 徽章上的数字都在", bdg is TextureRect and (bdg as TextureRect).texture != null and lvn != null)
		var gs_a = get_node("/root/GameState")
		if bdg is TextureRect and lvn != null:
			var br_a: Rect2 = (bdg as Control).get_global_rect()
			_ok("ⓐ ★徽章在卡的最左端(中心 x 在卡左 1/4)", br_a.get_center().x < cr.position.x + cr.size.x * 0.25, str(br_a))
			_ok("ⓐ ★徽章上的数字 == season_level(%d)" % int(gs_a.season_level), lvn.text == str(int(gs_a.season_level)), "「%s」" % lvn.text)
			## ★量**字的墨迹块**而不是 Label 框: 框按墨迹偏差实测挪过 +2/+13(2026-10-05), 框沿可以出盾, 字不许。
			_ok("ⓐ ★数字是大字(≥ 30 号) 且压在徽章上", lvn.get_theme_font_size("font_size") >= 30
				and br_a.encloses(_ink_box(lvn)), "%d · 字 %s / 盾 %s" % [lvn.get_theme_font_size("font_size"), str(_ink_box(lvn)), str(br_a)])
		var bar_a: TextureProgressBar = _find_named(card, str(MENU_S.XP_BAR_NAME)) as TextureProgressBar
		var xpt_a: Label = _find_named(card, str(MENU_S.XP_TEXT_NAME)) as Label
		_ok("ⓐ ★分母: 经验条 + 条上的字都在", bar_a != null and xpt_a != null)
		if bar_a != null and xpt_a != null:
			var need_a: int = int(_P2A.xp_to_next(int(gs_a.season_level)))
			_ok("ⓐ ★经验条 value/max == season_xp/xp_to_next(%d/%d)" % [int(gs_a.season_xp), need_a],
				int(bar_a.value) == int(gs_a.season_xp) and int(bar_a.max_value) == need_a, "%.0f/%.0f" % [bar_a.value, bar_a.max_value])
			_ok("ⓐ ★条上写着「%d/%d」" % [int(gs_a.season_xp), need_a], xpt_a.text == "%d/%d" % [int(gs_a.season_xp), need_a], "「%s」" % xpt_a.text)
			## ★同上量墨迹块: 条上的字框 2026-10-06 为纯数字偏上下移了 3px(框沿出条 1px, 字没出)。
			_ok("ⓐ ★条上的字压在条上", bar_a.get_global_rect().grow(6.0).encloses(_ink_box(xpt_a)),
				"字 %s / 条 %s" % [str(_ink_box(xpt_a)), str(bar_a.get_global_rect())])
			if bdg is Control:
				var gx: float = bar_a.get_global_rect().position.x - (bdg as Control).get_global_rect().end.x
				_ok("ⓐ ★经验条从徽章右边起(间距 0..24, 读成「2 [42/50]」)", gx >= 0.0 and gx <= 24.0, "%.0f" % gx)
			## 满级: 写「满级」、整条填满(走产品自己的 xp_readout, 临时改等级再还原)
			var lv0: int = int(gs_a.season_level)
			gs_a.season_level = int(_P2A.MAX_LEVEL)
			var mx: Array = _menu.xp_readout()
			gs_a.season_level = lv0
			_ok("ⓐ ★满级 ⇒ 写「满级」且整条填满", str(mx[2]) == "满级" and int(mx[0]) == int(mx[1]) and int(mx[1]) > 0, str(mx))
		var nm_a: Label = _find_named(card, "Nickname") as Label
		var tg_a: Label = _find_named(card, "PlayerTag") as Label
		if nm_a != null and tg_a != null:
			_ok("ⓐ ★ID 写成「#XXXX」、不带「ID」二字", tg_a.text.begins_with("#") and not tg_a.text.begins_with("##") and tg_a.text.find("ID") < 0, "「%s」" % tg_a.text)
			_ok("ⓐ ★ID 紧跟昵称同一行、字比昵称小", absf(tg_a.get_global_rect().get_center().y - nm_a.get_global_rect().get_center().y) <= 6.0
				and tg_a.get_theme_font_size("font_size") < nm_a.get_theme_font_size("font_size"), "")
		var sl_a: Label = _find_named(card, str(MENU_S.SEASON_LINE_NAME)) as Label
		_ok("ⓐ ★「第 %d 大轮」小字一行在经验条下面" % int(gs_a.season_id), sl_a != null and sl_a.text == "第 %d 大轮" % int(gs_a.season_id)
			and bar_a != null and sl_a.get_global_rect().position.y >= bar_a.get_global_rect().end.y, "")
		_ok("ⓐ ★卡里没有战绩行(战绩 / 胜负 / 还没上过场)", cj.find("战绩") < 0 and cj.find("胜") < 0 and cj.find("还没上过场") < 0, cj)
		_ok("ⓐ ★卡里没有命与本周(挪到开始战斗上方)", cj.find("♥") < 0 and cj.find("本周") < 0, cj)
		_ok("ⓐ ★卡里没有「Lv」字样(等级就是徽章上的数字)", cj.find("Lv") < 0, cj)
		_ok("ⓐ ★整张卡可点", taps.has(card))
		var fnt_bad: Array = []
		var ink_end := 0.0
		for n_a in _walk(card):
			if not (n_a is Label) or str((n_a as Label).text).strip_edges() == "":
				continue
			var la: Label = n_a
			var fs_a: int = la.get_theme_font_size("font_size")
			if fs_a < 17:
				fnt_bad.append("「%s」%d" % [la.text.substr(0, 8), fs_a])
			var fa: Font = la.get_theme_font("font")
			var ink_w: float = fa.get_string_size(la.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_a).x if fa != null else 0.0
			if la.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT:
				ink_end = maxf(ink_end, la.get_global_rect().position.x + ink_w)
		if bar_a != null:
			ink_end = maxf(ink_end, bar_a.get_global_rect().end.x)
		var low: Array = []
		for n_l in _walk(card):
			if n_l is Label and str((n_l as Label).text).strip_edges() != "":
				var lr_l: Rect2 = (n_l as Control).get_global_rect()
				var ink_bot: float = lr_l.get_center().y + float((n_l as Label).get_theme_font_size("font_size")) * 0.5
				if ink_bot > cr.end.y - 18.0:
					low.append("「%s」%.0f" % [(n_l as Label).text.substr(0, 6), ink_bot])
		_ok("ⓐ2 ★每行字都落在卡底边铜线之上(墨迹底 ≤ 卡底 − 18)", low.is_empty(), "%s / 卡底 %.0f" % [str(low), cr.end.y])
		_ok("ⓐ2 ★卡里各行 ≥ 17 号", fnt_bad.is_empty(), str(fnt_bad))
		_ok("ⓐ2 ★卡宽贴合内容(最长那行字/经验条的右端到卡右沿 ≤ 40px)", ink_end > 0.0 and cr.end.x - ink_end <= 40.0,
			"字到 %.0f / 卡到 %.0f" % [ink_end, cr.end.x])
		## ★真点一下整张卡 ⇒ 进战绩页(左列不再单设战绩键, 这是唯一入口)
		var ctap: BaseButton = null
		for n_t in _walk(card):
			if n_t is BaseButton:
				ctap = n_t
		var went := ""
		if ctap != null:
			for cn in ctap.pressed.get_connections():
				var cb_t: Callable = cn["callable"]
				if cb_t.get_method() == "_open_record":
					went = "_open_record"
		_ok("ⓐ ★点玩家卡接的是 _open_record(→ Record)", went == "_open_record", went)
		## 2026-10-06 用户「顶上那个斗龟场动画可以去掉」⇒ 主菜单不再有 Logo
		_ok("ⓐ ★主菜单不再放标题图 Logo", _find_named(_menu, "Logo") == null)

	# ── ⓑ ★右上 = 两种货币一条 + ? / ⚙ 小图标键 ──
	## ★2026-10-06 货币区换成**一条**货币条 `CURRENCY_BAR_NAME`(照荒野乱斗: 每种货币一段 cur_seg.png 斜切暗底),
	##   原来两块 chip.png 木牌已下线 ⇒ 量货币条里那两段。
	var cbar: Control = _find_named(content, str(MENU_S.CURRENCY_BAR_NAME)) as Control
	var chips: Array = []
	if cbar != null:
		for n_b in _walk(cbar):
			if n_b is NinePatchRect and (n_b as NinePatchRect).texture != null \
					and str((n_b as NinePatchRect).texture.resource_path).get_file() == "cur_seg.png":
				chips.append((n_b as Control).get_global_rect())
	_ok("ⓑ ★分母: 货币条在场, 里面两段货币(cur_seg.png)", cbar != null and chips.size() == 2, "%d 段" % chips.size())
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
		_ok("ⓑ ★两段货币在同一行(顶沿差 ≤2)", absf(c0.position.y - c1.position.y) <= 2.0, "%s / %s" % [str(c0), str(c1)])
		_ok("ⓑ ★货币在右上(都在屏宽右半 · 底沿 ≤ 130)", minf(c0.position.x, c1.position.x) >= W * 0.5 and maxf(c0.end.y, c1.end.y) <= 130.0,
			"%s / %s" % [str(c0), str(c1)])
		var chips_end: float = maxf(c0.end.x, c1.end.x)
		var vis_max := 0.0
		for t_b in icon_taps:
			## ★量看得见的那块方键(iconbtn), 不量 81 的点击区: 点击区按触摸线外扩, 本来就会伸到货币条底下。
			var vis_b: Control = _find_frame_square(t_b)
			var tr_b: Rect2 = (vis_b if vis_b != null else (t_b as Control)).get_global_rect()
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
		if str(c.name).begins_with(str(MENU_S.SQ_NAME_PREFIX)):
			squares.append(c)
	squares.sort_custom(func(a, b): return (a as Control).global_position.y < (b as Control).global_position.y)
	var sq_names: Array = []
	for c in squares:
		sq_names.append(_sq_label(c))
	_ok("ⓒ ★分母: 左列 4 颗方键 = 背包/商店/图鉴/排行榜(没有战绩: 整张玩家卡就是战绩入口)", sq_names == ["背包", str(MENU_S.SHOP_LABEL), "图鉴", "排行榜"], str(sq_names))
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
	_ok("ⓒ ★四颗都是正方形(宽高差 ≤1)", squares.size() == 4 and not_sq.is_empty(), str(not_sq))
	_ok("ⓒ ★四颗共用一条左沿(极差 ≤1)、贴左边(≤ 32)", lefts.size() == 4 and lefts.max() - lefts.min() <= 1.0 and lefts.min() <= 32.0, str(lefts))
	_ok("ⓒ ★竖排等距(间距极差 ≤1, 不重叠)", gaps_c.size() == 3 and gaps_c.max() - gaps_c.min() <= 1.0 and gaps_c.min() >= 0.0, str(gaps_c))
	_ok("ⓒ ★四颗都是图标在上、字在下", icon_ok == 4, "%d / 4" % icon_ok)
	_ok("ⓒ ★四颗都用方木块底(sqbtn.png)", skin_ok == 4, "%d / 4" % skin_ok)
	_ok("ⓒ ★四颗都带红点槽(右上角, 默认藏着)", badge_ok == 4, "%d / 4" % badge_ok)
	var rec_sq: Array = []
	for t_c in taps:
		if _tag(t_c).find("战绩") >= 0:
			rec_sq.append(_tag(t_c))
	_ok("ⓒ ★主屏上没有单独的「战绩」键", rec_sq.is_empty(), str(rec_sq))
	if card != null and squares.size() == 4:
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
		## 有计数条的日子: 训龟大师 / 计数条 / 开始战斗 三层; 没有(周六/周日): 训龟大师直接贴着开始战斗。
		var cnt: Control = _find_named(_menu, str(MENU_S.TODAY_COUNTER_NAME)) as Control
		var below_t: float = cnt.get_global_rect().position.y if cnt != null else hr.position.y
		_ok("ⓓ ★训龟大师贴在%s正上方 (间距 4..12px)" % ("计数条" if cnt != null else "主 CTA "), below_t - tr.end.y >= 4.0 and below_t - tr.end.y <= 12.0,
			"间距 %.0f" % (below_t - tr.end.y))
		# ── ⓖ ★开始战斗正上方 = 今天在动的两个数(荒野乱斗 PLAY 上面那条计数); 只在吃命/配额的日子 ──
		var want_g: Array = _menu.today_counter_texts(int(_menu._now_ts()))
		var gs_g = get_node("/root/GameState")
		_ok("ⓖ ★计数条在不在 == 今天吃不吃命/配额(_phase_status_line 为空)", (cnt != null) == (str(_menu._phase_status_line(int(_menu._now_ts()))) == ""), "")
		if cnt != null:
			var cr_g: Rect2 = cnt.get_global_rect()
			var ctx_g: Array = []
			for n_g in _walk(cnt):
				if n_g is Label:
					ctx_g.append(str((n_g as Label).text))
			print("  ⓖ 计数条 @(%.0f,%.0f) %.0f×%.0f  %s" % [cr_g.position.x, cr_g.position.y, cr_g.size.x, cr_g.size.y, str(ctx_g)])
			_ok("ⓖ ★计数条贴在开始战斗正上方(间距 0..10 · 水平中心在主 CTA 里)", hr.position.y - cr_g.end.y >= 0.0 and hr.position.y - cr_g.end.y <= 10.0
				and cr_g.get_center().x > hr.position.x and cr_g.get_center().x < hr.end.x, str(cr_g))
			_ok("ⓖ ★命 == ♥ %d/%d" % [int(gs_g.hearts), int(_P2A.HEARTS_MAX)], ctx_g.has("♥ %d/%d" % [int(gs_g.hearts), int(_P2A.HEARTS_MAX)]), str(ctx_g))
			_ok("ⓖ ★本周 == 本周对战 %d/%d" % [int(gs_g.ranked_used), int(_P2A.RANKED_QUOTA)],
				ctx_g.has("本周对战 %d/%d" % [int(gs_g.ranked_used), int(_P2A.RANKED_QUOTA)]), str(ctx_g))
			_ok("ⓖ ★计数条整条在屏内、不压训龟大师", Rect2(0, 0, W, H).encloses(cr_g) and not cr_g.intersects(tr), "")
		## 周六/周日: 喂已知日期给产品函数 —— 计数条不建, 模式卡第二行 == 当天读数(去掉与标题重复的赛制名)
		var wk_bad: Array = []
		var wk_n := 0
		for d_g in [6, 0]:
			var ts_g: int = 1789862400 + d_g * 86400 + 12 * 3600
			var st_g: String = str(_menu._phase_status_line(ts_g))
			var ln_g: Array = _menu.mode_card_lines(ts_g)
			if st_g == "":
				continue
			wk_n += 1
			if not _menu.today_counter_texts(ts_g).is_empty():
				wk_bad.append("%d: 周末还建计数条" % d_g)
			if str(ln_g[1]) == "" or not st_g.ends_with(str(ln_g[1])):
				wk_bad.append("%d: 卡第二行「%s」不是当天读数「%s」" % [d_g, str(ln_g[1]), st_g])
		_ok("ⓖ ★分母: 周六周日两天都有当天读数", wk_n == 2, "%d" % wk_n)
		_ok("ⓖ ★周六/周日: 没有计数条、模式卡第二行 == 当天读数", wk_bad.is_empty(), str(wk_bad))
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

		# ── ⓔ ★开始战斗左边 = 「今天」模式卡: 上沿暗带(倒计时 + i) / 赛制名大字 / 副标题 ──
		#    ★2026-10-06 照荒野乱斗开战按钮旁的模式卡: 规则句去掉了(收进本周赛程页), 第二行是副标题
		#      (平日「第 N 大轮」, 周六周日是当天读数); 倒计时挪到卡顶那条暗带里, 右端一颗「i」。
		_ok("ⓔ ★分母: 模式卡在场(`%s`)" % str(MENU_S.MODE_CARD_NAME), mode != null)
		if mode != null:
			var mr: Rect2 = mode.get_global_rect()
			print("  ⓔ 模式卡 @(%.0f,%.0f) %.0f×%.0f" % [mr.position.x, mr.position.y, mr.size.x, mr.size.y])
			_ok("ⓔ ★模式卡在开始战斗左边、读成一组(右沿 ≤ 主 CTA 左沿 · 间距 ≤ 12)", mr.end.x <= hr.position.x and hr.position.x - mr.end.x <= 12.0, str(mr))
			_ok("ⓔ ★模式卡高度接近开始战斗(≥ 85%)", mr.size.y >= hr.size.y * 0.85, "%.0f / %.0f" % [mr.size.y, hr.size.y])
			var mt: Label = _find_named(mode, "ModeTitle") as Label
			var mrl: Label = _find_named(mode, "ModeRule") as Label
			var mcd: Label = _find_named(mode, "ModeCountdown") as Label
			_ok("ⓔ ★分母: 赛制 / 副标题 / 倒计时三行都在", mt != null and mrl != null and mcd != null)
			if mt != null and mrl != null and mcd != null:
				_ok("ⓔ ★赛制名大字(≥ 26 号)", mt.get_theme_font_size("font_size") >= 26, "%d" % mt.get_theme_font_size("font_size"))
				_ok("ⓔ ★副标题 ≥ 17 号", mrl.get_theme_font_size("font_size") >= 17, "%d" % mrl.get_theme_font_size("font_size"))
				_ok("ⓔ ★倒计时单独一行(卡顶暗带里, 在赛制名上面) 且 ≥ 17 号", mcd.get_global_rect().get_center().y < mt.get_global_rect().position.y + 4.0
					and mcd.get_theme_font_size("font_size") >= 17, "")
				_ok("ⓔ ★副标题在赛制名下面", mrl.get_global_rect().position.y >= mt.get_global_rect().get_center().y, "")
				_ok("ⓔ ★倒计时高亮(字色与副标题不同)", mcd.get_theme_color("font_color") != mrl.get_theme_color("font_color"), "")
			var hint_ok := false
			for n_h in _walk(mode):
				if n_h is Label and str((n_h as Label).text) == "i" \
						and (n_h as Control).get_global_rect().end.x >= mr.end.x - 30.0:
					hint_ok = true
			_ok("ⓔ ★右上有「i」提示能点开说明(贴着卡右沿)", hint_ok)
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
			_ok("ⓔ ★副标题非空、倒计时非空", str(want_e[1]) != "" and str(want_e[2]) != "", str(want_e))
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

	# ── ⓕ ★点模式卡 ⇒ 打开本周赛程页(2026-10-06: 七格横条 → 整页四张阶段卡, 照荒野乱斗「CHOOSE EVENT」) ──
	var pop: Control = _find_named(_menu, str(MENU_S.WEEK_POPUP_NAME)) as Control
	var strip: Control = _find_named(_menu, str(MENU_S.WEEK_CARDS_NAME)) as Control
	_ok("ⓕ ★分母: 赛程页与四张卡的容器都在场", pop != null and strip != null)
	if pop != null and strip != null and mode != null:
		_ok("ⓕ ★卡住在赛程页里(不在主屏上常驻)", pop.is_ancestor_of(strip))
		_ok("ⓕ ★平时赛程页藏着(主屏上看不见卡)", not pop.is_visible_in_tree() and not strip.is_visible_in_tree())
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
			_ok("ⓕ ★★点模式卡 ⇒ 赛程页与卡都看得见了", pop.is_visible_in_tree() and strip.is_visible_in_tree())
			var srf: Rect2 = strip.get_global_rect()
			print("  ⓕ 赛程页四张卡 @(%.0f,%.0f) %.0f×%.0f" % [srf.position.x, srf.position.y, srf.size.x, srf.size.y])
			_ok("ⓕ ★四张卡整块在屏内", Rect2(0, 0, W, H).encloses(srf), str(srf))
			var cards_f: Array = []
			for c_f in strip.get_children():
				if str(c_f.name).begins_with(str(MENU_S.WEEK_CARD_PREFIX)):
					cards_f.append(str(c_f.name))
			_ok("ⓕ ★赛程页就是四个阶段四张卡", cards_f.size() == 4, str(cards_f))
			## 赛程页盖在所有入口上面: 在 content_root 子节点里排最后
			_ok("ⓕ ★赛程页排在内容层最上面(不被入口盖住)", content.get_child(content.get_child_count() - 1) == pop)
			## 顶栏: 左上返回键 + 页名
			var back_n: Control = _find_named(pop, str(MENU_S.WEEK_BACK_NAME)) as Control
			var ttl: Control = _find_named(pop, "WeekPopupTitle") as Control
			_ok("ⓕ2 ★分母: 返回键与页名都在", back_n != null and ttl != null)
			if back_n != null and ttl != null:
				var br2: Rect2 = back_n.get_global_rect()
				var tr2: Rect2 = ttl.get_global_rect()
				_ok("ⓕ2 ★返回键在左上角、页名紧跟在它右边同一行",
					br2.position.x <= 32.0 and br2.position.y <= 8.0 and tr2.position.x >= br2.end.x - 1.0
					and absf(tr2.get_center().y - br2.get_center().y) <= 8.0, "%s / %s" % [str(br2), str(tr2)])
				_ok("ⓕ2 ★卡在顶栏下面(不压顶栏)", srf.position.y >= float(MENU_S.WEEK_BAR_H), "%.0f" % srf.position.y)
				var bb: BaseButton = null
				for n_f in _walk(back_n):
					if n_f is BaseButton:
						bb = n_f
				var bm := ""
				if bb != null:
					for cn in bb.pressed.get_connections():
						bm = (cn["callable"] as Callable).get_method()
				_ok("ⓕ2 ★返回键接的是 _close_week_popup", bm == "_close_week_popup", bm)
				if bb != null:
					bb.pressed.emit()
					await get_tree().process_frame
					_ok("ⓕ ★按返回键 ⇒ 赛程页藏回去", not pop.is_visible_in_tree())
			var dim: Control = _find_named(pop, str(MENU_S.WEEK_DIM_NAME)) as Control
			_ok("ⓕ2 ★分母: 压暗色块在场", dim != null)
			if dim != null:
				mtap.pressed.emit()
				await get_tree().process_frame
				var dr: Rect2 = dim.get_global_rect()
				_ok("ⓕ2 ★压暗盖住宽屏两侧(左右各外扩 ≥ 140)", dr.position.x <= -140.0 and dr.end.x >= W + 140.0 and dr.position.y <= 0.0 and dr.end.y >= H, str(dr))
				_ok("ⓕ2 ★压暗处吃点击(下面的主菜单点不到)", dim.mouse_filter == Control.MOUSE_FILTER_STOP and dim.is_visible_in_tree())
				## 整页盖着主菜单 ⇒ 系统返回键 / Esc 也得关得掉(不能只有左上角一个出口)
				var ev := InputEventAction.new()
				ev.action = "ui_cancel"
				ev.pressed = true
				_menu._unhandled_input(ev)
				await get_tree().process_frame
				_ok("ⓕ2 ★★按返回键(ui_cancel) ⇒ 赛程页关上", not pop.is_visible_in_tree())

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

	# ── ⑬ ★赛程页的内容: 四个阶段各一张卡 + 恰好一张标今天(金边) ──
	#    2026-10-06 改口径: 七格横条换成整页四张阶段卡(照荒野乱斗「CHOOSE EVENT」)。
	#    ★「七天一天不少」那条没有对象了(每张卡写的是阶段占哪几天, 锁着的卡换成解锁条件);
	#      现在守的是: 四个阶段名都在 + 恰好一张是今天。七天逐天的对账在 verify_week_strip。
	var strip_txt: Array = []
	if strip != null:
		for nd in _walk(strip):
			var t13 := ""
			if nd is Label:
				t13 = str((nd as Label).text).strip_edges()
			elif nd is Button:
				t13 = str((nd as Button).text).strip_edges()
			if t13 != "":
				strip_txt.append(t13)
	print("  ⑬ 赛程页里有 %d 条文字: %s" % [strip_txt.size(), str(strip_txt)])
	_ok("⑬ ★分母: 赛程页里量到文字 (0 条 = 页是空的, 下面全是空检查)",
		strip_txt.size() >= 10, "%d 条" % strip_txt.size())
	var joined := "\n".join(PackedStringArray(strip_txt))
	var miss_p: Array = []
	for p3 in ["休赛", "积分赛", "闯关赛", "决赛日"]:
		if not strip_txt.has(p3):
			miss_p.append(p3)
	_ok("⑬ ★四个阶段名都在(缺一个就说明赛程表漏了一段)", miss_p.is_empty(), "缺 %s" % str(miss_p))
	var todays := 0
	if strip != null:
		for c13 in strip.get_children():
			if (c13 as Node).get_node_or_null("TodayFrame") != null:
				todays += 1
	_ok("⑬ ★恰好一张卡被标成今天(0=看不出今天 · >1=算错了)", todays == 1, "%d 张" % todays)

	# ── ⑬b ★今天那张卡说的话必须是**今天真能做到的事** (2026-09-22) ──
	#    ★判据**跟着纯函数走**, 不在这里另写一份"今天该说什么":
	#      `phase_pending_note()` 是 UI 与门禁共用的那一个答案(七天全量在 verify_week_season ⑦)。
	var _P2M := preload("res://scripts/gamedata/phase2_config.gd")
	## ★跟主菜单同一个钟(周一时本文件把钟钉到周二, 见开头)。
	var now_ts: int = int(_menu.clock_override_ts) if int(_menu.clock_override_ts) > 0 else int(Time.get_unix_time_from_system())
	var today_ph: String = _P2M.phase_at_utc(now_ts)
	var note_today: String = _P2M.phase_pending_note(today_ph)
	if note_today != "":
		_ok("⑬b ★今天是「%s」(玩法没上线) → 卡上必须直说" % today_ph,
			joined.find(note_today) >= 0, "页上没有「%s」: %s" % [note_today, str(strip_txt)])
		var _rk_name: String = str(_P2M.PHASE_LABEL.get(_P2M.PHASE_RANKED, ""))
		## ★2026-10-05 周一休赛不开放对战(用户「周一哪来的比赛」) ⇒ 周一那句要说清「不开放对战」。
		var _need: String = "不开放对战" if today_ph == _P2M.PHASE_REST else _rk_name
		_ok("⑬b ★分母: 那句话是产品纯函数给的, 且说清了今天能不能打 / 按谁的规矩打",
			_need != "" and note_today.find(_need) >= 0,
			"规矩名「%s」/ 那句话「%s」" % [_rk_name, note_today])
		## ★同时守住: 屏幕上**不许**出现开发状态词(原判据「必须含开发中」是在替缺陷站岗, 方向已反过来)。
		var _devw: Array = ["开发中", "打磨", "待做", "TODO", "占位", "未实现", "暂按", "暂锁", "还没做"]
		var _hit_dev: Array = []
		for _w in _devw:
			if note_today.find(str(_w)) >= 0:
				_hit_dev.append(_w)
		_ok("⑬b ★卡上不许把开发状态说给玩家听",
			_hit_dev.is_empty(), "命中: %s ← 「%s」" % [str(_hit_dev), note_today])
	elif today_ph == _P2M.PHASE_FINALS:
		## ★周日决赛日(已上线) ⇒ 决赛日那张卡上有一个【进对阵图】的按钮(量按钮, 不是文字)。
		var door_ok := false
		if strip != null:
			for nd2 in _walk(strip):
				if nd2 is Button and str((nd2 as Button).text).find("对阵图") >= 0:
					door_ok = true
		_ok("⑬b ★今天是决赛日(已上线) → 卡上有一个【进对阵图】的按钮", door_ok, "页上的文字: %s" % str(strip_txt))
	else:
		## 积分赛 / 闯关赛(已上线): 有截止 ⇒ 倒计时或封盘提示; 已过截止 ⇒ 「今日已截止」并写下一个阶段几点开始。
		## ★★2026-10-04: 原来接受「维护」二字 ⇒ 收盘后那句错话「休赛日 · 周二开赛 · **本日维护**」反而让它绿
		##   (门禁替 bug 站岗)。维护只认真正的维护态「维护中」。
		if _P2M.close_left_sec(now_ts) < 0:
			_ok("⑬b ★今天是「%s」、已过截止 → 「今日已截止」并写下一个阶段的开始时刻" % today_ph,
				joined.find("今日已截止") >= 0 and joined.find("开始") >= 0 and joined.find("休赛日 · 周二") < 0
				or joined.find("维护中") >= 0, str(strip_txt))
		else:
			_ok("⑬b ★今天是「%s」 → 卡上给的是倒计时或封盘提示" % today_ph,
				joined.find("距截止") >= 0 or joined.find("已截止") >= 0
				or joined.find("维护中") >= 0, str(strip_txt))

	# ── ⑬c ★**四个阶段各喂一个已知日期**, 别只量"今天"那一张 ──
	#    上面 ⑬b 量的是今天 —— 一周里有几天走不到周末那半, 等于那几天它是空检查。
	#    ⇒ 直接喂四个已知日期, **建产品那张真卡**(`_week_card(week_card_info(阶段, 时刻))`)再量。
	#    ★★判据**不问 `phase_pending_note()` 这一天要不要挂提示** —— 那是拿被测函数当尺子。
	#      「哪几天要挂」由**星期几 + 开关**决定, 写死在下面这张表里(跟着 `PHASE_MODE_LIVE` 手动同步)。
	var DAYS := {                      # 显示名: [时间戳, 这天那张卡应该长什么样]
		##   "note"       —— 玩法没上线, 要说清这天按什么规则
		##   "countdown"  —— 有截止概念, 给倒计时/封盘提示
		##   "board_door" —— 周六: 倒计时 + 「全场赛况」的门
		##   "door"       —— 周日: 「查看对阵图」的门
		"周一休赛": [1789344000, "note"],
		"周四积分赛": [1789603200, "countdown"],
		"周六闯关赛": [1789776000, "board_door"],
		"周日决赛日": [1789862400, "door"],
	}
	for dn in DAYS.keys():
		var ts_d: int = int((DAYS[dn] as Array)[0])
		var want_kind: String = str((DAYS[dn] as Array)[1])
		var ph_d: String = _P2M.phase_at_utc(ts_d)
		var blk: Node = _menu._week_card(_menu.week_card_info(ph_d, ts_d))
		var btxt: Array = []
		var btns: Array = []
		for bn in _walk(blk):
			if bn is Label:
				btxt.append(str((bn as Label).text).strip_edges())
			if bn is Button and str((bn as Button).text) != "":
				btns.append(bn)
		var bj := " / ".join(PackedStringArray(btxt))
		var want_note: String = _P2M.phase_pending_note(ph_d)
		_ok("⑬c ★分母(%s): 那张卡真建出了文字" % dn, btxt.size() >= 3, bj)
		if want_kind == "door" or want_kind == "board_door":
			## ★★门判据卡三件: ① 真的建出了能按的 Button ② 上面写着通到哪 ③ **接了处理函数**
			_ok("⑬c ★★分母(%s): 真建出了一个能按的门" % dn, btns.size() >= 1,
				"Button %d 个 / 文字 %s" % [btns.size(), bj])
			if btns.size() >= 1:
				var bt: Button = btns[0]
				if want_kind == "board_door":
					_ok("⑬c ★%s: 卡上照常给倒计时" % dn, bj.find("距截止") >= 0 or bj.find("已截止") >= 0, bj)
					_ok("⑬c ★%s: 门上写着通到哪(全场赛况)" % dn, str(bt.text).find("全场赛况") >= 0, str(bt.text))
				else:
					_ok("⑬c ★%s: 门上写着通到哪(玩家看得懂)" % dn, str(bt.text).find("对阵图") >= 0, str(bt.text))
				_ok("⑬c ★★%s: 门**接了处理函数**(有按钮 ≠ 按了有用)" % dn,
					bt.pressed.get_connections().size() >= 1, "连了 %d 个" % bt.pressed.get_connections().size())
		elif want_kind == "note":
			_ok("⑬c ★%s: 卡上必须说清这天不开放对战" % dn, bj.find("不开放对战") >= 0,
				"要出现「不开放对战」· 卡上是「%s」" % bj)
			var devnote: Array = []
			for w in ["开发中", "暂按", "待做", "TODO", "占位", "未实现"]:
				if bj.find(str(w)) >= 0:
					devnote.append(str(w))
			_ok("⑬c ★★%s: 屏幕上不许出现开发状态词(玩家不需要知道我们做到哪了)" % dn,
				devnote.is_empty(), "撞上 %s · 卡上是「%s」" % [str(devnote), bj])
			_ok("⑬c ★%s: 卡上那句 == phase_pending_note() 给的那句" % dn,
				want_note != "" and bj.find(want_note) >= 0, "函数给「%s」· 卡上是「%s」" % [want_note, bj])
			_ok("⑬c ★%s: 不说「本日维护」/「开打」这类做不到的话" % dn,
				bj.find("本日维护") < 0 and bj.find("开打") < 0, bj)
		else:
			_ok("⑬c ★%s: 照常给倒计时" % dn, bj.find("距截止") >= 0 or bj.find("已截止") >= 0, bj)
		blk.free()

	# ── ⑬e ★「玩法没上线」那一支的【兜底那一句】也不许把开发状态说给玩家听 (2026-09-28) ──
	#  ★由来: 卡上「玩法没上线」那一支有一条兜底(`phase_pending_note()` 给空串时),
	#    只在 `strip_finals_live_override` 把决赛日手动按成"没上线"时才上屏 ⇒ 这里把那个局面**真的造出来**再量。
	var _ov0: int = int(_menu.strip_finals_live_override)
	_menu.strip_finals_live_override = 0          # 0 = 手动按成「玩法没上线」
	var sun_ts: int = 1789862400                  # 周日(与 ⑬c 同一个时刻)
	_ok("⑬e ★分母①: 这个局面真是 BK_PENDING(纯静态函数穷举得到)",
		MENU_S.close_block_kind(_P2M.PHASE_FINALS, false, false, -1, false) == MENU_S.BK_PENDING,
		str(MENU_S.close_block_kind(_P2M.PHASE_FINALS, false, false, -1, false)))
	_ok("⑬e ★分母②: 纯函数这时给的是空串 ⇒ 走的正是那条兜底",
		_P2M.phase_pending_note(_P2M.PHASE_FINALS) == "",
		"给了「%s」" % _P2M.phase_pending_note(_P2M.PHASE_FINALS))
	var blk_e: Node = _menu._week_card(_menu.week_card_info(_P2M.PHASE_FINALS, sun_ts))
	var etxt: Array = []
	for en in _walk(blk_e):
		if en is Label:
			etxt.append(str((en as Label).text).strip_edges())
	var ej := " / ".join(PackedStringArray(etxt))
	_ok("⑬e ★分母③: 兜底那张卡真建出了文字", etxt.size() >= 3, ej)
	_ok("⑬e 兜底那句也说清了这天按【哪个赛制】的规矩打",
		ej.find(str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED])) >= 0,
		"要出现「%s」· 卡上是「%s」" % [str(_P2M.PHASE_LABEL[_P2M.PHASE_RANKED]), ej])
	var edev: Array = []
	for ew in ["开发中", "打磨", "暂按", "暂锁", "待做", "TODO", "占位", "未实现", "还没做"]:
		if ej.find(str(ew)) >= 0:
			edev.append(str(ew))
	_ok("⑬e ★★兜底那句不许出现开发状态词(玩家不需要知道我们做到哪了)",
		edev.is_empty(), "撞上 %s · 卡上是「%s」" % [str(edev), ej])
	blk_e.free()
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
				## ⑭c ★理由那行**读得清**。
				##   2026-10-05 版: 理由直接压在看台上(没底) ⇒ 要 ≥17 号字 + 实心描边 ≥4。
				##   2026-10-06 版: 理由收进方键底边一块**实心暗签**(xpbar.png 九宫格)里, 不再压看台 ⇒
				##   读得清靠「暗底 + 描边」: ≥14 号字 + 实心描边 ≥4 + 整行字落在暗签里 + 整行字不出方键。
				var rs_lab: Label = null
				for n_r in _walk(shop_h):
					if str(n_r.name) == str(MENU_S.LOCK_REASON_NAME) and n_r is Label:
						rs_lab = n_r
				var rs_plate: Rect2 = Rect2()
				if rs_lab != null:
					for n_p in rs_lab.get_parent().get_children():
						if n_p is NinePatchRect and (n_p as NinePatchRect).texture != null \
								and str((n_p as NinePatchRect).texture.resource_path).get_file() == "xpbar.png" \
								and (n_p as Control).get_global_rect().grow(1.0).encloses(_ink_box(rs_lab)):
							rs_plate = (n_p as Control).get_global_rect()
				_ok("⑭c ★[%s] 锁理由 ≥14 号字 + 实心描边 ≥4 + 压在实心暗签上 + 不出方键" % str(cs[0]),
					rs_lab != null and rs_lab.get_theme_font_size("font_size") >= 14 and rs_lab.get_theme_constant("outline_size") >= 4
						and rs_plate.size.x > 0.0 and shop_h.get_global_rect().grow(4.0).encloses(_ink_box(rs_lab)),
					"字 %s 描边 %s 暗签 %s" % [str(rs_lab.get_theme_font_size("font_size")) if rs_lab != null else "-",
						str(rs_lab.get_theme_constant("outline_size")) if rs_lab != null else "-", str(rs_plate)])
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

	# ── ⓐ3 ★真点一下玩家卡 ⇒ 真进了战绩页(最后做: 换场景之后主菜单就没了) ──
	var card_t: Control = _find_named(_menu, str(MENU_S.CARD_NAME)) as Control
	var tap_t: BaseButton = null
	if card_t != null:
		for n_t in _walk(card_t):
			if n_t is BaseButton:
				tap_t = n_t
	_ok("ⓐ3 ★分母: 玩家卡上有可点的按钮", tap_t != null)
	if tap_t != null:
		get_tree().current_scene = _menu
		tap_t.pressed.emit()
		var rec_ok := false
		for _i_t in range(30):
			await get_tree().process_frame
			var cs: Node = get_tree().current_scene
			if cs != null and str(cs.scene_file_path).ends_with("/Record.tscn"):
				rec_ok = true
				break
		_ok("ⓐ3 ★★点玩家卡 ⇒ 当前场景真换成了战绩页(Record.tscn)", rec_ok,
			str(get_tree().current_scene.scene_file_path) if get_tree().current_scene != null else "null")
		_menu = null

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


## 玩家看得到的那把锁: 这块按钮的子树里有没有一把**画出来的**像素锁。
## ★2026-10-06: 锁从系统表情 🔒 Label 换成像素锁 TextureRect(`_pixel_lock`, 名字 LOCK_ICON_NAME,
##   贴图 menu/hud/lock.png)。商店方键 / 开始战斗角标 / 赛程卡都用它。
## ★量的是**玩家看得到的东西**, 不是我自己插的标记
##   (memory `fb-gate-must-measure-requirement-not-my-hook`): 名字之外还要真挂着 lock.png、
##   自己可见、有尺寸 —— 只有名字没有图 = 玩家什么也看不见。
func _has_lock_glyph(holder: Control) -> bool:
	if holder == null:
		return false
	for n in _walk(holder):
		if n is TextureRect and str(n.name) == str(MENU_S.LOCK_ICON_NAME) \
				and (n as TextureRect).texture != null \
				and str((n as TextureRect).texture.resource_path).get_file() == "lock.png" \
				and (n as TextureRect).visible and (n as TextureRect).size.x >= 12.0:
			return true
	return false


## Label 的**墨迹块**(字串实宽 × 字号高, 按对齐方式落在框里)。量「字压没压在 X 上」用它, 不用 Label 框。
func _ink_box(l: Label) -> Rect2:
	var r: Rect2 = l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else r.size.x
	w = minf(w, r.size.x)
	var h: float = minf(float(fs), r.size.y)
	var x: float = r.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x += (r.size.x - w) * 0.5
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x += r.size.x - w
	var y: float = r.position.y
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y += (r.size.y - h) * 0.5
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y += r.size.y - h
	return Rect2(x, y, w, h)


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


## ? / ⚙ 那颗键里看得见的方框(2026-10-06 起是实体按钮 iconbtn.png 九宫格; 原 frame-square.png)。没有 ⇒ null。
func _find_frame_square(holder: Node) -> Control:
	for n in _walk(holder):
		if n is NinePatchRect and (n as NinePatchRect).texture != null \
				and str((n as NinePatchRect).texture.resource_path).get_file() == "iconbtn.png":
			return n as Control
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
