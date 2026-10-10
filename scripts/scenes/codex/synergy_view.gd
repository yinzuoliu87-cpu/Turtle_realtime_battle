class_name CodexSynergyView
extends RefCounted
## 图鉴·羁绊页(2026-10-10 重排, 用户「图鉴排版现在就修」)。
##
## 参考: docs/plans/ref/20261006-云顶装备弹窗/3-tft手游-点羁绊弹小卡.png —— 云顶点羁绊弹的小卡:
##   名字 → 一档一行「(3) … / (5) …」→ 成员头像一排。
## 原来这一页是**一整堵字墙**: 每档把 5~6 条【子机制】用「 · 」串成一行, 混着半角「, ( ) ;」、
##   「→」与「同上」, 头顶还有一行和大标题重复的「装备羁绊」副标, 成员装备只是一列名字(看不出能点)。
## 现在:
##   · 抬头 = 图标框 + 名字 + 激活档位(副标「装备羁绊」删掉)
##   · 一档一行: 左列「N 件」, 右列把那一档的子机制**拆成一条一行**(【专名】走高亮色)
##   · 成员 = 装备图标格(槽框皮 + 名字), 点一下跳到那件装备的图鉴页
## 文案事实源仍是 Phase2Types.TIER_DESCS —— 这里**只改显示**(拆行 / 半角标点转全角 / 「同上」展开),
##   一个字都不改源文案。

const TIER_COL_W := 76.0         # 左列「N 件」的宽
const BULLET_GAP := 14.0         # 小方点到正文的距离
const LINE_GAP := 4.0            # 同一档内两条子机制之间
const TIER_GAP := 14.0           # 两档之间(中间画一条细线)
const BODY_PX := 16
const KEY_COLOR := "#ffd93d"     # 【专名】高亮色(与龟页技能名同一个金)
const TILE := 64.0               # 成员图标格边长(槽框 slot-frame 的最小可用尺寸是 40)
const TILE_ICON := 44.0
const CELL_W := 100.0            # 一格的占宽(名字最长 6 个字 × 14px = 84)
const CELL_H := 96.0
const NAME_PX := 14

var host
var _view_ref: WeakRef   # CodexDetail(拿 _type_members); 弱引用 —— 它反过来持有本对象, 强引用会成环泄漏

func _init(h, v) -> void:
	host = h
	_view_ref = weakref(v)


