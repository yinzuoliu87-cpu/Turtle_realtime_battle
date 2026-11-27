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
const _TapSlop := preload("res://scripts/util/tap_slop.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")

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
	if host.Phase2Types.TIER_TABLE.has(tname) or host.Phase2Types.TAG_ONLY.has(tname):   # 特殊羁绊(筹码)也走同一版式: 同类装备在标题下
		_show_table(tname, tiers, color, members)
		return
	host._add_text(130, 46, tname, 32, color, 0.0, 0.5, true)
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	## 两件事各占一行(文案规则 2: 不拿「·」把两个读数拼成一行)
	## 特殊羁绊(筹码, 用户 11-27): 没有档位 ⇒ 不写「激活 N 件」
	host._add_text(130, 80, Lang.t("激活：%s 件") % thresh if not tiers.is_empty() else Lang.t("无羁绊加成"), 16, color, 0.0, 0.5, true)
	host._add_text(130, 104, Lang.t("现有装备：%d 件") % members.size(), 16, color, 0.0, 0.5, true)

	## 逐档: 左列「N 件」, 右列一条一行。
	var y := 132.0
	host._add_text(20, y, "羁绊效果" if not tiers.is_empty() else "说明", 17, "#58d3ff", 0.0, 0.0, true)   # 没有档位的羁绊(筹码)不写「羁绊效果」
	y += 32.0
	## ★2026-10-13 机制只写一次(云顶羁绊小卡): TYPE_INTRO 一条一行, 下面逐档只列变化的数字。
	var intro_w: float = float(host.DETAIL_W) - 40.0
	for il in host.Phase2Types.intro_lines(tname):
		var it := RichTextLabel.new()
		it.bbcode_enabled = true; it.fit_content = true; it.scroll_active = false
		it.position = Vector2(20, y)
		it.custom_minimum_size = Vector2(intro_w, 0)
		it.add_theme_font_size_override("normal_font_size", BODY_PX)
		it.add_theme_color_override("default_color", Color("#e8f2ff"))
		it.add_theme_constant_override("line_separation", 4)
		it.text = SummonCodex.linkify(line_bb(_normalize(SkillText.render_consts(str(il)))))
		SummonCodex.attach_links(it, func(sid: String) -> void: host._codex_detail.open_entry({"k": "summon", "id": sid}))
		it.set_meta("codex_syn_intro", tname)
		host.detail.add_child(it)
		y += maxf(22.0, it.get_combined_minimum_size().y) + LINE_GAP + 2.0
	if not host.Phase2Types.intro_lines(tname).is_empty():
		y += TIER_GAP
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
		var badge_lbl = host._add_text(20, y + 11.0, Lang.t("%d 件") % th, 18, color, 0.0, 0.5, true)
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


## ── 逐档一句版式(2026-11-27 原型; Phase2Types.TIER_TABLE 有这个羁绊才走; 表格版用户看过说不清楚, 已改) ──
## 用户 11-27 看剑这页: 我提的四条 —— ① 同一句话每档重写一遍 ⇒ 机制只写一次 + 件数 × 数字表(云顶「(3) … (6) …」);
##   ② 规则细节挪到表下灰字; ③ 同类装备挪到标题下(不用滚); ④ 删掉有歧义的「现有装备：N 件」与「激活：…」(表里的 (3)(6)(9) 就是激活件数)。
const TBL_TIER_W := 44.0
const TBL_HEAD_H := 30.0
const TBL_ROW_H := 36.0
const TOP_CELL_W := 86.0          # 10 件一行放得下((900 - 40) / 86 = 10)

