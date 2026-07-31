extends Control

## 训龟大师 配置界面 (用户2026-07-26: 主菜单独立入口, 选形象 + 配【全部技能五选一·单个】)。
## ★设计: 被动+主动放一起, 只能选 1 个。选被动=没有主动Q; 选主动=没有被动。
## 技能用【图标卡片】展示(图标+名+被动/主动标签), 居中排版, 说明卡带底板。
## 选择写 GameState.trainer_appearance/trainer_skill + save(), 战斗时读取。

## 全部技能池(被动 + 主动·五选一)。icon 供卡片显示; kind 显示"被动/主动"。
const SKILLS := [
	{"id": "magic_stone", "kind": "被动", "name": "魔法石", "icon": "res://assets/sprites/vfx/magic-stone-icon.png", "desc": "装配后大师攻击力 ×10。普攻附带 2% 目标最大生命 魔法伤害；每次攻击自身 +5% 攻速(可叠·不封顶·整局不清零)。攒到 10/25/50 层时身上会亮起共鸣特效。"},
	{"id": "hook", "kind": "主动", "name": "钩锁", "icon": "res://assets/sprites/vfx/hook-skill-icon.png", "desc": "朝方向甩钩(射程600)勾住第一个敌人：眩晕4秒、一段段拽向大师、受伤+25%。CD20，空放返还。"},
	{"id": "fury_potion", "kind": "主动", "name": "怒火药水", "icon": "res://assets/sprites/vfx/fury-potion-icon.png", "desc": "朝700码内一点丢药水：落点300码内友军5秒 +30%攻速 / +25%龟能充能 / +25%移速。CD16。"},
	{"id": "whistle", "kind": "主动", "name": "口哨", "icon": "res://assets/sprites/vfx/whistle-icon.png", "desc": "随机1个：给友军700临时生命(5秒·到期按比例削) / 召灵体小龟蓄力放气波(2000码贯穿·命中扣100+15%目标最大生命真实伤害+击飞+削甲30%持续5秒) / 友军狂暴4秒(+20%攻击力·+20点吸血·免疫死亡)。CD14。"},
	{"id": "glacier", "kind": "主动", "name": "冰川", "icon": "res://assets/sprites/vfx/glacier-icon.png", "desc": "沿方向生成500码冰川(6秒)：站上的敌 -40%移速 + 受伤+20%。CD17。"},
	{"id": "hunt_order", "kind": "主动", "name": "猎龟令", "icon": "res://assets/sprites/vfx/hunt-order-icon.png", "desc": "锁定600码内一个敌人15秒：它受到伤害+15%，且以它为圆心400码内的我方友军优先攻击它(圈随它移动)。CD30(空放返还一半)。"},
	{"id": "tame", "kind": "主动", "name": "驯服", "icon": "res://assets/sprites/vfx/tame-icon.png", "desc": "标记600码内一个敌人：它死亡时不真死，以30%最大生命重生并归顺我方(重生2.5秒无敌)，此后每秒损失2%最大生命。可跨入终极战场。CD60(空放返还一半)。"},
]
## 三形象(2026-07-26 定稿·PixelLab)。sprite = 南向立绘, 用于选择卡缩略 + 大预览。
const APPEARANCES := [
	{"id": "villager", "name": "村民", "sprite": "res://assets/sprites/trainer/trainer-villager.png"},
	{"id": "mage", "name": "魔法师", "sprite": "res://assets/sprites/trainer/trainer-mage.png"},
	{"id": "girl", "name": "少女", "sprite": "res://assets/sprites/trainer/trainer-girl.png"},
]

const GOLD := Color(1.0, 0.86, 0.4)

var _sel_skill: String = "hook"
var _sel_appearance: String = "villager"
var _desc_label: RichTextLabel = null
var _skill_cards: Array = []        # [ [Button, id], ... ]
var _appear_cards: Array = []       # [ [Button, id], ... ]
var _preview_rect: TextureRect = null

func _ready() -> void:
	_sel_skill = _valid_skill(str(GameState.trainer_skill))
	_sel_appearance = _valid_appearance(str(GameState.trainer_appearance))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _valid_skill(id: String) -> String:
	for s in SKILLS:
		if str(s["id"]) == id:
			return id
	return "hook"

