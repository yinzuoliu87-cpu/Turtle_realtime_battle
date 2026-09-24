extends Node
## verify_timestop_global_freeze.gd — 时停期间【整个战斗世界的状态】有没有变
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：用户 2026-09-14
## ══════════════════════════════════════════════════════════════════
## 「触手和直升机只是我看到的典型，**还有无数东西是否被时停你怎么办**？」
##
## 他说中了要害。在这之前我的做法是**逐个补断言**：背景鱼群、非携带者立绘、
## 一笔护盾余额、触手的内部钟、直升机的坐标……**那是打地鼠**——
## 判据的覆盖面等于"我想得到的东西"，而我永远列不全。
##
## ⇒ 换判据的**形状**：不列举被测对象，改成**扫全部**。
##
## ══════════════════════════════════════════════════════════════════
##  判据：全域差分
## ══════════════════════════════════════════════════════════════════
## 把 `battle` 持有的**每一个系统对象**（`_tentacle_vfx` / `_gun_syn` / `_spec` /
## `_equip_sys` / …，靠 `get_property_list()` 枚举，不靠我手写名单）连同它们内部的
## Dictionary / Array 一起**递归摘要**成一串数字指纹，在时停期间前后各取一次，
## **要求指纹一个字节都不变**。
##
## 这样：**我没想到的东西也在扫描范围里**。以后有人加了新系统、新的每帧驱动，
## 它只要在时停期间动了内部状态，这条就会红——不需要谁记得来加一条断言。
##
## ★三条分母（缺一条这个判据就是空的）：
##   ① 扫到的对象数 / 字段数要够大（扫了个寂寞 = 恒真）
##   ② 时停**之前**同样的指纹**必须在变**（不变说明我摘要的东西本来就是死的）
##   ③ 时停真的进了
##
## ★白名单只放三类**本来就该动**的，每条都写清为什么：
##   · `_timestop` 自己（它在倒计时、在推自己的演出）
##   · 携带者自己的动作会碰到的（伤害统计 / 弹道在途表）
##   · 纯渲染侧的帧计数（不是战斗状态）
## 白名单是「我看过了」，不是「我懒得管」。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 这三类在时停期间**允许**变化，各有理由（见段头）。
const ALLOW := {
	"_timestop": "时停系统自己：在倒计时(_ts_remaining)、在推自己的演出(_ts_sand_t/_ts_wave_t/_ts_core_t)",
	"_ballistics": "携带者的弹道在途表：文案写着「伤害即时结算」，只推 active 的那批",
	"_damage": "伤害统计累加器：携带者打出的伤害要记账",
	"_render": "纯渲染侧（相机/抖动/帧计数），不是战斗状态",
	"_vfx": "演出层：携带者自己的打击火花/飘字",
	"_hud": "UI 层：血条/面板刷新",
	"_equip_tick_sys": "携带者自己的延时结算队列（与 _ballistics 同族，见主场景 in_ts 分支）",
}

var _s = null
var _n := 0
## 时停持有者的单位字典 —— 扫描时跳过【它本人】(见 `_is_carrier` 注释)
var _carriers: Array = []
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


## ★★时停持有者【本人】的单位字典不进指纹。
##   由来(2026-09-15): 全域差分连红 3 次, 诊断拍平后是 `_spec._bal.sb1.probe_decay.u._sep_target` 新增了键 `_st_heal` ——
##   石头龟(非携带者)的 `_sep_target` 引用着携带者的单位字典, 携带者在时停里第一次被治疗, 统计字段被创建,
##   扫描顺着引用扫到了它。那是【携带者自己的动作】(白名单第二类), 不是冻结漏了。
##   ★只跳持有者本人(is_same 比), 不跳所有单位 —— 宽一格就把「非携带者被改了」也放过去。
##   反向验证: 撤掉主场景「时停期间门住全场每帧 tick」那道闸, 本条照样红。
func _is_carrier(d: Dictionary) -> bool:
	if not (d.has("id") and d.has("side")):
		return false
	for c in _carriers:
		if is_same(c, d):
			return true
	return false


