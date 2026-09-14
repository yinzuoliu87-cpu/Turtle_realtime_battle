extends Node
## verify_extra_true_ledger.gd — 金弹·火控 / 腐蚀 的额外真伤必须进伤害账(第九批 D3)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来 (2026-09-15, 077~086 调查)
## ══════════════════════════════════════════════════════════════════
## 探针: 一段 100 伤害带 60% 金弹, 目标实际掉血 160, 但 `_st_taken` 与 `_st_dealt` 都只 +100。
## 根因: `battle_damage.gd` 把 `dmg * _gold` / `dmg * _cor` 加进了扣血, 记账却用加之前的 `dmg`。
## 影响: 结算面板少算; 085 压电陶瓷片按伤害账差分转龟能, 该转 30 实转 15。
## 墨迹(线条被动)那份额外真伤早就单独进账了 —— 金弹与腐蚀是漏了这一步。
##
## ★判据量【产品自己的账】对【实际掉血】, 不数我插的标记; 期望系数写死(60% 金弹 / 3★ 压电 15%)。
##   干净合成单位: 护甲 / 魔抗 / 减伤 / 暴击 / 闪避全清零 ⇒ 账 == 掉血 才成立(分母①先证明这一点)。
const GOLD_PCT := 0.60          # 本测试给攻击者挂的金弹比例
const PIEZO_3STAR := 0.15       # 085 文案: 3★ 把受到伤害的 15% 转成龟能

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _mk(id: String, side: String, off: Vector2, hp: float = 900000.0) -> Dictionary:
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
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["corrode_stacks"] = 0
	u["corrode_tier"] = 0
	_s._units.append(u)
	return u


func _taken(u: Dictionary) -> int:
	return int(u.get("_st_taken", 0))


func _dealt(u: Dictionary) -> int:
	return int(u.get("_st_dealt", 0))


func _tru(u: Dictionary) -> int:
	return int((u.get("_st_taken_by_type", {}) as Dictionary).get("tru", 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 额外真伤进伤害账: 金弹·火控 / 腐蚀 (第九批 D3) ===")
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	_s._units.clear()

	var att: Dictionary = _mk("green", "left", Vector2(-160.0, 0.0))
	var tgt: Dictionary = _mk("green", "right", Vector2(160.0, 0.0))

	# ── ① 分母: 不带额外真伤时, 账 == 掉血(干净单位才成立) ──
	var h0: float = float(tgt["hp"])
	var t0: int = _taken(tgt)
	var d0: int = _dealt(att)
	_s._damage._apply_damage_from(att, tgt, 100, Color.WHITE)
	var hd0: float = h0 - float(tgt["hp"])
	_ok("★分母①: 不带额外真伤打 100 → 掉血 %.1f · 承伤账 +%d · 输出账 +%d(三者都应为 100)"
		% [hd0, _taken(tgt) - t0, _dealt(att) - d0],
		absf(hd0 - 100.0) < 0.51 and _taken(tgt) - t0 == 100 and _dealt(att) - d0 == 100,
		"单位不干净 ⇒ 下面「账 == 掉血」的判据不成立")

	# ── ② 金弹 60% ──
	att["_golden_pct"] = GOLD_PCT
	var h1: float = float(tgt["hp"])
	var t1: int = _taken(tgt)
	var d1: int = _dealt(att)
	var r1: int = _tru(tgt)
	_s._damage._apply_damage_from(att, tgt, 100, Color.WHITE)
	var hd1: float = h1 - float(tgt["hp"])
	_ok("★分母②: 金弹真的生效了 —— 打 100 实际掉血 %.1f(应为 160)" % hd1,
		absf(hd1 - 160.0) < 0.51, "金弹没生效 ⇒ ② 量不到额外真伤")
	_ok("② 金弹那 60 真伤进了承伤账(+%d, 应 == 掉血 %.0f)" % [_taken(tgt) - t1, hd1],
		absf(float(_taken(tgt) - t1) - hd1) < 1.01, "账比掉血少 ⇒ 结算面板少算、085 少转")
	_ok("② 也进了攻击者的输出账(+%d, 应为 160)" % (_dealt(att) - d1),
		_dealt(att) - d1 == 160, "")
	_ok("② 额外那 60 记在【真伤】分桶(+%d, 应为 60)" % (_tru(tgt) - r1),
		_tru(tgt) - r1 == 60, "")
	att["_golden_pct"] = 0.0

	# ── ③ 腐蚀满 5 层 · 普攻/技能路 ──
	tgt["corrode_stacks"] = 5
	tgt["corrode_tier"] = 3
	var h2: float = float(tgt["hp"])
	var t2: int = _taken(tgt)
	_s._damage._apply_damage_from(att, tgt, 100, Color.WHITE)
	var hd2: float = h2 - float(tgt["hp"])
	_ok("★分母③: 腐蚀真的转了真伤 —— 打 100 掉血 %.1f(> 100 才说明转了)" % hd2, hd2 > 110.0, "")
	_ok("③ 腐蚀 · 普攻路: 承伤账增量 == 实际掉血(+%d vs %.1f)" % [_taken(tgt) - t2, hd2],
		absf(float(_taken(tgt) - t2) - hd2) < 1.01, "")

	# ── ④ 腐蚀满 5 层 · 持续伤害路(_apply_damage) ──
	var h3: float = float(tgt["hp"])
	var t3: int = _taken(tgt)
	var d3: int = _dealt(att)
	_s._damage._apply_damage(tgt, 100, Color.WHITE, att, "dot")
	var hd3: float = h3 - float(tgt["hp"])
	_ok("④ 腐蚀 · 持续伤害路: 承伤账增量 == 实际掉血(+%d vs %.1f)" % [_taken(tgt) - t3, hd3],
		hd3 > 110.0 and absf(float(_taken(tgt) - t3) - hd3) < 1.01, "两条伤害路径只修一条(CLAUDE.md §3.3)")
	_ok("④ 持续伤害路也进施加者的输出账(+%d vs 掉血 %.1f)" % [_dealt(att) - d3, hd3],
		absf(float(_dealt(att) - d3) - hd3) < 1.01, "")
	tgt["corrode_stacks"] = 0
	tgt["corrode_tier"] = 0

	# ── ⑤ 085 压电陶瓷片: 按伤害账转龟能, 金弹那份也要算 ──
	var ud: Dictionary = _mk("fortune", "right", Vector2(160.0, 140.0))
	ud["equips"] = [{"id": "p2eq_085", "star": 3}]
	ud["eq_state"] = {}
	_s._equip_sys._stats._eq_apply_all_stats()
	_s._equip_sys._eq_tick(ud, 0.016)          # 先把开局的残差结掉
	var e0: float = float(ud.get("energy_bank", 0.0))
	att["_golden_pct"] = GOLD_PCT
	_s._damage._apply_damage_from(att, ud, 100, Color.WHITE)
	att["_golden_pct"] = 0.0
	_s._equip_sys._eq_tick(ud, 0.016)          # 真入口: 残差结算
	var conv: float = float(ud.get("energy_bank", 0.0)) - e0
	_ok("⑤ 085 挨 100 + 60%% 金弹(实际掉血 160) → 转出 %.2f 龟能(应为 160 × 15%% = 24, 只算名义伤害是 15)" % conv,
		absf(conv - 160.0 * PIEZO_3STAR) < 0.51, "")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
