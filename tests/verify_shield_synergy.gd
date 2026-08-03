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
	foe["hp"] = 100000.0
	me["shield"] = 500.0; me["_shield_rage"] = 0.0
	s._shield_syn._riposte(me, foe)
	_ok("★没装圣光护盾装备 → 就算有护盾也【不反击】",
		absf(100000.0 - float(foe["hp"])) < 0.5, "敌掉 %.0f" % (100000.0 - float(foe["hp"])))
	me["equips"] = [{"id": "p2eq_095", "star": 1}]     # 装上圣光护盾
	foe["hp"] = 100000.0; me["shield"] = 500.0
	s._shield_syn._riposte(me, foe)
	var rip: float = 100000.0 - float(foe["hp"])
	_ok("反击: 装了圣光护盾且有护盾 → 2 点真伤(固定, 不随件数放大)",
		absf(rip - 2.0) < 0.5, "实得 %.0f" % rip)
	foe["hp"] = 100000.0; me["shield"] = 0.0
	s._shield_syn._riposte(me, foe)
	_ok("★对照: 装了但当前没有护盾值 → 不反击(「圣光护盾存在时」)",
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
	_ok("收殓: 敌人(3000血)阵亡 → 最近携带盾者 +900 护盾(30%)",
		absf(float(me["shield"]) - 900.0) < 1.0, "实得 %.0f" % float(me["shield"]))
	# 只给敌人的对面, 不给同阵营
	var ally_dead := _mk("left", [], 3000.0)
	me["shield"] = 0.0
	s._shield_syn.on_enemy_died(ally_dead)
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
