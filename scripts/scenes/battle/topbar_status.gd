extends RefCounted
## topbar_status.gd — 顶部栏的「人」与「状态」那一层(2026-10-07 顶部栏重做)。
##
## 血条本体(两段主条 / 蛋副条 / 残影 / 回血带 / VS 徽章)仍在 battle_hud.gd 的 `_pk_*` 里 ——
## 那套有两份门禁焊着(verify_battle_hud_r1 / verify_pk_bar_continuity), 字段名不动。
## 这里只放它周围新加的东西:
##   · 两端领队头像 + 双方名字(照铁拳8 / 罪恶装备 / 碧蓝幻想VS: 头像在条的外端, 名字贴着条)
##   · VS 下面: 三路小圆点(铁拳的回合点) + 路名计时牌(上路战场 0:23 / 加时 0:42 / 破蛋 0:08)
##   · 加时: 一次性大字「加时！」+ 牌子两侧两枚图标徽章(增伤 +25% / 治疗 -50%), 点一下出一行说明
##   · 团灭: 那一侧主条上盖「团灭」戳; 蛋副条变亮呼吸(围栏破了 = 蛋能打了)
##   · 蛋碎: 那一侧蛋副条碎片飞散
##
## ★全部按渲染帧驱动(hud._pk_tick → tick), 不用 tween: battle_hud 的 tween 棘轮(tween_freeze_audit)
##   只减不增, 而且这些都是"看"的东西, 不进 sim、不影响确定性。
## ★用户 2026-10-07 的话(逐字钉住):
##   「中间弄vs，计时放在VS下面」「我们这又不是倒计时」(计时正着走; 只有破蛋那 10 秒是倒数)
##   「百分比和数值可以加，但这么搞很丑啊」(→ 挂在条外端下面的斜牌, 见 battle_hud._pk_mk_tag)
##   「加时、团灭、破蛋的新显示方案行」

const FRAME_TEX := "res://assets/sprites/battlehud/topbar-portrait-frame.png"
const DOT_RING_TEX := "res://assets/sprites/battlehud/topbar-dot-ring.png"
const DOT_CORE_TEX := "res://assets/sprites/battlehud/topbar-dot-core.png"
## 牌子/徽章/说明框共用一张新画的银边石板(与血条的细金属边同一套光: 左上亮右下暗)。
const PLATE_TEX := "res://assets/sprites/battlehud/topbar-plate.png"
## 加时两枚徽章的图标(新画, 11×11 → 局内 ×2): 增伤 = 橙红上箭头, 治疗减半 = 绿十字 + 红下箭头。
const ICON_AMP := "res://assets/sprites/battlehud/topbar-ot-amp.png"
const ICON_HEAL := "res://assets/sprites/battlehud/topbar-ot-heal.png"

const PORT := 58.0           # 头像边长(框图 29×29 的 2 倍, 落在像素网格上)
const PORT_GAP := 6.0        # 头像与条外端的间距
const PORT_Y := -16.0        # 头像顶相对主条顶(头像比条高, 上下各探出一截)
const NAME_Y := -20.0        # 名字行相对主条顶
const DOT_PX := 18.0         # 路点边长(9×9 的 2 倍)
const LANES := ["top", "bottom", "final"]
const SPLASH_TEXT := "加时！"
const SPLASH_DUR := 1.2      # 大字从出现到淡完(秒)
const STAMP_TEXT := "团灭"
const POPUP_LIFE := 3.0      # 说明小框自己消失的时间(秒)

var hud
var battle
var bar: Control = null
var port_l: TextureRect = null
var port_r: TextureRect = null
var _port_id := {"left": "", "right": ""}
var name_l: Label = null
var name_r: Label = null
var dot_cores: Array = []
var dot_rings: Array = []
var plate: PanelContainer = null
var badge_amp: PanelContainer = null
var badge_heal: PanelContainer = null
var badge_amp_lab: Label = null
var badge_heal_lab: Label = null
var popup: PanelContainer = null
var popup_lab: Label = null
var catcher: Control = null
var _popup_t := 0.0
var splash: Control = null
var splash_lab: Label = null
var _splash_t := -1.0
var stamps := {}
var _stamp_t := {"left": -1.0, "right": -1.0}
var _shards: Array = []
var _egg_broken := {"left": false, "right": false}
var _amp_prev := 0
var _amp_pulse := 0.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()   # ★自己的 rng: 碎片方向不许碰战斗 rng(回放确定性)


