extends Node
## verify_skills_not_dead.gd — 每个技能【由它自己的龟放】必须真的干活 (2026-08-31)
##
## ★★★2026-09-01: 这份门禁**从 2026-08-31 写好那天起就没跑过一次** ——
##   文件名带 `_wip_` 前缀, 而 `run-tests.sh` 只自动发现 `tests/verify_*.gd`。
##   一份"防以后加进来的死技能"的棘轮, 自己先当了三十多个小时的死代码。
##   真跑起来当场发现它跑不完: 三处 `str(单位字典)` 触发 Godot 递归 stringify,
##   刷 12 万条 `Maximum dictionary recursion reached`、10 分钟还没结束(见 `_vsig` 头注)。
##   修完 91 秒跑完、84 个技能零空转。**"写好了"和"在跑"是两件事。**
##
## ★由来: 2026-08-31 核实"69 个技能没门禁"这个数, 发现它是**假缺口** ——
##   按【名字】搜出来的缺口不算数: `verify_copy_no_lock` 其实已经逐个放过 80 个,
##   只是测试里没写它们的名字。(同族: 今晚照旧账念了三次, 三次全是烂账。)
##
## ★真正缺的是这一层: 现有门禁验到"分派得到 + 有实现"(copy_chain_audit 的结构对账),
##   以及"被龟壳抄了不留长命锁"。**"它自己放出来到底干没干活"没人验过。**
##   历史上这个坑是真的: 原白名单里躺过 13 个普攻位技能, 放在 `_do_skill` 名单里
##   **永远不会被执行**, 130 龟能白花、屏幕上什么都不发生, **而且不报错**。
##
## ★★判据第一版是【空的】, 反向验证当场抓到: 我把竹击整个掏空, 门禁照样绿。
##   因为我把"建了演出节点"也算成"干活了", 而 `_do_skill` **自己就会建通用施法演出**
##   —— 实测 84 个技能【全部】≥5 个新建节点, 这个条件恒真。
##   (同族: 判据要刚好卡住那个形状; 这次是宽了一格, 宽到把恒真式当判据。)
##
## ★现在的判据 = 【状态真的变了】, 并且用【对照组】减掉通用部分:
##   · 对照 = 放一个**不存在的技能 id** —— `_do_skill` 的通用那半照跑, 技能那半没有。
##   · 干活 = 敌人掉血 / 敌人身上多出对照组没有的字段(眩晕·减速·标记…)
##            / 施法者拿到盾或治疗 / 施法者身上多出对照组没有的字段(buff)。
##   四者全无 = 空转。
##
## 实测基线(2026-08-31): 84 个全部有效果, **零空转**。这条是棘轮, 防的是以后加进来的死技能。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])



