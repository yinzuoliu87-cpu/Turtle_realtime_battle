extends Node
## verify_copy_rules.gd — 龟壳「复制」的黑名单规则 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-27:「那个规则是有问题的啊」
##   「龟壳的复制是偷取主动技能，比如双头融合，那释放就只应该打出几道波；
##     比如虚化，就是给自己 buff 并造成伤害，**我不明白为什么不能复制**」
##
## 原规则是白名单（默认不能抄、逐个批准），理由写着「排除变身/召唤/自增益，
## 否则从龟壳放会污染自身状态」—— 把"实现麻烦"当成了"玩法规则"。
## 后果：87 个主动技只能抄 29 个，**12 只龟一个技能都抄不到**。
##
## 探针 `tests/_probe_copy_residue.gd`（56 个技能 × 带对照组 × 等 6 秒）实测：
## **真正留下残留的只有 5 个** ⇒ 为了挡住 5 个，挡掉了 51 个。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据走**真复制入口** `_sk_shell_copy`，不是直接读常量表 ——
##   读表只能证明"名单写对了"，证明不了"复制真的会挑到它"
##   (memory [[fb-verify-must-run-the-real-path]])。
## ★每条断言配分母：候选池非空、目标真的挨了打、黑名单技能真的被构造出来过。
##   N=0 是空检查不是通过 (memory [[fb-gate-subject-never-constructed]])。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_copy_rules.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")

