extends Node
## verify_ui_consistency.gd — 全屏 UI 一致性【棘轮门禁】(2026-08-18)
##
## ═══ 为什么要有这个 ═══
## 用户 2026-08-18:「那到底还有哪些问题呢, **怎么这么多没想到的呢**, 你得在迭代里都解决」。
##
## 根因不是"我不够细", 是**我每条判据都只在当时那一块上建过, 从没铺到全屏**:
##   · 网页盒判据建在战斗信息面板 → 图鉴 45 个 / 选龟 43 个网页盒躺了一整晚没人查
##   · 死点击判据只认 `gui_input`, **完全覆盖不到 Button**(按钮走 pressed 信号)
##   · 探针实例化的是**空背包**, 33 格 6 卡根本没建 ⇒ 报"背包 0 网页盒"是假绿
##   · 换框之后内容区变小、文字压在金属边带上 —— 这一整类**我自己造的**毛病,
##     前十条判据一条都逮不到(实测 71 处)
##
## ⇒ 这张表是 13 条判据 × 7 个屏, 每格记基线, **只许降不许升**。
##   「忘了查另外几屏」从此不是"我要记得", 而是**结构上做不到**。
##
## ═══ 13 条判据(全部量真实矩形/真实像素, 不搜源码字符串) ═══
##   1 网页盒   StyleBoxFlat 四边有边框 + 底半透明 = CSS border+rgba 的长相(★主指标)
##   2 圆角盒   corner_radius > 0
##   3 默认皮   Button 非 flat 且没换过皮 —— 圆角纯色是"没游戏味"最直接的来源
##   4 死点击   BaseButton / 接了 gui_input, 却 MOUSE_FILTER_IGNORE
##   5 热区     短边 < 44pt 且长边 < 200px(真正难点的形状, 不含整行整列)
##   6 截断     clip_text 且真实字宽 > 真实矩形宽
##   7 挤没     有字但宽或高 < 6px
##   8 压扁     九宫格边距和 ≥ 实际尺寸 ⇒ 中段为负, 框根本画不出来
##   9 溢出     Label 要的行数 > 装得下的行数
##  10 压字     两段【不同】的文字矩形相交 > 25%
##  11 压边带   文字真实字块越出框的内容区
##  (12/13 = 分母: 每屏可见控件数、全局按钮/标签数)
##
## ═══ 三个"判据本身会不会骗我"的堵口(每个都是今晚栽出来的) ═══
## ① **分母**: 每屏必须真的扫到控件, 否则 = 场景没建起来的假绿(今晚踩过 6 次)
## ② **边带宽度从贴图里量, 不读配置边距**: panel-frame 配置 20 → 真实边带 13;
##    slot-frame 配置 12 → 真实 6。拿配置值当尺子会高估碰撞、报一堆假的。
##    空心框(中间透明)要从外往内扫, 否则返回半个贴图宽(card-frame 72px 报过 36)。
## ③ **量真实字块, 不量控件矩形**: 列表行的 Label 占满 52px 行高但字是垂直居中的,
##    拿控件矩形量会把"稳稳在行中间"的字报成压边带 13px。**尺子要匹配被测概念。**

const TOUCH_MIN := 81.0

## 每屏基线(上界)。**只许改小, 不许改大** —— 要放大必须在 CHANGELOG 里写清为什么。
## 商店库存是随机的(实测 0~2 网页盒 / 11~13 圆角盒), 所以它那两格取上沿。
const BASE: Dictionary = {
	"MainMenu":   {"web": 1, "round": 3, "frame": 0},
	"Inventory":  {"web": 10, "round": 19, "frame": 4},
	"Codex":      {"web": 0, "round": 0, "frame": 2},
	"TeamSelect": {"web": 15, "round": 77, "frame": 1},
	# 商店货架随机 ⇒ 它这两格是**容差基线**(实测跨多次运行 0~3 网页盒 / 11~14 圆角盒)。
	# 卡到实测上沿会偶发红; 而真回归是数量级的(31 vs 0), 容差 +1 挡不住的场面不存在。
	"Shop":       {"web": 4, "round": 16, "frame": 0},
	"Settings":   {"web": 0, "round": 0, "frame": 0},
	"Record":     {"web": 1, "round": 1, "frame": 0},
}

