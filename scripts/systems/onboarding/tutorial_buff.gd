extends RefCounted
## 教程加成 —— 新手教程那一把战斗里, 我方所有单位 增伤 + 减伤(方案书 docs/plans/20261020-教程重写.md D8)。
##
## 用户 2026-10-20 原话:「你可以在新手教程里给我方单位50%增伤和30减伤啊，最为教程模式的特殊机制啊」
## ★★这是**明示**的教程模式机制, 不是隐藏倍率(memory project-no-resist-comp-hidden-multiplier):
##   · 走游戏现有的属性通道 `damage_amp`(增伤)/ `damage_reduction`(减伤), 不另写伤害公式 ——
##     两条伤害路径(CLAUDE.md §3.3)本来就都读这两个字段; 面板「增伤 / 减伤」两行照常显示加成后的值。
##   · 战斗里看得见: 我方头像栏上方一枚「教程加成」签(点开出 `text()` 那一句); 点开我方龟的详情, 状态里也有这一条。
##   · 对手、补小将、分路结算等规则一律不变(教程不许改对局规则, 用户 10-20)。
## ★只在教程沙盒里生效(`active()`): 导演在教程中 + 在沙盒里 + 教学战斗阶段。正式对局 / 周六周日 / 回放 / 服务器裁判
##   里导演不在教程中 ⇒ 一个单位都不加(门禁 verify_tutorial_battle_short ②)。

const _TD := preload("res://autoload/tutorial_director.gd")
## 单位上的标记(门禁与详情面板读它)。
const MARK := "tut_buff"
const BADGE_NAME := "TutorialBuffBadge"
const BADGE_TEXT := "教程加成"


## 现在是不是教学战斗(导演在教程中、沙盒在、阶段是第一把)。
static func active() -> bool:
	var tr := Engine.get_main_loop() as SceneTree
	var td: Node = tr.root.get_node_or_null("/root/TutorialDirector") if tr != null and tr.root != null else null
	return td != null and td.is_active() and td.in_sandbox() and str(td.stage()) == "match1"


## 说明句(数字读常量, 不手抄)。
static func text() -> String:
	return "新手教程：增伤 %d%%，减伤 %d%%" % [int(round(_TD.TUTORIAL_DMG_AMP * 100.0)), int(round(_TD.TUTORIAL_DR * 100.0))]


## 单位刚建出来时调(battle_spawn 的 `_make_unit` / `_spawn_summon` 末尾)。只给我方; 训龟大师不算(它不参与伤害)。★幂等。
static func apply(u: Dictionary) -> void:
	if str(u.get("side", "")) != "left" or bool(u.get("is_trainer", false)) or bool(u.get(MARK, false)):
		return
	if not active():
		return
	u[MARK] = true
	u["damage_amp"] = float(u.get("damage_amp", 0.0)) + _TD.TUTORIAL_DMG_AMP
	u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + _TD.TUTORIAL_DR


## 导演看到教学战斗时挂上(与战斗提示一起)。
static func attach_badge(bt: Node) -> Node:
	if bt == null or not is_instance_valid(bt) or bt.get_node_or_null(BADGE_NAME) != null:
		return null
	var n := BadgeNode.new()
	n.name = BADGE_NAME
	n.battle = bt
	n.desc = text()
	bt.add_child(n)
	return n


## 「教程加成」签: 贴在我方头像栏正上方(跟着那一栏走); 点一下出说明句, 再点 / 3 秒后收起。
class BadgeNode extends Node:
	const POPUP_LIFE := 3.0
	var battle: Node = null
	var desc := ""
	var _layer: CanvasLayer = null
	var badge: PanelContainer = null
	var popup: PanelContainer = null
	var popup_lab: Label = null
	var _popup_t := 0.0

	func _ready() -> void:
		_layer = CanvasLayer.new()
		_layer.layer = 5
		add_child(_layer)
		badge = _plate(Color("#ffd27a"))
		badge.name = "Badge"
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		var l := _lab(BADGE_TEXT, 17, Color("#ffd27a"))
		badge.add_child(l)
		badge.gui_input.connect(_on_input)
		badge.visible = false
		_layer.add_child(badge)
		popup = _plate(Color("#ffd27a"))
		popup.name = "Popup"
		popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup_lab = _lab(desc, 16, Color("#f4f1ea"))
		popup.add_child(popup_lab)
		popup.visible = false
		_layer.add_child(popup)

	## 硬边像素框(直角、2px 描边, 与首次提示条同一套): 不借顶栏石板图(素材铁律「新内容一律新素材」)。
	func _plate(border: Color) -> PanelContainer:
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.071, 0.110, 0.204, 0.94)
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 12; sb.content_margin_right = 12
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		pc.add_theme_stylebox_override("panel", sb)
		return pc

	func _lab(t: String, fs: int, col: Color) -> Label:
		var l := Label.new()
		l.text = t
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 4)
		return l

	func _on_input(ev: InputEvent) -> void:
		var press: bool = (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
		if not press:
			return
		if popup.visible:
			popup.visible = false
		else:
			show_popup()
		badge.get_viewport().set_input_as_handled()

	func show_popup() -> void:
		popup.visible = true
		popup.size = popup.get_combined_minimum_size()
		popup.position = _popup_at()
		_popup_t = POPUP_LIFE

	## 说明框放在签的右边(下面是头像栏, 不压它)。
	func _popup_at() -> Vector2:
		return Vector2(badge.position.x + badge.size.x + 8.0, badge.position.y + (badge.size.y - popup.size.y) * 0.5).round()

	## 门禁 / 录屏读。
	func popup_text() -> String:
		return popup_lab.text if popup_lab != null else ""

	func _process(dt: float) -> void:
		if battle == null or not is_instance_valid(battle):
			return
		var col = battle.get("_team_panel_left")
		var on: bool = col != null and is_instance_valid(col) and col is Control and (col as Control).is_visible_in_tree() \
			and not bool(battle.get("_over"))
		badge.visible = on
		if not on:
			popup.visible = false
			return
		badge.size = badge.get_combined_minimum_size()
		var r: Rect2 = (col as Control).get_global_rect()
		badge.position = Vector2(r.position.x, r.position.y - badge.size.y - 8.0).round()
		if popup.visible:
			_popup_t -= dt
			popup.position = _popup_at()
			if _popup_t <= 0.0:
				popup.visible = false
