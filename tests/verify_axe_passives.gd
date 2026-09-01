extends Node
## verify_axe_passives.gd — 096 小木斧·五期【被动 3~6】(2026-09-01)
##
## ★需求原文(用户 2026-08-31)逐字:
##   被动3(石斧)「召唤物每过9秒，普攻获得强化onhit来造成击飞和短暂击退，并造成0.5ATK额外物理伤害」
##   被动4(铁斧)「召唤物的每第二次普攻变为竖劈，额外造成5%目标最大生命值真实伤害并施加10层流血」
##   被动5(金斧)「每第一次普攻变成180度横扫，与竖劈交替进行。每次普攻命中会为召唤物提供一层
##               持续5秒的效率层数，可无限叠加，每次叠加刷新时常」「一层效率提供4%攻击速度和2%移动速度」
##   被动6(钻石斧)「在释放治疗时…开始一段蓄力：在一个梯形预警范围里，每蓄力0.5秒使梯形区域的高
##               增加100码，共蓄力4秒，蓄力期间获得70%减伤并且效率计时器中断，蓄力完毕后砸下斧头，
##               高高击飞梯形里的所有敌人并眩晕3秒，每个敌人造成4ATK物理伤害」
##   四条各给「50点最大生命值，5攻击力，3护甲和3魔抗」——**可叠加**。
##
## ★★这份门禁里最容易写假的五条:
##   ① 「交替」: 只验"第2下是竖劈"会漏掉交替本身。要连打 6 下, 把 1/2/3/4/5/6 各是什么**列出来**比。
##   ② 「档位闸」: 只验"石斧能触发"是恒真式(不加闸也能触发)。**木斧不许触发**才是判据。
##   ③ 「效率层刷新」: 只验层数涨了没验时长。要在 4 秒时再叠一层, 验它从那一刻**重新算 5 秒**。
##   ④ 「蓄力中断计时」: 只验"蓄力中层数还在"会被"层数根本没到期"蒙混。要让蓄力**跨过原到期时刻**。
##   ⑤ 「70% 减伤要还原」: 只验蓄力时减伤上去了, 不验砸完降回来 ⇒ 一个永久 70% 减伤的怪物。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 造一只【干净的合成斧头】—— 不走真召唤, 因为真召唤的血/攻随经验变、
## 而这份门禁量的是行为不是数值(CLAUDE.md: 拿随机 spawn 单位测精确数值会 CI 偶发红)。
func _mk_axe(pv: int, atk: float = 100.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = pv
	ax["atk"] = atk
	ax["id"] = "__axe_probe__"        # 隔离掉 basic 龟自己的不屈/暴击(否则数值飘)
	ax["crit"] = 0.0
	ax["atk_range"] = 200.0
	return ax


func _mk_foe(off: Vector2, hp: float = 200000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "right", c + off)
	_s._units.append(u)
	u["maxHp"] = hp
	u["hp"] = hp
	u["id"] = "__foe_probe__"
	u["def"] = 0.0
	u["mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["shield"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 096 小木斧 · 五期 被动 3~6 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_consts()
	_t_stage_gate()
	_t_smash()
	_t_alternate()
	_t_eff()
	_t_charge()
	_t_trapezoid()
	await _t_energy_real()

	if _n < 38:
		print("  [FAIL] ★分母: 断言只有 %d 条(<38) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 096 五期(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 分母: 常量就是需求的字面值
# ══════════════════════════════════════════════════════════════
func _t_consts() -> void:
	print("--- ① 分母: 常量 ---")
	_ok("★分母: 被动3 每 %.0f 秒一次 · 额外 %.1f×ATK" % [AE.SMASH_IV, AE.SMASH_ATK],
		is_equal_approx(AE.SMASH_IV, 9.0) and is_equal_approx(AE.SMASH_ATK, 0.5))
	_ok("★分母: 被动4 竖劈 %.0f%% 目标最大生命真伤 + %d 层流血"
		% [AE.CLEAVE_MAXHP_PCT * 100.0, AE.CLEAVE_BLEED],
		is_equal_approx(AE.CLEAVE_MAXHP_PCT, 0.05) and AE.CLEAVE_BLEED == 10)
	_ok("★分母: 被动5 横扫 %.0f° · 效率层 %.0f 秒 · 一层 +%.0f%%攻速 +%.0f%%移速"
		% [AE.SWEEP_ARC_DEG, AE.EFF_DUR, AE.EFF_ASPD * 100.0, AE.EFF_MOVE * 100.0],
		is_equal_approx(AE.SWEEP_ARC_DEG, 180.0) and is_equal_approx(AE.EFF_DUR, 5.0)
		and is_equal_approx(AE.EFF_ASPD, 0.04) and is_equal_approx(AE.EFF_MOVE, 0.02))
	_ok("★分母: 被动6 蓄 %.0f 秒 · 每 %.1f 秒 +%.0f 码 · 减伤 %.0f%% · %.0f×ATK · 眩晕 %.0f 秒"
		% [AE.CHARGE_TIME, AE.CHARGE_STEP, AE.CHARGE_H_PER_STEP, AE.CHARGE_DR * 100.0,
		   AE.SLAM_ATK, AE.SLAM_STUN],
		is_equal_approx(AE.CHARGE_TIME, 4.0) and is_equal_approx(AE.CHARGE_STEP, 0.5)
		and is_equal_approx(AE.CHARGE_H_PER_STEP, 100.0) and is_equal_approx(AE.CHARGE_DR, 0.70)
		and is_equal_approx(AE.SLAM_ATK, 4.0) and is_equal_approx(AE.SLAM_STUN, 3.0))
	## 四条被动的属性可叠加 —— 拿 minion_hp/atk 的差值验, 不看常量本身
	var h0: float = AE.minion_hp(0, 0)
	var h4: float = AE.minion_hp(0, 4)
	var a0: float = AE.minion_atk(0, 0)
	var a4: float = AE.minion_atk(0, 4)
	_ok("★四条被动属性【可叠加】: 血 %.0f→%.0f(+%.0f×4) · 攻 %.0f→%.0f(+%.0f×4)"
		% [h0, h4, AE.PASSIVE_HP, a0, a4, AE.PASSIVE_ATK],
		is_equal_approx(h4 - h0, AE.PASSIVE_HP * 4.0)
		and is_equal_approx(a4 - a0, AE.PASSIVE_ATK * 4.0))
	_ok("★分母: 一条都不解锁时不白给(passives_at(0) == 0)", AE.passives_at(0) == 0)


# ══════════════════════════════════════════════════════════════
#  ② 档位闸: 木斧一条都不许触发
# ══════════════════════════════════════════════════════════════
func _t_stage_gate() -> void:
	print("--- ② 档位闸(木斧不许触发) ---")
	var pas = _s._equip_sys._axe._pas
	var ax: Dictionary = _mk_axe(0)          # 木斧: 0 条被动
	var foe: Dictionary = _mk_foe(Vector2(60, 0))
	ax["_axe_smash_ready"] = true            # 就算硬把标记打开也不许生效
	_ok("★木斧(0条): 强化 on-hit 不触发", is_equal_approx(pas.smash_on_hit(ax, foe), 0.0))
	_ok("★木斧(0条): 第 2 下不竖劈", is_equal_approx(pas.cleave_settle(ax, foe, 2), 0.0))
	_ok("★木斧(0条): 第 1 下不横扫", pas.sweep_targets(ax, foe, 1).is_empty())
	_ok("★木斧(0条): 命中不给效率层", pas.add_eff(ax) == 0)
	_ok("★木斧(0条): 治疗不进蓄力", not pas.begin_charge(ax))
	## 分母: 换成钻石斧同样的调用【全都】生效 —— 否则上面五条是恒真式
	var dx: Dictionary = _mk_axe(4)
	dx["_axe_smash_ready"] = true
	var f2: Dictionary = _mk_foe(Vector2(70, 0))
	_ok("★★分母: 钻石斧(4条)同样的五个调用全都生效",
		pas.smash_on_hit(dx, f2) > 0.0 and pas.cleave_settle(dx, f2, 2) > 0.0
		and not pas.sweep_targets(dx, f2, 1).is_empty() and pas.add_eff(dx) == 1
		and pas.begin_charge(dx))


# ══════════════════════════════════════════════════════════════
#  ③ 被动 3: 每 9 秒一次强化 on-hit
# ══════════════════════════════════════════════════════════════
func _t_smash() -> void:
	print("--- ③ 被动3 强化 on-hit ---")
	var pas = _s._equip_sys._axe._pas
	var ax: Dictionary = _mk_axe(1, 100.0)
	var foe: Dictionary = _mk_foe(Vector2(80, 0))
	## 刚出生: 还没到 9 秒 ⇒ 不该强化
	pas.tick_smash(ax, 0.016)
	_ok("★刚出生没到 %.0f 秒: 不强化" % AE.SMASH_IV, is_equal_approx(pas.smash_on_hit(ax, foe), 0.0),
		"下一次可用时刻 = %.2f (现在 %.2f)" % [float(ax.get("_axe_smash_at", -1)), _s._t])
	## 把时刻拨到过去 = 充能满
	ax["_axe_smash_at"] = _s._t - 0.1
	pas.tick_smash(ax, 0.016)
	var hp0: float = float(foe["hp"])
	var extra: float = pas.smash_on_hit(ax, foe)
	_ok("★充满后触发, 额外伤害 = %.1f×ATK = %.0f" % [AE.SMASH_ATK, 100.0 * AE.SMASH_ATK],
		is_equal_approx(extra, 100.0 * AE.SMASH_ATK), "实测 %.1f" % extra)
	_ok("★分母: 目标真的掉血了(%.0f → %.0f)" % [hp0, float(foe["hp"])], float(foe["hp"]) < hp0)
	_ok("★触发后立刻消耗掉, 紧接着第二下不再强化",
		is_equal_approx(pas.smash_on_hit(ax, foe), 0.0))
	_ok("★消耗后下一次可用时刻推到 %.0f 秒后" % AE.SMASH_IV,
		float(ax["_axe_smash_at"]) > _s._t + AE.SMASH_IV - 0.2)
	## 击飞: 走 _knockback ⇒ 目标应当离地
	_ok("★强化命中把目标打上天(height > 0 或 vy > 0)",
		float(foe.get("height", 0.0)) > 0.0 or float(foe.get("vy", 0.0)) > 0.0,
		"height=%.2f vy=%.2f" % [float(foe.get("height", 0.0)), float(foe.get("vy", 0.0))])


# ══════════════════════════════════════════════════════════════
#  ④ 被动 4/5: 竖劈与横扫【交替】
# ══════════════════════════════════════════════════════════════
func _t_alternate() -> void:
	print("--- ④ 被动4/5 交替 ---")
	var pas = _s._equip_sys._axe._pas
	var ax: Dictionary = _mk_axe(3, 100.0)     # 金斧: 竖劈与横扫都解锁
	var foe: Dictionary = _mk_foe(Vector2(90, 0))
	## ★连打 6 下, 把每一下【是什么】列出来 —— 只验"第2下是竖劈"看不出交替
	var seq: Array = []
	for i in range(6):
		var sw: int = pas.bump_swing(ax)
		var c: float = pas.cleave_settle(ax, foe, sw)
		var sp: Array = pas.sweep_targets(ax, foe, sw)
		seq.append("竖劈" if c > 0.0 else ("横扫" if not sp.is_empty() else "普通"))
	_ok("★六下依次是 横扫/竖劈/横扫/竖劈/横扫/竖劈(实测 %s)" % str(seq),
		seq == ["横扫", "竖劈", "横扫", "竖劈", "横扫", "竖劈"])
	## 竖劈的数值: 5% 目标最大生命【真实伤害】+ 10 层流血
	var f2: Dictionary = _mk_foe(Vector2(100, 0), 10000.0)
	## ★★杠杆要选对: 这条路(`_apply_damage`)**根本不查护甲/魔抗** ——
	##   护甲只在 `_resolve_dmg` / `_phys_after_armor` / `_dot_after_resist` 里算
	##   (memory [[fb-damage-type-is-wiring-not-color]])。所以给 500 甲当判据是**空的**:
	##   反向验证当场证明了 —— 把它改成 `_apply_damage_from` 物理路, 一条都没红。
	##   `bucket == "tru"` 真正跳过的是 `flat_dr` 与 `damage_reduction`(见 _mitigate_incoming),
	##   ⇒ 判据必须落在这两个上。
	f2["def"] = 500.0                 # 留着做对照(这条路不查它, 不构成判据)
	f2["mr"] = 500.0
	f2["damage_reduction"] = 0.5      # ★真判据: 五成减伤
	f2["flat_dr"] = 30.0              # ★真判据: 固定减伤 30
	var hp0: float = float(f2["hp"])
	var d: float = pas.cleave_settle(ax, f2, 2)
	_ok("★竖劈额外伤害 = %.0f%% 目标最大生命 = %.0f" % [AE.CLEAVE_MAXHP_PCT * 100.0, 10000.0 * AE.CLEAVE_MAXHP_PCT],
		is_equal_approx(d, 10000.0 * AE.CLEAVE_MAXHP_PCT), "实测 %.1f" % d)
	var lost: float = hp0 - float(f2["hp"])
	_ok("★★竖劈是【真实伤害】: 目标 50%% 减伤 + 30 固定减伤照样掉满 %.0f(实测掉 %.0f)"
		% [d, lost], absf(lost - d) < 1.01 and d > 1.0,
		"分母: d=%.1f 必须 >1, 否则 0-0 也算过" % d)
	## 分母: 同样这只靶子, 走【非真伤】那条路时确实会被削 —— 证明减伤真的在起作用
	var hp1: float = float(f2["hp"])
	_s._damage._apply_damage(f2, int(d), Color("#888888"), ax, "dot", false)
	var soft: float = hp1 - float(f2["hp"])
	_ok("★★分母: 同一只靶子走非真伤路会被削(%.0f → %.0f, 少掉 %.0f)"
		% [d, soft, d - soft], soft < d - 1.0, "减伤没生效的话这条会红")
	## ★字段名是 `dot_stacks["bleed"]`, 不是我第一版编的 `bleed_stacks` ——
	##   编出来的字段名全仓 0 次出现, 读到的永远是 0, 而门禁会红成"效果没生效"
	##   (memory [[fb-gate-subject-never-constructed]]: 一晚五次里有三次是这个形状)。
	var bl: int = int((f2.get("dot_stacks", {}) as Dictionary).get("bleed", 0))
	_ok("★竖劈施加 %d 层流血(实测 %d)" % [AE.CLEAVE_BLEED, bl], bl >= AE.CLEAVE_BLEED)
	## 横扫: 180° 扇形 —— 正面的进名单、背后的不进
	var front: Dictionary = _mk_foe(Vector2(120, 40))
	var back: Dictionary = _mk_foe(Vector2(-120, 0))
	var lst: Array = pas.sweep_targets(ax, foe, 1)
	var has_front := false
	var has_back := false
	for o in lst:
		if is_same(o, front):
			has_front = true
		if is_same(o, back):
			has_back = true
	_ok("★横扫扫到【正面】那个(分母: 名单 %d 个)" % lst.size(), has_front and lst.size() > 0)
	_ok("★★横扫扫不到【背后】那个(180° 就是只覆盖正面这半边)", not has_back)


# ══════════════════════════════════════════════════════════════
#  ⑤ 被动 5: 效率层
# ══════════════════════════════════════════════════════════════
func _t_eff() -> void:
	print("--- ⑤ 被动5 效率层 ---")
	var pas = _s._equip_sys._axe._pas
	var ax: Dictionary = _mk_axe(3)
	_ok("★分母: 起手 0 层", pas.eff_stacks(ax) == 0)
	for i in range(7):
		pas.add_eff(ax)
	_ok("★可无限叠(叠 7 次 = 7 层, 没有上限钳)", pas.eff_stacks(ax) == 7,
		"实测 %d 层" % pas.eff_stacks(ax))
	_ok("★一层 +%.0f%% 攻速: 7 层 = ×%.2f" % [AE.EFF_ASPD * 100.0, AE.eff_aspd_mult(7)],
		is_equal_approx(AE.eff_aspd_mult(7), 1.0 + 0.04 * 7.0))
	_ok("★一层 +%.0f%% 移速: 7 层 = ×%.2f" % [AE.EFF_MOVE * 100.0, AE.eff_move_mult(7)],
		is_equal_approx(AE.eff_move_mult(7), 1.0 + 0.02 * 7.0))
	## ★★"每次叠加刷新时长": 把到期时刻拨到只剩 0.1 秒, 再叠一层, 它必须重新变成 5 秒
	ax["_axe_eff_until"] = _s._t + 0.1
	pas.add_eff(ax)
	_ok("★★叠新层【刷新整条时长】(到期从 +0.1 秒推回 +%.0f 秒)" % AE.EFF_DUR,
		float(ax["_axe_eff_until"]) > _s._t + AE.EFF_DUR - 0.2,
		"剩余 %.2f 秒" % (float(ax["_axe_eff_until"]) - _s._t))
	## 过期就整条清零(不是逐层衰减)
	ax["_axe_eff_until"] = _s._t - 0.01
	_ok("★到期整条清零(不逐层衰减)", pas.eff_stacks(ax) == 0)


# ══════════════════════════════════════════════════════════════
#  ⑥ 被动 6: 蓄力 → 猛砸
# ══════════════════════════════════════════════════════════════
func _t_charge() -> void:
	print("--- ⑥ 被动6 蓄力与猛砸 ---")
	var pas = _s._equip_sys._axe._pas
	var ax: Dictionary = _mk_axe(4, 100.0)
	var foe: Dictionary = _mk_foe(Vector2(300, 0))
	var dr0: float = float(ax.get("damage_reduction", 0.0))
	_ok("★治疗时进入蓄力", pas.begin_charge(ax) and pas.is_charging(ax))
	_ok("★蓄力期间 %.0f%% 减伤(%.2f → %.2f)" % [AE.CHARGE_DR * 100.0, dr0, float(ax["damage_reduction"])],
		is_equal_approx(float(ax["damage_reduction"]), AE.CHARGE_DR))
	_ok("★分母: 减伤确实被抬高了(原来是 %.2f)" % dr0, AE.CHARGE_DR > dr0)
	_ok("★已经在蓄了就不重开(否则治疗一进来就把高清零)", not pas.begin_charge(ax))
	## ★★效率计时【中断】: 先叠一层(5 秒), 再让蓄力跨过它原本的到期时刻
	pas.add_eff(ax)
	var until0: float = float(ax["_axe_eff_until"])
	var mv_until0: float = float(ax.get("move_buff_until", 0.0))
	## ★★驱动【真 tick_charge】, 不直接调 hold_eff ——
	##   第一版我直接调 hold_eff 循环 300 次, 反向验证当场证明它是假的:
	##   把 tick_charge 里那句 hold_eff 删掉, 门禁**一条都没红**, 因为它根本没走那条路。
	##   这正是"断言自己插的钩子"(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
	for i in range(300):                      # 300 × 0.02 = 6 秒 > 效率层的 5 秒
		pas.tick_charge(ax, 0.02)
	_ok("★★蓄力中效率计时【中断】: 到期时刻被往后推了 %.1f 秒(跨过了原 5 秒)"
		% (float(ax["_axe_eff_until"]) - until0),
		float(ax["_axe_eff_until"]) - until0 > 5.0)
	## ★★★效率层现在同时驱动**两条**计时: 攻速走 `_axe_eff_until`、移速走 `move_buff_until`。
	##   只暂停一条 ⇒ 4 秒蓄力结束时移速加成已过期而攻速还在, 而需求说的是"效率计时器中断"(一条)。
	##   老判据只盯 `_axe_eff_until` —— **窄了一格, 抓不到**(2026-09-01 逐句核对时读出来的)。
	_ok("★★★移速那一半【也】被暂停(move_buff_until 推了 %.1f 秒)"
		% (float(ax.get("move_buff_until", 0.0)) - mv_until0),
		float(ax.get("move_buff_until", 0.0)) - mv_until0 > 5.0,
		"分母: 原到期 %.2f · 现在 %.2f · 当前 t=%.2f"
		% [mv_until0, float(ax.get("move_buff_until", 0.0)), float(_s._t)])
	## 阶梯高度
	var bad: Array = []
	for pair in [[0.0, 0.0], [0.4, 0.0], [0.5, 100.0], [0.9, 100.0], [2.0, 400.0], [4.0, 800.0], [9.0, 800.0]]:
		var got: float = AE.charge_height(float(pair[0]))
		if not is_equal_approx(got, float(pair[1])):
			bad.append("%.1fs → %.0f(应 %.0f)" % [float(pair[0]), got, float(pair[1])])
	_ok("★高度是【0.5 秒一格的阶梯】不是连续增长(0.4s 仍是 0 码; 满蓄 800 码)",
		bad.is_empty(), str(bad))
	## 砸下去
	ax["_axe_charge_t0"] = _s._t - AE.CHARGE_TIME       # 直接推到蓄满
	ax["_axe_charge_dir"] = Vector2.RIGHT
	var hp0: float = float(foe["hp"])
	var n: int = pas.slam_settle(ax)
	_ok("★砸中了梯形里的敌人(命中 %d 个)" % n, n >= 1)
	var lost: float = hp0 - float(foe["hp"])
	_ok("★每个敌人吃 %.0f×ATK = %.0f 物理(实测掉 %.0f)" % [AE.SLAM_ATK, 100.0 * AE.SLAM_ATK, lost],
		lost >= 100.0 * AE.SLAM_ATK * 0.5, "0甲0抗的靶子, 掉血应≈满额")
	_ok("★砸完眩晕 %.0f 秒" % AE.SLAM_STUN,
		float(foe.get("stun_until", 0.0)) > _s._t + AE.SLAM_STUN - 0.6,
		"stun_until=%.2f 现在 %.2f" % [float(foe.get("stun_until", 0.0)), _s._t])
	_ok("★砸完高高击飞", float(foe.get("height", 0.0)) > 0.0 or float(foe.get("vy", 0.0)) > 0.0)
	_ok("★★砸完减伤【还原】(不许留一个永久 70% 减伤的怪物)",
		is_equal_approx(float(ax.get("damage_reduction", 0.0)), dr0),
		"现在 %.2f (原 %.2f)" % [float(ax.get("damage_reduction", 0.0)), dr0])
	_ok("★砸完退出蓄力态", not pas.is_charging(ax))


# ══════════════════════════════════════════════════════════════
#  ⑦ 梯形几何(纯函数, 直接喂坐标)
# ══════════════════════════════════════════════════════════════
func _t_trapezoid() -> void:
	print("--- ⑦ 梯形几何 ---")
	var o := Vector2.ZERO
	var d := Vector2.RIGHT
	_ok("★正前方 400 码、贴中轴 → 在里面", AE.in_trapezoid(o, d, 800.0, Vector2(400, 0)))
	_ok("★★背后 400 码 → 不在里面(梯形是单向的)", not AE.in_trapezoid(o, d, 800.0, Vector2(-400, 0)))
	_ok("★超出高(900 > 800) → 不在里面", not AE.in_trapezoid(o, d, 800.0, Vector2(900, 0)))
	_ok("★高只蓄到 100 时, 400 码外的敌人打不到(高是会长的)",
		not AE.in_trapezoid(o, d, 100.0, Vector2(400, 0)))
	## 近窄远宽: 同一个横向偏移, 近处出界、远处在内
	var lat: float = AE.TRAPEZOID_NEAR_W * 0.5 + 30.0
	_ok("★★近窄远宽: 横向 %.0f 码时【近处(50)出界】而【远处(760)在内】" % lat,
		not AE.in_trapezoid(o, d, 800.0, Vector2(50, lat))
		and AE.in_trapezoid(o, d, 800.0, Vector2(760, lat)))
	_ok("★高为 0(还没开始蓄)时谁都打不到", not AE.in_trapezoid(o, d, 0.0, Vector2(10, 0)))
	## 方向真的跟着 dir 转(写死朝右的实现在这条上红)
	_ok("★★朝向跟着 dir 转: dir 朝上时, 正上方在内、正右方出界",
		AE.in_trapezoid(o, Vector2.UP, 800.0, Vector2(0, -400))
		and not AE.in_trapezoid(o, Vector2.UP, 800.0, Vector2(400, 0)))


# ══════════════════════════════════════════════════════════════
#  ⑧ ★★★龟能【真的会涨】—— 不喂数, 真跑 sim
# ══════════════════════════════════════════════════════════════
## ★由来(2026-09-01): 探针实测「真跑 13.78 游戏秒, 斧头 energy 纹丝不动 0.00」——
##   「攒满 140 龟能」的通用主动、被动6 的蓄力猛砸、四个最终造物的主动,
##   **在真实对局里一个都放不出来**。而当时 125 条门禁全绿:
##   它们都**自己先把 energy 设成 140** 再调 cast_heal —— 证明的是"函数对不对",
##   从没证明"游戏里攒得满"。(memory [[fb-verify-must-run-the-real-path]])
## ★根因: 引擎里**没有 `u["energy"]` 这个字段** —— 实时版龟能 = 技能冷却充能。
##   `_make_unit` 建了这个键但全引擎零读者 ⇒ 我读的字段没人写, 永远是 0。
## ★★所以这一节的判据只有一条硬规矩: **一个字都不许喂**, 只推时间。
func _t_energy_real() -> void:
	print("--- ⑧ 龟能真的会涨(不喂数) ---")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(owner_u)
	owner_u["equips"] = [{"id": "p2eq_096", "star": 1}]
	var axsys = _s._equip_sys._axe
	var ax = axsys.summon(owner_u)
	_ok("★分母: 斧头建出来了且 maxEnergy = %.0f" % AE.ACTIVE_ENERGY,
		ax is Dictionary and float(ax.get("maxEnergy", -1.0)) == AE.ACTIVE_ENERGY,
		"maxEnergy=%s" % str(ax.get("maxEnergy", "缺") if ax is Dictionary else "null"))
	if not (ax is Dictionary):
		return
	_ok("★分母: 起手就是 0 龟能(没人偷偷喂)", float(ax.get("energy", -1.0)) == 0.0,
		"实测 %.1f" % float(ax.get("energy", -1.0)))
	## ★★只推时间, 一个字段都不写
	var t0: float = float(_s._t)
	var w := 0
	while w < 1200 and float(_s._t) - t0 < 2.0:
		await get_tree().process_frame
		w += 1
	var e2: float = float(ax.get("energy", 0.0))
	_ok("★★★真跑 %.2f 游戏秒后龟能【涨了】(实测 %.1f) —— 这条红过: 之前恒为 0"
		% [float(_s._t) - t0, e2], e2 > 0.0, "分母: 推了 %d 帧" % w)
	## 速率对不对: 1 点 = 0.075 秒 ⇒ 每秒 13.33 点
	var want: float = (float(_s._t) - t0) / AE.SEC_PER_ENERGY
	_ok("★速率 = 全局换算(1 点 %.3f 秒): 期望 %.1f 实测 %.1f(±8%%)"
		% [AE.SEC_PER_ENERGY, want, e2], want > 0.0 and absf(e2 - want) <= want * 0.08,
		"差 %.1f" % absf(e2 - want))
	## ★★全息斧的「50% 龟能充能速率」这才有了消费者
	_ok("★★全息斧 +50%% 充能: 同样 1 秒多涨一半(%.1f vs %.1f)"
		% [AE.energy_gain(1.0, 1.5), AE.energy_gain(1.0, 1.0)],
		is_equal_approx(AE.energy_gain(1.0, 1.5), AE.energy_gain(1.0, 1.0) * 1.5),
		"echarge_perm 没乘进去 = 造物4的属性又是死的")
	## ★★★真的攒满并**把主动放出来** —— 全程不喂 energy
	## ★★探针实测: 木斧召唤物(500 血)在默认战斗场里**2.5 秒就被打死**, 而主动要 10.5 秒攒满
	##   ⇒ 直接等会等到一具尸体, 那量的是"活不活得下来"、不是"攒不攒得满"。
	##   ⇒ 每帧把血补满(**只碰 hp, 一个字都不碰 energy**), 判据才刚好卡住这一节要问的事。
	##   (memory: 判据要刚好卡住那个形状 / 拿干净合成单位隔离)
	## ★★把龟能【归零】再计时 —— 归零不是"喂", 是把基线对齐到需求那句话:
	##   「攒满 140 龟能」⇒ 从 0 到放出来应该正好是 140 × 0.075 = 10.5 秒。
	##   不归零的话前面几节耗掉的游戏时间会混进来, 量出来的"2.6 秒"根本不是满条时间。
	ax["energy"] = 0.0
	ax["shield"] = 0.0
	var t1: float = float(_s._t)
	var w2 := 0
	var fired := false
	var fill_t := -1.0
	var prev_e := 0.0
	var sh_before := 0.0
	var sh_gain := -1.0
	## ★上限要让【失败路径】也跑得完: 修坏了(龟能恒 0)时这个循环会跑满,
	##   跑满还超预算就会被 --quit-after 掐断 ⇒ 反向验证时那条断言"没红"
	##   其实是"根本没执行到"。2026-09-01 反向验证第一次就栽在这。
	while w2 < 3600 and float(_s._t) - t1 < 13.0:
		await get_tree().process_frame
		w2 += 1
		## ★★携带者**也**要保命 —— 龟能是在 `AxeSystem.tick` 里涨的, 而那是从
		##   **携带者的装备 tick** 分派下来的: 携带者一死, 斧头整条 tick 就停了。
		##   第二版只保了斧头, 结果 13 秒只涨到 106(= 8 秒的量), 正是携带者 8 秒时死了。
		ax["hp"] = float(ax.get("maxHp", 1.0))      # 只保命, 不喂龟能
		ax["alive"] = true
		owner_u["hp"] = float(owner_u.get("maxHp", 1.0))
		owner_u["alive"] = true
		## ★★判据不能是「护盾 > 0」—— **被动2 偷护盾也会让盾 >0**,
		##   第一版就是这么写的, 结果 2.62 秒就"过了"(那是偷来的盾, 主动根本没放)。
		##   ⇒ 量产品自己的账: 龟能【攒到满→归零】这个跃迁, 只有 cast_heal 会造成。
		var e_now: float = float(ax.get("energy", 0.0))
		if prev_e >= AE.ACTIVE_ENERGY - 1.0 and e_now < 1.0:
			fired = true
			fill_t = float(_s._t) - t1
			sh_gain = float(ax.get("shield", 0.0)) - sh_before
			break
		prev_e = e_now
		sh_before = float(ax.get("shield", 0.0))
	var want_t: float = AE.ACTIVE_ENERGY * AE.SEC_PER_ENERGY
	_ok("★★★龟能从 0 攒满并**真的放出了主动**(实测 %.2f 秒, 应 %.2f 秒 ±15%%)"
		% [fill_t, want_t], fired and absf(fill_t - want_t) <= want_t * 0.15,
		"分母: 推了 %d 帧 · 当前龟能 %.1f · 护盾 %.1f"
		% [w2, float(ax.get("energy", 0.0)), float(ax.get("shield", 0.0))])
	## ★★量的是**那一帧的增量**, 不是护盾总量 —— 总量里混着被动2 偷来的。
	_ok("★主动那一帧加的护盾 = %.0f%% 最大生命(实测 +%.1f / 应 %.1f)"
		% [AE.ACTIVE_SHIELD_PCT * 100.0, sh_gain,
		   float(ax.get("maxHp", 0.0)) * AE.ACTIVE_SHIELD_PCT],
		fired and absf(sh_gain - float(ax.get("maxHp", 0.0)) * AE.ACTIVE_SHIELD_PCT) <= 1.5)
	_ok("★★放完龟能【清零】重新攒(不是一直满着每帧放)",
		fired and float(ax.get("energy", 999.0)) < AE.ACTIVE_ENERGY * 0.5,
		"实测 %.1f" % float(ax.get("energy", -1.0)))
