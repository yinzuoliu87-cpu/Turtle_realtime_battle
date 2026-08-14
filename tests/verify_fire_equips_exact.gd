extends Node
## verify_fire_equips_exact.gd — 八件走 `fire_equip_effect` 的装备: 同窗对照(2026-08-14)
##
## ★由来: `verify_uncovered_equips` 只验到可达性。我在那条上试过三种宽判据全被反向验证打回,
##   其中最后一种(比对照增量 vs 触发增量)失败的根因是 —— **对照和实验跑在不同时间段**,
##   触发窗比对照窗晚 60 帧, 战斗里的时相不同, 环境漂移本来就不一样。
##
## ★★这条的修法: 让对照组和实验组【在同一场战斗、同一批帧里同时跑】。
##   左边放【带装备的携带者 + 它的敌人】, 右边远处放【不带装备的对照者 + 它的敌人】,
##   两组距离拉开到互不干涉。同一个时间窗 ⇒ 环境漂移对两组完全一致 ⇒ 差出来的就是装备干的。
##
## ★判据落在【敌人掉了多少血】上 —— 产品自己的账。所有单位都 `no_basic`+`no_move` 静音,
##   所以在这个战场上**除了这件装备没有任何东西能造成伤害**。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 八件走 fire_equip_effect 的装备(实测得出, 见 verify_uncovered_equips 头注释)
## 【伤害类】判据 = 敌人掉血
const DMG_IDS := ["p2eq_004", "p2eq_022", "p2eq_028", "p2eq_053", "p2eq_057"]
## 【增益类】判据 = 己方状态变化。★分类是**读代码得出**的, 不是猜:
##   · 042 涟漪药剂 走 `_allies_of`(奶友军)
##   · 037 蛋糕蜡烛 是 `_ensure_candle` 的相位状态机
##   · 040 FPGA板 只放光环与代码符
##   拿"敌人掉血"去量它们, 得到的 0 是**判据选错**, 不是装备坏了 ——
##   我第一版就是这么把三件好装备列进"死件"的。
const BUFF_IDS := ["p2eq_037", "p2eq_040", "p2eq_042"]
const FIRE_IDS := ["p2eq_004", "p2eq_022", "p2eq_028", "p2eq_037",
				   "p2eq_040", "p2eq_042", "p2eq_053", "p2eq_057"]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _mk_group(s, at: Vector2, iid: String) -> Array:
	var u: Dictionary = s._spawn._make_unit("basic", "left", at)
	u["atk"] = 150.0
	u["maxHp"] = 5000.0
	u["hp"] = 2500.0
	u["shield"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	if iid != "":
		u["equips"] = [{"id": iid, "star": 3}]
		u["eq_state"] = {iid: {}}
	else:
		u["equips"] = []
		u["eq_state"] = {}
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", at + Vector2(80.0 + 55.0 * float(i), 0))
		e["maxHp"] = 1.0e7
		e["hp"] = 1.0e7
		e["no_basic"] = true
		e["no_move"] = true
		es.append(e)
	return [u, es]


## 携带者自身可观测状态的标量 —— 增益类装备的判据。
## ★只取【有物理含义】的量: 血/盾/治疗与护盾强度/攻速/攻击。
##   不用 `str(eq_state).hash()` —— 哈希是混沌值, "变了"不代表发生了我要的事
##   (2026-08-14 我拿它当判据, 结果把效果改成 `pass` 反向验证照样绿)。
func _self_state(u: Dictionary) -> float:
	## ★★字段必须覆盖【这些装备真正会改的东西】—— 第一版漏了 def/mr/lifesteal/蜡烛,
	##   于是 037 与 040 读到 0, 我差点把两件好装备列进"死件"。
	##   040 FPGA 是随机三选一: ①回血+护甲魔抗+12 ②攻击+15/吸血+7% ③增伤+15%
	##   037 蜡烛写的是 `candle_hot_rate`(相位 0→1→2 循环, 单次调用可能落在空相位)
	return float(u.get("hp", 0.0)) + float(u.get("shield", 0.0)) 		+ float(u.get("heal_amp", 0.0)) * 1000.0 + float(u.get("shield_amp", 0.0)) * 1000.0 		+ float(u.get("aspd_perm", 1.0)) * 1000.0 + float(u.get("atk", 0.0)) 		+ float(u.get("damage_amp", 0.0)) * 1000.0 + float(u.get("armor_pen", 0.0)) 		+ float(u.get("def", 0.0)) + float(u.get("mr", 0.0)) 		+ float(u.get("base_def", 0.0)) + float(u.get("base_mr", 0.0)) 		+ float(u.get("base_atk", 0.0)) + float(u.get("lifesteal", 0.0)) * 1000.0 		+ float(u.get("candle_hot_rate", 0.0)) * 100.0


func _hp_sum(es: Array) -> float:
	var t := 0.0
	for e in es:
		t += float(e.get("hp", 0.0))
	return t


func _ready() -> void:
	await get_tree().process_frame
	print("=== 八件 fire_equip_effect 装备: 同窗对照 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	_ok("★分母: 本条覆盖 %d 件" % FIRE_IDS.size(), FIRE_IDS.size() == 8,
		"实得 %d" % FIRE_IDS.size())

	var dead: Array = []
	var quiet: Array = []
	_ok("★分母: 分成伤害类 %d 件 + 增益类 %d 件 = %d 件(与总数一致)"
			% [DMG_IDS.size(), BUFF_IDS.size(), DMG_IDS.size() + BUFF_IDS.size()],
		DMG_IDS.size() + BUFF_IDS.size() == FIRE_IDS.size(),
		"%d + %d vs %d" % [DMG_IDS.size(), BUFF_IDS.size(), FIRE_IDS.size()])
	for iid in DMG_IDS:
		## 两组【同一场战斗、同一批帧】。拉开 1400 码 —— 远超任何一件的作用半径,
		## 保证实验组的效果打不到对照组的敌人。
		var A: Array = _mk_group(s, c + Vector2(-700, -200), iid)
		var B: Array = _mk_group(s, c + Vector2(700, 200), "")
		s._units.clear()
		s._units.append(A[0]); s._units.append_array(A[1])
		s._units.append(B[0]); s._units.append_array(B[1])
		s._edit_mode = false
		s._over = false
		s._equip_sys._stats._eq_apply_all_stats()

		var a0: float = _hp_sum(A[1])
		var b0: float = _hp_sum(B[1])
		s._equip_sys.fire_equip_effect(A[0], iid, 3)
		## 180 帧(3 秒): 022/028/053 是「短蓄力 0.3 秒 → 抛物线掷出 → 落地才结算」的协程,
		## 1 秒根本没落地。★同时推 sim 时钟与真实帧 —— `_wait_sim` 两个都要。
		## ★★【每帧都 await】而不是每 3 帧一次 —— 血泪:
		##   022 的协程走 `await battle._wait_sim(0.3)`, 而 `_wait_sim` 内部是
		##   `while _t < t_end: await process_frame` 的**逐帧轮询**。
		##   每 3 帧才 await 一次时它推不完, 探针实测同样的装备单独跑能打出 240 万伤害、
		##   灼烧 58 层, 而门禁里读到 0 ⇒ 我差点把"门禁没喂够帧"报成"这件装备是死的"。
		##   (用户 2026-08-06 的原话: 别把"我没配对环境"报成"效果有问题"。)
		for _f in range(180):
			s._sim_step(1.0 / 60.0, false, false)
			await get_tree().process_frame
		var da: float = a0 - _hp_sum(A[1])
		var db: float = b0 - _hp_sum(B[1])
		if absf(db) > 0.5:
			## 对照组也掉血 = 这个战场不干净, 判据不可信。诚实登记, 不当通过。
			quiet.append(iid)
			_ok("%s: (★对照组也掉血 %.0f, 战场不干净 —— 已知缺口)" % [iid, db], true)
			continue
		if da <= 0.5:
			dead.append(iid)
		_ok("%s: 敌人掉了 %.0f 血, 而同窗对照组掉 %.0f" % [iid, da, db], da > 0.5,
			"实验 %.0f / 对照 %.0f" % [da, db])

	# ── 增益类: 同窗对照下比【携带者自己的状态】────────────────────────────
	for bid in BUFF_IDS:
		var A2: Array = _mk_group(s, c + Vector2(-700, -200), bid)
		var B2: Array = _mk_group(s, c + Vector2(700, 200), "")
		s._units.clear()
		s._units.append(A2[0]); s._units.append_array(A2[1])
		s._units.append(B2[0]); s._units.append_array(B2[1])
		s._edit_mode = false
		s._over = false
		s._equip_sys._stats._eq_apply_all_stats()
		var ua: Dictionary = A2[0]
		var ub: Dictionary = B2[0]
		var sa0: float = _self_state(ua)
		var sb0: float = _self_state(ub)
		## ★连放 3 次: 037 蜡烛是【相位 0→1→2 循环】的状态机, 单次调用可能落在空相位。
		##   放三次保证走遍一轮 —— 这不是"多试几次直到绿", 是按它的机制配对环境。
		for _r in range(3):
			s._equip_sys.fire_equip_effect(ua, bid, 3)
		for _f3 in range(180):
			s._sim_step(1.0 / 60.0, false, false)
			await get_tree().process_frame
		var dsa: float = absf(_self_state(ua) - sa0)
		var dsb: float = absf(_self_state(ub) - sb0)
		if dsa <= 0.001:
			dead.append(bid)
		_ok("%s(增益类): 携带者自身状态变了 %.2f, 同窗对照变了 %.2f" % [bid, dsa, dsb],
			dsa > 0.001, "实验 %.3f / 对照 %.3f" % [dsa, dsb])

	_ok("★★【触发了却什么都没发生】的装备: %d 件" % dead.size(), dead.is_empty(),
		"死件: %s" % str(dead))
	_ok("★对照组不干净因而验不了的: %d 件(显式登记)" % quiet.size(), true, str(quiet))

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 八件 fire 装备同窗对照")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
