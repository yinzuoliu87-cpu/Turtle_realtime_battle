extends Node
## _probe_uiaudit.gd — 全屏 UI 问题总清点(2026-08-18, 只量不判)
##
## 由来: 用户「那到底还有哪些问题呢, 怎么这么多没想到的呢」——
## 我一直是被问一次查一块。这个探针把今晚零散建起来的**全部判据**一次铺到所有屏幕,
## 一次性给出完整清单, 而不是继续挤牙膏。
##
## 十条判据(每条都在战斗面板上验过、且都反向验证过会红):
##   1 网页盒   StyleBoxFlat 四边有边框 + 底半透明  = CSS border+rgba 的长相
##   2 圆角盒   corner_radius > 0
##   3 九宫格   挂了几种金属贴图(越多越统一)
##   4 默认皮   Button 非 flat 非 TextureButton 且无 normal 覆盖
##   5 死点击   BaseButton 或接了 gui_input, 却是 MOUSE_FILTER_IGNORE
##   6 热区     短边 < 81px(44pt) 且 长边 < 200px(排除整行/整列)
##   7 字号档   面板里可见 Label 的不同 font_size 数(一档 = 一种角色)
##   8 截断     clip_text 且真实字宽 > 真实矩形宽
##   9 挤没     有字(≥2)但宽或高 < 6px
##  10 压扁     NinePatchRect 边距和 ≥ 实际尺寸(中段是负的, 框画不出来)

const SCENES: Array = [
	["res://scenes/MainMenu.tscn", ""],
	["res://scenes/Inventory.tscn", "res://tests/_setup_inv_demo.gd"],
	["res://scenes/Codex.tscn", ""],
	["res://scenes/TeamSelect.tscn", ""],
	["res://scenes/Shop.tscn", ""],
	["res://scenes/Settings.tscn", ""],
	["res://scenes/Record.tscn", ""],
]
const TOUCH_MIN := 81.0

var _band_cache: Dictionary = {}


## 量【贴图里真实画出来的边带有多厚】—— 不用九宫格配置的边距。
##
## ★为什么: 配置边距是"从哪里切开去拉伸", 不是"画了多宽的边"。实测两者差一倍:
##     panel-frame 配置 20 ⇒ 真实边带 左 9 / 上 13
##     slot-frame  配置 12 ⇒ 真实边带 6 / 6
##     chip-frame  配置  7 ⇒ 真实边带 4 / 2
##   拿配置值当尺子会**高估碰撞**, 把本来没压到的文字也报出来(判据太宽, 今晚第 6 次)。
## ★量法: 从贴图正中往外扫, 颜色第一次明显偏离"中心那片平底色"的地方 = 边带内沿。
##   (反过来从外往内扫是错的 —— 最外圈的深色描边和内场底色很接近, 一扫就停, 量出 1px。)
func _band_of(tex: Texture2D) -> float:
	var key := tex.resource_path
	if _band_cache.has(key):
		return float(_band_cache[key])
	var img := tex.get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var ctr := img.get_pixel(cx, cy)
	var bl := 0
	var bt := 0
	if ctr.a < 0.04:
		# 【空心框】中间是透明的(卡框类贴图都是这样)。此时"从中心往外扫"第一步就撞上
		#   透明像素、直接返回半个贴图宽 —— 实测 card-frame-t1 72x72 报 36px, 荒唐。
		#   空心框要**从外往内扫**: 边带 = 从边缘算起、连续不透明的那一段。
		for x in range(0, cx):
			if img.get_pixel(x, cy).a < 0.04:
				if x > 0:
					bl = x
					break
			elif x == cx - 1:
				bl = cx
		for y in range(0, cy):
			if img.get_pixel(cx, y).a < 0.04:
				if y > 0:
					bt = y
					break
			elif y == cy - 1:
				bt = cy
	else:
		for x in range(cx, 0, -1):
			var c := img.get_pixel(x, cy)
			if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)), absf(c.b - ctr.b)) > 0.12:
				bl = x
				break
		for y in range(cy, 0, -1):
			var c2 := img.get_pixel(cx, y)
			if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)), absf(c2.b - ctr.b)) > 0.12:
				bt = y
				break
	var band := float(maxi(bl, bt))
	_band_cache[key] = band
	print("      [边带] %-22s %dx%d ⇒ %.0f px" % [key.get_file(), img.get_width(), img.get_height(), band])
	return band