func _init(h) -> void:
	hud = h
	battle = h.battle
	_rng.seed = 20261007


## 在 PK 条上把这一层建出来。bar 的本地坐标: x∈[0, 条总宽], y=0 是主条顶。
func build(b: Control) -> void:
	bar = b
	var w: float = hud._pk_w_cur
	port_l = _mk_portrait(Vector2(-PORT_GAP - PORT, PORT_Y), false)
	port_r = _mk_portrait(Vector2(w + PORT_GAP, PORT_Y), true)
	var nm: Dictionary = side_names()
	name_l = _mk_name(str(nm["l"]), true)
	name_r = _mk_name(str(nm["r"]), false)
	for side in ["left", "right"]:
		stamps[side] = _mk_stamp(side)
	_build_splash()
	if battle._is_dual_lane_mode():
		_build_center()
	refresh()


## 两边名字。正常对局: 我 = 自己的显示名, 对面 = 对手快照里的名字; 回放: 录像里记的两个人。
## 单路/评审台/调试场(没有双路)不显示名字 —— 那里两边都不是"人"。
func side_names() -> Dictionary:
	if not battle._is_dual_lane_mode():
		return {"l": "", "r": ""}
	if battle._replay != null and battle._replay.is_playing():
		return ReplayRecorder.side_names(battle._replay.rec, ReplayRecorder.viewer_name)
	var foe := ""
	var g = GameState.dual_ghost if GameState != null else {}
	if g is Dictionary and (g as Dictionary).get("profile", null) is Dictionary:
		foe = str(((g as Dictionary)["profile"] as Dictionary).get("name", ""))
	return {"l": str(battle.Backend.player_display_name()), "r": foe}


func _mk_portrait(pos: Vector2, flip: bool) -> TextureRect:
	var holder := Control.new()
	holder.name = "TopPortrait_" + ("R" if flip else "L")
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = pos
	holder.size = Vector2(PORT, PORT)
	bar.add_child(holder)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var team: Color = hud.PK_RED if flip else hud.PK_BLUE
	bg.color = Color(0.06, 0.06, 0.08).lerp(team, 0.22)
	bg.position = Vector2(6, 6)
	bg.size = Vector2(PORT - 12, PORT - 12)
	holder.add_child(bg)
	var tr := TextureRect.new()
	tr.name = "Face"
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.flip_h = flip                 # 右边那只朝里看(两边对望)
	tr.position = Vector2(8, 8)
	tr.size = Vector2(PORT - 16, PORT - 16)
	holder.add_child(tr)
	var fr := TextureRect.new()
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists(FRAME_TEX):
		fr.texture = load(FRAME_TEX)
	else:
		push_warning("[顶栏] 头像框素材缺失: %s" % FRAME_TEX)
	fr.size = Vector2(PORT, PORT)
	holder.add_child(fr)
	return tr


func _mk_name(txt: String, left: bool) -> Label:
	var l := Label.new()
	l.name = "TopName_" + ("L" if left else "R")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = txt
	l.visible = txt != ""
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#f4f1ea"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var nw: float = minf(240.0, hud._pk_seg_cur * 0.6)
	l.size = Vector2(nw, 18)
	if left:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector2(hud.PK_SLANT + 2.0, NAME_Y)
	else:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector2(hud._pk_w_cur - hud.PK_SLANT - 2.0 - nw, NAME_Y)
	bar.add_child(l)
	return l


