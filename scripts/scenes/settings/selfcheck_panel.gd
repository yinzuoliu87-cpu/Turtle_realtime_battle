extends RefCounted
## selfcheck_panel.gd —— 设置页隐藏的「设备自检」弹框(2026-10-19 · 诊断用)。本体见 `scripts/referee/device_selfcheck.gd`。
## 入口: 设置页底部版本号那一行连点 TAPS 次(`SettingsScene._footer`)。不在任何按钮上露出。
##
## ★皮与「问题反馈」弹框同一套: 压暗底 + `panel-frame` 金属九宫格 + `UISkin.pixel_button`(像素实心钮, 不用擂台金木框)。
## ★战斗场挂在一块**不显示、不渲染**的 SubViewport 下跑(玩家看到的只有进度与每个场景的一致 / 不一致)。
## ★文案: 名词 / 短指令, 不拟人、不加语气词(memory `fb-no-colloquial-copy`)。
## ★压暗层吃掉全部点击 ⇒ 跑的时候点不到返回键离开本页; 想停就点「取消」(当前场景下一帧就收手, 现场照样还原)。

const W := 1280.0
const BOX := Vector2(640.0, 440.0)
const TAPS := 5
const TAP_WINDOW_MS := 3000

## 【门禁按名字找的节点】
const LAYER := "SelfcheckLayer"
const HOST := "SelfcheckHost"
const STATUS := "SelfcheckStatus"
const GRID := "SelfcheckGrid"
const START := "SelfcheckStart"
const CLOSE := "SelfcheckClose"

const TITLE := "设备自检"
const TXT_IDLE := "共 %d 项 · 预计 5 分钟"
const TXT_RUNNING := "进行中 %d / %d"
const TXT_CANCELLED := "已取消"
const TXT_SAME := "一致"
const TXT_DIFF := "不一致"
const BTN_START := "开始"
const BTN_CANCEL := "取消"
const BTN_CLOSE := "关闭"

const C_OK := Color("#7fe0b0")
const C_BAD := Color("#ff9a9a")
const C_DIM := Color("#7d93ac")
const C_TXT := Color("#c9d6e2")


## 连点计数(纯函数, 门禁直接喂时刻): `taps` = 之前几次点的毫秒时刻, 返回这一次之后的列表; 列表满 TAPS 个 = 该打开了。
static func note_tap(taps: Array, now_ms: int) -> Array:
	var out: Array = []
	for t in taps:
		if now_ms - int(t) <= TAP_WINDOW_MS:
			out.append(int(t))
	out.append(now_ms)
	return out


