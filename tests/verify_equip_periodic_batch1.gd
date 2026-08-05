extends Node
## verify_equip_periodic_batch1.gd — 新装备【批①·周期类 15 件】逐件焊死 + 量级门禁
##
## 方案书: docs/plans/20260804-新装备35件效果.md (批 A「周期类」, 用户拍板 U1=C 分 3 批)
## 覆盖: 062 069 070 072 077 079 080 081 087 088 089 090 091 092 094
##
## ★本文件的规矩(这个项目吃过亏才立的, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】, 不用随机 spawn 的敌 —— 随机敌带盾/flat_dr/未播种 RNG
##     会让精确数值在 CI 上偶发红(memory: fb-ci-vs-local-divergence)。
##   · 合成单位坐标放在 ARENA 【内】—— 放外面会被钳到同一点。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 触发一律走【真入口】`_equip_sys.fire_equip_effect(...)`(周期到点与法力条满共用的那一条),
##     不去调各效果函数的内部实现 —— memory fb-verify-must-run-the-real-path:
##     「断言函数存在」守不住「还有没有人调它」。
##   · 不依赖任何演出 tween / 弹道飞完(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##   · 每条断言都打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_periodic_batch1.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

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


## 干净合成单位: 放 ARENA 中心附近, 清掉一切会干扰精确数值的减伤/护盾/暴击。
## ★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%,
##   拿 basic 当携带者去验"32 点伤害"会量到 38(探针在 20260801 那份门禁里实测过 72 vs 60)。
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
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


## 装上一件装备(只挂条目, 不跑属性管线 —— 属性会污染"效果加了多少"的量测)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 走真入口触发一次这件装备的周期效果。
func _fire(u: Dictionary, iid: String, star: int) -> void:
	var stt: Dictionary = u["eq_state"].get(iid, {})
	u["eq_state"][iid] = stt
	_s._equip_sys.fire_equip_effect(u, iid, star, stt)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 新装备批①·周期类 15 件 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	_t_dispatch()
	_t062_mist()
	_t069_cake()
	_t070_ration()
	_t072_feast()
	_t077_derringer()
	_t079_armory()
	_t080_cannon()
	_t081_wicker()
	_t087_mint()
	_t088_scepter()
	_t089_talisman()
	_t090_codex()
	_t091_scute()
	_t092_compass()
	_t094_awaken()
	_t_magnitude()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 新装备批①周期类" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律: 15 件全部落在【同一个】 fire_equip_effect 的 match 上
#    (方案书 §1.3 / R3: 不许再造周期分发)
# ─────────────────────────────────────────────────────────────
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律 ──")
	var ids := ["p2eq_062", "p2eq_069", "p2eq_070", "p2eq_072", "p2eq_077", "p2eq_079",
		"p2eq_080", "p2eq_081", "p2eq_087", "p2eq_088", "p2eq_089", "p2eq_090",
		"p2eq_091", "p2eq_092", "p2eq_094"]
	# ★读源码找 match 分支 —— 但先剥掉注释, 否则会命中我自己写的说明文字
	#   (20260801 那份门禁的作者已经因此吃过两次亏)。
	var raw: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var code := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		code += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	var body: String = _fn_body(code, "func fire_equip_effect")
	var miss: Array = []
	for iid in ids:
		if not body.contains("\"%s\":" % iid):
			miss.append(iid)
	_ok("⓪ ★15 件全在 fire_equip_effect 的 match 里(不另起周期分发)", miss.is_empty(),
		"缺 %s" % str(miss))
	_ok("⓪ ★分母: 取到的函数体非空(%d 字符) —— 空串会让上面那条恒真" % body.length(),
		body.length() > 200, "len=%d" % body.length())
	# 分支不许重复(方案书 §5.2 第一条)
	var dup: Array = []
	for iid in ids:
		if body.count("\"%s\":" % iid) != 1:
			dup.append("%s×%d" % [iid, body.count("\"%s\":" % iid)])
	_ok("⓪ match 里没有重复 id", dup.is_empty(), str(dup))
	# 周期表: 12 件排周期, 法器 3 件【不排】(它们由法力条满触发)
	var iv: Dictionary = EquipSystem.EQ_IV_BATCH1
	_ok("⓪ 枪三件的周期 = 8 秒(枪件固定 8 秒·不吃攻速)",
		absf(float(iv.get("p2eq_077", 0.0)) - 8.0) < 0.001
		and absf(float(iv.get("p2eq_079", 0.0)) - 8.0) < 0.001
		and absf(float(iv.get("p2eq_080", 0.0)) - 8.0) < 0.001,
		"077=%s 079=%s 080=%s" % [str(iv.get("p2eq_077", "缺")), str(iv.get("p2eq_079", "缺")), str(iv.get("p2eq_080", "缺"))])
	_ok("⓪ 其余九件的周期 = 2.5 秒",
		absf(float(iv.get("p2eq_062", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_069", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_070", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_072", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_081", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_087", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_091", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_092", 0.0)) - 2.5) < 0.001
		and absf(float(iv.get("p2eq_094", 0.0)) - 2.5) < 0.001)
	_ok("⓪ ★法器三件不排周期(触发时机 = 法力条满, 排了就成两套行为)",
		not iv.has("p2eq_088") and not iv.has("p2eq_089") and not iv.has("p2eq_090"))
	# ★接线: _tick_eq_intervals 真的会查这张新表(不查 = 12 件永远不触发, 而上面的断言照样全绿)
	var tick_body: String = _fn_body(code, "func _tick_eq_intervals")
	_ok("⓪ ★★接线: _tick_eq_intervals 真的读了 EQ_IV_BATCH1", tick_body.contains("EQ_IV_BATCH1"),
		"len=%d" % tick_body.length())
	# 真的跑一遍每帧节拍: 攒够 2.5 秒必须触发(这条是"函数被调用"的直接证据)
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -260.0), 1000.0), "p2eq_070", 3)
	var hp0: float = float(u["maxHp"])
	_s._equip_sys._tick_eq_intervals(u, 2.0)
	var mid: float = float(u["maxHp"])
	_s._equip_sys._tick_eq_intervals(u, 0.6)
	_ok("⓪ ★★节拍接线: 不满 2.5 秒不触发, 满了就触发(拿 070 当探针)",
		absf(mid - hp0) < 0.01 and float(u["maxHp"]) > hp0 + 29.0,
		"2.0秒后 %.0f / 2.6秒后 %.0f (起点 %.0f)" % [mid, float(u["maxHp"]), hp0])


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


