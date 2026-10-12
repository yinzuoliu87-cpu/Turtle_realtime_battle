extends RefCounted
## feedback_panel.gd —— 设置页「问题反馈」弹框(2026-10-12)。上传见 `scripts/net/feedback_net.gd`。
##
## ★做法与皮照抄设置页「重置存档？」确认框: 压暗底 + `panel-frame` 金属九宫格 + `UISkin.pixel_button`;
##   类型四选一用 `UISkin.pixel_tab`(设置页分段钮同一套); 输入框用 `bar-frame` 凹槽(同 `_skin_edit`)。
## ★玩家只填两样: 类型 + 描述。版本 / 平台 / 设备 / 系统版本 / 账号 / 最近对局 / 最近报错自动附带。
## ★文案规矩(memory `fb-no-colloquial-copy`): 按钮 / 标题用名词或短指令, 提示用陈述句, 不拟人、不用语气词。
## 用法: `FeedbackPanel.open(host)` —— host 是设置页根节点(坐标系 1280×720 设计框)。

const NET := preload("res://scripts/net/feedback_net.gd")

const W := 1280.0
const H := 720.0
const BOX := Vector2(600.0, 440.0)

## 【门禁按名字找的节点】
const LAYER := "FeedbackLayer"
const EDIT := "FeedbackEdit"
const STATUS := "FeedbackStatus"
const SUBMIT := "FeedbackSubmit"
const CANCEL := "FeedbackCancel"
const KIND_PREFIX := "FeedbackKind"

const TITLE := "问题反馈"
const PLACEHOLDER := "问题描述（必填，500 字以内）"
const MSG_SENDING := "提交中"
const MSG_OK := "已提交"
const MSG_FAIL := "提交失败，请检查网络后重试"
## [代码, 界面文字]
const KINDS := [
	[NET.KIND_CRASH, "闪退 / 卡顿"],
	[NET.KIND_DISPLAY, "画面 / 显示"],
	[NET.KIND_GAMEPLAY, "玩法 / 数值"],
	[NET.KIND_OTHER, "其他"],
]


