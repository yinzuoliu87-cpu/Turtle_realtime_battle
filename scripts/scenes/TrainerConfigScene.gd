extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")

## 训龟大师 配置界面 (用户2026-07-26: 主菜单独立入口, 选形象 + 配【全部技能 N 选 1·单个】)。
## ★设计: 被动+主动放一起, 只能选 1 个。选被动=没有主动Q; 选主动=没有被动。
## 版式见下方「2026-10-19 整页重做」一节。
## 选择写 GameState.trainer_appearance/trainer_skill + save(), 战斗时读取。

## 全部技能池(被动 + 主动·**N 选 1**, N 就是本数组长度)。icon 供卡片显示; kind 显示"被动/主动"。
const SKILLS := [
	{"id": "magic_stone", "kind": "被动", "name": "魔法石", "icon": "res://assets/sprites/vfx/magic-stone-icon.png", "desc": "训龟大师的攻击额外造成 2% 目标最大生命值的魔法伤害。每次攻击获得 +3% 攻击速度，可无限叠加。层数达到 10、25、50 时亮起共鸣光效。"},
	{"id": "hook", "kind": "主动", "name": "钩锁", "icon": "res://assets/sprites/vfx/hook-skill-icon.png", "desc": "训龟大师朝最近的敌人射出钩索，命中第一个敌人时将其眩晕 4 秒并拉至身边，期间目标受到的伤害 +25%。冷却 20 秒，未命中时冷却 10 秒。"},
	{"id": "fury_potion", "kind": "主动", "name": "怒火药水", "icon": "res://assets/sprites/vfx/fury-potion-icon.png", "desc": "训龟大师朝最近的敌人投掷药水。落点附近的友军获得 5 秒狂热：+30% 攻击速度、+25% 移动速度、+25% 龟能充能。冷却 16 秒。"},
	{"id": "whistle", "kind": "主动", "name": "口哨", "icon": "res://assets/sprites/vfx/whistle-icon.png", "desc": "训龟大师吹响口哨，随机召唤以下一种。护盾：全体友军获得 700 护盾，5 秒后逐渐消退。灵龟：召出一只灵体小龟，蓄力后打出一道贯穿气波，对命中的敌人造成 100 点 + 15% 目标最大生命值的真实伤害并将其击飞，护甲降低 30%，持续 5 秒。狂暴：全体友军 4 秒内攻击力 +20%、生命偷取 +20%，且不会死亡。冷却 14 秒。"},
	{"id": "glacier", "kind": "主动", "name": "冰川", "icon": "res://assets/sprites/vfx/glacier-icon.png", "desc": "训龟大师朝最近的敌人生成一条冰川，持续 6 秒。冰面上的敌人移动速度降低 40%，受到的伤害 +20%。冷却 17 秒。"},
	{"id": "hunt_order", "kind": "主动", "name": "猎龟令", "icon": "res://assets/sprites/vfx/hunt-order-icon.png", "desc": "训龟大师锁定最近的敌人，持续 15 秒：目标受到的伤害 +15%，其周围的友军优先攻击该目标（范围随目标移动）。冷却 30 秒，未命中时冷却 15 秒。"},
	{"id": "tame", "kind": "主动", "name": "驯服", "icon": "res://assets/sprites/vfx/tame-icon.png", "desc": "训龟大师标记最近的敌人。该敌人下次死亡时以 30% 最大生命值复活并加入我方，复活后 2.5 秒无敌，此后每秒损失 2% 最大生命值，持续作战至终极战场。冷却 60 秒，未命中时冷却 30 秒。"},
]
## 三形象(2026-07-26 定稿·PixelLab)。sprite = 南向立绘, 用于选择卡缩略 + 大预览。
const APPEARANCES := [
	{"id": "villager", "name": "村民", "sprite": "res://assets/sprites/trainer/trainer-villager.png"},
	{"id": "mage", "name": "魔法师", "sprite": "res://assets/sprites/trainer/trainer-mage.png"},
	{"id": "girl", "name": "少女", "sprite": "res://assets/sprites/trainer/trainer-girl.png"},
]

