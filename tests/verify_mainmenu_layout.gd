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
## ★状态行那一块的节点名从**产品的常量**取, 不抄字面量(抄一次就永远落后一次)。
const MENU_S := preload("res://scripts/scenes/MainMenuScene.gd")
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
	## ★2026-10-05 6 → 7: 排行榜那一行对半分出「战绩」入口(回放体验打磨, MainMenuScene.RECORD_ENTRY_NAME)。
	print("  左栏按钮栈 %d 个 (★分母: 应为 7 = 左栏 4 行(排行榜|战绩 同一行) + 训龟大师 + 英雄)" % stack.size())
	_ok("★分母: 左栏按钮栈 = 7 个", stack.size() == 7, "%d 个" % stack.size())
	if stack.size() != 7:
		_done(); return

	# ── ① 谁也别超出 1280×720 ──
	var oob: Array = []
	## ★擂台背景(2026-10-05)是一张 390×180 的原生画布按 ×4 放大、**居中裁边**铺满视口 ——
	##   画布里的层本来就伸出屏幕两侧(1280 宽下左右各裁 140px)。它们不是控件, 是被裁掉的画。
	##   ⇒ 背景子树不算越界; 但「背景自己裁边 + 盖满视口」由 ⑮b 单独断言(不是放过, 是换了量法)。
	var bd_node: Node = _find_named(_menu, "ArenaBackdrop")
	for c in all:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.size.x >= W - 1.0 and r.size.y >= H - 1.0:
			continue                                     # 背景/遮罩本就该铺满
		if bd_node != null and (bd_node as Node).is_ancestor_of(c):
			continue
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
	#    ★2026-09-17: 豁免名单【清零了】。原来唯一的豁免是 46px 高的「🛠 调试场」——
	#    它已按用户要求搬进设置页(「调试场可以塞到设置里, 正式上线的不会要调试场」),
	#    腾出来的空档给了「本周赛程条」。所以这里改成【断言豁免数 == 0】:
	#    豁免是会烂的东西(写下时有理由, 半年后没人记得), 让它自己报出来比留着注释可靠。
	var small: Array = []
	var exempt := 0
	for c in taps:
		var r: Rect2 = (c as Control).get_global_rect()
		var short: float = minf(r.size.x, r.size.y)
		if short < 1.0:
			continue
		if _tag(c).find("调试场") >= 0:
			exempt += 1
			print("       ★主菜单上又出现了调试场 %.0f×%.0f — 它应该只在设置页" % [r.size.x, r.size.y])
			continue
		if short < MIN_TAP:
			small.append("%s %.0f×%.0f = 短边 %.0fpt" % [_tag(c), r.size.x, r.size.y, short / 1.846])
	_ok("③ ★玩家可点元素短边 ≥ %.0fpx (=44pt)" % MIN_TAP, small.is_empty(), "不达标 %d 个 / 豁免 %d 个" % [small.size(), exempt])
	_ok("③b ★触摸线豁免名单已清零(调试场已搬进设置)", exempt == 0, "还有 %d 个豁免" % exempt)
	for sm in small.slice(0, 8):
		print("       ★太小: " + sm)

	# ── ④ ★赛程条贴底、横跨左栏、七格齐全 (2026-09-18 版式重做后换的判据) ──
	#    原来这里量的是「右信息板与左栏栈首尾对齐」—— 那块 560×398 的表格卡【已经删掉了】,
	#    判据留着只会量到别的 PanelContainer(实测量到了赛程条, 报「右沿 932 ≠ 1264」)。
	#    ★换形状不是放宽: 新版式要守的是"周赛制信息贴底成条、不再占一整栏"。
	var st := INF
	var sb := -INF
	for c in stack:
		var r: Rect2 = (c as Control).get_global_rect()
		st = minf(st, r.position.y)
		sb = maxf(sb, r.end.y)
	var strip: Control = _find_strip(content)
	if strip == null:
		print("  [FAIL] ④ ★分母: 找不到贴底赛程条(最宽的 PanelContainer)"); _fail += 1
	else:
		var sr: Rect2 = strip.get_global_rect()
		print("  ④ 赛程条 @(%.0f,%.0f) %.0f×%.0f  (左栏栈 y %.0f..%.0f)" % [
			sr.position.x, sr.position.y, sr.size.x, sr.size.y, st, sb])
		_ok("④ ★赛程条贴底 (底沿距屏底 ≤ 24px)", H - sr.end.y <= 24.0, "距底 %.0f" % (H - sr.end.y))
		_ok("④ ★赛程条左沿与左栏对齐 (差 ≤2px)", absf(sr.position.x - 48.0) <= 2.0, "左沿 %.0f" % sr.position.x)
		_ok("④ ★赛程条是【条】不是【块】(高 ≤ 96px)", sr.size.y <= 96.0, "高 %.0f" % sr.size.y)
		_ok("④ ★赛程条不压住左栏入口 (顶沿在栈底之下)", sr.position.y >= sb - 2.0,
			"条顶 %.0f vs 栈底 %.0f" % [sr.position.y, sb])

	# ── ⑤ ★训龟大师与主 CTA 同轴 (2026-09-18 换的判据) ──
	#    原来量的是「训龟大师紧贴 2×2 网格」—— 那个网格已经不存在了(次级入口改成无框文字列),
	#    训龟大师也按方案挪到了右栏、贴在主 CTA 正上方。现在要守的是那组关系。
	var trainer: Control = _find_button_holder(stack, "训龟大师")
	var hero: Control = _find_button_holder(stack, "开始战斗")
	if trainer == null or hero == null:
		print("  [FAIL] ⑤ ★分母: 找不到训龟大师 或 开始战斗"); _fail += 1
	else:
		var tr: Rect2 = trainer.get_global_rect()
		var hr: Rect2 = hero.get_global_rect()
		print("  ⑤ 训龟大师 %.0f×%.0f @(%.0f,%.0f) / 主CTA %.0f×%.0f @(%.0f,%.0f)" % [
			tr.size.x, tr.size.y, tr.position.x, tr.position.y,
			hr.size.x, hr.size.y, hr.position.x, hr.position.y])
		_ok("⑤ ★训龟大师与主 CTA 右沿同轴 (差 ≤2px)", absf(tr.end.x - hr.end.x) <= 2.0,
			"差 %.1f" % (tr.end.x - hr.end.x))
		## ★2026-10-05 UI 重做换判据(不是放宽): 原来要求「不粘连 16..64」, 那一版训龟大师离主 CTA 36px,
		##   实拍是「飘在半空、主次关系看不出」。新版式是**贴成一组**: 6px 缝, 主次靠材质分
		##   (主 CTA 金边木框 + 呼吸光晕 / 训龟大师铁箍木板)。⇒ 间距必须落在 4..12 —— 拉开或压住都红。
		_ok("⑤ ★训龟大师贴在主 CTA 正上方成一组 (间距 4..12px)",
			hr.position.y - tr.end.y >= 4.0 and hr.position.y - tr.end.y <= 12.0,
			"间距 %.0f" % (hr.position.y - tr.end.y))
		## ⑤b 主次靠【材质】分: 训龟大师用的是另一张皮(不是主 CTA 那张金边木框)。
		var t_tex := ""
		var h_tex := ""
		for n5 in _walk(trainer):
			if n5 is NinePatchRect and (n5 as NinePatchRect).texture != null:
				t_tex = str((n5 as NinePatchRect).texture.resource_path).get_file()
			elif n5 is TextureRect and not (n5 is MenuCtaGlow) and (n5 as TextureRect).texture != null and t_tex == "":
				t_tex = str((n5 as TextureRect).texture.resource_path).get_file()
		for n5 in _walk(hero):
			if n5 is TextureRect and not (n5 is MenuCtaGlow) and (n5 as TextureRect).texture != null and h_tex == "":
				h_tex = str((n5 as TextureRect).texture.resource_path).get_file()
		_ok("⑤b ★训龟大师与主 CTA 不是同一张皮(只差大小 = 主次分不开)", t_tex != "" and h_tex != "" and t_tex != h_tex,
			"训龟大师「%s」 / 主 CTA「%s」" % [t_tex, h_tex])
		_ok("⑤ ★主 CTA 面积明显大于训龟大师 (≥ 1.8 倍)",
			(hr.size.x * hr.size.y) >= (tr.size.x * tr.size.y) * 1.8,
			"%.2f 倍" % ((hr.size.x * hr.size.y) / maxf(1.0, tr.size.x * tr.size.y)))

	# ── ⑥ ★左栏四个入口等高等距 (2026-09-18 换的判据) ──
	#    原来量的是「按钮宽高比 ≤ 4.0」—— 那是给【木框按钮】定的, 而次级入口现在是
	#    382×82 的无框文字行(4.66:1), 拿旧尺子量会把"按文案设计的行"判成"太扁的按钮"。
	#    ★新版式要守的是"四行等高、间距一致" —— 参差不齐才是真毛病。
	var entries: Array = []
	for c in stack:
		if c == trainer or c == hero:
			continue
		entries.append((c as Control).get_global_rect())
	entries.sort_custom(func(a, b): return (a as Rect2).position.y < (b as Rect2).position.y)
	## ★2026-10-05: 第 4 行对半分成「排行榜 | 战绩」(两块同一行) ⇒ 同一行的并成一个矩形再量;
	##   并之前先量这两块: 等高、首尾相接、合起来恰好是整行宽(不重叠也不留缝)。
	var merged: Array = []
	var halves := 0
	for r in entries:
		var rr: Rect2 = r
		if not merged.is_empty() and absf((merged[-1] as Rect2).position.y - rr.position.y) <= 1.0:
			var prev: Rect2 = merged[-1]
			halves += 1
			_ok("⑥ 同一行两块等高、首尾相接", absf(prev.size.y - rr.size.y) <= 1.0 and absf(prev.end.x - rr.position.x) <= 1.0,
				"%s | %s" % [str(prev), str(rr)])
			merged[-1] = prev.merge(rr)
		else:
			merged.append(rr)
	_ok("⑥ 分母: 恰好一行是对半分的(排行榜 | 战绩)", halves == 1, "%d" % halves)
	entries = merged
	_ok("⑥ ★分母: 左栏入口 = 4 行", entries.size() == 4, "%d 行" % entries.size())
	if entries.size() == 4:
		var hs: Array = []
		var gaps: Array = []
		for i in range(entries.size()):
			hs.append((entries[i] as Rect2).size.y)
			if i > 0:
				gaps.append((entries[i] as Rect2).position.y - (entries[i - 1] as Rect2).position.y)
		var h_lo: float = hs.min()
		var h_hi: float = hs.max()
		var g_lo: float = gaps.min()
		var g_hi: float = gaps.max()
		print("  ⑥ 入口高 %.0f..%.0f  行距 %.0f..%.0f" % [h_lo, h_hi, g_lo, g_hi])
		_ok("⑥ ★四个入口等高 (极差 ≤1px)", h_hi - h_lo <= 1.0, "极差 %.1f" % (h_hi - h_lo))
		_ok("⑥ ★行距一致 (极差 ≤1px)", g_hi - g_lo <= 1.0, "极差 %.1f" % (g_hi - g_lo))
		_ok("⑥ ★行距 = 行高 (贴着排, 不留缝也不重叠)", absf(g_lo - h_lo) <= 1.0,
			"行距 %.0f vs 行高 %.0f" % [g_lo, h_lo])

	# ── ⑦ ★赛季状态压成【两行】, 而且是可点的(→战绩) (2026-09-28 改口径) ──
	#    2026-09-18 这条换过一次判据(原来量的是"信息板四行的值右沿对齐", 那张 560×398 的表格卡已删)。
	#    ★★2026-09-28 再改: 那一行拆成了**两行** —— 周六那句实测 ink 485px 而框只有
	#      `LEFT_W - 8` = 374px, **顶穿控件 111px**, 从 2026-09-22 起就在而门禁没量到。
	#      根因是这条判据在**一个 Label**里找 `大轮`+`Lv`+`本周`, 而屏幕上那三个词
	#      **一周只有五天**在同一段字里(周六换闯关赛读数、周日换决赛日读数, 都没有"本周")
	#      ⇒ 这条判据本身也是"一周只成立五天"的 —— 真在周六跑 CI 它会假红。
	#    ⇒ 现在: ①按 `STATUS_TWO_LINE` 抓那一块 ②两行的字**合起来**看 ③"本周"那一维
	#      改成**问产品自己今天该说什么**(`_phase_status_line(_now_ts())`), 七天都成立。
	#    ★七天逐天的字宽/顶穿在 `verify_gauntlet_ahead ④`(那边钉死时钟跑七遍);
	#      这里量的是**今天这一屏、等入场落定之后**的真实几何 —— 两边的尺子不一样, 都要。
	var two_blk: Node = _find_named(_menu, str(MENU_S.STATUS_TWO_LINE))
	_ok("⑦ ★分母: 场景树里有 `%s` 那一块(找不到 = 下面全是空检查)" % str(MENU_S.STATUS_TWO_LINE),
		two_blk != null)
	var status_lines: Array = []
	if two_blk != null:
		var q3: Array = [two_blk]
		while not q3.is_empty():
			var nd3 = q3.pop_front()
			if nd3 is Label:
				var t3 := str((nd3 as Label).text)
				if t3.strip_edges() != "" and not status_lines.has(t3):
					status_lines.append(t3)
			for ch3 in nd3.get_children():
				q3.append(ch3)
	print("  ⑦ 状态行 %d 行: %s" % [status_lines.size(), str(status_lines)])
	_ok("⑦ ★★状态行是【两行】(一行装不下周六那句, 见本节头注)", status_lines.size() == 2,
		"%d 行 %s" % [status_lines.size(), str(status_lines)])
	var status_txt := ""
	for s7 in status_lines:
		status_txt += str(s7) + "  "
	_ok("⑦ ★屏幕上有一行写着「第 N 大轮 · Lv」的状态",
		status_txt.find("大轮") >= 0 and status_txt.find("Lv") >= 0, status_txt)
	## ★"今天那一维"问产品自己 —— 空串 = 今天是积分赛口径(该说命 + 本周场次),
	##   非空 = 今天有自己的相位读数(周六闯关赛 / 周日决赛日), 那一段就该原样出现在屏幕上。
	var today_line := str(_menu._phase_status_line(_menu._now_ts()))
	var want7: Array = ["大轮", "Lv"]
	if today_line == "":
		want7.append("♥")
		want7.append("本周")
	else:
		want7.append(today_line)
	var miss_s: Array = []
	for k in want7:
		if status_txt.find(str(k)) < 0:
			miss_s.append(k)
	_ok("⑦ ★状态行把赛季/等级/**今天那条读数**都说了(今天=%s)" % (
			"积分赛口径" if today_line == "" else "「" + today_line + "」"),
		miss_s.is_empty(), "缺 %s / 屏上「%s」" % [str(miss_s), status_txt])
	## ★★★几何: 状态行里**每一段字的矩形**都必须还在那一行的框里。
	##   `Control` 会把自己夹到 `get_combined_minimum_size()` ⇒ 设了 box 也拦不住字长出去,
	##   一个错都不报 —— 顶穿 111px 那件事就是这么躲过门禁的。
	if two_blk != null:
		var row_holder: Control = (two_blk as Node).get_parent() as Control
		var hr7: Rect2 = row_holder.get_global_rect()
		var spill7: Array = []
		var lab7 := 0
		var q7: Array = [row_holder]
		while not q7.is_empty():
			var nd7 = q7.pop_front()
			if nd7 is Label:
				lab7 += 1
				var lr7: Rect2 = (nd7 as Control).get_global_rect()
				if not hr7.encloses(lr7):
					spill7.append("「%s」x %.0f..%.0f y %.0f..%.0f" % [
						str((nd7 as Label).text).substr(0, 20),
						lr7.position.x, lr7.end.x, lr7.position.y, lr7.end.y])
			for ch7 in nd7.get_children():
				q7.append(ch7)
		print("  ⑦ 状态行框 x %.0f..%.0f y %.0f..%.0f · 扫了 %d 段字" % [
			hr7.position.x, hr7.end.x, hr7.position.y, hr7.end.y, lab7])
		_ok("⑦ ★分母: 真扫到了那一行里的字(0 段 = 下面是空检查)", lab7 >= 3, "%d 段" % lab7)
		_ok("⑦ ★★★没有一段字顶穿状态行(周六那句原来长出框外 111px)",
			spill7.is_empty(), "%d 条 %s" % [spill7.size(), str(spill7.slice(0, 3))])
	## ★不能用 _tag(): 它只取【第一个】子孙 Label, 而状态行的第一个是「第 N 大轮 · Lv」,
	##   "战绩"在第二个 Label 里 —— 拿 _tag 找会漏判成"战绩入口没了"(实测红过)。
	var rec_hit := false
	for c in taps:
		var q2: Array = [c]
		while not q2.is_empty() and not rec_hit:
			var nd2 = q2.pop_back()
			for ch2 in nd2.get_children():
				q2.append(ch2)
				if ch2 is Label and str((ch2 as Label).text).find("战绩") >= 0:
					rec_hit = true
					break
		if rec_hit:
			break
	_ok("⑦ ★战绩仍然可点(没因为删信息板而丢掉入口)", rec_hit)

	# ── ⑯ ★左栏 / 状态区 / 赛程条的新版式(2026-10-05 UI 重做) ──
	#    用户否掉草稿那面整块挂旗(「太重, 像个弹窗」), 定了: 每行一块短窄木牌、牌间露出看台;
	#    状态区绶带更小更轻、跟左栏一起滑入; 赛程条字大对比高、「今」不填实心、木纹不拉糊。
	#    ★每条都量产品自己的节点, 名字从产品常量取。
	var rows16: Array = []
	for c in stack:
		if c != trainer and c != hero:
			rows16.append(c)
	var plaques: Array = []
	var plaque_miss: Array = []
	for c in rows16:
		var found: Array = []
		for n16 in _walk(c):
			if str(n16.name) == str(MENU_S.ROW_PLAQUE_NAME):
				found.append(n16)
		if found.size() != 1:
			plaque_miss.append("%s:%d" % [_tag(c), found.size()])
		else:
			plaques.append([c, found[0]])
	_ok("⑯a ★分母: 左栏 5 个入口(背包/商店/图鉴/排行榜/战绩)每个恰好一块木牌", rows16.size() == 5 and plaque_miss.is_empty(),
		"入口 %d 个 · 不对的 %s" % [rows16.size(), str(plaque_miss)])
	var fat: Array = []
	for pr in plaques:
		var hr16: Rect2 = (pr[0] as Control).get_global_rect()
		var pr16: Rect2 = (pr[1] as Control).get_global_rect()
		var tex16: Texture2D = (pr[1] as NinePatchRect).texture if pr[1] is NinePatchRect else null
		## 窄: 高 ≤ 50 且 = 贴图原高(竖向不拉伸); 短: 比左栏宽至少窄 1/4(不是一条横贯左栏的底板)
		if tex16 == null or pr16.size.y > 50.0 or absf(pr16.size.y - float(tex16.get_height())) > 0.5 \
				or pr16.size.x > MENU_S.LEFT_W * 0.75 or pr16.size.x > hr16.size.x:
			fat.append("%s 牌 %.0f×%.0f / 行 %.0f×%.0f / 贴图高 %s" % [_tag(pr[0]), pr16.size.x, pr16.size.y,
				hr16.size.x, hr16.size.y, str(tex16.get_height()) if tex16 != null else "无"])
	_ok("⑯b ★木牌短而窄(高 ≤50 且 = 贴图原高 · 宽 ≤ 左栏宽 3/4 且不出本行)", not plaques.is_empty() and fat.is_empty(), str(fat))
	## ⑯c 牌与牌之间露出看台: 按行(顶沿)归并后, 相邻两行木牌的竖向空隙 ≥ 24px
	var row_spans: Dictionary = {}
	for pr in plaques:
		var r16: Rect2 = (pr[1] as Control).get_global_rect()
		var key16 := int(round((pr[0] as Control).get_global_rect().position.y))
		if row_spans.has(key16):
			var o16: Vector2 = row_spans[key16]
			row_spans[key16] = Vector2(minf(o16.x, r16.position.y), maxf(o16.y, r16.end.y))
		else:
			row_spans[key16] = Vector2(r16.position.y, r16.end.y)
	var ks: Array = row_spans.keys()
	ks.sort()
	var min_gap := INF
	for i16 in range(1, ks.size()):
		min_gap = minf(min_gap, (row_spans[ks[i16]] as Vector2).x - (row_spans[ks[i16 - 1]] as Vector2).y)
	_ok("⑯c ★木牌之间露出背景(相邻两行木牌空隙 ≥ 24px · 量了 %d 行)" % ks.size(), ks.size() == 4 and min_gap >= 24.0,
		"最小空隙 %.0f" % min_gap)
	## ⑯d 左栏**没有整块底板**: 任何画东西的控件(贴图/九宫格/色块/面板)盖住左栏区域一半以上都红。
	var col16 := Rect2(MENU_S.LEFT_X, MENU_S.STATUS_Y, MENU_S.LEFT_W, float(_menu._menu_bottom()) - MENU_S.STATUS_Y)
	var slabs: Array = []
	var painters16 := 0
	for c in all:
		if bd_node != null and ((bd_node as Node).is_ancestor_of(c) or c == bd_node):
			continue
		var paints: bool = c is TextureRect or c is NinePatchRect or c is Panel or c is PanelContainer \
			or (c is ColorRect and (c as ColorRect).color.a > 0.02)
		if not paints:
			continue
		var r16: Rect2 = (c as Control).get_global_rect()
		if r16.size.x >= W - 1.0 and r16.size.y >= H - 1.0:
			continue
		var it16: Rect2 = r16.intersection(col16)
		if it16.size.x * it16.size.y > 0.0:
			painters16 += 1
		if it16.size.x * it16.size.y >= col16.size.x * col16.size.y * 0.5:
			slabs.append("%s %s @(%.0f,%.0f) %.0f×%.0f" % [c.get_class(), str(c.name), r16.position.x, r16.position.y,
				r16.size.x, r16.size.y])
	_ok("⑯d ★分母: 左栏区域里量到了画东西的控件(木牌/图标)", painters16 >= 5, "%d 个" % painters16)
	_ok("⑯d ★左栏没有整块底板(草稿那面挂旗「像个弹窗」被否)", slabs.is_empty(), str(slabs))
	## ⑯e 状态区绶带: 在状态行 holder 里面(跟左栏一起滑入), 小而细
	var rib16: Node = _find_named(_menu, str(MENU_S.STATUS_RIBBON_NAME))
	var st_holder: Node = two_blk.get_parent() if two_blk != null else null
	_ok("⑯e ★分母: 绶带在场", rib16 != null)
	if rib16 != null:
		var rr16: Rect2 = (rib16 as Control).get_global_rect()
		_ok("⑯e ★绶带挂在状态行里(跟左栏一起滑入, 不是另起一层)", st_holder != null and (st_holder as Node).is_ancestor_of(rib16),
			"父 %s" % str(rib16.get_parent().name))
		_ok("⑯e ★绶带小而细(高 ≤ 32 · 宽 ≤ 左栏宽 3/4)", rr16.size.y <= 32.0 and rr16.size.x <= MENU_S.LEFT_W * 0.75,
			"%.0f×%.0f" % [rr16.size.x, rr16.size.y])
	## ⑯f 状态区下两行(没有底板)必须实心描边 + 够大。绶带上那行(身份行)不归这条管 ⇒ 按 y 排除绶带那一截。
	var weak16: Array = []
	var n_lines16 := 0
	if st_holder != null:
		var rib_bot: float = (rib16 as Control).get_global_rect().end.y if rib16 != null else -1.0e9
		for n16 in _walk(st_holder):
			if not (n16 is Label) or str((n16 as Label).text).strip_edges() == "":
				continue
			var lb16: Label = n16
			if lb16.get_global_rect().get_center().y <= rib_bot:
				continue
			n_lines16 += 1
			var fs16: int = lb16.get_theme_font_size("font_size")
			var ol16: int = lb16.get_theme_constant("outline_size")
			if fs16 < 18 or ol16 < 4:
				weak16.append("「%s」字 %d 描边 %d" % [lb16.text.substr(0, 10), fs16, ol16])
	_ok("⑯f ★状态区下两行字 ≥18 号且实心描边 ≥4(没有底板, 靠描边读出来 · 量了 %d 段)" % n_lines16,
		n_lines16 >= 2 and weak16.is_empty(), str(weak16))
	## ⑯g 赛程条木纹不拉伸: 中段两个方向都 TILE, 且贴图比条子宽(横向是原像素裁出来的, 不缩放), 竖向 1:1
	if strip != null:
		var sb16: StyleBox = (strip as Control).get_theme_stylebox("panel")
		var tile16 := false
		var tw16 := 0
		var vc16 := -1.0
		var bc16 := -2.0
		if sb16 is StyleBoxTexture and (sb16 as StyleBoxTexture).texture != null:
			var st16: StyleBoxTexture = sb16
			tile16 = st16.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE \
				and st16.axis_stretch_vertical == StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			tw16 = st16.texture.get_width()
			vc16 = float(st16.texture.get_height()) - st16.texture_margin_top - st16.texture_margin_bottom
			bc16 = (strip as Control).size.y - st16.texture_margin_top - st16.texture_margin_bottom
		_ok("⑯g ★赛程条木纹不拉伸(中段 TILE · 贴图宽 ≥ 条子宽)", tile16 and float(tw16) >= (strip as Control).size.x,
			"TILE=%s 贴图宽 %d 条宽 %.0f" % [str(tile16), tw16, (strip as Control).size.x])
		_ok("⑯g ★赛程条竖向 1:1(贴图中段高 == 条子中段高)", absf(vc16 - bc16) <= 0.5, "贴图 %.0f / 条子 %.0f" % [vc16, bc16])
	## ⑯h 「今」那一格不填实心: 皮的中心像素透明, 且字色与其余六格一样(同一套明暗)
	var today_cell: Control = null
	var other_cols: Dictionary = {}
	var today_cols: Dictionary = {}
	if strip != null:
		for n16 in _walk(strip):
			if not (n16 is PanelContainer) or n16 == strip:
				continue
			var labs: Array = []
			for m16 in _walk(n16):
				if m16 is Label:
					labs.append(m16)
			if labs.size() < 2:
				continue
			var is_t: bool = str((labs[1] as Label).text).ends_with(" 今")
			for l16 in labs:
				var ck := str((l16 as Label).get_theme_color("font_color"))
				if is_t:
					today_cols[ck] = true
				else:
					other_cols[ck] = true
			if is_t:
				today_cell = n16
	_ok("⑯h ★分母: 找到「今」那一格", today_cell != null)
	if today_cell != null:
		var tsb: StyleBox = today_cell.get_theme_stylebox("panel")
		var hollow := false
		if tsb is StyleBoxTexture and (tsb as StyleBoxTexture).texture != null:
			var img16: Image = (tsb as StyleBoxTexture).texture.get_image()
			hollow = img16.get_pixel(img16.get_width() / 2, img16.get_height() / 2).a < 0.05
		elif tsb is StyleBoxFlat:
			hollow = (tsb as StyleBoxFlat).bg_color.a < 0.05
		_ok("⑯h ★「今」那格不填实心底(只有一圈边框)", hollow, str(tsb))
		var same16 := true
		for k16 in today_cols.keys():
			if not other_cols.has(k16):
				same16 = false
		_ok("⑯h ★「今」那格的字色与其余六格同一套", not today_cols.is_empty() and not other_cols.is_empty() and same16,
			"今 %s / 其余 %s" % [str(today_cols.keys()), str(other_cols.keys())])

	# ── ⑰ ★版式骨架: 对齐线(2026-10-05 对标 16 款像素/木质游戏后加) ──
	#    Into the Breach / Wildfrost / Loop Hero 的竖排菜单 = 等宽条 + 共用左沿;
	#    Kingdom Rush / Darkest Dungeon 的右上 HUD 与右下主按钮收在同一条右边距上。
	#    ⇒ 左栏: 五块木牌一样宽, 四行共用一条左沿, 状态区绶带也落在这条左沿上;
	#      右栏: 两块货币牌、训龟大师、开始战斗共用一条右沿。
	var p_lefts: Array = []
	var p_widths: Array = []
	for pr in plaques:
		var r17: Rect2 = (pr[1] as Control).get_global_rect()
		p_widths.append(r17.size.x)
		if r17.position.x < MENU_S.LEFT_X + MENU_S.LEFT_W * 0.5:
			p_lefts.append(r17.position.x)
	_ok("⑰a ★分母: 第一列量到 4 块木牌、共 5 块", p_lefts.size() == 4 and p_widths.size() == 5,
		"第一列 %d / 共 %d" % [p_lefts.size(), p_widths.size()])
	if p_widths.size() == 5 and p_lefts.size() == 4:
		_ok("⑰a ★五块木牌等宽(极差 ≤1px · 宽度跟着字走 = 右沿参差)", p_widths.max() - p_widths.min() <= 1.0,
			"宽 %s" % str(p_widths))
		_ok("⑰a ★第一列四块木牌共用一条左沿(极差 ≤1px)", p_lefts.max() - p_lefts.min() <= 1.0, "左沿 %s" % str(p_lefts))
		if rib16 != null:
			var rl17: float = (rib16 as Control).get_global_rect().position.x
			_ok("⑰a ★状态区绶带也落在木牌那条左沿上(差 ≤2px)", absf(rl17 - float(p_lefts.min())) <= 2.0,
				"绶带 %.0f / 木牌 %.0f" % [rl17, float(p_lefts.min())])
	var chips17: Array = []
	for n17 in _walk(content):
		if n17 is NinePatchRect and (n17 as NinePatchRect).texture != null \
				and str((n17 as NinePatchRect).texture.resource_path).get_file() == "chip.png":
			chips17.append((n17 as Control).get_global_rect())
	_ok("⑰b ★分母: 两块货币牌在场", chips17.size() == 2, "%d 块" % chips17.size())
	if chips17.size() == 2 and hero != null and trainer != null:
		var cr17: float = maxf((chips17[0] as Rect2).end.x, (chips17[1] as Rect2).end.x)
		var hr17: float = hero.get_global_rect().end.x
		_ok("⑰b ★右栏一条右沿: 货币牌右沿 == 开始战斗右沿(差 ≤2px)", absf(cr17 - hr17) <= 2.0,
			"货币 %.0f / 主 CTA %.0f" % [cr17, hr17])

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
		_ok("⑮e ★分母: 量到两只角斗龟的框", frs_15.size() == 2, "%d 个" % frs_15.size())
		var covered_15: Array = []
		var strip_c_15: Control = _find_strip(content)
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


## 贴底的赛程条 = content_root 下【最宽的】PanelContainer。
## ★2026-09-18: 原名 `_find_panel`, 找的是那张 560 宽的右信息板 —— 它已经删了。
##   拿"第一个 PanelContainer"会钉死在 add_child 顺序上, 所以按【最宽】找。
func _find_strip(content: Control) -> Control:
	var best: Control = null
	for c in content.get_children():
		if c is PanelContainer and (c as Control).visible:
			if best == null or (c as Control).size.x > best.size.x:
				best = c as Control
	return best


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