## 把任意值递归摘成一个数字指纹。★只摘**数**（float/int/bool/Vector/Color），
## 不摘对象引用与字符串 —— 前者会绕回 battle 自身成环，后者不是"在动"的东西。
func _fp(v, depth: int) -> float:
	if depth > 4:
		return 0.0
	var t := typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v)
	if t == TYPE_BOOL:
		return 1.0 if v else 0.0
	if t == TYPE_VECTOR2:
		return (v as Vector2).x * 1.7 + (v as Vector2).y * 2.3
	if t == TYPE_VECTOR3:
		return (v as Vector3).x * 1.7 + (v as Vector3).y * 2.3 + (v as Vector3).z * 3.1
	if t == TYPE_COLOR:
		var c: Color = v
		return c.r * 1.1 + c.g * 1.3 + c.b * 1.7 + c.a * 1.9
	if t == TYPE_ARRAY:
		var a: Array = v
		var acc := 0.0
		for i in range(mini(a.size(), 64)):
			acc += _fp(a[i], depth + 1) * float(i + 1)
		return acc + float(a.size()) * 0.5
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		if _is_carrier(d):
			return 0.0
		var acc2 := 0.0
		var ks: Array = d.keys()
		## ★键排序: 字典遍历顺序在两次快照之间可能不同, 不排序会读出假变化
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for i in range(mini(ks.size(), 64)):
			## ★★单位字典**不能**当 key、也不能深递归 —— 它们互相引用成环
			##   (CLAUDE.md §3.2: Godot 递归哈希会无限递归卡死)。depth 上限挡住了这条。
			acc2 += _fp(d[ks[i]], depth + 1) * float(i + 1)
		return acc2 + float(ks.size()) * 0.5
	return 0.0


## 扫 battle 的每一个系统对象, 逐字段摘指纹。返回 {"<对象>.<字段>": 指纹}。
func _snap() -> Dictionary:
	var out: Dictionary = {}
	for p in _s.get_property_list():
		var pn: String = str(p.get("name", ""))
		if not pn.begins_with("_") or ALLOW.has(pn):
			continue
		var obj = _s.get(pn)
		if not (obj is RefCounted):
			continue
		for q in (obj as Object).get_property_list():
			var qn: String = str(q.get("name", ""))
			## ★不再只扫 `_` 开头的 —— 那样只扫到 55 个字段, 扫描面白白缩了一半。
			##   只跳过 `battle`(它绕回 battle 自身成环)与 Godot 自带的 `script`/`RefCounted` 属性。
			if qn == "battle" or qn == "script" or qn == "" or qn.begins_with("Ref"):
				continue
			var qt: int = int(q.get("type", 0))
			if qt != TYPE_FLOAT and qt != TYPE_INT and qt != TYPE_BOOL \
					and qt != TYPE_ARRAY and qt != TYPE_DICTIONARY \
					and qt != TYPE_VECTOR2 and qt != TYPE_VECTOR3:
				continue
			out[pn + "." + qn] = _fp((obj as Object).get(qn), 0)
	return out