## 「团灭」戳: 压在那一侧主条正中, 略歪, 出现时从大缩回(盖章的感觉)。
func _mk_stamp(side: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "WipeStamp_" + side
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.02, 0.03, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color("#ff5a5a")
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 0; sb.content_margin_bottom = 0
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = STAMP_TEXT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#ffd6d6"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 3)
	pc.add_child(l)
	bar.add_child(pc)
	var sz: Vector2 = pc.get_combined_minimum_size()
	pc.size = sz
	var seg: float = hud._pk_seg_cur
	var cx: float = seg * 0.5 if side == "left" else seg + hud.PK_VS + seg * 0.5
	pc.position = Vector2(cx - sz.x * 0.5, hud.PK_H * 0.5 - sz.y * 0.5)
	pc.pivot_offset = sz * 0.5
	pc.rotation = -0.07
	pc.visible = false
	return pc


## 「加时！」大字: 屏幕中上, 一次性, 1.2 秒内缩回再淡掉。挂在条上 = 换视口重建时一起走。
func _build_splash() -> void:
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var holder := Control.new()
	holder.name = "OvertimeSplash"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 20
	var top: float = bar.offset_top
	holder.position = Vector2(0.0, vp.y * 0.36 - top - 60.0)
	holder.size = Vector2(hud._pk_w_cur, 120.0)
	holder.visible = false
	bar.add_child(holder)
	## 背后一条斜切暗带: 让大字压在任何地图上都读得出(与血条同一个斜切语言)。
	var band := ColorRect.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = Color(0.12, 0.02, 0.0, 0.62)
	band.position = Vector2(hud._pk_w_cur * 0.18, 22.0)
	band.size = Vector2(hud._pk_w_cur * 0.64, 76.0)
	band.material = hud._pk_slant_mat(band.size)
	holder.add_child(band)
	var l := Label.new()
	l.text = SPLASH_TEXT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 78)
	l.add_theme_color_override("font_color", Color("#ffb03a"))
	l.add_theme_color_override("font_outline_color", Color("#5c0c00"))
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.position = Vector2.ZERO
	l.size = holder.size
	l.pivot_offset = holder.size * 0.5
	holder.add_child(l)
	splash = holder
	splash_lab = l


## VS 下面那一列: 三路点 + 路名计时牌(两侧加时徽章) + 徽章说明小框。只有双路有。
func _build_center() -> void:
	var seg: float = hud._pk_seg_cur
	var vs: float = hud.PK_VS
	## ── 三路点 ──
	var row := HBoxContainer.new()
	row.name = "LaneDots"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var dw: float = DOT_PX * 3.0 + 12.0
	row.position = Vector2(seg + vs * 0.5 - dw * 0.5, hud.PK_H + 22.0)
	row.size = Vector2(dw, DOT_PX)
	bar.add_child(row)
	dot_cores.clear()
	dot_rings.clear()
	for i in range(LANES.size()):
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = Vector2(DOT_PX, DOT_PX)
		row.add_child(cell)
		var core := _mk_px_rect(DOT_CORE_TEX, DOT_PX)
		cell.add_child(core)
		var ring := _mk_px_rect(DOT_RING_TEX, DOT_PX)
		ring.pivot_offset = Vector2(DOT_PX, DOT_PX) * 0.5
		cell.add_child(ring)
		dot_cores.append(core)
		dot_rings.append(ring)
	## ── 牌子一行: [增伤徽章][路名计时牌][治疗徽章] ──
	var prow := HBoxContainer.new()
	prow.name = "LaneRow"
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prow.add_theme_constant_override("separation", 8)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.anchor_left = 0.5; prow.anchor_right = 0.5
	prow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prow.offset_top = hud.PK_H + 22.0 + DOT_PX + 4.0
	bar.add_child(prow)
	badge_amp = _mk_badge(ICON_AMP, "amp")
	badge_amp_lab = badge_amp.get_meta("lab")
	prow.add_child(badge_amp)
	plate = PanelContainer.new()
	plate.name = "LanePlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PLATE_TEX):
		var lsb := StyleBoxTexture.new()
		lsb.texture = load(PLATE_TEX)
		lsb.set_texture_margin_all(12)
		lsb.content_margin_left = 16; lsb.content_margin_right = 16
		lsb.content_margin_top = 3; lsb.content_margin_bottom = 3
		plate.add_theme_stylebox_override("panel", lsb)
	prow.add_child(plate)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 20)
	lab.add_theme_color_override("font_color", Color("#ffe08a"))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lab.add_theme_constant_override("outline_size", 4)
	plate.add_child(lab)
	battle._dl_hud = lab
	badge_heal = _mk_badge(ICON_HEAL, "heal")
	badge_heal_lab = badge_heal.get_meta("lab")
	badge_heal_lab.text = "-%d%%" % int(round((1.0 - float(battle.SD_HEAL_MULT)) * 100.0))
	prow.add_child(badge_heal)
	badge_amp.visible = false
	badge_heal.visible = false
	_build_popup()


