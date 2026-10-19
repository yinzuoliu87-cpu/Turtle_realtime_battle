extends Node
## verify_trainer_page_ui — 训龟大师页(2026-10-19 重做)的交互判据。
##
## 重做把「保存 / 取消」换成了「点一下 = 装配」+ 顶栏返回。这条门禁量的是**点真按钮**之后:
##   ① 技能槽: 发 pressed ⇒ GameState.trainer_skill 立刻变、只有那一张亮徽记、详情换成那一门
##   ② 形象槽: 发 pressed ⇒ GameState.trainer_appearance 立刻变、大立绘换贴图
##   ③ 所有可点的槽短边 ≥ 81(44pt)
##   ④ 说明排版只加换行、一个字不改(去掉换行后与 SKILLS[].desc 逐字相同)
## 分母: 槽数 == SKILLS / APPEARANCES 条数, 否则后面全是空检查。

const TC := preload("res://scripts/scenes/TrainerConfigScene.gd")

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true              # save() 直接返回, 不碰玩家存档
	var skill0: String = str(gs.trainer_skill)
	var app0: String = str(gs.trainer_appearance)
	gs.trainer_skill = "hook"
	gs.trainer_appearance = "villager"

	var inst = load("res://scenes/TrainerConfig.tscn").instantiate()
	add_child(inst)
	for _i in range(5):
		await get_tree().process_frame

	_ok("★分母: 技能槽数 == SKILLS", inst._skill_cards.size() == TC.SKILLS.size(),
		"%d / %d" % [inst._skill_cards.size(), TC.SKILLS.size()])
	_ok("★分母: 形象槽数 == APPEARANCES", inst._appear_cards.size() == TC.APPEARANCES.size(),
		"%d / %d" % [inst._appear_cards.size(), TC.APPEARANCES.size()])

	## ① 技能: 逐张点一遍
	for c in inst._skill_cards:
		var b: Button = c[0]
		var sid: String = str(c[1])
		b.pressed.emit()
		await get_tree().process_frame
		_ok("① 点「%s」⇒ GameState.trainer_skill 立刻 = %s" % [sid, sid], str(gs.trainer_skill) == sid, str(gs.trainer_skill))
		var lit := 0
		var pressed := 0
		for c2 in inst._skill_cards:
			if (c2[3] as Control).visible:
				lit += 1
			if (c2[0] as Button).button_pressed:
				pressed += 1
		_ok("① 点「%s」⇒ 只有 1 枚已装配徽记、1 个按下槽" % sid, lit == 1 and pressed == 1 and b.button_pressed,
			"徽记 %d / 按下 %d" % [lit, pressed])
		var want_name := ""
		for s in TC.SKILLS:
			if str(s["id"]) == sid:
				want_name = str(s["name"])
		_ok("① 点「%s」⇒ 详情名字换成 %s" % [sid, want_name], inst._detail_name.text == want_name, inst._detail_name.text)
		_ok("③ 技能槽「%s」短边 ≥ 81" % sid, minf(b.size.x, b.size.y) >= 81.0, str(b.size))

	## ② 形象
	for c in inst._appear_cards:
		var b: Button = c[0]
		var aid: String = str(c[1])
		b.pressed.emit()
		await get_tree().process_frame
		_ok("② 点「%s」⇒ GameState.trainer_appearance 立刻 = %s" % [aid, aid], str(gs.trainer_appearance) == aid, str(gs.trainer_appearance))
		var want := ""
		for a in TC.APPEARANCES:
			if str(a["id"]) == aid:
				want = str(a["sprite"])
		var tex: Texture2D = inst._preview_rect.texture
		_ok("② 点「%s」⇒ 大立绘换成它的贴图" % aid, tex != null and tex.resource_path == want,
			tex.resource_path if tex != null else "null")
		_ok("③ 形象槽「%s」短边 ≥ 81" % aid, minf(b.size.x, b.size.y) >= 81.0, str(b.size))

	## ④ 排版只加换行
	var n_split := 0
	for s in TC.SKILLS:
		var d: String = str(s["desc"])
		var laid: String = inst._layout_desc(d)
		if laid != d:
			n_split += 1
		_ok("④「%s」排版后去掉换行 == 原文" % s["name"], laid.replace("\n", "") == d)
	_ok("④ ★分母: 排版真的动过(至少口哨分了行)", n_split >= 1, "%d 条" % n_split)

	inst.queue_free()
	gs.trainer_skill = skill0
	gs.trainer_appearance = app0
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 训龟大师页交互 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 训龟大师页交互 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
