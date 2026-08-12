extends Node
## verify_shield_synergy.gd — 盾羁绊三条主动【怒气冲击波 / 反击 / 收殓】(用户 2026-08-03 定)
##
## ★盾是两个来源拼起来的: 怒气←类型原生 · 圣光/反击/收殓←学派圣甲议会。
##   圣光在 verify_synergy_live 里守着(它和潮涌/盛宴同一个节拍), 这里守另外三条。
##
## ★用户两处改动各有一条断言:
##   · 怒气按【伤害值】不按次数 ⇒ "挨 10 次 40 伤" 与 "挨 1 次 400 伤" 必须等价
##   · 怒气给【全队】不只携带者 ⇒ 不带盾的队友也会放冲击波
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new(); add_child(s)
	_scene = s
	await get_tree().process_frame; await get_tree().process_frame
	var SH := ["p2eq_018","p2eq_081","p2eq_082","p2eq_016","p2eq_021","p2eq_045","p2eq_014","p2eq_015","p2eq_017"]
	print("=== 盾羁绊: 怒气 / 反击 / 收殓 ===")

	# ── 怒气: 按伤害值攒, 满 400 放 ──
	var me := _mk("left", SH.slice(0, 3), 2000.0)
	var foe := _mk("right", [], 100000.0)
	_run(s, [me, _mk("left", SH.slice(3, 6)), _mk("left", SH.slice(6, 9)), foe])
	var tier: int = s._synergy.tier_for(me, "盾")
	_ok("★分母: 9 件盾 → 顶档(第3档)", tier == 3, "实得 %d" % tier)
	var hp0: float = float(foe["hp"])
	me["_shield_rage"] = 0.0
	for _i in range(10):
		me["shield"] = 0.0                         # ★每次清盾: 隔离掉顶档【反击】的那一发
		s._shield_syn._rage(me, 3, 40.0)           # ★直接调 _rage: on_damaged 会在冲击波之后再打一发【反击】
		                                           #   (冲击波刚给了盾 ⇒ 反击条件当场满足), 混进来就量不准
	var d_many: float = hp0 - float(foe["hp"])
	_ok("怒气: 累计挨 400(10×40) 放了一次冲击波", d_many > 0.0, "敌掉 %.0f" % d_many)
	foe["hp"] = 100000.0
	me["_shield_rage"] = 0.0
	me["shield"] = 0.0                             # ★清盾: 否则顶档【反击】也会打一发, 混进这次测量
	s._shield_syn._rage(me, 3, 400.0)              # 一次 400(同上, 绕开反击)
	var d_one: float = 100000.0 - float(foe["hp"])
	_ok("★怒气按【伤害值】不按次数: 挨1次400 == 挨10次40", absf(d_one - d_many) < 1.0,
		"一次 %.0f / 十次 %.0f" % [d_one, d_many])
	_ok("★冲击波伤害 = 自身maxHp/HP_MULT×8%% = %.0f" % (2000.0 / 3.0 * 0.08),
		absf(d_one - int(2000.0 / 3.0 * 0.08)) < 1.5, "实得 %.0f" % d_one)
	# ★2026-08-03 用户改: 护盾 = 【冲击波伤害的 20%】, 不再是"等量最大生命百分比"。
	#   原写法伤害除 HP_MULT、护盾不除 ⇒ 护盾是伤害的 3 倍, 而文案写"等量" —— 玩家看不出来。
	#   现在两者同源, 文案与实装天然一致。
	_ok("★冲击波护盾 = 伤害 × 20%% = %.0f" % (d_one * 0.2),
		absf(float(me["shield"]) - float(int(d_one)) * 0.2) < 1.0, "实得 %.0f" % float(me["shield"]))
	# 攒不满不放
	foe["hp"] = 100000.0; me["_shield_rage"] = 0.0; me["shield"] = 0.0
	s._shield_syn._rage(me, 3, 399.0)
	_ok("★对照: 攒到 399 不放(阈值是 400)", absf(100000.0 - float(foe["hp"])) < 0.5,
		"敌掉 %.0f" % (100000.0 - float(foe["hp"])))
	# 一次超大伤害放多次
	foe["hp"] = 100000.0; me["_shield_rage"] = 0.0; me["shield"] = 0.0
	s._shield_syn._rage(me, 3, 1200.0)
	_ok("★一次挨 1200 放三次(不是攒着等下次)",
		absf((100000.0 - float(foe["hp"])) - d_one * 3.0) < 3.0,
		"敌掉 %.0f (单次 %.0f)" % [100000.0 - float(foe["hp"]), d_one])

	# ── 怒气给全队(不只携带盾者) ──
	var noshield := _mk("left", [], 2000.0)
	_run(s, [me, noshield, _mk("left", SH.slice(3, 6)), _mk("left", SH.slice(6, 9)), foe])
	foe["hp"] = 100000.0; noshield["_shield_rage"] = 0.0; noshield["shield"] = 0.0
	s._shield_syn._rage(noshield, 3, 400.0)
	_ok("★★怒气给【全队】: 不带盾的队友也放冲击波(用户 2026-08-03 改)",
		100000.0 - float(foe["hp"]) > 0.0, "敌掉 %.0f" % (100000.0 - float(foe["hp"])))

	# ── ★on_damaged 走全路: 冲击波 + 反击在同一次调用里【都会发】 ──
	#   (上面几条为了量准, 都直接调 _rage 绕开了反击; 这条专门验完整路径。)
	foe["hp"] = 100000.0; me["_shield_rage"] = 0.0; me["shield"] = 0.0
	s._shield_syn.on_damaged(me, foe, 400)
	var full: float = 100000.0 - float(foe["hp"])
	_ok("★完整路径: 一次 on_damaged(400) 只有冲击波(没装圣光护盾 ⇒ 无反击)",
		absf(full - d_one) < 1.5, "实得 %.0f (冲击波 %.0f)" % [full, d_one])

	# ── 反击: 有护盾才反, 顶档才有 ──
	# ★反击现在来自【圣光护盾装备】, 不是档位: 没装就没有(用户 2026-08-03 重定)
	#
	# ★★2026-08-10 反击改成【光弹飞到才出伤】(用户:「要光弹啊，弹命中了再出伤啊」)。
	#   伤害挂在 `_queue_shots` 的延后队列上, 调完 `_riposte` 那一帧敌人还没掉血 ——
	#   所以这里必须把队列**推完**再读血。不推的话两条都会读到 0:
	#   "有反击"那条假 FAIL, 而"不反击"那两条变成**假通过**(没飞到也是 0)。
	var _drain := func() -> void:
		s._ballistics._step_pending_shots(2.0)
	## ★★2026-08-12 语义改动(用户:「反击也是只要有圣光护盾就反击, 不一定要装备啊」):
	##   反击的条件从【装着 095】改成【圣光护盾值 > 0】—— 规格原文「圣光护盾存在时」
	##   说的是这份护盾在不在, 而不是这件装备在不在。收殓/9 档转来的圣盾值同样算。
	foe["hp"] = 100000.0
	me["shield"] = 500.0; me["_holyShieldVal"] = 0.0; me["_shield_rage"] = 0.0
	s._shield_syn._riposte(me, foe)
	_drain.call()
	_ok("★只有【普通护盾】、圣盾值为 0 → 不反击(分母)",
		absf(100000.0 - float(foe["hp"])) < 0.5, "敌掉 %.0f" % (100000.0 - float(foe["hp"])))
	## ★没装 095 但【圣盾值在】(收殓/9档转来的) ⇒ 照样反击
	foe["hp"] = 100000.0; me["shield"] = 500.0; me["_holyShieldVal"] = 120.0
	s._shield_syn._riposte(me, foe)
	_drain.call()
	_ok("★没装 095 但圣盾值在 ⇒ 照样反击(用户 2026-08-12 拍板)",
		(100000.0 - float(foe["hp"])) > 0.5, "敌掉 %.0f" % (100000.0 - float(foe["hp"])))
	me["equips"] = [{"id": "p2eq_095", "star": 1}]     # 装上圣光护盾
	foe["hp"] = 100000.0; me["shield"] = 500.0; me["_holyShieldVal"] = 500.0
	s._shield_syn._riposte(me, foe)
	## ★先抓一把"还没推队列时的血" —— 它必须还是满的,
	##   否则就是"光弹还没到伤害先出了", 那正是这次要防的毛病。
	var hp_before_flight: float = float(foe["hp"])
	_drain.call()
	var rip: float = 100000.0 - float(foe["hp"])
	_ok("★反击的伤害**不在发弹那一帧**出(光弹要飞到才结算)",
		absf(hp_before_flight - 100000.0) < 0.5, "发弹那一帧敌已掉 %.0f" % (100000.0 - hp_before_flight))
	_ok("反击: 装了圣光护盾且有护盾 → 2 点真伤(固定, 不随件数放大)",
		absf(rip - 2.0) < 0.5, "实得 %.0f" % rip)
	## ★清盾要连【圣盾值】一起清 —— 反击现在看的是它, 只清 shield 会留着上一条用例的残值
	foe["hp"] = 100000.0; me["shield"] = 0.0; me["_holyShieldVal"] = 0.0
	s._shield_syn._riposte(me, foe)
	_drain.call()
	_ok("★对照: 装了但圣盾值为 0 → 不反击(「圣光护盾存在时」)",
		absf(100000.0 - float(foe["hp"])) < 0.5, "敌掉 %.0f" % (100000.0 - float(foe["hp"])))
	# 圣光护盾装备的周期护盾
	me["shield"] = 0.0
	s._shield_syn._t_holy = 0.0
	s._shield_syn.tick(3.1)
	_ok("圣光护盾装备: 每 3 秒生成 55 点(顶档 +20%% ⇒ 66)",
		absf(float(me["shield"]) - 66.0) < 1.0, "实得 %.0f" % float(me["shield"]))
	# ★把盾装回去 —— 下面的【收殓】要最近的携带盾者, 清空了就找不到人。
	me["equips"] = [{"id": "p2eq_018", "star": 1}, {"id": "p2eq_081", "star": 1}, {"id": "p2eq_082", "star": 1}]

	# ── 收殓: 敌人死 → 最近的携带盾者得盾 ──
	me["shield"] = 0.0
	var dead := _mk("right", [], 3000.0)
	dead["pos"] = Vector2(10, 0)
	me["pos"] = Vector2(20, 0)
	_run(s, [me, _mk("left", SH.slice(3, 6)), _mk("left", SH.slice(6, 9)), dead])
	me["shield"] = 0.0
	s._shield_syn.on_enemy_died(dead)
	## ★★2026-08-12 重做: 护盾不再当场到账 —— 尸体上的金球要【高抛物线飞】到收殓者身上,
	##   落地那一刻才给(用户:「转移到自己身上后再获得护盾」)。判据随之分两段。
	_ok("收殓 ★金球飞行途中【还没到账】(效果时刻 = 演出到达时刻)",
		absf(float(me["shield"])) < 0.5, "实得 %.0f" % float(me["shield"]))
	var steps: int = int(ceil((SynergyVfx.REAP_FLY_SEC + 0.08) / 0.02))
	for _i in range(steps):
		s._ballistics._step_pending_shots(0.02)
	_ok("收殓: 敌人(3000血)阵亡 → 金球落地后最近携带盾者 +900 护盾(30%)",
		absf(float(me["shield"]) - 900.0) < 1.0, "实得 %.0f" % float(me["shield"]))
	## ★★金球的【高抛物线飞行】—— 量真实节点(金球与圣盾罩子同为金色, 像素法分不开)。
	##   用户 2026-08-12:「我要球从尸体飞到单位上, 是高有个抛物线的飞」
	var sv = s._vfx._syn
	var corpse := Vector2(200.0, 400.0)
	var taker2: Dictionary = {"pos": Vector2(700.0, 400.0), "alive": true}
	var orb = sv.reap_orb(corpse, taker2)
	_ok("收殓 ★金球节点真的挂进 _world",
		orb != null and s._world.is_ancestor_of(orb), str(orb))
	if orb != null:
		var y0: float = orb.position.y
		var ys: Array = [y0]
		var xs: Array = [orb.position.x]
		for _k in range(5):
			sv.tick_reaps(SynergyVfx.REAP_FLY_SEC / 6.0)
			ys.append(orb.position.y)
			xs.append(orb.position.x)
		var peak: float = ys[0]
		var peak_i := 0
		for i in range(ys.size()):
			if float(ys[i]) > peak:
				peak = float(ys[i])
				peak_i = i
		_ok("收殓 ★★是【抛物线】: 高度 %.2f→峰值 %.2f(第 %d 段)→回落, 峰在中段"
				% [y0, peak, peak_i], peak > y0 + 1.0 and peak_i >= 1 and peak_i <= 4, str(ys))
		_ok("收殓 ★弧【高】: 峰值比起点高 %.2f 米(REAP_HOP_H=%.1f)" % [peak - y0, SynergyVfx.REAP_HOP_H],
			peak - y0 > SynergyVfx.REAP_HOP_H * 0.6, "")
		_ok("收殓 ★是【从尸体飞到人】不是原地跳: 水平位移 %.2f m > 0"
				% absf(float(xs[xs.size() - 1]) - float(xs[0])),
			absf(float(xs[xs.size() - 1]) - float(xs[0])) > 1.0, str(xs))
	_ok("收殓 ★同步触发证据: 收殓者身上记了 1 次", int(me.get("_reap_taken_n", 0)) == 1,
		"n=%d" % int(me.get("_reap_taken_n", 0)))
	# 只给敌人的对面, 不给同阵营
	var ally_dead := _mk("left", [], 3000.0)
	me["shield"] = 0.0
	s._shield_syn.on_enemy_died(ally_dead)
	## ★对照组也要把定时器推完 —— 否则"没盾"可能只是"还在飞"(假对照)
	for _j in range(int(ceil((SynergyVfx.REAP_FLY_SEC + 0.08) / 0.02))):
		s._ballistics._step_pending_shots(0.02)
	_ok("★对照: 【我方】单位阵亡不给我方盾(收殓只吃敌人的死)",
		absf(float(me["shield"])) < 0.5, "实得 %.0f" % float(me["shield"]))

	s._units.clear(); s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	# ── 9档【圣光·强化】: 盾类装备给的护盾/治疗, 额外 20% 转圣光护盾 ──
	me["shield"] = 0.0
	s._cur_eq_item = "p2eq_016"          # 铁壁盾(盾类)
	s._damage._grant_shield(me, 100.0)
	_ok("9档【圣光·强化】: 盾类装备给 100 护盾 → 实得 120(额外 20%%)",
		absf(float(me["shield"]) - 120.0) < 1.0, "实得 %.0f" % float(me["shield"]))
	me["shield"] = 0.0
	s._cur_eq_item = "p2eq_001"          # 锈蚀短剑(剑类)
	s._damage._grant_shield(me, 100.0)
	_ok("★对照: 【非盾类】装备给的护盾不转化(100 就是 100)",
		absf(float(me["shield"]) - 100.0) < 1.0, "实得 %.0f" % float(me["shield"]))
	me["shield"] = 0.0
	s._cur_eq_item = ""                  # 非装备来源(技能/羁绊)
	s._damage._grant_shield(me, 100.0)
	_ok("★对照: 【非装备来源】的护盾不转化 —— _cur_eq_item 用完必须清",
		absf(float(me["shield"]) - 100.0) < 1.0, "实得 %.0f" % float(me["shield"]))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 盾羁绊三条主动" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run(s, units: Array) -> void:
	s._units.clear(); s._units.append_array(units)
	s._synergy._by_side = {"left": {}, "right": {}}
	s._synergy.apply_all()