## ══════════════════════════════════════════════════════════════════════
##  2026-10-19 整页重做(用户「训龟大师页面你找人来优化好」)
## ══════════════════════════════════════════════════════════════════════
## 方案书: docs/plans/20261019-训龟大师页优化.md(参考图、验收清单、未决点都在那里)。
##
## 版式(1280×720 设计框, UIFrame 居中; 顶栏自己铺满视口宽):
##   ┌ 顶栏: ← 训龟大师 ─────────────────────────────────────────────┐
##   │ 左 = 形象展台: 聚光 + 石台 + 6 倍大立绘 + 形象名 + 3 个形象槽     │
##   │ 右 = 技能: 「被动 | 主动」两组一行 7 槽 + 下方选中技能的详情       │
##   └────────────────────────────────────────────────────────────────┘
## ★点一下 = 装配(并存盘), 不再有「保存 / 取消」两个键 —— 参考里的角色/技能装配页
##   (Darkest Dungeon 名册页、Archero 英雄页)都是点选即生效、左上返回。
##   旧版「取消」会静默丢掉改动, 而离开的唯一出口是顶栏返回 ⇒ 返回时同样再存一次。
## ★逻辑不动: 仍然是 SKILLS 里 N 选 1、写 GameState.trainer_skill / trainer_appearance。

const TPSkin := preload("res://scripts/scenes/trainer/trainer_page_skin.gd")

const GOLD := TPSkin.GOLD

## ── 版式常量(设计坐标) ──────────────────────────────────────────
const TOP := 102.0                 # 顶栏 87 + 15
const BOTTOM := 704.0
const L_X := 24.0                  # 左栏(形象展台)
const L_W := 404.0
const R_X := 448.0                 # 右栏(技能)
const R_W := 808.0
const PAD := 24.0                  # 面板内边距(贴图边带 9, 留足 15 的余量)

## 技能槽: 92 ≥ 81(44pt 触控下限)。7 个 + 组间距 30 = 724 ≤ 右栏内宽 760。
const CARD_W := 92.0
const CARD_H := 92.0
const CARD_GAP := 10.0
const GROUP_GAP := 30.0
## 形象槽: 104, 立绘 ×2 放进去。
const APP_W := 104.0
const APP_H := 104.0
const APP_GAP := 18.0
## 大立绘倍率: 原生 20×~40 ⇒ ×6 ≈ 120×240, 是这一页的主角。
const HERO_SCALE := 6.0
## 详情图标槽: 图标 64 原生 ×2 = 128(图标四周本身有透明边, 136 的槽不会让画面压到边带)。
const DETAIL_SLOT := 136.0
## 说明文字字号。
const DESC_PX := 19

var _sel_skill: String = "hook"
var _sel_appearance: String = "villager"
var _desc_label: RichTextLabel = null
var _skill_cards: Array = []        # [ [Button, id, 名字 Label, 已装配徽记], ... ]
var _appear_cards: Array = []       # [ [Button, id, 名字 Label], ... ]
var _preview_rect: TextureRect = null
var _hero_home_y: float = 0.0
var _app_name_label: Label = null
var _detail_icon: TextureRect = null
var _detail_name: Label = null
var _detail_kind_box: HBoxContainer = null
var _top_bar = null

func _ready() -> void:
	_sel_skill = _valid_skill(str(GameState.trainer_skill))
	_sel_appearance = _valid_appearance(str(GameState.trainer_appearance))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# ★UI 双端适配: 内容装进 1280×720 设计框并居中于真实视口(放在 _ready 最后)。
	UIFrame.attach(self)

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

func _skill_of(id: String) -> Dictionary:
	for s in SKILLS:
		if str(s["id"]) == id:
			return s
	return {}


