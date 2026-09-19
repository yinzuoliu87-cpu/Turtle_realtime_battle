extends Node
## verify_trainer_skill_count — 训龟大师页：**文案说几个、屏上画几个、数组里有几个**，三个数必须相等。
##
## ★★为什么有它（2026-09-19 实拍巡检当场看见的）：
##   屏幕标题长期写着「技能（**五选一** · 被动或主动只能带一样）」，
##   而 `SKILLS` 数组里是 **7 条**，屏上也确实画了 7 张卡。
##   同一个文件 `:20` 的注释自己都写着「技能行 **7**×124」，
##   `battle_render.gd:26` 也写着「trainer_skill 是【七选一】」——
##   **只有玩家看见的那一行是错的**，而且错了不知道多久。
##
## ★修法不是把「五」改成「七」，是**从数组现算**（手写的数字迟早再漂一次）。
##   这条门禁守的就是"现算"这件事没被谁改回硬编码。
##
## ★判据走**真场景实例**读活节点的 text / 数活卡片，
##   不是在源码里找 `SKILLS.size()` 这个串 —— 那样把整行删掉判据照样绿。

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _collect(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		_collect(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var TC = load("res://scripts/scenes/TrainerConfigScene.gd")
	_ok("① ★分母: TrainerConfigScene.gd 载得进来", TC != null)
	if TC == null:
		_done()
		return
	var n_arr: int = int((TC.SKILLS as Array).size())
	_ok("① ★分母: SKILLS 数组非空", n_arr > 0, "%d 条" % n_arr)

	var ps: PackedScene = load("res://scenes/TrainerConfig.tscn")
	_ok("① ★分母: TrainerConfig.tscn 载得进来", ps != null)
	if ps == null:
		_done()
		return
	var inst: Node = ps.instantiate()
	add_child(inst)
	for _i in range(20):
		await get_tree().process_frame

	var labels: Array = []
	_collect(inst, labels)
	_ok("① ★分母: 屏上真建出了 Label", labels.size() >= 10, "共 %d 个" % labels.size())

	## ── ② 屏上到底画了几张技能卡：按**技能名**数 ──────────────
	##   ★不数控件类型（卡片是 Panel+Label 组合，形状会变），数"每个技能的名字出现没出现"。
	var names_on_screen := 0
	var missing: Array = []
	var texts: Array = []
	for l in labels:
		texts.append(str((l as Label).text))
	for s in TC.SKILLS:
		var nm := str((s as Dictionary).get("name", ""))
		if texts.has(nm):
			names_on_screen += 1
		else:
			missing.append(nm)
	_ok("② 屏上画出的技能卡数 == 数组条数", names_on_screen == n_arr,
		"屏上 %d · 数组 %d%s" % [names_on_screen, n_arr,
			("" if missing.is_empty() else " · 缺 " + str(missing))])

	## ── ③ 标题文案里的数字 == 数组条数 ───────────────────────
	##   ★这一条是本门禁的主角：漂掉的就是它。
	var heading := ""
	for t in texts:
		var s := str(t)
		if s.begins_with("技能") and s.contains("选"):
			heading = s
			break
	_ok("③ ★分母: 找得到技能那行标题", heading != "", "实得 %s" % heading)
	if heading != "":
		var digits := ""
		for ch in heading:
			if ch >= "0" and ch <= "9":
				digits += ch
			elif digits != "":
				break
		_ok("③ ★标题里的数字 == 数组条数(不许手写)", digits == str(n_arr),
			"标题「%s」解析出 %s · 数组 %d" % [heading, ("(无阿拉伯数字)" if digits == "" else digits), n_arr])
		## ★钉住那次真实漂移：中文数字写法已经错过一次，不许再出现。
		for w in ["五选一", "三选一", "四选一", "六选一", "七选一"]:
			_ok("③ 标题不含手写的中文数字「%s」" % w, not heading.contains(w), "标题=%s" % heading)

	inst.queue_free()
	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 训龟大师技能计数 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 训龟大师技能计数 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