## ★用真的 _make_unit 造单位, 不手写字典。
## 手写的第一版漏了 untargetable_until / dmg_dealt 等字段 ⇒ _nearest_enemy 里直接 SCRIPT ERROR,
## 而【断言还是绿的】(冲击波打不出去 → "敌掉 0" 也满足"> 0"以外的某些条件)。
## 同 verify_equip_batch_20260730d 的做法: 走真构造再把要控的字段覆盖掉。
var _scene
func _mk(side: String, ids: Array, hp: float = 2000.0) -> Dictionary:
	var c: Vector2 = _scene.ARENA.position + _scene.ARENA.size * 0.5
	var off := Vector2(-200.0, 0.0) if side == "left" else Vector2(200.0, 0.0)
	# ★★不能用 "basic" —— 小龟有【不屈】被动: 对任何目标按稀有度增伤(C 档 +20%),
	#   于是冲击波 53 打出去变成 64, 断言当场红而代码一点毛病没有。
	#   探针实测才看出来(battle_damage.gd:77 `if src.get("id") == "basic"`)。
	#   换成 green(无此类被动)。⇒ 教训: 合成单位挑 id 时要确认那只龟【没有全局改伤害的被动】。
	var u: Dictionary = _scene._spawn._make_unit("green", side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0; u["base_def"] = 0.0
	u["mr"] = 0.0; u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	var e: Array = []
	for i in ids: e.append({"id": str(i), "star": 1})
	u["equips"] = e
	u["eq_state"] = {}
	return u
