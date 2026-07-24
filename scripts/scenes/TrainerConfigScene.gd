extends Control

## 训龟大师 配置界面 (用户2026-07-23 需求: 主菜单独立入口, 选形象 + 配被动 + 配单个主动技能)。
## 选择写 GameState.trainer_appearance/passive/active + save(), 战斗时读取。

const PASSIVES := [
	{"id": "", "name": "无", "desc": "不带被动。"},
	{"id": "magic_stone", "name": "魔法石", "desc": "普攻附带 2% 目标最大生命 魔法伤害；每次攻击自身 +5% 攻速(可叠·持续到本场结束)。"},
]
const ACTIVES := [
	{"id": "hook", "name": "钩锁", "desc": "朝方向甩钩(射程600)勾住第一个敌人：眩晕4秒、一段段拽向大师、受伤+25%。CD20，空放返还。"},
	{"id": "fury_potion", "name": "怒火药水", "desc": "朝700码内一点丢药水：落点300码内友军5秒 +30%攻速 / +25%龟能充能 / +25%移速。CD16。"},
	{"id": "whistle", "name": "口哨", "desc": "随机1个：给友军700临时生命 / 召灵体小龟放气波(击飞+200物理+削甲30%) / 友军狂暴(+20%攻+吸血·免死4秒)。CD14。"},
	{"id": "glacier", "name": "冰川", "desc": "沿方向生成500码冰川(6秒)：站上的敌 -40%移速 + 受伤+20%。CD17。"},
]
const APPEARANCES := [
	{"id": "default", "name": "默认(冒险家)"},
]

var _sel_passive: String = ""
var _sel_active: String = "hook"
var _sel_appearance: String = "default"
var _desc_label: Label = null

func _ready() -> void:
	_sel_passive = str(GameState.trainer_passive)
	_sel_active = str(GameState.trainer_active) if GameState.trainer_active != "" else "hook"
	_sel_appearance = str(GameState.trainer_appearance)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.10, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(0, 40)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.custom_minimum_size = Vector2(680, 0)
	add_child(box)

	var title := Label.new()
	title.text = "🐢 训龟大师"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_section("形象", APPEARANCES, func(id): _sel_appearance = id, func(): return _sel_appearance))
	box.add_child(_section("被动技能", PASSIVES, func(id): _sel_passive = id, func(): return _sel_passive))
	box.add_child(_section("主动技能（单槽·移动端按住圆盘拖动瞄准 / PC 按 Q）", ACTIVES, func(id): _select_active(id), func(): return _sel_active))

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(680, 60)
	_desc_label.add_theme_font_size_override("font_size", 18)
	_desc_label.modulate = Color(0.8, 0.86, 0.95)
	box.add_child(_desc_label)
	_refresh_desc()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var save_btn := Button.new()
	save_btn.text = "保存并返回"
	save_btn.custom_minimum_size = Vector2(200, 56)
	save_btn.pressed.connect(_save_and_back)
	row.add_child(save_btn)
	var back_btn := Button.new()
	back_btn.text = "返回(不保存)"
	back_btn.custom_minimum_size = Vector2(200, 56)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	row.add_child(back_btn)

## 一个选择区: 标题 + 一排选项按钮(单选·高亮当前)。set_cb(id) 设选择, get_cb() 取当前。
func _section(title: String, opts: Array, set_cb: Callable, get_cb: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var lb := Label.new()
	lb.text = title
	lb.add_theme_font_size_override("font_size", 20)
	lb.modulate = Color(1.0, 0.86, 0.4)
	v.add_child(lb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var btns: Array = []
	for opt in opts:
		var b := Button.new()
		b.text = str(opt["name"])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 46)
		var oid: String = str(opt["id"])
		b.button_pressed = (oid == str(get_cb.call()))
		b.pressed.connect(func():
			set_cb.call(oid)
			for bb in btns:
				bb[0].button_pressed = (str(bb[1]) == str(get_cb.call()))
			_refresh_desc())
		h.add_child(b)
		btns.append([b, oid])
	return v

func _select_active(id: String) -> void:
	_sel_active = id

func _refresh_desc() -> void:
	if _desc_label == null:
		return
	var txt := ""
	for p in PASSIVES:
		if str(p["id"]) == _sel_passive:
			txt += "被动 · %s：%s\n" % [p["name"], p["desc"]]
	for a in ACTIVES:
		if str(a["id"]) == _sel_active:
			txt += "主动 · %s：%s" % [a["name"], a["desc"]]
	_desc_label.text = txt

## 写回 GameState + 存盘(抽出来便于门禁测, 不含切场景)。
func _write_loadout() -> void:
	GameState.trainer_appearance = _sel_appearance
	GameState.trainer_passive = _sel_passive
	GameState.trainer_active = _sel_active
	GameState.save()

func _save_and_back() -> void:
	_write_loadout()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