func _build_ui() -> void:
	_bg()
	var sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		"title": "训龟大师",
		"palette": TopBar.DEEP,
		"width": 1280.0,
		"safe_left": sm.x,
		"safe_right": sm.z,
		"on_back": _save_and_back,
	})
	_build_stage()
	_build_skills()
	_refresh_appearance()
	_refresh_cards()
	_refresh_desc()


## 一块大面板(不透明、直角、像素铆钉框)。
func _panel(x: float, y: float, w: float, h: float) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", TPSkin.box("panel.png", TPSkin.PANEL_MARGIN))
	p.position = Vector2(x, y)
	p.size = Vector2(w, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


## 区块标题: 金字 + 一条通到右沿的细线(Darkest Dungeon 名册页的分区写法, 不用括号说明)。
func _section_head(parent: Control, txt: String, y: float, w: float) -> Label:
	var lb := TPSkin.label(txt, 20, GOLD)
	lb.position = Vector2(PAD, y)
	parent.add_child(lb)
	var rule := ColorRect.new()
	rule.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
	rule.position = Vector2(PAD, y + 32.0)
	rule.size = Vector2(w - PAD * 2.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return lb


## ── 左栏: 形象展台 ────────────────────────────────────────────────
func _build_stage() -> void:
	var p := _panel(L_X, TOP, L_W, BOTTOM - TOP)
	_section_head(p, "形象", 14.0, L_W)

	var cx := L_W * 0.5
	## 聚光(像素抖动的三档光, 不是软渐变) —— 让人物从底色里站出来。
	var lt := TPSkin.pixel_rect(TPSkin.tex("spotlight.png"), Vector2(320, 280))
	lt.position = Vector2(cx - 160.0, 60.0)
	p.add_child(lt)
	## 石台: 原生 60×20 ×4。
	var ped := TPSkin.pixel_rect(TPSkin.tex("pedestal.png"), Vector2(240, 80))
	ped.position = Vector2(cx - 120.0, 300.0)
	p.add_child(ped)
	## 立绘: 用原生尺寸 × 整数倍, 像素不变形。脚落在石台顶面中线(石台顶面椭圆中心在原生 y=7 ⇒ ×4 = 28)。
	_preview_rect = TextureRect.new()
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_preview_rect)

	_app_name_label = TPSkin.label("", 28, TPSkin.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_app_name_label.position = Vector2(0, 392.0)
	_app_name_label.size = Vector2(L_W, 40)
	p.add_child(_app_name_label)

	_appear_cards.clear()
	var total := APP_W * APPEARANCES.size() + APP_GAP * (APPEARANCES.size() - 1)
	var x0 := (L_W - total) * 0.5
	var y0 := 448.0
	for i in range(APPEARANCES.size()):
		var opt: Dictionary = APPEARANCES[i]
		var oid: String = str(opt["id"])
		var card := Button.new()
		card.toggle_mode = true
		card.custom_minimum_size = Vector2(APP_W, APP_H)
		card.size = Vector2(APP_W, APP_H)
		card.position = Vector2(x0 + i * (APP_W + APP_GAP), y0)
		TPSkin.skin_slot(card)
		var sp: String = str(opt["sprite"])
		var t: Texture2D = load(sp) if ResourceLoader.exists(sp) else null
		## 缩略: 原生 ×2(整数倍), 居中放进槽里。
		var ts := Vector2(40, 80)
		if t != null:
			ts = Vector2(t.get_width(), t.get_height()) * 2.0
		var th := TPSkin.pixel_rect(t, ts)
		th.stretch_mode = TextureRect.STRETCH_SCALE
		th.position = ((Vector2(APP_W, APP_H) - ts) * 0.5).round()
		card.add_child(th)
		var nm := TPSkin.label(str(opt["name"]), 17, TPSkin.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		nm.position = Vector2(card.position.x - 10.0, y0 + APP_H + 8.0)
		nm.size = Vector2(APP_W + 20.0, 26)
		p.add_child(nm)
		card.pressed.connect(_on_appearance.bind(oid))
		p.add_child(card)
		_appear_cards.append([card, oid, nm])


## ── 右栏: 技能 ────────────────────────────────────────────────────
func _build_skills() -> void:
	var p := _panel(R_X, TOP, R_W, BOTTOM - TOP)
	## ★这一行被 `tests/verify_trainer_skill_count.gd` 钉着: 以「技能」开头、含「选」、
	##   第一串阿拉伯数字 == SKILLS.size()(数字现算, 不手写)。
	_section_head(p, "技能 · %d 选 1" % SKILLS.size(), 14.0, R_W)
	var rule_hint := TPSkin.label("被动与主动只能装配其一", 16, TPSkin.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	rule_hint.position = Vector2(R_W - PAD - 360.0, 18.0)
	rule_hint.size = Vector2(360, 26)
	p.add_child(rule_hint)

	## 分组: 被动在前, 主动在后, 中间留宽缝 —— 「二者只能装一个」靠排版就看得出来。
	var passive: Array = []
	var active: Array = []
	for s in SKILLS:
		if str(s["kind"]) == "被动":
			passive.append(s)
		else:
			active.append(s)
	var n := SKILLS.size()
	var total := CARD_W * n + CARD_GAP * (n - 2) + GROUP_GAP
	if passive.is_empty() or active.is_empty():
		total = CARD_W * n + CARD_GAP * (n - 1)
	var x := (R_W - total) * 0.5
	var cap_y := 54.0
	var card_y := 80.0
	_skill_cards.clear()
	for grp in [passive, active]:
		if (grp as Array).is_empty():
			continue
		var gw: float = CARD_W * (grp as Array).size() + CARD_GAP * ((grp as Array).size() - 1)
		var kind: String = str((grp as Array)[0]["kind"])
		var tag := TPSkin.kind_tag(kind, 15)
		tag.position = Vector2(x, cap_y)
		p.add_child(tag)
		## 组线: 从签后一直画到组尾, 标出这一组管几张。
		var gl := ColorRect.new()
		gl.color = (TPSkin.KIND_PASSIVE if kind == "被动" else TPSkin.KIND_ACTIVE) * Color(1, 1, 1, 0.35)
		gl.position = Vector2(x, card_y - 6.0)
		gl.size = Vector2(gw, 2.0)
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(gl)
		for s in grp:
			_add_skill_card(p, s, Vector2(x, card_y))
			x += CARD_W + CARD_GAP
		x += GROUP_GAP - CARD_GAP

	## 详情区: 一条分隔线下面, 左边大图标槽、右边名字与类别签, 说明在下面通栏(长说明不挤成窄条)。
	var div := ColorRect.new()
	div.color = Color(0.36, 0.44, 0.55, 0.45)
	div.position = Vector2(PAD, 212.0)
	div.size = Vector2(R_W - PAD * 2.0, 2.0)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(div)

	var slot := Panel.new()
	slot.add_theme_stylebox_override("panel", TPSkin.box("slot-selected.png", TPSkin.SLOT_MARGIN))
	slot.position = Vector2(PAD, 228.0)
	slot.size = Vector2(DETAIL_SLOT, DETAIL_SLOT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(slot)
	_detail_icon = TPSkin.pixel_rect(null, Vector2(128, 128))
	_detail_icon.position = ((Vector2(DETAIL_SLOT, DETAIL_SLOT) - Vector2(128, 128)) * 0.5).round()
	slot.add_child(_detail_icon)

	var tx := PAD + DETAIL_SLOT + 24.0
	var tw := R_W - tx - PAD
	_detail_name = TPSkin.label("", 32, TPSkin.TEXT)
	_detail_name.position = Vector2(tx, 238.0)
	_detail_name.size = Vector2(tw * 0.6, 46)
	p.add_child(_detail_name)
	## 名字后面: 类别签 + 已装配。名字长度不定 ⇒ 用 HBox 跟着排, 不手算宽度。
	_detail_kind_box = HBoxContainer.new()
	_detail_kind_box.add_theme_constant_override("separation", 12)
	_detail_kind_box.position = Vector2(tx, 292.0)
	_detail_kind_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_detail_kind_box)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.add_theme_font_size_override("normal_font_size", DESC_PX)
	_desc_label.add_theme_font_size_override("bold_font_size", DESC_PX)
	_desc_label.add_theme_constant_override("line_separation", 4)
	_desc_label.add_theme_color_override("default_color", Color(0.84, 0.88, 0.94))
	_desc_label.position = Vector2(PAD, 378.0)
	_desc_label.custom_minimum_size = Vector2(R_W - PAD * 2.0, 0)
	_desc_label.size = Vector2(R_W - PAD * 2.0, (BOTTOM - TOP) - 378.0 - PAD)
	p.add_child(_desc_label)


func _add_skill_card(parent: Control, opt: Dictionary, pos: Vector2) -> void:
	var oid: String = str(opt["id"])
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	card.position = pos
	card.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	TPSkin.skin_slot(card)
	var ip: String = str(opt["icon"])
	var icon := TPSkin.pixel_rect(load(ip) if ResourceLoader.exists(ip) else null, Vector2(64, 64))
	icon.position = ((Vector2(CARD_W, CARD_H) - Vector2(64, 64)) * 0.5).round()
	card.add_child(icon)
	## 已装配徽记: 压在右上角(选中才显示)。
	var badge := TPSkin.pixel_rect(TPSkin.tex("badge-check.png"), Vector2(33, 33))
	badge.position = Vector2(CARD_W - 24.0, -9.0)
	badge.visible = false
	card.add_child(badge)
	var nm := TPSkin.label(str(opt["name"]), 16, TPSkin.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(pos.x - 8.0, pos.y + CARD_H + 6.0)
	nm.size = Vector2(CARD_W + 16.0, 24)
	parent.add_child(nm)
	card.pressed.connect(_on_skill.bind(oid))
	parent.add_child(card)
	_skill_cards.append([card, oid, nm, badge])


## ── 交互 ──────────────────────────────────────────────────────────
func _on_skill(oid: String) -> void:
	var changed := oid != _sel_skill
	_sel_skill = oid
	_refresh_cards()
	_refresh_desc()
	if changed:
		_write_loadout()
		for c in _skill_cards:
			if str(c[1]) == oid:
				_pop(c[0])

func _on_appearance(oid: String) -> void:
	var changed := oid != _sel_appearance
	_sel_appearance = oid
	_refresh_appearance()
	if changed:
		_write_loadout()
		_hop_hero()


## 点中反馈: 槽轻轻一弹(缩放 1.08 → 1), 只动这一张。
func _pop(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.scale = Vector2(1.08, 1.08)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, UIPalette.T_TAP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 换形象: 人物在石台上跳一下(一个立绘像素 = HERO_SCALE 设计像素, 跳 3 格)。
func _hop_hero() -> void:
	if _preview_rect == null:
		return
	_preview_rect.position.y = _hero_home_y
	var tw := _preview_rect.create_tween()
	tw.tween_property(_preview_rect, "position:y", _hero_home_y - HERO_SCALE * 3.0, UIPalette.T_TAP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_preview_rect, "position:y", _hero_home_y, UIPalette.T_TAP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 刷新: 大立绘换成选中形象 + 形象名 + 槽的选中态。
func _refresh_appearance() -> void:
	for c in _appear_cards:
		var on := str(c[1]) == _sel_appearance
		(c[0] as Button).button_pressed = on
		(c[2] as Label).add_theme_color_override("font_color", GOLD if on else TPSkin.TEXT_DIM)
	for opt in APPEARANCES:
		if str(opt["id"]) != _sel_appearance:
			continue
		if _app_name_label != null:
			_app_name_label.text = str(opt["name"])
		if _preview_rect != null:
			var sp: String = str(opt["sprite"])
			var t: Texture2D = load(sp) if ResourceLoader.exists(sp) else null
			_preview_rect.texture = t
			var sz := Vector2(20, 40) * HERO_SCALE
			if t != null:
				sz = Vector2(t.get_width(), t.get_height()) * HERO_SCALE
			_preview_rect.size = sz
			## 脚底 = 石台顶面中线(面板坐标 300 + 28), 立绘底下有 1 原生像素透明边。
			_hero_home_y = 300.0 + 28.0 - sz.y + HERO_SCALE
			_preview_rect.position = Vector2(round(L_W * 0.5 - sz.x * 0.5), _hero_home_y)
		return

## 刷新技能槽选中态: 金框 + 右上徽记 + 名字变金。
func _refresh_cards() -> void:
	for c in _skill_cards:
		var on := str(c[1]) == _sel_skill
		(c[0] as Button).button_pressed = on
		(c[2] as Label).add_theme_color_override("font_color", GOLD if on else TPSkin.TEXT_DIM)
		(c[3] as Control).visible = on

func _refresh_desc() -> void:
	if _desc_label == null:
		return
	var s: Dictionary = _skill_of(_sel_skill)
	if s.is_empty():
		_desc_label.text = ""
		return
	if _detail_name != null:
		_detail_name.text = str(s["name"])
	if _detail_icon != null:
		var ip: String = str(s["icon"])
		_detail_icon.texture = load(ip) if ResourceLoader.exists(ip) else null
	if _detail_kind_box != null:
		for ch in _detail_kind_box.get_children():
			_detail_kind_box.remove_child(ch)
			ch.queue_free()
		_detail_kind_box.add_child(TPSkin.kind_tag(str(s["kind"]), 16))
		var eq := HBoxContainer.new()
		eq.add_theme_constant_override("separation", 6)
		eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bd := TPSkin.pixel_rect(TPSkin.tex("badge-check.png"), Vector2(24, 24))
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eq.add_child(bd)
		eq.add_child(TPSkin.label("已装配", 16, GOLD))
		_detail_kind_box.add_child(eq)
	## 说明走全项目同一个文案渲染(关键词上色 + 属性小图标), 与图鉴/商店一个口径。
	_desc_label.text = SkillText.plain_to_bb(_layout_desc(str(s["desc"])), DESC_PX)


## 说明的排版(只动换行, 一个字不改):
##   · 冷却那一句另起一行 —— 参考里技能说明都把冷却单独放, 玩家扫一眼就找得到。
##   · 「随机召唤以下一种」那类说明, 每个分支另起一行(口哨 150 字挤成一坨时找不到分支从哪开始)。
func _layout_desc(d: String) -> String:
	var out := d.replace("。冷却", "。\n冷却")
	if out.contains("以下一种"):
		var re := RegEx.create_from_string("。([^。： ]{2,4})：")
		out = re.sub(out, "。\n$1：", true)
	return out


## 背景 = 全屏共用的平铺底 + 一层更深的压暗(这一页的主角是面板里的立绘与图标)。
func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := TweenKit.loop_on(tile)
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.55),
		Color(0.031, 0.047, 0.078, 0.66),
		Color(0.031, 0.047, 0.078, 0.78),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 8; gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)


## 写回 GameState + 存盘(抽出来便于门禁测, 不含切场景)。
func _write_loadout() -> void:
	GameState.trainer_appearance = _sel_appearance
	GameState.trainer_skill = _sel_skill
	GameState.save()

## 顶栏返回: 点选时已存过, 这里再存一次兜底(异常退出前最后一次机会)。
func _save_and_back() -> void:
	_write_loadout()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