## 【真正画出来的那块字】的矩形 —— 不是 Label 控件的矩形。
##
## ★由来: 判据 13 报「精英小将」压边带 13px, 可实拍里那行字**稳稳在行中间**。
##   原因是列表行的 Label `size.y = 52`(占满整行)配 `VERTICAL_ALIGNMENT_CENTER` ——
##   控件矩形上下都伸进边带, 但**画出来的字只有 20px 高、居中**, 根本没碰到。
##   拿控件矩形当尺子 = 量了个空盒子。**尺子要匹配被测概念**(memory: 3D 水准线那条)。
func _ink_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	if f == null:
		return r
	var fs: int = l.get_theme_font_size("font_size")
	var ts: Vector2 = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		ts.x = minf(ts.x, r.size.x)
		ts.y = float(maxi(l.get_visible_line_count(), 1)) * f.get_height(fs)
	var w: float = minf(ts.x, r.size.x)
	var h: float = minf(ts.y, r.size.y)
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER: x = r.position.x + (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT: x = r.position.x + (r.size.x - w)
	var y := r.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER: y = r.position.y + (r.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM: y = r.position.y + (r.size.y - h)
	return Rect2(x, y, w, h)


func _audit(root: Node) -> Dictionary:
	var d := {"web": 0, "round": 0, "tex": {}, "stock": [], "dead": [], "small": [],
		"fonts": {}, "clip": [], "squash": [], "flat9": [], "spill": [], "overlap": [], "onframe": []}
	## 【第 11 条·文字溢出卡框】几何判据, 不看父子关系。
	## ★由来: 图鉴技能卡实拍, 「过肩摔」那张的正文**穿出卡框底边**继续往下写。
	##   前十条判据一条都逮不到它 —— 它们查的是"盒子长什么样", 没有一条查"内容装不装得下"。
	##   而这一屏是**绝对定位**(卡片和文字是兄弟节点), 所以不能用 `get_parent()`,
	##   只能量真实矩形: 文字**从卡里开始**却**在卡外结束** = 溢出。
	var cards: Array = []
	var labels: Array = []
	var raw_labels: Array = []
	var framed: Array = []   # [矩形, 边距] —— 挂了九宫格贴图的盒子
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is NinePatchRect and (n as Control).is_visible_in_tree():
			var np := n as NinePatchRect
			if np.texture != null:
				d["tex"][np.texture.resource_path.get_file()] = true
				var mv: float = np.patch_margin_top + np.patch_margin_bottom
				var mh: float = np.patch_margin_left + np.patch_margin_right
				if np.size.y > 0.0 and (np.size.y <= mv or np.size.x <= mh):
					(d["flat9"] as Array).append("%.0fx%.0f/边距%.0f,%.0f" % [np.size.x, np.size.y, mh, mv])
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			if (c is Panel or c is PanelContainer or c is NinePatchRect) 					and c.size.x >= 60.0 and c.size.y >= 40.0:
				cards.append(c.get_global_rect())
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				var _np2 := n as NinePatchRect
				framed.append([c.get_global_rect(), _band_of(_np2.texture)])
			if n is Label and str((n as Label).text).strip_edges().length() >= 4:
				labels.append([_ink_rect(n as Label), str((n as Label).text)])
				raw_labels.append(n as Label)
			for slot in ["panel", "normal", "background", "fill"]:
				if not c.has_theme_stylebox_override(slot):
					continue
				var sb = c.get_theme_stylebox(slot)
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					d["tex"][(sb as StyleBoxTexture).texture.resource_path.get_file()] = true
					var _st2 := sb as StyleBoxTexture
					framed.append([c.get_global_rect(), _band_of(_st2.texture)])
				elif sb is StyleBoxFlat:
					var f := sb as StyleBoxFlat
					if f.corner_radius_top_left > 0:
						d["round"] += 1
					if f.border_width_top > 0 and f.border_width_bottom > 0 \
							and f.border_width_left > 0 and f.border_width_right > 0 \
							and f.bg_color.a < 0.95:
						d["web"] += 1
			var is_btn: bool = c is BaseButton
			var wired: bool = c.gui_input.get_connections().size() > 0
			if c is Button and not (c as Button).flat and not c.has_theme_stylebox_override("normal"):
				(d["stock"] as Array).append(str((c as Button).text).substr(0, 10))
			if (is_btn or wired) and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				(d["dead"] as Array).append(c.name)
			if (is_btn or wired) and c.size.x > 1.0 and c.size.y > 1.0 \
					and minf(c.size.x, c.size.y) < TOUCH_MIN and maxf(c.size.x, c.size.y) < 200.0:
				(d["small"] as Array).append("%.0fx%.0f" % [c.size.x, c.size.y])
			if n is Label:
				var lb := n as Label
				var tx := str(lb.text).strip_edges()
				if tx.length() >= 2:
					var fs: int = lb.get_theme_font_size("font_size")
					d["fonts"][fs] = int(d["fonts"].get(fs, 0)) + 1
					if lb.size.x < 6.0 or lb.size.y < 6.0:
						(d["squash"] as Array).append("「%s」" % tx.substr(0, 10))
					if lb.clip_text and lb.autowrap_mode == TextServer.AUTOWRAP_OFF and lb.size.x > 1.0:
						var fnt: Font = lb.get_theme_font("font")
						if fnt != null and fnt.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > lb.size.x + 0.5:
							(d["clip"] as Array).append("「%s」" % tx.substr(0, 10))
		for ch in n.get_children():
			st.append(ch)
	# ★第一版判据错了(几何法): 拿"文字矩形 vs 卡片矩形"比, 报 0 —— 而实拍里
	#   图鉴「过肩摔」的正文明明穿出卡框。原因是**溢出的是 Label 自己的矩形**:
	#   Godot 的 Label 在 autowrap 下, 行数超过高度时**照样往框外画**(除非 clip_text)。
	#   卡片矩形完全没被越过, 几何法自然什么都看不见。
	#   ⇒ 改用 Label 自带的两个计数, 它量的就是"要几行 / 装得下几行", 一比就知道。
	# 【第 12 条·两段文字压在一起】
	# ★由来: 图鉴技能卡实拍放大 3 倍才看清 —— 正文没穿出卡框(所以第 11 条报 0 是对的),
	#   真正的毛病是**「点开看全部」压在正文最后一行上**, 两行字叠成一团。
	#   我第一眼把它读成"文字溢出", 是**眯着眼看小图**得出的结论 —— 又一次。
	#   ⇒ 判据: 两个可见 Label 的真实矩形相交面积 > 较小者的 25%。
	for i2 in range(labels.size()):
		for j2 in range(i2 + 1, labels.size()):
			var ra: Rect2 = labels[i2][0]
			var rb: Rect2 = labels[j2][0]
			var inter: Rect2 = ra.intersection(rb)
			if inter.size.x <= 0.0 or inter.size.y <= 0.0:
				continue
			var amin: float = minf(ra.size.x * ra.size.y, rb.size.x * rb.size.y)
			if amin <= 0.0:
				continue
			# ⚠ 第一版在主菜单报 20 条, 全是「🐢 训龟大师」压自己 —— 那是**用多份同文字
			#   标签做描边/阴影**的常规手法, 不是 bug。同文字的一律跳过。
			if str(labels[i2][1]) == str(labels[j2][1]):
				continue
			if (inter.size.x * inter.size.y) / amin > 0.25:
				(d["overlap"] as Array).append("「%s」压「%s」" % [
					str(labels[i2][1]).substr(0, 6), str(labels[j2][1]).substr(0, 6)])
	# 【第 13 条·文字压在框的边带上】—— 这一条是**我自己的改动催生的**。
	# ★由来: 图鉴「点开看全部」实拍压在卡框下边带 + 铆钉上; 选龟龟卡的名字行被底部
	#   两颗铆钉夹住。原来边框只有 2px 细线, 换成金属九宫格后边带有了**真实厚度**,
	#   贴着边缘摆的文字就撞上去了。**换框不是换个花纹, 是内容区变小了。**
	# ⇒ 判据: 文字中心落在某个「有框盒子」内, 但文字矩形越出了【框内缩后的内容区】。
	#   取包含它的**最小**框(卡在面板里时算卡, 不算外层面板)。
	for k3 in range(labels.size()):
		var lr3: Rect2 = labels[k3][0]
		var c3 := lr3.position + lr3.size * 0.5
		var best := -1
		var best_a := 1e18
		for f3 in range(framed.size()):
			var fr: Rect2 = framed[f3][0]
			if not fr.has_point(c3):
				continue
			var ar: float = fr.size.x * fr.size.y
			if ar < best_a:
				best_a = ar
				best = f3
		if best < 0:
			continue
		var fr2: Rect2 = framed[best][0]
		# ⚠ 判据太宽第 7 次: 商店报「← 点货架卡片看」压边带 123px —— 那是一条横跨整屏的
		#   提示条, 它的**中心**恰好落进某个小卡框里, 于是被判成"那张卡的内容"。
		#   加包含度门槛: 文字必须主要待在这个框里(交叠 ≥ 文字面积的 60%)才算它的内容。
		var inter2: Rect2 = fr2.intersection(lr3)
		var la: float = lr3.size.x * lr3.size.y
		if la <= 0.0 or inter2.size.x <= 0.0 or inter2.size.y <= 0.0:
			continue
		if (inter2.size.x * inter2.size.y) / la < 0.60:
			continue
		var m3: float = float(framed[best][1])
		var inner := Rect2(fr2.position + Vector2(m3, m3), fr2.size - Vector2(m3, m3) * 2.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		var over := maxf(maxf(inner.position.y - lr3.position.y,
			(lr3.position.y + lr3.size.y) - (inner.position.y + inner.size.y)),
			maxf(inner.position.x - lr3.position.x,
			(lr3.position.x + lr3.size.x) - (inner.position.x + inner.size.x)))
		if over > 2.0:
			(d["onframe"] as Array).append("「%s」压边带 %.0fpx" % [str(labels[k3][1]).substr(0, 8), over])
	for lb2 in raw_labels:
		var L: Label = lb2
		var need: int = L.get_line_count()
		var fit: int = L.get_visible_line_count()
		if need > fit:
			(d["spill"] as Array).append("「%s」%d行只装下%d行%s" % [
				str(L.text).substr(0, 8), need, fit, "(被裁)" if L.clip_text else "(画到框外)"])
	return d


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 全屏 UI 问题总清点 ===")
	print("%-13s%5s%5s%5s%5s%5s%5s%5s%5s%5s%5s%5s%5s%6s" % [
		"屏", "网页", "圆角", "贴图", "默认皮", "死点", "热区", "字号", "截断", "挤没", "压扁", "溢出", "压字", "压边带"])
	var tot := {"web": 0, "round": 0, "stock": 0, "dead": 0, "small": 0, "clip": 0, "squash": 0, "flat9": 0, "spill": 0, "overlap": 0, "onframe": 0}
	for row in SCENES:
		var path: String = str(row[0])
		if not ResourceLoader.exists(path):
			continue
		var setup: String = str(row[1])
		if setup != "" and ResourceLoader.exists(setup):
			var sc = load(setup)
			if sc != null and sc.has_method("run"):
				sc.run()
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(14):
			await get_tree().process_frame
		var d := _audit(inst)
		print("%-13s%5d%5d%5d%5d%5d%5d%5d%5d%5d%5d%5d%5d%6d" % [
			path.get_file().replace(".tscn", ""), d["web"], d["round"], (d["tex"] as Dictionary).size(),
			(d["stock"] as Array).size(), (d["dead"] as Array).size(), (d["small"] as Array).size(),
			(d["fonts"] as Dictionary).size(), (d["clip"] as Array).size(),
			(d["squash"] as Array).size(), (d["flat9"] as Array).size(), (d["spill"] as Array).size(), (d["overlap"] as Array).size(), (d["onframe"] as Array).size()])
		for k in ["web", "round", "stock", "dead", "small", "clip", "squash", "flat9", "spill", "overlap", "onframe"]:
			var v = d[k]
			tot[k] += (v if typeof(v) == TYPE_INT else (v as Array).size())
		for k2 in ["stock", "dead", "clip", "squash", "flat9", "spill", "overlap", "onframe"]:
			if not (d[k2] as Array).is_empty():
				print("      %-6s %s" % [k2, str((d[k2] as Array).slice(0, 5))])
		print("      [分母] 卡片矩形 %d · 长标签 %d" % [int(d.get("_nc", 0)), int(d.get("_nl", 0))])
		var fk: Array = (d["fonts"] as Dictionary).keys()
		fk.sort()
		if fk.size() > 5:
			print("      字号档 %d 档: %s" % [fk.size(), str(fk)])
		inst.queue_free()
		await get_tree().process_frame
	print("────────────────────────────────────────")
	print("合计 网页盒 %d · 圆角盒 %d · 默认皮 %d · 死点击 %d · 热区不足 %d · 截断 %d · 挤没 %d · 压扁 %d · 文字溢出 %d · 压字 %d · 压边带 %d"
		% [tot["web"], tot["round"], tot["stock"], tot["dead"], tot["small"], tot["clip"], tot["squash"], tot["flat9"], tot["spill"], tot["overlap"], tot["onframe"]])
	print("PROBE DONE")
	get_tree().quit(0)