# ─────────────────────────────────────────────────────────────
# 062 雾行海葵: 3 秒未受伤 → +1 层雾隐(最多 3), 每层 +4/6/9% 闪避, 受伤清空
# ─────────────────────────────────────────────────────────────
func _t062_mist() -> void:
	print("── 062 雾行海葵 · 雾隐层 ──")
	for si in range(3):
		var per: float = [0.04, 0.06, 0.09][si]   # 需求字面值 4/6/9%
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-340.0 + 20.0 * float(si), -200.0)), "p2eq_062", si + 1)
		_s._recalc_stats(u)
		_ok("062 si=%d ★分母: 起手闪避 = 0(不是本来就有)" % si,
			absf(float(u["dodge_bonus"])) < 0.0001, "dodge=%.4f" % float(u["dodge_bonus"]))
		_fire(u, "p2eq_062", si + 1)
		_ok("062 si=%d 一层 = +%.0f%% 闪避" % [si, per * 100.0],
			absf(float(u["dodge_bonus"]) - per) < 0.0005,
			"实测 %.4f 期望 %.4f" % [float(u["dodge_bonus"]), per])
		_fire(u, "p2eq_062", si + 1)
		_fire(u, "p2eq_062", si + 1)
		_ok("062 si=%d 三层 = +%.0f%% 闪避" % [si, per * 3.0 * 100.0],
			absf(float(u["dodge_bonus"]) - per * 3.0) < 0.0005,
			"实测 %.4f 期望 %.4f" % [float(u["dodge_bonus"]), per * 3.0])
		_fire(u, "p2eq_062", si + 1)
		_fire(u, "p2eq_062", si + 1)
		_ok("062 si=%d ★层数封顶 3(再跳两次还是三层)" % si,
			absf(float(u["dodge_bonus"]) - per * 3.0) < 0.0005,
			"实测 %.4f" % float(u["dodge_bonus"]))
		# 受伤 → 清空。★用真实的承伤统计字段 _st_taken(两条伤害路径都在记)驱动
		u["_st_taken"] = int(u.get("_st_taken", 0)) + 137
		_fire(u, "p2eq_062", si + 1)
		_ok("062 si=%d ★受伤清空(闪避回到 0)" % si,
			absf(float(u["dodge_bonus"])) < 0.0005, "实测 %.4f" % float(u["dodge_bonus"]))
		_fire(u, "p2eq_062", si + 1)
		_ok("062 si=%d 清空后能重新叠(又回到一层)" % si,
			absf(float(u["dodge_bonus"]) - per) < 0.0005, "实测 %.4f" % float(u["dodge_bonus"]))


# ─────────────────────────────────────────────────────────────
# 069 珊瑚糖糕: 每 2.5 秒回复 2/3.5/5% 已损失生命
# ─────────────────────────────────────────────────────────────
func _t069_cake() -> void:
	print("── 069 珊瑚糖糕 · 回已损失生命 ──")
	for si in range(3):
		var want: float = [20.0, 35.0, 50.0][si]   # 1000 血、损失 1000×?  见下: 已损 1000-?
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0 + 20.0 * float(si), -160.0), 2000.0), "p2eq_069", si + 1)
		u["hp"] = 1000.0                              # 已损失 1000 → 2/3.5/5% = 20/35/50
		_fire(u, "p2eq_069", si + 1)
		_s._damage._heal_flush(u)
		_ok("069 si=%d 已损 1000 → 回 %.0f 点(需求 2/3.5/5%%)" % [si, want],
			absf(float(u["hp"]) - (1000.0 + want)) < 1.0,
			"hp=%.1f 期望 %.1f" % [float(u["hp"]), 1000.0 + want])
	# ★分母: 满血时不该凭空回(证明量的是"已损失生命"不是固定值)
	var f: Dictionary = _equip(_mk("fortune", "left", Vector2(-240.0, -160.0), 2000.0), "p2eq_069", 3)
	_fire(f, "p2eq_069", 3)
	_s._damage._heal_flush(f)
	_ok("069 ★分母: 满血时回 0(按已损失生命算, 不是固定值)",
		absf(float(f["hp"]) - 2000.0) < 0.01, "hp=%.1f" % float(f["hp"]))


# ─────────────────────────────────────────────────────────────
# 070 深海龟粮砖: 每 2.5 秒永久 +10/18/30 最大生命(本场累积, 无上限)
# ─────────────────────────────────────────────────────────────
func _t070_ration() -> void:
	print("── 070 深海龟粮砖 · 永久 +最大生命 ──")
	for si in range(3):
		var per: float = [10.0, 18.0, 30.0][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-200.0 + 20.0 * float(si), -160.0), 1000.0), "p2eq_070", si + 1)
		_fire(u, "p2eq_070", si + 1)
		_ok("070 si=%d 一跳 +%.0f 最大生命(★不乘 HP_MULT · CLAUDE.md §3.1)" % [si, per],
			absf(float(u["maxHp"]) - (1000.0 + per)) < 0.01,
			"maxHp=%.1f 期望 %.1f" % [float(u["maxHp"]), 1000.0 + per])
		_ok("070 si=%d 当前生命同步涨(不是只涨上限)" % si,
			absf(float(u["hp"]) - (1000.0 + per)) < 0.01, "hp=%.1f" % float(u["hp"]))
		for _k in range(9):
			_fire(u, "p2eq_070", si + 1)
		_ok("070 si=%d 十跳 = +%.0f(线性累积, 无上限)" % [si, per * 10.0],
			absf(float(u["maxHp"]) - (1000.0 + per * 10.0)) < 0.01,
			"maxHp=%.1f 期望 %.1f" % [float(u["maxHp"]), 1000.0 + per * 10.0])


