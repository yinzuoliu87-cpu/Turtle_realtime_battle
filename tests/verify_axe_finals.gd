extends Node
## verify_axe_finals.gd — 四个最终造物 (2026-09-01·方案书六期)
##
## ★需求原文(用户 2026-08-31)逐字，每条断言都能指回引用 —— 见 AxeFinalStats 头注。
##
## ★★这份门禁里最容易写假的六条：
##   ① 「无限叠加」：只验"叠了 3 层"看不出有没有上限。要叠到 200 层再量一次。
##   ② 「处决线」：只验"低于线被处决"会漏掉边界。**恰好在线上要处决、线上一点点不处决**，
##      两侧各量一次 —— 边界写错一格是这类功能最常见的 bug。
##   ③ 「独立的4秒，不打扰当前buff」：只验"再放一次还在"会被"刷新"蒙混。
##      要**先让第一层过期**，看第二层还在不在。
##   ④ 「魔法伤害」：伤害类型是接线不是颜色。给靶子堆魔抗，量它**真的被削**。
##   ⑤ 「600码内」：只验范围内吃到，不验范围外**没吃到** ⇒ 全场加血也算过。
##   ⑥ 「不再获得减伤」(炽天使)：这是需求**明确取消**的东西，要验它确实是 0，
##      不能当成"漏掉了没写"。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AV := preload("res://scripts/scenes/battle/axe_final_vfx.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk_axe(final_key: String, atk: float = 100.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", c)
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = 4
	ax["_axe_final"] = final_key
	ax["id"] = "__axe_probe__"
	ax["crit"] = 0.0
	ax["atk"] = atk
	ax["maxHp"] = 10000.0
	ax["hp"] = 5000.0
	ax["maxEnergy"] = 1000.0
	ax["energy"] = 0.0
	ax["atk_range"] = 200.0
	return ax


func _mk_foe(off: Vector2, hp: float = 100000.0, mr: float = 0.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "right", c + off)
	_s._units.append(u)
	u["id"] = "__foe_probe__"
	u["maxHp"] = hp
	u["hp"] = hp
	u["def"] = 0.0
	u["mr"] = mr
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["shield"] = 0.0
	return u


