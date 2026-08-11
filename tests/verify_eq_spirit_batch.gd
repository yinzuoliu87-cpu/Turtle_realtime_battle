extends Node
## verify_eq_spirit_batch.gd — 【灵物 5 件·用户逐件重做版】逐件焊死 + 演出物理不变量
##   060 磷光水母伞 · 061 钻孔螺 · 062 螳螂虾钳 · 063 白鲸气环 · 064 溺者的浮囊
##
## 规格事实源: docs/plans/20260805-装备逐件重做.md **§0.5 已定稿**(用户当场拍板的决定)。
## 实装契约: docs/plans/20260805-实装契约.md §7。
##
## ★本文件的规矩(逐条对应 CLAUDE.md / memory / 契约 §7):
##   · 需求字面值**直接写在断言里**, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 全部用【干净合成单位】(不用随机 spawn 的敌: 带盾/flat_dr/未播种 RNG 会 CI 偶发红)。
##   · 合成单位坐标放在 ARENA 【内】—— 放外面会被钳到同一点。
##   · 触发一律走【真入口】(_eq_on_hit / _eq_on_dodge / _eq_on_cast / tick_unit / _spec),
##     并且至少各有一条【经中央伤害管线 _apply_damage_from 的端到端】断言。
##   · **不依赖任何演出 tween / 弹道飞完**(CLAUDE.md §3.5)。演出形态由纯函数 + `apply_at` 同步写。
##   · 每条断言打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 容差 `< 0.51`(整数取整)或严格相等 —— 批② 曾抄成 `< 1.01`, 把 60 改成 61 一条都不红。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_spirit_batch.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SVX := preload("res://scripts/scenes/battle/spirit_eq_vfx.gd")

## ★演出物理量的期望值全部写成【独立算出来的字面量】, 不调被测的 static func。
const E_CONST := 2.718281828459045
## 二阶欠阻尼(ζ=0.28): 超调 Mp = e^(−ζπ/√(1−ζ²))
const WANT_OVERSHOOT := 0.39999714984100704
## 峰值时刻 tp = π/ω_d, ω_d = 12·√(1−0.28²) = 11.5136...
const WANT_PEAK_T := 0.27270769562411401
## 对数减缩 δ = 2πζ/√(1−ζ²)
const WANT_LOGDEC := 1.8325957145940464
## Paris: â(N) = (1−20/24)/(1−N/24) ⇒ 1/â(N) = 6 − N/4
const WANT_INVA_SLOPE := -0.25
const WANT_INVA_B := 6.0
## Rayleigh 2/5 尺度不变: R(1−k·s)/R(1−s) = k^0.4
const WANT_K4_04 := 1.7411011265922482      # 4^0.4
## 段②峰 / 段①峰 = ln(R_MIN^−2) / ln(2^2) = ln(277.777…)/ln(4)
const WANT_FLASH_RATIO := 4.058893689053568
## 涡环: R₀=0.42, R(t)² = R₀² + (1−R₀²)·t/LIFE ⇒ R² 对 t 严格线性
const WANT_RING_R0 := 0.42
## 063 覆盖率 = 0.03 / 0.075
const WANT_COVERAGE := 0.40

var _n := 0
var _fail := 0
var _s = null
var _eq = null
var _sp = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位。★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害
##   +20%, 拿 basic 当携带者去验精确数值会量到 ×1.2(批①/批② 两份门禁都实测过这个坑)。
func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
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
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["breach_stacks"] = 0
	u["whale_rings"] = 0
	_s._units.append(u)
	return u


## 只挂条目(不跑属性管线 —— 属性会污染"效果加了多少"的量测)
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 挂条目 + 跑【常驻字段】管线(060/064 的每帧钩靠它开)
func _equip_flags(u: Dictionary, iid: String, star: int) -> Dictionary:
	_equip(u, iid, star)
	_s._equip_sys._stats._eq_apply_flags(u, iid, star)
	return u


func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


func _has_curse(u: Dictionary) -> bool:
	for d in u.get("dots", []):
		if d is Dictionary and str((d as Dictionary).get("tag", "")) == "curse":
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 灵物 5 件(用户逐件重做版) ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准
	_eq = _s._equip_sys
	_sp = _eq._spirit_sys

	_t_wiring()
	_t_basic_gate()
	_t060_parasol()
	_t061_drill()
	_t062_mantis()
	_t063_whale()
	_t064_bladder()
	_t_phys_060()
	_t_phys_061()
	_t_phys_062()
	_t_phys_063()
	_t_phys_064()
	await _t_vfx_nodes()

	_s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 灵物 5 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律 / 接线 / 旧效果确实拆干净了
# ─────────────────────────────────────────────────────────────
func _t_wiring() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var applyc: String = _strip("res://scripts/systems/equip/equip_stats_apply.gd")
	_ok("⓪ ★分母: equip_system 源码读得到(%d 字符)" % code.length(), code.length() > 50000,
		"len=%d" % code.length())
	_ok("⓪ ★接线: battle._equip_sys._spirit_sys 真的 new 出来了", _sp != null)

	var hit: String = _fn_body(code, "func _eq_on_hit")
	_ok("⓪ ★分母: _eq_on_hit 函数体非空(%d 字符)" % hit.length(), hit.length() > 200)
	var miss: Array = []
	for pair in [["p2eq_061", "_eq_drill_snail"], ["p2eq_062", "_eq_mantis_strike"],
			["p2eq_063", "_eq_whale_ring"]]:
		if not hit.contains("\"%s\": _spirit_sys.%s(" % [pair[0], pair[1]]):
			miss.append("%s→%s" % [pair[0], pair[1]])
	_ok("⓪ 061/062/063 挂在 _eq_on_hit 上且写成 \"id\": _sys._fn( 形状", miss.is_empty(), str(miss))

	var dg: String = _fn_body(code, "func _eq_on_dodge")
	_ok("⓪ 062 挂在 _eq_on_dodge 上", dg.contains("\"p2eq_062\": _spirit_sys._eq_mantis_ready("),
		"len=%d" % dg.length())
	var ct: String = _fn_body(code, "func _eq_on_cast")
	_ok("⓪ 063 挂在 _eq_on_cast 上", ct.contains("\"p2eq_063\": _spirit_sys._eq_whale_haste("),
		"len=%d" % ct.length())
	var tk: String = _fn_body(code, "func _eq_tick")
	_ok("⓪ ★★接线: _eq_tick 每帧真的调 _spirit_sys.tick_unit(060 相位 / 064 血线全靠它)",
		tk.contains("_spirit_sys.tick_unit("), "len=%d" % tk.length())
	_ok("⓪ ★★接线: 主场景每帧真的调 _eq_tick(否则上面那条全绿而游戏里一次都不跳)",
		_strip("res://scripts/scenes/RealtimeBattle3DScene.gd").contains("_equip_sys._eq_tick(u, delta)"))
	_ok("⓪ 060/064 的常驻字段在 _eq_apply_flags 里写了",
		applyc.contains("u[\"_parasol_si\"]") and applyc.contains("u[\"_bladder_si\"]"))

	# ── 旧效果确实整条拆掉了(留着 = 新旧同时生效) ──
	_ok("⓪ ★旧 062 雾行海葵的 _eq_mist_anemone 已删干净", not code.contains("_eq_mist_anemone"))
	_ok("⓪ ★旧 064 深渊招魂螺的 _eq_abyss_conch_on_death 已删干净",
		not code.contains("_eq_abyss_conch_on_death"))
	_ok("⓪ ★旧 062 已从周期表 EQ_IV_BATCH1 摘掉(它不再是周期类)",
		not EquipSystem.EQ_IV_BATCH1.has("p2eq_062"),
		"表里现有 %d 件" % EquipSystem.EQ_IV_BATCH1.size())
	# ★分母口径 2026-08-06 改: 原来点名 077 当"还活着的周期件", 但批④ 已把 077 改成
	#   【登场召唤小手枪】、从这张表摘掉了 ⇒ 换成点名 067/075 这两件仍是真周期件的。
	_ok("⓪ ★分母: EQ_IV_BATCH1 里其余周期件还在(证明上面那条不是因为表空了)",
		EquipSystem.EQ_IV_BATCH1.has("p2eq_067") and EquipSystem.EQ_IV_BATCH1.has("p2eq_075")
			and EquipSystem.EQ_IV_BATCH1.size() >= 2,
		"表里 %d 件: %s" % [EquipSystem.EQ_IV_BATCH1.size(), str(EquipSystem.EQ_IV_BATCH1.keys())])
	_ok("⓪ ★旧 063 的免死标记 _ink_sac 已零写入(063 现在是白鲸气环)",
		not applyc.contains("u[\"_ink_sac\"] = true"))

	# ── 属性表(EquipStats.STATS 是装备属性的真事实源) ──
	var st: Dictionary = _s.EquipStats.STATS
	_ok("060 3★ 属性 = 护甲19 + 魔抗19(用户 §0.5「改为给护甲和魔抗」)",
		int(st["p2eq_060"][2].get("def", 0)) == 19 and int(st["p2eq_060"][2].get("mr", 0)) == 19,
		str(st["p2eq_060"][2]))
	_ok("061 属性 = 射程+50(三星同值) + 攻速 15/30/50%(用户范例「装备3」原话)",
		int(st["p2eq_061"][0].get("_rangeAdd", 0)) == 50
		and int(st["p2eq_061"][2].get("_rangeAdd", 0)) == 50
		and int(st["p2eq_061"][0].get("_aspdPct", 0)) == 15
		and int(st["p2eq_061"][1].get("_aspdPct", 0)) == 30
		and int(st["p2eq_061"][2].get("_aspdPct", 0)) == 50, str(st["p2eq_061"]))
	_ok("062 属性 = 攻击力 + 移速(用户 §0.5)",
		st["p2eq_062"][2].has("atk") and st["p2eq_062"][2].has("_mspdPct"), str(st["p2eq_062"][2]))
	_ok("063 属性 = 攻速 + 暴击率(用户 §0.5)",
		st["p2eq_063"][2].has("_aspdPct") and st["p2eq_063"][2].has("crit"), str(st["p2eq_063"][2]))
	_ok("064 属性 = 生命 + 龟能充能速率(用户 §0.5)",
		st["p2eq_064"][2].has("hp") and st["p2eq_064"][2].has("_echargePct"), str(st["p2eq_064"][2]))


