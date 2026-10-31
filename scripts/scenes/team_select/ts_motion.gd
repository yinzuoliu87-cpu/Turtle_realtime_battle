class_name TsMotion
extends RefCounted
## 选龟页的动效(2026-10-30)。用户:「其实更重要的一点是，他们游戏是动态的，并不是你看到这么静态的。
##   你得思考，怎么看上去有动态的游戏感？人家的游戏都是动态的呀。」(方案书 docs/plans/20261030-选龟页重做.md §4.9)
## 清单: 入场编排(统领卡依次落下 / 龟池卡一排排浮上来 / 右栏淡入)· 上阵(卡飞向空位、落定弹一下 + 扬尘)·
##   金边呼吸 · 高稀有度扫光 · 出战键就绪光 · 桌面氛围(烛光明暗 + 浮尘)。统领卡 / 右栏立绘的待机动画在 UnitCardArt.portrait_anim。
## ★只动内层美术节点(Content / 立绘 / 光)的位置, 布局节点只动透明度与缩放(绕中心)——
##   门禁量的槽位 / 卡片 / 出战键位置不受影响。循环动画一律 TweenKit.loop_on(节点离开场景树自动停)。

const GOLD := Color("#ffd86b")

var host
var _cta_glow: TextureRect = null
var _cta_sheen: Control = null
var _cta_clip: Control = null
var _cta_ready := false


func _init(h) -> void:
	host = h


## 建完界面后调一次(resize 重建也会再调: 旧的节点随 root 子节点一起被清掉)。
func setup() -> void:
	_ambient()
	_cta_setup()


# ───────────────────────────── 入场 ─────────────────────────────