# ─────────────────────────────────────────────────────────────
# 072 百年龟苓宴: 开战给全队 +60/110/180 最大生命 + 每 2.5 秒全队回 1/1.5/2.5% 已损
# ─────────────────────────────────────────────────────────────
func _t072_feast() -> void:
	print("── 072 百年龟苓宴 · 开战送血 + 全队回血 ──")
	# (a) 开战一次性 +最大生命(走真入口 _eq_apply_all_stats)
	_s._units.clear()
	var car: Dictionary = _mk("fortune", "left", Vector2(-120.0, -100.0), 1000.0)
	car["equips"] = [{"id": "p2eq_072", "star": 3}]
	var mate: Dictionary = _mk("basic", "left", Vector2(-60.0, -100.0), 1000.0)   # 不带任何装备的队友
	var foe: Dictionary = _mk("basic", "right", Vector2(200.0, -100.0), 1000.0)
	_s._equip_sys._stats._eq_apply_all_stats()
	_ok("072 ★队友(不带装备)拿到 +180 最大生命(3★需求字面值)",
		absf(float(mate["maxHp"]) - 1180.0) < 0.01, "maxHp=%.1f 期望 1180" % float(mate["maxHp"]))
	_ok("072 携带者拿到 1400(属性表 3★ hp) + 180(开战送血) = +1580",
		absf(float(car["maxHp"]) - 2580.0) < 0.01, "maxHp=%.1f 期望 2580" % float(car["maxHp"]))
	_ok("072 ★敌方不吃(只给自己这一队)",
		absf(float(foe["maxHp"]) - 1000.0) < 0.01, "敌 maxHp=%.1f" % float(foe["maxHp"]))
	var mate_hp: float = float(mate["maxHp"])
	_s._equip_sys._stats._eq_apply_all_stats()
	_ok("072 ★只给一次(再跑一遍开战管线, 队友血量不再涨)",
		absf(float(mate["maxHp"]) - mate_hp) < 0.01,
		"maxHp %.0f → %.0f" % [mate_hp, float(mate["maxHp"])])
	# (b) 周期: 全队回已损失生命
	_s._units.clear()
	var c2: Dictionary = _equip(_mk("fortune", "left", Vector2(-120.0, -60.0), 2000.0), "p2eq_072", 3)
	var m2: Dictionary = _mk("basic", "left", Vector2(-60.0, -60.0), 2000.0)
	var e2: Dictionary = _mk("basic", "right", Vector2(200.0, -60.0), 2000.0)
	c2["hp"] = 1000.0
	m2["hp"] = 1000.0
	e2["hp"] = 1000.0
	_fire(c2, "p2eq_072", 3)
	_s._damage._heal_flush(c2)
	_s._damage._heal_flush(m2)
	_ok("072 ★周期: 队友也回(已损 1000 × 2.5% = 25)",
		absf(float(m2["hp"]) - 1025.0) < 1.0, "队友 hp=%.1f 期望 1025" % float(m2["hp"]))
	_ok("072 周期: 携带者自己也回 25",
		absf(float(c2["hp"]) - 1025.0) < 1.0, "本体 hp=%.1f 期望 1025" % float(c2["hp"]))
	_ok("072 ★分母: 敌人一点都没回(证明作用域是全队不是全场)",
		absf(float(e2["hp"]) - 1000.0) < 0.01, "敌 hp=%.1f" % float(e2["hp"]))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 077 铜管手铳: 每 8 秒射 2/3/4 发, 每发 12/20/32 物理
# ─────────────────────────────────────────────────────────────
func _t077_derringer() -> void:
	print("── 077 铜管手铳 · 小弹连射 ──")
	for si in range(3):
		var want_n: int = [2, 3, 4][si]
		var want_d: float = [12.0, 20.0, 32.0][si]
		_s._units.clear()
		_s._pending_shots.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 0.0), 3000.0), "p2eq_077", si + 1)
		var e: Dictionary = _mk("basic", "right", Vector2(100.0, 0.0), 9000.0)
		_fire(u, "p2eq_077", si + 1)
		_ok("077 si=%d 一轮 %d 发(需求 2/3/4)" % [si, want_n],
			_s._pending_shots.size() == want_n, "pending=%d" % _s._pending_shots.size())
		_s._pending_shots.clear()
		# 单发伤害: 直接调具名结算函数(不等排队/演出 —— CLAUDE.md §3.5)
		var h0: float = float(e["hp"])
		_s._equip_sys._derringer_shot(u, si)
		_ok("077 si=%d 每发 %.0f 物理(需求 12/20/32, 目标护甲 0)" % [si, want_d],
			absf(h0 - float(e["hp"]) - want_d) < 1.01, "实掉 %.1f" % (h0 - float(e["hp"])))
	_s._units.clear()
	_s._pending_shots.clear()