# ─────────────────────────────────────────────────────────────
# 060 磷光水母伞: 每 7 秒开伞 2.5 秒(11/22/35% 减伤 + 15% 闪避, 200 码),
#                 结束时携带者回复 50/80/130, 然后才重新计时
# ─────────────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════════════════════════
# ⓪b 非普攻不触发【普攻】规格件(2026-08-11 用户报修: 赛博浮游炮/技能曾误触发钻孔螺)
#    判据走【真实伤害入口】: _apply_damage_from(无标) vs _apply_basic_hit_from(普攻标)。
#    不是直接调 _eq_on_hit 喂布尔 —— 那是恒真式, 守不住"伤害管线忘了传标"。
# ══════════════════════════════════════════════════════════════════════════
func _t_basic_gate() -> void:
	print("── ⓪b 普攻闸(浮游炮/技能不触发) ──")
	_s._units.clear()
	var a: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-100.0, 0.0), 1000.0), "p2eq_061", 3)
	var t: Dictionary = _mk("basic", "right", Vector2(100.0, 0.0), 100000.0)
	t["dodge_bonus"] = 0.0
	_s._damage._apply_damage_from(a, t, 10, Color(1, 1, 1))
	_ok("⓪b ★★技能/浮游炮命中【不】叠破损(走真实伤害入口, 无普攻标)",
		int(t.get("breach_stacks", 0)) == 0, "实测 %d 层" % int(t.get("breach_stacks", 0)))
	_s._damage._apply_basic_hit_from(a, t, 10, Color(1, 1, 1))
	_ok("⓪b ★普攻命中叠破损(_apply_basic_hit_from 带标)",
		int(t.get("breach_stacks", 0)) > 0, "实测 %d 层" % int(t.get("breach_stacks", 0)))


