extends Node
## verify_equip_batch_20260801.gd — 用户 2026-08-01 装备批次(12 编号 / 13 条)逐条焊死
##
## 方案书: docs/plans/20260801-装备批次13条.md (含验收清单与已知风险)
##
## ★本文件的规矩(都是这个项目吃过亏才立的):
##   · 全部用【干净合成单位】, 不用随机 spawn 的敌 —— 随机敌带盾/flat_dr/未播种 RNG 会让
##     精确数值在 CI 上偶发红(memory: fb-ci-vs-local-divergence)。
##   · 合成单位坐标放在 ARENA 【内】—— 放外面会被钳到同一点, 表现为"帧数少就红帧数多就绿"。
##   · 需求字面值直接写在断言里, 【不引用被测常量】—— 引用常量就是拿代码跟它自己比, 永远绿。
##   · 不依赖任何演出 tween 跑完(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_batch_20260801.tscn

const VC := preload("res://scripts/systems/visual_constants.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/gamedata/equip_stats.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位: 放 ARENA 中心附近, 清掉一切会干扰精确数值的减伤/护盾。
func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp; u["hp"] = hp
	u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["def"] = 0.0; u["mr"] = 0.0; u["base_def"] = 0.0; u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 装备批次 2026-08-01 (13 条) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t1_skeleton()
	_t2_necklace()
	_t3_hotspring()
	_t4_earring()
	# ★★必须 await —— _t5 里有 await(等死亡淡出那几帧)。不 await 的话它一让出,
	#   _ready 就直接跑到末尾打总结, 后面的断言全被甩掉且【不报错】:
	#   表现是断言总数悄悄从 110 掉到 97、"ALL PASS" 照打。这种缺口比 FAIL 危险。
	await _t5_hookbomb()
	_t5_hookbomb_numcolor()
	_t6_sniper()
	_t7_laser()
	_t89_carry()
	_t10_crystal()
	_t11a_hammer()
	_t11b_sharepool()
	_t12_anchor()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装备批次13条" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 唤灵骨符 032: 骷髅 血16/31/55 攻3/5/8 双抗0 受伤恒为1 存活13/17/23秒
# ─────────────────────────────────────────────────────────────
func _t1_skeleton() -> void:
	print("── ① 唤灵骨符 · 亡灵骷髅 ──")
	var want_hp := [16.0, 31.0, 55.0]
	var want_atk := [3.0, 5.0, 8.0]
	var want_life := [13.0, 17.0, 23.0]
	var made := 0
	for si in range(3):
		var owner: Dictionary = _mk("basic", "left", Vector2(-120.0 + 30.0 * float(si), -80.0))
		var before: int = _s._units.size()
		_s._equip_sys._eq_summon_skeleton(owner, si)
		if _s._units.size() <= before:
			_ok("① si=%d 召出骷髅" % si, false, "单位数没变 = 没召出来")
			continue
		var sk: Dictionary = _s._units[_s._units.size() - 1]
		made += 1
		_ok("① si=%d 骷髅最大生命 = %.0f (需求字面值)" % [si, want_hp[si]],
			absf(float(sk["maxHp"]) - want_hp[si]) < 0.5, "实际 %.1f" % float(sk["maxHp"]))
		_ok("① si=%d 骷髅攻击力 = %.0f" % [si, want_atk[si]],
			absf(float(sk.get("atk", 0.0)) - want_atk[si]) < 0.5, "实际 %.1f" % float(sk.get("atk", 0.0)))
		_ok("① si=%d 骷髅双抗 = 0(不再靠 20000 双抗免伤)" % si,
			absf(float(sk["def"])) < 0.01 and absf(float(sk["mr"])) < 0.01,
			"def=%.0f mr=%.0f" % [float(sk["def"]), float(sk["mr"])])
		_ok("① si=%d 存活时长 = %.0f 秒" % [si, want_life[si]],
			absf(float(sk.get("summon_life", 0.0)) - want_life[si]) < 0.01,
			"实际 %.1f" % float(sk.get("summon_life", 0.0)))
	_ok("① ★分母: 三个星级都真的召出了骷髅", made == 3, "made=%d/3" % made)

	# ★受伤恒为 1 —— 两条伤害路径【各验一次】(CLAUDE.md §3.3: 只改一条会有只在某类伤害下出现的怪象)
	var ow: Dictionary = _mk("basic", "left", Vector2(-200.0, 60.0))
	var b2: int = _s._units.size()
	_s._equip_sys._eq_summon_skeleton(ow, 2)
	if _s._units.size() > b2:
		var sk2: Dictionary = _s._units[_s._units.size() - 1]
		var atk: Dictionary = _mk("basic", "right", Vector2(200.0, 60.0))
		# 路径 A: _apply_damage_from (普攻/技能)
		var h0: float = float(sk2["hp"])
		_s._damage._apply_damage_from(atk, sk2, 99999, Color.WHITE, 0.0, false, false)
		var d_a: float = h0 - float(sk2["hp"])
		_ok("① ★路径A _apply_damage_from 打 99999 → 只掉 1 点",
			absf(d_a - 1.0) < 0.01, "实掉 %.2f" % d_a)
		# 路径 B: _apply_damage (DoT / 真伤) —— bucket="tru" 即真实伤害
		var h1: float = float(sk2["hp"])
		_s._damage._apply_damage(sk2, 99999, Color.WHITE, atk, "tru")
		var d_b: float = h1 - float(sk2["hp"])
		_ok("① ★路径B _apply_damage 真伤 99999 → 只掉 1 点(用户点名「包括真实伤害」)",
			absf(d_b - 1.0) < 0.01, "实掉 %.2f" % d_b)
		# ★反向对照(分母): 同样的两发打在【没有这个 flag 的普通单位】上必须是巨伤,
		#   否则"只掉1"可能是伤害管线整个没工作, 而不是免伤生效。
		var norm: Dictionary = _mk("basic", "right", Vector2(240.0, 120.0), 500000.0)
		var nh: float = float(norm["hp"])
		_s._damage._apply_damage_from(atk, norm, 99999, Color.WHITE, 0.0, false, false)
		_ok("① ★分母: 普通单位吃同一发 → 掉血远大于 1(证明测的是免伤不是空管线)",
			(nh - float(norm["hp"])) > 100.0, "普通单位掉 %.0f" % (nh - float(norm["hp"])))
	# 爆炸口径不动: 用户「原样伤害」= 沿用现有 boom_pct_true(目标自身%最大生命真伤)
	var ow3: Dictionary = _mk("basic", "left", Vector2(-260.0, -140.0))
	var b3: int = _s._units.size()
	_s._equip_sys._eq_summon_skeleton(ow3, 1)
	if _s._units.size() > b3:
		var sk3: Dictionary = _s._units[_s._units.size() - 1]
		_ok("① 爆炸仍走 boom_pct_true(原样, 未改)",
			float(sk3.get("boom_pct_true", 0.0)) > 0.0,
			"boom_pct_true=%.2f" % float(sk3.get("boom_pct_true", 0.0)))


# ─────────────────────────────────────────────────────────────
# ② 深海项链 044: 6 秒内回复 20/40/80% 最大生命
# ─────────────────────────────────────────────────────────────
func _t2_necklace() -> void:
	print("── ② 深海项链 · 6 秒持续回复 ──")
	for si in range(3):
		var pct: float = [0.20, 0.40, 0.80][si]
		var u: Dictionary = _mk("basic", "left", Vector2(-80.0 + 20.0 * float(si), 140.0), 1000.0)
		u["equips"] = [{"id": "p2eq_044", "star": si + 1}]
		u["eq_state"] = {}
		u["hp50_fired"] = false
		u["hp"] = 400.0                       # <50% → 触发阈值
		u["eq_hot_until"] = 0.0; u["eq_hot_rate"] = 0.0
		var t0: float = _s._t
		var hp_before: float = float(u["hp"])
		_s._equip_sys._eq_check_hp_threshold(u)
		_ok("② si=%d 不再瞬回(触发瞬间血量不变)" % si,
			absf(float(u["hp"]) - hp_before) < 0.01, "hp %.0f→%.0f" % [hp_before, float(u["hp"])])
		_ok("② si=%d 回复窗口 = 6 秒(需求字面值)" % si,
			absf(float(u.get("eq_hot_until", 0.0)) - (t0 + 6.0)) < 0.05,
			"until-_t = %.2f" % (float(u.get("eq_hot_until", 0.0)) - t0))
		var want_rate: float = 1000.0 * pct / 6.0
		_ok("② si=%d 速率 = maxHp×%.0f%% / 6秒" % [si, pct * 100.0],
			absf(float(u.get("eq_hot_rate", 0.0)) - want_rate) < 0.5,
			"%.2f vs %.2f" % [float(u.get("eq_hot_rate", 0.0)), want_rate])
		# 总量 = 速率 × 时长 = 文案百分比
		_ok("② si=%d 总量 = %.0f%% maxHp" % [si, pct * 100.0],
			absf(float(u.get("eq_hot_rate", 0.0)) * 6.0 - 1000.0 * pct) < 1.0,
			"总量 %.0f" % (float(u.get("eq_hot_rate", 0.0)) * 6.0))


# ─────────────────────────────────────────────────────────────
# ③ 温泉蛋 036: 等级上限 3/4/5 + 携带者每秒回【定额 2/5/10 + 0.3/0.8/1.2%最大生命】
#    (2026-08-31 用户改的公式; 原为纯定额 5/7/10。本用例的合成单位 maxHp=1000,
#     所以 1★ 应回 2+3=5、2★ 5+8=13、3★ 10+12=22。★`heal_ps` 只存【定额那一半】——
#     百分比那半跟着当前 maxHp 走, 由 EquipTickSystem 在 tick 里现算, 不进 heal_ps。)
# ─────────────────────────────────────────────────────────────
func _t3_hotspring() -> void:
	print("── ③ 温泉蛋 · 等级上限与每秒回血 ──")
	for si in range(3):
		var u: Dictionary = _mk("basic", "left", Vector2(60.0 + 20.0 * float(si), -160.0), 1000.0)
		u["equips"] = [{"id": "p2eq_036", "star": si + 1}]
		u["eq_state"] = {}
		# 走真实入口: 整单位跑一遍属性管线(而不是自己拼 eq_state —— 那样测的是测试自己写的值)
		_s._equip_sys._stats._eq_apply_all_stats()
		var stt: Dictionary = u["eq_state"].get("p2eq_036", {})
		_ok("③ si=%d 等级上限 = %d (需求字面值 3/4/5)" % [si, [3, 4, 5][si]],
			int(stt.get("egg_cap", 0)) == [3, 4, 5][si], "egg_cap=%s" % str(stt.get("egg_cap", "缺")))
		_ok("③ si=%d heal_ps 存的是定额那一半 = %.0f (需求字面值 2/5/10)" % [si, [2.0, 5.0, 10.0][si]],
			absf(float(stt.get("heal_ps", 0.0)) - [2.0, 5.0, 10.0][si]) < 0.01,
			"heal_ps=%.1f" % float(stt.get("heal_ps", 0.0)))
		# 每秒回血真的回进去(走 tick, 不是只写字段)
		u["hp"] = 500.0
		_s._equip_tick_sys._tick_hotspring(u, 0.5)
		var mid: float = float(u["hp"])
		_ok("③ si=%d 不满 1 秒不回血" % si, absf(mid - 500.0) < 0.01, "hp=%.1f" % mid)
		_s._equip_tick_sys._tick_hotspring(u, 0.6)
		_s._damage._heal_flush(u)
		## 走 tick 量到的是【两半之和】: 定额 + 百分比×maxHp。
		## ★★maxHp 必须【现读】不能写死 1000 —— 单位装上 036 之后装备自带的生命加成
		##   已经把 maxHp 抬起来了(实测 1★1066.7 / 2★1125 / 3★1183.3, 随星级涨),
		##   写死 1000 会把这条判据钉在一个根本不存在的血量上(我第一版就是这么写的, 当场红)。
		##   系数 2/5/10 与 0.003/0.008/0.012 仍是硬编码的需求字面值 ⇒ 不是自证循环。
		## ★这条与上面那条【必须都在】—— 只留 heal_ps 那条的话, 百分比那半整个删掉也照样绿。
		var mhp: float = float(u.get("maxHp", 0.0))
		var want3: float = [2.0, 5.0, 10.0][si] + mhp * [0.003, 0.008, 0.012][si]
		_ok("③ si=%d 满 1 秒回 %.1f 点(定额+%.1f%%×%.0f生命)" % [si, want3, [0.3, 0.8, 1.2][si], mhp],
			mhp > 900.0 and absf(float(u["hp"]) - (500.0 + want3)) < 0.51,
			"hp=%.1f (期望 %.1f) maxHp=%.1f" % [float(u["hp"]), 500.0 + want3, mhp])
		# 等级上限真的拦得住: 灌爆孵化进度也不会超过 cap
		u["has_egg"] = true
		for _k in range(20):
			_s._equip_tick_sys._egg_add_progress(u, 100.0)
		var stt2: Dictionary = u["eq_state"].get("p2eq_036", {})
		_ok("③ si=%d 灌 2000 进度后等级停在上限 %d" % [si, [3, 4, 5][si]],
			int(stt2.get("egg_levels", 0)) == [3, 4, 5][si],
			"egg_levels=%d" % int(stt2.get("egg_levels", 0)))


# ─────────────────────────────────────────────────────────────
# ④ 珍珠耳环 045: 8 秒内回复 30/60/100% 最大生命
# ─────────────────────────────────────────────────────────────
func _t4_earring() -> void:
	print("── ④ 珍珠耳环 · 8 秒持续回复 ──")
	for si in range(3):
		var pct: float = [0.30, 0.60, 1.00][si]
		var u: Dictionary = _mk("basic", "left", Vector2(-40.0 + 20.0 * float(si), 190.0), 1000.0)
		u["equips"] = [{"id": "p2eq_045", "star": si + 1}]
		u["eq_state"] = {}
		u["hp50_fired"] = false
		u["hp"] = 400.0
		u["eq_hot_until"] = 0.0; u["eq_hot_rate"] = 0.0
		var t0: float = _s._t
		_s._equip_sys._eq_check_hp_threshold(u)
		_ok("④ si=%d 回复窗口 = 8 秒(需求字面值)" % si,
			absf(float(u.get("eq_hot_until", 0.0)) - (t0 + 8.0)) < 0.05,
			"until-_t = %.2f" % (float(u.get("eq_hot_until", 0.0)) - t0))
		_ok("④ si=%d 总量 = %.0f%% maxHp" % [si, pct * 100.0],
			absf(float(u.get("eq_hot_rate", 0.0)) * 8.0 - 1000.0 * pct) < 1.0,
			"总量 %.0f (期望 %.0f)" % [float(u.get("eq_hot_rate", 0.0)) * 8.0, 1000.0 * pct])


# ─────────────────────────────────────────────────────────────
# ⑤ 靶向器 055: 钩索炸弹(全新机制)
# ─────────────────────────────────────────────────────────────
func _t5_hookbomb() -> void:
	print("── ⑤ 靶向器 · 钩索炸弹 ──")
	var hb = _s._hookbomb_sys
	# ★携带者用 fortune 不用 basic: 小龟·不屈(_BASIC_RARITY_BONUS) 会给小龟造成的一切伤害 +20%,
	#   拿小龟当携带者去验"1% = 10 点"会量到 12 —— 探针实测 72 vs 60。这是真实规则, 不是 bug。
	var car: Dictionary = _mk("fortune", "left", Vector2(-300.0, 0.0), 2000.0)
	car["equips"] = [{"id": "p2eq_055", "star": 1}]
	car["eq_state"] = {}
	var e1: Dictionary = _mk("basic", "right", Vector2(60.0, 0.0), 1000.0)
	var e2: Dictionary = _mk("basic", "right", Vector2(300.0, 0.0), 1000.0)
	# 排除名单: 大师 / 龟蛋 / 免控
	var tr: Dictionary = _mk("basic", "right", Vector2(80.0, 40.0), 1000.0); tr["is_trainer"] = true
	var eg: Dictionary = _mk("basic", "right", Vector2(80.0, 80.0), 1000.0); eg["_isEgg"] = true
	var im: Dictionary = _mk("basic", "right", Vector2(80.0, 120.0), 1000.0); im["cc_immune_until"] = _s._t + 60.0
	_ok("⑤ ★排除训龟大师", not hb._hb_can_grab(tr))
	_ok("⑤ ★排除龟蛋", not hb._hb_can_grab(eg))
	_ok("⑤ ★排除免控单位(cc_immune_until 未过)", not hb._hb_can_grab(im))
	_ok("⑤ ★分母: 普通敌可被抓(证明上面三条不是「永远 false」)", hb._hb_can_grab(e1) and hb._hb_can_grab(e2))

	# 触发: 累计造成 400 伤害之前不挂弹, 之后挂 1 个(si=0)
	car["_st_dealt"] = 399
	_s._equip_tick_sys._tick_targeter(car, 0.1)
	_ok("⑤ 累计 399 伤害 → 不触发", float(e1.get("hookbomb_pct", 0.0)) <= 0.0 and float(e2.get("hookbomb_pct", 0.0)) <= 0.0)
	car["_st_dealt"] = 400
	_s._equip_tick_sys._tick_targeter(car, 0.1)
	var attached := 0
	for o in [e1, e2]:
		if float(o.get("hookbomb_pct", 0.0)) > 0.0: attached += 1
	_ok("⑤ ★累计 400 伤害 → 触发, 1★挂 1 个(最近的那个)", attached == 1, "挂了 %d 个" % attached)
	_ok("⑤ 挂在【最近】的敌人身上", float(e1.get("hookbomb_pct", 0.0)) > 0.0,
		"e1(近)=%.3f e2(远)=%.3f" % [float(e1.get("hookbomb_pct", 0.0)), float(e2.get("hookbomb_pct", 0.0))])
	_ok("⑤ 大师/龟蛋/免控身上没有被挂弹",
		float(tr.get("hookbomb_pct", 0.0)) <= 0.0 and float(eg.get("hookbomb_pct", 0.0)) <= 0.0 and float(im.get("hookbomb_pct", 0.0)) <= 0.0)

	# 每秒 3% 宿主 maxHp 物理伤害(1★)
	# ★2026-08-29 从 2% 改成 3%: 同一轮把这一段从"不吃护甲的定额"改成**真物理**
	#   (`_phys_after_armor`)。实测一场真实对局 387 次挨打的平均护甲倍率 0.6685
	#   ⇒ 0.02/0.6685 = 0.0299 ≈ 0.03, **平均强度不变**但从此护甲能挡它。
	#   口径见 docs/design/实时版-系统机制权威.md §7.5(铁律·没有例外)。
	e1["hp"] = 1000.0
	e1["def"] = 0.0                          # ★这一格先验"系数对不对" ⇒ 护甲清零隔离出纯系数
	_s._hookbomb_sys._hb_tick(e1, 0.5)
	_ok("⑤ 不满 1 秒不跳伤", absf(float(e1["hp"]) - 1000.0) < 0.01, "hp=%.1f" % float(e1["hp"]))
	_s._hookbomb_sys._hb_tick(e1, 0.6)
	_ok("⑤ ★满 1 秒·零护甲 → 掉 3% maxHp = 30 点",
		absf(1000.0 - float(e1["hp"]) - 30.0) < 1.01, "掉了 %.1f" % (1000.0 - float(e1["hp"])))
	## ★★这次改造的【重点】: 护甲要真的起作用。
	##   判据 = 同一颗炸弹、同一个宿主, **只把护甲拉上去**, 掉血必须变少,
	##   而且要落在护甲公式 `1 - def/(def+40)` 上(±8% 容量化取整)。
	##   只断言"系数是 3%"守不住 —— 撤掉 `_phys_after_armor` 那条照样全绿(那正是本轮修的病)。
	e1["hp"] = 1000.0
	e1["def"] = 40.0                         # 40 护甲 ⇒ 倍率 1-40/80 = 0.5, 应掉 15 点
	_s._hookbomb_sys._hb_tick(e1, 1.1)
	var _armored: float = 1000.0 - float(e1["hp"])
	_ok("⑤ ★★护甲真的起作用: 40 护甲(倍率 0.500) → 掉 30×0.5 = 15 点",
		absf(_armored - 15.0) / 15.0 < 0.08,
		"实掉 %.1f (零护甲时是 30) —— 若仍是 30 说明没走 _phys_after_armor" % _armored)
	e1["def"] = 0.0
	# ★★节奏常量也焊进来 —— 用户 2026-08-02 逐条定的, 不写门禁就会被下一次"顺手调一下"改掉
	_ok("⑤ ★抽搐 2.0 秒(用户指定「抖动得2秒钟」)",
		absf(float(_s._hookbomb_sys.CONVULSE_SEC) - 2.0) < 0.001, "CONVULSE_SEC=%.2f" % float(_s._hookbomb_sys.CONVULSE_SEC))
	_ok("⑤ ★缠住定身 1.1 秒(用户指定「定住的时间还要久点」)",
		absf(float(_s._hookbomb_sys.PULL_STUN) - 1.1) < 0.001, "PULL_STUN=%.2f" % float(_s._hookbomb_sys.PULL_STUN))
	# ★★"尸体全程在场"(用户 2026-08-02:「爆开的时候尸体也在那啊，拉回来聚在一块后尸体才消失」)。
	#   这条不能靠看截图判 —— 我上一轮就把【病毒巢】当成"尸体在场"了, 判错了自己的产出。
	#   ★走真入口: 用单位【自己的】立绘 + 真 _kill(那条独立的死亡淡出 modulate:a→0 后 hide()
	#   就是从 _kill 里来的)。自己 new 一个 Sprite3D 塞进 unit 是行不通的 —— 渲染层会把
	#   这个它不认识的孤儿立绘回收掉, 测出来的是脚手架的毛病不是产品的。
	var corpse: Dictionary = _mk("fortune", "right", Vector2(300.0, 60.0), 1000.0)   # ★用真实存在的龟 id, "green" 没有立绘
	_s._units.append(corpse)
	for _w0 in range(4):
		await get_tree().process_frame          # 等 spawn 把立绘建出来
	var csp = corpse.get("sprite", null)
	_ok("⑤ ★分母: 尸体用例真的拿到了单位自己的立绘", is_instance_valid(csp),
		"sprite=%s" % ("有效" if is_instance_valid(csp) else "无"))
	if is_instance_valid(csp):
		corpse["hp"] = 1.0
		_s._kill(corpse)                        # 真入口: 触发 _kill 里的死亡淡出
		_s._hookbomb_sys._convulse(corpse)      # 抽搐 CONVULSE_SEC=2.0 秒
		var cw := 0
		while cw < 200 and is_instance_valid(csp):
			await get_tree().process_frame      # 给死亡淡出足够时间去 hide()
			cw += 1
		var still: bool = is_instance_valid(csp) and (csp as Node3D).visible
		_ok("⑤ ★★抽搐期间尸体不被【_kill 的死亡淡出】收走(跑了 %d 帧)" % cw, still,
			"有效=%s visible=%s alpha=%.2f" % [str(is_instance_valid(csp)),
				str((csp as Node3D).visible) if is_instance_valid(csp) else "-",
				(csp as Sprite3D).modulate.a if is_instance_valid(csp) else -1.0])

	## ★2026-08-29 2/4/4% → 3/6/6%（真物理改造的 ×1.5 补偿, 见上面 _hb_tick 那段头注）。
	##   "平均强度不变"这条口径另有专门门禁 `verify_armor_compensation` 逐值对账。
	_ok("⑤ ★DoT 三档 = 3/6/6% maxHp",
		absf(float(_s._hookbomb_sys.BOMB_DPS_PCT[0]) - 0.03) < 0.0001
		and absf(float(_s._hookbomb_sys.BOMB_DPS_PCT[1]) - 0.06) < 0.0001
		and absf(float(_s._hookbomb_sys.BOMB_DPS_PCT[2]) - 0.06) < 0.0001,
		"%s" % str(_s._hookbomb_sys.BOMB_DPS_PCT))

	# 3★ 挂 2 个
	# ★★清场(2026-08-08 补): 本节原本**没有**清场, 而同一文件其它节都有 ——
	#   前面子测试造的敌人还在 `_s._units` 里, 会去抢靶向器的 **2 个名额**
	#   ⇒ f1/f2/f3 只挂得上 1 个。这就是路线图里记的那条"⑤ 偶发红·根因是测试隔离",
	#   之前判"偶发"没顺手改; 它今天又把全套门禁报成红了 ⇒ 补一行根治。
	#   ☆判据: 同一份产品代码早先全套绿、后来全套红, 四个 tag 全绿而 HEAD 全红
	#     ⇒ 不是回归, 是这条测试自己不稳。
	_s._units.clear()
	var car3: Dictionary = _mk("fortune", "left", Vector2(-320.0, 200.0), 2000.0)
	car3["equips"] = [{"id": "p2eq_055", "star": 3}]
	car3["eq_state"] = {}
	car3["_st_dealt"] = 400
	var f1: Dictionary = _mk("basic", "right", Vector2(40.0, 200.0), 1000.0)
	var f2: Dictionary = _mk("basic", "right", Vector2(80.0, 200.0), 1000.0)
	var f3: Dictionary = _mk("basic", "right", Vector2(320.0, 200.0), 1000.0)
	_s._equip_tick_sys._tick_targeter(car3, 0.1)
	var n3 := 0
	for o in [f1, f2, f3]:
		if float(o.get("hookbomb_pct", 0.0)) > 0.0: n3 += 1
	_ok("⑤ ★3★ 挂 2 个(需求 1/1/2)", n3 == 2, "挂了 %d 个" % n3)

	# 引爆: 宿主带弹死亡 → 全体敌被眩晕 + 拉向携带者 + 爆炸伤害
	var car2: Dictionary = _mk("fortune", "left", Vector2(-100.0, -220.0), 2000.0)
	var v1: Dictionary = _mk("basic", "right", Vector2(280.0, -220.0), 1000.0)
	var v2: Dictionary = _mk("basic", "right", Vector2(300.0, -180.0), 1000.0)
	var vtr: Dictionary = _mk("basic", "right", Vector2(320.0, -140.0), 1000.0); vtr["is_trainer"] = true
	var hp_v1: float = float(v1["hp"])
	var trhp: float = float(vtr["hp"])
	# ★震中 = 【宿主倒地处】, 不是携带者(用户 2026-08-01 指参考《虐杀原型2》人体炸弹:
	#   触须从被植入者体内爆出、把周围拖向【那个人】)。这里显式传一个远离携带者的震中来验。
	var epi: Vector2 = (v1["pos"] as Vector2) + Vector2(40.0, 0.0)
	var pos_before: Vector2 = v1["pos"]
	var got: int = _s._hookbomb_sys._hb_detonate(car2, 0, epi)
	_ok("⑤ ★分母: 引爆卷入了 N>0 个敌人", got > 0, "N=%d" % got)
	_ok("⑤ ★被眩晕(抓住→拖回整段都晕住)", float(v1.get("stun_until", 0.0)) > _s._t,
		"stun_until-_t=%.2f" % (float(v1.get("stun_until", 0.0)) - _s._t))
	# ★★"拉拽有速度, 不是瞬移"(用户原话:「瞬移并不是拉拽，拉拽是有速度的吗」)——
	#   判据: 引爆【当帧】位置不能变。瞬移实现会立刻改 pos, 一测就露。
	_ok("⑤ ★★不是瞬移: 引爆当帧位置没变(位移走各自的拉拽时长插值)",
		(v1["pos"] as Vector2).distance_to(pos_before) < 0.01,
		"当帧位移 %.2f 码" % (v1["pos"] as Vector2).distance_to(pos_before))
	# 聚拢落点: 纯几何, 围绕【震中】而不是携带者
	# ★落点必须【沿目标自己相对震中的方位】—— 不能按序号把人摆到圈上的固定槽位,
	#   那会让站在左边的敌人被"拽"到右边去(用户 2026-08-01 指出)。
	var west: Vector2 = epi + Vector2(-300.0, 0.0)      # 一个在震中【西侧】的目标
	var dw: Vector2 = _s._hookbomb_sys._hb_pull_dest_at(epi, west)
	_ok("⑤ ★聚拢距离 = PULL_GATHER_R", absf(dw.distance_to(epi) - float(_s._hookbomb_sys.PULL_GATHER_R)) < 0.5,
		"距震中 %.1f 码" % dw.distance_to(epi))
	_ok("⑤ ★★西侧的目标拖完仍在【西侧】(不是被摆到对面)", dw.x < epi.x - 1.0,
		"落点 x=%.0f 震中 x=%.0f" % [dw.x, epi.x])
	var north: Vector2 = epi + Vector2(0.0, -300.0)
	var dn: Vector2 = _s._hookbomb_sys._hb_pull_dest_at(epi, north)
	_ok("⑤ ★北侧的目标拖完仍在【北侧】", dn.y < epi.y - 1.0,
		"落点 y=%.0f 震中 y=%.0f" % [dn.y, epi.y])

	# ★★触须只拽近、不顶开: 已经比聚拢半径【更近】的目标, 落点必须原地不动。
	#   反例(我第一版): 无条件摆到半径 85 的圈上 → 站在 40 码的会被往外推 45 码。
	var near_p: Vector2 = epi + Vector2(40.0, 0.0)
	var dnear: Vector2 = _s._hookbomb_sys._hb_pull_dest_at(epi, near_p)
	_ok("⑤ ★★比聚拢半径更近的目标【原地不动】(不被触须往外顶)",
		dnear.distance_to(near_p) < 0.01 and dnear.distance_to(epi) <= 40.5,
		"原距 40 码 → 落点距震中 %.1f 码, 位移 %.2f 码" % [dnear.distance_to(epi), dnear.distance_to(near_p)])

	# ★★恒定收缩速度: 拉得远 ⇒ 拉得久。定长实现(所有人 0.42 秒)在这里会红。
	# ★取样点必须落在【未钳位区间】: PULL_DUR 夹在 [MIN,MAX] 之间, 贴脸的被抬到 MIN、
	#   极远的被压到 MAX —— 在钳位区里比速度, 比的是钳位不是恒速(200 码只需走 55 码,
	#   0.039 秒被抬到 0.08 ⇒ 688 码/秒, 门禁因此红过一次)。1000/400 码两点都在区间内。
	var far_p: Vector2 = epi + Vector2(1000.0, 0.0)
	var t_far: float = _s._hookbomb_sys._hb_pull_dur(far_p, _s._hookbomb_sys._hb_pull_dest_at(epi, far_p))
	var mid_p: Vector2 = epi + Vector2(400.0, 0.0)
	var t_mid: float = _s._hookbomb_sys._hb_pull_dur(mid_p, _s._hookbomb_sys._hb_pull_dest_at(epi, mid_p))
	_ok("⑤ ★★触须收缩【恒速】: 远的拉得久, 不是所有人同一个时长",
		t_far > t_mid + 0.05 and t_mid > 0.05,
		"1000 码 → %.2f 秒 / 400 码 → %.2f 秒" % [t_far, t_mid])
	# 钳位下限单独守: 贴脸的目标也不能一帧到位
	var hug: Vector2 = epi + Vector2(float(_s._hookbomb_sys.PULL_GATHER_R) + 8.0, 0.0)
	var t_hug: float = _s._hookbomb_sys._hb_pull_dur(hug, _s._hookbomb_sys._hb_pull_dest_at(epi, hug))
	_ok("⑤ ★贴脸拉拽也不瞬移(钳在 PULL_DUR_MIN)",
		t_hug >= float(_s._hookbomb_sys.PULL_DUR_MIN) - 0.001,
		"仅需走 8 码 → %.3f 秒 (下限 %.2f)" % [t_hug, float(_s._hookbomb_sys.PULL_DUR_MIN)])
	var v_far: float = far_p.distance_to(_s._hookbomb_sys._hb_pull_dest_at(epi, far_p)) / maxf(0.001, t_far)
	var v_mid: float = mid_p.distance_to(_s._hookbomb_sys._hb_pull_dest_at(epi, mid_p)) / maxf(0.001, t_mid)
	_ok("⑤ ★两条触须的实际收缩速度一致(±15%)",
		absf(v_far - v_mid) / maxf(1.0, v_mid) < 0.15,
		"远 %.0f 码/秒 vs 中 %.0f 码/秒" % [v_far, v_mid])
	# 爆炸: 直接调纯结算函数(不等演出 —— CLAUDE.md §3.5)
	var blast_list: Array = [v1]
	var nb: int = _s._hookbomb_sys._hb_blast(car2, blast_list, 0, epi)
	_ok("⑤ ★分母: 爆炸真的结算到了 %d 个目标" % nb, nb > 0)
	## ★2026-09-06 用户「病毒箭头爆炸伤害削弱为120/250/400+目标10%最大生命值」
	##   ⇒ 120 + 10%maxHp（原 2026-08-29 的 300 + 15%，那是真物理改造的 ×1.5 补偿值）。
	##   v1 的护甲在 _mk 里是 0, 所以这一格量的是纯系数; "护甲真的起作用"由上面 _hb_tick 那条与
	##   `verify_dmg_type_sentinel` ①d 各守一半。
	##   ★带护甲时实际到手约 ×0.6685（见 verify_armor_compensation ③b-1 打印的数）。
	_ok("⑤ ★爆炸伤害·零护甲 = 120 + 10%%maxHp = 220",
		absf(hp_v1 - float(v1["hp"]) - 220.0) < 1.51, "实掉 %.1f" % (hp_v1 - float(v1["hp"])))
	_ok("⑤ ★大师没被卷入(不掉血/不被拉)", absf(float(vtr["hp"]) - trhp) < 0.01,
		"大师掉了 %.1f" % (trhp - float(vtr["hp"])))
	# ★挂弹【不看免控】(用户:「挂炸弹不包括免控的因为这不是控制技能」), 但拉拽仍排除免控
	var immu: Dictionary = _mk("basic", "right", Vector2(300.0, -260.0), 1000.0)
	immu["cc_immune_until"] = _s._t + 60.0
	_ok("⑤ ★免控单位【可以】被挂弹(挂弹不是控制)", _s._hookbomb_sys._hb_can_bomb(immu))
	_ok("⑤ ★免控单位【不会】被拉/被晕(那才是控制)", not _s._hookbomb_sys._hb_can_grab(immu))



# ─────────────────────────────────────────────────────────────
# ⑥ 狙击长管 057: 每一枪都要蓄力(不只第一枪)
# ─────────────────────────────────────────────────────────────
	# ★★放在 _t5 【最末尾】: 它要等 2.2 秒墙钟, 而这 2.2 秒里 sim 一直在跑,
	#   夹在中间会把后面用例依赖的敌人状态搅乱(第一版就让「3★挂 2 个」变成挂了 1 个)。
	# 拉拽【绝不能给单位凭空创建 _home_pos】(用户 2026-08-02:「拉过来后位置卡住不动」)。
	#   RealtimeBattle3DScene 里有一段每帧无条件生效的归位:
	#     if u.has("_home_pos") ... pos = pos.move_toward(_home_pos, 220*delta)
	#   它只服务评审假人 —— 真实对局的单位没这个键, 那段是惰性的。一旦写进去,
	#   被拉的敌人就被永久钉在聚拢点上, 眩晕早过期也走不掉(探针实测: 2.5 秒只挪 0~2 码)。
	# ★不要 append 进 _units —— 多一只敌人会把后面「3★挂 2 个」那条用例的最近敌算错
	#   (第一版就这么污染了, 表现是"挂了 1 个"而不是 2 个)。_pull_over_time 不需要它在 _units 里。
	var nohome: Dictionary = _mk("green", "right", Vector2(360.0, -40.0), 1000.0)
	_ok("⑤ ★分母: 这只本来【没有】_home_pos", not nohome.has("_home_pos"))
	_s._hookbomb_sys._pull_over_time(nohome, (nohome["pos"] as Vector2) + Vector2(-120.0, 0.0), 0.3)
	# ★★等【墙钟】不等帧数(CLAUDE.md §3.5): 拉拽前有 PULL_STUN+0.08 ≈ 1.18 秒的绷紧等待,
	#   而无头下帧率极高 —— 我第一版等了 90 帧, 实际只过去 0.1 秒, 位移根本没开始,
	#   于是【把 bug 改回去门禁照样绿】(反向验证当场抓到这个假绿灯)。
	var _t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - _t0 < 2200:
		await get_tree().process_frame
	_ok("⑤ ★★拉拽后仍然没有 _home_pos(否则会被归位逻辑永久钉住)",
		not nohome.has("_home_pos"),
		"_home_pos=%s" % str(nohome.get("_home_pos", "无")))


func _t6_sniper() -> void:
	print("── ⑥ 狙击长管 · 每枪蓄力 ──")
	var u: Dictionary = _mk("basic", "left", Vector2(-360.0, -60.0), 2000.0)
	var e: Dictionary = _mk("basic", "right", Vector2(120.0, -60.0), 1000.0)
	_s._pending_shots.clear()
	_s._equip_sys._eq_sniper_windup(u, 0)
	_ok("⑥ 第一枪: 排了一发【延迟】射击而不是立刻开火", _s._pending_shots.size() == 1,
		"pending=%d" % _s._pending_shots.size())
	if _s._pending_shots.size() > 0:
		_ok("⑥ 蓄力时长 = 1.0 秒", absf(float(_s._pending_shots[0].get("delay", 0.0)) - 1.0) < 0.01,
			"delay=%.2f" % float(_s._pending_shots[0].get("delay", 0.0)))
	# ★核心: 击杀后【连狙】那一枪也必须是"排延迟", 不能立即开火
	_s._pending_shots.clear()
	e["hp"] = 1.0                                   # 一枪必死 → 触发连狙分支
	_s._equip_sys._eq_sniper(u, 0, 0)
	_ok("⑥ ★击杀触发的连狙也走蓄力(原来是立即开火)", _s._pending_shots.size() >= 1,
		"击杀后 pending=%d" % _s._pending_shots.size())
	if _s._pending_shots.size() > 0:
		_ok("⑥ ★连狙那一枪的蓄力也是 1.0 秒",
			absf(float(_s._pending_shots[0].get("delay", 0.0)) - 1.0) < 0.01,
			"delay=%.2f" % float(_s._pending_shots[0].get("delay", 0.0)))
	_ok("⑥ ★分母: 靶子确实被打死了(否则连狙分支根本没进)", not e.get("alive", true),
		"alive=%s hp=%.1f" % [str(e.get("alive", true)), float(e["hp"])])
	_s._pending_shots.clear()


# ─────────────────────────────────────────────────────────────
# ⑦ 激光长刃 010: 近战携带者半径 +250 码 (★远程侧也要验)
# ─────────────────────────────────────────────────────────────
func _t7_laser() -> void:
	print("── ⑦ 激光长刃 · 近战 +250 码 ──")
	var base_rng := 70.0
	var probe := base_rng + 180.0          # 落在 [基础, 基础+250) 之间 → 只有近战打得到
	# 近战携带者
	var m: Dictionary = _mk("basic", "left", Vector2(-380.0, 260.0), 2000.0)
	m["melee"] = true; m["atk_range"] = base_rng; m["atk"] = 50.0
	var mt: Dictionary = _mk("basic", "right", Vector2(-380.0 + probe, 260.0), 5000.0)
	var mh: float = float(mt["hp"])
	_s._equip_sys._eq_laser_sweep(m, mt, 0)
	var m_dealt: float = mh - float(mt["hp"])
	# 远程携带者: 同样的距离、同样的星级
	var r: Dictionary = _mk("basic", "left", Vector2(-380.0, 330.0), 2000.0)
	r["melee"] = false; r["atk_range"] = base_rng; r["atk"] = 50.0
	var rt: Dictionary = _mk("basic", "right", Vector2(-380.0 + probe, 330.0), 5000.0)
	var rh: float = float(rt["hp"])
	_s._equip_sys._eq_laser_sweep(r, rt, 0)
	var r_dealt: float = rh - float(rt["hp"])
	_ok("⑦ ★近战携带者: %.0f 码外(>射程70)的敌【打得到】" % probe, m_dealt > 0.0, "掉血 %.1f" % m_dealt)
	_ok("⑦ ★远程携带者: 同一距离【打不到】(证明不是所有人都 +250)", r_dealt <= 0.01, "掉血 %.1f" % r_dealt)


# ─────────────────────────────────────────────────────────────
# ⑧⑨ 竹制弓箭 039 / 哑铃 020 / 温泉蛋 036 层数跨路保留
# ─────────────────────────────────────────────────────────────
func _t89_carry() -> void:
	print("── ⑧⑨③ 跨路保留(换路不清零) ──")
	_s._units.clear()
	_s._eq_carry.clear()
	# 上路: 一只带竹弓+哑铃的龟, 打掉一些层数
	var a: Dictionary = _mk("basic", "left", Vector2(-100.0, 0.0), 1000.0)
	a["equips"] = [{"id": "p2eq_039", "star": 1}, {"id": "p2eq_020", "star": 1}]
	a["eq_state"] = {"p2eq_039": {"bamboo_charges": 2, "bamboo_hits": 1}, "p2eq_020": {"exercise": 3}}
	_s._dl_sys._dl_save_eq_carry()
	_ok("⑧⑨ ★分母: 存下了层数记录", _s._eq_carry.size() >= 2, "记录 %d 条" % _s._eq_carry.size())

	# 换路: 重建一只【全新的】同 id 同阵营单位(模拟 _dl_build_lane_field 的重建)
	_s._units.clear()
	var b: Dictionary = _mk("basic", "left", Vector2(-100.0, 0.0), 1000.0)
	b["equips"] = [{"id": "p2eq_039", "star": 1}, {"id": "p2eq_020", "star": 1}]
	b["eq_state"] = {}
	_ok("⑧⑨ ★确实换了对象(is_same(旧,新)==false) —— 否则测的是同一个字典, 永远绿",
		not is_same(a, b))
	var hp_fresh: float = float(b["maxHp"])
	_s._dl_sys._dl_restore_eq_carry()
	var s39: Dictionary = b["eq_state"].get("p2eq_039", {})
	var s20: Dictionary = b["eq_state"].get("p2eq_020", {})
	_ok("⑧ ★竹弓剩余充能跨路保留 = 2(不是重置回 6)",
		int(s39.get("bamboo_charges", -1)) == 2, "bamboo_charges=%s" % str(s39.get("bamboo_charges", "缺")))
	_ok("⑨ ★哑铃锻炼层跨路保留 = 3(不是重置回 0)",
		int(s20.get("exercise", -1)) == 3, "exercise=%s" % str(s20.get("exercise", "缺")))
	# 层数换来的永久最大生命也要跟过来: 竹弓消耗 6-2=4 层 ×50 + 哑铃 3 层 ×40 = 320
	var want_gain: float = 4.0 * 50.0 + 3.0 * 40.0
	_ok("⑧⑨ ★层数换来的最大生命一起跟过来 (+%.0f)" % want_gain,
		absf(float(b["maxHp"]) - hp_fresh - want_gain) < 1.0,
		"maxHp %.0f→%.0f (期望 +%.0f)" % [hp_fresh, float(b["maxHp"]), want_gain])

	# 温泉蛋等级跨路
	_s._units.clear(); _s._eq_carry.clear()
	var c: Dictionary = _mk("basic", "left", Vector2(-100.0, 0.0), 1000.0)
	c["equips"] = [{"id": "p2eq_036", "star": 1}]
	c["eq_state"] = {"p2eq_036": {"egg_levels": 2, "incub": 40.0, "egg_cap": 3}}
	_s._dl_sys._dl_save_eq_carry()
	_s._units.clear()
	var d: Dictionary = _mk("basic", "left", Vector2(-100.0, 0.0), 1000.0)
	d["equips"] = [{"id": "p2eq_036", "star": 1}]
	d["eq_state"] = {}
	var d_hp0: float = float(d["maxHp"])
	_s._dl_sys._dl_restore_eq_carry()
	var s36: Dictionary = d["eq_state"].get("p2eq_036", {})
	_ok("③ ★温泉蛋临时等级跨路保留 = 2", int(s36.get("egg_levels", -1)) == 2,
		"egg_levels=%s" % str(s36.get("egg_levels", "缺")))
	_ok("③ ★等级换来的属性也重放了(maxHp 涨了 2×5%%)",
		float(d["maxHp"]) > d_hp0 + 1.0, "maxHp %.0f→%.0f" % [d_hp0, float(d["maxHp"])])

	# "只有开新对局才重置" —— 载体挂在场景实例上, 新场景 = 空表
	_ok("③⑧⑨ ★载体是场景成员(新对局=新场景=空表, 不需另写清空)",
		_s.get("_eq_carry") is Dictionary)

	# ══ ★★接线断言 ══
	# 上面所有断言测的是【函数本身对不对】, 而那守不住【还有没有人调它】。
	# 反向验证实测(2026-08-01): 把 _dl_build_lane_field 里的 _dl_restore_eq_carry() 调用删掉,
	# 上面 10 条断言【照样全绿】—— 那就是一个被门禁保护着的死函数(memory: fb-verify-must-run-the-real-path)。
	# 所以这里直接查换路流程里的调用点。★先剥注释再找: 否则会命中我自己写的说明文字
	# (本次会话已经因为 contains() 命中自己的注释吃过两次亏)。
	var raw: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var code := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		code += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	_ok("⑧⑨ ★接线: _dl_build_lane_field 内真的调了 _dl_restore_eq_carry()",
		_fn_body(code, "func _dl_build_lane_field").contains("_dl_restore_eq_carry()"))
	_ok("⑧⑨ ★接线: _dl_clear_units 内真的调了 _dl_save_eq_carry() —— 清场前不存就没得还原",
		_fn_body(code, "func _dl_clear_units").contains("_dl_save_eq_carry()"))
	_s._units.clear(); _s._eq_carry.clear()


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


# ─────────────────────────────────────────────────────────────
# ⑩ 迷你水晶球B 031: 伤害 60/130/250, 偷魔抗固定 10%
# ─────────────────────────────────────────────────────────────
func _t10_crystal() -> void:
	print("── ⑩ 迷你水晶球B · 伤害与偷魔抗 ──")
	# ★伤害与偷魔抗必须用【两个目标】分开量: 验伤害要目标魔抗=0(否则管线打折,
	#   探针实测 mr=100 时 _resolve_dmg(60)=17), 验偷取又必须目标有魔抗。同一个目标办不到。
	# ★携带者用 fortune 不用 basic —— 小龟·不屈 +20% 会把精确数值抬高(探针: 72 vs 60)。
	for si in range(3):
		var u: Dictionary = _mk("fortune", "left", Vector2(-260.0, -300.0 + 40.0 * float(si)), 3000.0)
		u["base_mr"] = 0.0; u["mr"] = 0.0
		u["crit"] = 0.0; u["damage_amp"] = 0.0
		var want: float = [60.0, 130.0, 250.0][si]

		# (a) 伤害: 目标魔抗 0 → 掉血应精确等于需求字面值
		var oa: Dictionary = _mk("basic", "right", Vector2(-160.0, -300.0 + 40.0 * float(si)), 9000.0)
		var hp0: float = float(oa["hp"])
		_crystal_hit(u, oa, si)
		var dealt: float = hp0 - float(oa["hp"])
		_ok("⑩ si=%d 伤害 = %.0f (需求字面值 60/130/250)" % [si, want],
			absf(dealt - want) < 2.0, "实伤 %.1f" % dealt)
		_arr_drop(oa)

		# (b) 偷魔抗: 另一个目标带 100 魔抗 → 固定偷 10%(=10), 三个星级都一样
		var ob: Dictionary = _mk("basic", "right", Vector2(-120.0, -300.0 + 40.0 * float(si)), 9000.0)
		ob["base_mr"] = 100.0; ob["mr"] = 100.0
		var mr_me0: float = float(u["mr"])
		_crystal_hit(u, ob, si)
		_ok("⑩ si=%d ★偷魔抗固定 10%% (100 → 90), 不随星级" % si,
			absf(float(ob["mr"]) - 90.0) < 0.5, "目标魔抗 %.1f" % float(ob["mr"]))
		_ok("⑩ si=%d 携带者拿到偷来的 10 点魔抗" % si,
			absf(float(u["mr"]) - mr_me0 - 10.0) < 0.5,
			"携带者魔抗 %.1f → %.1f" % [mr_me0, float(u["mr"])])
		_arr_drop(ob)


## 让水晶扫描【只扫到指定目标】: 直接调单步结算, 扫描窗口跨过 0 弧度方向。
## ★不调 _eq_crystal_sweep: 那条建 tween 转一圈, 而"数值测试不该依赖 tween 跑完"(CLAUDE.md §3.5)。
func _crystal_hit(u: Dictionary, o: Dictionary, si: int) -> void:
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	_s._world.add_child(im)
	var ang: float = atan2(float(o["pos"].y) - float(u["pos"].y), float(o["pos"].x) - float(u["pos"].x))
	var state: Dictionary = {"prev": ang - 0.2}
	_s._crystal_sys._crystal_sweep_step(ang + 0.2, u, si, 4000.0, state, im, imesh, mat)
	im.queue_free()


## 把单位从 _units 里摘掉(★用 is_same 比较, 不能用 == / erase —— Godot 会递归哈希单位字典成环卡死)
func _arr_drop(t: Dictionary) -> void:
	for i in range(_s._units.size()):
		if is_same(_s._units[i], t):
			_s._units.remove_at(i)
			return


# ─────────────────────────────────────────────────────────────
# ⑪a 重击锤 047: 3★ 生命值 400
# ─────────────────────────────────────────────────────────────
func _t11a_hammer() -> void:
	print("── ⑪a 重击锤 · 3★ 生命 400 ──")
	var rows = ES.STATS.get("p2eq_047", [])
	_ok("⑪a ★分母: 重击锤在属性表里有 3 档", rows is Array and (rows as Array).size() == 3)
	if rows is Array and (rows as Array).size() == 3:
		_ok("⑪a 3★ hp = 400 (需求字面值, 原 700)",
			int((rows as Array)[2].get("hp", -1)) == 400, "实际 %s" % str((rows as Array)[2].get("hp", "缺")))
		_ok("⑪a 1★/2★ 未被误改 (100 / 200)",
			int((rows as Array)[0].get("hp", -1)) == 100 and int((rows as Array)[1].get("hp", -1)) == 200,
			"%s / %s" % [str((rows as Array)[0].get("hp", "?")), str((rows as Array)[1].get("hp", "?"))])


# ─────────────────────────────────────────────────────────────
# ⑪b 分摊名单: 排除龟蛋 + 训龟大师 (铁壁盾 016 与 温泉蛋孵化盾 036 共用)
# ─────────────────────────────────────────────────────────────
func _t11b_sharepool() -> void:
	print("── ⑪b 分摊护盾名单 · 排龟蛋与大师 ──")
	_s._units.clear()
	var me: Dictionary = _mk("basic", "left", Vector2(-60.0, 0.0), 1000.0)
	var mate: Dictionary = _mk("basic", "left", Vector2(-20.0, 0.0), 1000.0)
	var tr: Dictionary = _mk("basic", "left", Vector2(20.0, 0.0), 1000.0); tr["is_trainer"] = true
	var eg: Dictionary = _mk("basic", "left", Vector2(60.0, 0.0), 1000.0); eg["_isEgg"] = true
	var pool: Array = _s._targeting._allies_share_pool(me)
	var has_tr := false
	var has_eg := false
	var has_me := false
	var has_mate := false
	for o in pool:
		if is_same(o, tr): has_tr = true
		if is_same(o, eg): has_eg = true
		if is_same(o, me): has_me = true
		if is_same(o, mate): has_mate = true
	_ok("⑪b ★名单不含训龟大师", not has_tr)
	_ok("⑪b ★名单不含龟蛋", not has_eg)
	_ok("⑪b ★分母: 名单含自己与普通友军(不是空名单)", has_me and has_mate, "名单 %d 人" % pool.size())
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑫ 不沉之锚 017: 每 0.25 秒回血, 且 on-hurt 不再回血
# ─────────────────────────────────────────────────────────────
func _t12_anchor() -> void:
	print("── ⑫ 不沉之锚 · 每 0.25 秒回血 ──")
	_s._units.clear()
	var u: Dictionary = _mk("basic", "left", Vector2(-60.0, 0.0), 1000.0)
	u["equips"] = [{"id": "p2eq_017", "star": 1}]
	u["eq_state"] = {}
	u["hp"] = 500.0
	_s._equip_tick_sys._tick_anchor(u, 0.2)
	_s._damage._heal_flush(u)
	_ok("⑫ 0.2 秒 → 还没到节拍, 不回血", absf(float(u["hp"]) - 500.0) < 0.01, "hp=%.1f" % float(u["hp"]))
	_s._equip_tick_sys._tick_anchor(u, 0.06)
	_s._damage._heal_flush(u)
	## ★2026-08-12 用户削弱: 每 0.25 秒回血 1/2/15% → **0.1/0.2/3%** maxHp。
	##   1★ 于是从 10 点变成 1 点(maxHp 1000)。数值判据在 verify_nerf_pistol_anchor 里逐星级验,
	##   这里只守"节拍到了会回血"这条时序。
	_ok("⑫ ★满 0.25 秒 → 回 0.1% maxHp = 1 点(1★·2026-08-12 削弱后)",
		absf(float(u["hp"]) - 501.0) < 0.51, "hp=%.1f (期望 501)" % float(u["hp"]))
	# on-hurt 不得再产生治疗(否则变成"定时 + 受伤"双份)
	var atk: Dictionary = _mk("basic", "right", Vector2(60.0, 0.0), 1000.0)
	u["hp"] = 500.0
	_s._equip_sys._eq_on_target(u, atk, 100)
	_s._damage._heal_flush(u)
	_ok("⑫ ★on-hurt 路径不再回血(不双份触发)", absf(float(u["hp"]) - 500.0) < 0.01,
		"hp=%.1f" % float(u["hp"]))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# ⑤-色 靶向器的伤害数字必须按【通用规矩】取色, 不许写死
#
#   ★由来(2026-08-30): 用户「靶向器是跳的数字没按规矩」→ 拍板「颜色按通用取」。
#     全项目的规矩是 VisualConstants.cls_for("damage", 类型, 暴击) —— 按伤害类型
#     统一取色(物红/魔蓝/真白), 见 battle_damage.gd:355。
#     本件原来把两处显示都写死成橙色(聚爆 #ff8a3a · 头顶累加读数 NUM_COL)。
#
#   ★靶向器两段是【真物理】(实测 500 护甲把伤害砍到 7.4%), 所以必须取物理色。
# ─────────────────────────────────────────────────────────────
func _t5_hookbomb_numcolor() -> void:
	print("── ⑤-色 伤害数字按通用规矩取色 ──")
	var hb = _s._hookbomb_sys
	var want: Color = VC.color_of(VC.cls_for("damage", "physical", false))
	var got: Color = hb._num_col()
	## ★分母: 通用物理色不能恰好等于那个退役橙色 —— 否则下面那条是和自己比, 恒真。
	_ok("⑤-色 ★分母: 通用物理色 ≠ 退役的写死橙色(否则下面恒真)",
		not got.is_equal_approx(hb.NUM_COL),
		"通用 %s / 旧橙 %s" % [str(got), str(hb.NUM_COL)])
	_ok("⑤-色 取色走 VisualConstants(物理)", got.is_equal_approx(want),
		"got %s / want %s" % [str(got), str(want)])

	## ★真正守得住的那条: 两处【显示】不许再出现写死的颜色字面量。
	##   只断言 _num_col() 对是不够的 —— 谁在渲染那行换回 Color("#...") 照样绿。
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/hookbomb_system.gd")
	var blast_ok := src.contains('_float_text(pp, str(dd), _num_col()')
	var label_ok := src.contains("lbl.modulate = _num_col()")
	_ok("⑤-色 ★分母: 源码读得到", src.length() > 5000, "%d 字" % src.length())
	_ok("⑤-色 聚爆飘字那行用 _num_col() 而不是颜色字面量", blast_ok)
	_ok("⑤-色 头顶累加读数那行用 _num_col() 而不是颜色字面量", label_ok)
	## NUM_COL 只许当门禁对照, 不许再接进渲染。
	_ok("⑤-色 退役常量 NUM_COL 没有被接回渲染", not src.contains("modulate = NUM_COL"))