# ─────────────────────────────────────────────────────────────
# 079 军械库连射机: 每 8 秒射 5/7/10 发, 每发 10/16/26 物理; 每发算入【金弹】计数
# ─────────────────────────────────────────────────────────────
func _t079_armory() -> void:
	print("── 079 军械库连射机 · 连射 + 喂金弹 ──")
	for si in range(3):
		var want_n: int = [5, 7, 10][si]
		var want_d: float = [10.0, 16.0, 26.0][si]
		_s._units.clear()
		_s._pending_shots.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 40.0), 3000.0), "p2eq_079", si + 1)
		var e: Dictionary = _mk("basic", "right", Vector2(100.0, 40.0), 9000.0)
		_fire(u, "p2eq_079", si + 1)
		_ok("079 si=%d 一轮 %d 发(需求 5/7/10)" % [si, want_n],
			_s._pending_shots.size() == want_n, "pending=%d" % _s._pending_shots.size())
		_s._pending_shots.clear()
		var h0: float = float(e["hp"])
		_s._equip_sys._armory_shot(u, si)
		_ok("079 si=%d 每发 %.0f 物理(需求 10/16/26)" % [si, want_d],
			absf(h0 - float(e["hp"]) - want_d) < 1.01, "实掉 %.1f" % (h0 - float(e["hp"])))
	# ★★金弹计数: 枪羁绊激活(3 件)后, 每射满 4 发额外多一发金弹。
	#   10 发 → 第 4/8 发各触发一次 ⇒ 排队总数 12。不喂计数的话永远是 10。
	_s._units.clear()
	_s._pending_shots.clear()
	var g: Dictionary = _mk("fortune", "left", Vector2(-300.0, 80.0), 3000.0)
	g["equips"] = [{"id": "p2eq_079", "star": 3}, {"id": "p2eq_077", "star": 1}, {"id": "p2eq_080", "star": 1}]
	g["eq_state"] = {}
	var ge: Dictionary = _mk("basic", "right", Vector2(100.0, 80.0), 9000.0)
	var saved = _s._synergy._by_side
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	_ok("079 ★分母: 三件枪 → 枪羁绊档 1 激活(不激活就没有金弹, 下面那条会恒真)",
		int(_s._synergy.tier_for(g, "枪")) == 1, "tier=%d" % int(_s._synergy.tier_for(g, "枪")))
	_s._pending_shots.clear()
	_fire(g, "p2eq_079", 3)
	_ok("079 ★★每发都算入金弹计数: 10 发 → 排 12 发(多出 2 发金弹)",
		_s._pending_shots.size() == 12, "pending=%d (期望 12)" % _s._pending_shots.size())
	_ok("079 ★分母: 靶子在场(否则 10 发全打空, 上面那条也就不成立)",
		ge.get("alive", false) and float(ge["hp"]) > 0.0)
	_s._synergy._by_side = saved
	_s._units.clear()
	_s._pending_shots.clear()


# ─────────────────────────────────────────────────────────────
# 080 穿甲重炮: 每 8 秒朝最远敌轰 120/220/400 物理, 贯穿直线, 无视 30/45/60% 护甲
# ─────────────────────────────────────────────────────────────
func _t080_cannon() -> void:
	print("── 080 穿甲重炮 · 贯穿 + 无视护甲 ──")
	for si in range(3):
		var want: float = [120.0, 220.0, 400.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-360.0, 120.0), 3000.0), "p2eq_080", si + 1)
		var a: Dictionary = _mk("basic", "right", Vector2(-60.0, 120.0), 9000.0)
		var b: Dictionary = _mk("basic", "right", Vector2(120.0, 120.0), 9000.0)
		var c: Dictionary = _mk("basic", "right", Vector2(300.0, 120.0), 9000.0)
		var off: Dictionary = _mk("basic", "right", Vector2(120.0, 380.0), 9000.0)   # 明显不在直线上
		var ha: float = float(a["hp"])
		var hb: float = float(b["hp"])
		var hc: float = float(c["hp"])
		var ho: float = float(off["hp"])
		_fire(u, "p2eq_080", si + 1)
		_ok("080 si=%d ★贯穿: 直线上三个敌人【全都】吃到 %.0f(需求 120/220/400)" % [si, want],
			absf(ha - float(a["hp"]) - want) < 1.01
			and absf(hb - float(b["hp"]) - want) < 1.01
			and absf(hc - float(c["hp"]) - want) < 1.01,
			"近 %.0f / 中 %.0f / 远 %.0f" % [ha - float(a["hp"]), hb - float(b["hp"]), hc - float(c["hp"])])
		_ok("080 si=%d ★分母: 不在直线上的敌人没吃到(证明是直线不是全场)" % si,
			absf(ho - float(off["hp"])) < 0.01, "线外掉血 %.1f" % (ho - float(off["hp"])))
	# 无视护甲: 3★ 无视 60% —— 目标护甲 100
	#   不穿甲: 100 → 倍率 1-100/140 = 0.2857 → 400×0.2857 = 114
	#   穿 60%: 有效护甲 40 → 倍率 1-40/80 = 0.5 → 400×0.5 = 200
	_s._units.clear()
	var p: Dictionary = _equip(_mk("fortune", "left", Vector2(-360.0, 200.0), 3000.0), "p2eq_080", 3)
	var t: Dictionary = _mk("basic", "right", Vector2(0.0, 200.0), 9000.0)
	t["def"] = 100.0
	t["base_def"] = 100.0
	var plain: int = _s._resolve_dmg(p, 400.0, t, false)
	var h0: float = float(t["hp"])
	_fire(p, "p2eq_080", 3)
	var dealt: float = h0 - float(t["hp"])
	_ok("080 ★分母: 同样 400 打 100 护甲【不穿甲】= 114(经典曲线 K=40)",
		plain == 114, "实测 %d" % plain)
	_ok("080 ★无视 60% 护甲 → 同一发打成 200(有效护甲 100→40)",
		absf(dealt - 200.0) < 1.01, "实掉 %.1f 期望 200" % dealt)
	_ok("080 ★★结算完把 armor_pen_pct 还原(临时抬高不能漏还 —— 漏还 = 携带者从此永久穿甲)",
		absf(float(p.get("armor_pen_pct", 0.0))) < 0.0001,
		"armor_pen_pct=%.3f" % float(p.get("armor_pen_pct", 0.0)))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 081 藤编圆盾: 每 2.5 秒生成 25/45/75 护盾(不叠加, 覆盖)
