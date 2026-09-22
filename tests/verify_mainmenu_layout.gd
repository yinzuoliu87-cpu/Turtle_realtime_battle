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
		_ok("⑤ ★训龟大师在主 CTA 正上方且不粘连 (间距 16..64px)",
			hr.position.y - tr.end.y >= 16.0 and hr.position.y - tr.end.y <= 64.0,
			"间距 %.0f" % (hr.position.y - tr.end.y))
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
	_ok("⑥ ★分母: 左栏入口 = 4 个", entries.size() == 4, "%d 个" % entries.size())
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

	# ── ⑦ ★赛季状态压成一行, 而且是可点的(→战绩) (2026-09-18 换的判据) ──
	#    原来量的是「信息板四行的值右沿对齐」—— 那张 560×398 的表格卡已删。
	#    新版式要守的是"玩家数据不占一整栏, 但该说的仍说全了"。
	var status_txt := ""
	for c in all:
		if c is Label:
			var t := str((c as Label).text)
			if t.find("大轮") >= 0 and t.find("Lv") >= 0:
				status_txt = t
				break
	_ok("⑦ ★屏幕上有一行写着「第 N 大轮 · Lv」的状态", status_txt != "", status_txt)
	var miss_s: Array = []
	for k in ["大轮", "Lv", "本周"]:
		if status_txt.find(k) < 0:
			miss_s.append(k)
	_ok("⑦ ★状态行把赛季/等级/本周场次都说了", miss_s.is_empty(), "缺 %s" % str(miss_s))
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
		_ok("⑬b ★分母: 那句话确实是产品的纯函数给的, 不是我在门禁里硬写的",
			note_today.find("开发中") >= 0, note_today)
	else:
		## 积分赛那几天照旧: 要么在倒计时, 要么已进封盘窗口(收盘前 10 分钟)
		_ok("⑬b ★今天是积分赛 → 收盘块给的是倒计时或封盘提示",
			joined.find("距收盘") >= 0 or joined.find("已封盘") >= 0
			or joined.find("维护") >= 0, str(strip_txt))

	# ── ⑬c ★**四个阶段各喂一个已知日期**, 别只量"今天"那一格 ──
	#    上面 ⑬b 量的是今天 —— 一周里有四天走不到周末那半, 等于那几天它是空检查
	#    (跑门禁的日子决定判据强弱 = 判据本身不可靠)。
	#    `_week_close_block(now)` 本来就收时间戳 ⇒ 直接喂四个已知日期, **调产品那个真函数**。
	#    ★★判据**不问 `phase_pending_note()` 这一天要不要挂提示** —— 那是拿被测函数当尺子:
	#      它若退化成"永远返回空串", 判据会跟着走进 else 分支、然后全绿
	#      (实测: 变异 M3 第一版没红, 就是栽在这里; 同一份文件 ⑥ 的注释早写过这条)。
	#      「哪几天要挂」由**星期几 + 开关**决定, 写死在下面这张表里。
	var DAYS := {                      # 显示名: [时间戳, 玩法还没上线的那三天?]
		"周一休赛": [1789344000, true],
		"周四积分赛": [1789603200, false],
		"周六闯关赛": [1789776000, true],
		"周日决赛日": [1789862400, true],
	}
	for dn in DAYS.keys():
		var ts_d: int = int((DAYS[dn] as Array)[0])
		var needs_note: bool = bool((DAYS[dn] as Array)[1]) and not _P2M.WEEKEND_MODES_LIVE
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
		_ok("⑬c ★分母(%s): 收盘块真建出了文字" % dn, btxt.size() >= 2, bj)
		if needs_note:
			## ① 屏幕上必须出现「开发中」这个意思 —— 判据写死, 不引被测函数
			_ok("⑬c ★%s: 玩法没上线 → 条子上要说「开发中」" % dn, bj.find("开发中") >= 0, bj)
			## ② 而且必须**就是产品那个纯函数给的那一句**(否则 UI 自己抄了一份, 必然漂)
			_ok("⑬c ★%s: 条子上那句 == phase_pending_note() 给的那句" % dn,
				want_note != "" and bj.find(want_note) >= 0,
				"函数给「%s」· 条子上是「%s」" % [want_note, bj])
			## ★同时**不许**再出现那两句做不到的话 —— 只查"有没有加新句子"是半条判据
			_ok("⑬c ★%s: 不再说「本日维护」/「开打」这类做不到的话" % dn,
				bj.find("维护") < 0 and bj.find("开打") < 0, bj)
		else:
			## 玩法上线之后(WEEKEND_MODES_LIVE=true)三种阶段各说各的话, 逐个卡死 ——
			## 写成"倒计时【或】维护【或】开打"就成了一条永远绿的或门。
			var ph_d: String = _P2M.phase_at_utc(ts_d)
			if ph_d == _P2M.PHASE_REST:
				_ok("⑬c ★%s: 休赛日说维护" % dn, bj.find("维护") >= 0, bj)
			elif ph_d == _P2M.PHASE_FINALS:
				_ok("⑬c ★%s: 决赛日说几点开打" % dn, bj.find("开打") >= 0, bj)
			else:
				_ok("⑬c ★%s: 照常给倒计时" % dn,
					bj.find("距收盘") >= 0 or bj.find("已封盘") >= 0, bj)
		blk.queue_free()

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
		for case_name in ["出局", "配额打满"]:
			if case_name == "出局":
				gs_m.hearts = 0
			else:
				gs_m.hearts = 8
				gs_m.ranked_used = int(_P2M.RANKED_QUOTA)
			var blocked: bool = gs_m.is_eliminated() if case_name == "出局" \
				else gs_m.ranked_quota_full()
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
			if not _P2M.WEEKEND_MODES_LIVE:
				## ★判据写死, 不问被测函数 —— 玩法没上线就不许把玩家指向闯关赛/观战
				_ok("⑬d ★%s: 玩法没上线 → 不许说「闯关赛」「观战」" % case_name,
					toast_txt.find("闯关赛") < 0 and toast_txt.find("观战") < 0, toast_txt)
			for ch_c in new_kids:
				ch_c.queue_free()
		gs_m.hearts = kp_h
		gs_m.ranked_used = kp_u

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