## 一个值的【签名】—— 用来比"这个字段变了没有"。
##
## ★★绝不 `str()` 一个可能含【单位字典】的值(CLAUDE.md §3.2 的同一颗雷):
##   单位字典之间互相引用成环(`summon_owner` / `_axe_ref` / `dot_src` …),
##   Godot 会递归 stringify 直到报 `Maximum dictionary recursion reached`。
##   实测(2026-09-01): 原来那三行 `str(dict)` 刷了 **12 万条**这个错误,
##   并把整个测试拖到 10 分钟还没跑完 —— 这正是它一直挂着 `_wip_` 前缀、
##   **从来没进过门禁**的原因(门禁只自动发现 `verify_*.gd`)。
## ⇒ 复合值只取【形状】(类型 + 尺寸), 对象取实例 id, 标量才原样比。
##   代价: "已有的数组内容变了但长度没变"这一种变化量不到 —— 诚实记在这里,
##   新增键那条分支仍然抓得到绝大多数(buff 类全是标量)。
static func _vsig(v) -> String:
	if v is Dictionary:
		return "D%d" % (v as Dictionary).size()
	if v is Array:
		return "A%d" % (v as Array).size()
	if v is Object:
		return "O%d" % ((v as Object).get_instance_id() if is_instance_valid(v) else 0)
	return str(v)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node_or_null("/root/GameState").test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	## 技能 → 它的主人
	var owner_of := {}
	var pets: Array = DataRegistry.all_pets
	for p in pets:
		for sk in (p.get("skillPool", []) if p is Dictionary else []):
			var t = str((sk as Dictionary).get("type", ""))
			if t != "" and _s._IMPL_SKILLS.has(t):
				owner_of[t] = str(p.get("id", ""))
	var keys: Array = owner_of.keys()
	keys.sort()
	_ok("★分母: 扫到 %d 个已实现技能(<60 就是扫描失效, 不是通过)" % keys.size(),
		keys.size() >= 60, str(keys.size()))

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	## ── 对照组: 放一个【不存在的技能 id】, 记下通用那半会动哪些字段 ──
	_s._units.clear()
	var cu: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-160.0, 0.0))
	cu["maxHp"] = 1.0e6
	cu["hp"] = 1.0e6
	cu["no_basic"] = true
	cu["no_move"] = true
	var ce: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-40.0, 0.0))
	ce["maxHp"] = 1.0e6
	ce["hp"] = 1.0e6
	ce["no_basic"] = true
	ce["no_move"] = true
	_s._units.append(cu)
	_s._units.append(ce)
	var cu_pre := {}
	for k in cu.keys():
		cu_pre[str(k)] = _vsig(cu[k])
	var ce_pre := {}
	for k in ce.keys():
		ce_pre[str(k)] = _vsig(ce[k])
	_s._do_skill(cu, ce, "___nonexistent_skill___")
	for _fc in range(150):
		await get_tree().process_frame
	## churn = 【同样的 150 帧窗口里, 不放任何真技能也会自己动的字段名】。
	## ★这一步是判据的第五版才补上的: 前几版只比"有没有新键", 而纯 buff 类技能
	##   改的是**已有字段的值**(强化随从改 atk/def/mr/lifesteal/crit, 一个新键都不加)
	##   ⇒ 掏空它门禁照样绿。必须连【值】一起比, 再用 churn 把每帧记账减掉。
	var churn := {}
	for pair in [[cu, cu_pre], [ce, ce_pre]]:
		var o: Dictionary = pair[0]
		var snap: Dictionary = pair[1]
		for k in o.keys():
			var ks := str(k)
			if not snap.has(ks) or str(snap[ks]) != str(o[k]):
				churn[ks] = true
	var base_self := {}
	for k in cu.keys():
		base_self[str(k)] = true
	var base_foe := {}
	for k in ce.keys():
		base_foe[str(k)] = true
	_ok("★分母: 对照组建出了单位(自%d/敌%d 字段), 并测出 %d 个【每帧自己会动】的字段"
		% [base_self.size(), base_foe.size(), churn.size()],
		base_self.size() > 50 and base_foe.size() > 50 and churn.size() >= 1)

	var dead: Array = []
	for st in keys:
		var pid: String = str(owner_of[st])
		## ★上一轮的延时回调还抓着【已经被清掉的单位】—— 不清空的话下一轮触发时
		##   引擎报 `Lambda capture at index 0 was freed`, 而门禁的致命正则会把它判红。
		##   实测 3 次里偶发 1 次: **是我这个台子留的悬空引用, 不是产品的问题**。
		_s._pending_shots.clear()
		_s._units.clear()
		var u: Dictionary = _s._spawn._make_unit(pid, "left", c + Vector2(-160.0, 0.0))
		u["maxHp"] = 1.0e6
		u["hp"] = 1.0e6
		u["shield"] = 0.0
		## ★★必须禁掉普攻/移动 —— 反向验证抓到: 我等的那 150 帧里龟在**正常普攻**,
		##   把竹击整个掏空, 伤害照样有 33381(那是普攻打的), 门禁纹丝不动。
		##   判据量的是"这个窗口里有没有伤害", 而要问的是"**技能**造成了没有"。
		u["no_basic"] = true
		u["no_move"] = true
		## ★有些技能【要有前置对象才生效】—— 缩头乌龟的「强化随从」第一行就是
		##   "没有随从就 return"。台子上不建随从的话它当然什么都不做,
		##   那是**被测对象不在场**, 不是技能坏了([[fb-gate-subject-never-constructed]])。
		##   ⇒ 把前置建出来, 而不是给这条开豁免。
		if pid == "hiding":
			_s._spawn._spawn_hiding_minion(u)
		var foes: Array = []
		for k in range(3):
			var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-40.0 + 80.0 * k, -40.0 + 40.0 * k))
			e["maxHp"] = 1.0e6
			e["hp"] = 1.0e6
			e["shield"] = 0.0
			e["no_basic"] = true
			e["no_move"] = true
			foes.append(e)
			_s._units.append(e)
		_s._units.append(u)
		var hp0 := 0.0
		for e in foes:
			hp0 += float(e["hp"])
		var sh0: float = float(u.get("shield", 0.0))
		var hs0: float = float(u.get("hp", 0.0))
		## ★施法【前】对场上每个单位拍一次键集快照 —— 技能的效果可能落在
		##   施法者 / 敌人 / **友军或召唤物**(缩头乌龟的强化随从就是加在随从身上)。
		##   只量施法者和敌人会把它误判成空转(反向验证抓到过)。
		var pre: Array = []
		for o in _s._units:
			var kk := {}
			for k in (o as Dictionary).keys():
				kk[str(k)] = _vsig((o as Dictionary)[k])
			pre.append(kk)
		var born := {"n": 0}
		var cb := func(_nd: Node) -> void: born["n"] += 1
		if _s._world != null:
			_s._world.child_entered_tree.connect(cb)
		_s._do_skill(u, foes[0], str(st))
		for _f in range(150):
			await get_tree().process_frame
		if _s._world != null and _s._world.child_entered_tree.is_connected(cb):
			_s._world.child_entered_tree.disconnect(cb)
		var hp1 := 0.0
		for e in foes:
			hp1 += float(e["hp"])
		var dmg: float = hp0 - hp1
		var gain: float = maxf(0.0, float(u.get("shield", 0.0)) - sh0) \
			+ maxf(0.0, float(u.get("hp", 0.0)) - hs0)
		var nb: int = int(born["n"])
		## 新字段 = 施法后场上任何单位多出来的键, 且**不是对照组也会多出来的那些**
		##   (对照组 = 放一个不存在的技能, 通用施法那半照跑)。
		var newk := 0
		for i in range(mini(pre.size(), _s._units.size())):
			var o: Dictionary = _s._units[i]
			var kk: Dictionary = pre[i]
			for k in o.keys():
				var ks := str(k)
				if churn.has(ks):
					continue          # 每帧自己会动的记账字段, 不算技能干的
				if not kk.has(ks):
					newk += 1         # 新键
				elif str(kk[ks]) != _vsig(o[k]):
					newk += 1         # 已有键但【值变了】—— 纯 buff 类全靠这条
		var flag := ""
		if dmg <= 0.0 and gain <= 0.0 and newk <= 0:
			flag = "❌空转(不掉血·不给盾治疗·场上【任何单位】的状态都没变)"
			dead.append("%s (%s)" % [st, pid])
		if flag != "":
			print("  %-24s %-10s 伤害 %9.1f · 盾/治疗 %8.1f · 新字段 %d · 节点 %d %s"
				% [st, pid, dmg, gain, newk, nb, flag])
	_ok("★分母: 真的逐个放过 %d 个(不是空转)" % keys.size(), keys.size() >= 60)
	_ok("★★每个技能由它自己的龟放出来都必须干活(掉血/盾治疗/敌我状态变化 —— 演出节点不算, 那是通用的)",
		dead.is_empty(), "空转 %d 个: %s" % [dead.size(), str(dead.slice(0, mini(8, dead.size())))])
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 没有死技能" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