# ─────────────────────────────────────────────────────────────
func _t081_wicker() -> void:
	print("── 081 藤编圆盾 · 覆盖式护盾 ──")
	for si in range(3):
		var want: float = [25.0, 45.0, 75.0][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0 + 20.0 * float(si), 240.0), 2000.0), "p2eq_081", si + 1)
		_ok("081 si=%d ★分母: 起手护盾 = 0" % si, absf(float(u["shield"])) < 0.01)
		_fire(u, "p2eq_081", si + 1)
		_ok("081 si=%d 一跳 → 护盾 %.0f(需求 25/45/75)" % [si, want],
			absf(float(u["shield"]) - want) < 0.51, "shield=%.1f" % float(u["shield"]))
		_fire(u, "p2eq_081", si + 1)
		_fire(u, "p2eq_081", si + 1)
		_ok("081 si=%d ★三跳还是 %.0f(【覆盖】不是叠加 —— 叠加会变成 %.0f)" % [si, want, want * 3.0],
			absf(float(u["shield"]) - want) < 0.51, "shield=%.1f" % float(u["shield"]))
		# 盾被打掉一半 → 下一跳补回到 want(这才叫"覆盖")
		u["shield"] = want * 0.4
		_fire(u, "p2eq_081", si + 1)
		_ok("081 si=%d 盾掉到 %.0f 后, 下一跳补回 %.0f" % [si, want * 0.4, want],
			absf(float(u["shield"]) - want) < 0.51, "shield=%.1f" % float(u["shield"]))


# ─────────────────────────────────────────────────────────────
# 087 深渊铸币机: 每 2.5 秒铸 1/2/3 枚; 无羁绊上限 6/10/15(U4-A), 与羁绊共用账本
# ─────────────────────────────────────────────────────────────
func _t087_mint() -> void:
	print("── 087 深渊铸币机 · 铸币与上限 ──")
	for si in range(3):
		var per: int = [1, 2, 3][si]
		var cap: int = [6, 10, 15][si]     # 用户拍板 U4-A: 无羁绊时按星级
		_s._gadget_syn.reset_match()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0 + 20.0 * float(si), 300.0), 2000.0), "p2eq_087", si + 1)
		_ok("087 si=%d ★分母: 起手本场铸币 = 0" % si, _s._gadget_syn.minted("left") == 0,
			"minted=%d" % _s._gadget_syn.minted("left"))
		_fire(u, "p2eq_087", si + 1)
		_ok("087 si=%d 一跳铸 %d 枚(需求 1/2/3)" % [si, per],
			_s._gadget_syn.minted("left") == per, "minted=%d" % _s._gadget_syn.minted("left"))
		for _k in range(40):
			_fire(u, "p2eq_087", si + 1)
		_ok("087 si=%d ★无羁绊时本场上限 = %d 枚(U4-A 按星级 6/10/15)" % [si, cap],
			_s._gadget_syn.minted("left") == cap, "minted=%d 期望 %d" % [_s._gadget_syn.minted("left"), cap])
	# ★与羁绊【共用同一本账】: 装备铸的币会挤占羁绊的额度(不是各记一本各自封顶)
	_s._gadget_syn.reset_match()
	var v: Dictionary = _equip(_mk("fortune", "left", Vector2(-200.0, 340.0), 2000.0), "p2eq_087", 1)
	_fire(v, "p2eq_087", 1)
	_fire(v, "p2eq_087", 1)
	_ok("087 ★★共用账本: 装备铸的币进的是 GadgetSynergySystem.minted() 那一本(不是自己另记)",
		_s._gadget_syn.minted("left") == 2, "minted=%d" % _s._gadget_syn.minted("left"))
	_s._gadget_syn.reset_match()


# ─────────────────────────────────────────────────────────────
# 088 潮汐骨杖: 法力条满 → 最近敌 30/55/95 魔法
# ─────────────────────────────────────────────────────────────
func _t088_scepter() -> void:
	print("── 088 潮汐骨杖 · 法力满放伤 ──")
	for si in range(3):
		var want: float = [30.0, 55.0, 95.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -300.0), 3000.0), "p2eq_088", si + 1)
		var near: Dictionary = _mk("basic", "right", Vector2(-100.0, -300.0), 9000.0)
		var far: Dictionary = _mk("basic", "right", Vector2(360.0, -300.0), 9000.0)
		var h0: float = float(near["hp"])
		var f0: float = float(far["hp"])
		_fire(u, "p2eq_088", si + 1)
		_ok("088 si=%d 最近敌吃 %.0f 魔法(需求 30/55/95, 魔抗 0)" % [si, want],
			absf(h0 - float(near["hp"]) - want) < 1.01, "实掉 %.1f" % (h0 - float(near["hp"])))
		_ok("088 si=%d ★分母: 远处那个没吃到(证明是单体最近敌)" % si,
			absf(f0 - float(far["hp"])) < 0.01, "远处掉 %.1f" % (f0 - float(far["hp"])))
	# ★真入口: 由【法力条满】触发(StaffSynergySystem._fire → fire_equip_effect 同一条路)
	_s._units.clear()
	var s: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -340.0), 3000.0), "p2eq_088", 3)
	var t: Dictionary = _mk("basic", "right", Vector2(-100.0, -340.0), 9000.0)
	var th: float = float(t["hp"])
	_s._staff_syn._fire(s, "p2eq_088", 3)
	_ok("088 ★★法力条满这条路也真的打出伤害(与周期走同一个 fire_equip_effect)",
		absf(th - float(t["hp"]) - 95.0) < 1.01, "实掉 %.1f" % (th - float(t["hp"])))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 089 蚀月符纸: 法力条满 → 全队回 1.5/2.5/4% 已损失生命
