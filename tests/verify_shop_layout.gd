extends Node
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
const DESC_H := 214.0
const DESC_FONT := 18

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
	if OS.get_environment("SHOP_FULLBENCH") != "":
		var bench: Array = []
		for i in range(14):
			bench.append({"id": "p2eq_001", "star": 1})
		gs.persistent_bench = bench

	print("=== 商店版式体检 (%.0f×%.0f) ===" % [SCREEN_W, SCREEN_H])
	var sc = SHOP.instantiate()
	add_child(sc)
	# ★无头视口是【方形】的(memory: fb-test-window-right-middle) —— 根 Control 用 PRESET_FULL_RECT
	#   会跟着它变成 1280×1280, 于是背景板被误报"越界"。强制按真机口径 1280×720 量。
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(SCREEN_W, SCREEN_H)
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
	print("  ⑥ 描述容纳体检: 框 %.0f×%.0f / 字号 %d / 装备 %d 件 (★分母)" % [DESC_W, DESC_H, DESC_FONT, eqs.size()])
	if eqs.is_empty():
		print("  [FAIL] 取不到装备表 —— 本条是空检查"); _fail += 1
	else:
		var probe := RichTextLabel.new()
		probe.bbcode_enabled = true
		probe.add_theme_font_size_override("normal_font_size", DESC_FONT)
		probe.size = Vector2(DESC_W, DESC_H)
		add_child(probe)
		var over: Array = []
		var worst := 0.0
		var worst_nm := ""
		for e in eqs:
			var ed: Dictionary = e if e is Dictionary else {}
			var raw := str(ed.get("effectDesc1", ""))
			if raw == "":
				continue
			probe.text = raw
			await get_tree().process_frame
			var ch: float = probe.get_content_height()
			if ch > worst:
				worst = ch; worst_nm = str(ed.get("name", ed.get("id", "?")))
			if ch > DESC_H + 0.5:
				over.append("%s 需 %.0fpx" % [str(ed.get("name", "?")), ch])
		print("     一屏放得下: %d / %d 件   最高的是「%s」需 %.0fpx (框 %.0f)" % [
			eqs.size() - over.size(), eqs.size(), worst_nm, worst, DESC_H])
		for o in over.slice(0, 6):
			print("       ↕需滚动: " + o)
		if over.size() > 6:
			print("       …另有 %d 件需滚动" % (over.size() - 6))
		probe.queue_free()
		_chk("⑥ 没有描述超出框高 ×3 (超了滚起来太痛苦)", worst <= DESC_H * 3.0)

	# ── ⑤ 分母自检: 至少要有按钮, 否则第②条是空检查 ──
	var nbtn := 0
	for c in all:
		if c is Button:
			nbtn += 1
	print("  按钮数 = %d" % nbtn)
	_chk("⑤ ★分母: 按钮数 > 0 (0 个 = 第②条是空检查)", nbtn > 0)

	_done(sc)


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


func _done(sc) -> void:
	sc.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 商店版式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