func _t060_parasol() -> void:
	print("── 060 磷光水母伞 ──")
	for si in range(3):
		var want_dr: float = [0.11, 0.22, 0.35][si]
		var want_heal: float = [50.0, 80.0, 130.0][si]
		_s._units.clear()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -300.0), 1000.0),
			"p2eq_060", si + 1)
		# ★★边界卡在 199 / 201 码 —— 不是 150 / 300。
		#   反向验证实测: 用 150/300 时把 PARASOL_RADIUS 从 200 改成 150 **一条都不红**
		#   (150 恰好还在圈里、300 本来就在圈外), 那是一条量不出半径的假门禁。
		var near: Dictionary = _mk("fortune", "left", Vector2(-101.0, -300.0), 1000.0)   # 距 199 码(圈内)
		var far: Dictionary = _mk("fortune", "left", Vector2(-99.0, -300.0), 1000.0)     # 距 201 码(圈外)
		u["hp"] = 400.0
		_ok("060 si=%d ★分母: 起手减伤 0 / 闪避 0 / 伞没开" % si,
			absf(float(u["damage_reduction"])) < 1e-6 and absf(float(u["dodge_bonus"])) < 1e-6
			and int(u.get("_parasol_si", -1)) == si,
			"dr=%.4f dodge=%.4f si=%d" % [float(u["damage_reduction"]), float(u["dodge_bonus"]), int(u.get("_parasol_si", -1))])
		# 6.9 秒还不开
		_sp.tick_unit(u, 6.9)
		_ok("060 si=%d 6.9 秒还没到 7 秒 → 伞没开" % si,
			absf(float(u["damage_reduction"])) < 1e-6,
			"dr=%.4f" % float(u["damage_reduction"]))
		# 再走 0.2 秒 → 越过 7 秒 → 开伞
		_sp.tick_unit(u, 0.2)
		_ok("060 si=%d 满 7 秒开伞 → 携带者减伤 = %.2f(需求 11/22/35%%)" % [si, want_dr],
			absf(float(u["damage_reduction"]) - want_dr) < 0.0005,
			"实测 %.4f" % float(u["damage_reduction"]))
		_ok("060 si=%d 携带者闪避 = 0.15(★固定值, 三星同值)" % si,
			absf(float(u["dodge_bonus"]) - 0.15) < 0.0005, "实测 %.4f" % float(u["dodge_bonus"]))
		_ok("060 si=%d 199 码处的队友吃到同样的减伤与闪避(边界内)" % si,
			absf(float(near["damage_reduction"]) - want_dr) < 0.0005
			and absf(float(near["dodge_bonus"]) - 0.15) < 0.0005,
			"dr=%.4f dodge=%.4f" % [float(near["damage_reduction"]), float(near["dodge_bonus"])])
		_ok("060 si=%d ★★201 码处的队友一点没吃到(半径卡在 200, ±1 码就分得出来)" % si,
			absf(float(far["damage_reduction"])) < 1e-6 and absf(float(far["dodge_bonus"])) < 1e-6,
			"dr=%.4f dodge=%.4f" % [float(far["damage_reduction"]), float(far["dodge_bonus"])])
		# 2.4 秒还没收
		_sp.tick_unit(u, 2.4)
		_ok("060 si=%d 开伞 2.4 秒还没到 2.5 秒 → 还开着" % si,
			absf(float(u["damage_reduction"]) - want_dr) < 0.0005,
			"dr=%.4f" % float(u["damage_reduction"]))
		var hp_before: float = float(u["hp"])
		_sp.tick_unit(u, 0.2)
		_ok("060 si=%d 满 2.5 秒收伞 → 减伤/闪避全撤(自己与队友都撤)" % si,
			absf(float(u["damage_reduction"])) < 1e-6 and absf(float(u["dodge_bonus"])) < 1e-6
			and absf(float(near["damage_reduction"])) < 1e-6 and absf(float(near["dodge_bonus"])) < 1e-6,
			"自 dr=%.4f dodge=%.4f / 友 dr=%.4f" % [float(u["damage_reduction"]), float(u["dodge_bonus"]), float(near["damage_reduction"])])
		_ok("060 si=%d 收伞时携带者回复 %.0f 生命(需求 50/80/130)" % [si, want_heal],
			absf(float(u["hp"]) - (hp_before + want_heal)) < 0.51,
			"hp %.1f → %.1f(期望 %.1f)" % [hp_before, float(u["hp"]), hp_before + want_heal])
	# ★★关键口径: 「效果结束后**才**重新开始 7 秒计时」⇒ 完整循环 = 2.5 + 7 = 9.5 秒,
	#   第二次开伞落在 t=9.5 而不是 t=7。喂到 9.4 秒必须还没开, 再喂 0.2 就开。
	_s._units.clear()
	var c: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, -260.0), 1000.0), "p2eq_060", 3)
	_sp.tick_unit(c, 7.0)                       # 第一次开
	_sp.tick_unit(c, 2.5)                       # 收伞(此刻 t=9.5)
	var opened_again := false
	var acc := 0.0
	for i in range(120):                        # 每步 0.1 秒, 最多再走 12 秒(得够跨过 7 秒)
		_sp.tick_unit(c, 0.1)
		acc += 0.1
		if float(c["damage_reduction"]) > 0.001:
			opened_again = true
			break
	_ok("060 ★★「效果结束后才重新计时」: 收伞后又整整 7 秒才第二次开伞(实测再等 %.1f 秒)" % acc,
		opened_again and absf(acc - 7.0) < 0.16, "再等 %.2f 秒, 期望 7.0" % acc)
	_ok("060 ★分母: 第二次确实开了(不是循环跑完了才判)", opened_again)
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 061 钻孔螺: on-hit 额外 2/2.5/3% 目标最大生命魔法伤 + 叠 1/1/2 层破损(上限20),
#             目标已有 20 层时这段转真实伤害
# ─────────────────────────────────────────────────────────────
func _t061_drill() -> void:
	print("── 061 钻孔螺 ──")
	for si in range(3):
		var pct: float = [0.02, 0.025, 0.03][si]
		var stk: int = [1, 1, 2][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -220.0), 3000.0), "p2eq_061", si + 1)
		var o: Dictionary = _mk("fortune", "right", Vector2(-150.0, -220.0), 2000.0)
		var h0: float = float(o["hp"])
		_ok("061 si=%d ★分母: 起手破损 0 层" % si, int(o.get("breach_stacks", 0)) == 0)
		_s._equip_sys._eq_on_hit(u, o, 0, true)
		_ok("061 si=%d 额外伤害 = 2000 × %.1f%% = %.0f(魔抗 0)" % [si, pct * 100.0, 2000.0 * pct],
			absf(h0 - float(o["hp"]) - 2000.0 * pct) < 0.51,
			"实掉 %.1f 期望 %.1f" % [h0 - float(o["hp"]), 2000.0 * pct])
		_ok("061 si=%d 叠 %d 层破损(需求 1/1/2)" % [si, stk],
			int(o["breach_stacks"]) == stk, "实测 %d" % int(o["breach_stacks"]))
	# ★上限 20 层
	_s._units.clear()
	var a: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -180.0), 3000.0), "p2eq_061", 3)
	var t: Dictionary = _mk("fortune", "right", Vector2(-150.0, -180.0), 100000.0)
	for i in range(30):
		_s._equip_sys._eq_on_hit(a, t, 0, true)
	_ok("061 ★单目标破损上限 20 层(打 30 下也只有 20)",
		int(t["breach_stacks"]) == 20, "实测 %d" % int(t["breach_stacks"]))
	# ★★满 20 层 → 转真实伤害。三步比, 【不引用游戏的抗性公式】:
	#   ① 零抗性 + 18 层 ⇒ 基数就是 10000 × 2% = 200(精确)
	#   ② 100 魔抗 + 18 层 ⇒ 魔法段被吃掉一部分, 严格 < 200
	#   ③ 同一个 100 魔抗目标 + 20 层 ⇒ 真伤, 又精确回到 200
	_s._units.clear()
	var a2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -140.0), 3000.0), "p2eq_061", 1)
	var m0: Dictionary = _mk("fortune", "right", Vector2(-150.0, -140.0), 10000.0)
	m0["breach_stacks"] = 18
	var z0: float = float(m0["hp"])
	_s._equip_sys._eq_on_hit(a2, m0, 0, true)
	var dbase: float = z0 - float(m0["hp"])
	_ok("061 ★分母: 零抗性 + 18 层 → 基数 = 10000 × 2% = 200",
		absf(dbase - 200.0) < 0.51, "实掉 %.1f" % dbase)
	var m: Dictionary = _mk("fortune", "right", Vector2(-110.0, -140.0), 10000.0)
	m["mr"] = 100.0                          # 魔抗 100 ⇒ 魔法段被吃掉一部分
	m["breach_stacks"] = 18
	var b0: float = float(m["hp"])
	_s._equip_sys._eq_on_hit(a2, m, 0, true)
	var d18: float = b0 - float(m["hp"])
	_ok("061 ★分母: 18 层时走【魔法】伤害 ⇒ 100 魔抗真的吃掉了一部分(严格 < 200 且 > 0)",
		d18 > 0.0 and d18 < 199.5, "实掉 %.1f(零抗性时是 %.1f)" % [d18, dbase])
	m["breach_stacks"] = 20
	var b1: float = float(m["hp"])
	_s._equip_sys._eq_on_hit(a2, m, 0, true)       # 20 层 → 真伤(不吃魔抗) → 10000×2% = 200
	var d20: float = b1 - float(m["hp"])
	_ok("061 ★★满 20 层 → 转【真实伤害】: 同一个 100 魔抗目标上从 %.1f 变回精确 200" % d18,
		absf(d20 - 200.0) < 0.51, "实掉 %.1f 期望 200" % d20)
	# ★多携带者共享层数(同【腐蚀】口径)
	_s._units.clear()
	var p1: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -100.0), 3000.0), "p2eq_061", 1)
	var p2: Dictionary = _equip(_mk("fortune", "left", Vector2(-280.0, -100.0), 3000.0), "p2eq_061", 1)
	var sh: Dictionary = _mk("fortune", "right", Vector2(-150.0, -100.0), 5000.0)
	_s._equip_sys._eq_on_hit(p1, sh, 0, true)
	_s._equip_sys._eq_on_hit(p2, sh, 0, true)
	_ok("061 ★多个携带者共享同一目标身上的破损层(1+1=2, 不是各记各的)",
		int(sh["breach_stacks"]) == 2, "实测 %d" % int(sh["breach_stacks"]))
	# ★分母: 不带 061 的同一发, 一点不掉血也不叠层
	_s._units.clear()
	var bare: Dictionary = _mk("fortune", "left", Vector2(-300.0, -60.0), 3000.0)
	var o2: Dictionary = _mk("fortune", "right", Vector2(-150.0, -60.0), 2000.0)
	var q0: float = float(o2["hp"])
	_s._equip_sys._eq_on_hit(bare, o2, 0, true)
	_ok("061 ★分母: 不带 061 → 不掉血也不叠层(证明上面那些不是恒真)",
		absf(q0 - float(o2["hp"])) < 0.01 and int(o2.get("breach_stacks", 0)) == 0,
		"掉 %.1f 层 %d" % [q0 - float(o2["hp"]), int(o2.get("breach_stacks", 0))])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 062 螳螂虾钳: 闪避后强化下一次普攻(0.7/1/1.5 ATK + 6/8/13% 目标最大生命 物理),
