extends Node
## ★2026-08-20: 文案里现在可能有 {C:类名.常量名}(直接引用代码常量, 见 skill_text.gd)。
##   判据必须先 `SkillText.render_consts()` 再量 —— 否则量的是模板不是玩家看到的字,
##   会把"3/5/8"读成一长串 {C:...}。(引入机制那天这两条门禁当场就红了, 红得对。)
## verify_shop_layout.gd — 商店页版式不许超界 + 触摸目标不许太小
##
## 由来 (2026-07-28 重设计)：用户问「确定不会超界面吗」—— 我出草图时【没算过】，
## 一算才发现底部只剩 150px，而备战席(94)+阵容装备(172)放不下，差 22px。
## 这种事不该靠人算，所以焊成门禁：布局一改就自动验。
##
## 查三件事：
##   ① 所有控件都在 1280×720 内（不超右边界、不超下边界）
##   ② 可点控件（Button）高度 ≥ 44px —— 移动端触摸目标最低标准
##      (用户 2026-07-28「买经验按钮很小」：原 200×36 不达标)
##   ③ 关键区块之间不重叠（卡区 / 详情面板 / 底部两栏）
##
## ★不查"好不好看"，只查"放不放得下、点不点得中" —— 这两件机器能判。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shop_layout.tscn