func _mk_px_rect(path: String, px: float) -> TextureRect:
	var t := TextureRect.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists(path):
		t.texture = load(path)
	else:
		push_warning("[顶栏] 素材缺失: %s" % path)
	t.size = Vector2(px, px)
	return t


## 加时徽章: [属性图标][读数]。整块可点 —— 点一下出一行说明(屏幕上平时不挂句子)。
func _mk_badge(icon_path: String, kind: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "OtBadge_" + kind
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(PLATE_TEX):
		var sb := StyleBoxTexture.new()
		sb.texture = load(PLATE_TEX)
		sb.set_texture_margin_all(12)
		sb.content_margin_left = 8; sb.content_margin_right = 10
		sb.content_margin_top = 3; sb.content_margin_bottom = 3
		pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 4)
	pc.add_child(hb)
	var ic := TextureRect.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(22, 22)
	if ResourceLoader.exists(icon_path):
		ic.texture = load(icon_path)
	hb.add_child(ic)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#ff8a4c") if kind == "amp" else Color("#9fe3b0"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 4)
	hb.add_child(l)
	pc.set_meta("lab", l)
	pc.set_meta("kind", kind)
	pc.gui_input.connect(_on_badge_input.bind(pc))
	return pc


## 说明小框 + 背后的全屏接点层(点别处就关)。
func _build_popup() -> void:
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	catcher = Control.new()
	catcher.name = "OtPopupCatcher"
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.z_index = 19
	catcher.position = Vector2(-bar.offset_left - vp.x * 0.5, -bar.offset_top)
	catcher.size = vp
	catcher.visible = false
	catcher.gui_input.connect(_on_catcher_input)
	bar.add_child(catcher)
	popup = PanelContainer.new()
	popup.name = "OtPopup"
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.z_index = 20
	if ResourceLoader.exists(PLATE_TEX):
		var sb := StyleBoxTexture.new()
		sb.texture = load(PLATE_TEX)
		sb.set_texture_margin_all(12)
		sb.content_margin_left = 14; sb.content_margin_right = 14
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		popup.add_theme_stylebox_override("panel", sb)
	popup_lab = Label.new()
	popup_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_lab.add_theme_font_size_override("font_size", 16)
	popup_lab.add_theme_color_override("font_color", Color("#f4f1ea"))
	popup.add_child(popup_lab)
	popup.visible = false
	popup.gui_input.connect(_on_catcher_input)
	bar.add_child(popup)


## 一行说明。数字从战斗常量来(SD_STEP / SD_AMP_PER / SD_HEAL_MULT), 不写死。
func badge_text(kind: String) -> String:
	if kind == "amp":
		return "加时中每 %d 秒, 全场伤害再 +%d%%" % [int(battle.SD_STEP), int(round(float(battle.SD_AMP_PER) * 100.0))]
	return "加时中所有治疗效果 -%d%%" % int(round((1.0 - float(battle.SD_HEAL_MULT)) * 100.0))


