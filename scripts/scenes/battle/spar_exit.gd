extends RefCounted
## spar_exit.gd —— 好友切磋对局里左下角那颗「退出」(2026-11-19)。
##
## 用户 11-19「然后切磋没有按钮可以退出观看吗」「切磋这个按钮应该做吧」(语音转写, 原文「其所以没有按钮手退出观看吗」):
##   11-18 起切磋的换路幕布点不动了(dual_lane_flow._dl_present_click, 用户「切磋的时候…不可以去点击」),
##   而对局里又没有任何离场的口 ⇒ 开了切磋只能看完。
##   补一颗与观赛 / 逐帧直播**同样子、同位置**的红键(replay_controls._build_live / _build_stream_exit), 同样先问一句再走。
## ★只在切磋: 正式对局局内不放退出 / 暂停(用户 07-30「局内不再有退出去或暂停的按钮了」; 10-19 投降也删了)。
## ★离场 = 回发起切磋的那一页(Spar.back_scene: 好友 / 排行榜)。GameState 由 RealtimeBattle3DScene._exit_tree 的
##   Spar.end() 还原 —— 任何离场路都走那里, 这里不另还原。
## ★结算屏出来就收起(结算屏上有「再来一局 / 返回好友」): battle_hud._settle_buttons 切磋那一支调 hide()。
## ★画在 _ui_layer 上面一层: 换路幕布(_ui_layer, z 50)盖着时也能点。
## 放这里的理由(CLAUDE.md §6): 不在 _sim_step 调用链上; replay_controls 管回放 / 观赛, battle_hud 已 2590 行 ⇒ 单独一个文件。
## 门禁 tests/verify_spar_exit.gd。

const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")

## 节点名 —— 门禁按名字找。
const N_LAYER := "SparExitLayer"
const N_EXIT := "SparExit"
const N_ASK := "SparExitAsk"
const N_YES := "SparExitYes"
const N_NO := "SparExitNo"
const TXT_ASK := "退出切磋？"

var battle
var layer: CanvasLayer = null
var root: Control = null
var exit_btn: Button = null
var ask: Control = null


func _init(b) -> void:
	battle = b


func build() -> void:
	if battle == null or battle._ui_layer == null or (layer != null and is_instance_valid(layer)):
		return
	layer = CanvasLayer.new()
	layer.name = N_LAYER
	layer.layer = int(battle._ui_layer.layer) + 1
	battle.add_child(layer)
	root = Control.new()
	root.name = "SparExitRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var vp := Vector2(battle.get_viewport().get_visible_rect().size)
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	exit_btn = PixelKey.icon_key(N_EXIT, RC.KEY_RED, RC.KEY_RED_DOWN, RC.ICON_EXIT)
	exit_btn.position = Vector2(m.x, vp.y - m.w - PixelKey.KEY_PX)
	exit_btn.pressed.connect(open_ask)
	BackKey.tag(exit_btn)     # 安卓返回键 = 点「退出」(先问)
	root.add_child(exit_btn)


## 点退出: 先问一句(键小、贴着屏幕边, 误触一下这场切磋就没了)。
func open_ask() -> void:
	if root == null or not is_instance_valid(root) or (ask != null and is_instance_valid(ask)):
		return
	var dim := ColorRect.new()
	dim.name = N_ASK
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	ask = dim
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", SettleScreenS.frame_style())
	pc.custom_minimum_size = Vector2(440, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	var tl := Label.new()
	tl.text = TXT_ASK
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_color", RC.COL_TEXT)
	UISkin.title_label(tl, 24)                                # 弹框标题 24 号(与回放 / 观赛退出框同一套)
	vb.add_child(tl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var stay := _btn(RC.TXT_ASK_STAY, N_NO)
	stay.pressed.connect(close_ask)
	BackKey.tag(stay)         # 问框开着时再按返回 = 继续观看
	hb.add_child(stay)
	var leave := _btn(RC.TXT_ASK_LEAVE, N_YES)
	leave.pressed.connect(leave_now)
	hb.add_child(leave)


func close_ask() -> void:
	if ask != null and is_instance_valid(ask):
		ask.queue_free()
	ask = null


func leave_now() -> void:
	if battle != null and is_instance_valid(battle) and battle.get_tree() != null:
		SceneNav.go(battle.get_tree(), Spar.back_scene())


## 结算屏出来了: 收起键与问框(结算屏上有「再来一局 / 返回」)。
func hide() -> void:
	close_ask()
	if exit_btn != null and is_instance_valid(exit_btn):
		exit_btn.visible = false


## 弹框里的按钮属于弹框 ⇒ UISkin.card_button(与回放 / 观赛退出框同一个样子)。
func _btn(t: String, nm: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.custom_minimum_size = Vector2(160.0, RC.BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 22)
	UISkin.card_button(b)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, RC.COL_TEXT)
	return b
