extends Control

## 训龟大师 配置界面 (用户2026-07-26 更正: 主菜单独立入口, 选形象 + 配【全部技能五选一·单个】)。
## ★设计: 被动+主动放一起, 只能选 1 个。选被动=没有主动Q; 选主动=没有被动。
## 选择写 GameState.trainer_appearance/trainer_skill + save(), 战斗时读取。

## 全部技能池(被动 + 主动·五选一)。kind 仅供说明卡显示"被动/主动"。
const SKILLS := [
	{"id": "magic_stone", "kind": "被动", "name": "魔法石", "desc": "普攻附带 2% 目标最大生命 魔法伤害；每次攻击自身 +5% 攻速(可叠·持续到本场结束)。"},
	{"id": "hook", "kind": "主动", "name": "钩锁", "desc": "朝方向甩钩(射程600)勾住第一个敌人：眩晕4秒、一段段拽向大师、受伤+25%。CD20，空放返还。"},
	{"id": "fury_potion", "kind": "主动", "name": "怒火药水", "desc": "朝700码内一点丢药水：落点300码内友军5秒 +30%攻速 / +25%龟能充能 / +25%移速。CD16。"},
	{"id": "whistle", "kind": "主动", "name": "口哨", "desc": "随机1个：给友军700临时生命 / 召灵体小龟放气波(击飞+200物理+削甲30%) / 友军狂暴(+20%攻+吸血·免死4秒)。CD14。"},
	{"id": "glacier", "kind": "主动", "name": "冰川", "desc": "沿方向生成500码冰川(6秒)：站上的敌 -40%移速 + 受伤+20%。CD17。"},
]
const APPEARANCES := [
	{"id": "default", "name": "默认(冒险家)"},
]

var _sel_skill: String = "hook"
var _sel_appearance: String = "default"
var _desc_label: Label = null

func _ready() -> void:
	_sel_skill = _valid_skill(str(GameState.trainer_skill))
	_sel_appearance = str(GameState.trainer_appearance)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

## 校验技能 id 合法(旧档/脏数据兜底为 hook)。
func _valid_skill(id: String) -> String:
	for s in SKILLS:
		if str(s["id"]) == id:
			return id
	return "hook"

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
	box.add_child(_section("技能（五选一·被动或主动只能带一样）", SKILLS, func(id): _sel_skill = id, func(): return _sel_skill))

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
		b.custom_minimum_size = Vector2(126, 46)
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

func _refresh_desc() -> void:
	if _desc_label == null:
		return
	for s in SKILLS:
		if str(s["id"]) == _sel_skill:
			_desc_label.text = "%s · %s：%s" % [s["kind"], s["name"], s["desc"]]
			return
	_desc_label.text = ""

## 写回 GameState + 存盘(抽出来便于门禁测, 不含切场景)。
func _write_loadout() -> void:
	GameState.trainer_appearance = _sel_appearance
	GameState.trainer_skill = _sel_skill
	GameState.save()

func _save_and_back() -> void:
	_write_loadout()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