## 同 `_snap` 的扫描范围与深度, 但把每个字段拍平成「路径 → 数」—— 只在判据红了之后用来看「到底哪个数变了」。
## ★深度上限与 `_fp` 相同(4): 单位字典互相引用成环(CLAUDE.md §3.2), 不设上限会无限递归。
func _flat(v, path: String, depth: int, out: Dictionary) -> void:
	if depth > 4 or out.size() > 4000:
		return
	var t := typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		out[path] = float(v)
	elif t == TYPE_BOOL:
		out[path] = 1.0 if v else 0.0
	elif t == TYPE_VECTOR2 or t == TYPE_VECTOR3 or t == TYPE_COLOR:
		out[path] = _fp(v, 0)
	elif t == TYPE_ARRAY:
		var a: Array = v
		for i in range(mini(a.size(), 64)):
			_flat(a[i], "%s[%d]" % [path, i], depth + 1, out)
	elif t == TYPE_DICTIONARY:
		var d: Dictionary = v
		if _is_carrier(d):
			return
		var ks: Array = d.keys()
		ks.sort_custom(func(x, y): return str(x) < str(y))
		## ★键名清单也记下来: `_fp` 会把字典的【键数量】算进指纹, 而第 5 层的值一律算 0 ——
		##   一个值是字符串/对象的键被加上或删掉, 指纹会变, 但拍平的数字一个都不会变
		##   (2026-09-15 第二版诊断就是这样打出「变了 0 处」的)。
		var names: PackedStringArray = []
		for k in ks:
			names.append(str(k))
		out[path + "#keys"] = ",".join(names)
		for i in range(mini(ks.size(), 64)):
			_flat(d[ks[i]], "%s.%s" % [path, str(ks[i])], depth + 1, out)


func _snap_raw() -> Dictionary:
	var out: Dictionary = {}
	for p in _s.get_property_list():
		var pn: String = str(p.get("name", ""))
		if not pn.begins_with("_") or ALLOW.has(pn):
			continue
		var obj = _s.get(pn)
		if not (obj is RefCounted):
			continue
		for q in (obj as Object).get_property_list():
			var qn: String = str(q.get("name", ""))
			if qn == "battle" or qn == "script" or qn == "" or qn.begins_with("Ref"):
				continue
			var qt: int = int(q.get("type", 0))
			if qt != TYPE_FLOAT and qt != TYPE_INT and qt != TYPE_BOOL \
					and qt != TYPE_ARRAY and qt != TYPE_DICTIONARY \
					and qt != TYPE_VECTOR2 and qt != TYPE_VECTOR3:
				continue
			var leaves: Dictionary = {}
			_flat((obj as Object).get(qn), "", 0, leaves)
			out[pn + "." + qn] = leaves
	return out


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var hit: Array = []
	for k in a.keys():
		if b.has(k) and absf(float(a[k]) - float(b[k])) > 1e-6:
			hit.append(k)
	hit.sort()
	return hit


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