#               回复整次普攻总伤害的 40%; 强化有 2 秒 CD 且 **CD 卡的是触发**
# ─────────────────────────────────────────────────────────────
func _t062_mantis() -> void:
	print("── 062 螳螂虾钳 ──")
	for si in range(3):
		var atk_k: float = [0.7, 1.0, 1.5][si]
		var hp_k: float = [0.06, 0.08, 0.13][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -20.0), 3000.0), "p2eq_062", si + 1)
		u["atk"] = 100.0
		u["hp"] = 1000.0
		var o: Dictionary = _mk("fortune", "right", Vector2(-150.0, -20.0), 2000.0)
		var want: float = 100.0 * atk_k + 2000.0 * hp_k
		# ★没蓄力时: 普攻不产生任何额外伤害
		var z0: float = float(o["hp"])
		_s._equip_sys._eq_on_hit(u, o, 50, true)
		_ok("062 si=%d ★分母: 没闪避过 → 普攻不带额外段(掉血 0)" % si,
			absf(z0 - float(o["hp"])) < 0.01, "实掉 %.1f" % (z0 - float(o["hp"])))
		# 闪避 → 蓄一发
		_s._equip_sys._eq_on_dodge(u)
		_ok("062 si=%d 闪避成功 → emp_ready 置起" % si,
			bool((u["eq_state"].get("p2eq_062", {}) as Dictionary).get("emp_ready", false)))
		var h0: float = float(o["hp"])
		var me0: float = float(u["hp"])
		_s._equip_sys._eq_on_hit(u, o, 50, true)   # 假定普攻本体打了 50
		var got: float = h0 - float(o["hp"])
		_ok("062 si=%d 额外物理 = %.1f×ATK100 + %.0f%%×2000 = %.0f(护甲 0)" % [si, atk_k, hp_k * 100.0, want],
			absf(got - want) < 0.51, "实掉 %.1f 期望 %.1f" % [got, want])
		_ok("062 si=%d ★口径①: 回血 = 40%% ×(普攻本体 50 + 额外 %.0f) = %.1f" % [si, want, (50.0 + want) * 0.4],
			absf(float(u["hp"]) - me0 - (50.0 + want) * 0.4) < 0.51,
			"实回 %.1f 期望 %.1f" % [float(u["hp"]) - me0, (50.0 + want) * 0.4])
	# ★★口径②: 2 秒 CD 卡的是【触发】—— 打出后 2 秒内闪避**不再蓄**
	_s._units.clear()
	var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 20.0), 3000.0), "p2eq_062", 3)
	c["atk"] = 100.0
	var e: Dictionary = _mk("fortune", "right", Vector2(-150.0, 20.0), 2000.0)
	var tsave: float = _s._t
	_s._equip_sys._eq_on_dodge(c)
	_s._equip_sys._eq_on_hit(c, e, 10, true)                       # 打出 → 进 CD
	_s._t = tsave + 1.9
	_s._equip_sys._eq_on_dodge(c)
	_ok("062 ★★口径②: CD 内(1.9 秒)闪避成功也【不蓄】下一发(不是'蓄了但打不出')",
		not bool((c["eq_state"].get("p2eq_062", {}) as Dictionary).get("emp_ready", false)),
		"emp_ready=%s" % str((c["eq_state"].get("p2eq_062", {}) as Dictionary).get("emp_ready", false)))
	var y0: float = float(e["hp"])
	_s._equip_sys._eq_on_hit(c, e, 10, true)
	_ok("062 ★★CD 内的普攻确实没有额外段(掉血 0)",
		absf(y0 - float(e["hp"])) < 0.01, "实掉 %.1f" % (y0 - float(e["hp"])))
	_s._t = tsave + 2.1
	_s._equip_sys._eq_on_dodge(c)
	_ok("062 CD 过了(2.1 秒)闪避又能蓄",
		bool((c["eq_state"].get("p2eq_062", {}) as Dictionary).get("emp_ready", false)))
	_s._t = tsave
	# ★★真入口: 走【中央伤害管线的闪避分支】触发蓄力
	_s._units.clear()
	var d: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 60.0), 3000.0), "p2eq_062", 3)
	d["dodge_bonus"] = 1.0                       # randf() ∈ [0,1) 恒 < 1.0 ⇒ 必闪
	var atkr: Dictionary = _mk("fortune", "right", Vector2(-150.0, 60.0), 9000.0)
	_s._damage._apply_damage_from(atkr, d, 500, Color("#ffffff"))
	_ok("062 ★★真入口: 经 _apply_damage_from 的闪避分支 → 真的蓄上了",
		bool((d["eq_state"].get("p2eq_062", {}) as Dictionary).get("emp_ready", false)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 063 白鲸气环: on-cast +30/60/100% 攻速(持续=消耗龟能×0.03);
#               普攻挂【环】, 3 个环引爆 25/40/70 真伤
# ─────────────────────────────────────────────────────────────
func _t063_whale() -> void:
	print("── 063 白鲸气环 ──")
	for si in range(3):
		var want_mult: float = 1.0 + [0.30, 0.60, 1.00][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 100.0), 3000.0), "p2eq_063", si + 1)
		u["haste_mult"] = 1.0
		u["haste_until"] = 0.0
		u["energy_cost"] = {"whaleTest": 100.0}
		u["pending"] = "K:whaleTest"
		_ok("063 si=%d ★分母: 起手没有攻速 buff(倍率 1.0)" % si,
			absf(float(u.get("haste_mult", 1.0)) - 1.0) < 1e-6)
		_s._equip_sys._eq_on_cast(u, u)
		_ok("063 si=%d 放技能后攻速倍率 = %.2f(需求 +30/60/100%%)" % [si, want_mult],
			absf(float(u["haste_mult"]) - want_mult) < 0.0005,
			"实测 %.3f" % float(u["haste_mult"]))
		_ok("063 si=%d 持续 = 消耗龟能 100 × 0.03 = 3.00 秒" % si,
			absf(float(u["haste_until"]) - (_s._t + 3.0)) < 0.02,
			"until-_t=%.3f 期望 3.00" % (float(u["haste_until"]) - _s._t))
	# ★覆盖率恒定 40%: 加成持续(cost×0.03) ÷ 充满龟能(cost×0.075) ≡ 0.40, 与消耗无关
	_s._units.clear()
	var w: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 140.0), 3000.0), "p2eq_063", 3)
	var cov_bad: Array = []
	for cost in [10.0, 40.0, 80.0, 150.0, 210.0]:
		w["haste_mult"] = 1.0
		w["haste_until"] = 0.0
		w["energy_cost"] = {"whaleTest": cost}
		w["pending"] = "K:whaleTest"
		_s._equip_sys._eq_on_cast(w, w)
		var dur: float = float(w["haste_until"]) - _s._t
		var cd: float = float(_s._skill_cd(w, "whaleTest"))
		if absf(dur / maxf(cd, 1e-6) - 0.40) > 0.002:
			cov_bad.append("cost=%.0f 覆盖率 %.3f" % [cost, dur / maxf(cd, 1e-6)])
	_ok("063 ★覆盖率对 5 种龟能消耗恒为 40%(0.03 ÷ 0.075, 与龟无关)", cov_bad.is_empty(), str(cov_bad))
	# ★环: 前两次不炸, 第三次炸 25/40/70 真伤且清零
	for si in range(3):
		var boom: float = [25.0, 40.0, 70.0][si]
		_s._units.clear()
		var u2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 180.0), 3000.0), "p2eq_063", si + 1)
		var o: Dictionary = _mk("fortune", "right", Vector2(-150.0, 180.0), 5000.0)
		o["mr"] = 200.0
		o["def"] = 200.0                     # 真伤不吃这两条 —— 是不是真伤在这里就分得出来
		var s0: float = float(o["hp"])
		_s._equip_sys._eq_on_hit(u2, o, 0, true)
		_s._equip_sys._eq_on_hit(u2, o, 0, true)
		_ok("063 si=%d ★分母: 前两个环不掉血, 环数 = 2" % si,
			absf(s0 - float(o["hp"])) < 0.01 and int(o["whale_rings"]) == 2,
			"掉 %.1f 环 %d" % [s0 - float(o["hp"]), int(o["whale_rings"])])
		_s._equip_sys._eq_on_hit(u2, o, 0, true)
		_ok("063 si=%d 第 3 个环引爆 = %.0f 点【真实】伤害(200 双抗一点不减)" % [si, boom],
			absf(s0 - float(o["hp"]) - boom) < 0.51, "实掉 %.1f" % (s0 - float(o["hp"])))
		_ok("063 si=%d 引爆后环数清零(重新攒)" % si,
			int(o["whale_rings"]) == 0, "环 %d" % int(o["whale_rings"]))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 064 溺者的浮囊: 首次 <35% → 幽灵护盾 50/80/160% maxHp(20 秒线性衰减),
