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
## ★"tap" = 短边 < 81px(44pt) 的可点元素上限。剩下的 18 个各有理由, 不是漏做:
##   · TeamSelect 5 个(返回/清空/上次阵容/开始冒险/被动签): 它们的**底板烤在 select-bg.png 上**,
##     2026-08-19 实拍验证过 —— 一加高文字就浮到画好的木牌外面。要真加大得先重画背景图。
##   · Inventory 8 个迷你装备格 + 3 个前/后排小钮: 版式极限(见下), 已另给 81px 的「卸下」主路径。
##   · MainMenu 1 个调试入口 / Shop 1 个: 见下。
##
## ★两处**不是余量、是有理由的豁免**(别当成"还没改完"):
##   · MainMenu 的 1 个 = 右下角调试入口 120x46。它**不是玩家路径**, 刻意保持朴素,
##     和正式按钮长得不一样正是想要的效果。
##   · Inventory 的 10 个 = 单位卡上的 40x40 迷你装备格。2026-08-18 实拍对比后**退回过一次**:
##     换金属框会让**费用色从整块实心退化成一圈细边**, 而那块实心色本身就是信息
##     (一眼分得出 2/3/4/5 费)。⇒ 贴图框有它的最小可用尺寸, 小于它就该保持纯色块。
const BASE: Dictionary = {
	"MainMenu": {"web": 1, "round": 3, "frame": 0, "tap": 1},
	"Inventory": {"web": 10, "round": 19, "frame": 1, "tap": 11},
	"Codex": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	"TeamSelect": {"web": 0, "round": 61, "frame": 0, "tap": 5},
	# 商店货架随机 ⇒ 它这两格是**容差基线**(实测跨多次运行 0~3 网页盒 / 11~14 圆角盒)。
	# 卡到实测上沿会偶发红; 而真回归是数量级的(31 vs 0), 容差 +1 挡不住的场面不存在。
	"Shop": {"web": 0, "round": 11, "frame": 0, "tap": 1},
	"Settings": {"web": 0, "round": 0, "frame": 0, "tap": 0},
	"Record": {"web": 0, "round": 0, "frame": 0, "tap": 0},
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
## 是不是"浮在内容上的提示层"(toast) —— 这类重叠是设计如此, 不是 bug。
func _is_toast(c: Control) -> bool:
	var n := c
	var hop := 0
	while n != null and hop < 4:
		var nm := str(n.name).to_lower()
		if nm.findn("status") >= 0 or nm.findn("toast") >= 0 or nm.findn("flash") >= 0:
			return true
		n = n.get_parent() as Control
		hop += 1
	return false


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


## 等到【版面真的不动了】再量。
##
## ★由来(2026-08-18): 原来固定等 14 帧就量, 而好几个屏有**入场动画**(木牌从左边滑进来)。
##   实测主菜单的「排行榜」「图鉴」两个标签此时 global x = **−485**, 还在屏幕外,
##   而且两者**报同一个矩形** ⇒ 压字判据当场报"排行榜压图鉴", 可实拍两块木牌离得远远的。
##   **量了一个还在动的东西 = 量了个不存在的画面。**
## ⇒ 改成轮询: 每帧把所有可见控件的矩形加起来求和, 连续 6 帧不变才算稳住(上限 240 帧兜底)。
func _settle(root: Node) -> void:
	var last := -1.0
	var same := 0
	for _i in range(240):
		await get_tree().process_frame
		var acc := 0.0
		var st: Array = [root]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is Control and (n as Control).is_visible_in_tree():
				var r := (n as Control).get_global_rect()
				acc += r.position.x + r.position.y * 3.0 + r.size.x * 7.0 + r.size.y * 11.0
			for ch in n.get_children():
				st.append(ch)
		if absf(acc - last) < 0.5:
			same += 1
			if same >= 6:
				return
		else:
			same = 0
		last = acc


var _bbox_cache: Dictionary = {}


## 贴图里【真正有像素的那一块】在 0~1 归一坐标下的包围盒。
##
## ★由来: 龟/小将立绘四周都有大片透明留白(94x104 的框里, 实际画面可能只占中间 70%)。
##   只把控件矩形按 stretch 换算, 得到的还是"含留白的那块", 于是 28 张龟卡的头像、
##   6 张小将卡的立绘、28 个稀有度角标**全被报成压边带 3~7px** —— 而实拍它们稳稳在框里。
##   这是同一个错的第 9、10 次: **量真正画出来的东西, 不是量装它的盒子。**
func _opaque_bbox(tex: Texture2D) -> Rect2:
	var key := tex.resource_path
	if _bbox_cache.has(key):
		return _bbox_cache[key]
	var img := tex.get_image()
	var bb := Rect2(0, 0, 1, 1)
	if img != null and img.get_width() > 0:
		var w := img.get_width()
		var h := img.get_height()
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		var step: int = maxi(1, int(maxf(float(w), float(h)) / 96.0))   # 大图抽样, 够用且不慢
		for y in range(0, h, step):
			for x in range(0, w, step):
				if img.get_pixel(x, y).a > 0.06:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		if x1 >= x0 and y1 >= y0:
			bb = Rect2(float(x0) / float(w), float(y0) / float(h),
				float(x1 - x0 + 1) / float(w), float(y1 - y0 + 1) / float(h))
	_bbox_cache[key] = bb
	return bb


## 把"画出来的矩形"再按贴图的不透明包围盒收一圈。
func _crop_alpha(drawn: Rect2, tex: Texture2D) -> Rect2:
	var bb := _opaque_bbox(tex)
	return Rect2(drawn.position + Vector2(bb.position.x * drawn.size.x, bb.position.y * drawn.size.y),
		Vector2(bb.size.x * drawn.size.x, bb.size.y * drawn.size.y))


## 真正画出来的那块图的矩形(不是 TextureRect 控件的矩形)。
func _art_rect(t: TextureRect) -> Rect2:
	var r := t.get_global_rect()
	var ts: Vector2 = t.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return r
	match t.stretch_mode:
		TextureRect.STRETCH_KEEP:
			return _crop_alpha(Rect2(r.position,
				Vector2(minf(ts.x, r.size.x), minf(ts.y, r.size.y))), t.texture)
		TextureRect.STRETCH_KEEP_CENTERED:
			var kc: Vector2 = Vector2(minf(ts.x, r.size.x), minf(ts.y, r.size.y))
			return _crop_alpha(Rect2(r.position + (r.size - kc) * 0.5, kc), t.texture)
		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var k: float = minf(r.size.x / ts.x, r.size.y / ts.y)
			var sz: Vector2 = ts * k
			if t.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				return _crop_alpha(Rect2(r.position + (r.size - sz) * 0.5, sz), t.texture)
			return _crop_alpha(Rect2(r.position, sz), t.texture)
		_:
			pass          # SCALE / COVERED: 铺满整个矩形, 直接进下面的留白裁剪
	return _crop_alpha(r, t.texture)


func _audit(root: Node) -> Dictionary:
	var d := {"web": 0, "round": 0, "ctrl": 0, "btn": 0, "lbl": 0,
		"stock": [], "dead": [], "small": [], "clip": [], "squash": [],
		"flat9": [], "spill": [], "overlap": [], "frame": [], "tap": []}
	var labels: Array = []
	var framed: Array = []
	var arts: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			d["ctrl"] = int(d["ctrl"]) + 1
			## 触控热区: 短边 < 81px(=44pt) 的可点元素。★TouchPad 本身不算(它是别人的热区),
			##   有效热区 = 控件矩形 与 它挂的 TouchPad 取大 —— 不这么算数字会反着涨(实测 43→51)。
			if str(c.name) != "TouchPad":
				var _hit: bool = c is BaseButton or c.gui_input.get_connections().size() > 0
				var _ew: float = c.size.x
				var _eh: float = c.size.y
				var _pad = c.get_node_or_null("TouchPad")
				if _pad != null and _pad is Control:
					_ew = maxf(_ew, (_pad as Control).size.x)
					_eh = maxf(_eh, (_pad as Control).size.y)
				if _hit and _ew > 1.0 and _eh > 1.0 and minf(_ew, _eh) < 81.0 and maxf(_ew, _eh) < 200.0:
					(d["tap"] as Array).append("%.0fx%.0f %s" % [_ew, _eh, c.get_class()])
			if n is TextureRect and (n as TextureRect).texture != null and c.size.x >= 12.0 and c.size.y >= 12.0:
				# 头像/图标顶破框也是"压边带"的一种(图鉴列表行的头像实拍把行框切开了)。
				# ★但要量【真正画出来的那块图】: TextureRect 用 KEEP_ASPECT_CENTERED 时
				#   图是**按比例缩到框内居中**的, 控件矩形比图大一圈 ——
				#   拿控件矩形量, 28 张龟卡的头像全被报成"压边带 3px", 而实拍头像稳稳在卡里。
				#   和文字那次一模一样的错(第 9 次): **尺子要匹配被测概念。**
				# ★角标要放过: 稀有度小签、被动小图标这类**本来就是设计成压在卡角上的**
				#   (选龟 28 张卡各一个, 实拍就该那样)。判据: 自己 ≤24px 且住在一个独立的小盒子里。
				#   不放过的话它们会一直红, 逼我去"修"一个根本不是问题的东西。
				var is_badge: bool = c.size.x <= 24.0 and c.size.y <= 24.0 \
					and (c.get_parent() is PanelContainer or c.get_parent() is Panel)
				if not is_badge:
					arts.append([_art_rect(n as TextureRect), "图<%s|%.0fx%.0f>" % [str(c.name), c.size.x, c.size.y]])
			if n is NinePatchRect and (n as NinePatchRect).texture != null:
				var np := n as NinePatchRect
				framed.append([c.get_global_rect(), _band_of(np.texture)])
				var mv: float = np.patch_margin_top + np.patch_margin_bottom
				var mh: float = np.patch_margin_left + np.patch_margin_right
				if np.size.y > 0.0 and (np.size.y <= mv or np.size.x <= mh):
					(d["flat9"] as Array).append("%.0fx%.0f" % [np.size.x, np.size.y])
			# ★两个覆盖缺口(2026-08-18 实拍图鉴才发现, 判据全绿而肉眼三处毛病):
			#   ① 技能卡正文是 **RichTextLabel**, 不是 Label ⇒ 「点开看全部」压在正文上,
			#      压字判据**根本没把正文收进来**, 报 0。
			#   ② 门槛写的 `length() >= 4` —— 而龟名是 2~3 个字(「财神龟」)、稀有度是 1 个字母(「C」)。
			#      底部统计行压在「财神龟」上、右边框切掉「C」, 两条都因为**字太短被过滤掉了**。
			#   ⇒ 文字类一律收进来(Label + RichTextLabel), 门槛降到 1。
			if n is RichTextLabel and str((n as RichTextLabel).get_parsed_text()).strip_edges() != "":
				var rl := n as RichTextLabel
				d["lbl"] = int(d["lbl"]) + 1
				var rr := rl.get_global_rect()
				var used := minf(rl.get_content_height(), rr.size.y) if rl.get_content_height() > 0.0 else rr.size.y
				labels.append([Rect2(rr.position, Vector2(rr.size.x, used)),
					str(rl.get_parsed_text()).strip_edges(), _is_toast(rl)])
			if n is Label and str((n as Label).text).strip_edges().length() >= 1:
				var lb := n as Label
				d["lbl"] = int(d["lbl"]) + 1
				## 角标小签(选中 ✓ / 基础 / 稀有度)本来就是刻意压在格子角上的, 和图片角标同一类 ——
				## 之前只豁免了 TextureRect, 这里把 Label 版补上: 它住在一个 <40px 的独立小盒子里。
				var _par := lb.get_parent() as Control
				var _badge: bool = _par != null and (_par is PanelContainer or _par is Panel) \
						and _par.size.x < 40.0 and _par.size.y < 40.0
				labels.append([_ink_rect(lb), str(lb.text), _is_toast(lb) or _badge])
				var fs2: int = lb.get_theme_font_size("font_size")
				# ⚠ 判据太宽第 8 次: 报选龟稀有度栏杆的「A」「B」「C」被挤没 —— 实拍那几个
				#   字母**显示得好好的**。原因是这些 Label 是手工定位的, `size` 就是 (0,0),
				#   而 **Godot 的 Label 不裁剪**: 矩形再小照样把字画出来。
				#   只有 `clip_text` 打开时"矩形太小"才真会吃掉字。
				if (lb.size.x < 6.0 or lb.size.y < 6.0) and lb.clip_text:
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
			# ★toast(StatusBar/飘字提示)本来就是【浮在内容上】的一层, 2 秒后淡出 ——
			#   把它算成"两段文字压在一起"是判据没分清"重叠"和"覆盖式提示"。
			#   只豁免这一类(名字里带 status/toast), 其它重叠仍然要红。
			if labels[i][2] or labels[j][2]:
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
	var boxed: Array = labels.duplicate()
	boxed.append_array(arts)
	for k in range(boxed.size()):
		var lr: Rect2 = boxed[k][0]
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
		if boxed[k].size() > 2 and bool(boxed[k][2]):
			continue          # 角标/toast: 压在边上是设计如此
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
			(d["frame"] as Array).append("%s+%.0f" % [str(boxed[k][1]).substr(0, 50), over])
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
		# ★商店货架已在 ShopScene 里钉死(test_mode ⇒ _rng.seed 固定, 不 randomize)。
		#   之前试 `seed(20260818)` 没用是因为**那是全局 RNG, 而商店有自己的 RandomNumberGenerator** ——
		#   钉错了对象, 不是"钉不住"。现三次连跑都是 0/11。
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		await _settle(inst)
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
		_ok("%s 热区不足(短边<44pt) ≤ %d" % [str(scn), int(b["tap"])],
			(d["tap"] as Array).size() <= int(b["tap"]),
			"实测 %d %s" % [(d["tap"] as Array).size(), str((d["tap"] as Array).slice(0, 4))])
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
