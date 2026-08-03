extends Node
## verify_equip_new_stats.gd — 三个新属性字段 + D16「多件叠加统一用加」（批 2 · 方案书 §4.7）
##
## 守四组：
##   ① 三个新字段（`_aspdPct` / `_mspdPct` / `_rangePct`）**显示与施加成对存在**
##      —— 这正是 `dodgePct` 栽过的地方：展示分支写了、施加分支从来没有，
##         图鉴上写着"闪避 +15%"而战斗里一点都不加，活了很久没人发现（v0.18.9 才修）。
##   ② 叠加口径是【加】不是【乘】（D16「u4加吧」）：3 件 +20% 应得 1.60，不是 1.728。
##   ③ ★★R21 点名的那条：**038 信号放大器 + 056 飞镖 3★** 的组合值。
##      D16 只改运算符、不改任何字面量 ⇒ **`tooltip_number_audit` 抓不到**
##      （它只把文案里的三元组 `a/b/c` 去匹配代码里的 `[N,N,N]` 字面量）。
##      ⇒ 这条断言是这次改动**唯一**的守卫。
##   ④ 射程 / 移速走的是**独立乘子**，不是就地改 `atk_range` / `move_spd`
##      —— 就地改会被形态切换（双生 / 熔岩 / 机甲）整个覆盖掉，也会在升星/换路重建时重复乘。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_new_stats.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 装备新属性字段 + D16 加法叠加 (批2) ===")
	RB.DEBUG_EDIT = true                      # 空编辑场, 不跑整场战斗
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	# 施加子系统挂在 EquipSystem 下(battle._equip_sys._stats), 不是主场景的直接成员。
	var _ap = s._equip_sys._stats
	if _ap == null:
		print('  [FAIL] 拿不到 EquipStatsApply'); get_tree().quit(1); return

	# ── ① 显示与施加成对 ────────────────────────────────────────
	# 展示侧: 造一个带该字段的假 stats dict, 看 stat_lines 认不认。
	# 施加侧: 走真入口 _apply_stat_dict, 看单位字典上的通道变了没有。
	var pairs := [
		["_aspdPct", "攻击速度", "aspd_perm"],
		["_mspdPct", "移动速度", "move_perm"],
		["_rangePct", "攻击射程", "range_perm"],
		["_echargePct", "龟能充能速率", "echarge_perm"],   # 本来就有, 一并守住
	]
	for p in pairs:
		var key: String = p[0]
		var label: String = p[1]
		var chan: String = p[2]
		# 展示
		var shown := false
		for kv in EquipStats.lines_of({key: 20}):
			if str(kv[0]) == label:
				shown = true
		_ok("① %s 在属性栏显示为「%s」" % [key, label], shown)
		# 施加
		var u := _mk()
		_ap.apply_stat_dict(u, {key: 20}, "p2eq_001")
		_ok("① %s 真的施加到 %s(20%% → 1.20)" % [key, chan],
			absf(float(u.get(chan, 1.0)) - 1.20) < 0.001, "实得 %.3f" % float(u.get(chan, 1.0)))

	# ── ② 叠加用加不用乘 ────────────────────────────────────────
	# 3 件 +20%: 加法 = 1 + 0.2×3 = 1.60; 乘法 = 1.2³ = 1.728。差 8%, 一眼分得开。
	for p in pairs:
		var key: String = p[0]
		var chan: String = p[2]
		var u := _mk()
		for i in range(3):
			_ap.apply_stat_dict(u, {key: 20}, "p2eq_001")
		_ok("② %s 三件叠加 = 1.60(加法) 而不是 1.728(乘法)" % key,
			absf(float(u.get(chan, 1.0)) - 1.60) < 0.001, "实得 %.3f" % float(u.get(chan, 1.0)))

	# ── ③ ★★R21: 038 + 056 3★ 的组合值 ────────────────────────
	# 038 信号放大器 = 固定 +30% 攻速(不分星); 056 飞镖 3★ = +150%。
	# 加法: 1 + 0.30 + 1.50 = 2.80  ／  乘法: 1.30 × 2.50 = 3.25
	# ★这是 D16 唯一会被察觉的地方, 而 tooltip_number_audit 看不到它(只改运算符不改字面量)。
	var u2 := _mk()
	_ap._eq_apply_one_stats(u2, "p2eq_038", 1)
	_ok("③ 038 单件 = 1.30", absf(float(u2.get("aspd_perm", 1.0)) - 1.30) < 0.001,
		"实得 %.3f" % float(u2.get("aspd_perm", 1.0)))
	_ap._eq_apply_one_stats(u2, "p2eq_056", 3)
	_ok("③ ★★038 + 056(3★) = 2.80(加法) 而不是 3.25(乘法) —— R21 唯一的守卫",
		absf(float(u2.get("aspd_perm", 1.0)) - 2.80) < 0.001,
		"实得 %.3f" % float(u2.get("aspd_perm", 1.0)))
	# ★★必须【两个顺序都验】—— 反向验证时发现的坑:
	#   只按 038→056 的顺序验, 把 038 单独改回乘法【一条都不红】。
	#   因为 038 是第一件, 作用在基数 1.0 上时 1.0×(1+0.3) 与 1.0+0.3 恰好同值,
	#   差异全被后一件吃掉了。换成 056→038 的顺序, 038 就作用在 2.50 上, 乘法立刻露出来
	#   (2.50×1.30 = 3.25 ≠ 2.80)。⇒ 一条"组合值"断言只能守住【后施加的那一件】。
	var u2b := _mk()
	_ap._eq_apply_one_stats(u2b, "p2eq_056", 3)
	_ap._eq_apply_one_stats(u2b, "p2eq_038", 1)
	_ok("③ ★★换个顺序(056→038)仍是 2.80 —— 这条才守得住 038 那一件",
		absf(float(u2b.get("aspd_perm", 1.0)) - 2.80) < 0.001,
		"实得 %.3f" % float(u2b.get("aspd_perm", 1.0)))

	# ── ④ 独立乘子, 不就地改基础值 ──────────────────────────────
	var u3 := _mk()
	var r0: float = float(u3["atk_range"])
	var m0: float = float(u3["move_spd"])
	_ap.apply_stat_dict(u3, {"_rangePct": 30, "_mspdPct": 30}, "p2eq_001")
	_ok("④ ★基础 atk_range 没被就地改(形态切换会覆盖它)",
		absf(float(u3["atk_range"]) - r0) < 0.001, "%.0f → %.0f" % [r0, float(u3["atk_range"])])
	_ok("④ ★基础 move_spd 没被就地改", absf(float(u3["move_spd"]) - m0) < 0.001,
		"%.0f → %.0f" % [m0, float(u3["move_spd"])])
	_ok("④ 生效射程 = 基础 × range_perm = %.0f" % (r0 * 1.3),
		absf(s._eff_range(u3) - r0 * 1.3) < 0.01, "实得 %.1f" % s._eff_range(u3))
	# ★换形态之后加成必须还在 —— 就地乘的写法在这里会归零。
	u3["atk_range"] = 400.0                      # 模拟双生/熔岩切远程形态
	_ok("④ ★★换形态(atk_range 被整个覆盖)后, 装备射程加成仍在: 400×1.3=520",
		absf(s._eff_range(u3) - 520.0) < 0.01, "实得 %.1f" % s._eff_range(u3))

	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装备新属性字段(批2)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 干净合成单位 —— 只带这几条断言真正读的字段（memory fb-ci-vs-local-divergence）。
func _mk() -> Dictionary:
	# ★buffs / base_* 是 _recalc_stats 直接下标读的(不是 .get) —— 少了会 SCRIPT ERROR。
	#   断言照样绿, 但 run-tests.sh 的致命正则会把整个测试判红, 而且看起来像断言没打出来。
	return {"id": "basic", "side": "left", "alive": true, "hp": 1000.0, "maxHp": 1000.0,
		"atk_range": 200.0, "move_spd": 100.0, "eq_state": {}, "equips": [], "buffs": {},
		"base_atk": 100.0, "base_def": 0.0, "base_mr": 0.0, "atk": 100.0, "def": 0.0, "mr": 0.0,
		"crit": 0.0, "crit_dmg": 1.5, "armor_pen": 0.0, "magic_pen": 0.0, "lifesteal": 0.0}
