extends RefCounted
## player_menu.gd —— 玩家菜单「举报昵称 / 拉黑」(2026-10-20 · App Store 审核指南 1.2)。
##
## ★全项目只有这一个菜单: 排行榜 / 周六赛况板 / 周日对阵图 / 对局顶栏点到别人, 弹的都是它(每屏只负责「点哪里打开」)。
##   参考: 皇室战争 / 荒野乱斗点排行榜上的人 ⇒ 一张小卡(名字 + 玩家 ID + 几颗操作键)。
## ★举报 ⇒ `report_net.gd`(服务端记一行, 管理员处理: 方案书 docs/plans/20261020-AppStore上架.md「昵称举报处理」)。
## ★拉黑 ⇒ `blocklist.gd`(只在本机; 对方昵称显示成默认昵称; 设置 → 账号 →「黑名单」里可移出)。
## ★自己(玩家 ID == 我的)不弹: 举报 / 拉黑自己没有意义。没有合法玩家 ID 的(待定 / 轮空 / 已注销)不弹。
## ★文案规矩(memory `fb-no-colloquial-copy`): 按钮 / 标题用名词或短指令, 提示用陈述句。
## 用法: `PlayerMenu.open(host, {"name": 原名, "tag": "#XXXXXX", "ctx": ReportNet.CTX_*}, on_change)`
##   on_change() 在拉黑 / 移出之后调一次 —— 宿主据此重画名字。

const RPT := preload("res://scripts/net/report_net.gd")
const BL := preload("res://scripts/util/blocklist.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const BOX := Vector2(480.0, 284.0)

## 【门禁按名字找的节点】
const LAYER := "PlayerMenuLayer"
const TITLE := "PlayerMenuTitle"
const STATUS := "PlayerMenuStatus"
const BTN_REPORT := "PlayerMenuReport"
const BTN_BLOCK := "PlayerMenuBlock"
const BTN_CLOSE := "PlayerMenuClose"
## 各屏的入口节点名(门禁按它数「入口在不在」)。
const ENTRY := "PlayerMenuEntry"

const L_REPORT := "举报昵称"
const L_BLOCK := "拉黑"
const L_UNBLOCK := "移出黑名单"
const L_CLOSE := "关闭"
const L_ENTRY := "举报 / 拉黑"
const MSG_SENDING := "提交中"
const MSG := {
	RPT.R_OK: "已举报",
	RPT.R_DUP: "24 小时内已举报过该玩家",
	RPT.R_LIMIT: "今日举报次数已达上限",
	RPT.R_SELF: "无法举报自己",
	RPT.R_FAIL: "举报失败，请检查网络后重试",
}
const MSG_BLOCKED := "已拉黑 · 昵称显示为默认昵称"
const MSG_UNBLOCKED := "已移出黑名单"
const MSG_FULL := "黑名单已满"


## 这个人能不能打开菜单(合法玩家 ID、不是我自己)。
static func can_open(tag: String) -> bool:
	return _P2.tag_valid(tag) and tag != my_tag()


static func my_tag() -> String:
	return str(preload("res://scripts/net/backend.gd").my_tag())


## 打开菜单。不该开(自己 / 没有玩家 ID)⇒ 返回 null。已经开着 ⇒ 返回那一个。
static func open(host: Node, info: Dictionary, on_change: Callable = Callable()) -> Node:
	var tag := str(info.get("tag", ""))
	if host == null or not host.is_inside_tree() or not can_open(tag):
		return null
	var old := host.get_node_or_null(LAYER)
	if old != null:
		return old
	var name := str(info.get("name", "")).strip_edges()
	var ctx := str(info.get("ctx", ""))
	var layer := CanvasLayer.new()
	layer.name = LAYER
	layer.layer = 90
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			layer.queue_free())

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#5aa0ff"))
	box.add_theme_stylebox_override("panel", rtex)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var vs: Vector2 = host.get_viewport().get_visible_rect().size
	box.position = (vs - BOX) * 0.5
	box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.name = TITLE
	ttl.text = BL.shown_name(name, tag)
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#f4f8ff"))
	ttl.clip_text = true
	ttl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)
	ttl.position = Vector2(24, 20); ttl.size = Vector2(BOX.x - 48.0, 34)
	var tl := Label.new()
	tl.text = "玩家 ID %s" % tag
	tl.add_theme_font_size_override("font_size", 14)
	tl.add_theme_color_override("font_color", Color("#8fa6bd"))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tl)
	tl.position = Vector2(24, 56); tl.size = Vector2(BOX.x - 48.0, 22)

	var st := Label.new()
	st.name = STATUS
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Color("#c9d6e2"))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(st)
	st.position = Vector2(24, 86); st.size = Vector2(BOX.x - 48.0, 24)

	var rep := _btn(box, BTN_REPORT, L_REPORT, UISkin.PX_SLATE, Vector2(40, 122))
	var blk := _btn(box, BTN_BLOCK, L_UNBLOCK if BL.is_blocked(tag) else L_BLOCK, UISkin.PX_SLATE, Vector2(250, 122))
	var cl := _btn(box, BTN_CLOSE, L_CLOSE, UISkin.PX_SLATE, Vector2(145, 200))
	## 原名(拉黑后屏幕上显示的是默认名, 举报要的是原名)。
	rep.pressed.connect(func() -> void:
		if name == "":
			st.text = MSG[RPT.R_FAIL]
			return
		rep.disabled = true
		st.text = MSG_SENDING
		RPT.report(tag, name, ctx, func(code: String) -> void:
			if not is_instance_valid(st):
				return
			st.text = str(MSG.get(code, MSG[RPT.R_FAIL]))
			## 成功 / 已举报过 / 上限 ⇒ 这颗键不再可点; 失败 ⇒ 可以再试。
			rep.disabled = code != RPT.R_FAIL))
	blk.pressed.connect(func() -> void:
		if BL.is_blocked(tag):
			BL.remove(tag)
			blk.text = L_BLOCK
			st.text = MSG_UNBLOCKED
			ttl.text = name
		elif BL.add(tag, name):
			blk.text = L_UNBLOCK
			st.text = MSG_BLOCKED
			ttl.text = BL.shown_name(name, tag)
		else:
			st.text = MSG_FULL
		if on_change.is_valid():
			on_change.call())
	cl.pressed.connect(func() -> void: layer.queue_free())
	return layer