## ★★这份名单【写死在测试里】, **不是**从产品的 `CopyRules.UNCOPYABLE` 读的。
##
##   2026-08-29 反向验证当场抓到我自己的漏洞: 第一版遍历的是产品的黑名单 ⇒
##   把 `cyberSmartAI` 从产品名单里删掉(= 放行一个会变形态的技能),
##   门禁**照样 ALL PASS** —— 因为它"不测它了"。
##   遍历被测对象自己的名单 = 只能发现"多了什么", 发现不了"少了什么"。
##
##   这五个是探针 `tests/_probe_copy_residue.gd` 实测【6 秒后仍留残留】的全部,
##   要放行哪一个, 必须先跑探针证明它不再留残留, 然后**同时改这里**。
const MUST_BLOCK := ["angelAscend", "fortuneBuyEquip", "cyberSmartAI", "hunterStealth", "shellShadow"]

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 造一个龟壳 + 一个带指定技能的敌人, 走真复制入口, 回报"到底有没有放出来"。
##
## ★★判据选型踩过的坑(留档): 第一版拿【同步伤害 + skill_cd 多了一条】当判据, 结果
##   5 个"应该能抄"的技能红了 4 个 —— **不是产品的问题, 是判据不合身**:
##     · `bambooHeal` 是**纯治疗**, 对敌人本来就 0 伤害
##     · `twoHeadFusion` / `iceFreeze` / `lineInkBomb` 的伤害埋在**延时队列/弹道**里,
##       同步那一瞬当然是 0(CLAUDE.md §3.5 同族)
##     · `skill_cd` 是 `_cast_skill` 写的, 而复制走的是 `_do_skill` —— 压根不会写
##   ⇒ 改成量【世界变了没有】: 敌人掉血 / 龟壳回血 / 龟壳得盾 / 场上多了单位, 任一即算。
##     并用**墙钟**等 1.2 秒让延时与弹道结算(不用帧数、不用游戏时钟 —— CLAUDE.md §3.5)。
##
## 返回 {cast: bool, dmg: float, heal: float, shield: float, spawned: int}
func _copy_once(stype: String):
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["energy"] = 999.0
	sh["maxHp"] = 6000.0
	sh["hp"] = 3000.0                           # ★留出回血余量, 满血时治疗类看不出变化
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(140, 0))
	## ★空字符串 = 对照组: 敌人身上没有可抄的技 ⇒ 候选池为空 ⇒ 什么都不该发生。
	foe["active_skills"] = [] if stype == "" else [stype]
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	foe["no_basic"] = true
	foe["no_move"] = true
	_s._units.clear()
	_s._units.append(sh)
	_s._units.append(foe)
	_s._over = false

	var hp0: float = float(foe["hp"])
	var shp0: float = float(sh["hp"])
	var ssh0: float = float(sh.get("shield", 0.0)) + float(sh.get("_auraShieldVal", 0.0))
	var n0: int = _s._units.size()
	_s._shell_sys._sk_shell_copy(sh, foe)
	## ★墙钟等结算 —— 帧数在无头 CI 下每帧只推进 1ms, 游戏时钟在 _kill 后会冻结
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200:
		await get_tree().process_frame

	var dmg: float = hp0 - float(foe["hp"])
	var heal: float = float(sh["hp"]) - shp0
	var shd: float = (float(sh.get("shield", 0.0)) + float(sh.get("_auraShieldVal", 0.0))) - ssh0
	var spawned: int = _s._units.size() - n0
	return {
		"cast": dmg > 0.5 or heal > 0.5 or shd > 0.5 or spawned > 0,
		"dmg": dmg, "heal": heal, "shield": shd, "spawned": spawned,
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟壳复制·黑名单规则 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var impl: Dictionary = _s._IMPL_SKILLS
	var block: Dictionary = CopyRules.UNCOPYABLE

	# ── ① 分母 ──
	_ok("★分母: 黑名单非空且很小(%d 条) —— 空了这门禁就是恒真" % block.size(),
		block.size() >= 3 and block.size() <= 12, str(block.keys()))
	_ok("★分母: _IMPL_SKILLS 解析到 %d 条" % impl.size(), impl.size() >= 50)
	var n_cop := 0
	for k in impl.keys():
		if CopyRules.can_copy(str(k), impl):
			n_cop += 1
	_ok("★★分母: 现在能抄 %d / %d 个已实现技(旧白名单只有 29)" % [n_cop, impl.size()],
		n_cop >= 70, "低于 70 说明黑名单又长回去了")

	# ── ①b ★★探针量到会污染的那 5 个, 一个都不许从黑名单里消失 ──
	## 见 MUST_BLOCK 头注: 遍历产品名单只能发现"多了", 发现不了"少了"。
	for st0 in MUST_BLOCK:
		_ok("★★①b `%s` 必须仍在黑名单里(探针实测它会留残留)" % str(st0),
			block.has(str(st0)),
			"从黑名单消失了 —— 要放行必须先跑 _probe_copy_residue 证明不再留残留")

	# ── ② 黑名单每条都必须【真实存在】且【理由写了具体字段名】 ──
	## 挡一个不存在的技能 = 挡了个寂寞(打错字/技能改名后没跟), 而且不报错。
	for k in block.keys():
		var st := str(k)
		_ok("★② 黑名单 `%s` 真的是个已实现技能" % st, impl.has(st),
			"不存在 ⇒ 挡了个寂寞")
		var why := CopyRules.why_not(st)
		## 理由必须写探针量到的**具体字段名**(小写下划线的标识符), 不许写"感觉会出问题"
		_ok("★② 黑名单 `%s` 的理由里有具体字段名" % st,
			why.length() >= 12 and RegEx.create_from_string("[a-z_]{4,}").search(why) != null,
			why)

	# ── ③ ★★走真复制入口: 黑名单里的【抄不到】 ──
	## ★同样遍历 MUST_BLOCK 而不是产品名单 —— 理由见 MUST_BLOCK 头注。
	var blocked_tested := 0
	for k in MUST_BLOCK:
		var st := str(k)
		if not impl.has(st):
			continue
		var r: Dictionary = await _copy_once(st)
		blocked_tested += 1
		_ok("★★③ 黑名单 `%s`: 走真复制入口后【没被放出来】" % st,
			not bool(r["cast"]), "cast=%s 伤害%.0f 回血%.0f 盾%.0f 召唤%d" % [str(r["cast"]), float(r["dmg"]), float(r["heal"]), float(r["shield"]), int(r["spawned"])])
	_ok("★分母: 真的试了 %d 个黑名单技能(N=0 是空检查)" % blocked_tested,
		blocked_tested >= 3)

	# ── ④ ★★走真复制入口: 用户点名的那几个【现在抄得到】 ──
	## 用户原话举的两个例子: 双头融合(twoHeadFusion) / 虚化(ghostPhase)。
	## 另加三个原白名单挡掉、探针实测零风险的, 覆盖不同效果类别:
	##   iceFreeze(控制+伤害) / bambooHeal(纯治疗自增益) / lineInkBomb(纯伤害)
	var want := ["twoHeadFusion", "ghostPhase", "iceFreeze", "bambooHeal", "lineInkBomb"]
	var allowed_tested := 0
	for st in want:
		if not impl.has(st):
			_ok("★④ `%s` 应该是已实现技能" % st, false, "_IMPL 里没有 —— 技能改名了?")
			continue
		var r: Dictionary = await _copy_once(str(st))
		allowed_tested += 1
		_ok("★★④ 用户点名/同类 `%s`: 走真复制入口后【真的放出来了】" % st,
			bool(r["cast"]), "cast=%s 伤害%.0f 回血%.0f 盾%.0f 召唤%d" % [str(r["cast"]), float(r["dmg"]), float(r["heal"]), float(r["shield"]), int(r["spawned"])])
	_ok("★分母: 真的试了 %d 个应可抄技能(N=0 是空检查)" % allowed_tested,
		allowed_tested >= 4)

	# ── ④b ★★对照组: 敌人身上【没有可抄的技】⇒ 什么都不该发生 ──
	## 没这条的话, ④ 的判据("世界变了")可能只是龟壳自己被动 tick 出来的 ——
	## 那样每个技能都会"通过", 恒真式(memory [[fb-verify-check-can-fail]])。
	var ctrl: Dictionary = await _copy_once("")
	_ok("★★④b 对照组(敌人无可抄技): 世界不该变",
		not bool(ctrl["cast"]),
		"伤害%.0f 回血%.0f 盾%.0f 召唤%d" % [float(ctrl["dmg"]), float(ctrl["heal"]),
			float(ctrl["shield"]), int(ctrl["spawned"])])

	# ── ⑤ 分派不到的 type 一律抄不到(130 龟能白花的老坑) ──
	## 原白名单里躺过 13 个普攻位技能 —— 它们走普攻分派, 放在 `_do_skill` 名单里
	## 永远不会被执行, 抄到它 = 龟能白花且屏幕上什么都不发生, 还不报错。
	_ok("★⑤ 不在 _IMPL 里的 type 抄不到(编一个不存在的)",
		not CopyRules.can_copy("__nope_not_a_skill__", impl))
	_ok("★⑤ 空字符串抄不到", not CopyRules.can_copy("", impl))

	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 28:
		print("  [FAIL] ★分母: 断言只有 %d 条(<28) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 龟壳复制黑名单规则" if _fail == 0 else "FAIL x%d — 龟壳复制黑名单规则" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
