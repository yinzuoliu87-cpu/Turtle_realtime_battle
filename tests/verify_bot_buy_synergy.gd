extends Node
## verify_bot_buy_synergy.gd — 机器人【羁绊流】买装策略的出价分(2026-08-12 今晚排单 B)
##
## 由来: 快照池的机器人原本只有三种买法(合成优先 / 贵的优先 / 随机), **一件都不看羁绊** ——
## 而类型羁绊自 2026-08-03 起是【唯一】的构筑维度。结果快照里全是"无羁绊队",
## 玩家打到的鬼影不体现这套系统, 新装备(060~076)进来后差距只会更大。
## 补第四种玩家原型: 羁绊流(`_cohort.gd` STRATEGIES 的 "synergy")。
##
## ★这里验的是**纯函数 `CohortSim.syn_key`** —— 不跑整场模拟(那要几十分钟, 且带 RNG)。
##   判据是排序【关系】不是绝对分值: 谁该排在谁前面。改权重不该让门禁红, 改【偏好顺序】才该红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_bot_buy_synergy.tscn

const Cohort := preload("res://tests/_cohort.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	var dr = get_node_or_null("/root/DataRegistry")
	if dr == null:
		print("  [FAIL] 缺 autoload DataRegistry"); get_tree().quit(1); return

	print("=== 机器人羁绊流买装策略 ===")

	# ── ★分母: 先证明数据在位 —— 类型表读得到、弓箭是 [3,6,9] 三档 ──
	var tiers: Array = (Phase2Types.TYPES.get("弓箭", {}) as Dictionary).get("tiers", [])
	_ok("★分母: 弓箭类型阈值读得到 = %s(不是空表, 否则下面全是空检查)" % str(tiers),
		tiers.size() == 3 and int(tiers[0]) == 3)
	var bow_ids: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid := str((e as Dictionary).get("id", ""))
		if Phase2Types.type_of(eid) == "弓箭":
			bow_ids.append(eid)
	_ok("★分母: 弓箭类型的装备找得到 %d 件(≥4 才够摆下面的局面)" % bow_ids.size(), bow_ids.size() >= 4)
	if bow_ids.size() < 4 or tiers.is_empty():
		_done()
		return

	var a: String = str(bow_ids[0])
	var b: String = str(bow_ids[1])
	var c: String = str(bow_ids[2])
	var d: String = str(bow_ids[3])
	var def_a: Dictionary = DataRegistry.phase2_equipment_by_id.get(a, {})
	var def_c: Dictionary = DataRegistry.phase2_equipment_by_id.get(c, {})

	# ── ① 差 1 件跨档 > 差 2 件 ──
	#    队伍已有 2 件弓箭 ⇒ 再买 1 件正好到档1(阈值 3)
	var seen2 := {b: true, c: true}
	var tc2 := {"弓箭": 2}
	var k_cross: float = Cohort.syn_key(def_a, seen2, tc2)
	#    队伍只有 1 件弓箭 ⇒ 还差 2 件
	var seen1 := {b: true}
	var tc1 := {"弓箭": 1}
	var k_far: float = Cohort.syn_key(def_a, seen1, tc1)
	_ok("① 跨档件(差1)出价 %.2f > 差2件 %.2f —— 能立刻拿整档属性的先买" % [k_cross, k_far],
		k_cross > k_far and k_far > 0.0)

	# ── ② 差 2 件 > 差 3 件(离阈值越近越先买, 单调) ──
	var k_far3: float = Cohort.syn_key(def_a, {}, {})
	_ok("② 单调性: 差2件 %.2f > 差3件 %.2f" % [k_far, k_far3], k_far > k_far3 and k_far3 > 0.0)

	# ── ③ ★去重: 已有同款 id 的件, 羁绊收益恒为 0(calc_active 按 id 去重) ──
	#    这条是最容易写错的地方 —— 按"件数"数就会误以为重复买也能升档。
	var seen_dup := {a: true, b: true}
	var k_dup: float = Cohort.syn_key(def_a, seen_dup, {"弓箭": 2})
	_ok("③ ★重复件出价 = %.2f(恒 0): 羁绊按 id 去重, 再买一件同款不涨羁绊数" % k_dup,
		absf(k_dup) < 1e-9)
	_ok("③-b ★同一件在【没有】时是跨档件(%.2f) / 【已有】时是 0 —— 差别只来自去重" % k_cross,
		k_cross > 0.0)

	# ── ④ 顶档后不再优先(买了也不涨档), 但仍高于 0 ──
	var top: int = int(tiers[tiers.size() - 1])
	var k_top: float = Cohort.syn_key(def_a, seen2, {"弓箭": top})
	_ok("④ 类型已顶档(%d 件)出价 %.2f: 低于任何还能升档的件, 但不是 0" % [top, k_top],
		k_top < k_far3 and k_top > 0.0)

	# ── ⑤ ★分母: 无类型的东西出价 0(经验书/空位这类不该被羁绊逻辑挑中) ──
	_ok("⑤ ★分母: 未知 id 出价 = 0", absf(Cohort.syn_key({"id": "no_such_equip"}, {}, {})) < 1e-9)
	_ok("⑤-b ★分母: 非字典入参出价 = 0(空货架格不崩)", absf(Cohort.syn_key(null, {}, {})) < 1e-9)

	# ── ⑥ 跨类型比较: 差1件的弓箭 > 差2件的另一类型(不是只在同类型内排序) ──
	var other_type := ""
	var other_def: Dictionary = {}
	for e in DataRegistry.phase2_equipment:
		var eid2 := str((e as Dictionary).get("id", ""))
		var ty2 := str(Phase2Types.type_of(eid2))
		if ty2 != "" and ty2 != "弓箭":
			other_type = ty2
			other_def = e
			break
	if other_type != "":
		var otiers: Array = (Phase2Types.TYPES.get(other_type, {}) as Dictionary).get("tiers", [])
		var need2: int = maxi(int(otiers[0]) - 2, 0)   # 摆成"还差 2 件"
		var k_other: float = Cohort.syn_key(other_def, {}, {other_type: maxi(int(otiers[0]) - 2, 0)})
		_ok("⑥ 跨类型: 弓箭跨档件 %.2f > %s 还差2件 %.2f(排序是全局的, 不分类型)"
			% [k_cross, other_type, k_other], k_cross > k_other)
		_ok("⑥-b ★分母: 对照组本身有效(>0, 否则上一条是拿 0 比大小)", k_other > 0.0 or need2 == 0)

	# ── ⑦ 策略表真的把它排进去了(写了函数没人用 = 死代码) ──
	_ok("⑦ ★_cohort 的 STRATEGIES 里真的有 synergy(否则机器人永远抽不到这套买法)",
		(Cohort.STRATEGIES as Array).has("synergy"),
		)
	print("     STRATEGIES = %s" % str(Cohort.STRATEGIES))

	_done()


func _ok(what: String, cond: bool, extra: String = "") -> void:
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", what, ("  " + extra) if extra != "" else ""])


func _done() -> void:
	print("")
	print("ALL PASS — 机器人羁绊流买装" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