static func _btn(box: Control, nm: String, label: String, accent: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	UISkin.pixel_button(b, accent, 4)
	box.add_child(b)
	b.position = pos
	b.size = Vector2(190, 56)
	return b


## 菜单挂在哪: 当前场景根(入口按钮会随宿主重画被释放, 菜单不能跟着它走)。
static func host_of(n: Node) -> Node:
	var t := n.get_tree()
	if t != null and t.current_scene != null:
		return t.current_scene
	return n


## 入口 ①: 一块透明热区(排行榜行 / 对局顶栏名字这类「点名字」的地方)。返回那颗按钮; 不该开的人返回 null。
static func hotspot(parent: Control, rect: Rect2, info: Dictionary, on_change: Callable = Callable()) -> Button:
	if not can_open(str(info.get("tag", ""))):
		return null
	var b := Button.new()
	b.name = ENTRY
	b.set_meta("tag", str(info.get("tag", "")))
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	## 透传: 盖在可滚动的列表上时不吃掉拖动(同 GauntletBoardScene._hit 的取舍)。
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.position = rect.position
	b.size = rect.size
	b.pressed.connect(func() -> void: open(host_of(b), info, on_change))
	parent.add_child(b)
	return b


## 入口 ②: 一颗小按钮「举报 / 拉黑」(对阵图弹窗 / 赛况板选中某人时)。不该开的人返回 null。
static func entry_button(info: Dictionary, on_change: Callable = Callable(), size: Vector2 = Vector2(200, 48)) -> Button:
	if not can_open(str(info.get("tag", ""))):
		return null
	var b := Button.new()
	b.name = ENTRY
	b.set_meta("tag", str(info.get("tag", "")))
	b.text = L_ENTRY
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	UISkin.pixel_button(b, UISkin.PX_SLATE, 3)
	b.custom_minimum_size = size
	b.size = size
	b.pressed.connect(func() -> void: open(host_of(b), info, on_change))
	return b