# ─────────────────────────────────────────────────────────────
func _t089_talisman() -> void:
	print("── 089 蚀月符纸 · 全队回血 ──")
	for si in range(3):
		var want: float = [15.0, 25.0, 40.0][si]   # 已损 1000 × 1.5/2.5/4%
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 340.0), 2000.0), "p2eq_089", si + 1)
		var m: Dictionary = _mk("basic", "left", Vector2(-240.0, 340.0), 2000.0)
		var e: Dictionary = _mk("basic", "right", Vector2(200.0, 340.0), 2000.0)
		u["hp"] = 1000.0
		m["hp"] = 1000.0
		e["hp"] = 1000.0
		_fire(u, "p2eq_089", si + 1)
		_s._damage._heal_flush(u)
		_s._damage._heal_flush(m)
		_ok("089 si=%d ★队友回 %.0f(已损 1000 × 1.5/2.5/4%%)" % [si, want],
			absf(float(m["hp"]) - (1000.0 + want)) < 1.0, "队友 hp=%.1f" % float(m["hp"]))
		_ok("089 si=%d 本体也回 %.0f" % [si, want],
			absf(float(u["hp"]) - (1000.0 + want)) < 1.0, "本体 hp=%.1f" % float(u["hp"]))
		_ok("089 si=%d ★分母: 敌人没回(作用域是全队)" % si,
			absf(float(e["hp"]) - 1000.0) < 0.01, "敌 hp=%.1f" % float(e["hp"]))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 090 万潮法典: 法力条满 → 全场敌 50/90/160 魔法 + 全队回 3/5/8% 已损 + 净化 1 种
# ─────────────────────────────────────────────────────────────
func _t090_codex() -> void:
	print("── 090 万潮法典 · 群伤 + 群奶 + 净化 ──")
	for si in range(3):
		var wd: float = [50.0, 90.0, 160.0][si]
		var wh: float = [30.0, 50.0, 80.0][si]   # 已损 1000 × 3/5/8%
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -380.0), 3000.0), "p2eq_090", si + 1)
		var m: Dictionary = _mk("basic", "left", Vector2(-240.0, -380.0), 2000.0)
		var e1: Dictionary = _mk("basic", "right", Vector2(-40.0, -380.0), 9000.0)
		var e2: Dictionary = _mk("basic", "right", Vector2(380.0, -380.0), 9000.0)   # 场地另一头
		u["hp"] = 1000.0
		m["hp"] = 1000.0
		var h1: float = float(e1["hp"])
		var h2: float = float(e2["hp"])
		m["stun_until"] = _s._t + 30.0                 # 队友身上挂一个减益等着被净化
		_fire(u, "p2eq_090", si + 1)
		_s._damage._heal_flush(u)
		_s._damage._heal_flush(m)
		_ok("090 si=%d ★全场敌人各吃 %.0f 魔法(近的和最远的都吃到)" % [si, wd],
			absf(h1 - float(e1["hp"]) - wd) < 1.01 and absf(h2 - float(e2["hp"]) - wd) < 1.01,
			"近 %.1f / 远 %.1f" % [h1 - float(e1["hp"]), h2 - float(e2["hp"])])
		_ok("090 si=%d 全队回 %.0f(已损 1000 × 3/5/8%%)" % [si, wh],
			absf(float(m["hp"]) - (1000.0 + wh)) < 1.0, "队友 hp=%.1f" % float(m["hp"]))
		_ok("090 si=%d ★净化 1 种减益(队友的眩晕被清)" % si,
			float(m.get("stun_until", 0.0)) <= _s._t,
			"stun_until-_t=%.2f" % (float(m.get("stun_until", 0.0)) - _s._t))
	# ★分母: 只净化【1 种】—— 同时挂眩晕+减速, 放完还应剩一种(按固定顺序先清眩晕)
	_s._units.clear()
	var v: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -420.0), 3000.0), "p2eq_090", 3)
	v["stun_until"] = _s._t + 30.0
	v["slow_until"] = _s._t + 30.0
	_fire(v, "p2eq_090", 3)
	_ok("090 ★只净化 1 种(眩晕清了, 减速【还在】—— 不是一次全清)",
		float(v.get("stun_until", 0.0)) <= _s._t and float(v.get("slow_until", 0.0)) > _s._t,
		"stun=%.2f slow=%.2f (_t=%.2f)" % [float(v.get("stun_until", 0.0)), float(v.get("slow_until", 0.0)), _s._t])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 091 远古龟甲片: 每 2.5 秒永久 +3/5/8 最大生命(上限 +120/220/360)
# ─────────────────────────────────────────────────────────────
func _t091_scute() -> void:
	print("── 091 远古龟甲片 · 永久 +最大生命(有上限) ──")
	for si in range(3):
		var per: float = [3.0, 5.0, 8.0][si]
		var cap: float = [120.0, 220.0, 360.0][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-160.0 + 20.0 * float(si), -420.0), 1000.0), "p2eq_091", si + 1)
		_fire(u, "p2eq_091", si + 1)
		_ok("091 si=%d 一跳 +%.0f 最大生命(需求 3/5/8)" % [si, per],
			absf(float(u["maxHp"]) - (1000.0 + per)) < 0.01,
			"maxHp=%.1f 期望 %.1f" % [float(u["maxHp"]), 1000.0 + per])
		for _k in range(200):
			_fire(u, "p2eq_091", si + 1)
		_ok("091 si=%d ★封顶 +%.0f(需求 120/220/360; 灌 200 跳也不超)" % [si, cap],
			absf(float(u["maxHp"]) - (1000.0 + cap)) < 0.01,
			"maxHp=%.1f 期望 %.1f" % [float(u["maxHp"]), 1000.0 + cap])