func _mk(id: String, side: String, dx: float, star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + Vector2(dx, 0))
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	if star > 0:
		u["equips"] = [{"id": "p2eq_059", "star": star}]
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 059 时停: 全域差分(不列举被测对象, 扫 battle 持有的全部系统状态) ===")
	print("   用户 2026-09-14:「触手和直升机只是我看到的典型, 还有无数东西是否被时停你怎么办?」")
	_s = RB.new()
	add_child(_s)
	await _wait(40)

	_s._units.clear()
	## ★★沙漏**先不装**(star=0), 到手动触发那一刻才装上。
	##   由来(2026-09-15): 这条门禁独立跑 3/3 全过, 却在并行门禁里红过一次。
	##   独立跑每帧 ~0.016 秒, 时停前那 170 帧只走 2.7 秒; 并行负载下每帧被钳到 0.1 秒
	##   ⇒ 170 帧 = 17 秒, **越过沙漏的天然触发点 10 秒**, 时停会自己先放出来,
	##   污染「时停之前」的分母。钉 `_t=9.5` 探针确认天然触发确实会先放(手动前 _ts_fired=true)。
	##   ⚠ 如实记: 那次钉钟的探针**并没有复现出红** —— 所以这是一个被证实的暴露,
	##     但**不能说它就是那次红的原因**。堵它是因为它会让判据读错, 不是因为它已被定罪。
	var carrier: Dictionary = _mk("fortune", "left", -200.0, 0)
	var other: Dictionary = _mk("stone", "right", 260.0, 0)
	## ★★2026-09-20(B 阶段·战斗确定性)——【为什么要把携带者的 active 摘掉】
	##   时停的文案写死了「active 携带者照常施法/伤害即时结算」, 而**施法本身要掷骰**:
	##   本用例的携带者是财神龟, 它会在下面那段测量窗口里放一次骰子(`_sk_fortune_dice`)。
	##   那一掷【原来走的是裸全局 randi_range】—— 引擎的全局状态, 本用例根本扫不到;
	##   B 阶段把它路由到 `_battle_rng`(受控 PRNG·可种子化) 之后才落进扫描面,
	##   `_battle_rng.state` 当场变 ⇒ 判据红。红的不是"时停漏了什么", 是"原来有一处漏在扫描面之外"。
	## ★不把 `_battle_rng` 塞进 ALLOW: 那是**放松判据**(以后真有"时停里偷偷掷骰"的 bug 也不会红)。
	##   改成【让携带者在窗口内本就不该掷骰】—— `_battle_rng` 留在禁止集里, 判据保持满齿。
	## ⚠ 代价: 本用例不再覆盖"携带者边施法边冻结"那一路。那需要"变几次 == 施法几次"的判据, 另案。
	var _gold_ctl: float = float(carrier.get("gold", 0.0))
	_s._fortune_sys._sk_fortune_dice(carrier)   # 控制组: 真放一次, 证明【金币涨了】确实等价于【施过法】
	_ok("★分母⑥: 金币增量能当施法计数(控制组真放一次骰子 → +%.0f 金)"
		% (float(carrier.get("gold", 0.0)) - _gold_ctl),
		float(carrier.get("gold", 0.0)) > _gold_ctl,
		"控制组放了也不涨 ⇒ 下面那条「窗口内 0 次施法」是恒真式(拿一个永远为 0 的量去断言 0)")
	carrier["active_skills"] = []   # 从这里起, 携带者在窗口内不会再自己放技
	## ★★**被动也要停**(2026-09-24 补)。上面那一行摘掉了携带者的**主动技**,
	##   而财神龟还有一条**被动**: 每 3 秒 `_battle_rng.randi_range` 掎一次金币
	##   (`RealtimeBattle3DScene` 那行 `if u["id"] == "fortune"`)。
	##   满帧率下测量窗口里几乎没有游戏时间流逝, 它等不到三秒 ⇒ 一直看不见;
	##   15fps 下窗口多走 4 倍游戏时间, 它掎了 ⇒ `_battle_rng.state` 动 ⇒ 主判据红。
	##   探针实证(--max-fps 15): 携带者 `_goldtimer: 2.683 → 1.633`(过了一轮)。
	## ★做法与上面那一行**同一个思路**: 不把 `_battle_rng` 塞进 ALLOW(那是放松判据),
	##   而是让携带者**本就不该掎骰** —— 把被动的计时器按到永远到不了点。
	carrier["_goldtimer"] = -1.0e9
	## 把场上尽量摆满: 触手 / 直升机 / 一笔会衰减的余额 —— 让扫描有东西可扫
	_s._tentacle_vfx.ensure_forced("right", 2)
	_s._equip_sys._gun_sys._spawn_heli(other, 2, 300.0)
	_s._spec.grant(other, "probe_decay", 1000.0, {"decay_sec": 40.0})
	await _wait(40)

	var a0: Dictionary = _snap()
	var objs: Dictionary = {}
	for k in a0.keys():
		objs[str(k).split(".")[0]] = true
	_ok("★分母①: 扫到 %d 个系统对象、共 %d 个字段" % [objs.size(), a0.size()],
		objs.size() >= 20 and a0.size() >= 90,
		"扫了个寂寞 ⇒ 下面那条是恒真式")

	await _wait(90)
	var a1: Dictionary = _snap()
	var pre: Array = _diff(a0, a1)
	_ok("★分母②: 时停【之前】这些字段里有 %d 个在变" % pre.size(),
		pre.size() >= 5,
		"一个都不变 ⇒ 我摘要的东西本来就是死的, 判据什么都验不到")
	print("     [探针] 时停前在变的(前 10): %s" % str(pre.slice(0, 10)))

	var ts = _s._timestop
	_ok("★分母④: 手动触发之前时停【没有】自己放过(_ts_fired=%s)" % str(ts._ts_fired),
		not bool(ts._ts_fired) and (ts._ts_active as Array).is_empty(),
		"天然触发先放了 ⇒ 「时停之前」那两次快照其实是在时停里取的, 分母② 读错了")
	carrier["equips"] = [{"id": "p2eq_059", "star": 3}]   # 到这一刻才装上沙漏
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	ts._ts_update_trigger(10.0)
	_ok("★分母③: 时停真的进了(active=%d, 剩 %.1f 秒)"
		% [(ts._ts_active as Array).size(), float(ts._ts_remaining)],
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 5.0,
		"没进时停 ⇒ 下面是空检查")
	_carriers = (ts._ts_active as Array).duplicate()
	_ok("★分母⑤: 跳过的只有时停持有者本人(%d 个), 非携带者那只【不在】里面" % _carriers.size(),
		_carriers.size() == 1 and is_same(_carriers[0], carrier) and not _is_carrier(other),
		"跳多了 ⇒ 非携带者被改也看不见")
	await _wait(50)   # 让入停那一下的演出自己跑完

	var _gold_win: float = float(carrier.get("gold", 0.0))   # 窗口内"施法次数"的观测量(见上面 ⑥)
	var b0: Dictionary = _snap()
	var raw0: Dictionary = _snap_raw()
	await _wait(120)
	var b1: Dictionary = _snap()
	var raw1: Dictionary = _snap_raw()
	var dur: Array = _diff(b0, b1)
	_ok("★分母⑦: 时停窗口内携带者【一次都没施法】(金币增量 %.0f, 须为 0)"
		% (float(carrier.get("gold", 0.0)) - _gold_win),
		absf(float(carrier.get("gold", 0.0)) - _gold_win) < 0.001,
		"它要是真放了技, 掷骰会让 `_battle_rng` 动 —— 那时下面那条红的是【文案写死的合法行为】而不是 bug")
	## ★红的时候把变了的字段前后原始值打出来 —— 指纹只说「变了」, 不说「谁、哪一笔、怎么变」。
	##   由来(2026-09-15): `_spec._bal` 在时停期间连红 3 次, 指纹里看不出是哪个单位的哪笔余额。
	##   ★第一版打原始字符串(截 600 字), 只看到余额条目里存着整个单位字典 —— 看不到是哪个数变了。
	##     ⇒ 拍平成「路径 → 数」逐条比, 只打不同的那几条。
	for dk in dur:
		var diffs: Array = []
		var f0: Dictionary = raw0.get(dk, {})
		var f1: Dictionary = raw1.get(dk, {})
		for pk in f1.keys():
			if str(pk).ends_with("#keys") and f0.has(pk) and str(f0[pk]) != str(f1[pk]):
				var s0: PackedStringArray = str(f0[pk]).split(",")
				var s1: PackedStringArray = str(f1[pk]).split(",")
				var added: Array = []
				var removed: Array = []
				for nm in s1:
					if not s0.has(nm):
						added.append(nm)
				for nm in s0:
					if not s1.has(nm):
						removed.append(nm)
				diffs.append("%s 新增键 %s · 少了键 %s" % [pk, str(added), str(removed)])
			elif not f0.has(pk) or str(f0[pk]) != str(f1[pk]):
				diffs.append("%s: %s → %s" % [pk, str(f0.get(pk, "无")), str(f1[pk])])
		for pk in f0.keys():
			if not f1.has(pk):
				diffs.append("%s: %s → 无" % [pk, str(f0[pk])])
		diffs.sort()
		print("     [探针] %s 变了 %d 处: %s" % [dk, diffs.size(), str(diffs.slice(0, 12))])
	_ok("★★ 时停期间【全部系统状态】一个字段都不变(实测 %d 个变了, 时停前是 %d 个)"
		% [dur.size(), pre.size()],
		dur.is_empty(),
		"这些还在动: %s —— 白名单在本文件顶部 ALLOW, 加之前必须写清为什么它该动" % str(dur.slice(0, 8)))

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
