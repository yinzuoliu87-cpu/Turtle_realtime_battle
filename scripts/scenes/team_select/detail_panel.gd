class_name DetailPanel
extends RefCounted
## 选龟页·右栏详情面板渲染(立绘/属性/被动·_set_detail_pet协调器留主场景)
## 类内名不变;外部名加 battle.

## 能渲染 BBCode 的 tooltip 宿主 —— 被动 chip 的 tooltip 正文是 `render_bbcode` 的产物,
## 不挂它就走 Godot 的系统 tooltip(纯 Label), 标记会原样印给玩家(2026-10-02 实拍)。
## ★用 preload 常量而不是靠 class_name: 这份脚本没有 class_name(有意的, 见它的头注)。
const RichTooltip = preload("res://scripts/scenes/rich_tooltip.gd")
const TurtleStats := preload("res://scripts/gamedata/turtle_stats.gd")   # 定位(ROLE): 与移速 / 攻速同一份事实源

var host
## 上一次显示的是谁(换了一只 ⇒ 立绘弹进来; 2026-10-30 动效)
var _last_pid := ""

func _init(b) -> void:
	host = b

func _build_detail_region() -> void:
	## ★2026-10-30 选龟页重做: 右栏垫一整块说明卡底板(insp-card, 与商店 / 背包弹出的说明卡同一张)。
	##   原来坐在背景烤死的上下两块深色格子上, 而内容没对准格子(技能那行掉出下格, 属性数字贴死在格子右边)。
	var fr := Panel.new()
	fr.name = "DetailFrame"
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.root.add_child(fr)
	host._place(fr, "detailFrame")
	fr.add_theme_stylebox_override("panel", _frame_box())
	fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素框不插值
	# 上区: 立绘/名字/属性/被动 各自独立成块 (可拖可缩·用户2026-07-18); 内容由 _refresh_detail 填
	host._dt_portrait = _make_detail_panel("dtPortrait")
	host._dt_name = _make_detail_panel("dtName")
	host._dt_stats = _make_detail_panel("dtStats")
	host._dt_passive = _make_detail_panel("dtPassive")

	# 下块 (技能 3选1)
	var bot_panel = PanelContainer.new()
	host.root.add_child(bot_panel)
	host._place(bot_panel, "detailBottom")
	bot_panel.add_theme_stylebox_override("panel", host._dark_panel())
	host._detail_bottom = VBoxContainer.new()
	host._detail_bottom.alignment = BoxContainer.ALIGNMENT_CENTER   # PoC #poc-detail-bottom justify-center
	host._detail_bottom.add_theme_constant_override("separation", host._sp(10))
	bot_panel.add_child(host._detail_bottom)


## 右栏底板: 说明卡同一张 insp-card(12px 九宫格); 贴图缺失退回不透明深底 + 黄铜细边(与说明卡的兜底同色)。
func _frame_box() -> StyleBox:
	var p := "res://assets/sprites/battlehud/insp-card.png"
	if ResourceLoader.exists(p):
		var tb := StyleBoxTexture.new()
		tb.texture = load(p)
		tb.set_texture_margin_all(12)
		return tb
	var f := StyleBoxFlat.new()
	f.bg_color = Color("#120e0a")
	f.set_border_width_all(2); f.border_color = Color("#a5751d")
	f.set_corner_radius_all(0)
	return f


## 建一个独立信息子块面板 (透明底·按 RL key 放置·登记进编辑器·不挡下层点击)
func _make_detail_panel(key: String) -> PanelContainer:
	var p = PanelContainer.new()
	host.root.add_child(p)
	host._place(p, key)
	p.add_theme_stylebox_override("panel", host._dark_panel())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	return p