## 一档那一句的显示值: [k] 换成第 k 档下标; {STAT:键} 读 TYPES.stats[k](STATx2 双倍, STATpct 小数按百分数); 其余 {C:} 读代码常量。
## ★先换语言再填数(英文模板里同样带这些占位)。
static func table_cell(tname: String, tpl: String, k: int) -> String:
	var s: String = Lang.t(tpl).replace("[k]", "[%d]" % k)
	var stats: Array = (_P2T.TYPES.get(tname, {}) as Dictionary).get("stats", [])
	var rx := RegEx.create_from_string("[{]STAT(x2|pct)?:([A-Za-z_]+)[}]")
	for m in rx.search_all(s):
		var v: float = float((stats[k] as Dictionary).get(m.get_string(2), 0)) if k < stats.size() else 0.0
		match m.get_string(1):
			"x2": v *= 2.0
			"pct": v *= 100.0
		s = s.replace(m.get_string(0), _num(v))
	return SkillText.render_consts(s)


static func _num(v: float) -> String:
	var r: float = snappedf(v, 0.01)
	return str(int(r)) if is_equal_approx(r, roundf(r)) else String.num(r, 2).rstrip("0").rstrip(".")


## 第 k 档那一句的模板(rows 逐档写; 只有 row 的 = 各档同一句)。
static func row_tpl(tb: Dictionary, k: int) -> String:
	var rows: Array = tb.get("rows", [])
	if k < rows.size():
		return str(rows[k])
	return str(tb.get("row", ""))


func _show_table(tname: String, tiers: Array, color: String, members: Array) -> void:
	var tb: Dictionary = host.Phase2Types.TIER_TABLE.get(tname, {"lines": host.Phase2Types.intro_lines(tname)})
	var W: float = float(host.DETAIL_W)
	if tiers.is_empty():   # 特殊羁绊: 名字下一行「无羁绊加成」
		host._add_text(130, 50, tname, 32, color, 0.0, 0.5, true)
		host._add_text(130, 86, Lang.t("无羁绊加成"), 16, color, 0.0, 0.5, true)
	else:
		host._add_text(130, 66, tname, 32, color, 0.0, 0.5, true)
	## 同类装备: 标题下一排(9 件一行放得下)
	var y := 126.0
	var per_row: int = maxi(1, int((W - 40.0) / TOP_CELL_W))
	for i in range(members.size()):
		var cx: float = 20.0 + TOP_CELL_W * float(i % per_row) + TOP_CELL_W / 2.0
		_member_tile(members[i], cx, y + CELL_H * float(int(i / per_row)), 13)   # 格宽 86: 6 个字 × 13 = 78, 两个长名字之间留得出空
	y += CELL_H * float(int(ceil(float(members.size()) / float(per_row)))) + 4.0
	host._add_rect(W / 2.0, y, W - 40.0, 1, color, 0.25)
	y += 16.0
	## 11-27 用户「可以不需要羁绊效果这四个字」: 不放小标题, 分隔线下面直接是机制句(省一行, 同类装备排两行时也放得下)
	## 机制: 一条一行, 不带随件数变化的数
	for ln in tb.get("lines", []):
		var it := RichTextLabel.new()
		it.bbcode_enabled = true; it.fit_content = true; it.scroll_active = false
		it.position = Vector2(20, y)
		it.custom_minimum_size = Vector2(W - 40.0, 0)
		it.add_theme_font_size_override("normal_font_size", BODY_PX)
		it.add_theme_color_override("default_color", Color("#e8f2ff"))
		it.text = SummonCodex.linkify(line_bb(SkillText.render_consts(str(ln))))   # 【百夫长】【亡魂】点了跳角色页(11-27)
		SummonCodex.attach_links(it, func(sid: String) -> void: host._codex_detail.open_entry({"k": "summon", "id": sid}))
		it.set_meta("codex_syn_intro", tname)
		host.detail.add_child(it)
		y += maxf(22.0, it.get_combined_minimum_size().y) + LINE_GAP + 2.0
	y += 10.0
	if tiers.is_empty():
		return
	## 逐档: 每档一行「(3) 一句」(云顶羁绊卡的写法; 不做表格)
	host._add_rect(W / 2.0, y, W - 40.0, 1, color, 0.25)
	y += 10.0
	for k in range(tiers.size()):
		var tl = host._add_text(20.0, y + 11.0, "(%d)" % int(tiers[k]), 18, color, 0.0, 0.5, true)
		if tl != null:
			tl.set_meta("codex_syn_tier", int(tiers[k]))
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
		rt.position = Vector2(20.0 + TBL_TIER_W, y)
		rt.custom_minimum_size = Vector2(W - 40.0 - TBL_TIER_W, 0)
		rt.add_theme_font_size_override("normal_font_size", BODY_PX)
		rt.add_theme_color_override("default_color", Color("#e8f2ff"))
		rt.text = table_cell(tname, row_tpl(tb, k), k).replace("[", "[lb]")
		rt.set_meta("codex_syn_line", int(tiers[k]))
		host.detail.add_child(rt)
		y += maxf(TBL_ROW_H, rt.get_combined_minimum_size().y + 12.0)
	host._add_rect(W / 2.0, y, W - 40.0, 1, color, 0.25)
	## 规则细节: 最后灰色小字
	var note: String = str(tb.get("note", ""))
	if note != "":
		y += 12.0
		var nt := RichTextLabel.new()
		nt.bbcode_enabled = true; nt.fit_content = true; nt.scroll_active = false
		nt.position = Vector2(20, y)
		nt.custom_minimum_size = Vector2(W - 40.0, 0)
		nt.add_theme_font_size_override("normal_font_size", 14)
		nt.add_theme_color_override("default_color", Color("#8a93a0"))
		nt.text = SkillText.render_consts(note).replace("[", "[lb]")
		nt.set_meta("codex_syn_note", tname)
		host.detail.add_child(nt)