func _mk_ally(off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var a: Dictionary = _s._spawn._make_unit("basic", "left", c + off)
	_s._units.append(a)
	a["id"] = "__ally_probe__"
	a["maxHp"] = 5000.0
	a["hp"] = 1000.0
	a["maxEnergy"] = 1000.0
	a["energy"] = 0.0
	a["shield"] = 0.0
	return a


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 四个最终造物 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_table()
	_t_undead()
	_t_seraph()
	_t_holo()
	_t_ember()
	_t_vfx_curves()
	_t_real_path()

	if _n < 58:
		print("  [FAIL] ★分母: 断言只有 %d 条(<58) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 四个最终造物(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 分母: 数值表与 FINALS 一一对应
# ══════════════════════════════════════════════════════════════
func _t_table() -> void:
	print("--- ① 分母: 数值表 ---")
	var miss: Array = []
	for f in AE.FINALS:
		if not AF.STATS.has(str((f as Dictionary)["key"])):
			miss.append(str((f as Dictionary)["key"]))
	_ok("★四个造物**每一个**都在数值表里(少一个 = 那个造物没数值, 选了等于白选)",
		miss.is_empty() and AE.FINALS.size() == 4, str(miss))
	_ok("★分母: 亡灵 %.0f血/%.0f攻/%.0f甲/%.0f抗 · 环 %.0f码 · 重生 %.1f秒带 %.0f%%"
		% [AF.stat("undead", "hp"), AF.stat("undead", "atk"), AF.stat("undead", "def"),
		   AF.stat("undead", "mr"), AF.UNDEAD_RING_R, AF.UNDEAD_REVIVE_DELAY,
		   AF.UNDEAD_REVIVE_HP_PCT * 100.0],
		is_equal_approx(AF.stat("undead", "hp"), 1200.0)
		and is_equal_approx(AF.UNDEAD_RING_R, 300.0)
		and is_equal_approx(AF.UNDEAD_REVIVE_DELAY, 2.5)
		and is_equal_approx(AF.UNDEAD_REVIVE_HP_PCT, 0.40))
	_ok("★分母: 炽天使 %.0f射程 · %d层灼烧 · %d把回旋镖 · 半宽%.0f"
		% [AF.stat("seraph", "range"), AF.SERAPH_BURN_ON_HIT, AF.SERAPH_BOOMERANGS,
		   AF.SERAPH_BOOM_R],
		is_equal_approx(AF.stat("seraph", "range"), 300.0) and AF.SERAPH_BURN_ON_HIT == 8
		and AF.SERAPH_BOOMERANGS == 10 and is_equal_approx(AF.SERAPH_BOOM_R, 300.0))
	_ok("★★炽天使「**不再获得减伤**」是需求明确取消的 ⇒ 常量必须是 0(不是漏写)",
		is_equal_approx(AF.SERAPH_CHARGE_DR, 0.0))
	_ok("★分母: 全息 %.0f盾/%.0f龟能 · 阵%.0f码 每%.1f秒 回%.0f血 给%.0f龟能 +%.0f%%攻速 · 减伤%.0f%%"
		% [AF.HOLO_ONHIT_SHIELD, AF.HOLO_ONHIT_ENERGY, AF.HOLO_AURA_R, AF.HOLO_AURA_TICK,
		   AF.HOLO_AURA_HEAL, AF.HOLO_AURA_ENERGY, AF.HOLO_AURA_ASPD * 100.0, AF.HOLO_PLANT_DR * 100.0],
		is_equal_approx(AF.HOLO_ONHIT_SHIELD, 60.0) and is_equal_approx(AF.HOLO_AURA_R, 600.0)
		and is_equal_approx(AF.HOLO_AURA_TICK, 0.5) and is_equal_approx(AF.HOLO_AURA_HEAL, 100.0)
		and is_equal_approx(AF.HOLO_AURA_ASPD, 0.30) and is_equal_approx(AF.HOLO_PLANT_DR, 0.30))
	_ok("★分母: 余烬 %.0f攻/+%.0f%%攻速/+%.0f%%移速 · 每层%.1f%%处决线 · 处决+%.0f龟能 · 光%.0f秒"
		% [AF.stat("ember", "atk"), AF.stat("ember", "aspd_pct") * 100.0,
		   AF.stat("ember", "move_pct") * 100.0, AF.EMBER_SEED_EXEC_PCT * 100.0,
		   AF.EMBER_EXEC_ENERGY, AF.EMBER_LIGHT_TIME],
		is_equal_approx(AF.stat("ember", "atk"), 80.0)
		and is_equal_approx(AF.stat("ember", "aspd_pct"), 0.80)
		and is_equal_approx(AF.EMBER_SEED_EXEC_PCT, 0.005)
		and is_equal_approx(AF.EMBER_EXEC_ENERGY, 150.0))


# ══════════════════════════════════════════════════════════════
#  ② 亡灵之斧
# ══════════════════════════════════════════════════════════════
func _t_undead() -> void:
	print("--- ② 亡灵之斧 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("undead")
	## 属性折进去了没有
	var raw_hp: float = float(ax["maxHp"])
	var probe: Dictionary = _mk_axe("")
	probe["maxHp"] = 10000.0
	fin.apply_stats(probe, "undead")
	_ok("★登场折进 +%.0f 最大生命(%.0f → %.0f)" % [AF.stat("undead", "hp"), 10000.0, probe["maxHp"]],
		is_equal_approx(float(probe["maxHp"]), 10000.0 + AF.stat("undead", "hp")))

	## 环内/环外
	var inside: Dictionary = _mk_foe(Vector2(100, 0), 200000.0)
	var outside: Dictionary = _mk_foe(Vector2(AF.UNDEAD_RING_R + 200.0, 0), 200000.0)
	var hp_in0: float = float(inside["hp"])
	var hp_out0: float = float(outside["hp"])
	ax["hp"] = 5000.0
	var n: int = fin.undead_ring_tick(ax)
	_ok("★分母: 环内数到 %d 个敌人" % n, n == 1, "环 %.0f 码" % AF.UNDEAD_RING_R)
	_ok("★★环内那个真的掉血了(%.0f → %.0f)" % [hp_in0, float(inside["hp"])],
		float(inside["hp"]) < hp_in0)
	_ok("★★★环外那个【一点没掉】(只验环内吃到 = 全场掉血也算过)",
		is_equal_approx(float(outside["hp"]), hp_out0),
		"%.0f → %.0f" % [hp_out0, float(outside["hp"])])
	_ok("★★吸血 = %.1f%% 最大生命 × 环内人数(5000 → %.0f)"
		% [AF.UNDEAD_LEECH_PCT * 100.0, float(ax["hp"])],
		float(ax["hp"]) > 5000.0)

	## ★★魔法伤害要吃魔抗 —— 伤害类型是接线不是颜色
	var soft: Dictionary = _mk_foe(Vector2(60, 0), 100000.0, 0.0)
	var hard: Dictionary = _mk_foe(Vector2(-60, 0), 100000.0, 200.0)
	var s0: float = float(soft["hp"])
	var h0: float = float(hard["hp"])
	fin.undead_ring_tick(ax)
	var d_soft: float = s0 - float(soft["hp"])
	var d_hard: float = h0 - float(hard["hp"])
	_ok("★★★环是【魔法伤害】: 200 魔抗那个掉得更少(%.0f vs %.0f)" % [d_hard, d_soft],
		d_hard < d_soft - 0.5 and d_soft > 1.0, "分母: 无抗的掉了 %.0f(必须 >1)" % d_soft)

	## 重生
	var ux: Dictionary = _mk_axe("undead")
	ux["maxHp"] = 10000.0
	ux["alive"] = false
	ux["hp"] = 0.0
	_ok("★死后安排了重生", fin.undead_on_death(ux))
	_ok("★分母: 还没到 %.1f 秒时不站起来" % AF.UNDEAD_REVIVE_DELAY, not fin.undead_tick_revive(ux))
	ux["_axe_revive_at"] = _s._t - 0.01
	_ok("★★到点站起来了", fin.undead_tick_revive(ux) and ux.get("alive", false))
	_ok("★★带 %.0f%% 最大生命回来(实测 %.0f / %.0f)"
		% [AF.UNDEAD_REVIVE_HP_PCT * 100.0, float(ux["hp"]), float(ux["maxHp"])],
		is_equal_approx(float(ux["hp"]), 10000.0 * AF.UNDEAD_REVIVE_HP_PCT))
	ux["alive"] = false
	_ok("★★一场只重生一次(第二次不再安排)", not fin.undead_on_death(ux))
	## ★不做死亡动画(用户两次点名) —— 焊在这里, 六期不许破坏
	var rb_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var i_d: int = rb_src.find("const ACTION_DEATH := {")
	var body_d: String = rb_src.substr(i_d, rb_src.find("}", i_d) - i_d) if i_d >= 0 else ""
	_ok("★★★重生**不靠死亡动画**: ACTION_DEATH 里仍然没有 axe(用户两次点名不要)",
		body_d != "" and not body_d.contains("axe"), "分母: 表解析到 %d 字" % body_d.length())


# ══════════════════════════════════════════════════════════════
#  ③ 炽天使
# ══════════════════════════════════════════════════════════════
func _t_seraph() -> void:
	print("--- ③ 炽天使 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("seraph")
	var probe: Dictionary = _mk_axe("")
	probe["atk_range"] = 120.0
	probe["melee"] = true
	fin.apply_stats(probe, "seraph")
	_ok("★★射程**设成** %.0f 而不是加 %.0f(近战 120 加 300 会变成 420)"
		% [AF.stat("seraph", "range"), AF.stat("seraph", "range")],
		is_equal_approx(float(probe["atk_range"]), AF.stat("seraph", "range"))
		and not bool(probe.get("melee", true)))

	var foe: Dictionary = _mk_foe(Vector2(120, 0))
	fin.seraph_on_hit(ax, foe)
	var burn: int = int((foe.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_ok("★★普攻附带 %d 层灼烧(实测 %d)" % [AF.SERAPH_BURN_ON_HIT, burn],
		burn >= AF.SERAPH_BURN_ON_HIT)

	## 回旋镖: 直线上的吃到、身后的不吃
	var front: Dictionary = _mk_foe(Vector2(400, 60))
	var behind: Dictionary = _mk_foe(Vector2(-400, 0))
	var far_side: Dictionary = _mk_foe(Vector2(400, AF.SERAPH_BOOM_R + 200.0))
	var f0: float = float(front["hp"])
	var b0: float = float(behind["hp"])
	var s0: float = float(far_side["hp"])
	var hit: int = fin.seraph_boomerang_settle(ax, Vector2.RIGHT)
	_ok("★分母: 回旋镖命中 %d 个" % hit, hit >= 1)
	_ok("★★正前方那个掉血了(%.0f → %.0f)" % [f0, float(front["hp"])], float(front["hp"]) < f0)
	_ok("★★★身后那个【一点没掉】(「直直飞过」是单向的)",
		is_equal_approx(float(behind["hp"]), b0))
	_ok("★★★横向超出半宽 %.0f 的那个也没掉" % AF.SERAPH_BOOM_R,
		is_equal_approx(float(far_side["hp"]), s0))
	var fb: int = int((front.get("dot_stacks", {}) as Dictionary).get("burn", 0))
	_ok("★回旋镖命中也加 %d 层灼烧(实测 %d)" % [AF.SERAPH_BOOM_BURN, fb], fb >= AF.SERAPH_BOOM_BURN)
	## ★分母: 换成别的造物, 同一个调用什么都不该发生
	var other: Dictionary = _mk_axe("holo")
	var f1: float = float(front["hp"])
	_ok("★★分母: 换成全息斧, 同一个 seraph_boomerang_settle 一个都打不到",
		fin.seraph_boomerang_settle(other, Vector2.RIGHT) == 0
		and is_equal_approx(float(front["hp"]), f1))


# ══════════════════════════════════════════════════════════════
#  ④ 全息斧
# ══════════════════════════════════════════════════════════════
func _t_holo() -> void:
	print("--- ④ 全息斧 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("holo")
	var probe: Dictionary = _mk_axe("")
	fin.apply_stats(probe, "holo")
	_ok("★登场折进 +%.0f 最大生命 · %.0f%% 龟能充能速率登记在表里"
		% [AF.stat("holo", "hp"), AF.stat("holo", "energy_rate_pct") * 100.0],
		is_equal_approx(AF.stat("holo", "energy_rate_pct"), 0.50))

	## 普攻: 给【血量最低的】友军
	var low: Dictionary = _mk_ally(Vector2(80, 0))
	low["hp"] = 100.0
	var high: Dictionary = _mk_ally(Vector2(-80, 0))
	high["hp"] = 4900.0
	var got = fin.holo_on_hit(ax)
	_ok("★★挑中的是【血量最低】那个(不是最近的/第一个)", is_same(got, low),
		"低血 %.0f/%.0f vs 高血 %.0f/%.0f" % [low["hp"], low["maxHp"], high["hp"], high["maxHp"]])
	_ok("★给了 %.0f 护盾 + %.0f 龟能(实测 盾%.0f 能%.0f)"
		% [AF.HOLO_ONHIT_SHIELD, AF.HOLO_ONHIT_ENERGY, float(low.get("shield", 0.0)),
		   float(low.get("energy", 0.0))],
		float(low.get("shield", 0.0)) >= AF.HOLO_ONHIT_SHIELD
		and is_equal_approx(float(low.get("energy", 0.0)), AF.HOLO_ONHIT_ENERGY))

	## 法阵: 范围内吃到、范围外没吃到
	var near: Dictionary = _mk_ally(Vector2(200, 0))
	near["hp"] = 1000.0
	var far: Dictionary = _mk_ally(Vector2(AF.HOLO_AURA_R + 300.0, 0))
	far["hp"] = 1000.0
	far["energy"] = 0.0
	var n: int = fin.holo_aura_tick(ax)
	_ok("★分母: 法阵这一跳照顾到 %d 个友军" % n, n >= 1)
	_ok("★★范围内那个回了 %.0f 血(1000 → %.0f)" % [AF.HOLO_AURA_HEAL, float(near["hp"])],
		float(near["hp"]) > 1000.0)
	_ok("★★★范围外(%.0f 码)那个【一点没回、也没拿到龟能】—— 只验范围内吃到 = 全场加血也算过"
		% AF.HOLO_AURA_R,
		is_equal_approx(float(far["hp"]), 1000.0) and is_equal_approx(float(far.get("energy", 0.0)), 0.0),
		"血 %.0f 能 %.0f" % [float(far["hp"]), float(far.get("energy", 0.0))])
	_ok("★★范围内那个拿到 +%.0f%% 攻速" % (AF.HOLO_AURA_ASPD * 100.0),
		is_equal_approx(float(near.get("haste_mult", 1.0)), 1.0 + AF.HOLO_AURA_ASPD)
		and float(near.get("haste_until", 0.0)) > _s._t)


# ══════════════════════════════════════════════════════════════
#  ⑤ 余烬
# ══════════════════════════════════════════════════════════════
func _t_ember() -> void:
	print("--- ⑤ 余烬 ---")
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("ember")

	## ★★「无限叠加」—— 只验叠 3 层看不出有没有上限
	_ok("★处决线 = 层数 × %.1f%%: 10 层 = %.0f%%"
		% [AF.EMBER_SEED_EXEC_PCT * 100.0, AF.ember_exec_pct(10) * 100.0],
		is_equal_approx(AF.ember_exec_pct(10), 0.05))
	_ok("★★★真的**无上限**: 200 层 = %.0f%%(封顶的实现在这里会露馅)"
		% (AF.ember_exec_pct(200) * 100.0),
		is_equal_approx(AF.ember_exec_pct(200), AF.EMBER_SEED_EXEC_PCT * 200.0))

	## ★★处决线的两侧边界
	var mh := 10000.0
	var line: float = mh * AF.ember_exec_pct(10)
	_ok("★★恰好在线上(%.0f)【要】处决 —— 边界含等号" % line,
		AF.ember_should_execute(line, mh, 10))
	_ok("★★★线上一点点(%.0f)【不】处决 —— 边界写错一格就在这里露馅" % (line + 1.0),
		not AF.ember_should_execute(line + 1.0, mh, 10))
	_ok("★分母: 0 层时任何血量都不处决(没打过就不该被斩)",
		not AF.ember_should_execute(1.0, mh, 0))

	## 命中挂种子
	var foe: Dictionary = _mk_foe(Vector2(90, 0), 10000.0)
	var r1: Dictionary = fin.ember_on_hit(ax, foe)
	_ok("★命中挂 1 层种子(实测 %d)" % int(r1["stacks"]), int(r1["stacks"]) == 1)
	_ok("★分母: 满血时不处决", not bool(r1["executed"]))
	## 堆够层数 + 压低血量 → 处决
	foe["_ember_seeds"] = 39
	foe["hp"] = 10000.0 * 0.19          # 40 层 = 20% 线, 19% 在线下
	ax["energy"] = 0.0
	var r2: Dictionary = fin.ember_on_hit(ax, foe)
	_ok("★★40 层(线 %.0f%%)时 19%% 血被处决" % (AF.ember_exec_pct(40) * 100.0),
		bool(r2["executed"]), "层数 %d" % int(r2["stacks"]))
	_ok("★★处决之后召唤物 +%.0f 龟能(实测 %.0f)" % [AF.EMBER_EXEC_ENERGY, float(ax["energy"])],
		is_equal_approx(float(ax["energy"]), AF.EMBER_EXEC_ENERGY))

	## ★★★余烬之光: 独立叠加, 不是刷新
	var bx: Dictionary = _mk_axe("ember")
	_ok("★分母: 起手 0 层光", fin.ember_light_stacks(bx) == 0)
	fin.ember_light_cast(bx)
	_ok("★放一次 = 1 层, 且 buff 真的挂上了(减伤 %.0f%% / 免控)"
		% (AF.EMBER_LIGHT_DR * 100.0),
		fin.ember_light_stacks(bx) == 1
		and is_equal_approx(float(bx.get("damage_reduction", 0.0)), AF.EMBER_LIGHT_DR)
		and bool(bx.get("cc_immune", false)))
	fin.ember_light_cast(bx)
	_ok("★★再放一次 = 2 层(是**叠加**不是刷新)", fin.ember_light_stacks(bx) == 2)
	## ★★★关键: 让第一层过期, 第二层必须还在 —— "刷新"的实现在这里会掉到 0
	var arr: Array = bx["_ember_lights"]
	arr[0] = _s._t - 0.01               # 第一层已过期
	bx["_ember_lights"] = arr
	fin.ember_light_tick(bx)
	_ok("★★★第一层过期后第二层**还在**(刷新式实现在这里会变 0)",
		fin.ember_light_stacks(bx) == 1 and bool(bx.get("cc_immune", false)),
		"实测 %d 层" % fin.ember_light_stacks(bx))
	## ★多层【只延长在线时间, 不叠强度】—— 这条最容易做反
	_ok("★★两层时减伤仍是 %.0f%% 而不是翻倍(需求说的是「独立的4秒」, 不是效果叠乘)"
		% (AF.EMBER_LIGHT_DR * 100.0),
		is_equal_approx(float(bx.get("damage_reduction", 0.0)), AF.EMBER_LIGHT_DR))
	## 全部过期 → buff 干净落地
	arr = bx["_ember_lights"]
	for i in range(arr.size()):
		arr[i] = _s._t - 1.0
	bx["_ember_lights"] = arr
	fin.ember_light_tick(bx)
	_ok("★★全部过期后减伤/免控【还原】(不许留一个永久无敌的怪物)",
		fin.ember_light_stacks(bx) == 0
		and is_equal_approx(float(bx.get("damage_reduction", 0.0)), 0.0)
		and not bool(bx.get("cc_immune", true)))


# ══════════════════════════════════════════════════════════════
#  ⑥ 特效的【曲线形状】—— 这是本仓库对"特效也能被门禁守住"的答案
# ══════════════════════════════════════════════════════════════
## ★演出本身没法断言"好不好看", 但**运动曲线的性质可以被量**:
##   单调性 / 端点 / 值域 / 前后段快慢。照 arcane_eq_vfx 的先例(rise_frac 那一段)。
## ★这些函数是 static 纯函数 —— 不建节点、不等 tween, 门禁直接调。
func _t_vfx_curves() -> void:
	print("--- ⑥ 特效曲线 ---")
	## hold_fade: 前 70% 满亮, 后 30% 才淡 —— 防"淡出病"(一出生就淡 ⇒ 实拍读成土棕/灰)
	_ok("★★hold_fade 前 70%% 是**满亮**(0→1.0 / 0.7→1.0), 不是一出生就淡",
		is_equal_approx(AV.hold_fade(0.0), 1.0) and is_equal_approx(AV.hold_fade(0.7), 1.0))
	_ok("★hold_fade 末端归零(1.0 → 0)", is_equal_approx(AV.hold_fade(1.0), 0.0))
	var mono := true
	var prev := 2.0
	for i in range(41):
		var v: float = AV.hold_fade(float(i) / 40.0)
		if v > prev + 0.0001:
			mono = false
		prev = v
	_ok("★hold_fade 全程单调不增(41 个采样点)", mono)
	## ★★分母: 线性淡出在这里会红 —— 证明这条判据卡得住"淡出病"那个形状
	_ok("★★分母: 线性淡出(1-t)在 0.7 处只有 0.30, 与本曲线的 1.0 分得开",
		absf(AV.hold_fade(0.7) - (1.0 - 0.7)) > 0.5)

	## ring_breath: 常驻环要"活着"而不是闪一下
	var in_range := true
	for i in range(60):
		var b: float = AV.ring_breath(float(i) * 0.05)
		if b > 1.0001 or b < 0.94 - 0.0001:
			in_range = false
	_ok("★环呼吸恒在 [0.94, 1.0] 内(60 个采样点), 不会缩成一点也不会撑爆",
		in_range and is_equal_approx(AV.ring_breath(0.0), 1.0))

	## boomerang: 10 把在 4 秒里均匀铺开
	var ts: Array = []
	for i in range(AF.SERAPH_BOOMERANGS):
		ts.append(AV.boomerang_launch_t(i, AF.SERAPH_BOOMERANGS, AF.SERAPH_CAST_TIME))
	var inc := true
	for i in range(1, ts.size()):
		if float(ts[i]) <= float(ts[i - 1]):
			inc = false
	_ok("★★%d 把回旋镖的出手时刻**严格递增**且第一把在 0(实测 %s…)"
		% [AF.SERAPH_BOOMERANGS, str(ts.slice(0, 3))],
		inc and is_equal_approx(float(ts[0]), 0.0))
	_ok("★★最后一把也在 %.1f 秒之内出手(实测 %.2f) —— 出手时刻超出总时长 = 有几把永远不出"
		% [AF.SERAPH_CAST_TIME, float(ts[-1])], float(ts[-1]) < AF.SERAPH_CAST_TIME)
	_ok("★「直直飞过」是匀速: frac(半程)=0.5 而不是加速/减速",
		is_equal_approx(AV.boomerang_frac(0.5, 1.0), 0.5))

	## aura_pulse: 跳的那一刻最亮, 让"每 0.5 秒一跳"看得出节拍
	_ok("★法阵脉冲: 跳的那一刻最亮(1.0), 拍尾落到底(0.35)",
		is_equal_approx(AV.aura_pulse(0.0), 1.0) and is_equal_approx(AV.aura_pulse(1.0), 0.35))
	var pm := true
	var pv := 2.0
	for i in range(21):
		var a2: float = AV.aura_pulse(float(i) / 20.0)
		if a2 > pv + 0.0001:
			pm = false
		pv = a2
	_ok("★法阵脉冲单调衰减(21 个采样点)", pm)

	## revive_gather: 前慢后快(三次方) —— 线性的话读不出"聚拢"
	_ok("★重生聚拢 端点对(0→0 / 1→1)",
		is_equal_approx(AV.revive_gather(0.0), 0.0) and is_equal_approx(AV.revive_gather(1.0), 1.0))
	_ok("★★★重生是**前慢后快**: 走到一半时间只聚拢了 %.0f%%(线性会是 50%%)"
		% (AV.revive_gather(0.5) * 100.0), AV.revive_gather(0.5) < 0.30,
		"线性实现在这里会红")

	## seed_glow: 无上限的层数 → 有上限的视觉
	_ok("★种子火星浓度随层数涨(1 层 %.2f < 15 层 %.2f)"
		% [AV.seed_glow(1), AV.seed_glow(15)], AV.seed_glow(1) < AV.seed_glow(15))
	_ok("★★视觉浓度**封顶**(200 层与 30 层一样浓, 否则叠满是一团纯白)",
		is_equal_approx(AV.seed_glow(200), 1.0) and is_equal_approx(AV.seed_glow(30), 1.0))

	## ★★演出接在结算之后(§3.5): 源码守卫 —— 数值不许埋进 tween 链
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_final_forms.gd")
	_ok("★★结算文件里【不出现】tween —— 数值全是同步的, 演出只在 axe_final_vfx 里",
		not src.contains("_reg_tween") and not src.contains("create_tween"),
		"分母: 源码 %d 字" % src.length())
	_ok("★分母: 结算文件确实调了演出(vfx.xxx), 否则上面那条是空检查",
		src.contains("vfx."))


# ══════════════════════════════════════════════════════════════
#  ⑦ ★★走【真入口】—— 造物的主动到底放不放得出来
# ══════════════════════════════════════════════════════════════
## 由来(2026-09-01): 零调用者扫描抓到 —— `undead_on_death` / `seraph_boomerang_settle` /
## `holo_aura_tick` / `ember_light_cast` **产品代码里一个调用者都没有**。
## 也就是说四个造物的主动**一个都放不出来**, 而上面 64 条门禁全绿 ——
## 因为它们直接调那些函数, 从没证明"游戏里真的会走到"。
## (memory [[fb-verify-must-run-the-real-path]]: 断言函数存在 ≠ 还有没有人调)
##
## ⇒ 这一节**只从 `AxeSystem.tick` 进去**, 不碰 `_fin.*`。
func _t_real_path() -> void:
	print("--- ⑦ 走真入口 ---")
	var axs = _s._equip_sys._axe
	## 造一个"携带者 + 斧头"的最小场: tick 的入口参数是**携带者**, 不是斧头
	for cs in [["seraph", "_seraph_until"], ["holo", "_holo_until"]]:
		var fk: String = str(cs[0])
		var flag: String = str(cs[1])
		var ax: Dictionary = _mk_axe(fk)
		ax["maxEnergy"] = AE.ACTIVE_ENERGY
		ax["energy"] = AE.ACTIVE_ENERGY          # 龟能满 ⇒ 主动该放了
		ax["hp"] = 3000.0
		var owner: Dictionary = _mk_axe("")
		owner["_axe_ref"] = ax
		_mk_foe(Vector2(200, 0))
		axs.tick(owner, 0.016)                   # ★真入口
		_ok("★★%s: 从 AxeSystem.tick 进去, 主动**真的起来了**(标记 %s)" % [fk, flag],
			ax.has(flag), "龟能 %.0f" % float(ax.get("energy", -1)))
	## 余烬: 主动 = 立刻起一个 4 秒 buff(不是蓄力)
	var ex: Dictionary = _mk_axe("ember")
	ex["maxEnergy"] = AE.ACTIVE_ENERGY
	ex["energy"] = AE.ACTIVE_ENERGY
	ex["hp"] = 3000.0
	var eo: Dictionary = _mk_axe("")
	eo["_axe_ref"] = ex
	axs.tick(eo, 0.016)
	_ok("★★余烬: 从真入口进去后余烬之光**真的挂上了**(层数 %d · 免控 %s)"
		% [_s._equip_sys._axe._fin.ember_light_stacks(ex), str(ex.get("cc_immune", false))],
		_s._equip_sys._axe._fin.ember_light_stacks(ex) >= 1 and bool(ex.get("cc_immune", false)))
	## ★分母: 没有造物时仍然走**被动6的猛砸**(不能因为加了造物就把原路径弄丢)
	var nx: Dictionary = _mk_axe("")
	nx["_axe_pv"] = 4
	nx["maxEnergy"] = AE.ACTIVE_ENERGY
	nx["energy"] = AE.ACTIVE_ENERGY
	nx["hp"] = 3000.0
	var no: Dictionary = _mk_axe("")
	no["_axe_ref"] = nx
	axs.tick(no, 0.016)
	_ok("★★★分母: 没有造物时仍走被动6的梯形蓄力(原路径没被造物挤掉)",
		_s._equip_sys._axe._pas.is_charging(nx), "在蓄力=%s" % str(_s._equip_sys._axe._pas.is_charging(nx)))
	## ★炽天使真的会**一把一把甩** —— 推时间, 数它甩了几把
	var sx: Dictionary = _mk_axe("seraph")
	sx["maxEnergy"] = AE.ACTIVE_ENERGY
	sx["energy"] = AE.ACTIVE_ENERGY
	sx["hp"] = 3000.0
	var so: Dictionary = _mk_axe("")
	so["_axe_ref"] = sx
	var tgt: Dictionary = _mk_foe(Vector2(260, 0), 1.0e9)
	axs.tick(so, 0.016)
	var hp0: float = float(tgt["hp"])
	var thrown := 0
	for i in range(60):
		sx["_seraph_next"] = _s._t - 0.001       # 把"下一把"的时刻拨到过去 = 该甩了
		var before: int = int(sx.get("_seraph_left", 0))
		axs.tick(so, 0.016)
		if int(sx.get("_seraph_left", 0)) < before:
			thrown += 1
		if not sx.has("_seraph_until"):
			break
	_ok("★★炽天使从真入口一共甩了 %d 把(需求是 %d 把, 甩完自己收工)"
		% [thrown, AF.SERAPH_BOOMERANGS], thrown == AF.SERAPH_BOOMERANGS)
	_ok("★★这 %d 把真的打到人了(目标掉血 %.0f)" % [thrown, hp0 - float(tgt["hp"])],
		float(tgt["hp"]) < hp0)
	## ★全息斧: 插地期间有 30% 减伤, **到期必须还原**
	var hx: Dictionary = _mk_axe("holo")
	hx["maxEnergy"] = AE.ACTIVE_ENERGY
	hx["energy"] = AE.ACTIVE_ENERGY
	hx["hp"] = 3000.0
	var ho: Dictionary = _mk_axe("")
	ho["_axe_ref"] = hx
	axs.tick(ho, 0.016)
	_ok("★全息插地期间拿到 %.0f%% 减伤" % (AF.HOLO_PLANT_DR * 100.0),
		is_equal_approx(float(hx.get("damage_reduction", 0.0)), AF.HOLO_PLANT_DR))
	hx["_holo_until"] = _s._t - 0.01            # 拨到过期
	axs.tick(ho, 0.016)
	_ok("★★★插地到期后减伤**还原**(不还原就是个永久 30%% 减伤的怪物)",
		is_equal_approx(float(hx.get("damage_reduction", 0.0)), 0.0),
		"实测 %.2f" % float(hx.get("damage_reduction", 0.0)))
	## ★零调用者守卫: 四个曾经"写了没人读"的函数, 现在必须在产品里可达
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_final_forms.gd")
	var sys_src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/axe_system.gd")
	var eq_src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_ok("★★造物主动的分派器被 AxeSystem 真的调了(begin_active / tick_active / active_busy)",
		sys_src.contains("_fin.begin_active(") and sys_src.contains("_fin.tick_active(")
		and sys_src.contains("_fin.active_busy("))
	_ok("★★亡灵重生挂在 on-death 上(之前 undead_on_death 零调用者 = 死了根本不会重生)",
		eq_src.contains("undead_on_death("))
	var dead: Array = []
	for fn in ["seraph_boomerang_settle", "holo_aura_tick", "ember_light_cast"]:
		if src.count(fn) < 2:                     # 定义 1 次 + 至少被调 1 次
			dead.append(fn)
	_ok("★★这三个曾经零调用者的函数现在**在文件内被分派器调到**(分母: 每个至少出现 2 次)",
		dead.is_empty(), str(dead))