## ★不许有开头的空白等待、整套半秒内走完 —— 用户 2026-07-18 嫌原来的入场「浮现特效很烂」
##   (先空白 0.62s 再慢慢飘上来 + 放大 = 卡顿廉价感), 当时改成 0.14s 直接淡入。这里要「动」但不能退回那个样子。
func entrance() -> void:
	## 统领卡: 从上方 28px 依次落下(回弹), 0.3s, 三张只错开 0.05s
	for i in range(host._slot_nodes.size()):
		var content: Control = (host._slot_nodes[i] as Node).get_node_or_null("Content")
		if content == null:
			continue
		content.modulate.a = 0.0
		content.position.y = -28.0
		var d := 0.05 * float(i)
		var tw := content.create_tween().set_parallel(true)
		tw.tween_property(content, "position:y", 0.0, UIPalette.T_TRANS).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(content, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(d)
	## 龟池卡在第一次建网格时浮上来(PetGrid._refresh_grid 调 cascade_roster; 此刻网格还是空的)
	## 右栏 / 顶栏 / 羁绊纸 / 提示签: 淡入(只动透明度)
	var fades: Array = [host._dt_portrait, host._dt_name, host._dt_stats, host._dt_passive]
	for n in host.root.get_children():
		if n is Control and str((n as Node).name) in ["DetailFrame", "LockedHint", "RarityTabs", "TabsBase"]:
			fades.append(n)
	for c in fades:
		if is_instance_valid(c) and c is Control:
			(c as Control).modulate.a = 0.0
			(c as Control).create_tween().tween_property(c, "modulate:a", 1.0, UIPalette.T_BASE)
	if host._detail_bottom != null and is_instance_valid(host._detail_bottom):
		var bp: Control = (host._detail_bottom as Control).get_parent()
		if bp != null:
			bp.modulate.a = 0.0
			bp.create_tween().tween_property(bp, "modulate:a", 1.0, UIPalette.T_BASE).set_delay(0.05)


## 龟池卡一排排浮上来: 透明 + 略小(0.96)→ 原样(绕卡中心缩放, 不挪位置), 每张只错开 0.01s ⇒ 整片 0.4s 内到齐。
func cascade_roster(delay0: float) -> void:
	if host._grid_flow == null or not is_instance_valid(host._grid_flow):
		return
	var k := 0
	for card in (host._grid_flow as Node).get_children():
		if not (card is Control) or (card as Node).is_queued_for_deletion():
			continue
		var c := card as Control
		c.pivot_offset = c.custom_minimum_size * 0.5
		c.modulate.a = 0.0
		c.scale = Vector2.ONE * 0.96
		var d := delay0 + 0.01 * float(mini(k, 24))
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, UIPalette.T_TAP).set_delay(d)
		tw.tween_property(c, "scale", Vector2.ONE, UIPalette.T_BASE).set_delay(d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		k += 1


# ───────────────────────────── 上阵 ─────────────────────────────

## 第 i 格刚放上一只: 卡从龟池那张飞过来(点选上阵时), 落定弹一下 + 闪一下 + 扬尘。拖进来的不飞(手已经把它带过来了)。
func place(i: int, from_card: Control) -> void:
	var slot: Control = host._slot_nodes[i]
	var content: Control = slot.get_node_or_null("Content")
	if content == null:
		return
	if from_card == null or not is_instance_valid(from_card) or not from_card.is_visible_in_tree():
		_pop(slot, content)
		return
	var fly := from_card.duplicate(0) as Control
	if fly == null:
		_pop(slot, content)
		return
	DragLift.ignore_mouse_tree(fly)
	for r in fly.get_children():
		if str(r.name) == "Ring" or str(r.name) == "InTeamDim" or str(r.name) == "InTeamTag":
			r.free()
	var from_r := from_card.get_global_rect()
	var to_r := slot.get_global_rect()
	var root_org: Vector2 = (host.root as Control).get_global_rect().position
	fly.position = from_r.position - root_org
	fly.size = from_r.size
	fly.scale = Vector2.ONE
	fly.pivot_offset = Vector2.ZERO
	fly.modulate = Color(1, 1, 1, 1)
	fly.z_index = 50
	host.root.add_child(fly)
	content.modulate.a = 0.0
	## ★2026-10-31 录屏逐帧: 飞行那 0.3 秒整格(连木框)都是透明的 ⇒ 一点下去空位就没了, 桌面露出一个洞, 卡到了才补上。
	##   ⇒ 飞行期间垫一张「空位」底(窗口底 + 压暗木框, 与空位同一个样子), 落定时删掉。
	var ph := Control.new()
	ph.name = "FlyPlaceholder"
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(UnitCardArt.window(slot.size, UnitCardArt.border_for(slot.size)))
	ph.add_child(UnitCardArt.frame(slot.size, false, true))
	slot.add_child(ph)
	slot.move_child(ph, content.get_index())
	var k: float = to_r.size.y / maxf(1.0, from_r.size.y)
	var tw := fly.create_tween().set_parallel(true)
	tw.tween_property(fly, "position", to_r.position - root_org, UIPalette.T_TRANS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(fly, "scale", Vector2.ONE * k, UIPalette.T_TRANS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	## 落定回调里的节点一律经 WeakRef 取(tween_capture_audit: 捕获的节点先没了, 引擎在调用前就报「Lambda capture … was freed」)
	var w_fly: WeakRef = weakref(fly)
	var w_ph: WeakRef = weakref(ph)
	var w_content: WeakRef = weakref(content)
	var w_slot: WeakRef = weakref(slot)
	tw.chain().tween_callback(func() -> void:
		var f = w_fly.get_ref()
		if f != null:
			f.queue_free()
		var p = w_ph.get_ref()
		if p != null:
			p.queue_free()
		var c = w_content.get_ref()
		var s = w_slot.get_ref()
		if c != null and s != null:
			c.modulate.a = 1.0
			_pop(s, c))


func _pop(slot: Control, content: Control) -> void:
	content.pivot_offset = slot.size * 0.5
	content.scale = Vector2.ONE * 1.16
	content.modulate = Color(1.7, 1.55, 1.2, 1.0)
	var tw := content.create_tween().set_parallel(true)
	tw.tween_property(content, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(content, "modulate", Color(1, 1, 1, 1), UIPalette.T_TRANS)
	_dust(slot)


## 卡落定的扬尘: 卡下沿一小撮暖色尘土, 一次性, 1 秒后自己删掉。
func _dust(slot: Control) -> void:
	var p := CPUParticles2D.new()
	p.name = "PlaceDust"
	p.one_shot = true
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(slot.size.x * 0.4, 4.0)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, 260)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.86, 0.72, 0.5, 0.85)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	var root_org: Vector2 = (host.root as Control).get_global_rect().position
	p.position = slot.get_global_rect().position - root_org + Vector2(slot.size.x * 0.5, slot.size.y - 6.0)
	host.root.add_child(p)
	p.emitting = true
	var t := p.create_tween()
	t.tween_interval(UIPalette.T_SET)
	t.tween_callback(p.queue_free)


# ───────────────────────────── 呼吸 / 扫光 ─────────────────────────────

## 金边呼吸: 透明度 1 ↔ 0.45, 一呼一吸 1.6 秒。
static func breathe(holder: Control) -> void:
	if holder == null:
		return
	var tw := TweenKit.loop_on(holder)
	tw.tween_property(holder, "modulate:a", 0.45, UIPalette.T_SET).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, UIPalette.T_SET).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 高稀有度扫光: 一道斜的亮带隔几秒从窗口左边扫到右边(加色混合, 只在窗口里)。phase = 首次延迟(错开各张)。
static func sheen(card: Control, win: Rect2, phase: float) -> void:
	var clip := Control.new()
	clip.name = "Sheen"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = win.position
	clip.size = win.size
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.8, 0.0), Color(1, 0.95, 0.8, 0.42), Color(1, 0.95, 0.8, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 4
	var band := TextureRect.new()
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	band.material = mat
	var bw: float = win.size.x * 0.42
	band.size = Vector2(bw, win.size.y * 1.6)
	band.position = Vector2(-bw * 1.4, -win.size.y * 0.3)
	band.rotation = 0.35
	clip.add_child(band)
	card.add_child(clip)
	var tw := TweenKit.loop_on(band)
	tw.tween_interval(phase)
	tw.tween_property(band, "position:x", win.size.x + bw * 0.4, UIPalette.T_SLOW).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(band):
			band.position.x = -bw * 1.4)
	tw.tween_interval(3.4 - phase)