# ─────────────────────────────────────────────────────────────
# 092 沉船罗盘: 每 2.5 秒永久 +1/2/3 攻击力(上限 +30/60/100)
# ─────────────────────────────────────────────────────────────
func _t092_compass() -> void:
	print("── 092 沉船罗盘 · 永久 +攻击力(有上限) ──")
	for si in range(3):
		var per: float = [1.0, 2.0, 3.0][si]
		var cap: float = [30.0, 60.0, 100.0][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-100.0 + 20.0 * float(si), -420.0), 1000.0), "p2eq_092", si + 1)
		var a0: float = float(u["base_atk"])
		var atk0: float = float(u["atk"])
		_fire(u, "p2eq_092", si + 1)
		_ok("092 si=%d 一跳 +%.0f 攻击力(需求 1/2/3)" % [si, per],
			absf(float(u["base_atk"]) - a0 - per) < 0.01,
			"base_atk %.1f→%.1f" % [a0, float(u["base_atk"])])
		_ok("092 si=%d ★写的是 base_atk 且 atk 真的跟着涨(写 atk 会被 _recalc_stats 冲掉)" % si,
			float(u["atk"]) > atk0 + per - 0.51,
			"atk %.1f→%.1f" % [atk0, float(u["atk"])])
		for _k in range(200):
			_fire(u, "p2eq_092", si + 1)
		_ok("092 si=%d ★封顶 +%.0f(需求 30/60/100)" % [si, cap],
			absf(float(u["base_atk"]) - a0 - cap) < 0.01,
			"base_atk %.1f→%.1f 期望 +%.0f" % [a0, float(u["base_atk"]), cap])