#                 持有期 +15% 闪避 + 30/60/120 双抗;
#                 破盾(打光或衰减耗尽都算)→ 300 码内敌人 4 秒诅咒
# ─────────────────────────────────────────────────────────────
func _t064_bladder() -> void:
	print("── 064 溺者的浮囊 ──")
	for si in range(3):
		var pct: float = [0.50, 0.80, 1.60][si]
		var res: float = [30.0, 60.0, 120.0][si]
		_s._units.clear()
		_s._spec.clear_all()
		var u: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 220.0), 1000.0),
			"p2eq_064", si + 1)
		_ok("064 si=%d ★分母: 满血时不触发(护盾 0 / 双抗 0)" % si,
			absf(_s._spec.val(u, "p2eq_064_ghost")) < 0.001 and absf(float(u["def"])) < 1e-6,
			"盾 %.1f def %.1f" % [_s._spec.val(u, "p2eq_064_ghost"), float(u["def"])])
		_sp.tick_unit(u, 0.1)
		_ok("064 si=%d ★分母: 血量 36%% 也不触发(线在 35%%)" % si,
			absf(_s._spec.val(u, "p2eq_064_ghost")) < 0.001)
		u["hp"] = 340.0                       # 34% < 35%
		_sp.tick_unit(u, 0.1)
		_ok("064 si=%d 幽灵护盾 = 1000 × %.0f%% = %.0f" % [si, pct * 100.0, 1000.0 * pct],
			absf(_s._spec.val(u, "p2eq_064_ghost") - 1000.0 * pct) < 0.51,
			"实测 %.1f" % _s._spec.val(u, "p2eq_064_ghost"))
		_ok("064 si=%d 双抗各 +%.0f(需求 30/60/120)" % [si, res],
			absf(float(u["def"]) - res) < 0.51 and absf(float(u["mr"]) - res) < 0.51,
			"def %.1f mr %.1f" % [float(u["def"]), float(u["mr"])])
		_ok("064 si=%d 闪避 +15%%(固定值)" % si,
			absf(float(u["dodge_bonus"]) - 0.15) < 0.0005, "实测 %.4f" % float(u["dodge_bonus"]))
	# ★线性衰减: 20 秒总时长 ⇒ 走 5 秒剩 75%
	_s._units.clear()
	_s._spec.clear_all()
	var d: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 260.0), 1000.0), "p2eq_064", 1)
	d["hp"] = 300.0
	_sp.tick_unit(d, 0.1)
	var full: float = _s._spec.val(d, "p2eq_064_ghost")
	_s._spec.tick(5.0)
	_ok("064 ★线性衰减: 20 秒总时长 → 走 5 秒剩 75%(500 → 375)",
		absf(_s._spec.val(d, "p2eq_064_ghost") - full * 0.75) < 0.51,
		"实测 %.1f 期望 %.1f" % [_s._spec.val(d, "p2eq_064_ghost"), full * 0.75])
	_s._spec.tick(5.0)
	_ok("064 ★线性(不是指数): 再走 5 秒剩 50%(掉的量与前 5 秒相同)",
		absf(_s._spec.val(d, "p2eq_064_ghost") - full * 0.50) < 0.51,
		"实测 %.1f 期望 %.1f" % [_s._spec.val(d, "p2eq_064_ghost"), full * 0.50])
	# ★★口径①: 自然衰减耗尽也算"被打破" ⇒ 必定爆炸
	# ★★边界卡在 299 / 301 码(不是 150 / 400): 松的边界量不出半径 ——
	#   反向验证时把 GHOST_BURST_R 从 300 改成 200, 松边界一条都不会红。
	var near: Dictionary = _mk("fortune", "right", Vector2(-1.0, 260.0), 5000.0)     # 距 299 码(圈内)
	var far: Dictionary = _mk("fortune", "right", Vector2(1.0, 260.0), 5000.0)       # 距 301 码(圈外)
	_ok("064 ★分母: 爆炸前两个敌人身上都没有诅咒",
		not _has_curse(near) and not _has_curse(far))
	_s._spec.tick(11.0)
	_ok("064 ★★口径①: 自然衰减耗尽 → 也炸(余额归零)",
		absf(_s._spec.val(d, "p2eq_064_ghost")) < 0.001
		and int(d.get("_ghost_burst_n", 0)) == 1,
		"余额 %.2f 爆炸次数 %d" % [_s._spec.val(d, "p2eq_064_ghost"), int(d.get("_ghost_burst_n", 0))])
	_ok("064 ★★299 码处的敌人吃到 4 秒【诅咒】(边界内)", _has_curse(near))
	_ok("064 ★★301 码处的敌人没吃到(半径卡在 300, ±1 码就分得出来)", not _has_curse(far))
	_ok("064 破盾后双抗与闪避一并撤掉",
		absf(float(d["def"])) < 1e-6 and absf(float(d["mr"])) < 1e-6
		and absf(float(d["dodge_bonus"])) < 1e-6,
		"def %.1f mr %.1f dodge %.4f" % [float(d["def"]), float(d["mr"]), float(d["dodge_bonus"])])
	# 诅咒每秒 5% 最大生命(已有机制) ⇒ 4 秒 = 20% 最大生命
	var cd: Dictionary = {}
	for x in near.get("dots", []):
		if x is Dictionary and str((x as Dictionary).get("tag", "")) == "curse":
			cd = x
	_ok("064 诅咒走【已有统一入口】: 每秒 5% 最大生命(5000 → dps 250)",
		not cd.is_empty() and absf(float(cd.get("dps", 0.0)) - 250.0) < 0.51,
		"dps=%.1f" % float(cd.get("dps", -1.0)))
	# ★每路一次
	_sp.tick_unit(d, 0.1)
	_ok("064 ★每路一次: 破盾后仍在 35% 以下, 也不再给第二次",
		absf(_s._spec.val(d, "p2eq_064_ghost")) < 0.001
		and int(d.get("_ghost_burst_n", 0)) == 1,
		"余额 %.2f 爆炸 %d" % [_s._spec.val(d, "p2eq_064_ghost"), int(d.get("_ghost_burst_n", 0))])
	# ★★被打光也炸(reason=damage), 且走【真实伤害管线】—— 两条路上 SpecialBalance 都接了
	_s._units.clear()
	_s._spec.clear_all()
	var k: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-300.0, 300.0), 1000.0), "p2eq_064", 1)
	k["hp"] = 300.0
	_sp.tick_unit(k, 0.1)
	var foe: Dictionary = _mk("fortune", "right", Vector2(-150.0, 300.0), 5000.0)
	var atkr: Dictionary = _mk("fortune", "right", Vector2(-100.0, 300.0), 9000.0)
	_ok("064 ★分母: 打之前敌人没诅咒且护盾满(%.0f)" % _s._spec.val(k, "p2eq_064_ghost"),
		not _has_curse(foe) and _s._spec.val(k, "p2eq_064_ghost") > 400.0)
	# ★no_dodge = true: 幽灵护盾自带 15% 闪避, 不关掉的话这一发有 15% 概率被闪掉
	#   ⇒ CI 上偶发红(第一次跑就正好闪了一次)。这不是"调参数让它过", 是把随机源隔离掉。
	_s._damage._apply_damage_from(atkr, k, 9000, Color("#ffffff"), 0.0, false, false, false, true)
	_ok("064 ★★被打光也炸(经中央伤害管线 _apply_damage_from → SpecialBalance.absorb)",
		int(k.get("_ghost_burst_n", 0)) == 1 and _has_curse(foe),
		"爆炸 %d 诅咒 %s" % [int(k.get("_ghost_burst_n", 0)), str(_has_curse(foe))])
	_s._units.clear()
	_s._spec.clear_all()


