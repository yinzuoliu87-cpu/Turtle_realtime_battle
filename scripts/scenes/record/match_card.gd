extends RefCounted
## 对局卡的共享件 —— 战绩页(`RecordScene`)、周六赛况板(`GauntletBoardScene`)、
## 周日对阵图(`BracketMapScene`)三屏同一套: 卡框 / 斜面色块 / 龟头像 / 一方阵容 / VS / 「观看」像素按钮。
##
## 由来(2026-10-07 回放体验打磨第三轮, 用户「回放我说最重要的是周六周日啊，观看别人的啊」):
##   战绩页先按荒野乱斗 / 皇室战争 Battle Log 重做了对局卡; 周末两屏要同一种长相,
##   而不是各抄一份(memory fb-hand-rolled-copies-drift: 抄一次永远落后一次)。
## ★卡 = `slot-frame.png` 九宫格, 横幅 / 小方块 = 实心色块 + 右下 2px 暗边(像素斜面)。
## ★按钮 = `UISkin.pixel_button()`(2026-10-07 从大木牌换掉: 用户「按钮框能不能换一种呢，这不适合我们啊」,
##   参考 docs/plans/ref/20261007-按钮参考/)。

## 「观看」: 短边 84 ≥ 触控线 81(=44pt), 宽 150。
const WATCH_SIZE := Vector2(150, 84)
## 按钮语义色: 观看 / 回放 / 开始对战 = 金; 观赛(直播)= 红; 关闭 = 石板。
const BTN_WATCH := UISkin.PX_GOLD
const BTN_LIVE := UISkin.PX_RED
const BTN_CLOSE := UISkin.PX_SLATE
const AVATAR_PX := 56.0
const AVATAR_GAP := 4.0
const NAME_H := 20.0
## 头像节点名 —— 门禁按名字数头像。
const N_PORTRAIT := "Portrait"


## 卡框: `slot-frame.png`(57x57, 中心平色 + 四角金铆钉)。内边距 14 > 这张图画出来的边带(实测 6px)。
static func card_style(tint: Color = Color(0.70, 0.78, 0.92), mh: int = 14, mv: int = 12) -> StyleBox:
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.098, 0.133, 0.176, 1.0)
	fb.set_corner_radius_all(0)
	var st := UISkin.nine("slot-frame.png", 12, fb)
	if st is StyleBoxTexture:
		(st as StyleBoxTexture).modulate_color = tint
	st.content_margin_left = mh; st.content_margin_right = mh
	st.content_margin_top = mv; st.content_margin_bottom = mv
	return st