# ───────────────────────────── 出战键 ─────────────────────────────

## 出战键背后一团金光: 三只选齐(键能点)时亮起、慢慢呼吸; 刚变成能点的那一下闪一下。
## 不改主场景: 键每次重画(置灰 / 复原都会重画)时同步一次。
func _cta_setup() -> void:
	var btn: Button = host._start_btn
	if btn == null:
		return
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.82, 0.35, 0.9))
	g.set_color(1, Color(1.0, 0.82, 0.35, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 64
	_cta_glow = TextureRect.new()
	_cta_glow.name = "CtaGlow"
	_cta_glow.texture = gt
	_cta_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cta_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_cta_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cta_glow.material = mat
	_cta_glow.size = btn.size * Vector2(1.5, 2.0)
	_cta_glow.modulate.a = 0.0
	## 键贴着屏幕右下角 ⇒ 光团伸出屏幕外: 装进一个裁剪框, 框只取「光团 ∩ 屏幕」那块(_cta_fit; verify_ui_layout ① 不许控件出视口)
	_cta_clip = Control.new()
	_cta_clip.name = "CtaGlowClip"
	_cta_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cta_clip.clip_contents = true
	_cta_clip.show_behind_parent = true
	_cta_clip.add_child(_cta_glow)
	btn.add_child(_cta_clip)
	_cta_fit()
	var tw := TweenKit.loop_on(_cta_glow)
	tw.tween_property(_cta_glow, "self_modulate:a", 0.45, UIPalette.T_SET).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cta_glow, "self_modulate:a", 1.0, UIPalette.T_SET).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	## ★2026-10-31 录屏实测: 键贴在屏幕右下角, 背后那团光大半被键自己挡住, 只在上沿露一条(亮度只差 3%)
	##   ⇒ 就绪时键面上再隔几秒扫过一道光(与高稀有度卡同一种扫光), 「能点了」看得见。
	sheen(btn, Rect2(Vector2.ZERO, btn.size), 0.6)
	_cta_sheen = btn.get_node_or_null("Sheen") as Control
	if _cta_sheen != null:
		_cta_sheen.visible = false
	_cta_ready = false
	btn.draw.connect(_cta_sync)
	_cta_sync()


## 光团想要的框(以键为中心 1.5 × 2 倍)与屏幕取交集 ⇒ 裁剪框; 光团本身在框里倒推回原位, 看上去与不裁一样。
func _cta_fit() -> void:
	var btn: Button = host._start_btn
	if btn == null or _cta_clip == null or not is_instance_valid(_cta_clip) or not is_instance_valid(_cta_glow):
		return
	var want := Rect2(-(btn.size * Vector2(1.5, 2.0) - btn.size) * 0.5, btn.size * Vector2(1.5, 2.0))
	var screen := Rect2(-btn.get_global_rect().position, host._vp())
	var r := want.intersection(screen)
	_cta_clip.position = r.position
	_cta_clip.size = r.size
	_cta_glow.size = want.size
	_cta_glow.position = want.position - r.position


func _cta_sync() -> void:
	var btn: Button = host._start_btn
	if btn == null or _cta_glow == null or not is_instance_valid(_cta_glow):
		return
	_cta_fit.call_deferred()      # 在键的 draw 回调里, 不当场改子节点的框
	var ready: bool = not btn.disabled
	if ready == _cta_ready:
		return
	_cta_ready = ready
	if _cta_sheen != null and is_instance_valid(_cta_sheen):
		_cta_sheen.visible = ready
	var tw := _cta_glow.create_tween()
	if ready:
		## 刚选齐: 先冲到很亮(颜色过曝; 透明度过 1 没用)再落回呼吸
		_cta_glow.modulate = Color(2.0, 1.8, 1.3, 1.0)
		tw.tween_property(_cta_glow, "modulate", Color(1, 1, 1, 0.8), UIPalette.T_SLOW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(_cta_glow, "modulate:a", 0.0, UIPalette.T_BASE)


# ───────────────────────────── 桌面氛围 ─────────────────────────────

## 烛光明暗(背景右上那支蜡烛) + 满屏一点点浮尘。都垫在界面最底下(root 的第一个孩子), 不挡点击。
func _ambient() -> void:
	var vp: Vector2 = host._vp()
	## 浮尘
	var p := CPUParticles2D.new()
	p.name = "AmbientDust"
	p.amount = 28
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = vp * 0.5
	p.position = vp * 0.5
	p.direction = Vector2(0.3, -1)
	p.spread = 40.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector2(0, -1.5)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(1.0, 0.88, 0.62, 0.32)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	host.root.add_child(p)
	host.root.move_child(p, 0)
	## 烛光: 背景蜡烛火苗处(设计坐标 1562, 62)一团暖光, 不规则明暗
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.72, 0.32, 0.55))
	g.set_color(1, Color(1.0, 0.72, 0.32, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var glow := TextureRect.new()
	glow.name = "CandleGlow"
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	var sz: float = 300.0 * host._s()
	glow.size = Vector2(sz, sz)
	glow.position = host._stage_to_screen(Vector2(1562, 62)) - Vector2(sz, sz) * 0.5
	## 蜡烛贴着右上角 ⇒ 光团有一半在屏幕外: 装进一层满屏裁剪框(屏幕外那半本来就看不见; verify_ui_layout ① 不许控件出视口)
	var clip := Control.new()
	clip.name = "AmbientClip"
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.size = vp
	clip.add_child(glow)
	host.root.add_child(clip)
	host.root.move_child(clip, 1)
	var tw := TweenKit.loop_on(glow)
	for step in [[0.78, 0.13], [0.6, 0.19], [0.92, 0.11], [0.7, 0.23], [0.85, 0.16], [0.55, 0.21]]:
		tw.tween_property(glow, "modulate:a", float(step[0]), float(step[1]))
