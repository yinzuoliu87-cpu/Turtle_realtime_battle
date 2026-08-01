class_name CodexList
extends RefCounted
## 图鉴·左栏列表行构建(龟/装备/状态/分组头/简单行·back_button和共享_add_text/image/portrait/rect留主场景)
## 类内名不变;外部名加 battle.

var host

## ★★图标贴图缓存(2026-08-01 修「点装备那里会卡一下」, 用户报)。
## 实测: 切到"装备"页签一次阻塞 179~208 ms(其余页签只要 6~38 ms) —— 60fps 下卡住十几帧。
## 根因: 装备页 67 行每行 load() 一张 PNG 图标; 而【行被 free 后贴图引用归零 → 被逐出 Godot 的
##   资源缓存 → 下次切回来 67 张全部重新从盘上读】, 所以第二次切也照样慢(实测第2轮 179ms)。
## ★用 static 常驻持有引用, 贴图就不会被逐出。67 张 UI 小图, 内存代价可忽略。
static var _tex_cache: Dictionary = {}

static func _icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t      # ★不存在也记下来 —— 否则每次都要再问一次文件系统
	return t


## 预热图标缓存: 把"首次进装备页要读 67 张 PNG"那 200ms 摊到开图鉴之后的若干帧里。
## ★缓存解决的是【第二次以后】(206→13ms), 第一次该读的盘还是要读 —— 只能提前、分帧读, 不能省。
## ★每帧只读 PER_FRAME 张: 读满一帧就让出去, 保证任何一帧都不会明显变长。
## ★每帧读几张: 实测每张 PNG 约 3ms。6 张/帧时预热期最大单帧 47ms(60fps 一帧只有 16.7ms)——
##   那只是把卡顿从"点装备那一下"挪到了"刚进图鉴那几帧", 没解决问题。2 张/帧才压得住。
const WARM_PER_FRAME := 2

func warm_icons(tree: SceneTree) -> void:
	var paths: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var img: String = str(eq.get("img", ""))
		if img.ends_with(".png"):
			paths.append("res://assets/sprites/%s" % img)
	for eq in DataRegistry.all_equipment:
		if eq is Dictionary and str(eq.get("icon", "")).ends_with(".png"):
			paths.append("res://assets/sprites/%s" % str(eq["icon"]))
	for pet in DataRegistry.all_pets:
		if pet is Dictionary:
			paths.append("res://assets/sprites/avatars/%s.png" % str(pet.get("id", "")))
	var n := 0
	for pp in paths:
		if _tex_cache.has(pp):
			continue
		_icon(pp)
		n += 1
		if n % WARM_PER_FRAME == 0:
			await tree.process_frame


func _init(b) -> void:
	host = b

func _add_pet_row(pet: Dictionary) -> void:
	var idx = host._items.size() - 1
	var rarity: String = pet.get("rarity", "C")
	var col = Color(host.RARITY_COLOR.get(rarity, "#ffffff")); col.a = 0.7
	var p = host._make_row(52, 0.85, col)
	var idx_path = "res://assets/sprites/avatars/%s.png" % pet.get("id", "")
	# 圆头像 (40 直径), PoC addCircularAvatar — 这里用 TextureRect 方框近似 (Godot 无内置圆裁, 1:1 数据正确)
	var av = TextureRect.new()
	av.position = Vector2(6, 6)
	av.custom_minimum_size = Vector2(40, 40); av.size = Vector2(40, 40)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.texture = _icon(idx_path)      # 走缓存(同上: 行被 free 会把贴图逐出缓存 → 每次切页签重读盘)
	p.add_child(av)
	# 名字 15px (PoC #fff bold)
	var name_lbl = Label.new()
	name_lbl.text = pet.get("name", "?")
	name_lbl.position = Vector2(56, 0)
	name_lbl.size = Vector2(host.LIST_W - 16 - 56 - 26, 52)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	p.add_child(name_lbl)
	# 稀有度文字右对齐 14px 彩
	var rar = Label.new()
	rar.text = rarity
	rar.position = Vector2(host.LIST_W - 16 - 38, 0)
	rar.size = Vector2(24, 52)
	rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rar.add_theme_font_size_override("font_size", 14)
	rar.add_theme_font_override("font", host._mono_font())   # PoC CodexScene.ts:199 fontFamily:'monospace'
	rar.add_theme_color_override("font_color", Color(host.RARITY_COLOR.get(rarity, "#ffffff")))
	p.add_child(rar)
	host._connect_row(p, idx, col)


