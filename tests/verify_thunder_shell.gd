extends Node
## verify_thunder_shell.gd — 025 雷鸣贝壳【降雷】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「每 EquipTickSystem.THUNDER_IV 秒降下 **1/2/3 道雷**各电击 1 名随机敌人,
##   每道造成 **1×攻击力的真实伤害**。」
##
## ⇒ 量三件事:
##   ① 道数吃星级: ★1 一道 / ★3 三道(**很容易只落第一道**)
##   ② 每道 = 1×ATK 且是**真实伤害**(不吃护甲/魔抗)
##   ③ ★★走真入口: 让 `_tick_thunder` 自己跑一个周期, 看雷到底落不落
##
## ★★改之前两层延时都是 tween(`tween_interval(d*0.3)` 错峰 + `tween_interval(0.25)` 雷中段):
##   tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5) ⇒ ★2/★3 的第 2、3 道
##   可能根本不落。现在两层都挂 `EquipTickSystem._bolt_q`, 由 `_drain_bolts()` 按游戏钟结算。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ET := preload("res://scripts/systems/equip/equip_tick_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## ★用产品自己的造单位函数, 不手抄字段表(手抄的副本必然落后 —— 024 那轮抄两版漏两样)
func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	## ★暴击归零: 同一条断言两次跑出 120 / 180 —— 是**暴击在随机**, 不是产品在飘。
	##   判据要对随机不敏感(memory [[fb-make-assertions-rng-insensitive]])。
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	return u


