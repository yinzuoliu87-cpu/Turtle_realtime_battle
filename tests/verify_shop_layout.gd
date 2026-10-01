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
## ★★这两个 preload 是为了【从产品自己身上回读常量】, 不在这里手抄一份副本
##   (memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后)。
const SHOP_GD = preload("res://scripts/scenes/ShopScene.gd")
const P2CFG = preload("res://scripts/gamedata/phase2_config.gd")
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
var _n := 0
## 全绿时的断言条数【地板】。低于它 = 有协程在半路被掐断 / 静默 abort ⇒ 判红
## (fb-null-readback-makes-test-silently-abort: 读一个不存在的成员会让协程就地返回,
##  后面的断言一条不跑, 而进程 rc=0 还照样打 ALL PASS)。加/删断言时同步改这个数。
const MIN_ASSERTS := 92


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
	## ★★2026-10-01 补这一条: 上面两条只对了【框与字号】, 没对**量的是哪一串文字**。
	##   这条判据原来自己算 `render_consts(effectDesc1)`, 而商店真正显示的是
	##   `SkillText.equip_full_bb(edef, 20)` —— P2 给装备接上内联属性图标之后, 两者**不是一回事**
	##   (实测: 按老写法 3 件要滚, 按真入口 4 件), 而这条判据会一直绿着。
	##   ⇒ 现在下面取文字用的就是那一行; 这里焊住"商店确实还在用它", 它一改这条就红。
	_chk("⑥ ★口径自检: 取文字走的与 ShopScene._rich_desc 同一个口(equip_full_bb(edef, 20))",
		src_shop.find("SkillText.equip_full_bb(edef, 20)") >= 0)
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
			## ★★2026-10-01 修【判据没跑真入口】: 这里原来是
			##   `SkillText.render_consts(str(ed.get("effectDesc1", "")))` —— 自己另算一份,
			##   而商店真正显示的是 `ShopScene._rich_desc` ⇒ `SkillText.equip_full_bb(edef, 20)`。
			##   P2 给装备文案接上内联属性图标之后, **图标比字高**, 正是会撑爆这个 246px 框的东西,
			##   而这条判据按老写法量的是没有图标的纯文本 —— 它会一直绿着, 说的却是另一件事。
			##   (memory `fb-verify-must-run-the-real-path` / `fb-hand-rolled-copies-drift`)
			## ⚠ 与真入口仍差两点, 都不影响高度: ① 数据损坏时的空态兜底 ② highlight_star 只加色标记。
			var raw := SkillText.equip_full_bb(ed, 20)
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
	_n += 1
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
	_check_shared_skin(sc)
	await _check_owned_shine(sc)
	## ★下面四条各自改 GameState(等级/背包/身上的装备), 所以一律放在前面那些
	##   "看现场版式"的判据【之后】—— 顺序反了会把它们的现场掀掉。
	_check_sell_nonzero()
	await _check_name_not_truncated(sc)
	await _check_equip_cap_same_source(sc)
	await _check_bag_popup_all(sc)
	await _check_maxlevel_xp()      # ★台账 ⑷: 满级不许印哨兵分母 / 死按钮要长得像死的
	await _check_buy_feedback()     # ★台账 ⑮: 不成交要说为什么, 成交要看得见
	sc.queue_free()
	await get_tree().process_frame
	print("")
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d) —— 有东西在半路被掐断了, 别当绿灯"
			% [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
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


# ══════════════════════════════════════════════════════════════════════
#  SHARED_SKIN —— 商店的按钮皮必须来自共享层, 不许再有屏幕专用的一次性皮
# ══════════════════════════════════════════════════════════════════════
## ★由来(用户 2026-09-29:「不好看的按钮」)。在此之前商店自己建 StyleBoxTexture,
##   贴 `assets/sprites/shop/btn-frame.png`(128×64) + `shop/buy-btn.png` —— 而
##   主菜单/背包/图鉴/排行榜/设置/对阵表… 十个屏都走 `UISkin.button`。
##   **同一种控件两套皮**, 而且那张 128×64 里 36 行是边框、中段只剩 28 行,
##   套到实测 76~96 高的按钮上被拉 2.7~3.4 倍 ⇒ 实拍就是一圈青色细描边。
##
## ★★判据**不是我列的一张贴图白名单** —— 名单会跟着共享层漂(memory:
##   「有没有一个客观事实可以代替我的名单」)。这里拿**共享层自己**当尺子:
##   造一颗同尺寸的临时按钮丢给 `UISkin.button()`, 问它会挑哪张,
##   再和商店那颗真按钮身上挂的那张比。共享层哪天改了挑法, 这条跟着走, 不用改判据。
##
## ★量四件事, 每件都能单独红:
##   ① [分母] 真的扫到了按钮, 而且其中带贴图皮的 ≥5 颗 —— N=0 是空检查不是通过
##   ② 没有一颗按钮的皮来自 `res://assets/sprites/shop/` (= 屏幕专用的一次性皮)
##   ③ 每一颗的贴图 == `UISkin.button()` 对**同样宽高**会挑的那张
##   ④ 边带×2 装得进这颗按钮的真实宽高(ui_skin.gd:117 那条量出来的判法) ——
##      装不进去的话九宫格会把两端叠在一起, 那正是当初不选 `menu/btn-frame.png` 的原因
func _check_shared_skin(sc) -> void:
	var btns: Array = []
	_collect_buttons(sc, btns)
	var skinned: Array = []
	var from_shop: Array = []
	var mismatch: Array = []
	var band_overflow: Array = []
	for b in btns:
		var bt := b as Button
		var sb := bt.get_theme_stylebox("normal")
		if not (sb is StyleBoxTexture):
			continue                       # TopBar 那两颗是共享原语给的扁平薄片, 本来就没贴图
		var st := sb as StyleBoxTexture
		if st.texture == null:
			continue
		skinned.append(bt)
		var path := str(st.texture.resource_path)
		var r := bt.get_global_rect()
		if path.begins_with("res://assets/sprites/shop/"):
			from_shop.append("%s ← %s" % [bt.text.substr(0, 10), path])
		## 共享层对同尺寸会挑哪张? 造一颗一次性按钮去问它, 不拿我写死的名单比。
		var probe := Button.new()
		probe.size = r.size
		probe.custom_minimum_size = r.size
		UISkin.button(probe)
		var psb := probe.get_theme_stylebox("normal")
		var want := ""
		var want_margin := 0.0
		if psb is StyleBoxTexture and (psb as StyleBoxTexture).texture != null:
			want = str(((psb as StyleBoxTexture).texture as Texture2D).resource_path)
			want_margin = (psb as StyleBoxTexture).texture_margin_left
		probe.free()
		if want != "" and want != path:
			mismatch.append("%s 用 %s, 而共享层对 %.0fx%.0f 会挑 %s"
				% [bt.text.substr(0, 10), path.get_file(), r.size.x, r.size.y, want.get_file()])
		## ④ 边带×2 装不装得进这个控件(横竖各算一遍)
		var mx: float = st.texture_margin_left + st.texture_margin_right
		var my: float = st.texture_margin_top + st.texture_margin_bottom
		if mx >= r.size.x or my >= r.size.y:
			band_overflow.append("%s %.0fx%.0f 装不下边带 %.0f/%.0f"
				% [bt.text.substr(0, 10), r.size.x, r.size.y, mx, my])
	print("  [SHARED_SKIN 分母] 扫到 %d 颗按钮, 其中带贴图皮 %d 颗" % [btns.size(), skinned.size()])
	for b2 in skinned:
		var s2 := (b2 as Button).get_theme_stylebox("normal") as StyleBoxTexture
		print("     %-22s %5.0fx%-4.0f %s" % [str((b2 as Button).text).substr(0, 20),
			(b2 as Button).get_global_rect().size.x, (b2 as Button).get_global_rect().size.y,
			str(s2.texture.resource_path).get_file()])
	_chk("SHARED_SKIN ★分母: 商店里带贴图皮的按钮 ≥5 颗(N=0 是空检查)", skinned.size() >= 5)
	_chk("SHARED_SKIN ★没有屏幕专用的一次性皮(assets/sprites/shop/ 下的贴图不许当按钮皮): %s"
		% ("无" if from_shop.is_empty() else str(from_shop)), from_shop.is_empty())
	_chk("SHARED_SKIN ★★每颗的皮 == UISkin.button() 对同尺寸会挑的那张: %s"
		% ("全对上" if mismatch.is_empty() else str(mismatch)), mismatch.is_empty())
	_chk("SHARED_SKIN ★边带×2 装得进每颗按钮的真实宽高: %s"
		% ("全装得下" if band_overflow.is_empty() else str(band_overflow)), band_overflow.is_empty())


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button and (n as Button).visible:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


# ══════════════════════════════════════════════════════════════════════
#  SELL_NONZERO —— 不许存在「卖了一分钱不退」的装备
# ══════════════════════════════════════════════════════════════════════
## ★由来(2026-09-29 真机实测·台账 ⑶): 背包里点「卖出 +0」⇒ 木制长剑从背包消失、
##   深海币 4→4。原式 `floor(cost * star * 0.8)` 在 1费1★ 上算出 **0**,
##   而 1 费正是出货率最高的那一档 —— 96 件里 23 件可卖件全中。
##   那不是「便宜」是 **白没**: 一次点击、不可撤销、还没有确认框。
##
## ★★判据量的是**卖价函数本身**, 逐格穷举 96 件 × 3 星 —— 不抽样、不挑代表件。
##   四条各自能单独红:
##     ① [分母] 真的扫到了可卖件 × 3 星(N=0 是空检查不是通过)
##     ② 没有一格 < 1
##     ③ [分母·反证] **同一套量法**把地板价摘掉(= 修复前的原式)会量出 N 格为 0,
##        N>0 ⇒ 这条判据不是恒真式(照 SHARED_SKIN 那条的做法: 拿产品自己当尺子)
##     ④ 单一事实源: 屏上写的价与真进账的数都只能从 `Phase2Config.sell_value` 取
func _check_sell_nonzero() -> void:
	var dr := get_node_or_null("/root/DataRegistry")
	var eqs: Array = dr.phase2_equipment if dr != null else []
	var zero: Array = []
	var raw_zero := 0
	var cells := 0
	var sellable := 0
	var one_cost := 0
	for e in eqs:
		var ed: Dictionary = e if e is Dictionary else {}
		## 羁绊赠送件(圣光护盾 shopAvailable=0): `_sell_selected` 开头就早退,
		## 它根本进不了交易路径 ⇒ 不算「可卖装备」。
		if int(ed.get("shopAvailable", 1)) == 0:
			continue
		sellable += 1
		var cost := int(ed.get("cost", 1))
		if cost <= 1:
			one_cost += 1
		for star in range(1, 4):
			cells += 1
			var v := int(P2CFG.sell_value(cost, star))
			if v < 1:
				zero.append("%s(%d 费)★%d → +%d" % [str(ed.get("name", "?")), cost, star, v])
			## 同一套量法, 只把地板价摘掉 = 修复前那条原式
			if int(floor(float(maxi(1, cost) * star) * float(P2CFG.SELL_RATE))) < 1:
				raw_zero += 1
	print("")
	print("  [SELL_NONZERO 分母] 装备表 %d 件, 其中可卖 %d 件(1 费 %d 件) × 3 星 = %d 格"
		% [eqs.size(), sellable, one_cost, cells])
	_chk("SELL_NONZERO ★分母: 真扫到 %d 件可卖装备 × 3 星 = %d 格(N=0 是空检查)" % [sellable, cells],
		sellable >= 90 and cells >= 270)
	_chk("SELL_NONZERO ★★没有一格卖价是 0 —— 要么给钱、要么别让卖, 不许「白没」: %s"
		% ("全部 ≥1" if zero.is_empty() else str(zero.slice(0, 6))), zero.is_empty())
	_chk("SELL_NONZERO ★分母·反证: 同一套量法摘掉地板价会量出 %d 格为 0(>0 ⇒ 上一条不是恒真式)"
		% raw_zero, raw_zero > 0)
	## ★只看**代码行**, 注释行要跳过 —— 那个原式此刻正被写在注释里当反面教材,
	##   整份文件里搜一下必然命中, 那样这条就永远红(第一版就是这么红的)。
	var ops := FileAccess.get_file_as_string("res://scripts/scenes/inventory/equip_ops.gd")
	var handrolled: Array = []
	var routed := false
	for ln in ops.split("
"):
		var t := str(ln).strip_edges()
		if t.begins_with("#"):
			continue
		if t.find("P2.sell_value(") >= 0:
			routed = true
		if t.find("0.8") >= 0:
			handrolled.append(t.substr(0, 60))
	_chk("SELL_NONZERO ★单一事实源: 卖价只从 Phase2Config.sell_value 取, 代码里没有手写的取整式 %s"
		% ("" if handrolled.is_empty() else str(handrolled)),
		routed and handrolled.is_empty())


# ══════════════════════════════════════════════════════════════════════
#  NAME_NOT_TRUNCATED —— 出战阵容里那行装备名不许被裁
# ══════════════════════════════════════════════════════════════════════
## ★由来(台账 ⑺): 那行字**就是为了「手机没有 hover、别只靠 tooltip」才加的**,
##   而它当初画在 36px 宽的格子上 ⇒ 只看得见前 3 个字。讽刺就在这里。
##
## ★★判据量的是**真实渲染宽度**, 不是数字数 —— 中文/拉丁/数字每个字的宽都不一样,
##   「N 个字以内」这种判据换一件带 A/B 后缀的装备就骗过去了。
## ★七条断言, 每条能单独红:
##   ① [分母] 96 件全扫到, 并打出最长名字/最宽像素
##   ② 现宽度下**一件都不超**
##   ③ 现宽度下没有两个不同的名字被裁成**同一个词**(守护贝壳/守护贝母 →「守护贝」那一族)
##   ④⑤ [分母·反证] 同一套量法, 把宽度换回改版前的 36px 会量出一堆超宽 + 好几组同词
##      ⇒ 量法不是恒真式
##   ⑥⑦ 屏上那个控件**真的**是这个宽度和字号(常量对得上而控件没读它 = 判据白跑,
##      memory [[fb-gate-subject-never-constructed]])
func _check_name_not_truncated(sc) -> void:
	var box_w := float(SHOP_GD.LINEUP_NAME_W)
	var fsz := int(SHOP_GD.LINEUP_NAME_FONT)
	## 量尺 = 产品那行字自己的字体/字号。这颗 Label 只借来拿 Font, 不参与版式。
	var ruler := Label.new()
	ruler.add_theme_font_size_override("font_size", fsz)
	add_child(ruler)
	await get_tree().process_frame
	var f: Font = ruler.get_theme_font("font")
	## ★键名是 "font_size" 不是 "font" —— 写错会静默拿到主题默认的 16 号,
	##   量出来的宽度全部偏大 45%(第一版探针就是这么量的, 那个 96px 是假数)。
	var fs: int = ruler.get_theme_font_size("font_size")
	ruler.queue_free()
	var dr := get_node_or_null("/root/DataRegistry")
	var eqs: Array = dr.phase2_equipment if dr != null else []
	var over: Array = []
	var over36 := 0
	var worst := 0.0
	var worst_nm := ""
	var maxchars := 0
	var vis_now: Dictionary = {}
	var vis_36: Dictionary = {}
	var names := 0
	for e in eqs:
		var nm := str((e as Dictionary).get("name", ""))
		if nm == "":
			continue
		names += 1
		maxchars = maxi(maxchars, nm.length())
		var w: float = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		if w > worst:
			worst = w
			worst_nm = nm
		if w > box_w + 0.5:
			over.append("%s 需 %.0fpx" % [nm, w])
		if w > 36.5:
			over36 += 1
		_bump(vis_now, _visible_prefix(f, fs, nm, box_w), nm)
		_bump(vis_36, _visible_prefix(f, fs, nm, 36.0), nm)
	var dup_now := _dup_groups(vis_now)
	var dup_36 := _dup_groups(vis_36)
	print("")
	print("  [NAME_NOT_TRUNCATED 分母] 扫到 %d 个装备名; 最长 %d 个字; 最宽「%s」= %.0fpx; 框宽 %.0fpx / 字号 %d"
		% [names, maxchars, worst_nm, worst, box_w, fs])
	_chk("NAME_NOT_TRUNCATED ★分母: 96 件名字全扫到, 字体/字号取到了(%d 号)" % fs,
		names >= 90 and f != null and fs == fsz)
	_chk("NAME_NOT_TRUNCATED ★★现框宽 %.0fpx 下一件都不超(最宽的「%s」占 %.0fpx): %s"
		% [box_w, worst_nm, worst, "无" if over.is_empty() else str(over.slice(0, 6))], over.is_empty())
	_chk("NAME_NOT_TRUNCATED ★★没有两个不同的装备被裁成同一个词: %s"
		% ("无" if dup_now.is_empty() else str(dup_now)), dup_now.is_empty())
	print("     反证(同一套量法·把框宽换回改版前的 36px): %d 件超宽 / %d 组撞成同词 %s"
		% [over36, dup_36.size(), str(dup_36.slice(0, 3))])
	_chk("NAME_NOT_TRUNCATED ★分母·反证: 36px 下量出 %d 件超宽(>0 ⇒ 量法不是恒真式)" % over36,
		over36 > 0)
	_chk("NAME_NOT_TRUNCATED ★分母·反证: 36px 下量出 %d 组撞成同词(>0 ⇒ 撞词那条也不是恒真式)"
		% dup_36.size(), dup_36.size() > 0)
	## ── 屏上那个控件真的用这个宽度和字号吗 ────────────────────────
	var long_id := ""
	for e in eqs:
		if str((e as Dictionary).get("name", "")) == worst_nm:
			long_id = str((e as Dictionary).get("id", ""))
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.dual_lineup = {}          # 让 get_dual_lineup 重建成合法默认结构
	GameState.persistent_equipped = {"basic": [{"id": long_id, "star": 1}]}
	if sc._popup != null and is_instance_valid(sc._popup):
		sc._popup.queue_free()
		await get_tree().process_frame
	sc._open_bottom_popup("lineup")
	for _i in range(5):
		await get_tree().process_frame
	var hits: Array = []
	for c in _labels_in(sc._popup):
		if str((c as Label).text) == worst_nm:
			hits.append(c)
	_chk("NAME_NOT_TRUNCATED ★分母: 弹层里真的画出了「%s」那行字(%d 个) —— 找不到就说明上面全白量"
		% [worst_nm, hits.size()], hits.size() >= 1)
	if hits.size() >= 1:
		var lb: Label = hits[0]
		_chk("NAME_NOT_TRUNCATED ★★屏上那个控件宽 %.0fpx == LINEUP_NAME_W(%.0f)"
			% [lb.size.x, box_w], absf(lb.size.x - box_w) < 0.5)
		_chk("NAME_NOT_TRUNCATED ★★屏上那个控件字号 %d == LINEUP_NAME_FONT(%d)"
			% [lb.get_theme_font_size("font_size"), fsz], lb.get_theme_font_size("font_size") == fsz)
		var wr: float = f.get_string_size(str(lb.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			lb.get_theme_font_size("font_size")).x
		_chk("NAME_NOT_TRUNCATED ★★那行字在自己的控件里放得下(%.0f ≤ %.0f, 省略号一次都不该出现)"
			% [wr, lb.size.x], wr <= lb.size.x + 0.5)


## 宽度 w 装得下的最长前缀 = 玩家实际看得见的那个词
func _visible_prefix(f: Font, fs: int, nm: String, w: float) -> String:
	if f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x <= w + 0.5:
		return nm
	var k := 0
	while k < nm.length():
		if f.get_string_size(nm.substr(0, k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x > w + 0.5:
			break
		k += 1
	return nm.substr(0, k)


func _bump(d: Dictionary, key: String, val: String) -> void:
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append(val)


## 同一个可见词对应 >1 个装备名 = 玩家看到两件「同名」的东西
func _dup_groups(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		if (d[k] as Array).size() > 1:
			out.append("「%s」= %s" % [str(k), str(d[k])])
	return out


func _labels_in(n: Node) -> Array:
	var out: Array = []
	if n == null or not is_instance_valid(n):
		return out
	_labels_rec(n, out)
	return out


func _labels_rec(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels_rec(c, out)


# ══════════════════════════════════════════════════════════════════════
#  EQUIP_CAP_SAME_SOURCE —— 商店写的「已装 N/M」必须就是真正拦人的那个上限
# ══════════════════════════════════════════════════════════════════════
## ★由来: `_lineup_equip_count()` 原来自己数 `slots += 3` × 6 只 ⇒ 分母**恒等于 18**,
##   而真上限是 `GameState.team_equip_cap()` = (赛季等级−1)×2。实测 Lv7 时商店写
##   「已装 12/18」而背包写「12/12」, 玩家照 18 去买了 4 件, 回来点空槽**毫无反应**
##   (拦人的是 12 那个数)。分子同病: 手数会把羁绊赠品算进去 ⇒ 满编时出现「已装 19/18」。
##
## ★★为什么必须扫**多个等级**: 恒等于 18 的写法在 Lv10 上是对的 —— 单档测永远绿。
##   所以判据里有一条分母专门问「这几档的真上限是不是同一个数」。
func _check_equip_cap_same_source(sc) -> void:
	print("")
	var caps: Dictionary = {}
	var bad: Array = []
	var found := 0
	GameState.persistent_equipped = {"basic": []}
	for L in [1, 3, 7, 10]:
		GameState.season_level = L
		sc._rebuild()
		for _i in range(4):
			await get_tree().process_frame
		var pair := _lineup_pair(sc)
		var want_cap := int(GameState.team_equip_cap())
		var want_used := int(GameState.team_equipped_count())
		caps[want_cap] = true
		if pair.is_empty():
			bad.append("Lv%d 找不到「出战阵容」按钮上那个读数" % L)
			continue
		found += 1
		print("     Lv%-2d 屏上「已装 %d/%d」   真上限 team_equip_cap()=%d  真已装 team_equipped_count()=%d"
			% [L, pair[0], pair[1], want_cap, want_used])
		if pair[1] != want_cap:
			bad.append("Lv%d 屏上分母 %d ≠ team_equip_cap()=%d" % [L, pair[1], want_cap])
		if pair[0] != want_used:
			bad.append("Lv%d 屏上分子 %d ≠ team_equipped_count()=%d" % [L, pair[0], want_used])
	_chk("EQUIP_CAP_SAME_SOURCE ★分母: 四档都读到了那个读数(%d/4)" % found, found == 4)
	_chk("EQUIP_CAP_SAME_SOURCE ★分母: 这四档的真上限有 %d 个不同值(全一样的话「恒等于 18」也能全绿)"
		% caps.size(), caps.size() >= 3)
	_chk("EQUIP_CAP_SAME_SOURCE ★★商店那个分母/分子 == GameState 的 team_equip_cap()/team_equipped_count(): %s"
		% ("四档全对上" if bad.is_empty() else str(bad)), bad.is_empty())
	## ── 羁绊赠品算不算进「已装」: 与真正拦人的 team_has_equip_room 同口径(= 不算) ──
	GameState.season_level = 7
	GameState.persistent_equipped = {"basic": []}
	sc._rebuild()
	for _i in range(4):
		await get_tree().process_frame
	var p0 := _lineup_pair(sc)
	GameState.persistent_equipped = {"basic": [{"id": "p2eq_095", "star": 1}]}
	sc._rebuild()
	for _i in range(4):
		await get_tree().process_frame
	var p1 := _lineup_pair(sc)
	_chk("EQUIP_CAP_SAME_SOURCE ★分母: p2eq_095 确实被 GameState 认成羁绊赠品",
		GameState.is_synergy_grant({"id": "p2eq_095", "star": 1}))
	_chk("EQUIP_CAP_SAME_SOURCE ★分母: 装上去这一步真的改动了身上的装备数组(现在 %d 件)"
		% (GameState.persistent_equipped.get("basic", []) as Array).size(),
		(GameState.persistent_equipped.get("basic", []) as Array).size() == 1)
	_chk("EQUIP_CAP_SAME_SOURCE ★★羁绊赠品不计入「已装」(装上前 %s / 装上后 %s) —— 否则满编时会写出「19/18」"
		% [str(p0), str(p1)],
		p0.size() == 2 and p1.size() == 2 and p0[0] == p1[0] and p0[1] == p1[1])


## 「🐢 出战阵容  已装 A/B」那颗按钮上的两个数。找不到 ⇒ 空数组(分母不成立)
func _lineup_pair(sc) -> Array:
	var btns: Array = []
	_collect_buttons(sc, btns)
	for b in btns:
		var t := str((b as Button).text)
		var i := t.find("已装 ")
		if i < 0:
			continue
		var parts: PackedStringArray = t.substr(i + 3).strip_edges().split("/")
		if parts.size() < 2:
			continue
		var a := str(parts[0]).strip_edges()
		var c := str(parts[1]).strip_edges()
		if a.is_valid_int() and c.is_valid_int():
			return [int(a), int(c)]
	return []


# ══════════════════════════════════════════════════════════════════════
#  BAG_POPUP_ALL —— 「背包里有 N 件, 点一下看看」点开就得有 N 件
# ══════════════════════════════════════════════════════════════════════
## ★由来: 标题写「背包里有 18 件」, 而 `_build_bench_preview` 里写死
##   `mini(10, bench.size())` ⇒ 点开只画 10 格, 剩下 8 件在界面上一点痕迹都没有,
##   弹层下半还空着两行。**静默截断**: 玩家只会以为东西丢了。
##
## ★两个量级各测一遍, 因为它们要的是两种不同的正确行为:
##   · 放得下(18 件) ⇒ **一件不少全画出来**
##   · 真放不下(>PER_ROW×MAX_ROWS) ⇒ 画满 + **屏上写清楚还剩几件**(截断可以, 不说话不行)
func _check_bag_popup_all(sc) -> void:
	print("")
	var per_row := int(SHOP_GD.BENCH_PER_ROW)
	var cap := per_row * int(SHOP_GD.BENCH_MAX_ROWS)
	print("  [BAG_POPUP_ALL 分母] 弹层一行 %d 格 × 最多 %d 行 = 画得下 %d 件"
		% [per_row, int(SHOP_GD.BENCH_MAX_ROWS), cap])
	for n in [18, cap + 5]:
		var bench: Array = []
		for i in range(n):
			bench.append({"id": "p2eq_%03d" % (1 + (i % 90)), "star": 1})
		GameState.persistent_bench = bench
		if sc._popup != null and is_instance_valid(sc._popup):
			sc._popup.queue_free()
			await get_tree().process_frame
		sc._open_bottom_popup("bench")
		for _i in range(5):
			await get_tree().process_frame
		var pan: Panel = _popup_panel(sc)
		var cells: Array = []
		if pan != null:
			_bench_cells(pan, cells)
		var want := mini(cap, n)
		print("     背包 %d 件 → 弹层画出 %d 格(该画 %d)   面板 %s"
			% [n, cells.size(), want, str(pan.size) if pan != null else "找不到"])
		_chk("BAG_POPUP_ALL ★分母: 背包真塞了 %d 件, 且弹层面板建出来了(>10 = 原来那个硬上限)" % n,
			n > 10 and GameState.persistent_bench.size() == n and pan != null)
		_chk("BAG_POPUP_ALL ★★背包 %d 件 → 弹层该画 %d 格(实测 %d)" % [n, want, cells.size()],
			cells.size() == want)
		if pan == null:
			continue
		var pr: Rect2 = Rect2(pan.global_position, pan.size)
		var spill: Array = []
		for c in cells:
			var r: Rect2 = Rect2((c as Control).global_position, (c as Control).size)
			if not pr.encloses(r):
				spill.append("格@(%.0f,%.0f) 跑出面板 %s" % [r.position.x, r.position.y, str(pr)])
		_chk("BAG_POPUP_ALL ★每一格都在弹层面板里(换行铺也不许伸出去): %s"
			% ("全在里面" if spill.is_empty() else str(spill.slice(0, 4))), spill.is_empty())
		## 「收起」按钮不许被格子压住 —— 压住就是点不掉这层弹层
		var closer: Button = null
		var bts: Array = []
		_collect_buttons(pan, bts)
		for b in bts:
			if str((b as Button).text) == "收起":
				closer = b
		var blocked := 0
		if closer != null:
			var cr: Rect2 = Rect2(closer.global_position, closer.size)
			for c in cells:
				if cr.intersects(Rect2((c as Control).global_position, (c as Control).size)):
					blocked += 1
		_chk("BAG_POPUP_ALL ★分母+判据: 找到「收起」按钮, 而且没有格子压住它(压住 %d 格)" % blocked,
			closer != null and blocked == 0)
		if n > cap:
			var need := "还有 %d 件" % (n - cap)
			var said := false
			for l in _labels_in(pan):
				if str((l as Label).text).find(need) >= 0:
					said = true
			_chk("BAG_POPUP_ALL ★★真放不下的时候屏上写着「%s」(静默截断才是 bug)" % need, said)
	if sc._popup != null and is_instance_valid(sc._popup):
		sc._popup.queue_free()
		await get_tree().process_frame


## 弹层里那块 820 宽的面板
func _popup_panel(sc) -> Panel:
	if sc._popup == null or not is_instance_valid(sc._popup):
		return null
	for c in (sc._popup as Node).get_children():
		if c is Panel and absf((c as Panel).size.x - 820.0) < 1.0:
			return c as Panel
	return null


## 备战席格子 = 边长恰为 BENCH_CELL 的 Panel
func _bench_cells(n: Node, out: Array) -> void:
	if n is Panel and absf((n as Panel).size.x - float(SHOP_GD.BENCH_CELL)) < 0.5 \
			and absf((n as Panel).size.y - float(SHOP_GD.BENCH_CELL)) < 0.5:
		out.append(n)
	for c in n.get_children():
		_bench_cells(c, out)


# ══════════════════════════════════════════════════════════════════════
#  MAXLEVEL_XP —— 满级后屏幕不许把「升不了了」说成「还差好多」
# ══════════════════════════════════════════════════════════════════════
## ★由来(2026-09-29 台账 ⑷, 用户当场点名): `P2.xp_to_next()` 在 level ≥ MAX_LEVEL 时
##   返回 **999999**, 它自己的注释写着「极大(不可升)」—— 那是**代码内部表示"升不了了"的约定**。
##   原样印到屏上就变成「经验 0/999999」+ 一条**空**的进度条 ⇒ 玩家读出来是"还差好多, 继续攒",
##   同一个数在两边意思**正好相反**。实测证据: 一个只看屏幕的 agent 在满级后连点了 8 下
##   那颗已经死掉的「买经验」按钮。用户原话:「10级就是满级了，怎么有agent还想着点升级」
##   「满级了那就不应该这个样子按钮误导别人啊」。
##
## ★★量的是**屏幕**不是源码; 四条各自能单独红, 每条都配一条【未满级】的分母 ——
##   否则"满级时看不到 999999"在任何情况下都成立(界面没建出来时也成立)。
##     ① 满级那一屏一个字符都不许出现哨兵值, 而未满级那一屏必须印着「经验 a/b」
##     ② 经验条填满(ratio ≥ 0.99), 而未满级 xp=0 时它是空的(≤ 0.01) —— 尺子量得出区别
##     ③ 买经验按钮 disabled **且整颗压暗**(价格是子节点, 子节点不吃 disabled, 只有 modulate 传下去)
##     ④ 就算这颗按钮被【程序】按下, 也只说一句话、不动等级/经验/币
##        (`disabled` 是"点不动", 不等于"说清了为什么")
func _check_maxlevel_xp() -> void:
	print("")
	var sentinel: int = int(P2CFG.xp_to_next(int(P2CFG.MAX_LEVEL)))
	_chk("MAXLEVEL_XP ★分母: `xp_to_next(MAX_LEVEL)` 真是个哨兵大数(实测 %d ≥ 100000)" % sentinel,
		sentinel >= 100000)
	var seen := {}
	for lv in [int(P2CFG.MAX_LEVEL) - 1, int(P2CFG.MAX_LEVEL)]:
		GameState.season_level = lv
		GameState.season_xp = 0
		GameState.meta_deepsea_coins = 999
		GameState.meta_shop_offer = []
		var sc2 = SHOP.instantiate()
		add_child(sc2)
		if sc2 is Control:
			(sc2 as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			(sc2 as Control).size = Vector2(SCREEN_W, SCREEN_H)
		for _i in range(8):
			await get_tree().process_frame
		var all2: Array = []
		_collect(sc2, all2)
		## 屏上所有文字拼起来 —— 哨兵值出现在任何一条可见文本里就算露出来了
		var joined := ""
		var xp_line := ""
		for c in all2:
			var t := ""
			if c is Label:
				t = str((c as Label).text)
			elif c is RichTextLabel:
				t = str((c as RichTextLabel).get_parsed_text())
			elif c is Button:
				t = str((c as Button).text)
			if t == "":
				continue
			joined += t + "\n"
			if t.find("经验 ") >= 0 and t.find("/") >= 0:
				xp_line = t
		## 头部那条等级经验条: 先找它自己的槽框(bar-frame 贴图, 落在头部 y<110),
		## 再拿槽里那块填充 ColorRect 的宽度 ÷ 槽内宽 = 真实填充比例。
		## ★ratio 是从**渲染出来的矩形**算的, 不是回读我传给 `_pixel_bar` 的参数。
		var slot: NinePatchRect = null
		for c in all2:
			if c is NinePatchRect and (c as NinePatchRect).texture != null \
				and str((c as NinePatchRect).texture.resource_path).find("bar-frame") >= 0 \
				and (c as Control).position.y < 110.0:
				slot = c
		var ratio := -1.0
		if slot != null:
			var inner_w: float = slot.size.x - 2.0 * float(SHOP_GD.BAR_MARGIN_X)
			## ★一律用【局部】坐标: 无头视口是方形的, `UIFrame.attach` 把内容收编进设计框
			##   再居中 ⇒ 全局 y 会整体偏 (视口高−720)/2(实测偏 280, 判据当场找不到条)。
			##   本文件其余判据也都用局部坐标, 保持同一口径。
			var sr: Rect2 = Rect2(slot.position, slot.size)
			for c in all2:
				if c is ColorRect and sr.encloses(Rect2((c as Control).position, (c as Control).size)):
					ratio = maxf(ratio, (c as Control).size.x / maxf(1.0, inner_w))
			if ratio < 0.0:
				ratio = 0.0     # 槽在、填充块一个都没有 ⇒ 空条(宽 0 的 ColorRect 不进 _collect)
		## 买经验按钮 = 头部右上那颗【无字】按钮(价格是两个子节点, 所以 text 是空串)
		var bxp: Button = null
		for c in all2:
			var gr: Rect2 = Rect2((c as Control).position, (c as Control).size)
			if c is Button and gr.position.x > SCREEN_W - 200.0 and gr.position.y < 110.0 \
				and str((c as Button).text) == "":
				bxp = c
		seen[lv] = {
			"sentinel": joined.find(str(sentinel)) >= 0,
			"ratio": ratio,
			"xp_line": xp_line,
			"slot": slot != null,
			"bxp": bxp != null,
			"disabled": bxp != null and bxp.disabled,
			"alpha": bxp.modulate.a if bxp != null else -1.0,
		}
		## ④ 死按钮被【程序】按下也得说话 —— 按钮哪天 disabled 的条件漂了, 这里就是唯一出口
		if lv == int(P2CFG.MAX_LEVEL) and bxp != null:
			var lv0: int = int(GameState.season_level)
			var xp0: int = int(GameState.season_xp)
			var coin0: int = int(GameState.meta_deepsea_coins)
			bxp.pressed.emit()
			for _i in range(4):
				await get_tree().process_frame
			var said := ""
			for c2 in _labels_in(sc2):
				if str((c2 as Label).text).find("最高等级") >= 0:
					said = str((c2 as Label).text)
			_chk("MAXLEVEL_XP ④ 满级时按下买经验: 等级/经验/币一个没动(%d/%d/%d → %d/%d/%d), 且屏上给了一句话「%s」"
				% [lv0, xp0, coin0, int(GameState.season_level), int(GameState.season_xp),
				   int(GameState.meta_deepsea_coins), said],
				int(GameState.season_level) == lv0 and int(GameState.season_xp) == xp0
				and int(GameState.meta_deepsea_coins) == coin0 and said != "")
		sc2.queue_free()
		await get_tree().process_frame
	var mx: Dictionary = seen[int(P2CFG.MAX_LEVEL)]
	var sub: Dictionary = seen[int(P2CFG.MAX_LEVEL) - 1]
	print("     满级(Lv%d): 哨兵露出=%s 条填充=%.3f disabled=%s 整颗alpha=%.2f 经验行「%s」"
		% [int(P2CFG.MAX_LEVEL), str(mx["sentinel"]), float(mx["ratio"]), str(mx["disabled"]),
		   float(mx["alpha"]), str(mx["xp_line"])])
	print("     未满级(Lv%d): 哨兵露出=%s 条填充=%.3f disabled=%s 整颗alpha=%.2f 经验行「%s」"
		% [int(P2CFG.MAX_LEVEL) - 1, str(sub["sentinel"]), float(sub["ratio"]), str(sub["disabled"]),
		   float(sub["alpha"]), str(sub["xp_line"])])
	_chk("MAXLEVEL_XP ★分母: 两态的头部经验条都真的建出来了, 买经验按钮也都在场",
		bool(mx["slot"]) and bool(sub["slot"]) and bool(mx["bxp"]) and bool(sub["bxp"]))
	_chk("MAXLEVEL_XP ★分母: 未满级那一屏确实印着「经验 a/b」(否则 ① 是空检查) —— 「%s」"
		% str(sub["xp_line"]), str(sub["xp_line"]) != "")
	_chk("MAXLEVEL_XP ① 满级那一屏一个字符都没露出哨兵值 %d" % sentinel, not bool(mx["sentinel"]))
	_chk("MAXLEVEL_XP ① 未满级那一屏也没露哨兵(它的分母是真实数 %d)"
		% int(P2CFG.xp_to_next(int(P2CFG.MAX_LEVEL) - 1)), not bool(sub["sentinel"]))
	_chk("MAXLEVEL_XP ② 满级时经验条是【满的】(实测 %.3f ≥ 0.99)" % float(mx["ratio"]),
		float(mx["ratio"]) >= 0.99)
	_chk("MAXLEVEL_XP ② ★分母: 未满级 xp=0 时它是【空的】(实测 %.3f ≤ 0.01) —— 这把尺子量得出区别"
		% float(sub["ratio"]), float(sub["ratio"]) <= 0.01)
	_chk("MAXLEVEL_XP ③ 满级时买经验按钮 disabled=true 且整颗压暗(alpha %.2f < 0.6)"
		% float(mx["alpha"]), bool(mx["disabled"]) and float(mx["alpha"]) < 0.6)
	_chk("MAXLEVEL_XP ③ ★分母: 未满级时它是亮的、能点(disabled=%s alpha=%.2f)"
		% [str(sub["disabled"]), float(sub["alpha"])],
		not bool(sub["disabled"]) and float(sub["alpha"]) > 0.95)


# ══════════════════════════════════════════════════════════════════════
#  BUY_FEEDBACK —— 不成交要说为什么, 成交要看得见
# ══════════════════════════════════════════════════════════════════════
## ★由来(2026-09-29 台账 ⑮): 「商店买不起是一句 `return`，零反馈；买成功的唯一反馈是
##   `_rebuild()` 整屏重画(卡凭空消失、钱数变一下)」。
##   探针实测三条路**全部** `_toast_node = <null>`: `_on_buy` 买不起 / `_on_buy` 成交 /
##   `_on_refresh` 币不够。而「换一批」那颗按钮在 coins=0 时 `disabled=false` ——
##   点得下去、什么也不发生, 与满级那颗死按钮**同一个形状**。
##
## ★★两样一起量:【屏幕上多出来的那句话】+【状态有没有真的变】。
##   只看提示会被"提示出来了但钱没扣"骗过去; 只看状态会把"零反馈"判成通过。
## ★顺序是**按币量从少到多**排的: 换一批(要 0~1 币) → 买不起(price-1) → 成交(price+50)。
##   顺序反了"买不起"那两条就变成空检查(钱够了当然买得起)。
func _check_buy_feedback() -> void:
	print("")
	GameState.season_level = 5
	GameState.persistent_bench = []
	GameState.persistent_equipped = {}
	GameState.meta_shop_offer = []
	GameState.meta_deepsea_coins = 0
	var sc3 = SHOP.instantiate()
	add_child(sc3)
	if sc3 is Control:
		(sc3 as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc3 as Control).size = Vector2(SCREEN_W, SCREEN_H)
	for _i in range(8):
		await get_tree().process_frame
	var offer: Array = sc3._offer
	var first := -1
	for i in range(offer.size()):
		if offer[i] != null:
			first = i
			break
	_chk("BUY_FEEDBACK ★分母: 货架真的摆出了货(%d 格, 第一件在 #%d)" % [offer.size(), first],
		first >= 0)
	if first < 0:
		sc3.queue_free()
		await get_tree().process_frame
		return
	var edef3: Dictionary = sc3._deco(offer[first])
	var price: int = int(sc3._price(edef3))
	var nm: String = str(edef3.get("name", ""))

	# ── ① 换一批买不起: 按钮长得像死的 + 点了说为什么 + 货架一件没换 ──
	var rf: Button = null
	var bts: Array = []
	_collect_buttons(sc3, bts)
	for b in bts:
		if str((b as Button).text).find("换一批") >= 0:
			rf = b
	var before_ids: Array = []
	for it in sc3._offer:
		before_ids.append("" if it == null else str((it as Dictionary).get("id", "")))
	sc3._on_refresh()
	for _i in range(4):
		await get_tree().process_frame
	var msg2 := ""
	for l in _labels_in(sc3):
		if str((l as Label).text).find("换一批要") >= 0:
			msg2 = str((l as Label).text)
	var after_ids: Array = []
	for it in sc3._offer:
		after_ids.append("" if it == null else str((it as Dictionary).get("id", "")))
	print("     换一批买不起(币 0): 按钮 disabled=%s alpha=%.2f 屏上「%s」 货架变了=%s"
		% [str(rf != null and rf.disabled), rf.modulate.a if rf != null else -1.0, msg2,
		   str(before_ids != after_ids)])
	_chk("BUY_FEEDBACK ① ★分母: 找到「换一批」按钮", rf != null)
	_chk("BUY_FEEDBACK ① 币不够时「换一批」disabled 且整颗压暗(价钱那枚币图标是子节点, 不吃 disabled)",
		rf != null and rf.disabled and rf.modulate.a < 0.6)
	_chk("BUY_FEEDBACK ① 点它 → 屏上说清换一批要多少钱(「%s」里含 %d)" % [msg2, int(SHOP_GD.REFRESH_COST)],
		msg2 != "" and msg2.find(str(int(SHOP_GD.REFRESH_COST))) >= 0)
	_chk("BUY_FEEDBACK ① ★分母: 货架一件没换(不成交就不许偷偷重掷)", before_ids == after_ids)

	# ── ② 买不起: 说清【差多少】, 且一分钱不扣、一件不进背包 ──
	## ★币故意给成 price-1 而不是 0: 差额 1 ≠ 售价 price ⇒ 那句话里写的到底是
	##   "还差多少"还是"标价多少"分得清。给 0 的话两个数相等, 判据分不出来。
	GameState.meta_deepsea_coins = maxi(0, price - 1)
	sc3._rebuild()
	for _i in range(6):
		await get_tree().process_frame
	var coin0: int = int(GameState.meta_deepsea_coins)
	var bench0: int = GameState.persistent_bench.size()
	var gap0: int = price - coin0
	sc3._on_buy(first)
	for _i in range(4):
		await get_tree().process_frame
	var msg1 := ""
	for l in _labels_in(sc3):
		if str((l as Label).text).find("还差") >= 0:
			msg1 = str((l as Label).text)
	print("     买不起(币 %d / 价 %d, 差 %d): 屏上「%s」 币 %d→%d 背包 %d→%d"
		% [coin0, price, gap0, msg1, coin0, int(GameState.meta_deepsea_coins),
		   bench0, GameState.persistent_bench.size()])
	_chk("BUY_FEEDBACK ② 买不起 → 屏上写着「还差 %d 枚深海币」(不是只把按钮变灰)" % gap0,
		msg1.find("还差 %d 枚深海币" % gap0) >= 0)
	_chk("BUY_FEEDBACK ② ★分母: 买不起时钱和背包一个都没动(%d→%d / %d→%d)"
		% [coin0, int(GameState.meta_deepsea_coins), bench0, GameState.persistent_bench.size()],
		int(GameState.meta_deepsea_coins) == coin0
		and GameState.persistent_bench.size() == bench0)

	# ── ③ 成交: 屏上看得见买到了什么 + 背包真多一件 + 钱真扣了 + 提示活过整屏重画 ──
	GameState.meta_deepsea_coins = price + 50
	sc3._rebuild()
	for _i in range(6):
		await get_tree().process_frame
	var coin1: int = int(GameState.meta_deepsea_coins)
	var bench1: int = GameState.persistent_bench.size()
	sc3._on_buy(first)
	for _i in range(6):
		await get_tree().process_frame
	var msg3 := ""
	for l in _labels_in(sc3):
		if str((l as Label).text).find("买下") >= 0:
			msg3 = str((l as Label).text)
	print("     成交(价 %d): 屏上「%s」 币 %d→%d 背包 %d→%d"
		% [price, msg3, coin1, int(GameState.meta_deepsea_coins), bench1,
		   GameState.persistent_bench.size()])
	_chk("BUY_FEEDBACK ③ 成交 → 屏上一句话写出买到的是哪一件(「%s」里含「%s」)" % [msg3, nm],
		msg3 != "" and msg3.find(nm) >= 0)
	_chk("BUY_FEEDBACK ③ ★分母: 成交真的发生了(背包 %d→%d, 币 %d→%d)"
		% [bench1, GameState.persistent_bench.size(), coin1, int(GameState.meta_deepsea_coins)],
		GameState.persistent_bench.size() == bench1 + 1
		and int(GameState.meta_deepsea_coins) == coin1 - price)
	## ★★成交的提示必须**活过那一次 `_rebuild()`** —— 商店 `_rebuild()` 开头把所有子节点
	##   `queue_free()`, 提示若在重画【之前】发就当场被清掉(背包页 7 条 toast 一条看不见,
	##   根因一模一样)。这一条量的正是"它还在树上"。
	_chk("BUY_FEEDBACK ③ ★提示活过了那次整屏重画(不是发出来就被 _rebuild 清掉)",
		sc3._toast_node != null and is_instance_valid(sc3._toast_node)
		and (sc3._toast_node as Node).is_inside_tree())

	# ── ④ 提示不许盖住任何按钮 + 不许伸出 720 ──
	## ★由来: 提示原来摆在 y 430..474, 而「换一批」按钮就在 448..524 ——
	##   一句"深海币不够 · 换一批要 2"**盖住它解释的那颗按钮的上沿 26px**。
	##   提示越常出现, 这条越要紧, 所以焊住。(弹层 z=20 被压住是故意的, 不算。)
	if sc3._toast_node != null and is_instance_valid(sc3._toast_node):
		var tr: Rect2 = Rect2((sc3._toast_node as Control).position, (sc3._toast_node as Control).size)
		var covered: Array = []
		var bts2: Array = []
		_collect_buttons(sc3, bts2)
		for b in bts2:
			var brr: Rect2 = Rect2((b as Control).position, (b as Control).size)
			if tr.intersects(brr):
				covered.append("「%s」%s" % [str((b as Button).text).substr(0, 10), str(brr)])
		print("     提示矩形 %s ; 扫了 %d 颗按钮, 被盖住 %d 颗" % [str(tr), bts2.size(), covered.size()])
		_chk("BUY_FEEDBACK ④ ★分母: 这一屏真的有按钮可盖(扫到 %d 颗)" % bts2.size(), bts2.size() >= 4)
		_chk("BUY_FEEDBACK ④ 提示一颗按钮都没盖住: %s"
			% ("干净" if covered.is_empty() else str(covered.slice(0, 3))), covered.is_empty())
		_chk("BUY_FEEDBACK ④ 提示整条都在 %.0f 设计框内(底沿 %.0f)" % [SCREEN_H, tr.end.y],
			tr.end.y <= SCREEN_H + 0.5 and tr.position.y >= -0.5)
	sc3.queue_free()
	await get_tree().process_frame