## 校验形象 id(旧档"default"/脏数据 → 村民)。
func _valid_appearance(id: String) -> String:
	for a in APPEARANCES:
		if str(a["id"]) == id:
			return id
	return "villager"

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.10, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# CenterContainer 直接铺满 → 面板水平+垂直居中(PC/手机通用·游戏横屏锁定·1280×720 stretch)。
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# SafeArea: 居中面板本就远离边缘(刘海在横屏两侧)；再把面板宽度夹进安全区双保险。
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var m: Vector4 = SafeArea.margins(vp, 12.0)
	var pw: float = minf(1060.0, vp.x - m.x - m.z)   # 横屏用横向空间(两栏)·夹进安全区

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.12, 0.17, 0.96), GOLD.darkened(0.2), 2, 14))
	panel.custom_minimum_size = Vector2(pw, 0)
	center.add_child(panel)

	var pad := MarginContainer.new()
	for s in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + s, 22)
	for s in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 14)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)

	var title := Label.new()
	title.text = "🐢 训龟大师"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# ── 主体两栏(横屏用横向空间): 左=形象  右=技能+说明 ──
	var main := HBoxContainer.new()
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override("separation", 26)
	box.add_child(main)

	# 左栏: 形象
	var col_l := VBoxContainer.new()
	col_l.add_theme_constant_override("separation", 8)
	col_l.add_child(_heading("形象"))
	col_l.add_child(_appearance_section())
	main.add_child(col_l)

	# 竖分隔线
	var vsep := Panel.new()
	vsep.add_theme_stylebox_override("panel", _sb(Color(0.28, 0.32, 0.40, 0.55), Color(0, 0, 0, 0), 0, 0))
	vsep.custom_minimum_size = Vector2(2, 0)
	vsep.size_flags_vertical = Control.SIZE_FILL
	main.add_child(vsep)

	# 右栏: 技能 + 说明
	var col_r := VBoxContainer.new()
	col_r.add_theme_constant_override("separation", 8)
	col_r.add_child(_heading("技能  （五选一 · 被动或主动只能带一样）"))
	col_r.add_child(_skill_row())
	var desc_panel := PanelContainer.new()
	desc_panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.07, 0.11, 0.9), Color(0.3, 0.36, 0.46), 1, 8))
	col_r.add_child(desc_panel)
	var dpad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		dpad.add_theme_constant_override("margin_" + s, 14)
	desc_panel.add_child(dpad)
	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.custom_minimum_size = Vector2(640, 50)
	_desc_label.add_theme_font_size_override("normal_font_size", 17)
	dpad.add_child(_desc_label)
	_refresh_desc()
	main.add_child(col_r)

	# ── 按钮 ──
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var save_btn := Button.new()
	save_btn.text = "保存并返回"
	save_btn.custom_minimum_size = Vector2(200, 54)
	save_btn.pressed.connect(_save_and_back)
	row.add_child(save_btn)
	var back_btn := Button.new()
	back_btn.text = "返回(不保存)"
	back_btn.custom_minimum_size = Vector2(200, 54)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	row.add_child(back_btn)

func _heading(t: String) -> Label:
	var lb := Label.new()
	lb.text = t
	lb.add_theme_font_size_override("font_size", 20)
	lb.modulate = GOLD
	return lb

## 形象区(竖排·用于左栏): 上=大预览(选中形象站投影上), 下=3 个可选形象卡(缩略+名·选中金框)。
func _appearance_section() -> Control:
	var h := VBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)

	# 大预览(左·带框)
	var prev_panel := PanelContainer.new()
	prev_panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.07, 0.11, 0.9), Color(0.32, 0.38, 0.48), 1, 8))
	var pm := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + s, 8)
	prev_panel.add_child(pm)
	# 舞台: 人物底对齐"站"在椭圆投影上(不再垂直居中贴墙)。呼吸待机动画留 R6。
	var stage := VBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_END
	stage.add_theme_constant_override("separation", 0)
	stage.custom_minimum_size = Vector2(120, 126)
	_preview_rect = TextureRect.new()
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.custom_minimum_size = Vector2(102, 104)
	_preview_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_preview_rect)
	var shadow := Panel.new()
	shadow.add_theme_stylebox_override("panel", _oval(Color(0, 0, 0, 0.42)))
	shadow.custom_minimum_size = Vector2(66, 13)
	shadow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shadow)
	pm.add_child(stage)
	h.add_child(prev_panel)

	# 3 形象选择卡(右)
	_appear_cards.clear()
	var cardrow := HBoxContainer.new()
	cardrow.add_theme_constant_override("separation", 10)
	cardrow.alignment = BoxContainer.ALIGNMENT_CENTER
	for opt in APPEARANCES:
		var oid: String = str(opt["id"])
		var card := Button.new()
		card.toggle_mode = true
		card.custom_minimum_size = Vector2(80, 96)
		card.add_theme_stylebox_override("normal", _sb(Color(0.12, 0.15, 0.20, 1), Color(0.28, 0.32, 0.40), 1, 8))
		card.add_theme_stylebox_override("hover", _sb(Color(0.16, 0.20, 0.26, 1), GOLD.darkened(0.35), 1, 8))
		card.add_theme_stylebox_override("pressed", _sb(Color(0.21, 0.24, 0.15, 1), GOLD, 2, 8))
		card.add_theme_stylebox_override("hover_pressed", _sb(Color(0.24, 0.28, 0.17, 1), GOLD, 2, 8))
		card.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 1)
		var thumb := TextureRect.new()
		var sp: String = str(opt["sprite"])
		thumb.texture = load(sp) if ResourceLoader.exists(sp) else null
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = Vector2(46, 56)
		thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(thumb)
		var nm := Label.new()
		nm.text = str(opt["name"])
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 15)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		card.add_child(vb)
		card.pressed.connect(func():
			_sel_appearance = oid
			_refresh_appearance())
		cardrow.add_child(card)
		_appear_cards.append([card, oid])
	h.add_child(cardrow)
	_refresh_appearance()
	return h