## ── 显示用的拆行与标点归一(纯函数, 测试直接调) ──
## 一档的原文 → 若干条短行。
##   ① 按「 · 」(两侧带空格)拆 —— 「本场累积·跨路保留」这种不带空格的是词内间隔号, 不拆;
##   ② 半角标点 → 全角(源文案通篇是半角「, ; ( ) :」夹着全角「、」, 混排);
##   ③ 「 → 」读作因果, 换成「，」;
##   ④ 「【X】同上」「X同上」展开成上一档同名那一条(prev 由调用方逐档传入)。
static func split_tier(raw: String, prev_lines: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	for part in raw.split(" · ", false):
		var s: String = _normalize(str(part).strip_edges())
		if s == "":
			continue
		if s.ends_with("同上"):
			var key: String = s.trim_suffix("同上").replace("【", "").replace("】", "").strip_edges()
			for pl in prev_lines:
				if key != "" and key_of(pl) == key:
					s = pl
					break
		out.append(s)
	return out


## 一条子机制的【专名】(没有就 "")。「【怒气】冲击波 6%」→「怒气」。
static func key_of(line: String) -> String:
	if not line.begins_with("【"):
		return ""
	var e: int = line.find("】")
	return line.substr(1, e - 1) if e > 1 else ""


static func _normalize(s: String) -> String:
	s = s.replace(" → ", "，").replace("→", "，")
	s = s.replace(", ", "，").replace(",", "，")
	s = s.replace("; ", "；").replace(";", "；")
	s = s.replace(": ", "：")
	s = s.replace("(", "（").replace(")", "）")
	return s


## 一条 → BBCode: 【专名】高亮, 其余正文色。
static func line_bb(line: String) -> String:
	var esc: String = line.replace("[", "[lb]")
	var k: String = key_of(line)
	if k == "":
		return esc
	var head: String = "【%s】" % k
	return "[color=%s]%s[/color]%s" % [KEY_COLOR, head, esc.substr(head.length())]


func show(item: Dictionary) -> void:
	host._clear_detail()
	var tname: String = str(item.get("_type", ""))
	var def: Dictionary = host.Phase2Types.TYPES.get(tname, {})
	var color: String = host._type_color(tname)
	var icon: String = host._type_icon(tname)
	var tiers: Array = def.get("tiers", [])
	var members: Array = _view_ref.get_ref()._type_members(tname)

	## 抬头: 类型色框 + 32×32 像素图按 2x = 64 画(只有整数倍保得住像素网格) + 名字 + 激活档位。
	host._add_rect(60, 66, 90, 90, "#12202a", 0.55, color, 2.0, 0.9)
	if icon != "":
		var badge = host._add_image(60, 66, icon, 64, 64, true)
		if badge != null:
			badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	host._add_text(130, 46, tname, 32, color, 0.0, 0.5, true)
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	host._add_text(130, 88, "激活 %s 件   ·   现有装备 %d 件" % [thresh, members.size()], 16, color, 0.0, 0.5, true)

	## 逐档: 左列「N 件」, 右列一条一行。
	var y := 132.0
	host._add_text(20, y, "羁绊效果", 17, "#58d3ff", 0.0, 0.0, true)
	y += 32.0
	var descs: Array = host.Phase2Types.TIER_DESCS.get(tname, [])
	var prev := PackedStringArray()
	var body_x: float = 20.0 + TIER_COL_W
	var body_w: float = float(host.DETAIL_W) - body_x - 20.0 - BULLET_GAP
	for i in range(descs.size()):
		var raw: String = SkillText.render_consts(str(descs[i]))
		if raw.strip_edges() == "":
			continue
		var lines: PackedStringArray = split_tier(raw, prev)
		prev = lines
		if i > 0:
			host._add_rect(float(host.DETAIL_W) / 2.0, y - TIER_GAP / 2.0, float(host.DETAIL_W) - 40.0, 1, color, 0.25)
		var th: int = int(tiers[i]) if i < tiers.size() else 0
		var badge_lbl = host._add_text(20, y + 11.0, "%d 件" % th, 18, color, 0.0, 0.5, true)
		if badge_lbl != null:
			badge_lbl.set_meta("codex_syn_tier", th)
		var ly: float = y
		for ln in lines:
			host._add_rect(body_x + 3.0, ly + 12.0, 4, 4, "#8fa3b8", 1.0)
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
			rt.position = Vector2(body_x + BULLET_GAP, ly)
			rt.custom_minimum_size = Vector2(body_w, 0)
			rt.add_theme_font_size_override("normal_font_size", BODY_PX)
			rt.add_theme_color_override("default_color", Color("#e8f2ff"))
			rt.add_theme_constant_override("line_separation", 4)
			rt.text = line_bb(ln)
			rt.set_meta("codex_syn_line", th)
			host.detail.add_child(rt)
			ly += maxf(22.0, rt.get_combined_minimum_size().y) + LINE_GAP
		y = ly + TIER_GAP

	## 成员装备: 图标格(与背包/商店同一张槽框), 点一下跳那件装备的图鉴页。
	y += 6.0
	host._add_text(20, y, "同类装备", 17, "#58d3ff", 0.0, 0.0, true)
	y += 32.0
	var per_row: int = maxi(1, int((float(host.DETAIL_W) - 40.0) / CELL_W))
	for i in range(members.size()):
		var m: Dictionary = members[i]
		var cx: float = 20.0 + CELL_W * float(i % per_row) + CELL_W / 2.0
		var top: float = y + CELL_H * float(int(i / per_row))
		_member_tile(m, cx, top)


func _member_tile(m: Dictionary, cx: float, top: float) -> void:
	var eid: String = str(m.get("id", ""))
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#12202a")
	fb.border_color = Color("#5a6b80")
	fb.set_border_width_all(2)
	var tile := Panel.new()
	tile.position = Vector2(cx - TILE / 2.0, top)
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.size = Vector2(TILE, TILE)
	var tint := Color(0.80, 0.86, 0.95)
	tile.add_theme_stylebox_override("panel", UISkin.slot(fb, tint))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS   # 拖动透传给详情 ScrollContainer(手机能滑)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.set_meta("codex_syn_member", eid)
	host.detail.add_child(tile)
	var img: String = str(m.get("img", ""))
	var path: String = ("res://assets/sprites/" + img) if img.ends_with(".png") else ""
	if path != "" and ResourceLoader.exists(path):
		var tr = host._add_image(cx, top + TILE / 2.0, path, TILE_ICON, TILE_ICON, true)
		if tr != null:
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm = host._add_text(cx, top + TILE + 14.0, str(m.get("name", "?")), NAME_PX, "#cdd6e0", 0.5, 0.5)
	if nm != null:
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 点选判定与左栏列表行同一套: 按下记位置, 松开位移 < 14 才算点(大位移 = 在滑动)。
	var press := [Vector2.ZERO]
	tile.gui_input.connect(func(ev: InputEvent) -> void:
		var down: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and ev.pressed)
		var up: bool = (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and not ev.pressed)
		if down:
			press[0] = ev.position
		elif up and ev.position.distance_to(press[0]) < 14.0:
			open_equip(eid))
	tile.mouse_entered.connect(func() -> void:
		var sb = tile.get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			(sb as StyleBoxTexture).modulate_color = Color(1.45, 1.38, 1.18, 1.0))
	tile.mouse_exited.connect(func() -> void:
		var sb2 = tile.get_theme_stylebox("panel")
		if sb2 is StyleBoxTexture:
			(sb2 as StyleBoxTexture).modulate_color = tint)


## 跳到某件装备的图鉴页 —— 走页签切换 + 左栏选中那两个既有入口(与点页签、点列表行同一条路)。
func open_equip(eid: String) -> bool:
	host._switch_tab("equips")
	var items: Array = host._items
	for i in range(items.size()):
		var it = items[i]
		if it is Dictionary and str((it as Dictionary).get("id", "")) == eid:
			host._select(i)
			return true
	return false