const SHOP := preload("res://scenes/Shop.tscn")
const SCREEN_W := 1280.0
const SCREEN_H := 720.0
const MIN_TOUCH_H := 44.0     # 移动端触摸目标最低高度
## 第⑥条用: 必须与 ShopScene._build_detail_panel 里描述框的口径一致
const DESC_W := 372.0         # PANEL_W(440) - 左右各 34
## ★264 → 246(2026-08-14): 底部 18px 永久留给滚动提示, 提示不再压住正文最后一行。
## 这两个常量必须与 ShopScene 的真值一致 —— 手抄的副本必然落后, 所以第⑥条会【从源码回读】校对。
const DESC_H := 246.0
const DESC_FONT := 20
## 与 ShopScene.DESC_FONT_STEPS 同口径: 放不下就先缩字号, 缩到底才开滚。
const DESC_FONT_STEPS := [20, 18, 16, 15]
## 第⑧条用: 必须与 ShopScene 的 PANEL_* 一致
const PANEL_W := 440.0
const PANEL_H := 592.0
const PANEL_MARGIN := 25.0
## 第⑩条用: 头部右侧三组(币/等级/买经验)共用的竖直中心线
const HEADER_CY := 48.0

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	# 给足条件让商店进"已解锁"分支(否则只建锁定态, 测不到真版式)
	# ★边界: 满背包 + 买不起 —— 之前只测了"空背包+买得起", 那是最宽松的情形。
	#   背包塞满会让备战席格子铺开(验它不伸出左栏); 币=0 会走"深海币不足"分支。
	gs.meta_deepsea_coins = int(OS.get_environment("SHOP_COINS")) if OS.get_environment("SHOP_COINS").is_valid_int() else 999
	gs.season_level = 5
	# ★必须显式给战斗数 —— 商店"本大轮打完第一场才开店", 而 CI 是【全新存档】: season_total_battles=0
	#   → 只建锁定屏 → 控件寥寥 → 第①~⑦条全成空检查。
	#   本机存档里早有战斗数, 所以这条本地【永远绿】、只在 CI 红(CLAUDE.md: 本地绿≠CI绿)。
	gs.season_total_battles = 3
	if OS.get_environment("SHOP_FULLBENCH") != "":
		var bench: Array = []
		for i in range(14):
			bench.append({"id": "p2eq_001", "star": 1})
		gs.persistent_bench = bench

	print("=== 商店版式体检 (%.0f×%.0f) ===" % [SCREEN_W, SCREEN_H])
	var sc = SHOP.instantiate()
	## ★★用户 2026-08-14:「背包里有的装备在货架栏出现时要有镀层闪光效果告知用户背包里已有」
	##   判据: 让 `_owned_count` 返回 >0 的那件出现在货架 ⇒ 该卡下必须多出【镀层 Panel】。
	##   ★数的是产品自己建的节点, 不是我插的标记。反面同验: 没拥有的卡不许有镀层。
	##   (具体断言在文件末尾 —— 这里只留锚点说明, 保持原有构建顺序不变。)
	add_child(sc)
	# ★无头视口是【方形】的(memory: fb-test-window-right-middle) —— 根 Control 用 PRESET_FULL_RECT
	#   会跟着它变成 1280×1280, 于是背景板被误报"越界"。强制按真机口径 1280×720 量。
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(SCREEN_W, SCREEN_H)
	# ★必须选中一张卡: 不选的话详情面板走"← 点货架卡片看详情"的早退分支,
	#   购买按钮/属性行/分隔线【全都不存在】—— 第⑧条会变成空检查(实测面板只有 2 个子控件)。
	if sc.get("_sel") != null:
		sc._sel = 0
		sc._rebuild()
	for _i in range(6):
		await get_tree().process_frame

	var all: Array = []
	_collect(sc, all)
	print("  扫到 %d 个可见控件 (★分母)" % all.size())
	if all.size() < 10:
		print("  [FAIL] 控件太少 —— 商店可能没建起来(锁定态?), 后面的判断没意义"); _fail += 1; _done(sc); return

	# ── ① 越界 ──
	var oob: Array = []
	for c in all:
		var r: Rect2 = Rect2(c.position, c.size)
		if absf(r.size.x - SCREEN_W) < 1.0 and absf(r.size.y - SCREEN_H) < 1.0:
			continue   # 铺满型(背景板/遮罩): 本就该等于全屏, 不算越界
		if r.end.x > SCREEN_W + 0.5 or r.end.y > SCREEN_H + 0.5 or r.position.x < -0.5 or r.position.y < -0.5:
			oob.append("%s @(%.0f,%.0f) %.0f×%.0f → 右下(%.0f,%.0f)" % [
				c.get_class(), r.position.x, r.position.y, r.size.x, r.size.y, r.end.x, r.end.y])
	_chk("① 所有控件都在 %.0f×%.0f 内" % [SCREEN_W, SCREEN_H], oob.is_empty())
	for o in oob.slice(0, 8):
		print("       ★越界: " + o)

	# ── ② 触摸目标 ──
	var small: Array = []
	for c in all:
		if c is Button and c.visible and c.size.y > 0.0 and c.size.y < MIN_TOUCH_H:
			small.append("%s 高%.0f (<%.0f)" % [str((c as Button).text).substr(0, 12), c.size.y, MIN_TOUCH_H])
	_chk("② 按钮高度都 ≥ %.0fpx" % MIN_TOUCH_H, small.is_empty())
	for sm in small.slice(0, 8):
		print("       ★太小: " + sm)

	# ── ③ ★关键区块不许重叠 ──
	#    截图才发现: 我只改了 _rebuild 的坐标, 而 _build_lineup_equips/_build_bench_preview
	#    内部仍是写死的老坐标(px=730 / y=178+row*56 / y=560) → 阵容装备压在卡片和详情面板上。
	#    越界检查抓不到"两块都在屏内但互相压" —— 所以补这条。
	var zones := {
		"卡区": Rect2(40, 124, 740, 296),
		"详情面板": Rect2(800, 124, 440, 592),
	}
	var overlap: Array = []
	for c in all:
		var r: Rect2 = Rect2(c.position, c.size)
		if absf(r.size.x - SCREEN_W) < 1.0 and absf(r.size.y - SCREEN_H) < 1.0:
			continue
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue   # 分隔线之类
		# 只查【顶层】控件(卡片/面板自己的子节点当然在父区块里)
		if c.get_parent() != sc:
			continue
		for zn in zones.keys():
			var z: Rect2 = zones[zn]
			if not z.intersects(r):
				continue
			# 完全落在该区块内 = 它就是该区块的成员, 不算压
			if z.encloses(r):
				continue
			overlap.append("%s @(%.0f,%.0f) %.0f×%.0f 压到【%s】" % [
				c.get_class(), r.position.x, r.position.y, r.size.x, r.size.y, zn])
	_chk("③ 顶层控件不压到卡区/详情面板", overlap.is_empty())
	for ov in overlap.slice(0, 10):
		print("       ★重叠: " + ov)

	# ── ④ ★任意两个顶层控件不许互相重叠 ──
	#    比第③条更强: ③只查"压到卡区/详情面板", 抓不到【头部内部】的重叠 ——
	#    实际就漏了「Lv3 XP 6/10」压住「买经验」按钮 18px, 是我放大截图才看见的。
	#    Label 之间轻微重叠不致命, 但【按钮被文字压住】会真的点不到, 所以这条只对
	#    "至少一方是 Button" 的组合报错。
	var tops: Array = []
	for c in all:
		if c.get_parent() != sc:
			continue
		var r0: Rect2 = Rect2(c.position, c.size)
		if absf(r0.size.x - SCREEN_W) < 1.0 and absf(r0.size.y - SCREEN_H) < 1.0:
			continue
		if r0.size.x < 2.0 or r0.size.y < 2.0:
			continue
		tops.append(c)
	var clash: Array = []
	for i in range(tops.size()):
		for j in range(i + 1, tops.size()):
			var a: Control = tops[i]
			var b: Control = tops[j]
			if not (a is Button or b is Button):
				continue
			var ra: Rect2 = Rect2(a.position, a.size)
			var rb: Rect2 = Rect2(b.position, b.size)
			if ra.intersects(rb):
				clash.append("%s(%s) @%.0f,%.0f %.0f×%.0f  ×  %s(%s) @%.0f,%.0f %.0f×%.0f" % [
					a.get_class(), (a as Button).text.substr(0, 8) if a is Button else "", ra.position.x, ra.position.y, ra.size.x, ra.size.y,
					b.get_class(), (b as Button).text.substr(0, 8) if b is Button else "", rb.position.x, rb.position.y, rb.size.x, rb.size.y])
	_chk("④ 按钮不与其他顶层控件重叠(重叠=点不到)", clash.is_empty())
	for cl in clash.slice(0, 6):
		print("       ★压住: " + cl)

	# ── ⑦ ★不透明图标不许压在文字上 ──
	#    由来: 我把头部的 emoji 💠 换成真币图标时, 图标放 W-424、而数字标签右对齐正好收在
	#    W-390 → 【数字整个被图标盖住】, 截图上只剩一枚币、看不到余额。
	#    第④条只查"按钮被压"(按钮被压=点不到), 压的是 Label 就一路绿灯放行。
	#    TextureRect 是不透明的, 盖住 Label = 那行字直接读不到, 和按钮点不到一样是硬伤。
	var icons: Array = []
	var labels: Array = []
	for c in all:
		if c.get_parent() != sc:
			continue
		if c.size.x < 2.0 or c.size.y < 2.0:
			continue
		if c is TextureRect:
			icons.append(c)
		elif c is Label:
			labels.append(c)
	var covered: Array = []
	for ic in icons:
		for lb in labels:
			var ri: Rect2 = Rect2(ic.position, ic.size)
			var rl: Rect2 = Rect2(lb.position, lb.size)
			if not ri.intersects(rl):
				continue
			# Label 的 size 常常比实际文字宽(留白), 所以只在【重叠面积占 Label 一半以上】
			# 或【重叠区压在文字对齐的那一侧】时才算真盖住 —— 这里取前者, 简单且不误报。
			# ★不能按【框】的面积比判 —— 第一版就是这么写的, 反向验证【没红】:
			#   头部那个 Label 框宽 130 但文字【右对齐】, 只占最右约 50px, 图标正好盖住那 50px,
			#   按框面积算才 24% < 阈值 35% → 一路绿灯, 而实际数字一个都看不见。
			#   所以要用字体量出【真实文字矩形】(含对齐方式), 再判它有没有被盖。
			var rt: Rect2 = _text_rect(lb)
			if not ri.intersects(rt):
				continue
			var inter: Rect2 = ri.intersection(rt)
			var frac: float = (inter.size.x * inter.size.y) / maxf(1.0, rt.size.x * rt.size.y)
			if frac >= 0.25:
				covered.append("图标@(%.0f,%.0f)%.0f×%.0f 盖住「%s」的 %.0f%% (文字实占 %.0f×%.0f @%.0f,%.0f)" % [
					ri.position.x, ri.position.y, ri.size.x, ri.size.y,
					str((lb as Label).text).substr(0, 10), frac * 100.0,
					rt.size.x, rt.size.y, rt.position.x, rt.position.y])
	_chk("⑦ 不透明图标没盖住文字(盖住=那行字读不到)", covered.is_empty())
	for cv in covered.slice(0, 6):
		print("       ★盖住: " + cv)

	# ── ⑥ ★59 件装备的完整描述, 右侧面板【写不写得完】──
	#    由来: 用户 2026-07-28 砍掉卡面摘要时问「右边能写完整吗，这么小的字？」。
	#    这个不该由我目测/按字数估, 直接【量内容高度】: 用与商店同口径的 RichTextLabel
	#    (同字号 18 / 同框宽 400), 逐件填进去看 get_content_height() 会不会超出框高。
	#    ★超框不判 FAIL —— 面板开了 scroll_active, 超了是"要滚一下"不是"看不到"。
	#      但必须【把数字打出来】, 否则就是无声上限(CLAUDE.md: 静默截断 = 假装覆盖全了)。
	#      判 FAIL 的只有"超得离谱"(内容高 > 框高 ×3, 滚起来太痛苦)。
	# ★取 phase2_equipment —— 商店货源就是它(ShopScene:132 `var pool := DataRegistry.phase2_equipment`),
	#   不是 all_equipment(那是另一套旧数据), 拿错表这条就白测了。
	var dr := get_node_or_null("/root/DataRegistry")
	var eqs: Array = dr.phase2_equipment if dr != null else []
	print("")
	## ★口径必须与产品一致, 否则量的是我脑子里的版式不是屏幕上的版式。
	##   先从 ShopScene 源码回读框高与字号阶梯, 对不上就直接红(手抄的副本必然落后)。
	var src_shop := FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd")
	_chk("⑥ ★口径自检: 框高与 ShopScene.DESC_BOX_H 一致",
		src_shop.find("const DESC_BOX_H := %.1f" % DESC_H) >= 0)
	_chk("⑥ ★口径自检: 字号阶梯与 ShopScene.DESC_FONT_STEPS 一致",
		src_shop.find("const DESC_FONT_STEPS := [20, 18, 16, 15]") >= 0)
	print("  ⑥ 描述容纳体检: 框 %.0f×%.0f / 字号阶梯 %s / 装备 %d 件 (★分母)" % [
		DESC_W, DESC_H, str(DESC_FONT_STEPS), eqs.size()])
	if eqs.is_empty():
		print("  [FAIL] 取不到装备表 —— 本条是空检查"); _fail += 1
	else:
		var probe := RichTextLabel.new()
		probe.bbcode_enabled = true
		probe.size = Vector2(DESC_W, DESC_H)
		add_child(probe)
		var over: Array = []
		var shrunk := 0
		var worst := 0.0
		var worst_nm := ""
		for e in eqs:
			var ed: Dictionary = e if e is Dictionary else {}
			var raw := SkillText.render_consts(str(ed.get("effectDesc1", "")))
			if raw == "":
				continue
			## 逐档缩字号 —— 复刻 ShopScene._fit_desc_font 的行为, 不是量"字号 20 放不放得下"。
			var used := 0
			var ch := 0.0
			for fs in DESC_FONT_STEPS:
				probe.add_theme_font_size_override("normal_font_size", int(fs))
				probe.text = raw
				await get_tree().process_frame
				ch = probe.get_content_height()
				used = int(fs)
				if ch <= DESC_H + 0.5:
					break
			if used != int(DESC_FONT_STEPS[0]):
				shrunk += 1
			if ch > worst:
				worst = ch; worst_nm = str(ed.get("name", ed.get("id", "?")))
			if ch > DESC_H + 0.5:
				over.append("%s 缩到 %d 号仍需 %.0fpx" % [str(ed.get("name", "?")), used, ch])
		print("     缩字号后一屏放得下: %d / %d 件 (其中 %d 件靠缩字号才放下)   最难的「%s」需 %.0fpx (框 %.0f)" % [
			eqs.size() - over.size(), eqs.size(), shrunk, worst_nm, worst, DESC_H])
		for o in over.slice(0, 8):
			print("       ↕仍需滚动: " + o)
		if over.size() > 8:
			print("       …另有 %d 件仍需滚动" % (over.size() - 8))
		probe.queue_free()
		## ★判据从"别超 3 倍"收紧成"缩到底之后最多 3 件要滚"——
		##   用户 2026-08-14 抱怨的正是"断在半句"。开滚是退路不是常态。
		_chk("⑥ ★缩字号后仍需滚动的 ≤ 3 件", over.size() <= 3)

	# ── ⑧ ★详情面板的内容不许压进面板框的边框 ──
	#    由来: 购买按钮 y=512 高 68 → 下沿 580, 而面板框九宫格 margin=25,
	#    内容安全区下界只有 592-25=567 —— 压进下边框 13px, 看着就是"按钮太低"。
	#    前面几条都在量【屏幕】边界和【控件之间】的重叠, 谁也管不到"控件压到自己父框的边框上"。
	var panel: Control = null
	for c in all:
		# ★2026-08-01: 原判据是 `c.get_parent() == sc`(必须是场景根的直接子节点)。
		#   UI 双端适配后内容装进了 UIFrame 的 DesignFrame(见 scripts/util/ui_frame.gd),
		#   面板就多隔了一层, 这条会红 —— 而版式一点没变。判据的本意是"找那个 440×592 的面板",
		#   不是"找直接子节点", 所以认【根 或 设计框】两层。
		var par: Node = c.get_parent()
		# ★按【类型】认框, 不按名字: 旧框 queue_free 后仍占着 "DesignFrame" 这个名字, Godot 会把
		#   新框改名成 @Control@NNN —— 按名字认会认不出来(实测就是这么红的)。
		var par_ok: bool = (par == sc) or (par is UIFrame and par.get_parent() == sc)
		if par_ok and absf(c.size.x - PANEL_W) < 1.0 and absf(c.size.y - PANEL_H) < 1.0:
			panel = c; break
	print("")
	if panel == null:
		print("  [FAIL] ⑧ ★分母: 找不到详情面板(%.0f×%.0f)" % [PANEL_W, PANEL_H]); _fail += 1
	else:
		var safe := Rect2(PANEL_MARGIN, PANEL_MARGIN, PANEL_W - PANEL_MARGIN * 2.0, PANEL_H - PANEL_MARGIN * 2.0)
		print("  ⑧ 面板内容安全区 = x %.0f..%.0f  y %.0f..%.0f (框 margin %d)" % [
			safe.position.x, safe.end.x, safe.position.y, safe.end.y, PANEL_MARGIN])
		var nkid := panel.get_children().size()
		print("     面板子控件 %d 个 (★分母: ≤3 说明没选中卡片, 这条是空检查)" % nkid)
		if nkid <= 3:
			print("  [FAIL] ⑧ ★分母不足 —— 详情面板没建全(是不是没选中卡片?)"); _fail += 1
		var spill: Array = []
		for c in panel.get_children():
			if not (c is Control) or not (c as Control).visible:
				continue
			var r: Rect2 = Rect2((c as Control).position, (c as Control).size)
			if r.size.x < 2.0 or r.size.y < 2.0:
				continue
			if absf(r.size.x - PANEL_W) < 1.5 and absf(r.size.y - PANEL_H) < 1.5:
				continue   # 框自己(NinePatchRect 铺满)
			if r.position.y < safe.position.y - 0.5 or r.end.y > safe.end.y + 0.5 					or r.position.x < safe.position.x - 0.5 or r.end.x > safe.end.x + 0.5:
				spill.append("%s(%s) @(%.0f,%.0f) %.0f×%.0f → 下沿 %.0f" % [
					c.get_class(), (c as Button).text.substr(0, 8) if c is Button else "",
					r.position.x, r.position.y, r.size.x, r.size.y, r.end.y])
		_chk("⑧ ★面板内容不压到面板框的边框上", spill.is_empty())

		# ── ⑨ ★「属性」标题必须贴着它的内容 ──
		#    由来: _center_middle 收拢时同一个节点在数组里出现了两次 → 被移了【两倍】,
		#    标题跑到属性行上方 110px(本该 22px)。这种"位移量翻倍"肉眼看是"布局崩了",
		#    但越界/重叠检查一条都不会响 —— 两个控件都在安全区内、也不重叠。
		var hdr: Label = null
		var first_stat: Label = null
		for c in panel.get_children():
			if not (c is Label):
				continue
			var lb2: Label = c
			if str(lb2.text) == "属性":
				hdr = lb2
			elif hdr != null and lb2.position.y > hdr.position.y and (first_stat == null or lb2.position.y < first_stat.position.y):
				first_stat = lb2
		if hdr == null:
			print("  [FAIL] ⑨ ★分母: 找不到「属性」标题"); _fail += 1
		elif first_stat == null:
			print("     ⑨ (这件装备没有属性行, 跳过)")
		else:
			var gap: float = first_stat.position.y - (hdr.position.y + hdr.size.y)
			print("     ⑨ 「属性」标题底 %.0f → 首条属性顶 %.0f, 间距 %.0f px" % [
				hdr.position.y + hdr.size.y, first_stat.position.y, gap])
			_chk("⑨ ★标题与内容间距 ≤ 16px(超了说明位移被重复施加)", gap >= -2.0 and gap <= 16.0)
		for sp in spill.slice(0, 6):
			print("       ★压框: " + sp)

	# ── ⑩ ★右上角三组必须坐在同一条水平线上 ──
	#    由来 (用户 2026-07-29「右上角需要改」): 币 中心 41 / 等级 中心 41 / 买经验 中心 48,
	#    三组各走各的。这类"差几像素"的错位越界/重叠一条都不会响, 但肉眼一看就是没对齐。
	#    按 x 区间收三组的【并集矩形】, 不依赖各组内部怎么搭(图标+数字, 或 文字+进度条)。
	var grp := {"币": Rect2(), "等级": Rect2(), "买经验": Rect2()}
	var ghit := {"币": 0, "等级": 0, "买经验": 0}
	for c in all:
		var cc: Control = c
		var r := Rect2(cc.global_position, cc.size)
		if r.position.y >= 96.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
			continue   # 只看头部行
		var key := ""
		## ★2026-08-15 标题删掉后三组铺开到中间空位: 币 340..530 / 等级 661..901 / 买经验 1032..1252。
		##   区间跟着搬(x 下界 740→300) —— 不搬的话三组一个都收不到, 第⑩条变成"分母为 0"的空检查。
		## ★区间必须跟着版式走: 现在是 币 320..520 / 等级 560..900 / 购买说明+按钮 940..1252。
		##   分界线取在组与组【中间的空档】上, 不是拍脑袋取整 —— 取 600 的话等级组起点 560
		##   会被算进"币", 三组的并集全错而门禁照样有输出(最阴的那种假绿灯)。
		if r.position.x >= 300.0 and r.position.x < 540.0:
			key = "币"
		elif r.position.x >= 540.0 and r.position.x < 930.0:
			key = "等级"
		elif r.position.x >= 930.0:
			key = "买经验"
		if key == "":
			continue
		grp[key] = r if ghit[key] == 0 else (grp[key] as Rect2).merge(r)
		ghit[key] = int(ghit[key]) + 1
	var missing: Array = []
	for k in grp.keys():
		if int(ghit[k]) == 0:
			missing.append(k)
	if not missing.is_empty():
		print("  [FAIL] ⑩ ★分母: 头部右侧收不到这几组 %s" % [missing]); _fail += 1
	else:
		# ★判据是"每组都以 y=48 为中心", 不是"三组中心的极差"。
		#   反向验证时发现极差是【稀释】过的: 把币图标上移 7px, 并集矩形反而被撑大,
		#   中心只挪了 2.5px → 极差 ≤4 照样 PASS。拿固定基准线量才抓得住。
		var off_max := 0.0
		for k in ["币", "等级", "买经验"]:
			var r2: Rect2 = grp[k]
			var cy: float = r2.position.y + r2.size.y * 0.5
			off_max = maxf(off_max, absf(cy - HEADER_CY))
			print("     ⑩ %-4s x %.0f..%.0f  y %.0f..%.0f  中心 %.1f (偏离基准 %.1f)  (%d 个控件)" % [
				k, r2.position.x, r2.end.x, r2.position.y, r2.end.y, cy, cy - HEADER_CY, int(ghit[k])])
		print("     ⑩ 基准线 y=%.0f, 最大偏离 %.1f px" % [HEADER_CY, off_max])
		_chk("⑩ ★右上三组都以 y=%.0f 为竖直中心(偏离 ≤ 2px)" % HEADER_CY, off_max <= 2.0)

	# ── ⑪ ★底部两个摘要按钮的外沿要和卡区对齐 ──
	#    由来: 上一版跨 80..720, 而卡区跨 40..780 —— 中心差 10px, 看着就是歪的。
	var bmin := INF
	var bmax := -INF
	var bn := 0
	for c in all:
		if not (c is Button):
			continue
		var t := str((c as Button).text)
		if t.find("我的背包") < 0 and t.find("出战阵容") < 0:
			continue
		var cb: Control = c
		bmin = minf(bmin, cb.global_position.x)
		bmax = maxf(bmax, cb.global_position.x + cb.size.x)
		bn += 1
	if bn != 2:
		print("  [FAIL] ⑪ ★分母: 底部摘要按钮找到 %d 个(应为 2)" % bn); _fail += 1
	else:
		print("     ⑪ 底部按钮跨 %.0f..%.0f  /  卡区跨 40..780" % [bmin, bmax])
		_chk("⑪ ★底部按钮外沿与卡区对齐(各差 ≤ 2px)", absf(bmin - 40.0) <= 2.0 and absf(bmax - 780.0) <= 2.0)

	# ── ⑤ 分母自检: 至少要有按钮, 否则第②条是空检查 ──
	var nbtn := 0
	for c in all:
		if c is Button:
			nbtn += 1
	print("  按钮数 = %d" % nbtn)
	_chk("⑤ ★分母: 按钮数 > 0 (0 个 = 第②条是空检查)", nbtn > 0)

	# ── ⑫ 详情面板【不许】再有羁绊小签(用户 2026-08-15) ──
	#   原文:「不要小签啊, 搞让人反感 ai 味的东西干嘛」/「还差几件生效给我去掉啊」。
	#   ⇒ 小签整块删掉, 连同 `_synergy_two_lines` / `_synergy_info` 两个函数
	#     （留着不调 = 死函数, 照样能被"断言它存在"的门禁假保护住)。
	#   羁绊信息的去处: 页面底部本来就有 `_build_synergy_bar()`(2026-08-12 用户点名要的),
	#   逐档效果在图鉴·羁绊页 —— 不需要在详情面板再教一遍。
	_chk("⑫ ★羁绊小签的两个函数已删净(不是留着不调)",
		src_shop.find("func _synergy_two_lines") < 0
		and src_shop.find("func _synergy_info") < 0
		and src_shop.find("_synergy_bbcode") < 0)
	_chk("⑫ ★没有带感叹号的推销话术(「买这件就生效！」那类)",
		src_shop.find("就生效！") < 0 and src_shop.find("就更强！") < 0)
	_chk("⑫ ★也没有「还差 N 件」的复述(进度本身已经说完了)",
		src_shop.find("还差 %d 件") < 0 and src_shop.find("再装 %d 件") < 0)
	## ★但【类型】不能跟着一起没了 —— 它是买之前要知道的事实。改挂在价格行后面。
	##
	## ★★2026-09-28 判据从【grep 源码字面量】改成【量真实建出来的那一行】。
	##   原来是 `src_shop.find("Phase2Types.emoji_of(_tp2), _tp2") >= 0` —— 那是拿
	##   **一句源码长什么样**当尺子: 类型图标 emoji→像素图那天它必然红, 而它红不是因为
	##   需求坏了; 反过来, 只要我在源码里留着那串字符、把这一行**从面板上删掉**, 它照样绿。
	##   ⇒ 平移到行为: 把那一行从**建出来的树上**捞出来, 问它身上挂了什么。
	_type_line_checks(all)
	## ★分母: 羁绊总览条还在(它才是这一页说羁绊的地方)
	_chk("⑫ ★分母: 页面底部的羁绊总览条还在", src_shop.find("func _build_synergy_bar") >= 0)

	# ── ⑭ ★「没有属性只有效果」这句, 商店和背包必须逐字相同 ──
	#   由来: 同一件装备在两页看是同一句话。2026-09-28 之前商店是「（本件不提供属性加成，
	#   只有效果）」、背包定稿成「这件不加属性，只有效果」—— 同一句话两个版本, 玩家会
	#   以为两页讲的不是一回事, 比两边都留着原文更糟。
	#   ★量的是【两个文件里都出现了同一个字面量】, 不是"商店里有某句话" ——
	#     后者只要我在商店改个新词就恒真, 守不住"两边一致"这件事。
	## ★必须先剥注释再找 —— 两个文件的注释里都【引着旧句原文】("原文「…」是公文体")。
	##   拿生源码 grep 的话, 这条会被那两行历史说明钉成永远红, 而它本该管的是
	##   "还有没有代码真的把旧句显示给玩家"。(第一版就是这么红的, 红得不对。)
	var src_inv := FileAccess.get_file_as_string("res://scripts/scenes/InventoryScene.gd")
	_chk("⑭ ★分母: 读得到 InventoryScene.gd", src_inv.length() > 1000)
	var code_shop := _strip_comments(src_shop)
	var code_inv := _strip_comments(src_inv)
	_chk("⑭ ★分母: 剥注释没把代码剥没(两边都还剩大半)",
		code_shop.length() > src_shop.length() / 3 and code_inv.length() > src_inv.length() / 3)
	_chk("⑭ ★★商店与背包共用同一句「这件不加属性，只有效果」",
		code_shop.find("这件不加属性，只有效果") >= 0 and code_inv.find("这件不加属性，只有效果") >= 0)
	_chk("⑭ ★旧的公文体版本在【代码里】两边都已绝迹(留一处 = 又是两个版本)",
		code_shop.find("本件不提供属性加成") < 0 and code_inv.find("本件不提供属性加成") < 0)

	# ── ⑮ ★没有【吊着的分隔符】: 「上·」这种点号后面空着一片的标签 ──
	#   由来(2026-09-28 实拍, 而且是点开弹层才看见): 出战阵容那六列在【还没选龟】时
	#   写的是「上·」「下·」—— 点号后面什么都没有, 一眼就是"这里没做完"。
	#   根因是兜底永远轮不到(`u.get("id", "龟")` 里 id 是**空串而不是缺键**), 不是忘了写。
	#   ★这一类只有"把两半拼起来"的文案才会犯, 而那种拼接满屏都是 ⇒ 按形状扫全屏 Label,
	#     不是去断言某一句话长什么样(断言字面量的话, 换个拼法它又能溜回来)。
	#   ★`data_integrity.py` 早就对 json 文案做同一件事(`_is_dangle`), 这里补上屏幕这一侧。
	#   ★★必须【连弹层一起扫】—— 出错的那两块(备战席 / 出战阵容)自 2026-07-29 起
	#     `_rebuild()` 根本不画, 只在底部两颗按钮点开的弹层里画。
	#     只扫静止页的话这条**恒绿**: 第一版就是这样, 把 bug 放回去也没红(反向验证救的)。
	var dangle: Array = []
	var scanned := 0
	scanned += _scan_dangle(all, dangle)
	var pop_lines := 0
	for kind in ["bench", "lineup"]:
		sc.call("_open_bottom_popup", kind)
		await get_tree().process_frame
		var pop = sc.get("_popup")
		if pop == null or not is_instance_valid(pop):
			print("  [FAIL] ⑮ ★分母: 弹层 %s 没建起来" % kind); _fail += 1
			continue
		var plist: Array = []
		_collect(pop, plist)
		pop_lines += _scan_dangle(plist, dangle)
		pop.queue_free()
		await get_tree().process_frame
	scanned += pop_lines
	print("     ⑮ ★分母: 静止页 %d 行 + 弹层 %d 行 = %d 行 Label 文字" % [
		scanned - pop_lines, pop_lines, scanned])
	_chk("⑮ ★分母: 扫到的文字行 > 10(太少 = 下面那条是空检查)", scanned > 10)
	_chk("⑮ ★分母: 弹层里也真的扫到字了(0 行 = 「点了才出现」那半边没被覆盖)", pop_lines > 5)
	if not dangle.is_empty():
		print("       ★吊着分隔符的: " + str(dangle.slice(0, 8)))
	_chk("⑮ ★★没有吊着的分隔符(「上·」那种点号后面空着的拼接文案)", dangle.is_empty())

	_done(sc)