# ─────────────────────────────────────────────────────────────
# 演出物理不变量 ① 060: 二阶欠阻尼阶跃(膜张力)
# ─────────────────────────────────────────────────────────────
func _t_phys_060() -> void:
	print("── 特效① 060 阻尼振荡(伞面张力) ──")
	_ok("① x(0) = 0 且 x(∞) = 1(阶跃响应的两个端点)",
		absf(SVX.damped_step(0.0)) < 1e-9 and absf(SVX.damped_step(20.0) - 1.0) < 1e-6,
		"x(0)=%.6f x(20)=%.6f" % [SVX.damped_step(0.0), SVX.damped_step(20.0)])
	# 扫描找第一个峰
	var best_t := 0.0
	var best_v := -1e9
	for i in range(1, 4000):
		var tt: float = float(i) * 0.001
		var v: float = SVX.damped_step(tt)
		if v > best_v:
			best_v = v
			best_t = tt
	_ok("① ★超调量 = e^(−ζπ/√(1−ζ²)) = %.6f(闭式, 不是调出来的)" % WANT_OVERSHOOT,
		absf(best_v - (1.0 + WANT_OVERSHOOT)) < 0.002,
		"实测峰值 %.6f 期望 %.6f" % [best_v, 1.0 + WANT_OVERSHOOT])
	_ok("① ★峰值时刻 tp = π/ω_d = %.6f 秒" % WANT_PEAK_T,
		absf(best_t - WANT_PEAK_T) < 0.002, "实测 %.4f" % best_t)
	# ★对数减缩: 相邻两峰【偏差】之比恒为 e^δ, 与是第几对峰无关。手调曲线做不到。
	var peaks: Array = []
	var prev := -1e9
	var rising := true
	var last := SVX.damped_step(0.0)
	for i in range(1, 8000):
		var tt: float = float(i) * 0.001
		var v: float = SVX.damped_step(tt)
		if rising and v < last:
			peaks.append(last - 1.0)
			rising = false
		elif not rising and v > last:
			rising = true
		last = v
		prev = v
	var ratios: Array = []
	for i in range(peaks.size() - 1):
		if absf(float(peaks[i + 1])) > 1e-9:
			ratios.append(float(peaks[i]) / float(peaks[i + 1]))
	var want_ratio: float = exp(WANT_LOGDEC)
	var bad: Array = []
	for r in ratios:
		if absf(float(r) - want_ratio) > 0.05:
			bad.append("%.4f" % float(r))
	_ok("① ★★对数减缩: 找到 %d 个峰 / %d 对比值, **每一对**都 = e^δ = %.4f" % [peaks.size(), ratios.size(), want_ratio],
		ratios.size() >= 2 and bad.is_empty(), "偏离的: %s" % str(bad))
	_ok("① ★分母: 真的找到了 ≥3 个峰(找不到峰的话上面那条是空检查)", peaks.size() >= 3,
		"peaks=%d" % peaks.size())
	# 打开/收拢: 两端为 0, 中段 > 1(过冲)
	_ok("① 开伞曲线: t=0 收拢(0) / 2.5 秒末收回(≈0) / 中途过冲 >1",
		absf(SVX.parasol_open_frac(0.0, 2.5)) < 1e-9
		and SVX.parasol_open_frac(2.5, 2.5) < 1e-6
		and SVX.parasol_open_frac(WANT_PEAK_T, 2.5) > 1.0,
		"末 %.6f 峰 %.4f" % [SVX.parasol_open_frac(2.5, 2.5), SVX.parasol_open_frac(WANT_PEAK_T, 2.5)])


# ─────────────────────────────────────────────────────────────
# 演出物理不变量 ② 061: Paris 疲劳裂纹扩展律(破损累积可见性)
# ─────────────────────────────────────────────────────────────
func _t_phys_061() -> void:
	print("── 特效② 061 Paris 疲劳裂纹(破损【快满了】的读数) ──")
	_ok("② â(20 层) 归一到 1.0", absf(SVX.crack_len(20.0) - 1.0) < 1e-9,
		"%.6f" % SVX.crack_len(20.0))
	# ★1/â(N) 对 N 严格线性: 1/â = 6 − N/4。逐点比, 不是拟合。
	var lin_bad: Array = []
	for n in range(0, 21):
		var inv: float = 1.0 / SVX.crack_len(float(n))
		var want: float = WANT_INVA_B + WANT_INVA_SLOPE * float(n)
		if absf(inv - want) > 1e-6:
			lin_bad.append("N=%d 实 %.6f 期 %.6f" % [n, inv, want])
	_ok("② ★★Paris 闭式解: 1/â(N) 对 N **严格线性**(21 个点逐点比 6 − N/4)",
		lin_bad.is_empty(), str(lin_bad.slice(0, 3)))
	_ok("② ★分母: 曲线真的在长(â(0)=1/6, â(20)=1, 涨了 6 倍)",
		absf(SVX.crack_len(0.0) - 1.0 / 6.0) < 1e-6, "â(0)=%.6f" % SVX.crack_len(0.0))
	# ★"快满了"可读性: 最后一层的增量必须远大于中段
	var d20: float = SVX.crack_len(20.0) - SVX.crack_len(19.0)
	var d10: float = SVX.crack_len(10.0) - SVX.crack_len(9.0)
	_ok("② ★可读性: 第 20 层的增量是第 10 层增量的 5 倍以上(玩家能看出快满了)",
		d20 > d10 * 5.0, "Δ20=%.4f Δ10=%.4f 倍率 %.2f" % [d20, d10, d20 / maxf(d10, 1e-9)])
	# 单调
	var mono := true
	for n in range(1, 21):
		if SVX.crack_len(float(n)) <= SVX.crack_len(float(n - 1)):
			mono = false
	_ok("② 单调递增(层数只增不减 ⇒ 读数也只增不减)", mono)


