extends RefCounted
## finals_confirm_btn.gd —— 背包顶栏「确定阵容」(2026-11-16 · 方案书 docs/plans/20261116b-周末确定阵容按钮.md)。
##
## 用户 11-16:「加个按钮，就加在背包里面…加个确定阵容，然后在点确定阵容的时候，就顺便把那个选择技能…跳出来让玩家选择」。
## ★放顶栏「背包」页签右边: 背包重做后右边整片是装备栏、右下是羁绊条, 只有顶栏中间那段在手机与 iPad 上都空着;
##   用选龟页「出战」同一种像素金键(主操作), 不用木牌签(那是页签)。
## ★本周已晋级、决赛还没打完才有(FinalsConfirm.stage); 背包与上次提交的一样 ⇒「阵容已确定」, 不一样 / 没交过 ⇒「确定阵容」+ 红点。
## ★背包每次改阵容都整页重建(InventoryScene._rebuild 连顶栏一起), 所以这里每次建都是最新状态, 不另外监听。
## 点了 ⇒ 置 FinalsConfirm.pick_mode ⇒ 进选龟页(决赛模式: 换技能 →「提交阵容」)⇒ 回到背包时弹回执(take_receipt)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const N_BTN := "FinalsConfirmBtn"
const N_DOT := "FinalsConfirmDot"
const GAP := 18.0
const FONT_PX := 20
const DOT_PX := 12.0

var host = null
var btn: Button = null


func _init(h) -> void:
	host = h


## 顶栏建好之后调。不该出现 ⇒ 什么都不建。
func build(top_bar) -> void:
	btn = null
	if FinalsConfirm.stage(int(_P2.now_utc())) == "":
		return
	var tab: Control = null
	for b in top_bar.action_btns:
		if b is Button and str((b as Button).text) == "背包":
			tab = b
	if tab == null:
		return
	var done := FinalsConfirm.is_confirmed()
	btn = Button.new()
	btn.name = N_BTN
	btn.text = FinalsConfirm.BTN_DONE if done else FinalsConfirm.BTN_CONFIRM
	UISkin.pixel_button(btn, UISkin.PX_GOLD, 4)
	btn.add_theme_font_size_override("font_size", FONT_PX)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_press)
	(top_bar.bar as Control).add_child(btn)
	var h: float = maxf(tab.size.y, 44.0)
	btn.custom_minimum_size = Vector2(0.0, h)
	btn.size = Vector2(btn.get_combined_minimum_size().x, h)
	btn.position = Vector2(tab.position.x + tab.size.x + GAP, tab.position.y + (tab.size.y - h) * 0.5)
	if not done:
		## 红点: 背包里这一套还没交 / 交了之后又改过(像素小方块, 黑边; 不用圆点 —— 这一屏是像素硬边)
		var dot := Panel.new()
		dot.name = N_DOT
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#e5403a")
		sb.border_color = Color("#1a0d0b")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		dot.add_theme_stylebox_override("panel", sb)
		dot.size = Vector2(DOT_PX, DOT_PX)
		## 放在按钮右上角【里面】: 顶栏贴着屏幕上沿, 放到按钮外面会被屏幕边裁掉(11-16 实拍只剩一个小红点)
		dot.position = Vector2(btn.size.x - DOT_PX - 6.0, 6.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(dot)
	var r := FinalsConfirm.take_receipt()
	if r != "" and host != null and host.has_method("_toast"):
		host._toast(r)


func _on_press() -> void:
	FinalsConfirm.pick_mode = true
	SceneNav.go(host.get_tree(), "res://scenes/TeamSelect.tscn")
