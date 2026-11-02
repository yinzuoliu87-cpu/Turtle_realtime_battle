extends Node
## 批量台: 让龟壳把【每一个可抄技能】各抄一次, 逐个量四样 ——
##   ① 引擎报错 ② 有没有造成伤害 ③ 有没有污染龟壳自己 ④ 演出有没有建节点
## ★不叫 verify_* —— 不进自动发现, 是排查工具。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")

var _s = null


func _mk(id: String, side: String, off: Vector2, hp: float = 3000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["dots"] = []
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node_or_null("/root/GameState").test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	## 全部可抄技能 = 有实现 且 不在黑名单
	var all: Array = []
	for st in _s._IMPL_SKILLS.keys():
		if CopyRules.can_copy(str(st), _s._IMPL_SKILLS):
			all.append(str(st))
	all.sort()
	print("=== 龟壳复制 批量台: %d 个可抄技能 ===" % all.size())

	## ★★对照组: 先跑一遍【什么都不放】, 记下龟壳会自然长出哪些字段。
	##   没有它就分不出"这个技能污染了龟壳"和"每帧记账本来就会加的字段"
	##   —— 第一版没有对照组, 82 个技能全被报成"残留 19~39 个字段", 全是假警报。
	##   (这就是方案书 ①-E4 用过的对照组差分, 我第一版忘了用。)
	## ★对照组必须【和实验组一样真打一场】—— 否则 `state_t` / `_lunge_*` / `_spark_t` /
	##   `basic_alt` 这些"只要动过就会有"的每帧记账不会出现在对照里, 于是 76/82 全被误报。
	##   (第三版就栽在这: 对照组把敌人放 160 码外、只等 120 帧, 龟壳压根没出手。)
	_s._units.clear()
	var cs: Dictionary = _mk("shell", "left", Vector2(-200.0, 0.0))
	_mk("basic", "right", Vector2(-120.0, 0.0))
	for _f0 in range(480):
		await get_tree().process_frame
	var ctrl: Dictionary = {}
	for k in cs.keys():
		ctrl[str(k)] = true
	print("  [分母] 对照组(什么都不放)龟壳有 %d 个字段" % ctrl.size())

	var bad: Array = []
	for st in all:
		_s._units.clear()
		var shell: Dictionary = _mk("shell", "left", Vector2(-200.0, 0.0))
		var foe: Dictionary = _mk("basic", "right", Vector2(-120.0, 0.0))
		var foe2: Dictionary = _mk("basic", "right", Vector2(-60.0, 60.0))
		foe["active_skills"] = [str(st)]
		foe2["active_skills"] = [str(st)]
		var hp0: float = float(foe["hp"]) + float(foe2["hp"])
		var sh0: float = float(shell.get("shield", 0.0))
		var hs0: float = float(shell.get("hp", 0.0))
		## ★数【创建了多少节点】而不是净增减 —— tween 结束会释放, 净值常是负的,
		##   拿净值当"有没有演出"会把有演出的判成没演出(第一版 12 个假警报全是这个)。
		var born := {"n": 0}
		var cb := func(nd: Node) -> void: born["n"] += 1
		if _s._world != null:
			_s._world.child_entered_tree.connect(cb)

		_s._shell_sys._sk_shell_copy(shell, foe)
		for _f in range(120):
			await get_tree().process_frame

		if _s._world != null and _s._world.child_entered_tree.is_connected(cb):
			_s._world.child_entered_tree.disconnect(cb)
		var dmg: float = hp0 - (float(foe["hp"]) + float(foe2["hp"]))
		## 护盾/治疗也算"有效果" —— 护盾技本来就不掉血, 拿掉血当唯一判据会把它们全判死。
		var gain: float = maxf(0.0, float(shell.get("shield", 0.0)) - sh0) 			+ maxf(0.0, float(shell.get("hp", 0.0)) - hs0)
		## ★★污染的判据不是"多了个字段", 是【放完之后它还活着】。
		##   第二版拿"字段存在"当判据 ⇒ 82 个全中: `dmg_out_mult` 是复制机制自己设的
		##   60% 乘数(放完会被复位成 1.0, 但键还在), `_st_*` 是伤害统计计数器。
		##   这就是方案书 ①-E4 用的口径: **放完等 6 秒再看还剩什么**,
		##   只认 `*_until` 还在未来 / 布尔仍为真 —— 那才是"卡在别人的形态里"。
		for _f2 in range(360):
			await get_tree().process_frame
		var newk: Array = []
		for k in shell.keys():
			var ks := str(k)
			## 时间戳/计时器类不是形态 —— 它们只记"上次发生在第几秒", 每帧都在涨。
			if ctrl.has(ks) or ks.begins_with("_st_") or ks.ends_with("_t") 					or ks.ends_with("_dur") or ks.ends_with("_amp") or ks.ends_with("_start"):
				continue
			var v = shell[k]
			if v is bool and bool(v):
				newk.append(ks)
			elif ks.ends_with("_until") and (v is float or v is int) and float(v) > _s._t:
				newk.append("%s(+%.1fs)" % [ks, float(v) - _s._t])
			elif (v is float or v is int) and ks != "dmg_out_mult" 					and absf(float(v)) > 0.0001 and absf(float(v) - 1.0) > 0.0001:
				newk.append("%s=%s" % [ks, str(v)])
		var flag := ""
		if dmg <= 0.0 and gain <= 0.0 and int(born["n"]) <= 0:
			flag = "❌零效果(不掉血·不给盾/治疗·没建任何演出节点)"
		if not newk.is_empty():
			flag += " ⚠放完6秒后仍留在龟壳身上:%s" % str(newk.slice(0, mini(5, newk.size())))
		print("  %-22s 伤害 %7.1f · 盾/治疗 %7.1f · 新建节点 %3d · 污染 %d %s"
			% [st, dmg, gain, int(born["n"]), newk.size(), flag])
		if flag != "":
			bad.append("%s %s" % [st, flag])

	print("")
	print("=== 有问题的 %d / %d ===" % [bad.size(), all.size()])
	for b in bad:
		print("   " + b)
	print("PROBE DONE")
	get_tree().quit(0)