## 给 Label 加投影 (近似 CSS text-shadow)
# ─── 右栏详情 ──────────────────────────────────────────────────
func _refresh_detail() -> void:
	for cont in [host._dt_portrait, host._dt_name, host._dt_stats, host._dt_passive, host._detail_bottom]:
		if cont != null:
			for c in cont.get_children():
				c.queue_free()
	if host.detail_pet_id == "":
		return
	var pet: Dictionary = DataRegistry.pet_by_id.get(host.detail_pet_id, {})
	if pet.is_empty():
		return
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = host.RARITY_COLOR.get(rarity, Color.WHITE)
	# 数值=base×getLevelBonus(1+(lv-1)×0.05), 仅等级加成不乘稀有(1:1 PoC TeamSelectScene.ts:788-792).
	# 原 Godot 用裸 base + 硬编 Lv.1 → 有等级的龟数值/等级都不对.
	var det_lv: int = GameState.battle_level_for(host.detail_pet_id)   # ★10-11: 原读 get_pet_level(真玩家恒为 1), 与实战不符
	var lv_bonus: float = 1.0 + (det_lv - 1) * 0.05
	var hp: int = roundi(pet.get("hp", 0) * lv_bonus)
	var atk: int = roundi(pet.get("atk", 0) * lv_bonus)
	var def_: int = roundi(pet.get("def", 0) * lv_bonus)
	var mr: int = roundi(pet.get("mr", pet.get("def", 0)) * lv_bonus)

	# ── 上块: 立绘(居中+底部辉光) + 名/稀有/Lv 行 + 2列属性 + 被动 ──
	# PoC .dp-portrait: 高156 居中 + 底部 radial 金色辉光; 全身 idle 动画
	# 立绘外包一层等高(156)壳, 壳内底部叠 radial 金辉光(behind) + 立绘(front), 不改 VBox 布局.
	var portrait_wrap = Control.new()
	portrait_wrap.custom_minimum_size = Vector2(0, host._sp(164))   # 立绘块高(2026-10-30 重做: 156 → 164)
	portrait_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_wrap.clip_contents = true
	# 底部 radial 金色辉光 (PoC index.html:563: radial-gradient(ellipse at 50% 80%, rgba(255,216,107,.12), transparent 70%))
	var glow = TextureRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var grad = Gradient.new()
	grad.set_color(0, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.12))   # rgba(255,216,107,.12)
	grad.set_color(1, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.0))    # transparent 70%
	var gtex = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.8)            # ellipse at 50% 80% (近底部)
	gtex.fill_to = Vector2(0.5, 0.8 + 0.7)        # transparent 70% → 半径 0.7 (纵向)
	gtex.width = 256
	gtex.height = 256
	glow.texture = gtex
	portrait_wrap.add_child(glow)
	# PoC 立绘 = buildPetImgHTML(pet,124) 124px 帧, img max-height 150 (ts:810 / index.html:565).
	#   不撑满壳: 居中一个 124×150(×s) 盒, KEEP_ASPECT_CENTERED 不变形/不放大.
	var portrait = TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_CENTER)
	## 2026-10-30 重做: 124×150 → 200×160(右栏比原来宽, 立绘是这一栏的主角)
	var pw = float(host._sp(200))
	var ph = float(host._sp(160))
	portrait.size = Vector2(pw, ph)
	portrait.position = Vector2(-pw * 0.5, -ph * 0.5)   # 居中 (anchor 中心 + 自身一半偏移)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._apply_pet_idle_texture(portrait, pet)
	portrait_wrap.add_child(portrait)            # 立绘在辉光之上
	host._dt_portrait.add_child(portrait_wrap)
	## 没有逐帧待机图的龟(没挂 idle_tw): 立绘「呼吸」, 与统领卡同一种(UnitCardArt.breathe_idle; 2026-10-31 录屏量出 11 只一动不动)
	var still: bool = not portrait.has_meta("idle_tw")
	## 换了一只看 ⇒ 立绘从小弹到原大 + 淡入(2026-10-30 用户「他们游戏是动态的」); 弹完再开始呼吸(两条都动缩放, 不能同时)
	if _last_pid != "" and _last_pid != host.detail_pet_id:
		portrait.pivot_offset = portrait.size * 0.5
		portrait.scale = Vector2.ONE * 0.8
		portrait.modulate.a = 0.0
		var ptw := portrait.create_tween().set_parallel(true)
		ptw.tween_property(portrait, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ptw.tween_property(portrait, "modulate:a", 1.0, UIPalette.T_BASE)
		if still:
			ptw.chain().tween_callback(func() -> void: UnitCardArt.breathe_idle(portrait))
	elif still:
		UnitCardArt.breathe_idle(portrait)
	_last_pid = host.detail_pet_id

	# PoC .dp-name-row: 居中, 名 + 填充稀有 badge + Lv
	var name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", host._sp(8))
	var nm = Label.new()
	nm.text = pet.get("name", "?")
	nm.add_theme_font_size_override("font_size", host._sf(26))
	nm.add_theme_color_override("font_color", rcolor)
	nm.add_theme_color_override("font_outline_color", Color("#0d0805"))
	nm.add_theme_constant_override("outline_size", 5)
	name_row.add_child(nm)
	name_row.add_child(host._make_rarity_badge(rarity, rcolor, 12))   # PoC .dp-rarity 填充底 font:12px
	var lvl = Label.new()
	lvl.text = "Lv.%d" % det_lv
	lvl.add_theme_font_size_override("font_size", host._sf(17))
	lvl.add_theme_color_override("font_color", Color("#ffd86b"))
	name_row.add_child(lvl)
	host._dt_name.add_child(name_row)

	## ★2026-10-30 选龟页重做: 四项属性数字拿掉(用户「右侧4个属性感觉不用显示，或者不能去这么显示吧」)。
	##   同类「出战前选角色」界面 14 款(C:/tmp/ts_ref2/选角色参考.png)没有一款把属性数字常驻在编队页上:
	##   5 款只给战力总数、5 款只给等级 / 星级 / 定位词, 用数字的 3 款都在点开的详情里。
	##   ⇒ 这一格换成一行定位词(Dota Underlords 的做法), 取自 turtle_stats.ROLE(移速 / 攻速的同一份事实源)。
	##   上面算的 hp / atk / def_ / mr 仍要留着: 被动描述里的公式按它们算数(见下面 fake_f)。
	var role: String = str(TurtleStats.ROLE.get(host.detail_pet_id, ""))
	var role_lbl := Label.new()
	role_lbl.name = "Role"
	role_lbl.text = ("%s · %s" % [role.substr(0, 2), role.substr(2)]) if role.length() >= 4 else role
	role_lbl.add_theme_font_size_override("font_size", host._sf(24))
	role_lbl.add_theme_color_override("font_color", Color("#e7c68a"))
	role_lbl.add_theme_color_override("font_outline_color", Color("#0d0805"))
	role_lbl.add_theme_constant_override("outline_size", 5)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._dt_stats.add_child(role_lbl)

	# 被动 chip (PoC .dp-passive-chip: 绿底圆角框 + 图标 + 名(#7dffb3) + "被动" pill)
	var passive_raw = pet.get("passive")
	if passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty():
		var passive: Dictionary = passive_raw
		var chip = PanelContainer.new()
		## 2026-10-30 重做: 不透明深底 + 直角绿边(与技能格 / 说明卡同一族)。原来是金属小框染绿 + 一枚绿色小药丸「被动」。
		var chip_sb = StyleBoxFlat.new()
		chip_sb.bg_color = Color("#0c120d")
		chip_sb.border_color = Color("#5fbf8a")
		chip_sb.set_border_width_all(2)
		chip_sb.set_corner_radius_all(0)
		chip_sb.content_margin_left = host._sp(8); chip_sb.content_margin_right = host._sp(8)
		chip_sb.content_margin_top = host._sp(5); chip_sb.content_margin_bottom = host._sp(5)
		chip.add_theme_stylebox_override("panel", chip_sb)
		var prow = HBoxContainer.new()
		prow.add_theme_constant_override("separation", host._sp(6))
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "" and pi_path.ends_with(".png"):
			var full = "res://assets/sprites/" + pi_path
			if ResourceLoader.exists(full):
				var pic = TextureRect.new()
				pic.texture = load(full)
				pic.custom_minimum_size = Vector2(host._sp(34), host._sp(34))   # 被动图标调大(用户2026-07-18·原22)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				prow.add_child(pic)
		var pnm = Label.new()
		pnm.text = passive.get("name", "被动")
		pnm.add_theme_font_size_override("font_size", host._sf(20))   # 被动名(用户2026-07-18 13→17; 2026-10-30 重做 →20)
		pnm.add_theme_color_override("font_color", Color("#7dffb3"))
		pnm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pnm)
		# "被动" 小签
		## ★★2026-09-28 两处改动, 都是实拍(`C:/tmp/tsshots/before/2_filled.png` 裁右栏)量出来的:
		##   ① **直角**。原 `_sp(4)` 圆角 —— 与技能角标同族, 是这一屏 4 个【圆角盒】之一。
		##      24x35 远低于 `UISkin.MIN_FRAME_PX`(40) ⇒ 不套九宫格, 去网页味靠直角。
		##   ② **贴着字走, 别被撑高**。原来没给垂直 size_flags, PanelContainer 默认 FILL,
		##      于是它跟着那行 34px 的被动图标一起被拉成 24x35 的**竖条**, 字缩在中间 ——
		##      实拍看就是"一块灰绿方块里塞了两个字"。SHRINK_CENTER 之后它才是一枚签。
		var tag_pc = PanelContainer.new()
		tag_pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		## 2026-10-30 重做: 「被动」两个字不再套一块半透绿底(那是这一栏最后一枚网页签)
		var tag_sb = StyleBoxEmpty.new()
		tag_sb.content_margin_left = host._sp(5); tag_sb.content_margin_right = host._sp(5)
		tag_sb.content_margin_top = host._sp(1); tag_sb.content_margin_bottom = host._sp(1)
		tag_pc.add_theme_stylebox_override("panel", tag_sb)
		var tag_lbl = Label.new()
		tag_lbl.text = "被动"
		tag_lbl.add_theme_font_size_override("font_size", host._sf(14))
		tag_lbl.add_theme_color_override("font_color", Color("#5fbf8a"))
		tag_pc.add_child(tag_lbl)
		prow.add_child(tag_pc)
		chip.add_child(prow)
		# 被动描述只在 hover 看 (1:1 PoC ts:796/825 "悬浮看描述 省空间") — 不常驻铺文字(撑爆面板的自创)
		var fake_f = {"atk": atk, "def": def_, "mr": mr, "maxHp": hp, "crit": pet.get("crit", 0.25), "lv": det_lv, "passive": passive}
		## ★★2026-10-02: 挂能渲染 BBCode 的 tooltip 宿主。
		##   下面这行塞进去的是 `render_bbcode` 的产物(带 [color]/[b]/[img]), 而 Godot 的
		##   【系统 tooltip 是一个纯 Label】—— 实拍确认它把 `[color=#ff4444]+20%[/color]`
		##   这种标记**原样印在屏幕上**(docs/plans/20261002-文案落点BBCode普查.md 存图)。
		##   背包格子 2026-07-22 就踩过同一条并修好了, 这里只是一直没挂。
		##   ⚠ 顺序: `set_script` 要在写 `tooltip_text` 之前 —— 换脚本不会丢 tooltip_text
		##     (那是 Control 的原生属性, 不随脚本走), 但先挂再写读起来才是因果顺序。
		chip.set_script(RichTooltip)
		chip.tooltip_text = "%s\n%s" % [passive.get("name", "被动"), SkillText.render_bbcode_formula(str(passive.get("brief", "")), fake_f, passive, 14)]
		# 内容 IGNORE 鼠标 → 整 chip 捕获 hover 出 tooltip
		prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pnm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 点/触 被动 → 弹窗看描述 (PC 悬停之外再补点按, 手机唯一途径)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var _passive_tip: String = chip.tooltip_text
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				host._show_detail_popup_from(_passive_tip, Color("#7dffb3"), chip.get_global_rect()))
		host._dt_passive.add_child(chip)

	# ── 下块: 技能 3选1 ──
	host._skill_picker._build_skill_picker(pet)