## 列表内分组分隔条: 左右细线夹一个小标题, 不可点(纯视觉分段).
func _add_group_header(title: String) -> void:
	var h = Control.new()
	h.custom_minimum_size = Vector2(host.LIST_W - 16, 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.list_vbox.add_child(h)
	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#7a8a96"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(lbl)
	var tw: float = float(title.length()) * 13.0
	for side in [0, 1]:
		var ln = ColorRect.new()
		ln.color = Color("#3a4a5c")
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var seg: float = ((host.LIST_W - 16.0) - tw) / 2.0 - 14.0
		ln.size = Vector2(maxf(8.0, seg), 1)
		ln.position = Vector2(10.0 if side == 0 else (host.LIST_W - 16.0 - 10.0 - maxf(8.0, seg)), 15)
		h.add_child(ln)


func _add_simple_row(label: String, label_color: String, stroke: Color, icon_path: String, idx: int) -> void:
	var col = stroke; col.a = 0.7
	var p = host._make_row(52, 0.85, col)
	var _ictex: Texture2D = _icon(icon_path)
	if _ictex != null:
		var ic = TextureRect.new()
		ic.position = Vector2(6, 8)
		ic.custom_minimum_size = Vector2(36, 36); ic.size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = _ictex
		p.add_child(ic)
	var lbl = Label.new()
	lbl.text = label
	lbl.position = Vector2(48, 0)
	lbl.size = Vector2(host.LIST_W - 16 - 56, 52)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(label_color))
	p.add_child(lbl)
	host._connect_row(p, idx, col)


# 装备 Tab 总件数 = p2eq(59) + 消耗品件数 (Tab 计数 / 状态栏共用)
# ── 装备 Tab 列表: 59 件 p2eq 按费用 1→5 分组 + 末尾 8 件消耗品 (1:1 上线野生=duallane 实际装备池) ──
#   数据源: DataRegistry.phase2_equipment (data/phase2-equipment.json); 消耗品 = all_equipment 中 category=consumable。
#   行描边 + 标题 都用费用色(host.COST_COLOR·装备无 rarity 字段); p2eq 有 PNG 图标(img·2026-07-18)→图标格+纯名, 无 img 才 emoji 前缀兜底。
func _add_equip_rows() -> void:
	# 费用分组 (1→5)
	for cost in [1, 2, 3, 4, 5]:
		var items = []
		for eq in DataRegistry.phase2_equipment:
			if not (eq is Dictionary):
				continue
			if int(eq.get("cost", 0)) == cost:
				items.append(eq)
		if items.is_empty():
			continue
		var ccol: String = host.COST_COLOR.get(cost, "#4cc9f0")
		_add_header("▸ 费用 %d (%d)" % [cost, items.size()], ccol)
		for eq in items:
			host._items.append(eq)
			var stroke: String = ccol
			var emoji: String = str(eq.get("emoji", "📦"))
			var img: String = str(eq.get("img", ""))
			var ipath: String = "res://assets/sprites/%s" % img if img.ends_with(".png") else ""
			# 有 PNG 图标(新版 img·2026-07-18装备图标)→图标格+纯名; 无→emoji 前缀兜底(旧行为)
			var rname: String = str(eq.get("name", "?")) if ipath != "" else "%s %s" % [emoji, str(eq.get("name", "?"))]
			_add_simple_row(rname, "#ffffff", Color(stroke), ipath, host._items.size() - 1)
	# 消耗品分组 (取自 all_equipment category=consumable, 8 件; 有 PNG icon)
	var consumables = []
	for eq in DataRegistry.all_equipment:
		if eq is Dictionary and eq.get("category", "") == "consumable":
			consumables.append(eq)
	if not consumables.is_empty():
		_add_header("▸ 消耗品 (%d)" % consumables.size(), "#06d6a0")
		for eq in consumables:
			host._items.append(eq)
			var icon: String = str(eq.get("icon", ""))
			var ipath = "res://assets/sprites/%s" % icon if icon.ends_with(".png") else ""
			_add_simple_row(eq.get("name", "?"), "#ffffff", Color("#06d6a0"), ipath, host._items.size() - 1)


func _add_status_rows() -> void:
	var cat_label = {
		"dot": ["DoT (持续伤害)", "#ef4444"], "cc": ["CC (控制)", "#c77dff"],
		"buff": ["Buff (增益)", "#06d6a0"], "debuff": ["Debuff (减益)", "#fbbf24"],
	}
	for cat in ["dot", "cc", "buff", "debuff"]:
		var items = []
		for st in DataRegistry.status_defs:
			if st.get("category", "") == cat:
				items.append(st)
		if items.is_empty():
			continue
		_add_header(cat_label[cat][0], cat_label[cat][1])
		for st in items:
			host._items.append(st)
			var icon_key: String = st.get("iconKey", "")
			var ipath = "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", "")
			_add_simple_row(st.get("name", "?"), "#ffd93d", Color(cat_label[cat][1]), ipath, host._items.size() - 1)


func _add_header(text: String, color: String) -> void:
	var h = Label.new()
	h.text = text
	h.add_theme_font_size_override("font_size", 14)
	h.add_theme_color_override("font_color", Color(color))
	var wrap = MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_top", 4)
	wrap.add_child(h)
	host.list_vbox.add_child(wrap)