# ─────────────────────────────────────────────────────────────
# 演出物理不变量 ③ 062: Hertz 接触 + Rayleigh 空穴溃灭(两段式)
# ─────────────────────────────────────────────────────────────
func _t_phys_062() -> void:
	print("── 特效③ 062 空泡效应(钳合 → 空泡 → 溃灭闪光) ──")
	# ★Rayleigh 2/5 的尺度不变性: R(1−4s)/R(1−s) ≡ 4^0.4, 与 s 无关
	var inv_bad: Array = []
	for s in [0.2, 0.1, 0.05, 0.02, 0.01, 0.002]:
		var r1: float = SVX.cavity_radius(1.0 - 4.0 * s)
		var r2: float = SVX.cavity_radius(1.0 - s)
		if absf(r1 / maxf(r2, 1e-12) - WANT_K4_04) > 1e-6:
			inv_bad.append("s=%.3f 比值 %.6f" % [s, r1 / maxf(r2, 1e-12)])
	_ok("③ ★★Rayleigh 尺度不变: R(1−4s)/R(1−s) ≡ 4^0.4 = %.6f(对 6 个 s 全成立)" % WANT_K4_04,
		inv_bad.is_empty(), str(inv_bad))
	_ok("③ ★分母: R̂(0)=1 且 R̂(1)=0(溃灭到点)",
		absf(SVX.cavity_radius(0.0) - 1.0) < 1e-9 and absf(SVX.cavity_radius(1.0)) < 1e-9)
	# ★绝热压缩(γ=5/3): θ·R̂² ≡ 1, 直到半径被钳在 R_MIN
	var ad_bad: Array = []
	for tau in [0.0, 0.2, 0.5, 0.8, 0.95, 0.99]:
		var r: float = SVX.cavity_radius(tau)
		var th: float = SVX.cavity_theta(tau)
		if r > 0.061 and absf(th * r * r - 1.0) > 1e-6:
			ad_bad.append("τ=%.2f θ·R²=%.6f" % [tau, th * r * r])
	_ok("③ ★绝热律 θ = R̂^(−3(γ−1)) = R̂^(−2) ⇒ θ·R̂² ≡ 1(γ=5/3 单原子气体)",
		ad_bad.is_empty(), str(ad_bad))
	# ★两段式: 段②峰值必须比段①峰值亮, 且比值 = 闭式 ln(θmax)/ln(4)
	var a1: float = SVX.strike_peak_alpha()
	var a2: float = SVX.collapse_peak_alpha()
	_ok("③ ★★两段式: 溃灭闪光(%.4f) 比钳合闪光(%.4f) 更亮" % [a2, a1], a2 > a1)
	_ok("③ ★★亮度比 = ln(R_min^−2)/ln(2²) = %.4f(闭式, 不是拍的)" % WANT_FLASH_RATIO,
		absf(a2 / maxf(a1, 1e-9) - WANT_FLASH_RATIO) < 0.002,
		"实测 %.4f" % (a2 / maxf(a1, 1e-9)))
	# ★Hertz: â² 对 s 严格线性
	var hz_bad: Array = []
	for i in range(0, 11):
		var s2: float = float(i) * 0.1
		var a: float = SVX.hertz_contact(s2)
		if absf(a * a - s2) > 1e-9:
			hz_bad.append("s=%.1f a²=%.6f" % [s2, a * a])
	_ok("③ ★Hertz 接触: 等速逼近 ⇒ 接触半径² 对时间**严格线性**(11 点逐点比)",
		hz_bad.is_empty(), str(hz_bad))
	# 整段形态: 段① 在前, 段② 在后; 段② 末尾亮度到 1
	var s_start: Dictionary = SVX.strike_shape(0.05)
	var s_end: Dictionary = SVX.strike_shape(1.0)
	_ok("③ 整段: 起手在段①, 收尾在段② 且亮度到顶(1.0)",
		int(s_start["stage"]) == 1 and int(s_end["stage"]) == 2
		and absf(float(s_end["a"]) - 1.0) < 1e-6,
		"起 stage=%d 末 stage=%d a=%.4f" % [int(s_start["stage"]), int(s_end["stage"]), float(s_end["a"])])


# ─────────────────────────────────────────────────────────────
# 演出物理不变量 ④ 063: 浮力涡环(体积守恒 + 冲量线性 + Kelvin–Lamb)
# ─────────────────────────────────────────────────────────────
func _t_phys_063() -> void:
	print("── 特效④ 063 涡环(边走边胀·环管变细·体积守恒) ──")
	var life: float = 1.10
	# ★① 浮力冲量: R² 对 t 严格线性(dI/dt = 浮力, I ∝ R²)
	var r0: float = SVX.ring_radius(0.0)
	var r1: float = SVX.ring_radius(life)
	var lin_bad: Array = []
	for i in range(0, 12):
		var tt: float = float(i) / 11.0 * life
		var rr: float = SVX.ring_radius(tt)
		var want: float = r0 * r0 + (r1 * r1 - r0 * r0) * (tt / life)
		if absf(rr * rr - want) > 1e-6:
			lin_bad.append("t=%.3f R²=%.6f 期 %.6f" % [tt, rr * rr, want])
	_ok("④ ★★浮力涡环: R² 对 t **严格线性**(Turner 1957 · 12 点逐点比)",
		lin_bad.is_empty(), str(lin_bad.slice(0, 3)))
	_ok("④ ★分母: 环真的在胀(R: %.3f → %.3f)" % [r0, r1], r1 > r0 * 1.5)
	# ★② 体积守恒: V = 2π²R·a² = const ⇒ R·a² 恒定
	var vbad: Array = []
	var v0: float = SVX.ring_radius(0.0) * SVX.ring_tube(0.0) * SVX.ring_tube(0.0)
	for i in range(0, 12):
		var tt: float = float(i) / 11.0 * life
		var v: float = SVX.ring_radius(tt) * SVX.ring_tube(tt) * SVX.ring_tube(tt)
		if absf(v / maxf(v0, 1e-12) - 1.0) > 1e-6:
			vbad.append("t=%.3f V/V0=%.6f" % [tt, v / maxf(v0, 1e-12)])
	_ok("④ ★★体积守恒: R·a² 全程恒定(⇒ 环径涨则环管必细, 12 点逐点比)",
		vbad.is_empty(), str(vbad.slice(0, 3)))
	_ok("④ ★分母: 环管真的在变细(a: %.4f → %.4f)" % [SVX.ring_tube(0.0), SVX.ring_tube(life)],
		SVX.ring_tube(life) < SVX.ring_tube(0.0) * 0.9)
	# ★③ Kelvin–Lamb: U = Γ/(4πR)·[ln(8R/a) − 1/4] 随 R 增大单调降
	var mono := true
	var prev: float = SVX.ring_speed(0.0)
	for i in range(1, 12):
		var tt: float = float(i) / 11.0 * life
		var u: float = SVX.ring_speed(tt)
		if u >= prev:
			mono = false
		prev = u
	_ok("④ ★Kelvin–Lamb: 平移速度随环径增大**单调下降**(越胀越慢, %.3f → %.3f)"
		% [SVX.ring_speed(0.0), SVX.ring_speed(life)], mono)
	_ok("④ 3 个环引爆(与效果侧的 RING_TRIGGER 口径一致)", SVX.RING_TRIGGER == 3)


# ─────────────────────────────────────────────────────────────
# 演出物理不变量 ⑤ 064: 等压放气(浮囊瘪) + Fick 扩散(诅咒云)
# ─────────────────────────────────────────────────────────────
func _t_phys_064() -> void:
	print("── 特效⑤ 064 浮囊等压放气 + 诅咒云扩散 ──")
	# ★等压 ⇒ 体积 ∝ 剩余量 ⇒ (r/rmax)³ ≡ f 精确成立
	var vb: Array = []
	for i in range(0, 21):
		var f: float = float(i) / 20.0
		var r: float = SVX.bladder_radius_frac(f)
		if absf(r * r * r - f) > 1e-6:
			vb.append("f=%.2f r³=%.6f" % [f, r * r * r])
	_ok("⑤ ★★等压放气: (r/r_max)³ ≡ f **精确成立**(21 点逐点比 —— 体积线性于剩余余额)",
		vb.is_empty(), str(vb.slice(0, 3)))
	_ok("⑤ ★分母: 端点对(f=1 → r=1, f=0 → r=0)",
		absf(SVX.bladder_radius_frac(1.0) - 1.0) < 1e-9 and absf(SVX.bladder_radius_frac(0.0)) < 1e-9)
	# ★松弛度 s = 1 − f^(2/3) 与 (r/rmax)² 之和恒为 1 ⇒ 早期就看得见"在瘪"
	var sb: Array = []
	for i in range(0, 21):
		var f: float = float(i) / 20.0
		var r: float = SVX.bladder_radius_frac(f)
		if absf(SVX.bladder_slack(f) + r * r - 1.0) > 1e-6:
			sb.append("f=%.2f 和=%.6f" % [f, SVX.bladder_slack(f) + r * r])
	_ok("⑤ ★皮面松弛度 + (r/r_max)² ≡ 1(21 点逐点比)", sb.is_empty(), str(sb.slice(0, 3)))
	_ok("⑤ ★可读性: 掉到一半余额时松弛度已 >0.35(半径只小 21%, 光靠半径看不出在瘪)",
		SVX.bladder_slack(0.5) > 0.35, "slack(0.5)=%.4f" % SVX.bladder_slack(0.5))
	# ★Fick 扩散: r² 对归一时间严格线性
	var db: Array = []
	for i in range(0, 21):
		var uu: float = float(i) / 20.0
		var r: float = SVX.diffusion_radius(uu)
		if absf(r * r - uu) > 1e-6:
			db.append("u=%.2f r²=%.6f" % [uu, r * r])
	_ok("⑤ ★★诅咒云 Fick 扩散: r² 对时间**严格线性**(均方位移 = 2Dt · 21 点逐点比)",
		db.is_empty(), str(db.slice(0, 3)))