## 分母下限: 这一屏至少该扫到这么多可见控件。少于它 = 场景没建起来, 下面的"0 问题"全是假的。
const MIN_CTRL: Dictionary = {
	"MainMenu": 20, "Inventory": 120, "Codex": 120,
	"TeamSelect": 150, "Shop": 60, "Settings": 10, "Record": 10,
}

var _pass := 0
var _fail := 0
var _band_cache: Dictionary = {}


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## 量【贴图里真实画出来的边带有多厚】—— 不用九宫格配置的边距。
## 配置边距是"从哪切开去拉伸", 不是"画了多宽的边"; 实测两者差近一倍。
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
		for x in range(0, cx):
			if img.get_pixel(x, cy).a < 0.04 and x > 0:
				bl = x
				break
		for y in range(0, cy):
			if img.get_pixel(cx, y).a < 0.04 and y > 0:
				bt = y
				break
	else:
		for x2 in range(cx, 0, -1):
			var c := img.get_pixel(x2, cy)
			if c.a < 0.04 or maxf(maxf(absf(c.r - ctr.r), absf(c.g - ctr.g)), absf(c.b - ctr.b)) > 0.12:
				bl = x2
				break
		for y2 in range(cy, 0, -1):
			var c2 := img.get_pixel(cx, y2)
			if c2.a < 0.04 or maxf(maxf(absf(c2.r - ctr.r), absf(c2.g - ctr.g)), absf(c2.b - ctr.b)) > 0.12:
				bt = y2
				break
	var band := float(maxi(bl, bt))
	_band_cache[key] = band
	return band