# ─────────────────────────────────────────────────────────────
# 094 觉醒之核: 本路开打满 15/12/10 秒 → +8/14/22% 增伤(一次性 · 自存 t0)
# ─────────────────────────────────────────────────────────────
func _t094_awaken() -> void:
	print("── 094 觉醒之核 · 本路计时觉醒 ──")
	for si in range(3):
		var need: float = [15.0, 12.0, 10.0][si]
		var amp: float = [0.08, 0.14, 0.22][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-40.0 + 20.0 * float(si), -420.0), 1000.0), "p2eq_094", si + 1)
		_fire(u, "p2eq_094", si + 1)
		_ok("094 si=%d 刚开打不觉醒(增伤仍是 0)" % si,
			absf(float(u.get("damage_amp", 0.0))) < 0.0001,
			"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))
		var stt: Dictionary = u["eq_state"]["p2eq_094"]
		_ok("094 si=%d ★自存了 t0(不是直接读全局 _t)" % si, stt.has("awk_t0"),
			"awk_t0=%s" % str(stt.get("awk_t0", "缺")))
		# 把 t0 往回拨到"差 0.1 秒就满" → 仍不该觉醒
		stt["awk_t0"] = _s._t - need + 0.1
		_fire(u, "p2eq_094", si + 1)
		_ok("094 si=%d 差 0.1 秒还不觉醒(门槛就是 %.0f 秒)" % [si, need],
			absf(float(u.get("damage_amp", 0.0))) < 0.0001,
			"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))
		stt["awk_t0"] = _s._t - need - 0.1
		_fire(u, "p2eq_094", si + 1)
		_ok("094 si=%d ★满 %.0f 秒 → 增伤 +%.0f%%(需求 8/14/22%%)" % [si, need, amp * 100.0],
			absf(float(u.get("damage_amp", 0.0)) - amp) < 0.0005,
			"damage_amp=%.3f 期望 %.3f" % [float(u.get("damage_amp", 0.0)), amp])
		for _k in range(5):
			_fire(u, "p2eq_094", si + 1)
		_ok("094 si=%d ★一次性(再跳 5 次不会继续涨)" % si,
			absf(float(u.get("damage_amp", 0.0)) - amp) < 0.0005,
			"damage_amp=%.3f" % float(u.get("damage_amp", 0.0)))
	# ★★CLAUDE.md §3.4: _t 跨上路/下路/决胜累加、永不重置 ——
	#   把全局时钟推到远大于门槛处再【新建一路的单位】, 它必须【不】立刻觉醒。
	#   直接判 `_t >= 15` 的实现在这里会当场红。
	_s._units.clear()
	var t_saved: float = _s._t
	_s._t = 500.0                                  # 模拟下路开场: 全局钟早就过了 15 秒
	var d: Dictionary = _mk("fortune", "left", Vector2(0.0, -460.0), 1000.0)
	d["equips"] = [{"id": "p2eq_094", "star": 3}]
	d["eq_state"] = {}
	_s._equip_sys._stats._eq_apply_all_stats()     # 真入口: 每一路开战都会跑的属性管线
	var dstt: Dictionary = d["eq_state"].get("p2eq_094", {})
	_ok("094 ★★换路: 开战管线把 t0 重置成本路的开打时刻(500), 不是 0",
		absf(float(dstt.get("awk_t0", -1.0)) - 500.0) < 0.01,
		"awk_t0=%s" % str(dstt.get("awk_t0", "缺")))
	d["damage_amp"] = 0.0
	_fire(d, "p2eq_094", 3)
	_ok("094 ★★换路: 下路一开场【不】白送觉醒(_t=500 但本路才刚开打)",
		absf(float(d.get("damage_amp", 0.0))) < 0.0001,
		"damage_amp=%.3f" % float(d.get("damage_amp", 0.0)))
	_s._t = 512.0                                  # 本路过了 12 秒
	_fire(d, "p2eq_094", 3)
	_ok("094 ★换路后本路满 10 秒照样觉醒(不是被永久关掉)",
		absf(float(d.get("damage_amp", 0.0)) - 0.22) < 0.0005,
		"damage_amp=%.3f" % float(d.get("damage_amp", 0.0)))
	_s._t = t_saved
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
#  R1 量级门禁: 「本场永久累积」四件跑满一路的总增益要落在设计带内
#
#  ★为什么要有它(方案书 R1): 070/091/092/094 都是【本场永久累积】, 互相叠加且没有统一账本。
#    memory [[fb-verify-magnitude-not-just-correctness]]: 数值"对不对"和"合不合理"是两件事 ——
#    彩虹那次五条探针全绿(含反向验证)仍把胜率从 14% 推到 97%。
#
#  ★口径(写清楚, 免得下次有人按别的口径算出别的数):
#    · 参考时长取【单路 60 秒】⇒ 2.5 秒一跳 = 24 跳。战场 40 秒进决胜, 60 秒是偏长的一路。
#    · 增益不跟"龟基础属性"比, 而是跟【这件装备自己三星印在面板上的属性】比 ——
#      要量的是"效果加了多少", 不是"批 3 的属性表定得高不高"(那是另一条门禁的活)。
#      分母是 EquipStats 里的三星值, 与效果常量【不是同一个常量】, 所以不是恒真式。
#    · 带宽 [0.30, 1.60]: 下沿=效果起码得有存在感; 上沿=一路打完最多再送一件自己(不到两件)。
#      ⚠ 这条带是我推的参考值, 【不是用户拍的】—— 与 verify_synergy_magnitude 同一披露口径。
# ═════════════════════════════════════════════════════════════
const REF_TICKS := 24          # 参考单路 60 秒 ÷ 2.5 秒
const BAND_LO := 0.30
const BAND_HI := 1.60


func _t_magnitude() -> void:
	print("── R1 量级: 本场累积类跑满一路(24 跳) ──")
	_s._units.clear()
	# 070 深海龟粮砖 3★: 面板 +700 生命
	var a: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 420.0), 1000.0), "p2eq_070", 3)
	for _k in range(REF_TICKS):
		_fire(a, "p2eq_070", 3)
	var g070: float = float(a["maxHp"]) - 1000.0
	# 091 远古龟甲片 3★: 面板 +260 生命
	var b: Dictionary = _equip(_mk("fortune", "left", Vector2(-240.0, 420.0), 1000.0), "p2eq_091", 3)
	for _k2 in range(REF_TICKS):
		_fire(b, "p2eq_091", 3)
	var g091: float = float(b["maxHp"]) - 1000.0
	# 092 沉船罗盘 3★: 面板 +66 攻击力
	var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-180.0, 420.0), 1000.0), "p2eq_092", 3)
	var c0: float = float(c["base_atk"])
	for _k3 in range(REF_TICKS):
		_fire(c, "p2eq_092", 3)
	var g092: float = float(c["base_atk"]) - c0

	var rows := [
		["070 深海龟粮砖", g070, 700.0, 720.0],   # 24×30 = 720(无上限)
		["091 远古龟甲片", g091, 260.0, 192.0],   # 24×8 = 192(未触顶, 上限 360)
		["092 沉船罗盘  ", g092, 66.0, 72.0],     # 24×3 = 72(未触顶, 上限 100)
	]
	print("  %-16s %-10s %-10s %s" % ["装备", "一路增益", "面板三星值", "倍率"])
	var bad: Array = []
	for r in rows:
		var ratio: float = float(r[1]) / maxf(1.0, float(r[2]))
		print("  %-16s %-10.0f %-10.0f ×%.2f" % [str(r[0]), float(r[1]), float(r[2]), ratio])
		if ratio < BAND_LO or ratio > BAND_HI:
			bad.append("%s ×%.2f 不在 [%.2f, %.2f]" % [str(r[0]).strip_edges(), ratio, BAND_LO, BAND_HI])
	for r2 in rows:
		# 分母兼锚: 24 跳的实际增益必须等于硬写的期望数, 否则上面的倍率是拿错数算的
		_ok("R1 %s 24 跳增益 = %.0f(硬写期望)" % [str(r2[0]).strip_edges(), float(r2[3])],
			absf(float(r2[1]) - float(r2[3])) < 0.51,
			"实测 %.1f" % float(r2[1]))
	_ok("R1 ★★三件累积类的一路增益全部落在 [%.2f, %.2f] × 自身面板值" % [BAND_LO, BAND_HI],
		bad.is_empty(), str(bad))
	# 094 是【增伤%】不换算成倍率, 单卡绝对上限
	var d: Dictionary = _equip(_mk("fortune", "left", Vector2(-120.0, 420.0), 1000.0), "p2eq_094", 3)
	var dstt: Dictionary = {}
	d["eq_state"]["p2eq_094"] = dstt
	dstt["awk_t0"] = _s._t - 99.0
	for _k4 in range(REF_TICKS):
		_fire(d, "p2eq_094", 3)
	print("  %-16s 增伤 +%.0f%%(一次性)" % ["094 觉醒之核", float(d.get("damage_amp", 0.0)) * 100.0])
	_ok("R1 ★094 跑满一路的增伤 ≤ 25% (乘在所有伤害上的通道, 只卡绝对上限)",
		float(d.get("damage_amp", 0.0)) <= 0.25 + 0.0001,
		"damage_amp=%.3f" % float(d.get("damage_amp", 0.0)))
	_ok("R1 ★分母: 094 确实觉醒了(免得把「没触发」混成「没超标」)",
		float(d.get("damage_amp", 0.0)) > 0.0,
		"damage_amp=%.3f" % float(d.get("damage_amp", 0.0)))
	_s._units.clear()