## 刷新: 大预览换成选中形象立绘 + 卡片选中金框。
func _refresh_appearance() -> void:
	for c in _appear_cards:
		c[0].button_pressed = (str(c[1]) == _sel_appearance)
	if _preview_rect != null:
		for opt in APPEARANCES:
			if str(opt["id"]) == _sel_appearance:
				var sp: String = str(opt["sprite"])
				_preview_rect.texture = load(sp) if ResourceLoader.exists(sp) else null
				return

## 技能卡片横排(居中·图标+名+被动/主动标签·单选高亮)。
func _skill_row() -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	_skill_cards.clear()
	for opt in SKILLS:
		var oid: String = str(opt["id"])
		var card := Button.new()
		card.toggle_mode = true
		card.custom_minimum_size = Vector2(124, 108)
		card.button_pressed = (oid == _sel_skill)
		# 卡片底板 + 选中=金框高亮(不再靠明暗)
		card.add_theme_stylebox_override("normal", _sb(Color(0.13, 0.16, 0.22, 1), Color(0.30, 0.34, 0.42), 1, 9))
		card.add_theme_stylebox_override("hover", _sb(Color(0.17, 0.21, 0.28, 1), GOLD.darkened(0.35), 1, 9))
		card.add_theme_stylebox_override("pressed", _sb(Color(0.21, 0.24, 0.15, 1), GOLD, 3, 9))
		card.add_theme_stylebox_override("hover_pressed", _sb(Color(0.24, 0.28, 0.17, 1), GOLD, 3, 9))
		card.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		var ip: String = str(opt["icon"])
		icon.texture = load(ip) if ResourceLoader.exists(ip) else null
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE          # 忽略贴图原尺寸(否则大图撑爆卡片)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(52, 52)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER    # 钉死 60×60·居中, 不随卡片拉伸
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(icon)
		var nm := Label.new()
		nm.text = str(opt["name"])
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 16)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		var kd := Label.new()
		kd.text = str(opt["kind"])
		kd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kd.add_theme_font_size_override("font_size", 12)
		kd.modulate = Color(0.5, 0.85, 1.0) if str(opt["kind"]) == "被动" else Color(1.0, 0.7, 0.5)
		kd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(kd)
		card.add_child(vb)
		card.pressed.connect(func():
			_sel_skill = oid
			_refresh_cards()
			_refresh_desc())
		h.add_child(card)
		_skill_cards.append([card, oid])
	_refresh_cards()
	return h

## 刷新卡片选中态: 选中=金框高亮(pressed 样式), 其余=普通底板。
func _refresh_cards() -> void:
	for c in _skill_cards:
		var card: Button = c[0]
		card.button_pressed = (str(c[1]) == _sel_skill)

func _refresh_desc() -> void:
	if _desc_label == null:
		return
	for s in SKILLS:
		if str(s["id"]) == _sel_skill:
			var kc: String = "5cc6ff" if str(s["kind"]) == "被动" else "ffb27f"
			_desc_label.text = "[color=#%s][b]%s[/b][/color]  [b]%s[/b]\n%s" % [kc, s["kind"], s["name"], s["desc"]]
			return
	_desc_label.text = ""

## 造一个圆角描边底板 StyleBox。
func _sb(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	return sb

## 椭圆投影(全圆角矮条 ≈ 椭圆)。
func _oval(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(7)
	return sb

## 写回 GameState + 存盘(抽出来便于门禁测, 不含切场景)。
func _write_loadout() -> void:
	GameState.trainer_appearance = _sel_appearance
	GameState.trainer_skill = _sel_skill
	GameState.save()

func _save_and_back() -> void:
	_write_loadout()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
