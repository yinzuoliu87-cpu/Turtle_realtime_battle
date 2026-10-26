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
## 徽章整数倍放大(像素画只按整数倍)。参考里段位徽章占屏高一半上下(荒野乱斗升段), 720 高 ⇒ 7 倍(约 280px)。
const PX := 7
## ② 自动过的停留: 参考战队联赛「Season has ended」那一屏约 1 秒, 加上入场。
const AUTO_SEC := 1.6
const TXT_TAP := "点击任意处继续"
## 变身时徽章背后的放射光(PixelLab 出图挑 4 帧、锁成同一套 6 色; 像素画不旋转, 只逐帧闪)。
const BURST_TEX := preload("res://assets/sprites/menu/weekend/promo-burst.png")
## 徽章材质: flash = 过曝(0 原色 ~ 1 全白); sweep = 斜向高光带的位置(按原图像素格取整, 像素画不糊)。
const BADGE_SHADER := """shader_type canvas_item;
uniform float flash = 0.0;
uniform float sweep = -0.4;
uniform vec2 texel = vec2(0.025, 0.025);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 uv = floor(UV / texel) * texel;
	float d = abs((uv.x + uv.y) * 0.5 - sweep);
	float band = step(d, 0.05);
	vec3 rgb = mix(c.rgb, vec3(1.0), band * 0.7);
	rgb = mix(rgb, vec3(1.0), flash);
	COLOR = vec4(rgb, c.a);
}
"""
const BURST_FRAMES := 4
const BURST_PX := 5
const BURST_STEP := 0.15
const BURST_BOX_H := 470.0
## 整屏底色按「要去的那一站」换(荒野乱斗升段: 铜档橙红、银档亮蓝、金档金橙); 没有对应的(收盘「已结束」那屏)用深蓝。
const BG_COL := {
	"gauntlet": [Color("#c2482a"), Color("#2a0907")],
	"finals": [Color("#d99a1e"), Color("#3a1d04")],
}
const BG_DEFAULT := [Color("#24406b"), Color("#060b16")]


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
	var bgc: Array = BG_COL.get(to_key, BG_DEFAULT) if to_key != from_key else BG_DEFAULT
	var grad := Gradient.new()
	grad.set_color(0, bgc[0])
	grad.set_color(1, bgc[1])
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
	col.add_theme_constant_override("separation", 8)
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
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	var change: bool = tex_to != tex_from and tex_to != null
	## 有光时徽章区加高: 光束半径(约 228px)比徽章大一圈, 不加高就伸进下面那行大字后面(实拍: 字与光束搅在一起)。
	if change:
		side.y = maxf(side.y, BURST_BOX_H)
	var burst: TextureRect = null
	if change:
		burst = _burst(side)
		holder.add_child(burst)      # 先加 = 画在徽章后面
	holder.custom_minimum_size = side
	var b_from := _badge_rect(tex_from, side, "BadgeFrom")
	holder.add_child(b_from)
	var b_to: TextureRect = null
	if change:
		b_to = _badge_rect(tex_to, side, "BadgeTo")
		b_to.modulate.a = 0.0
		holder.add_child(b_to)
	## 大字是美术的一部分(参考的段位名: 超大、厚描边、落影), 不是一行说明。
	var t := _lbl(title, 72, Color("#fff1c9"), 14)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 7)
	t.name = "Title"
	t.modulate.a = 0.0
	var slot := Control.new()
	slot.name = "TitleSlot"
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(t)
	col.add_child(slot)
	var s := _lbl(sub, 26, Color("#fff6e6"), 6)
	s.name = "Sub"
	s.modulate.a = 0.0
	s.visible = sub != ""
	col.add_child(s)
	var hint := _lbl(TXT_TAP, 18, Color("#7d8b9c"), 0)
	hint.name = "TapHint"
	hint.modulate.a = 0.0
	col.add_child(hint)
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1, 1, 1, 1)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	ov.add_child(flash)
	host.add_child(ov)
	## 大字槽在入树之后量: 之前主题字体还没生效, 量出来偏小 ⇒ 实录里大字偏右、压在副标题上。
	slot.custom_minimum_size = t.get_combined_minimum_size()
	t.size = slot.custom_minimum_size
	## ── 入场(照荒野乱斗升段 30fps 逐帧, docs/plans/ref/20261026-周末弹窗商业参考.md「动作」一节):
	##   徽章出场先过曝(整枚发白)略大 → 0.2 秒退到原色原大; 换站 = 旧徽章过曝 → 白光擦屏 → 新徽章过曝落定、背后的光炸开再减弱;
	##   大字从左边滑进来(4 帧到位); 约 1 秒后一道高光斜扫过徽章; 最后才给「点击任意处继续」。
	ov.modulate.a = 0.0
	var tw := ov.create_tween().set_parallel(true)
	tw.tween_property(ov, "modulate:a", 1.0, UIPalette.T_TAP)
	_impact(tw, b_from, 0.0)
	var t_land: float = 0.0                       # 最后那枚徽章落定的时刻
	if change:
		t_land = UIPalette.T_SLOW + UIPalette.T_BASE
		var mf := b_from.material as ShaderMaterial
		tw.tween_property(mf, "shader_parameter/flash", 1.0, UIPalette.T_TAP).set_delay(t_land - UIPalette.T_TAP)
		tw.tween_property(b_from, "modulate:a", 0.0, UIPalette.T_TAP).set_delay(t_land)
		tw.tween_property(flash, "modulate:a", 0.9, UIPalette.T_TAP).set_delay(t_land - UIPalette.T_TAP)
		tw.tween_property(flash, "modulate:a", 0.0, UIPalette.T_TRANS).set_delay(t_land)
		tw.tween_property(b_to, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(t_land)
		_impact(tw, b_to, t_land)
		burst.pivot_offset = burst.size / 2.0
		burst.scale = Vector2(1.25, 1.25)
		tw.tween_property(burst, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(t_land)
		tw.tween_property(burst, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(t_land)
		tw.tween_property(burst, "modulate:a", 0.7, UIPalette.T_SET).set_delay(t_land + UIPalette.T_TRANS)
	var t_title: float = t_land + UIPalette.T_BASE
	t.position = Vector2(-slot.custom_minimum_size.x - 200.0, 0.0)
	tw.tween_property(t, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(t_title)
	tw.tween_property(t, "position", Vector2.ZERO, UIPalette.T_BASE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(t_title)
	tw.tween_property(s, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(t_title + UIPalette.T_BASE)
	## 高光扫过最后那枚徽章
	var last := b_to if change else b_from
	var ml := last.material as ShaderMaterial
	tw.tween_property(ml, "shader_parameter/sweep", 1.4, UIPalette.T_SLOW).set_delay(t_land + UIPalette.T_SET)
	if not auto:
		tw.tween_property(hint, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(t_land + UIPalette.T_SET + UIPalette.T_SLOW)
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


## 放射光: 横条 4 帧, 整数倍放大, 中心对准徽章框中心; 先藏着(变身那一刻淡入), 自己按 BURST_STEP 轮帧。
static func _burst(side: Vector2) -> TextureRect:
	var cell: int = BURST_TEX.get_width() / BURST_FRAMES
	var at := AtlasTexture.new()
	at.atlas = BURST_TEX
	at.region = Rect2(0, 0, cell, BURST_TEX.get_height())
	var r := TextureRect.new()
	r.name = "Burst"
	r.texture = at
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(cell, BURST_TEX.get_height()) * BURST_PX
	r.position = ((side - r.size) / 2.0).floor()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	## 叠加混合: 光是「加亮」底色, 不是一块不透明的实物(去掉了深色描边, 见素材头注)。
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	var fi := [0]
	var tm := Timer.new()
	tm.wait_time = BURST_STEP
	tm.autostart = true
	tm.timeout.connect(func() -> void:
		fi[0] = (fi[0] + 1) % BURST_FRAMES
		at.region = Rect2(fi[0] * cell, 0, cell, BURST_TEX.get_height()))
	r.add_child(tm)
	return r


## 过曝落定: 出场那一刻整枚发白、略大, T_BASE 内退回原色原大(荒野乱斗升段 0~0.2 秒)。
static func _impact(tw: Tween, b: TextureRect, at: float) -> void:
	var m := b.material as ShaderMaterial
	b.pivot_offset = b.size / 2.0
	b.scale = Vector2(1.18, 1.18)
	m.set_shader_parameter("flash", 1.0)
	tw.tween_property(m, "shader_parameter/flash", 0.0, UIPalette.T_BASE).set_delay(at)
	tw.tween_property(b, "scale", Vector2.ONE, UIPalette.T_BASE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(at)


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
	var sh := Shader.new()
	sh.code = BADGE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("texel", Vector2(1.0 / float(tex.get_width()), 1.0 / float(tex.get_height())) if tex != null else Vector2(0.025, 0.025))
	mat.set_shader_parameter("sweep", -0.4)
	r.material = mat
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