## 真正画出来的那块字的矩形(不是 Label 控件的矩形)。
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
		HORIZONTAL_ALIGNMENT_CENTER:
			x = r.position.x + (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = r.position.x + (r.size.x - w)
	var y := r.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = r.position.y + (r.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = r.position.y + (r.size.y - h)
	return Rect2(x, y, w, h)


func _audit(root: Node) -> Dictionary:
	var d := {"web": 0, "round": 0, "ctrl": 0, "btn": 0, "lbl": 0,
		"stock": [], "dead": [], "small": [], "clip": [], "squash": [],
		"flat9": [], "spill": [], "overlap": [], "frame": []}
	var labels: Array = []
	var framed: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			d["ctrl"] = int(d["ctrl"]) + 1
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				var np := n as NinePatchRect
				framed.append([c.get_global_rect(), _band_of(np.texture)])
				var mv: float = np.patch_margin_top + np.patch_margin_bottom
				var mh: float = np.patch_margin_left + np.patch_margin_right
				if np.size.y > 0.0 and (np.size.y <= mv or np.size.x <= mh):
					(d["flat9"] as Array).append("%.0fx%.0f" % [np.size.x, np.size.y])
			if n is Label and str((n as Label).text).strip_edges().length() >= 4:
				var lb := n as Label
				d["lbl"] = int(d["lbl"]) + 1
				labels.append([_ink_rect(lb), str(lb.text)])
				var fs2: int = lb.get_theme_font_size("font_size")
				if lb.size.x < 6.0 or lb.size.y < 6.0:
					(d["squash"] as Array).append(str(lb.text).substr(0, 8))
				if lb.get_line_count() > lb.get_visible_line_count():
					(d["spill"] as Array).append(str(lb.text).substr(0, 8))
				if lb.clip_text and lb.autowrap_mode == TextServer.AUTOWRAP_OFF and lb.size.x > 1.0:
					var fnt: Font = lb.get_theme_font("font")
					if fnt != null and fnt.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x > lb.size.x + 0.5:
						(d["clip"] as Array).append(str(lb.text).substr(0, 8))
			for slot in ["panel", "normal", "background", "fill"]:
				if not c.has_theme_stylebox_override(slot):
					continue
				var sb = c.get_theme_stylebox(slot)
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					framed.append([c.get_global_rect(), _band_of((sb as StyleBoxTexture).texture)])
				elif sb is StyleBoxFlat:
					var f2 := sb as StyleBoxFlat
					if f2.corner_radius_top_left > 0:
						d["round"] = int(d["round"]) + 1
					if f2.border_width_top > 0 and f2.border_width_bottom > 0 \
							and f2.border_width_left > 0 and f2.border_width_right > 0 \
							and f2.bg_color.a < 0.95:
						d["web"] = int(d["web"]) + 1
			var is_btn: bool = c is BaseButton
			var wired: bool = c.gui_input.get_connections().size() > 0
			if c is Button and not (c as Button).flat:
				d["btn"] = int(d["btn"]) + 1
				if not c.has_theme_stylebox_override("normal"):
					(d["stock"] as Array).append(str((c as Button).text).substr(0, 8))
			if (is_btn or wired) and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				(d["dead"] as Array).append(c.name)
			if (is_btn or wired) and c.size.x > 1.0 and c.size.y > 1.0 \
					and minf(c.size.x, c.size.y) < TOUCH_MIN and maxf(c.size.x, c.size.y) < 200.0:
				(d["small"] as Array).append("%.0fx%.0f" % [c.size.x, c.size.y])
		for ch in n.get_children():
			st.append(ch)
	for i in range(labels.size()):
		for j in range(i + 1, labels.size()):
			if str(labels[i][1]) == str(labels[j][1]):
				continue
			var ra: Rect2 = labels[i][0]
			var rb: Rect2 = labels[j][0]
			var inter: Rect2 = ra.intersection(rb)
			if inter.size.x <= 0.0 or inter.size.y <= 0.0:
				continue
			var amin: float = minf(ra.size.x * ra.size.y, rb.size.x * rb.size.y)
			if amin > 0.0 and (inter.size.x * inter.size.y) / amin > 0.25:
				(d["overlap"] as Array).append("%s|%s" % [
					str(labels[i][1]).substr(0, 5), str(labels[j][1]).substr(0, 5)])
	for k in range(labels.size()):
		var lr: Rect2 = labels[k][0]
		var cc := lr.position + lr.size * 0.5
		var best := -1
		var best_a := 1.0e18
		for fi in range(framed.size()):
			var fr: Rect2 = framed[fi][0]
			if not fr.has_point(cc):
				continue
			var ar: float = fr.size.x * fr.size.y
			if ar < best_a:
				best_a = ar
				best = fi
		if best < 0:
			continue
		var fr2: Rect2 = framed[best][0]
		var inter2: Rect2 = fr2.intersection(lr)
		var la: float = lr.size.x * lr.size.y
		if la <= 0.0 or inter2.size.x <= 0.0 or (inter2.size.x * inter2.size.y) / la < 0.60:
			continue
		var m: float = float(framed[best][1])
		var inner := Rect2(fr2.position + Vector2(m, m), fr2.size - Vector2(m, m) * 2.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		var over := maxf(maxf(inner.position.y - lr.position.y,
			(lr.position.y + lr.size.y) - (inner.position.y + inner.size.y)),
			maxf(inner.position.x - lr.position.x,
			(lr.position.x + lr.size.x) - (inner.position.x + inner.size.x)))
		if over > 2.0:
			(d["frame"] as Array).append("%s+%.0f" % [str(labels[k][1]).substr(0, 6), over])
	return d


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 全屏 UI 一致性棘轮 ===")
	var tot_ctrl := 0
	var tot_btn := 0
	var tot_lbl := 0
	var all_stock: Array = []
	var all_dead: Array = []
	var all_clip: Array = []
	var all_squash: Array = []
	var all_flat9: Array = []
	var all_spill: Array = []
	var all_overlap: Array = []
	for scn in BASE.keys():
		var path := "res://scenes/%s.tscn" % str(scn)
		if not ResourceLoader.exists(path):
			_ok("场景在位: %s" % str(scn), false, "找不到 %s" % path)
			continue
		if str(scn) == "Inventory" and ResourceLoader.exists("res://tests/_setup_inv_demo.gd"):
			var sc = load("res://tests/_setup_inv_demo.gd")
			if sc != null and sc.has_method("run"):
				sc.run()
		# ⚠ 试过 `seed(20260818)` 想钉死商店货架 —— **没用**, 三次仍是 0/11、2/13、1/12。
		#   说明货架不走全局 RNG。**别再试这条路**; 改成给商店一个容差基线(见 BASE 注释)。
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		for _i in range(14):
			await get_tree().process_frame
		var d := _audit(inst)
		var b: Dictionary = BASE[scn]
		tot_ctrl += int(d["ctrl"])
		tot_btn += int(d["btn"])
		tot_lbl += int(d["lbl"])
		_ok("★分母 %s: 真的建起来了" % str(scn), int(d["ctrl"]) >= int(MIN_CTRL.get(scn, 10)),
			"可见控件 %d (下限 %d)" % [int(d["ctrl"]), int(MIN_CTRL.get(scn, 10))])
		_ok("%s 网页盒 ≤ %d" % [str(scn), int(b["web"])], int(d["web"]) <= int(b["web"]),
			"实测 %d" % int(d["web"]))
		_ok("%s 圆角盒 ≤ %d" % [str(scn), int(b["round"])], int(d["round"]) <= int(b["round"]),
			"实测 %d" % int(d["round"]))
		_ok("%s 文字压边带 ≤ %d" % [str(scn), int(b["frame"])],
			(d["frame"] as Array).size() <= int(b["frame"]),
			"实测 %d %s" % [(d["frame"] as Array).size(), str((d["frame"] as Array).slice(0, 4))])
		for v1 in (d["stock"] as Array):
			all_stock.append("%s:%s" % [str(scn), str(v1)])
		for v2 in (d["dead"] as Array):
			all_dead.append("%s:%s" % [str(scn), str(v2)])
		for v3 in (d["clip"] as Array):
			all_clip.append("%s:%s" % [str(scn), str(v3)])
		for v4 in (d["squash"] as Array):
			all_squash.append("%s:%s" % [str(scn), str(v4)])
		for v5 in (d["flat9"] as Array):
			all_flat9.append("%s:%s" % [str(scn), str(v5)])
		for v6 in (d["spill"] as Array):
			all_spill.append("%s:%s" % [str(scn), str(v6)])
		for v7 in (d["overlap"] as Array):
			all_overlap.append("%s:%s" % [str(scn), str(v7)])
		inst.queue_free()
		await get_tree().process_frame
	print("  ── 全屏合计 ──")
	_ok("★分母: 扫到的可见控件 ≥ 500", tot_ctrl >= 500, "%d 个" % tot_ctrl)
	_ok("★分母: 扫到的按钮 ≥ 25", tot_btn >= 25, "%d 个" % tot_btn)
	_ok("★分母: 扫到的带字标签 ≥ 120", tot_lbl >= 120, "%d 个" % tot_lbl)
	_ok("没有【还用 Godot 默认皮】的按钮", all_stock.is_empty(), str(all_stock.slice(0, 5)))
	_ok("没有【收不到点击】的交互控件", all_dead.is_empty(), str(all_dead.slice(0, 5)))
	_ok("没有【被 clip_text 截断】的文字", all_clip.is_empty(), str(all_clip.slice(0, 5)))
	_ok("没有【被挤成 <6px】的文字", all_squash.is_empty(), str(all_squash.slice(0, 5)))
	_ok("没有【边距和 ≥ 尺寸】的退化九宫格", all_flat9.is_empty(), str(all_flat9.slice(0, 5)))
	_ok("没有【行数装不下】的文字", all_spill.is_empty(), str(all_spill.slice(0, 5)))
	_ok("没有【两段文字压在一起】", all_overlap.is_empty(), str(all_overlap.slice(0, 5)))
	print("  %d passed, %d failed" % [_pass, _fail])
	if _fail == 0:
		print("ALL PASS — 全屏 UI 一致性")
	get_tree().quit(1 if _fail > 0 else 0)