func _member_tile(m: Dictionary, cx: float, top: float, name_px: int = NAME_PX) -> void:
	var eid: String = str(m.get("id", ""))
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#12202a")
	fb.border_color = Color("#5a6b80")
	fb.set_border_width_all(2)
	var tile := Panel.new()
	## 11-27 用户「体现不出它的那个稀有度…这个框得想办法做呀…原本这个框太丑了」: 按费用换框(1 灰 / 2 绿 / 3 蓝 / 4 紫 / 5 金,
	##   右下角费用数字, 4、5 费底光, 5 费金角钉 + 宝石; tools/assetgen/ase/equip_cost_frame.lua), 32 像素原图 2 倍显示
	var cost: int = clampi(int(m.get("cost", 1)), 1, 5)
	var frame_path: String = "res://assets/sprites/ui/equip-frame-c%d.png" % cost
	var frame_sb: StyleBox = null
	if ResourceLoader.exists(frame_path):
		var st := StyleBoxTexture.new()
		st.texture = load(frame_path)
		frame_sb = st
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.set_meta("codex_syn_cost", cost)
	tile.position = Vector2(cx - TILE / 2.0, top)
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.size = Vector2(TILE, TILE)
	var tint := Color(1, 1, 1) if frame_sb != null else Color(0.80, 0.86, 0.95)
	tile.add_theme_stylebox_override("panel", frame_sb if frame_sb != null else UISkin.slot(fb, tint))
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
	var nm = host._add_text(cx, top + TILE + 14.0, str(m.get("name", "?")), name_px, "#cdd6e0", 0.5, 0.5)
	if nm != null:
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 点选判定与左栏列表行同一套(TapSlop): 松手且手指没挪远才算点(大位移 = 在滑动)。
	## ★2026-10-31 位移按画布全局坐标量: 原来量格子自己的局部坐标, 格子跟着手指一起滚 ⇒ 快甩时被当成点。
	var tap_st := _TapSlop.new()
	tile.gui_input.connect(func(ev: InputEvent) -> void:
		if tap_st.is_tap(tile, ev):
			open_equip(eid))
	tile.mouse_entered.connect(func() -> void:
		var sb = tile.get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			(sb as StyleBoxTexture).modulate_color = Color(1.3, 1.3, 1.3, 1.0))
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