func _is_press(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton:
		return (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if ev is InputEventScreenTouch:
		return (ev as InputEventScreenTouch).pressed
	return false


func _on_badge_input(ev: InputEvent, pc: PanelContainer) -> void:
	if not _is_press(ev):
		return
	var kind := str(pc.get_meta("kind", ""))
	if popup.visible and str(popup.get_meta("kind", "")) == kind:
		hide_popup()
	else:
		show_popup(kind)
	bar.get_viewport().set_input_as_handled()


func _on_catcher_input(ev: InputEvent) -> void:
	if _is_press(ev):
		hide_popup()
		bar.get_viewport().set_input_as_handled()


func show_popup(kind: String) -> void:
	if popup == null:
		return
	var src: Control = badge_amp if kind == "amp" else badge_heal
	popup_lab.text = badge_text(kind)
	popup.set_meta("kind", kind)
	popup.visible = true
	catcher.visible = true
	popup.size = popup.get_combined_minimum_size()
	var at: Vector2 = src.global_position - bar.global_position + Vector2(src.size.x * 0.5 - popup.size.x * 0.5, src.size.y + 6.0)
	var vpw: float = float(battle.get_viewport().get_visible_rect().size.x)
	var gx: float = bar.global_position.x
	at.x = clampf(at.x, 8.0 - gx, vpw - 8.0 - gx - popup.size.x)
	popup.position = at
	_popup_t = POPUP_LIFE


func hide_popup() -> void:
	if popup != null:
		popup.visible = false
	if catcher != null:
		catcher.visible = false


func show_splash() -> void:
	if splash == null or not is_instance_valid(splash):
		return
	_splash_t = 0.0
	splash.visible = true
	_amp_pulse = 1.0


## 每 PK_SAMPLE 秒(跟着 hud._pk_refresh): 头像换人 / 路点上色 / 蛋碎检测。
func refresh() -> void:
	if bar == null or not is_instance_valid(bar):
		return
	_refresh_portrait("left", port_l)
	_refresh_portrait("right", port_r)
	_refresh_dots()
	## 碎过的蛋又有血了(换路重建了蛋) ⇒ 允许它再碎一次
	if hud._pk_egg_tl > 0.0: _egg_broken["left"] = false
	if hud._pk_egg_tr > 0.0: _egg_broken["right"] = false


## 这一路这一边该挂谁的头像, 按优先级排好: 活着的龟统领 → 已倒下的龟统领 → 小将(这一路没带统领时)。
## 不算蛋 / 训龟大师 / 召唤物。
func portrait_candidates(side: String) -> Array:
	var alive_l: Array = []
	var dead_l: Array = []
	var minions: Array = []
	for u in battle._units:
		if str(u.get("side", "")) != side:
			continue
		if u.get("_isEgg", false) or u.get("is_trainer", false) or u.get("is_summon", false):
			continue
		if u.get("_isMinion", false):
			minions.append(u)
		elif u.get("alive", false):
			alive_l.append(u)
		else:
			dead_l.append(u)
	return alive_l + dead_l + minions


func _refresh_portrait(side: String, tr: TextureRect) -> void:
	if tr == null or not is_instance_valid(tr):
		return
	## 取第一个【真拿得到图】的候选(小将可能没有头像图)。拿到才记 key —— 没拿到下次采样再试。
	for u in portrait_candidates(side):
		var key := "%s|%s|%s" % [str(u.get("id", "")), str(u.get("name", "")), str(u.get("_isMinion", false))]
		if key == str(_port_id[side]):
			return
		var tex: Texture2D = battle._unit_portrait_texture(u)
		if tex != null:
			_port_id[side] = key
			tr.texture = tex
			return


func _refresh_dots() -> void:
	if dot_cores.is_empty() or GameState == null:
		return
	var res: Dictionary = GameState.lane_results if GameState.lane_results is Dictionary else {}
	for i in range(LANES.size()):
		var lane: String = LANES[i]
		var who := str(res.get(lane, ""))
		var core: TextureRect = dot_cores[i]
		if who == "left":
			core.modulate = hud.PK_BLUE
		elif who == "right":
			core.modulate = hud.PK_RED
		else:
			core.modulate = Color(0.10, 0.11, 0.14, 1.0)


## 这一路正在打的是第几个点(-1 = 不在打)。
func current_dot() -> int:
	if GameState == null:
		return -1
	return LANES.find(str(GameState.current_lane))


## 蛋碎(dual_lane_flow 在判到蛋死的那一刻调): 副条当场清空 + 外端崩出一把碎片 + 白闪。
## ★走事件不走采样: 蛋碎 = 整场结束, 结算屏紧跟着就上来; 等 0.1 秒一次的采样再发现就被盖住了。
## 碎片按帧自己飞, 0.7 秒内收干净。同一颗蛋只碎一次。
func break_egg(side: String) -> void:
	if bool(_egg_broken.get(side, false)) or bar == null or not is_instance_valid(bar):
		return
	_egg_broken[side] = true
	if side == "left":
		hud._pk_egg_tl = 0.0; hud._pk_egg_sl = 0.0
	else:
		hud._pk_egg_tr = 0.0; hud._pk_egg_sr = 0.0
	hud._pk_apply()
	var ex: float = hud._pk_egg_x0_of(side == "left")
	var ew: float = hud._pk_egg_w
	var y: float = hud.PK_H + hud.PK_EGG_GAP
	var flash := ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0.75)
	flash.position = Vector2(ex, y)
	flash.size = Vector2(ew, hud.PK_EGG_H)
	flash.material = hud._pk_slant_mat(flash.size)
	bar.add_child(flash)
	_shards.append({"n": flash, "v": Vector2.ZERO, "life": 0.3, "max": 0.3, "flash": true})
	var ox: float = ex + (14.0 if side == "left" else ew - 14.0)
	for i in range(16):
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = hud.PK_EGG_COL if i % 3 != 0 else Color("#fff6e0")
		r.size = Vector2(_rng.randf_range(5.0, 9.0), _rng.randf_range(4.0, 7.0))
		r.position = Vector2(ox + _rng.randf_range(-24.0, 24.0), y + hud.PK_EGG_H * 0.5 - 3.0)
		r.pivot_offset = r.size * 0.5
		r.rotation = _rng.randf_range(-0.6, 0.6)
		bar.add_child(r)
		var dirx: float = _rng.randf_range(-1.0, 1.0) * 220.0
		_shards.append({"n": r, "v": Vector2(dirx, _rng.randf_range(-280.0, -90.0)), "life": 0.8, "max": 0.8, "flash": false})


func shard_count() -> int:
	return _shards.size()


## 每帧: 大字 / 戳 / 徽章 / 路点呼吸 / 蛋副条亮度 / 碎片 / 说明小框寿命。
func tick(delta: float) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	_phase = fmod(_phase + delta, 1000.0)
	_tick_splash(delta)
	_tick_stamps(delta)
	_tick_badges(delta)
	_tick_dots()
	_tick_egg_glow()
	_tick_shards(delta)
	if popup != null and popup.visible:
		_popup_t -= delta
		if _popup_t <= 0.0:
			hide_popup()


func _tick_splash(delta: float) -> void:
	if _splash_t < 0.0 or splash == null:
		return
	_splash_t += delta
	var t: float = _splash_t
	if t >= SPLASH_DUR:
		_splash_t = -1.0
		splash.visible = false
		return
	var k: float = clampf(t / 0.16, 0.0, 1.0)
	var sc: float = lerpf(1.55, 1.0, 1.0 - pow(1.0 - k, 3.0))
	splash_lab.scale = Vector2(sc, sc)
	var a: float = 1.0 if t < SPLASH_DUR - 0.4 else clampf((SPLASH_DUR - t) / 0.4, 0.0, 1.0)
	splash.modulate = Color(1, 1, 1, a)


func _tick_stamps(delta: float) -> void:
	for side in ["left", "right"]:
		var st: PanelContainer = stamps.get(side, null)
		if st == null or not is_instance_valid(st):
			continue
		var on: bool = is_wiped(side)
		var face: TextureRect = port_l if side == "left" else port_r
		if face != null and is_instance_valid(face):
			face.modulate = Color(0.38, 0.38, 0.42, 1.0) if on else Color.WHITE
		if on and not st.visible:
			st.visible = true
			_stamp_t[side] = 0.0
		elif not on:
			st.visible = false
			_stamp_t[side] = -1.0
		if st.visible and float(_stamp_t[side]) >= 0.0:
			_stamp_t[side] = float(_stamp_t[side]) + delta
			var k: float = clampf(float(_stamp_t[side]) / 0.18, 0.0, 1.0)
			var sc: float = lerpf(1.9, 1.0, k)
			st.scale = Vector2(sc, sc)
			st.modulate = Color(1, 1, 1, clampf(k * 1.5, 0.0, 1.0))


## 这一方是不是团灭了(破蛋窗口里, 场上一个能打的都不剩)。判据走双路流程自己的存活计数。
func is_wiped(side: String) -> bool:
	if not battle._is_dual_lane_mode() or battle._dl_sys == null:
		return false
	if str(battle._dl_state) != "eggwindow":
		return false
	return int(battle._dl_sys._dl_side_alive(side)) == 0


func overtime_on() -> bool:
	return int(battle._sd_stacks) > 0 and (str(battle._dl_state) == "fight" or str(battle._dl_state) == "eggwindow")


func _tick_badges(delta: float) -> void:
	if badge_amp == null or not is_instance_valid(badge_amp):
		return
	var on: bool = overtime_on()
	badge_amp.visible = on
	badge_heal.visible = on
	if not on:
		_amp_prev = 0
		hide_popup()
		return
	var st: int = int(battle._sd_stacks)
	if st != _amp_prev:
		_amp_prev = st
		_amp_pulse = 1.0
		badge_amp_lab.text = "+%d%%" % int(round(float(battle._sd_amp()) * 100.0))
	_amp_pulse = maxf(0.0, _amp_pulse - delta * 2.5)
	var sc: float = 1.0 + _amp_pulse * 0.35
	badge_amp.pivot_offset = badge_amp.size * 0.5
	badge_amp.scale = Vector2(sc, sc)
	var g: float = 1.0 + _amp_pulse * 0.6
	badge_amp.modulate = Color(g, g, g, 1.0)


func _tick_dots() -> void:
	if dot_rings.is_empty():
		return
	var cur: int = current_dot()
	var res: Dictionary = GameState.lane_results if GameState != null and GameState.lane_results is Dictionary else {}
	for i in range(dot_rings.size()):
		var ring: TextureRect = dot_rings[i]
		if i == cur and not res.has(LANES[i]):
			var p: float = 0.5 + 0.5 * sin(_phase * 5.0)
			var b: float = 1.0 + 0.45 * p
			ring.modulate = Color(b, b * 0.95, b * 0.7, 1.0)
			ring.scale = Vector2.ONE * (1.0 + 0.12 * p)
		elif res.has(LANES[i]):
			ring.modulate = Color.WHITE
			ring.scale = Vector2.ONE
		else:
			ring.modulate = Color(0.55, 0.55, 0.6, 1.0)
			ring.scale = Vector2.ONE


## 蛋副条亮度: 围栏在 = 压暗(打不到); 围栏破 = 正常亮度上再加一层呼吸(现在能打了)。
func _tick_egg_glow() -> void:
	for side in ["left", "right"]:
		var bar_n: Control = hud._pk_egg_l if side == "left" else hud._pk_egg_r
		if bar_n == null or not is_instance_valid(bar_n):
			continue
		var m: Color
		if hud.egg_fenced(side):
			m = Color(0.58, 0.58, 0.58, 1.0)
		else:
			var k: float = 1.12 + 0.22 * (0.5 + 0.5 * sin(_phase * 6.0))
			m = Color(k, k, k, 1.0)
		bar_n.modulate = m
		var ic = hud._pk_egg_icons[0 if side == "left" else 1] if hud._pk_egg_icons.size() == 2 else null
		if ic != null and is_instance_valid(ic):
			ic.modulate = m


func _tick_shards(delta: float) -> void:
	var keep: Array = []
	for s in _shards:
		var n: Control = s["n"]
		if not is_instance_valid(n):
			continue
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			n.queue_free()
			continue
		var a: float = clampf(float(s["life"]) / float(s["max"]), 0.0, 1.0)
		if bool(s["flash"]):
			n.modulate = Color(1, 1, 1, a)
		else:
			var v: Vector2 = s["v"]
			v.y += 620.0 * delta
			s["v"] = v
			n.position += v * delta
			n.modulate = Color(1, 1, 1, a)
		keep.append(s)
	_shards = keep