func _total_hp(arr: Array) -> float:
	var t := 0.0
	for o in arr:
		t += float(o["hp"])
	return t


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 025 雷鸣贝壳: 每 %.0f 秒降 1/2/3 道雷 ===" % ET.THUNDER_IV)
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	## ★★关掉编辑态: DEBUG_EDIT ⇒ _edit_mode 置真 ⇒ _sim_step 里的 _fight_on 把整组 tick 门住,
	##   不关的话测出来的 0 是**测试自己的 0**(024 那轮栽过)。
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	_ok("① ★分母: THUNDER_IV = %.1f 秒" % ET.THUNDER_IV, ET.THUNDER_IV > 0.0)

	# ── ① ★★道数吃星级: 数它**自己排进队列的雷**, 不量世界净血量 ──────
	## ★第一版量的是三个敌人的总血量变化 —— 把**普攻也算进去了**(★3 报出 1799 道)。
	##   memory [[fb-make-the-noise-deterministic]]: 别量世界净变化, 要量被测那件事的账。
	for star_i in [0, 1, 2]:
		var want: int = [1, 2, 3][star_i]
		var carrier: Dictionary = _mk(500.0, 400.0, "left")
		carrier["equips"] = [{"id": "p2eq_025", "star": [1, 2, 3][star_i]}]
		carrier["eq_state"] = {"p2eq_025": {}}
		var o1: Dictionary = _mk(760.0, 400.0, "right")
		_s._units.append(carrier)
		_s._units.append(o1)
		ets._bolt_q.clear()
		## 直调周期函数喂满一个 THUNDER_IV, 让它当场排雷(不跑整局, 免得混进普攻)
		ets._tick_thunder(carrier, ET.THUNDER_IV + 0.01)
		var queued := 0
		for it in ets._bolt_q:
			if str(it["kind"]) == "bolt":
				queued += 1
		_ok("① ★★★%d 星排了 %d 道雷(应 %d 道)" % [[1, 2, 3][star_i], queued, want],
			queued == want,
			"★2/★3 的第 2、3 道原来挂在 tween 上, 无头下根本不落")
		carrier["alive"] = false
		o1["alive"] = false

	## ★每节前清场 —— 前面几节留下的单位还在 `_units` 里, 随机雷会劈到它们身上
	_s._units.clear()
	# ── ② 每道 = 1×ATK 的【真实】伤害 ─────────────────────────────
	## ★★不能断言「正好 100」: 携带者 id="basic" 时走**小龟·不屈**(按目标稀有度增伤, 默认 +20%)
	##   ⇒ 实测 120。那是**产品本来的行为**, 不是 025 的 bug。
	##   所以判据改成两条**对该被动不敏感**的形状:
	##     a) 护甲/魔抗拉满 vs 归零, 伤害**相等** ⇒ 真实伤害不吃减伤
	##     b) 攻击力翻倍, 伤害**翻倍** ⇒ 系数是 1×ATK(线性)
	_s._units.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	var tanky: Dictionary = _mk(760.0, 400.0, "right")
	tanky["def"] = 500.0
	tanky["mr"] = 500.0
	var squishy: Dictionary = _mk(820.0, 400.0, "right")
	squishy["def"] = 0.0
	squishy["mr"] = 0.0
	_s._units.append(c2)
	_s._units.append(tanky)
	_s._units.append(squishy)
	var ht: float = float(tanky["hp"])
	var hq: float = float(squishy["hp"])
	ets._thunder_hit(c2, tanky)
	ets._thunder_hit(c2, squishy)
	var dt_: float = ht - float(tanky["hp"])
	var dq: float = hq - float(squishy["hp"])
	_ok("② ★分母: 两边都真的掉血了(厚 %.0f / 脆 %.0f)" % [dt_, dq], dt_ > 0.0 and dq > 0.0)
	_ok("② ★★护甲500魔抗500 与 归零 伤害相等 ⇒ 真实伤害不吃减伤",
		absf(dt_ - dq) < 1.0, "厚 %.1f vs 脆 %.1f" % [dt_, dq])
	## b) 攻击力翻倍 ⇒ 伤害翻倍
	var c2b: Dictionary = _mk(500.0, 400.0, "left")
	c2b["atk"] = 200.0
	_s._units.append(c2b)
	var sq2: Dictionary = _mk(880.0, 400.0, "right")
	sq2["def"] = 0.0
	sq2["mr"] = 0.0
	_s._units.append(sq2)
	var h2b: float = float(sq2["hp"])
	ets._thunder_hit(c2b, sq2)
	var d2b: float = h2b - float(sq2["hp"])
	_ok("② ★★攻击力 100→200, 伤害 %.0f→%.0f(应翻倍) ⇒ 系数是 1×ATK" % [dq, d2b],
		absf(d2b - dq * 2.0) < 2.0)
	## ★每节前清场 —— 前面几节留下的单位还在 `_units` 里, 随机雷会劈到它们身上
	_s._units.clear()
	# ── ③ ★★★走真入口: 排进队列的雷**真的会被结算掉** ────────────
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	c3["equips"] = [{"id": "p2eq_025", "star": 3}]
	c3["eq_state"] = {"p2eq_025": {}}
	var o3: Dictionary = _mk(760.0, 400.0, "right")
	o3["def"] = 500.0
	o3["mr"] = 500.0
	_s._units.append(c3)
	_s._units.append(o3)
	ets._bolt_q.clear()
	ets._tick_thunder(c3, ET.THUNDER_IV + 0.01)
	var h3: float = float(o3["hp"])
	## 只推 sim(不跑普攻那条: 目标护甲魔抗拉满, 普攻几乎打不动), 推够 0.3×2 + 0.25
	for _k in range(120):
		_s._sim_step(_s.SIM_DT, false, false)
	var d3: float = h3 - float(o3["hp"])
	_ok("③ ★★★三道雷全部结算掉了(总伤 %.0f ≈ 3×100)" % d3,
		d3 >= 290.0,
		"若只有 100: 第 2、3 道没落 —— 就是 tween 那条老病")
	# ── ③ 队列排空, 没有漏结算 ───────────────────────────────────
	_ok("③ 队列已排空(没有漏结算的项)", ets._bolt_q.is_empty(),
		"剩 %d 项" % ets._bolt_q.size())

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 6:
		print("  [FAIL] ★断言只有 %d 条(<6) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 025 雷鸣贝壳" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
