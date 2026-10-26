extends RefCounted
class_name StageCeremony
## 整屏「一站」仪式(2026-10-26 · 方案书 docs/plans/20261026c-周末弹窗美术.md)。
##
## 参考的是荒野乱斗两段不剪辑实录(逐秒记录在 docs/plans/ref/20261026-周末弹窗商业参考.md):
##   ① 晋级那一局(积分赛第 11 胜 / 闯关赛第 4 胜)打完、进结算页之前:
##      本站徽章 → 下一站徽章, 大字「晋级闯关赛！」—— 照升段那一局的结算进度屏(`TID_BATTLE_END_RANKED_RANK_UP`)
##      与战队联赛「旧联赛徽章 → 新徽章 + PROMOTED」那一屏。
##   ② 收盘后第一次进主菜单的第一屏: 「积分赛已结束」+ 本站徽章, 自动过 —— 照战队联赛「Season has ended」整屏。
## ★一屏一件事: 点任意处继续; ② 停 AUTO_SEC 自己过。晋级在哪一刻决定就在哪一刻庆祝, 收盘那一遍不再庆祝。
## ★徽章 = 三站正式标识(WeekCloseCard.BADGE_TEX, 赛程页同一套; 用户 10-26「赛程条这些要动」)。

const NODE_NAME := "StageCeremony"
## 徽章整数倍放大(像素画只按整数倍)。参考里段位徽章占屏高一半上下, 720 高 ⇒ 6 倍(约 240px)。
const PX := 6
## ② 自动过的停留: 参考战队联赛「Season has ended」那一屏约 1 秒, 加上入场。
const AUTO_SEC := 1.6
const TXT_TAP := "点击任意处继续"


## from_key / to_key: 徽章键(积分赛 / 闯关赛 / 决赛日 = phase2_config 的 PHASE_*)。两者相同 ⇒ 只亮一枚、不变身。
## auto = true ⇒ 停 AUTO_SEC 自己关(也可以点掉)。on_done 在关掉之后调一次。
static func play(host: Node, from_key: String, to_key: String, title: String, sub: String, auto: bool, on_done: Callable) -> Control:
	var ov := ColorRect.new()
	ov.name = NODE_NAME
	ov.color = Color("#0b1324")
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_meta("to", to_key)
	## 底: 中心亮、四周暗(参考里升段 / 赛季结束都是中心最亮的底, 不是一整块平涂)。
	var grad := Gradient.new()
	grad.set_color(0, Color("#24406b"))
	grad.set_color(1, Color("#060b16"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.05, 1.05)
	var bg := TextureRect.new()
	bg.name = "Backdrop"
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(bg)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(col)
	var tex_from: Texture2D = WeekCloseCard.BADGE_TEX.get(from_key, null)
	var tex_to: Texture2D = WeekCloseCard.BADGE_TEX.get(to_key, tex_from)
	## 两枚徽章原图尺寸不同(裁到内容框): 各自按整数倍放大, 居中叠在同一个框里。
	var side := Vector2(36 * PX, 36 * PX)
	for tx in [tex_from, tex_to]:
		if tx != null:
			side = side.max(Vector2(tx.get_width(), tx.get_height()) * PX)
	var holder := Control.new()
	holder.name = "BadgeHolder"
	holder.custom_minimum_size = side
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	var b_from := _badge_rect(tex_from, side, "BadgeFrom")
	holder.add_child(b_from)
	var change: bool = tex_to != tex_from and tex_to != null
	var b_to: TextureRect = null
	if change:
		b_to = _badge_rect(tex_to, side, "BadgeTo")
		b_to.modulate.a = 0.0
		holder.add_child(b_to)
	var t := _lbl(title, 54, Color("#ffd93d"), 9)
	t.name = "Title"
	t.modulate.a = 0.0
	col.add_child(t)
	var s := _lbl(sub, 24, Color("#dfe6ee"), 5)
	s.name = "Sub"
	s.modulate.a = 0.0
	s.visible = sub != ""
	col.add_child(s)
	var hint := _lbl(TXT_TAP, 18, Color("#7d8b9c"), 0)
	hint.name = "TapHint"
	hint.modulate.a = 0.0
	col.add_child(hint)
	host.add_child(ov)
	## ── 入场: 底淡入 → 本站徽章弹出 →(变身)本站徽章收掉、下一站徽章放大落下 → 大字 → 一行 → 提示 ──
	ov.modulate.a = 0.0
	b_from.pivot_offset = b_from.size / 2.0
	b_from.scale = Vector2(0.6, 0.6)
	var tw := ov.create_tween().set_parallel(true)
	tw.tween_property(ov, "modulate:a", 1.0, UIPalette.T_BASE)
	tw.tween_property(b_from, "scale", Vector2.ONE, UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t_title: float = UIPalette.T_TRANS
	if change:
		b_to.pivot_offset = b_to.size / 2.0
		b_to.scale = Vector2(1.5, 1.5)
		tw.tween_property(b_from, "modulate:a", 0.0, UIPalette.T_TAP).set_delay(UIPalette.T_SET)
		tw.tween_property(b_from, "scale", Vector2(0.7, 0.7), UIPalette.T_TAP).set_delay(UIPalette.T_SET)
		tw.tween_property(b_to, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(UIPalette.T_SET)
		tw.tween_property(b_to, "scale", Vector2.ONE, UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(UIPalette.T_SET)
		t_title = UIPalette.T_SET + UIPalette.T_TRANS
	tw.tween_property(t, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(t_title)
	tw.tween_property(s, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(t_title + UIPalette.T_BASE)
	if not auto:
		tw.tween_property(hint, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(t_title + UIPalette.T_SLOW)
	_wire_close(ov, auto, on_done)
	return ov


## 关掉: 点任意处 / 自动; 只关一次。★单独一个函数: 这几个回调不挂在入场 tween 上(tween 建在 ov 自己身上, 随它释放)。
static func _wire_close(ov: Control, auto: bool, on_done: Callable) -> void:
	var closed := [false]
	var close := func() -> void:
		## 两个触发源(点击 / Timer)都长在 ov 身上, ov 没了它们也没了 ⇒ 不必再判 ov 在不在; 只防连点两次。
		if closed[0]:
			return
		closed[0] = true
		ov.queue_free()
		on_done.call()
	ov.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			close.call())
	if auto:
		## ★挂在弹层自己身上的 Timer(不是树级计时器): 弹层先没了它跟着没(tools/tree_timer_audit.py)。
		var tm := Timer.new()
		tm.one_shot = true
		tm.wait_time = AUTO_SEC
		ov.add_child(tm)
		tm.timeout.connect(close)
		tm.start()


static func _badge_rect(tex: Texture2D, side: Vector2, nm: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = nm
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	var sz := Vector2(tex.get_width(), tex.get_height()) * PX if tex != null else side
	r.size = sz
	r.position = ((side - sz) / 2.0).floor()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _lbl(txt: String, fs: int, c: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
