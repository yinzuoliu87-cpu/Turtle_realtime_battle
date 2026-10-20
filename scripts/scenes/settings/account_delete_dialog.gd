extends RefCounted
## account_delete_dialog.gd —— 设置 → 账号 →「删除账号」两步确认(2026-10-20 · App Store 审核指南 5.1.1(v))。
##
## 第一步: 写清删什么、什么保留(别人的录像里换成「已注销玩家」)、不可恢复 ⇒「取消」/「下一步」。
## 第二步: 再确认一次; 红键倒数 3 秒才可点(防误触, 不用输入文字 —— 手机上调出中文输入法比误触更糟)。
##   点了 ⇒「删除中」⇒ 成功: 本机已清理(`account_delete.wipe_local`), 调 `on_deleted()`(设置页据此回主菜单 ⇒ 首次进入流程);
##   失败: 状态行说原因, 本机一个字不动, 可以再点。
## ★皮照抄设置页「重置存档？」确认框(压暗底 + `panel-frame` 九宫格 + `UISkin.pixel_button`)。
## ★文案规矩(memory `fb-no-colloquial-copy`): 标题 / 按钮用名词或短指令, 说明用陈述句。

const NET := preload("res://scripts/net/account_delete.gd")

const BOX := Vector2(600.0, 340.0)
const COUNTDOWN_SEC := 3

## 【门禁按名字找的节点】
const LAYER := "AccountDeleteLayer"
const TITLE := "AccountDeleteTitle"
const BODY := "AccountDeleteBody"
const STATUS := "AccountDeleteStatus"
const BTN_CANCEL := "AccountDeleteCancel"
const BTN_NEXT := "AccountDeleteNext"
const BTN_CONFIRM := "AccountDeleteConfirm"

const T_STEP1 := "删除账号"
const T_STEP2 := "确认删除账号"
const BODY_STEP1 := ("删除内容：账号与玩家 ID · 云端存档 · 阵容快照\n排行榜与赛事记录 · 举报与反馈记录 · 本机存档。\n"
	+ "已完成对局的录像保留，其中的昵称与头像显示为「已注销玩家」。\n"
	+ "删除后无法恢复。")
const BODY_STEP2 := "账号删除后无法恢复，进度不可找回。"
const BODY_MAIL := "绑定的邮箱 %s 同时解除。"
const L_CANCEL := "取消"
const L_NEXT := "下一步"
const L_CONFIRM := "确认删除"
const MSG_SENDING := "删除中"
const MSG_OK := "账号已删除"   # devnote-ok: 玩家删号成功的结果提示(说的是玩家自己的账号, 不是开发状态)
const MSG := {
	NET.R_NET: "删除失败：网络不可用，账号未删除",
	NET.R_AUTH: "登录已失效，请先通过「邮箱登录」重新登录",
	NET.R_BLOCKED: "删除失败：当前版本不可提交，请更新后重试",
	NET.R_OFF: "删除失败：未连接服务器",
}


## 打开(第一步)。已经开着就不再开一个。`on_deleted()` 在删除成功后调一次。返回压暗层。
static func open(host: Control, email: String, on_deleted: Callable) -> Control:
	var old := host.get_node_or_null(LAYER)
	if old != null:
		return old as Control
	var dim := ColorRect.new()
	dim.name = LAYER
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ff5566")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#ff5566"))
	box.add_theme_stylebox_override("panel", rtex)
	var vs: Vector2 = host.get_viewport_rect().size
	box.position = (vs - BOX) * 0.5
	box.size = BOX
	dim.add_child(box)

	var ttl := Label.new()
	ttl.name = TITLE
	ttl.text = T_STEP1
	ttl.add_theme_font_size_override("font_size", 26)
	ttl.add_theme_color_override("font_color", Color("#ff5566"))
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)
	ttl.position = Vector2(0, 20); ttl.size = Vector2(BOX.x, 36)

	var body := Label.new()
	body.name = BODY
	body.text = BODY_STEP1
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color("#c9d6e2"))
	## 中文按字断行(理由见设置页 `_ask_reset` 同一处注释)。
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(body)
	body.position = Vector2(36, 72); body.size = Vector2(BOX.x - 72.0, 120)

	var st := Label.new()
	st.name = STATUS
	st.add_theme_font_size_override("font_size", 15)
	st.add_theme_color_override("font_color", Color("#ff9a9a"))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(st)
	st.position = Vector2(36, 196); st.size = Vector2(BOX.x - 72.0, 48)

	var cancel := _btn(box, BTN_CANCEL, L_CANCEL, UISkin.PX_SLATE, Vector2(40, 256))
	var nxt := _btn(box, BTN_NEXT, L_NEXT, UISkin.PX_RED, Vector2(310, 256))
	var ok := _btn(box, BTN_CONFIRM, L_CONFIRM, UISkin.PX_RED, Vector2(310, 256))
	ok.visible = false
	cancel.pressed.connect(func() -> void: dim.queue_free())

	## 第二步
	nxt.pressed.connect(func() -> void:
		ttl.text = T_STEP2
		body.text = BODY_STEP2 + (("\n" + BODY_MAIL % email) if email != "" else "")
		nxt.visible = false
		ok.visible = true
		ok.disabled = true
		var left := [COUNTDOWN_SEC]
		ok.text = "%s（%d）" % [L_CONFIRM, left[0]]
		var tm := Timer.new()
		tm.wait_time = 1.0
		tm.autostart = true
		box.add_child(tm)
		tm.timeout.connect(func() -> void:
			left[0] -= 1
			if left[0] > 0:
				ok.text = "%s（%d）" % [L_CONFIRM, left[0]]
				return
			ok.text = L_CONFIRM
			ok.disabled = false
			tm.queue_free()))

	ok.pressed.connect(func() -> void:
		ok.disabled = true
		cancel.disabled = true
		st.add_theme_color_override("font_color", Color("#c9d6e2"))
		st.text = MSG_SENDING
		NET.request(func(code: String) -> void:
			if not is_instance_valid(dim):
				return
			if code == NET.R_OK:
				st.text = MSG_OK
				if on_deleted.is_valid():
					on_deleted.call()
				return
			st.add_theme_color_override("font_color", Color("#ff9a9a"))
			st.text = str(MSG.get(code, MSG[NET.R_NET]))
			ok.disabled = false
			cancel.disabled = false))
	return dim


## 只给门禁用: 跳过 3 秒倒数(门禁不等真时钟)。
static func skip_countdown(dim: Control) -> void:
	var ok = dim.find_child(BTN_CONFIRM, true, false)
	if ok is Button:
		(ok as Button).disabled = false
		(ok as Button).text = L_CONFIRM
	for t in dim.find_children("*", "Timer", true, false):
		(t as Timer).queue_free()


static func _btn(box: Control, nm: String, label: String, accent: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	UISkin.pixel_button(b, accent, 4)
	box.add_child(b)
	b.position = pos
	b.size = Vector2(250, 56)
	return b