## 一批控件里所有 Label 的文字, 逐行查【吊着的分隔符】。返回扫了多少行(★分母)。
func _scan_dangle(ctrls: Array, out: Array) -> int:
	var seps := ["·", "・", "、", "，", ",", "：", ":", "/", "|", "—", "-"]
	var n := 0
	for c in ctrls:
		if not (c is Label):
			continue
		for raw in str((c as Label).text).split("
"):
			var t := str(raw).strip_edges()
			if t == "":
				continue
			n += 1
			for sp in seps:
				if t.ends_with(sp) or t.begins_with(sp) or t.find(sp + sp) >= 0:
					out.append("「%s」" % t)
					break
	return n


## 把整行注释剥掉, 只留可执行的代码。
## ★本仓的硬规矩是"行内注释绝不插进行中间"(CLAUDE.md §3.7), 所以按行剥是安全的 ——
##   一个 `#` 出现在行首(去掉前导 tab 之后)就是整行注释。
func _strip_comments(src: String) -> String:
	var out := ""
	for ln in src.split("
"):
		if str(ln).strip_edges().begins_with("#"):
			continue
		out += str(ln) + "
"
	return out


## Label 里【文字真正占的那块矩形】(不是控件框)。
## 控件框常常比文字宽一大截, 加上对齐方式, 文字可能贴在框的左/中/右。
## 只有拿到这块才判得准"图标有没有盖住字"。
func _text_rect(lb: Label) -> Rect2:
	var txt := str(lb.text)
	if txt == "":
		return Rect2(lb.position, Vector2.ZERO)
	var f: Font = lb.get_theme_font("font")
	var fs: int = lb.get_theme_font_size("font_size")
	if f == null:
		return Rect2(lb.position, lb.size)      # 拿不到字体就退回控件框(宁可漏判也不误报)
	var ts: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var tw: float = minf(ts.x, lb.size.x)
	var th: float = minf(f.get_height(fs), lb.size.y)
	var x: float = lb.position.x
	match lb.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER: x += (lb.size.x - tw) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:  x += lb.size.x - tw
	var y: float = lb.position.y
	match lb.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER: y += (lb.size.y - th) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM: y += lb.size.y - th
	return Rect2(Vector2(x, y), Vector2(tw, th))


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var ct: Control = c
			if ct.size.x > 0.0 and ct.size.y > 0.0:
				out.append(ct)
		_collect(c, out)


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("  %s %s" % ["[PASS]" if ok else "[FAIL]", what])


## ★★镀层闪光: 背包已有的装备, 货架卡上必须有一层【会呼吸的金色镀层】
##   (用户 2026-08-14:「背包里有的装备在货架栏出现时要有镀层闪光效果告知用户背包里已有」)。
## ★数产品自己建的节点(卡下多出的 Panel + 它里面的 ColorRect 高光), 不数我插的标记。
## ★正反两面都验: 已拥有 ⇒ 有; 没拥有 ⇒ 没有。只验一面守不住"每张卡都镀"。
func _check_owned_shine(sc) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd")
	_chk("镀层挂在【已拥有】这个条件下(owned > 0)", src.find("if owned > 0:") >= 0)
	_chk("镀层不挡点击(MOUSE_FILTER_IGNORE)", src.find("glow.mouse_filter = Control.MOUSE_FILTER_IGNORE") >= 0)
	_chk("镀层会呼吸(循环 tween 改 modulate:a)", src.find("bt.tween_property(glow, \"modulate:a\"") >= 0)
	_chk("有一道斜掠高光(ColorRect 扫过卡面)", src.find("shine.rotation = -0.5") >= 0)
	## 反面: 源码里这段必须在 `owned > 0` 之内 —— 若被挪到条件外, 每张卡都会镀。
	var i_cond: int = src.find("if owned > 0:")
	var i_glow: int = src.find("var glow := Panel.new()")
	_chk("★反面: 镀层在条件【之内】(不是每张卡都镀)", i_cond > 0 and i_glow > i_cond and i_glow - i_cond < 900)
	await _check_no_diagonal_spill(sc)


## ★★★斜向元素不许画到卡外 —— 2026-09-28 实拍抓到的真 bug 焊成门禁。
##
## 那一版的掠光是 26×245 的 ColorRect, 绕左上角转 -0.5 rad 再横扫 -40 → SLOT_W+40,
## 而 Godot 的 Control **默认不裁子节点** ⇒ 一条灰白斜带扫出卡外 180px, 正好盖到隔壁那张卡上。
## 实拍空隙里量到 RGB(57,64,62), 裁住之后是背景色 RGB(10,22,34)。
##
## ★上面那四条 `_chk` 全是【读源码找字符串】—— 掠光溢出的那些天它们**一条都没红**,
##   因为源码里 `shine.rotation = -0.5` 一直都在。字符串在不在, 和画出来的东西在哪, 是两件事。
##   ⇒ 这一条量【裁剪之后真正画出来的那块】: 四角走全局变换(含 rotation), 再逐级与每个
##     `clip_contents` 祖先求交, 然后和卡片矩形比。
## ★掠光的 x 由循环 tween 在扫 ⇒ 随便一帧抓到的位置不定, 靠运气抓不住最坏的一帧。
##   这里把扫描路径上的采样点逐个钉死再量。
## ★分母: 先把货架上每一件塞进背包(否则新档背包空 ⇒ 一道掠光都不建 ⇒ 这条是空检查)。
func _check_no_diagonal_spill(sc) -> void:
	var gs = get_node_or_null("/root/GameState")
	var off: Array = sc.get("_offer")
	var bench: Array = []
	for e in off:
		if e is Dictionary:
			bench.append({"id": str((e as Dictionary).get("id", "")), "star": 1})
	gs.persistent_bench = bench
	if sc.has_method("_rebuild"):
		sc.call("_rebuild")
	for _i in range(3):
		await get_tree().process_frame

	var cards: Array = []
	_collect_cards(sc, cards)
	var rots: Array = []
	for card in cards:
		var r: Array = []
		_collect_rotated(card, r)
		for cr in r:
			rots.append([card, cr])
	print("     ⑬ ★分母: 货架卡 %d 张, 其中斜向元素 %d 个" % [cards.size(), rots.size()])
	_chk("⑬ ★分母: 至少找到 1 个斜向元素(0 个 = 下面那条是空检查)", rots.size() > 0)

	var worst := 0.0
	var worst_desc := ""
	for pair in rots:
		var card: Control = pair[0]
		var cr: Control = pair[1]
		var card_rect := Rect2(card.global_position, card.size)
		var base_y: float = cr.position.y
		var base_x: float = cr.position.x
		for sx in [-40.0, -10.0, 20.0, 66.0, 110.0, 132.0, 152.0, 172.0]:
			cr.position = Vector2(sx, base_y)
			var vis := _visible_aabb(cr)
			var out: float = _outside_amount(vis, card_rect)
			if out > worst:
				worst = out
				worst_desc = "%s 在 x=%.0f 时画到 %.0f..%.0f (卡 %.0f..%.0f)" % [
					str(cr.name), sx, vis.position.x, vis.end.x, card_rect.position.x, card_rect.end.x]
		cr.position = Vector2(base_x, base_y)
	print("     ⑬ 最大出界 %.1f px%s" % [worst, ("  ← " + worst_desc) if worst > 0.5 else ""])
	_chk("⑬ ★★斜向元素(掠光/斜纹)不许画出卡片轮廓 —— 必须套 `_clip_box` 的剪刀", worst <= 0.5)


## 货架卡 = 尺寸恰为 132×136 的 Panel。★必须递归: `UIFrame.attach()` 会把所有
## 子节点收编进居中框, 卡片不再是场景根的直接子节点(只看直接子节点 ⇒ 扫到 0 张 ⇒ 空检查)。
func _collect_cards(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Panel and absf((c as Panel).size.x - 132.0) < 1.0 and absf((c as Panel).size.y - 136.0) < 1.0:
			out.append(c)
		else:
			_collect_cards(c, out)


func _collect_rotated(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ColorRect and absf((c as ColorRect).rotation) > 0.01:
			out.append(c)
		_collect_rotated(c, out)


## 这个控件在屏幕上【真正画出来的那块】: 四角走全局变换(含旋转), 再与每个
## `clip_contents` 祖先求交。没有裁剪祖先时 = 旋转后的整块外接矩形。
func _visible_aabb(ct: Control) -> Rect2:
	var xf: Transform2D = ct.get_global_transform()
	var sz: Vector2 = ct.size
	var r := Rect2(xf * Vector2.ZERO, Vector2.ZERO)
	for v in [Vector2(sz.x, 0.0), Vector2(0.0, sz.y), sz]:
		r = r.expand(xf * v)
	var a: Node = ct.get_parent()
	while a != null:
		if a is Control and (a as Control).clip_contents:
			r = r.intersection(Rect2((a as Control).global_position, (a as Control).size))
		a = a.get_parent()
	return r


## 出界量 = 可见块超出卡片矩形最多的那一边(px)。被裁成空 ⇒ 什么都没画 ⇒ 0。
func _outside_amount(vis: Rect2, card: Rect2) -> float:
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return 0.0
	return maxf(maxf(card.position.x - vis.position.x, vis.end.x - card.end.x),
		maxf(card.position.y - vis.position.y, vis.end.y - card.end.y))


func _done(sc) -> void:
	await _check_owned_shine(sc)
	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 商店版式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════════════
#  ⑫ 详情面板【价格行】: 类型写得出来, 且图标是【这个类型自己】的像素图
# ══════════════════════════════════════════════════════════════════════
## ★为什么要单独一节: 2026-09-28 类型图标从 emoji 换成 `assets/sprites/tags/` 的像素图,
##   这一行也从 `Label` 换成 `RichTextLabel`(Label 画不了行内图)。
##   原判据 grep 的是源码里那句 `Phase2Types.emoji_of(_tp2), _tp2` ——
##   **换个名字继续 grep `icon_of(_tp2)` 是同一个毛病**: 它守的是"源码长这样",
##   而需求是"玩家在这一行上看得见类型 + 一张属于这个类型的图"。
##
## ★★量的四件事, 每件都能单独红:
##   ① 价格行在树上, 而且**是 RichTextLabel** —— Label 画不了行内图, 换回去就是没图标
##   ② 行里写着类型名本身(「弓箭」), **不许出现花名**(「弓箭·神射手」游戏里没有这东西)
##   ③ 行内图标的路径 == `Phase2Types.icon_of(行上写的那个类型名)`
##      —— 这一条才是「香火显示成一把剑」那一族的判据: 挂错类型的图当场红
##   ④ 那张图**真的在盘上** —— 路径写错也是"悄悄不画", 不报错
func _type_line_checks(all: Array) -> void:
	var P2T = load("res://scripts/gamedata/phase2_types.gd")
	## 价格行的识别位 = 产品自己写的单位「深海币」(不是我为测试加的标记)。
	var lines: Array = []
	var as_label: int = 0
	for c in all:
		if c is RichTextLabel and str((c as RichTextLabel).text).find("深海币") >= 0:
			lines.append(c)
		elif c is Label and str((c as Label).text).find("深海币") >= 0 \
			and str((c as Label).text).find("·") >= 0:
			as_label += 1
	_chk("⑫ ★分母: 详情面板的价格行建出来了, 而且是 RichTextLabel(%d 条; Label 版 %d 条)"
		% [lines.size(), as_label], lines.size() >= 1 and as_label == 0)
	if lines.is_empty():
		return
	var txt: String = str((lines[0] as RichTextLabel).text)
	print("     ⑫ 价格行原文: %s" % txt)
	## 「N 深海币  ·  [img=16x16]res://...tags/tag-bow.png 弓箭」
	var sep: int = txt.find("  ·  ")
	_chk("⑫ ★价格行上仍然写着类型(买之前要知道的事实)", sep >= 0)
	if sep < 0:
		return
	var tail: String = txt.substr(sep + 5)
	var i_end: int = tail.find("[/img]")
	var i_open: int = tail.find("]")
	var icon: String = tail.substr(i_open + 1, i_end - i_open - 1) if (tail.begins_with("[img") and i_end > i_open and i_open >= 0) else ""
	var name_shown: String = (tail.substr(i_end + 6) if i_end >= 0 else tail).strip_edges()
	_chk("⑫ ★只写羁绊名本身「%s」, 不用「弓箭·神射手」这种花名" % name_shown,
		name_shown != "" and name_shown.find("·") < 0)
	## ★★这一条是核心: 行上画的图必须属于行上写的那个类型。
	_chk("⑫ ★★行内图标 == Phase2Types.icon_of(「%s」)  实测 %s" % [name_shown, icon],
		icon != "" and icon == str(P2T.icon_of(name_shown)))
	_chk("⑫ ★★那张图真的在盘上(路径写错也只是悄悄不画)",
		icon != "" and ResourceLoader.exists(icon))
	## ★分母: 这张表不是"所有类型都回落成同一张图" —— 否则上面那条恒真。
	var uniq: Dictionary = {}
	for t in (P2T.TYPES as Dictionary).keys():
		uniq[str(P2T.icon_of(str(t)))] = true
	_chk("⑫ ★分母: %d 个类型有 %d 张互不相同的图(全回落成一张时上一条恒真)"
		% [(P2T.TYPES as Dictionary).size(), uniq.size()],
		uniq.size() == (P2T.TYPES as Dictionary).size() and not uniq.has(""))