## 打开弹框(已开着就不再开)。返回压暗层。
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

	## 战斗场的落脚处: 不进画面、不渲染(SubViewport 不放进 SubViewportContainer = 不显示; 也不收输入)。
	var sv := SubViewport.new()
	sv.name = HOST
	sv.size = Vector2i(64, 64)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.audio_listener_enable_2d = false
	sv.audio_listener_enable_3d = false
	dim.add_child(sv)

	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#5aa0ff")
	sb.set_border_width_all(3); sb.set_corner_radius_all(0)
	var rtex := UISkin.nine("panel-frame.png", 20, sb)
	if rtex is StyleBoxTexture:
		(rtex as StyleBoxTexture).modulate_color = UISkin.tint_of(Color("#5aa0ff"))
	box.add_theme_stylebox_override("panel", rtex)
	## 按实际可见区居中(宽屏手机可见区比 1280 设计宽更宽; 与「问题反馈」弹框同一条)
	var vs: Vector2 = host.get_viewport_rect().size
	box.position = Vector2(vs.x / 2.0 - BOX.x / 2.0, vs.y / 2.0 - BOX.y / 2.0)
	box.size = BOX
	dim.add_child(box)

	var ttl := _label(box, TITLE, 24, Color("#cfe3ff"), Vector2(0, 18), Vector2(BOX.x, 32))
	UISkin.title_label(ttl, 24)        # 弹框标题: 像素标题字 24 号(docs/plans/20261027-UI美术规矩.md §4.1)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info := _label(box, "%s · %s · v%s" % [OS.get_name(), Engine.get_architecture_name(),
		ReplayRecorder.client_version()], 14, C_DIM, Vector2(0, 54), Vector2(BOX.x, 22))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	## 每个场景一格: 「⑧ 一致」。5 列 × 3 行。
	var scs: Array = DeviceSelfcheck.scenarios()
	var grid := GridContainer.new()
	grid.name = GRID
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	grid.position = Vector2(30, 92)
	grid.size = Vector2(BOX.x - 60.0, 150)
	box.add_child(grid)
	var cells: Array = []
	for sc in scs:
		var c := Label.new()
		c.text = "%s  —" % DeviceSelfcheck.short_tag(str((sc as Dictionary)["tag"]))
		c.custom_minimum_size = Vector2(108, 34)
		c.add_theme_font_size_override("font_size", 17)
		c.add_theme_color_override("font_color", C_DIM)
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(c)
		cells.append(c)

	var st := _label(box, TXT_IDLE % scs.size(), 18, C_TXT, Vector2(30, 268), Vector2(BOX.x - 60.0, 60))
	st.name = STATUS
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	var close := Button.new()
	close.name = CLOSE
	close.text = BTN_CLOSE
	close.add_theme_font_size_override("font_size", 18)
	close.position = Vector2(50, 352); close.size = Vector2(250, 56)
	close.focus_mode = Control.FOCUS_NONE
	UISkin.pixel_button(close, UISkin.PX_SLATE, 4)
	box.add_child(close)

	var go := Button.new()
	go.name = START
	go.text = BTN_START
	go.add_theme_font_size_override("font_size", 18)
	go.position = Vector2(340, 352); go.size = Vector2(250, 56)
	go.focus_mode = Control.FOCUS_NONE
	UISkin.pixel_button(go, UISkin.PX_GOLD, 4)
	box.add_child(go)

	var chk := DeviceSelfcheck.new()
	dim.set_meta("selfcheck", chk)          # 门禁从这里拿到正在跑的那一个
	chk.progressed.connect(func(done: int, total: int, tag: String, ok: bool) -> void:
		if not is_instance_valid(st):
			return
		st.text = TXT_RUNNING % [done, total]
		var c: Label = cells[done - 1]
		c.text = "%s %s" % [DeviceSelfcheck.short_tag(tag), TXT_SAME if ok else TXT_DIFF]
		c.add_theme_color_override("font_color", C_OK if ok else C_BAD))
	close.pressed.connect(func() -> void:
		if chk.running:
			chk.cancel()                    # 跑的时候这颗是「取消」: 收手、还原, 弹框留着
		else:
			dim.queue_free())
	go.pressed.connect(func() -> void:
		if chk.running:
			return
		go.disabled = true
		close.text = BTN_CANCEL
		st.text = TXT_RUNNING % [0, scs.size()]
		st.add_theme_color_override("font_color", C_TXT)
		for i in range(cells.size()):
			(cells[i] as Label).text = "%s  —" % DeviceSelfcheck.short_tag(str((scs[i] as Dictionary)["tag"]))
			(cells[i] as Label).add_theme_color_override("font_color", C_DIM)
		var s: Dictionary = await chk.run(sv)
		DeviceSelfcheck.report(s, chk.results)
		if not is_instance_valid(st):
			return
		go.disabled = false
		close.text = BTN_CLOSE
		if bool(s.get("cancelled", false)):
			st.text = TXT_CANCELLED
			st.add_theme_color_override("font_color", C_DIM)
		else:
			st.text = DeviceSelfcheck.result_line(s)
			st.add_theme_color_override("font_color",
				C_OK if int(s.get("passed", 0)) == int(s.get("total", -1)) else C_BAD))
	return dim


static func _label(parent: Control, t: String, fs: int, col: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = sz
	parent.add_child(l)
	return l
