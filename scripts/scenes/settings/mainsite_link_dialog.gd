extends RefCounted
## mainsite_link_dialog.gd —— 设置 → 账号 →「龟投账号」换号确认框(2026-11-08 · 方案书 20261105c §4.1:
##   「本机旧号不合并，切换前弹窗说明」)。
##
## 何时弹: 登录轮询回 confirmed + switched:true —— 这个龟投账号早已绑在另一个游戏账号上(`MainsiteLink.ST_SWITCH_ASK`)。
## 写清三件事: 该龟投账号绑着别的号 / 切换后本机登录那个号 / 本机当前进度不合并(切换前自动备份);
##   当前号没绑邮箱时再加一句「切换后无法恢复」(用户 09-24「没绑邮箱换设备就是丢档，这一点要在 UI 上说清楚」)。
## ★皮照抄设置页「存档冲突」框(压暗底 + `panel-frame` 九宫格 + 弹框里的按钮一律 `UISkin.card_button`, 用户 10-22)。
## ★文案口吻对齐「邮箱登录」框那句「本地进度将被替换（替换前自动备份）。」与删号框(标题只写状态, 正文数据式短句)。

const BOX := Vector2(600.0, 300.0)

## 【门禁按名字找的节点】
const LAYER := "MainsiteSwitchLayer"
const TITLE := "MainsiteSwitchTitle"
const BODY := "MainsiteSwitchBody"
const BTN_CANCEL := "MainsiteSwitchCancel"
const BTN_OK := "MainsiteSwitchOk"

const T_TITLE := "切换账号"
const B_LINKED := "该龟投账号已绑定其他游戏账号。"
const B_SWITCH := "切换后，本机将登录该账号。"
const B_NOMERGE := "本机当前进度不会合并到该账号（切换前自动备份）。"
const B_NOMAIL := "当前账号未绑定邮箱，切换后无法恢复。"
const L_CANCEL := "取消"
const L_OK := "确认切换"


## 正文(纯函数, 门禁直接读)。
static func body_text(has_mail: bool) -> String:
	var lines := [B_LINKED, B_SWITCH, B_NOMERGE]
	if not has_mail:
		lines.append(B_NOMAIL)
	return "\n".join(PackedStringArray(lines))


## 打开。已经开着就不再开一个。返回压暗层。`on_ok` / `on_cancel` 各在对应按钮按下后调一次(框先关)。
static func open(host: Control, has_mail: bool, on_ok: Callable, on_cancel: Callable) -> Control:
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
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffb454")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var tex := UISkin.nine("panel-frame.png", 20, sb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#ffb454"))
	box.add_theme_stylebox_override("panel", tex)
	## 设计框原点: 宽屏手机可见区比 1280 宽, 按设置页自己的那条公式居中(`_dlg_origin`); 别的宿主按视口居中。
	var org := Vector2.ZERO
	if host.has_method("_dlg_origin"):
		org = host.call("_dlg_origin") + (UIFrame.DESIGN - BOX) * 0.5
	else:
		org = (host.get_viewport_rect().size - BOX) * 0.5
	box.position = org.round()
	box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.name = TITLE
	ttl.text = T_TITLE
	ttl.add_theme_font_size_override("font_size", 24)
	UISkin.title_label(ttl, 24)        # 弹框标题统一 24 号像素标题字(docs/plans/20261027-UI美术规矩.md §4.1)
	ttl.add_theme_color_override("font_color", Color("#ffb454"))
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)
	ttl.position = Vector2(0, 20); ttl.size = Vector2(BOX.x, 36)

	var body := Label.new()
	body.name = BODY
	body.text = body_text(has_mail)
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color("#c9d6e2"))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## 中文按字断行(理由见设置页 `_ask_reset` 同一处注释)。
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(body)
	body.position = Vector2(36, 70); body.size = Vector2(BOX.x - 72.0, 116)

	var cancel := _btn(box, BTN_CANCEL, L_CANCEL, Vector2(40, 206))
	var ok := _btn(box, BTN_OK, L_OK, Vector2(310, 206))
	cancel.pressed.connect(func() -> void:
		dim.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	ok.pressed.connect(func() -> void:
		dim.queue_free()
		if on_ok.is_valid():
			on_ok.call())
	return dim


static func _btn(box: Control, nm: String, label: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.position = pos
	b.size = Vector2(250, 56)
	UISkin.card_button(b)
	box.add_child(b)
	b.position = pos
	b.size = Vector2(250, 56)
	return b