## 打开弹框。已经开着就不再开一个。返回压暗层。
static func open(host: Control) -> Control:
	var old := host.get_node_or_null(LAYER)
	if old != null:
		return old as Control
	var dim := ColorRect.new()
	dim.name = LAYER
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#5aa0ff"))
	box.add_theme_stylebox_override("panel", rtex)
	var home := Vector2(W / 2.0 - BOX.x / 2.0, H / 2.0 - BOX.y / 2.0)
	box.position = home; box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.text = TITLE
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.add_theme_color_override("font_color", Color("#cfe3ff"))
	ttl.position = Vector2(0, 18); ttl.size = Vector2(BOX.x, 32)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	## 类型: 2×2 分段钮(264×56 —— 长边 ≥200 过触摸线, 与设置页 `_SEG_W` 同一条理由)。
	var sel := [0]
	var tabs: Array = []
	for i in range(KINDS.size()):
		var b := Button.new()
		b.name = KIND_PREFIX + str(KINDS[i][0])
		b.text = str(KINDS[i][1])
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		var pos := Vector2(30.0 + float(i % 2) * 276.0, 64.0 + floorf(float(i) / 2.0) * 64.0)
		b.position = pos; b.size = Vector2(264, 56)
		UISkin.pixel_tab(b, i == 0)
		box.add_child(b)
		b.position = pos; b.size = Vector2(264, 56)
		tabs.append(b)
	for i in range(tabs.size()):
		var idx := i
		(tabs[i] as Button).pressed.connect(func() -> void:
			sel[0] = idx
			for j in range(tabs.size()):
				UISkin.pixel_tab(tabs[j], j == idx))

	var ed := TextEdit.new()
	ed.name = EDIT
	ed.placeholder_text = PLACEHOLDER
	ed.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ed.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	ed.add_theme_font_size_override("font_size", 16)
	_skin_edit(ed)
	ed.position = Vector2(30, 196); ed.size = Vector2(540, 128)
	box.add_child(ed)

	var st := Label.new()
	st.name = STATUS
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Color("#ff9a9a"))
	st.position = Vector2(30, 330); st.size = Vector2(430, 24)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(st)
	var cnt := Label.new()
	cnt.text = "0 / %d" % NET.MSG_MAX
	cnt.add_theme_font_size_override("font_size", 13)
	cnt.add_theme_color_override("font_color", Color("#7d93ac"))
	cnt.position = Vector2(470, 330); cnt.size = Vector2(100, 24)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(cnt)
	## 字数上限: TextEdit 没有 max_length ⇒ 超了就截回去。
	ed.text_changed.connect(func() -> void:
		if ed.text.length() > NET.MSG_MAX:
			ed.text = ed.text.left(NET.MSG_MAX)
			ed.set_caret_line(ed.get_line_count() - 1)
			ed.set_caret_column(ed.get_line(ed.get_line_count() - 1).length())
		cnt.text = "%d / %d" % [ed.text.length(), NET.MSG_MAX])
	## 手机上虚拟键盘会盖住下半屏 ⇒ 输入时把整块框往上提, 让输入框和两颗键露在上半屏。
	if OS.has_feature("mobile"):
		ed.focus_entered.connect(func() -> void: box.position = Vector2(home.x, 16.0 - 196.0))
		ed.focus_exited.connect(func() -> void: box.position = home)

	var cancel := Button.new()
	cancel.name = CANCEL
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.position = Vector2(40, 362); cancel.size = Vector2(250, 56)
	UISkin.pixel_button(cancel, UISkin.PX_SLATE, 4)
	cancel.pressed.connect(func() -> void: dim.queue_free())
	box.add_child(cancel)

	var ok := Button.new()
	ok.name = SUBMIT
	ok.text = "提交"
	ok.add_theme_font_size_override("font_size", 18)
	ok.position = Vector2(310, 362); ok.size = Vector2(250, 56)
	UISkin.pixel_button(ok, UISkin.PX_GOLD, 4)
	ok.pressed.connect(func() -> void:
		var err: String = NET.check_message(ed.text)
		if err != "":
			st.text = err
			st.add_theme_color_override("font_color", Color("#ff9a9a"))
			return
		ok.disabled = true
		st.text = MSG_SENDING
		st.add_theme_color_override("font_color", Color("#c9d6e2"))
		NET.submit(str(KINDS[int(sel[0])][0]), ed.text, func(sent: bool) -> void:
			if not is_instance_valid(st):
				return
			if sent:
				st.text = MSG_OK
				st.add_theme_color_override("font_color", Color("#7fe0b0"))
				ed.editable = false
			else:
				st.text = MSG_FAIL
				st.add_theme_color_override("font_color", Color("#ff9a9a"))
				ok.disabled = false))
	box.add_child(ok)
	return dim


## 输入框皮: `bar-frame` 凹槽, 边距与设置页 `_skin_edit` 同(从贴图量的 8 / 5)。
static func _skin_edit(e: TextEdit) -> void:
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#0e1726")
	fb.border_color = Color("#3c5570")
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(0)
	for slot in ["normal", "focus", "read_only"]:
		var sb := UISkin.nine("bar-frame.png", 8, fb)
		if sb is StyleBoxTexture:
			var stx := sb as StyleBoxTexture
			stx.set_texture_margin(SIDE_TOP, 5)
			stx.set_texture_margin(SIDE_BOTTOM, 5)
			stx.modulate_color = Color(1.02, 1.06, 1.0) if slot == "focus" else Color(0.66, 0.73, 0.84)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		e.add_theme_stylebox_override(slot, sb)
	e.add_theme_color_override("font_color", Color("#e8f0ff"))
	e.add_theme_color_override("font_readonly_color", Color("#a9b8c8"))
	e.add_theme_color_override("font_placeholder_color", Color("#7d93ac"))
	e.add_theme_color_override("caret_color", Color("#ffd93d"))
	e.add_theme_color_override("background_color", Color(0, 0, 0, 0))