## 实心底(a=1) + 只描右/下两条暗边 —— 像素 UI 的斜面; 不落进「四边描边 + 半透底」的网页盒。
static func bevel(bg: Color, edge: Color, mh: int, mv: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = edge
	sb.content_margin_left = mh; sb.content_margin_right = mh
	sb.content_margin_top = mv; sb.content_margin_bottom = mv
	return sb


## 一只龟的头像。直角纯色块 + 1px 边, 不套九宫格(头像图四边没留透明边, 套框会压脸)。
## pid == "" ⇒ 空槽; 这时给了 `letter` 就在槽里写那一个字(对阵图里没头像数据的人: 名字首字, 不编造龟)。
static func avatar(pid: String, px: float = AVATAR_PX, flip: bool = false, dim: bool = false,
		letter: String = "") -> Control:
	var pc := PanelContainer.new()
	pc.name = N_PORTRAIT
	## ★同一个父节点下的同名兄弟会被引擎改成 @…@ 名 ⇒ 门禁按这个 meta 认头像, 不按名字。
	pc.set_meta(N_PORTRAIT, pid)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://assets/sprites/avatars/%s.png" % pid
	var has := pid != "" and ResourceLoader.exists(path)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a1422") if (has or letter != "") else Color("#0b111a")
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color("#6a5a34") if (has or letter != "") else Color("#26323e")
	if dim:
		sb.border_color = Color("#2a3946")
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(px, px)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if has:
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(px, px)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.flip_h = flip
		tex.texture = load(path)
		if dim:
			tex.modulate = Color(0.46, 0.52, 0.60)
		pc.add_child(tex)
	elif letter != "":
		var l := Label.new()
		l.text = letter.substr(0, 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(px * 0.5))
		l.add_theme_color_override("font_color", Color("#6f7f8e") if dim else Color("#c7b489"))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(l)
	else:
		var e := Control.new()
		e.custom_minimum_size = Vector2(px, px)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(e)
	return pc


## 一边: 名字在上, 三个头像在下。对手那边头像翻过来朝里(两边对望, 与对局顶栏同一个做法)。
## 没有阵容 ⇒ 画三个空槽(版式不跳)。`name_col` 给胜负着色。
static func side(who: String, lineup, flip: bool, name_node: String = "",
		px: float = AVATAR_PX, name_col: Color = Color("#e8f0f6"), dim: bool = false) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	if name_node != "":
		nm.name = name_node
	nm.text = who
	nm.custom_minimum_size = Vector2(px * 3.0 + AVATAR_GAP * 2.0, NAME_H)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if flip else HORIZONTAL_ALIGNMENT_LEFT
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", name_col)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var avs := HBoxContainer.new()
	avs.add_theme_constant_override("separation", int(AVATAR_GAP))
	avs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if flip:
		avs.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(avs)
	var ids: Array = []
	if lineup is Array:
		for pid in lineup:
			if ids.size() < 3:
				ids.append(str(pid))
	for i in range(3):
		avs.add_child(avatar(str(ids[i]) if i < ids.size() else "", px, flip, dim))
	return col


## 结果横幅: 实心色条(斜面), 左边大字(胜利 / 失败 / 谁获胜), 右边一行小字(时长 · 多久之前)。
static func banner(head: String, info: String, bg: Color, edge: Color, head_col: Color, info_col: Color,
		h: float = 34.0) -> Control:
	var bn := PanelContainer.new()
	bn.name = "ResultBanner"
	bn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bn.add_theme_stylebox_override("panel", bevel(bg, edge, 14, 0))
	bn.custom_minimum_size = Vector2(0, h)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bn.add_child(hb)
	var res := Label.new()
	res.name = "ResultText"
	res.text = head
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res.add_theme_font_size_override("font_size", 22)
	res.add_theme_color_override("font_color", head_col)
	res.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	res.add_theme_constant_override("outline_size", 4)
	res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res.clip_text = true
	res.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(res)
	var inf := Label.new()
	inf.name = "ResultInfo"
	inf.text = info
	inf.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inf.add_theme_font_size_override("font_size", 15)
	inf.add_theme_color_override("font_color", info_col)
	inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(inf)
	return bn


## 两边中间那个「VS」。
static func vs_label(h: float) -> Label:
	var vs := Label.new()
	vs.text = "VS"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	vs.custom_minimum_size = Vector2(44, h)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.add_theme_font_size_override("font_size", 26)
	vs.add_theme_color_override("font_color", Color("#ffd93d"))
	vs.add_theme_color_override("font_outline_color", Color("#2a1a00"))
	vs.add_theme_constant_override("outline_size", 5)
	vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return vs


## 大按钮(`UISkin.pixel_button`)。默认金色「观看」; 别的语义由调用方给 BTN_LIVE / BTN_CLOSE。
static func big_btn(text: String, node_name: String, sz: Vector2 = WATCH_SIZE,
		accent: String = BTN_WATCH, fs: int = 24) -> Button:
	var bt := Button.new()
	bt.name = node_name
	bt.text = text
	bt.custom_minimum_size = sz
	bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bt.focus_mode = Control.FOCUS_NONE
	bt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bt.add_theme_font_size_override("font_size", fs)
	UISkin.pixel_button(bt, accent, 5)
	return bt


## 居中的一块提示框(空态 / 出错): 金属大框 + 左边一枚现成像素图标(32→64 整 2 倍) + 一行主文 + 可选一行副文。
## 返回 {"panel", "icon", "title", "sub"}, 调用方改字 / 换图标 / 显隐。
## `width` = 框宽。★字的宽度要在这里给定 —— autowrap 的 Label 不知道自己多宽时按 0 宽折行,
##   最小高度会被撑成一列一个字那么高(实拍: 一句话的框撑满半屏)。
static func notice_panel(parent: Control, width: float = 620.0) -> Dictionary:
	var pc := PanelContainer.new()
	pc.name = "NoticePanel"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#121a27")
	fb.set_corner_radius_all(0)
	var st := UISkin.nine("panel-frame.png", 20, fb)
	st.content_margin_left = 30; st.content_margin_right = 34
	st.content_margin_top = 24; st.content_margin_bottom = 24
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size = Vector2(width, 126.0)
	parent.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(64, 64)
	ic.stretch_mode = TextureRect.STRETCH_SCALE
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var text_w: float = maxf(120.0, width - 30.0 - 34.0 - 64.0 - 20.0)
	var t := Label.new()
	t.custom_minimum_size = Vector2(text_w, 0)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#e8f0f6"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var s := Label.new()
	s.custom_minimum_size = Vector2(text_w, 0)
	s.add_theme_font_size_override("font_size", 15)
	s.add_theme_color_override("font_color", Color("#9fb0c4"))
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(s)
	return {"panel": pc, "icon": ic, "title": t, "sub": s}


## 给提示框填字 + 图标(`assets/sprites/ui/` 里现成的那几枚)。图标不在就藏掉, 只留字。
static func notice_set(n: Dictionary, title: String, sub: String, icon: String) -> void:
	(n["title"] as Label).text = title
	(n["sub"] as Label).text = sub
	(n["sub"] as Label).visible = sub != ""
	var p := "res://assets/sprites/ui/%s.png" % icon
	var ic := n["icon"] as TextureRect
	ic.visible = icon != "" and ResourceLoader.exists(p)
	if ic.visible:
		ic.texture = load(p)