# ─────────────────────────────────────────────────────────────
# ⑥ 美术真的进 _world: 量【真实节点】的世界尺寸/朝向/材质, 不是量公式
# ─────────────────────────────────────────────────────────────
func _t_vfx_nodes() -> void:
	print("── ⑥ 演出节点(量真实节点, 不量公式) ──")
	_ok("⑥ ★分母: 世界节点 _world 在", is_instance_valid(_s._world))
	var vfx = _sp._vfx
	# ★★前面几组走【真效果路径】已经往 _world 里挂过伞/云了。clear_all() 用的是 queue_free ——
	#   **延迟**释放, 不等两帧的话 _pick_meta 会抓到一个已经排队待删的旧节点, 量出来永远是初值
	#   (第一次跑就栽在这: 伞半径三次读数全是 0.0001)。
	vfx.clear_all()
	await get_tree().process_frame
	await get_tree().process_frame
	var n0: int = _count_meta("")
	_ok("⑥ ★分母: 撤场后 _world 里本层节点清空(%d 个)" % n0, n0 == 0, "残留 %d" % n0)
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	# ══ ⑥-A 【走真效果路径】建节点 ═════════════════════════════════════════
	# ★★这一段必须走 tick_unit → _parasol_open, **不能**在这里直接调 vfx.parasol_open(…, 200.0, …):
	#   直接调 = 我自己把 200 喂进去再量它吐出来的 200, 那是恒真式。
	#   反向验证实测过: 第一版就是直接调的, 把效果侧的 PARASOL_RADIUS 改成 150 时**一条都没红**
	#   (memory fb-write-without-reader-and-fake-gates:「门禁模拟公式 ≠ 量真实对象」)。
	_s._units.clear()
	var pc: Dictionary = _equip_flags(_mk("fortune", "left", Vector2(-200.0, -200.0), 1000.0), "p2eq_060", 3)
	_sp.tick_unit(pc, 7.1)
	_ok("⑥ ★★【真效果路径】开伞真的往 _world 里挂了 3 个节点(伞体 + 磷光场 + 上浮微粒), 不是【函数被调过】",
		_count_meta("") - n0 == 3, "多了 %d 个" % (_count_meta("") - n0))
	# 2026-08-11 重做: 庇护圈从几何线圈换成【磷光浮游光点场】(用户「别用程序生成的圆敷衍」)。
	# 半径语义没变: plank 场节点的 scale 仍必须 = 200 码 × WS(圈带就画在 r=0.88~1.0 处)。
	var plank = _pick_meta("plank")
	_ok("⑥ ★分母: 取到了磷光场节点", plank != null)
	if plank != null:
		# ★★尺子匹配被测概念: 庇护半径必须是 200 【码】换算成米, 量的是【真效果建出来的】节点 scale
		var want_m: float = 200.0 * float(_s.WS)
		_ok("⑥ ★★磷光场的**真实世界半径** = 200 码 × WS = %.4f m(量真节点 scale, 不是量公式)" % want_m,
			absf(float(plank.scale.x) - want_m) < 1e-4,
			"实测 %.4f m" % float(plank.scale.x))
		# ★圈不再是连续几何环: 光点场顶点数 = (64场+30带)×2片×6顶点 —— 数真网格
		var vcnt: int = (plank.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		_ok("⑥ ★庇护范围是浮游光点场不是线圈(顶点数 = 94 颗 × 12)", vcnt == 94 * 12,
			"实为 %d 顶点" % vcnt)
		_ok("⑥ 零素材: 网格是程序现算的(resource_path 为空串)",
			str((plank.mesh as ArrayMesh).resource_path) == "",
			"path=%s" % str((plank.mesh as ArrayMesh).resource_path))
		_ok("⑥ 走 material_override(不是 surface override —— 后者在无头下刷 material is null)",
			plank.material_override != null and plank.get_surface_override_material_count() >= 0)
	# ══ ⑥-B 形态: 直接喂任意 u 看伞体半径怎么走(纯同步, 不等 tween) ═══════
	vfx.clear_all()
	await get_tree().process_frame
	await get_tree().process_frame
	var h: Dictionary = vfx.parasol_open(c, Color(1, 1, 1, 1), 200.0, 2.5)
	var bell = _pick_meta("bell")
	if bell != null:
		# 伞体半径随张开度走: u=0 时几乎为 0, 峰值时刻要 > 稳态
		vfx.apply_at(h, 0.0)
		var r_zero: float = float(bell.scale.x)
		vfx.apply_at(h, WANT_PEAK_T / 2.5)
		var r_peak: float = float(bell.scale.x)
		vfx.apply_at(h, 1.0)
		var r_end: float = float(bell.scale.x)
		_ok("⑥ ★伞体半径真的跟着阻尼振荡走: 起手≈0 / 峰值最大 / 末尾收回≈0",
			r_zero < 1e-3 and r_peak > r_zero and r_end < r_peak * 0.05,
			"起 %.5f 峰 %.5f 末 %.5f" % [r_zero, r_peak, r_end])
		_ok("⑥ ★分母: 峰值半径确实是个正经尺寸(>0.5 m)", r_peak > 0.5, "%.4f m" % r_peak)
	# 破裂云: 半径必须扩到 300 码
	var hb: Dictionary = vfx.bladder_burst(c, Color(1, 1, 1, 1), 300.0)
	var cloud = _pick_meta("curse_cloud")
	_ok("⑥ ★分母: 取到了诅咒云节点", cloud != null)
	if cloud != null:
		vfx.apply_at(hb, 1.0)
		var want300: float = 300.0 * float(_s.WS)
		_ok("⑥ ★★诅咒云扩到底 = 300 码 × WS = %.4f m(与效果半径同一个数)" % want300,
			absf(float(cloud.scale.x) - want300) < 1e-4, "实测 %.4f m" % float(cloud.scale.x))
	# 撤场: tick 到期后节点被 free
	var live0: int = vfx.live_count()
	vfx.tick(9.0)
	await get_tree().process_frame
	_ok("⑥ 到期自销: tick 走完时长后活着的句柄从 %d 降到 %d" % [live0, vfx.live_count()],
		live0 >= 2 and vfx.live_count() == 0, "live=%d" % vfx.live_count())
	# 守 _world == null 不崩(数值测试里常常只建单位不建世界)
	var saved = _s._world
	_s._world = null
	var empty: Dictionary = vfx.parasol_open(c, Color(1, 1, 1, 1), 200.0, 2.5)
	_s._world = saved
	_ok("⑥ _world 不在时不崩也不建(返回空句柄)", empty.is_empty())
	vfx.clear_all()


func _count_meta(kind: String) -> int:
	var n := 0
	for ch in _s._world.get_children():
		if not ch.has_meta("spirit_eq_vfx"):
			continue
		if kind != "" and str(ch.get_meta("spirit_eq_vfx")) != kind:
			continue
		n += 1
	return n


func _pick_meta(kind: String):
	for ch in _s._world.get_children():
		if ch.has_meta("spirit_eq_vfx") and str(ch.get_meta("spirit_eq_vfx")) == kind:
			return ch
	return null


## 某 surface 上所有三角面的 |世界法线·上|: 返回 [面数, 最小值, 平均值]
func _updots(mi: MeshInstance3D, surf: int) -> Array:
	var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var b: Basis = mi.global_transform.basis
	var cnt := 0
	var mn := 2.0
	var sum := 0.0
	var i := 0
	while i + 2 < vs.size():
		var nv: Vector3 = (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i])
		if nv.length() > 1e-12:
			var d: float = absf((b * nv).normalized().dot(Vector3.UP))
			mn = minf(mn, d)
			sum += d
			cnt += 1
		i += 3
	return [cnt, (mn if cnt > 0 else 0.0), (sum / float(maxi(1, cnt)))]
