extends Node
## verify_chain_lightning.gd — 026 雷电法杖【连锁闪电】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「携带者的普攻为该法器法力条充能 EquipSystem.THUNDER_MANA_PER_HIT 点;
##   法力条集满时朝随机目标发射连锁闪电, 造成 **(25/40/70 + 10% 攻击力) 魔法伤害**,
##   在不同敌人间跳跃, **共命中 7/10/15 次**。」(用户 2026-10-22 改; 原 40/60/90、4/5/6)
##
## ★★改之前: 逐跳错峰是 `tween_interval(i * 0.2)` + `tween_callback` ——
##   tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5)
##   ⇒ **第 2 跳以后根本不落**。024 龙蛋 / 025 雷鸣贝壳 / 026 连着三件同病,
##   所以做成**共享原语** `EquipTickSystem.schedule(delay, callable)`
##   (memory [[fb-fix-the-shared-primitive-not-one-instance]]: 共享原语被否就换原语,
##    不是只修那一件)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## ★用产品自己的造单位函数, 不手抄字段表(024 那轮手抄两版漏两样)
func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	## 暴击归零: 判据要对随机不敏感(025 那轮同一条断言跑出 120/180)
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	## ★★把普攻关掉: ② 那条要数「被连锁打中几个」, 而推 sim 时普攻也会打人
	##   ⇒ 实测报出 **7 个(应 6 个)**, 多的那个是普攻打的, 不是连锁。
	##   memory [[fb-make-the-noise-deterministic]]: 别量世界净变化, 把噪声源关掉再量。
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 026 雷电法杖: 连锁闪电共命中 7/10/15 次 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	## 关编辑态: DEBUG_EDIT ⇒ _edit_mode 置真 ⇒ _fight_on 把整组 tick 门住(024 那轮栽过)
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ── ① ★★跳数吃星级: 7/10/15; 每一跳排进去的伤害 = 基础 + 10% 攻击力 ──────────
	## 数它**自己排进队列的跳**, 不量世界净血量(025 那轮量净血量把普攻算进去了)
	_ok("① 常量 = 用户定的数(7/10/15 跳 · 25/40/70 + 10%% 攻击力)",
		ES.CHAIN_HOPS == [7, 10, 15] and ES.CHAIN_DMG == [25, 40, 70] and absf(ES.CHAIN_ATK_COEF - 0.1) < 1e-9)
	for star_i in [0, 1, 2]:
		var want: int = ES.CHAIN_HOPS[star_i]
		_s._units.clear()
		ets._bolt_q.clear()
		var carrier: Dictionary = _mk(500.0, 400.0, "left")
		_s._units.append(carrier)
		## 摆 8 个敌人: 比最大跳数(6)多, 才看得出它是「最多 N 个」而不是「有几个打几个」
		for k in range(8):
			_s._units.append(_mk(700.0 + 70.0 * k, 400.0 + (30.0 if k % 2 else -30.0), "right"))
		carrier["atk"] = 300.0
		_s._equip_sys._eq_chain_lightning(carrier, star_i)
		var queued: int = ets._bolt_q.size()
		_ok("① ★★★%d 星排了 %d 跳(应 %d 跳)" % [[1, 2, 3][star_i], queued, want],
			queued == want,
			"第 2 跳以后原来挂在 tween 上, 无头下根本不落")
		## 每一跳绑定的伤害(_chain_segment 的最后一个参数) = 基础 + 300 × 10%
		var want_dmg: int = int(ES.CHAIN_DMG[star_i]) + 30
		var bad_dmg: Array = []
		for it in ets._bolt_q:
			var args: Array = ((it as Dictionary)["fn"] as Callable).get_bound_arguments()
			if args.is_empty() or int(args[args.size() - 1]) != want_dmg:
				bad_dmg.append(args)
		_ok("① ★★%d 星每一跳伤害 = %d + 10%% × 攻击力 300 = %d" % [[1, 2, 3][star_i], int(ES.CHAIN_DMG[star_i]), want_dmg],
			queued > 0 and bad_dmg.is_empty(), str(bad_dmg.slice(0, 2)))

	# ── ② ★★每一跳都真的结算掉 ──────────────────────────────────
	_s._units.clear()
	ets._bolt_q.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c2)
	var foes: Array = []
	for k in range(8):
		var o: Dictionary = _mk(700.0 + 70.0 * k, 400.0 + (30.0 if k % 2 else -30.0), "right")
		foes.append(o)
		_s._units.append(o)
	_s._equip_sys._eq_chain_lightning(c2, 2)          # ★3: 15 跳, 8 个敌人 ⇒ 先各打一遍(优先没打过的), 再回头重复打
	var hp0: float = 0.0
	for o in foes:
		hp0 += float(o["hp"])
	var n_hops: int = ES.CHAIN_HOPS[2]
	## 推够 15 × 0.2 = 3.0 游戏秒(再留 1 秒余量)
	for _k in range(roundi((float(n_hops) * 0.2 + 1.0) / _s.SIM_DT)):
		_s._sim_step(_s.SIM_DT, false, false)
	var hurt := 0
	for o in foes:
		if float(o["hp"]) < 90000.0:
			hurt += 1
	_ok("② ★★★15 跳全部结算掉了 —— 被打中的敌人 %d 个(应 8 个: 跳数比敌人多, 每个都挨到)" % hurt, hurt == mini(n_hops, foes.size()),
		"若只有 1 个: 第 2 跳以后没落, 就是 tween 那条老病")
	_ok("② 队列已排空(没有漏结算的项)", ets._bolt_q.is_empty(),
		"剩 %d 项" % ets._bolt_q.size())

	# ── ③ 伤害口径: 魔法伤害(吃魔抗), 40/60/90 ───────────────────
	## ★不断言绝对数值 —— 携带者 id="basic" 走小龟·不屈(+20%), 那是产品本来的行为。
	##   判据落在**对该被动不敏感**的形状: 魔抗高的吃得少(⇒ 是魔法伤害不是真伤)。
	_s._units.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	var soft: Dictionary = _mk(700.0, 400.0, "right")
	soft["mr"] = 0.0
	var hard: Dictionary = _mk(760.0, 400.0, "right")
	hard["mr"] = 500.0
	_s._units.append(c3)
	_s._units.append(soft)
	_s._units.append(hard)
	var hs: float = float(soft["hp"])
	var hh: float = float(hard["hp"])
	_s._chain_segment(c3, c3["pos"], soft, 90)
	_s._chain_segment(c3, c3["pos"], hard, 90)
	var ds: float = hs - float(soft["hp"])
	var dh: float = hh - float(hard["hp"])
	_ok("③ ★分母: 两边都真的掉血了(软 %.0f / 硬 %.0f)" % [ds, dh], ds > 0.0 and dh > 0.0)
	_ok("③ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】不是真伤(软 %.0f vs 硬 %.0f)" % [ds, dh],
		dh < ds * 0.5)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 11:
		print("  [FAIL] ★断言只有 %d 条(<11) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 026 连锁闪电" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
