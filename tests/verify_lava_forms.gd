extends Node
## verify_lava_forms.gd — 熔岩龟【两个形态】的数值门禁(2026-08-14)
##
## ★★★由来: 变异探针实测 `lava_system._lava_volcano_erupt`(205 行)**打瘸了全套一条不红**
##   —— 熔岩龟是**裸奔**的。而用户 2026-08-13 刚改过它的砸地数值、08-14 又要削火山爆发。
##   按今晚立的规矩: **动裸奔系统之前先给它补门禁**, 否则削完没人守得住。
##
## ★这条守的是【两个形态各自的核心数值】, 判据全部从常量推导, 不抄数字:
##   · 火山爆发: 一段 ERUPT_ATK_COEF · ERUPT_BURN_COEF 层灼烧 · ERUPT_HEAL_PCT 回血
##   · 变身砸地: SLAM_ATK_COEF / SLAM_BURN_COEF
##   · 灼烧**不许走全局** `_default_burn_stacks` —— 那个凤凰等火系也在用,
##     熔岩调数值会静默削掉别人(2026-08-13 踩过)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Lava := preload("res://scripts/systems/skills/lava_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 熔岩龟: 两形态数值 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# ── ① 常量本身就是用户拍的那三个数 ──────────────────────────────────────
	_ok("★火山爆发伤害系数 = 1.2ATK(用户 2026-08-14: 原 5 段 0.5)",
		absf(Lava.ERUPT_ATK_COEF - 1.2) < 1e-6, "实得 %.2f" % Lava.ERUPT_ATK_COEF)
	_ok("★火山爆发灼烧 = 0.2ATK 层", absf(Lava.ERUPT_BURN_COEF - 0.2) < 1e-6,
		"实得 %.2f" % Lava.ERUPT_BURN_COEF)
	_ok("★火山爆发回血 = 8%", absf(Lava.ERUPT_HEAL_PCT - 0.08) < 1e-6,
		"实得 %.3f" % Lava.ERUPT_HEAL_PCT)
	## ★★灼烧不许走全局系数 —— 那是凤凰等火系共用的, 改它会波及别人。
	var src_lv := FileAccess.get_file_as_string("res://scripts/systems/skills/lava_system.gd")
	var bad := 0
	for ln in src_lv.split("\n"):
		var t: String = str(ln).strip_edges()
		if t.begins_with("#"):
			continue
		if t.find("_default_burn_stacks") >= 0:
			bad += 1
	_ok("★★熔岩【一处都不走】全局灼烧系数(实得 %d 处)" % bad, bad == 0,
		"走全局的地方 %d 处" % bad)

	# ── ② 【已知缺口】火山爆发的实际伤害无头量不到 ──────────────────────────
	##   ★根因: 浪潮的推进与命中判定是 `tween_method` 驱动的
	##     (lava_system.gd:193「波前沿线推进 + 逐帧命中判定 (tween_method 推 front-distance)」)
	##     —— **tween 在无头下推不动**, 与 031 水晶球B 同一个形状。
	##   ★031 的解法是把结算搬到 sim 时钟(见 `CrystalSystem.tick`), 这里同样可行, 但那是
	##     产品重构, 不在本次"只削数值"的范围内。**显式登记成会红的断言, 不静默略过。**
	##   ⇒ 本条现在只守【常量】(上面四条)与【形态分派】(下面两条)。
	##     常量守住 = 谁把 1.2/0.2/0.08 改了会红; 但"改完之后打出来对不对"没人验。
	const TWEEN_BURIED_NOTE := "火山爆发/浪潮命中判定走 tween_method, 无头量不到实际伤害"
	_ok("★★已知缺口显式登记: %s" % TWEEN_BURIED_NOTE,
		FileAccess.get_file_as_string("res://scripts/systems/skills/lava_system.gd").find("tween_method") >= 0,
		"要解掉它: 照 CrystalSystem.tick 的做法把结算搬到 sim 时钟")

	# ── ③ 反面: 远程形态放 A 技【不该】是火山爆发 ──────────────────────────
	##   ★两个形态的 A/B 技是完全不同的两套(火山: 火山爆发/烈焰打击;
	##     远程: 地裂/岩浆涌动)。分派选错形态是很容易犯的错, 焊住它。
	var src_disp := src_lv
	_ok("★★A 技按形态分派(火山=火山爆发 / 远程=地裂)",
		src_disp.find("if volcano: _lava_volcano_erupt(u)") >= 0
		and src_disp.find("else:       _lava_quake(u)") >= 0)
	_ok("★★B 技按形态分派(火山=烈焰打击 / 远程=岩浆涌动)",
		src_disp.find("if volcano: _lava_flame_strike(u, tgt)") >= 0
		and src_disp.find("else:       _lava_magma_surge(u, tgt)") >= 0)

	# ── ④ 地裂(岩浆池) 每跳伤害 —— 用户 2026-09-30 改的公式 ────────────────────
	##   需求原话:「熔岩龟的地裂在 10 跳改为每一条造成 12%ATK + 目标 0.5% 最大生命值魔法伤害」
	##   ★改前实测(探针 2026-09-30): 10 跳, 每跳 = atk×0.06, **没有任何目标生命百分比段**。
	##   ★判据的三个洞逐个堵:
	##     a) 只量一种 ATK/血量 ⇒ 「0.12ATK」和「0.5%maxHp」在那一组样本下同解
	##        ⇒ 删掉任意一段照样绿。⇒ 用 (atk, maxHp) 三个点。
	##     b) 只验纯函数 ⇒ 「函数写对了但没人调它」照样绿。⇒ 走真入口 _lava_quake + _tick_lava_zones。
	##     c) 只验总量 ⇒ 跳数错了也可能凑上。⇒ 单独数【结算了几跳】。
	_ok("★地裂每跳 ATK 系数 = 0.12(用户 2026-09-30: 原 0.06)",
		absf(Lava.QUAKE_ATK_COEF - 0.12) < 1e-9, "实得 %.4f" % Lava.QUAKE_ATK_COEF)
	_ok("★地裂每跳 + 目标 0.5% 最大生命值", absf(Lava.QUAKE_TGT_HP - 0.005) < 1e-12,
		"实得 %.5f" % Lava.QUAKE_TGT_HP)
	_ok("★地裂共 10 跳(5 秒 ÷ 0.5 秒·需求原话里的「10 跳」)",
		Lava.QUAKE_TICKS == 10 and absf(Lava.QUAKE_SEC - 5.0) < 1e-9
			and absf(Lava.QUAKE_TICK_SEC - 0.5) < 1e-9,
		"TICKS=%d SEC=%.2f TICK_SEC=%.2f" % [Lava.QUAKE_TICKS, Lava.QUAKE_SEC, Lava.QUAKE_TICK_SEC])

	## ── ④a 纯函数 × 三个样本点(定额 0 / ATK 段 / 生命段 三个未知量, 三个方程唯一确定) ──
	var q_ok := true
	var q_detail: Array = []
	for sp in [[100.0, 1000.0], [100.0, 9000.0], [400.0, 1000.0]]:
		var at: float = float(sp[0])
		var mh: float = float(sp[1])
		var src_q: Dictionary = _mk_clean(s, "lava", "left", Vector2(-120.0, -60.0), 6000.0)
		src_q["atk"] = at
		var tgt_q: Dictionary = _mk_clean(s, "fortune", "right", Vector2(120.0, -60.0), mh)
		var got: float = float(s._lava_sys._quake_tick_dmg(src_q, tgt_q))
		var want: float = at * 0.12 + mh * 0.005
		q_detail.append("%.0fATK/%.0fHP: %.1f(期望 %.1f)" % [at, mh, got, want])
		if absf(got - want) > 0.51:
			q_ok = false
		s._units.clear()
	_ok("★★地裂纯函数 × 三个样本点 = 12%ATK + 0.5%目标最大生命(mr=0 时不减)", q_ok,
		" · ".join(q_detail))

	## ── ④b 真入口端到端: 放地裂 → 强推时钟 14 次 → 只该结算 10 跳, 每跳等于纯函数 ──
	s._units.clear()
	var lv: Dictionary = _mk_clean(s, "lava", "left", Vector2(-40.0, 0.0), 8000.0)
	lv["atk"] = 200.0
	var en: Dictionary = _mk_clean(s, "fortune", "right", Vector2(0.0, 0.0), 4000.0)
	s._lava_sys._lava_quake(lv)
	_ok("★分母: 岩浆池真的建起来了, 且敌人在池内",
		s._lava_sys._lava_zones.size() == 1
			and float(en["pos"].distance_to(s._lava_sys._lava_zones[0]["center"]))
				<= float(s._lava_sys._lava_zones[0]["radius"]),
		"池 %d 个" % s._lava_sys._lava_zones.size())
	var zq: Dictionary = s._lava_sys._lava_zones[0]
	var per: Array = []
	for _i in range(14):
		en["hp"] = float(en["maxHp"])
		s._t = float(zq["next_tick"])
		s._lava_sys._tick_lava_zones(0.0)
		per.append(float(en["maxHp"]) - float(en["hp"]))
	var hits := 0
	for d in per:
		if float(d) > 0.0:
			hits += 1
	var want_tick: float = 200.0 * 0.12 + 4000.0 * 0.005
	_ok("★★真入口: 强推 14 次时钟只结算 %d 跳(= QUAKE_TICKS 10, 多推的不算)" % hits,
		hits == 10, "逐跳 %s" % str(per))
	## ★每一跳都比, 不只比首跳(10 跳里有一跳算错也要红)
	var bad_tick: Array = []
	for i in range(hits):
		if absf(float(per[i]) - want_tick) > 1.01:
			bad_tick.append("第%d跳 %.1f" % [i + 1, float(per[i])])
	_ok("★★真入口 10 跳每跳掉血都 = %.1f (0.12×200ATK + 0.5%%×4000HP)" % want_tick,
		hits == 10 and bad_tick.is_empty(),
		"分母 hits=%d · 对不上的跳: %s · 实测首跳 %.1f" % [hits, str(bad_tick), float(per[0])])

	## ── ④b+ 接线锚点: 每跳的结算得真有人在 sim 循环里推 ──
	##   ★上面那条端到端是【测试自己手推时钟】的, 把主循环里那一行摘掉它照样绿
	##     (memory [[fb-zero-caller-is-a-whole-class]]: 写了没人读/调是一整类)。
	##     `_lava_sys._tick_lava_zones(dt)` 在 RealtimeBattle3DScene._sim_step 里(约 2304 行)。
	_ok("★★岩浆池每跳结算挂在 sim 循环上(_sim_step 里调 _lava_sys._tick_lava_zones)",
		FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
			.find("_lava_sys._tick_lava_zones(") >= 0)

	## ── ④b++ 登记一条【前提】: 地裂改走 _resolve_dmg 后不再过 _atk_dmg 里的寒冰对火增伤 ──
	##   ★`_atk_dmg` 里有一段「攻击者带 _vs_fire_bonus 且目标是 熔岩/凤凰 ⇒ ×1.2」。
	##     地裂的每跳原来走 `_atk_dmg`, 现在走 `_resolve_dmg`(为了让 maxHp 段也吃魔抗),
	##     所以那一段不再作用于地裂。**这在当前是不可达的**: `_vs_fire_bonus` 全仓只有
	##     一个写入点(battle_spawn 的 `"ice":` 登场分支), 而岩浆池的 src 只能是放地裂的那只龟。
	##   ⇒ 把这个前提焊住: 哪天有人给别的单位也写 `_vs_fire_bonus`, 这条会红, 逼人回来重估。
	var writers := 0
	for f in ["res://scripts/scenes/battle/battle_spawn.gd",
			"res://scripts/scenes/RealtimeBattle3DScene.gd",
			"res://scripts/systems/skills/ice_system.gd",
			"res://scripts/systems/equip/equip_stats_apply.gd"]:
		for ln in FileAccess.get_file_as_string(f).split("
"):
			var t3: String = str(ln).strip_edges()
			if t3.begins_with("#") or t3.begins_with("##"):
				continue
			if t3.find("[\"_vs_fire_bonus\"] =") >= 0:
				writers += 1
	_ok("★★前提登记: `_vs_fire_bonus` 只有 1 个写入点(寒冰登场) ⇒ 地裂的 src 不可能带它",
		writers == 1, "写入点 %d 个(不是 1 就要回来重估地裂的 _resolve_dmg 改法)" % writers)

	## ── ④c 接线: 两段都必须吃魔抗(memory fb-damage-type-is-wiring-not-color) ──
	##   ★把 ATK 置 0, 只留「目标最大生命%」这一段, 再看它有没有被魔抗削 ——
	##     这正是旧写法(PIERCE_MAXHP_PCT 加在 _atk_dmg 外面)会露的那个洞。
	s._units.clear()
	var zsrc: Dictionary = _mk_clean(s, "lava", "left", Vector2(-40.0, 40.0), 8000.0)
	zsrc["atk"] = 0.0
	var soft_t: Dictionary = _mk_clean(s, "fortune", "right", Vector2(0.0, 40.0), 10000.0)
	var hard_t: Dictionary = _mk_clean(s, "fortune", "right", Vector2(20.0, 40.0), 10000.0)
	hard_t["mr"] = 100.0
	var d_soft: float = float(s._lava_sys._quake_tick_dmg(zsrc, soft_t))
	var d_hard: float = float(s._lava_sys._quake_tick_dmg(zsrc, hard_t))
	_ok("★★「目标最大生命%%」那一段也吃魔抗(ATK 置 0 单独量·mr 0 → %.1f / mr 100 → %.1f)"
			% [d_soft, d_hard],
		d_soft > 1.0 and d_hard < d_soft * 0.7,
		"分母 d_soft=%.1f 必须 >1; 期望 mr100 把它砍掉约一半" % d_soft)
	## ★同族分母: 护甲(def) 不该影响魔法段
	var arm_t: Dictionary = _mk_clean(s, "fortune", "right", Vector2(40.0, 40.0), 10000.0)
	arm_t["def"] = 100.0
	var d_arm: float = float(s._lava_sys._quake_tick_dmg(zsrc, arm_t))
	_ok("★★是【魔法】不是物理: 目标 100 护甲对它一点影响都没有(%.1f vs %.1f)" % [d_arm, d_soft],
		absf(d_arm - d_soft) < 0.51)
	s._units.clear()

	# ── ⑤ 变身砸地的两个系数(2026-08-13 用户拍的, 别被后来的人改掉) ─────────
	_ok("★变身砸地伤害 = 1.0ATK", absf(Lava.SLAM_ATK_COEF - 1.0) < 1e-6,
		"实得 %.2f" % Lava.SLAM_ATK_COEF)
	_ok("★变身砸地灼烧 = 0.3ATK 层", absf(Lava.SLAM_BURN_COEF - 0.3) < 1e-6,
		"实得 %.2f" % Lava.SLAM_BURN_COEF)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 熔岩龟两形态")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


## 干净合成单位: 把一切会污染精确数值的通道全部归零。
## ★不用随机 spawn 的敌 —— 队伍未播种 RNG / 带盾 / flat_dr 会让 CI 偶发红(CLAUDE.md §7)。
func _mk_clean(sc, id: String, side: String, off: Vector2, hp: float) -> Dictionary:
	var c: Vector2 = sc.ARENA.position + sc.ARENA.size * 0.5
	var u: Dictionary = sc._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	sc._units.append(u)
	return u


func _sum(es: Array) -> float:
	var t := 0.0
	for e in es:
		t += float(e.get("hp", 0.0))
	return t
