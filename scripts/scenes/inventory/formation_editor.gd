class_name InvFormation
extends RefCounted
## 背包·站位编辑(2026-10-19)。
##
## 用户 10-19:「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」。
##   ⇒ 两块小场地(上战场 / 下战场), 各画【本方半场】: 拖龟到想站的位置, 松手即存进阵容格子的 `off`
##      (`LineupPos`, 随快照上传, 对手打我时我的龟就站在这里)。
## ★小场地按战场同一套几何画: 岛形(`ArenaShape` 超椭圆, 与开打夹取同一个 pad 60)、中线前 120 不许站、
##   `LineupPos` 的可摆范围、左端是龟蛋。拖动时按同一套规则夹(拖动中显示的就是松手后会存下的那一格)
##   ⇒ 这里摆在哪, 开打就站在哪; 唯一的差别是每张图的障碍不同,
##   开打时撞上障碍会被推到障碍边上(`DualLaneFlow.clamp_place_side`)。
## ★面板从顶栏下沿开始(`TopBar.BAR_H`), 不压顶栏; 摆动即存, 顶栏「返回」随时可走。
## ★照 CLAUDE.md §5 拆分模板: RefCounted + 构造注入宿主(InventoryScene)。

const LP := preload("res://scripts/gamedata/lineup_pos.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Minion := preload("res://scripts/gamedata/phase2_minion.gd")
const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")   # 教程锚点: vis_rect

## 场地显示比例(世界像素 → 屏幕像素)。半场 798×728 ⇒ 479×437, 两块并排放得进 1280。
## ★2026-10-21 手机版 0.6 → 0.56: 底下两颗键原来到屏幕 691, 压进 iPhone 底部横条(682 起)。
const S := 0.56
## 小场地底图的原生分辨率: 每格 = 几个世界像素(放大时整像素 NEAREST, 边缘是像素台阶)。
const CELL := 7.0
const TOKEN := 64.0              # 龟头像直径(触控 ≥ 44pt 由外扩点击区保证, 见 TOKEN_HIT)
const TOKEN_HIT := 84.0
const PAD := 60.0                # 与 `clamp_place_side` 的岛形 pad 同一个数
const MID_GAP := 120.0           # 与 `clamp_place_side` 的「不越中线」同一个数
const C_GRASS := Color("#4e7a3a")
const C_GRASS_D := Color("#3c5f2d")
const C_NOGO := Color("#2c3a24")
const C_WATER := Color("#16324a")
const C_LINE := Color("#e8dcc4")
const DESIGN_W := 1280               # 背包按 1280×720 设计框画(`UIFrame`), 面板居中于它

var host = null
var _dim: Control = null
var _body: Control = null
var _drag: Dictionary = {}       # {lane, idx, grab} grab = 按下点到龟头像中心的偏移(拖动不跳)
static var _tex: Texture2D = null


func _init(h) -> void:
	host = h


func is_open() -> bool:
	return _dim != null and is_instance_valid(_dim)


## 本方半场在世界里的矩形(左方)。
static func half_rect() -> Rect2:
	return Rect2(RB.ARENA.position, Vector2(RB.ARENA.size.x * 0.5, RB.ARENA.size.y))


static func center() -> Vector2:
	return RB.ARENA.position + RB.ARENA.size * 0.5


## 左方队形中心(与 `_dl_build_lane_field` 的 `_cx - 420` 同一个点)。
static func base_l() -> Vector2:
	return center() - Vector2(float(LP.FORMATION_DX), 0.0)


## 世界坐标按摆位规则夹(岛形 + 不越中线)。障碍每张图不同, 这里不管。
static func clamp_world(w: Vector2) -> Vector2:
	w = ArenaShape.clamp_in(w, RB.ARENA, PAD)
	w.x = minf(w.x, center().x - MID_GAP)
	return w


## 世界坐标 → 要存的偏移(整数, 钳进可摆范围)。拖动中与松手都走它 ⇒ 看到的 = 存下的。
static func off_from_world(w: Vector2) -> Vector2i:
	var d: Vector2 = clamp_world(w) - base_l()
	return LP.clamp_off(Vector2i(int(round(d.x)), int(round(d.y))))


static func world_from_off(o: Vector2i) -> Vector2:
	return base_l() + Vector2(float(o.x), float(o.y))


## 半场底图: 岛上可站 = 草地, 中线前那一条 = 暗草(不能站), 岛外 = 海。
## 在不在 `LineupPos` 的可摆范围里(偏移矩形 DX/DY_MIN..MAX)。
static func _in_lp_range(wp: Vector2) -> bool:
	var d: Vector2 = wp - base_l()
	return d.x >= float(LP.DX_MIN) and d.x <= float(LP.DX_MAX) and d.y >= float(LP.DY_MIN) and d.y <= float(LP.DY_MAX)


static func field_tex() -> Texture2D:
	if _tex != null:
		return _tex
	var hr := half_rect()
	var w := int(ceil(hr.size.x / CELL))
	var h := int(ceil(hr.size.y / CELL))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var wp := hr.position + Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
			var col := C_WATER
			if ArenaShape.inside(wp, RB.ARENA, ArenaShape.N, 0.0):
				col = C_NOGO
				if ArenaShape.inside(wp, RB.ARENA, ArenaShape.N, PAD) and wp.x <= center().x - MID_GAP and _in_lp_range(wp):
					col = C_GRASS if ((x / 4 + y / 4) % 2 == 0) else C_GRASS_D
			img.set_pixel(x, y, col)
	_tex = ImageTexture.create_from_image(img)
	return _tex


# ══════════════════════════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════════════════════════

func open() -> void:
	if is_open():
		return
	_drag = {}
	_dim = ColorRect.new(); _dim.name = "FormationEditor"
	(_dim as ColorRect).color = Color(0.02, 0.04, 0.07, 0.94)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.offset_top = TopBar.BAR_H          # 不压顶栏
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(_dim)
	## 内容放进一块 1280 宽、水平居中的板(暗幕本身铺满整窗: 宽屏两侧也是暗的)。
	_body = Control.new(); _body.name = "FormationBody"
	_body.anchor_left = 0.5; _body.anchor_right = 0.5
	_body.offset_left = -float(DESIGN_W) * 0.5; _body.offset_right = float(DESIGN_W) * 0.5
	_body.offset_top = 0.0; _body.offset_bottom = 720.0 - TopBar.BAR_H
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(_body)
	var fs: Vector2 = half_rect().size * S
	var gap := 36.0
	var w_all: float = fs.x * 2.0 + gap
	var x0: float = float(DESIGN_W) * 0.5 - w_all * 0.5
	var ttl := Label.new(); ttl.name = "FormationTitle"
	ttl.text = "站位"
	ttl.add_theme_font_size_override("font_size", 26); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.add_theme_color_override("font_outline_color", Color("#0b1018")); ttl.add_theme_constant_override("outline_size", 5)
	ttl.position = Vector2(x0, 8); ttl.size = Vector2(80, 36)
	_body.add_child(ttl)
	var sub := Label.new(); sub.name = "FormationHint"
	sub.text = "拖动单位设置开战站位。实际站位避开当局地形。"
	sub.add_theme_font_size_override("font_size", 20); sub.add_theme_color_override("font_color", Color("#b9c6d3"))
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.position = Vector2(x0 + 84.0, 8); sub.size = Vector2(w_all - 84.0, 36)
	_body.add_child(sub)
	var y0 := 8.0 + 36.0 + 32.0
	var lanes := [["上战场", "top", Color("#ffd93d")], ["下战场", "bottom", Color("#7fd0ff")]]
	for k in range(2):
		_build_field(str(lanes[k][1]), str(lanes[k][0]), lanes[k][2], Vector2(x0 + float(k) * (fs.x + gap), y0))
	## 底部两颗键: 恢复默认(两路都清) / 完成
	var by: float = y0 + fs.y + 10.0
	var reset := _btn("FormationReset", "恢复默认", Vector2(x0, by), Vector2(200, TopBar.TOUCH_MIN), Color("#2a3644"), Color("#7d8a9c"))
	reset.pressed.connect(_reset_all)
	_body.add_child(reset)
	var done := _btn("FormationDone", "完成", Vector2(x0 + w_all - 200.0, by), Vector2(200, TopBar.TOUCH_MIN), Color("#6a3f1c"), Color("#d89a48"))
	done.pressed.connect(close)
	_body.add_child(done)
	_tut_notify("formation_opened")   # 教程 v3「点击站位」


## 教程 v3 的事件(非教程 / 没有引导 ⇒ 导演什么都不做)。
func _tut_notify(ev: String) -> void:
	var td = host.get_node_or_null("/root/TutorialDirector") if host != null and host.is_inside_tree() else null
	if td != null:
		td.notify(ev)


## 拖动松手时位移超过这么多屏幕像素才算「拖了一下」(教程「拖动龟调整站位」; 点一下不算)。
const TUT_DRAG_MIN := 24.0


## 教程 v3 锚点: formation_field(上战场小场地) / formation_token(上战场第一只) / formation_done(「完成」)。
func tut_anchor(nm: String) -> Rect2:
	if not is_open() or _body == null:
		return Rect2()
	var n: Node = null
	match nm:
		"formation_field":
			n = _body.find_child("Field_top", true, false)
		"formation_token":
			n = _body.find_child("Token_top_0", true, false)
		"formation_done":
			n = _body.find_child("FormationDone", true, false)
	return TutorialGuide.vis_rect(n)


func close() -> void:
	_drop_dim()
	_drag = {}
	host._rebuild()
	_tut_notify("formation_closed")   # 教程 v3「点击完成」


## 摘掉旧面板。★先改名再 queue_free: 同一帧里立刻重开时新面板才拿得到「FormationEditor」这个名字
##   (旧的还挂在树上直到帧末, 重名会让新的被自动改名, 按名字找就会找到那个要死的)。
func _drop_dim() -> void:
	if is_open():
		_dim.name = "FormationEditor_closing"
		_dim.queue_free()
	_dim = null
	_body = null


func _btn(nm: String, txt: String, pos: Vector2, sz: Vector2, bg: Color, border: Color) -> Button:
	var b := Button.new(); b.name = nm; b.text = txt
	b.add_theme_font_size_override("font_size", 20)
	for st in [["normal", 0.0], ["hover", 0.08], ["pressed", -0.08], ["focus", 0.0]]:
		var sb := StyleBoxFlat.new(); sb.bg_color = bg.lightened(st[1]) if float(st[1]) >= 0.0 else bg.darkened(-float(st[1]))
		sb.border_color = border; sb.set_border_width_all(3); sb.set_corner_radius_all(0)
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_color_override("font_color", Color("#fff1d6"))
	b.position = pos; b.size = sz
	return b


func _build_field(lane: String, title: String, col: Color, pos: Vector2) -> void:
	var fs: Vector2 = half_rect().size * S
	var hd := Label.new(); hd.name = "FieldTitle_" + lane
	hd.text = title
	hd.add_theme_font_size_override("font_size", 20); hd.add_theme_color_override("font_color", col)
	hd.position = pos - Vector2(0, 30); hd.size = Vector2(200, 28)
	_body.add_child(hd)
	var field := TextureRect.new(); field.name = "Field_" + lane
	field.texture = field_tex()
	field.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; field.stretch_mode = TextureRect.STRETCH_SCALE
	field.position = pos; field.size = fs
	field.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(field)
	## 中线(右沿)与「敌方」方向
	var mid := ColorRect.new(); mid.color = Color(C_LINE.r, C_LINE.g, C_LINE.b, 0.55)
	mid.position = Vector2(fs.x - 3.0, 0); mid.size = Vector2(3, fs.y); mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(mid)
	var foe := Label.new(); foe.text = "中线"
	foe.add_theme_font_size_override("font_size", 20); foe.add_theme_color_override("font_color", C_LINE)
	foe.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foe.position = Vector2(fs.x - 80.0, 6); foe.size = Vector2(72, 28); foe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(foe)
	## 龟蛋(左端, 与战场 `ARENA.x + 70` 同一个点)
	var egg_w := Vector2(RB.ARENA.position.x + 70.0, center().y)
	var egg := Label.new(); egg.name = "Egg"; egg.text = "蛋"
	egg.add_theme_font_size_override("font_size", 20); egg.add_theme_color_override("font_color", Color("#fff1d6"))
	egg.add_theme_color_override("font_outline_color", Color("#0b1018")); egg.add_theme_constant_override("outline_size", 4)
	egg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	egg.position = _to_field(egg_w) - Vector2(16, 14); egg.size = Vector2(32, 28); egg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(egg)
	## 单位
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	var n: int = arr.size()
	var lead_n := 0
	for u in arr:
		if u is Dictionary and str(u.get("kind", "")) == "leader":
			lead_n += 1
	var m_seen := 0
	for i in range(n):
		var u: Dictionary = arr[i] if arr[i] is Dictionary else {}
		var is_leader: bool = str(u.get("kind", "")) == "leader"
		var elite: bool = (not is_leader) and lead_n == 0 and m_seen == 0
		if not is_leader:
			m_seen += 1
		var o: Vector2i = LP.off_of(u, i, n)
		field.add_child(_token(lane, i, u, is_leader, elite, world_from_off(o)))


func _to_field(w: Vector2) -> Vector2:
	return (w - half_rect().position) * S


func _from_field(p: Vector2) -> Vector2:
	return half_rect().position + p / S


func _token(lane: String, idx: int, u: Dictionary, is_leader: bool, elite: bool, w: Vector2) -> Control:
	var t := Control.new(); t.name = "Token_%s_%d" % [lane, idx]
	t.size = Vector2(TOKEN_HIT, TOKEN_HIT)
	t.position = _to_field(world_from_off(off_from_world(w))) - t.size * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	var ring := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#16202c")
	sb.border_color = Color("#ffd93d") if is_leader else Color("#9fb2c8")
	sb.set_border_width_all(3); sb.set_corner_radius_all(int(TOKEN * 0.5))
	ring.add_theme_stylebox_override("panel", sb)
	ring.position = (t.size - Vector2(TOKEN, TOKEN)) * 0.5; ring.size = Vector2(TOKEN, TOKEN)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(ring)
	var img := ""
	if is_leader:
		img = "res://assets/sprites/avatars/%s.png" % str(u.get("id", ""))
	else:
		img = "res://assets/sprites/%s" % Phase2Minion.minion_img(elite, str(u.get("role", "front")) == "back")
	if str(u.get("id", "x")) != "" and ResourceLoader.exists(img):
		var a := TextureRect.new(); a.texture = load(img)
		a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		a.position = ring.position + Vector2(6, 6); a.size = Vector2(TOKEN - 12, TOKEN - 12)
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(a)
	t.gui_input.connect(func(ev): _on_token_input(lane, idx, t, ev))
	return t


func _on_token_input(lane: String, idx: int, t: Control, ev: InputEvent) -> void:
	var field: Control = t.get_parent()
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		var local: Vector2 = field.get_global_transform().affine_inverse() * mb.global_position
		if mb.pressed:
			_drag = {"lane": lane, "idx": idx, "grab": (t.position + t.size * 0.5) - local, "from": mb.global_position}
			t.z_index = 5
		elif not _drag.is_empty():
			var o: Vector2i = _off_at(local)
			var moved: float = (mb.global_position - (_drag.get("from", mb.global_position) as Vector2)).length()
			commit(lane, idx, o)
			if moved >= TUT_DRAG_MIN:
				_tut_notify("formation_dragged")   # 教程 v3「拖动龟调整站位」: 松手且真拖了一段
			t.position = _to_field(world_from_off(o)) - t.size * 0.5
			t.z_index = 0
			_drag = {}
	elif ev is InputEventMouseMotion and not _drag.is_empty():
		var local2: Vector2 = field.get_global_transform().affine_inverse() * (ev as InputEventMouseMotion).global_position
		t.position = _to_field(world_from_off(_off_at(local2))) - t.size * 0.5


## 小场地里的一个点(加上按下时的抓取偏移) → 要存的偏移。
func _off_at(local: Vector2) -> Vector2i:
	var g: Vector2 = _drag.get("grab", Vector2.ZERO)
	return off_from_world(_from_field(local + g))


## 写进阵容格子并存档。★门禁也走这一个入口(不另写一份写法)。
func commit(lane: String, idx: int, o: Vector2i) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not (a.get(lane) is Array) or idx < 0 or idx >= (a[lane] as Array).size() or not (a[lane][idx] is Dictionary):
		return
	(a[lane][idx] as Dictionary)["off"] = LP.pack(o)
	GameState.dual_lineup = a
	GameState.save()


func _reset_all() -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	for lane in ["top", "bottom"]:
		if a.get(lane) is Array:
			for u in a[lane]:
				if u is Dictionary:
					(u as Dictionary).erase("off")
	GameState.dual_lineup = a
	GameState.save()
	_drop_dim()
	open()
