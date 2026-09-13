extends Node
## verify_conch_worm_033.gd — 033 复活海螺【变虫】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「**彻底阵亡**(所有复活机会用尽)时, 在**原位**变形为一只小虫
##   (**100/1500/10000** 生命 · **50/80/200** 攻击力, **无护甲魔抗**, 只有星级无等级),
##   自动攻击最近的敌人, 攻击速度 `EquipSystem.WORM_ASPD` /秒, 造成 **1×攻击力的物理伤害**;
##   小虫诞生时随机携带 **3 件** 1/2/3 星的 `CONCH_COST_MIN` 费或 `CONCH_COST_MAX` 费装备。」
## 「★3: 变虫后每 `WORM_SPLIT_IV` 秒在空位分裂出一只新小虫(上限 `WORM_CAP` 只)。」
##
## ★这一件**原来没有台子**(`verify_wormhole_escape` 是星际龟的技能, 无关)。
## ★结算层查下来是健康的: 变形是同步的(`_spawn_summon`), 分裂走 `_tick_unit` 的
##   `worm_split_t` 每帧累加 —— 都在 sim 时钟上。tween 只用在小虫立绘的出场缩放(纯观感)。
## ★本轮顺手修了一处**同一个数存两份**: 变形那一行写死 `1.0 / 0.65`,
##   而常量 `WORM_ASPD` 就在旁边、文案用的也是 `{C:EquipSystem.WORM_ASPD}` 这个占位符 ——
##   分裂那条路读的是常量, 变形这条路读的是字面量, 改常量就会漂。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")

const WHP := [100.0, 1500.0, 10000.0]
const WATK := [50.0, 80.0, 200.0]

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	return u


func _worms(side: String) -> Array:
	var out: Array = []
	for o in _s._units:
		if str(o.get("summon_kind", "")) == "worm" and o.get("alive", false) \
				and str(o.get("side", "")) == side:
			out.append(o)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 033 复活海螺: 彻底阵亡 → 原位变虫 (攻速 %.2f/秒) ===" % ES.WORM_ASPD)
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ── ① ★★★走真入口 `_eq_on_death`: 变虫 + 数值吃星级 + 原位 ────────
	for si in [0, 1, 2]:
		_s._units.clear()
		var dead: Dictionary = _mk(640.0, 380.0, "left")
		dead["equips"] = [{"id": "p2eq_033", "star": [1, 2, 3][si]}]
		dead["eq_state"] = {}
		var where: Vector2 = dead["pos"]
		_s._units.append(dead)
		_s._units.append(_mk(900.0, 380.0, "right"))
		_s._equip_sys._eq_on_death(dead, null)
		var ws: Array = _worms("left")
		if ws.is_empty():
			_ok("① ★★★%d 星: 阵亡后变出小虫" % [si + 1], false, "一只都没有 —— on-death 那条路没走通")
			continue
		var w: Dictionary = ws[0]
		## ★★判据写过一版是错的: 我直接断言「血 == 100/1500/10000」, 实测 400/2200/10600 ——
		##   差额不是 bug, 是**那 3 件随机装备加的属性**(`_conch_grant_equips` 会走
		##   `_eq_apply_one_stats`)。判据必须把这份加成**从产品自己的表里算出来再减掉**,
		##   不能拍脑袋放宽阈值(memory [[fb-my-thresholds-degrade-good-assets]])。
		var bonus := {"hp": 0.0, "atk": 0.0, "def": 0.0, "mr": 0.0}
		for e in w.get("equips", []):
			var st: Array = _s.EquipStats.STATS.get(str(e.get("id", "")), [])
			var idx: int = clampi(int(e.get("star", 1)), 1, 3) - 1
			if idx < st.size():
				for k in bonus.keys():
					bonus[k] = float(bonus[k]) + float((st[idx] as Dictionary).get(k, 0))
		var base_hp: float = float(w["maxHp"]) - float(bonus["hp"])
		var base_atk: float = float(w["atk"]) - float(bonus["atk"])
		var base_def: float = float(w["def"]) - float(bonus["def"])
		var base_mr: float = float(w["mr"]) - float(bonus["mr"])
		_ok("① ★★★%d 星【扣掉三件装备的加成后】: 血 %.0f(应 %.0f) / 攻 %.0f(应 %.0f) / 双抗 %.0f+%.0f(应 0+0)"
			% [si + 1, base_hp, WHP[si], base_atk, WATK[si], base_def, base_mr],
			absf(base_hp - WHP[si]) < 1.0 and absf(base_atk - WATK[si]) < 1.0
				and absf(base_def) < 0.01 and absf(base_mr) < 0.01,
			"文案: 只有星级无等级 ⇒ 底子即实际, 不吃等级系数; 装备加成 血+%.0f 攻+%.0f 甲+%.0f 抗+%.0f"
				% [bonus["hp"], bonus["atk"], bonus["def"], bonus["mr"]])
		_ok("① ★★%d 星: 变在**原位**(%.0f,%.0f → %.0f,%.0f)"
			% [si + 1, where.x, where.y, float(w["pos"].x), float(w["pos"].y)],
			(w["pos"] as Vector2).distance_to(where) < 1.0,
			"文案明写「在原位变形」")

	# ── ② ★★攻速读的是常量, 不是写死的字面量 ──────────────────────────
	## 原来变形那一行写死 `1.0 / 0.65`, 而分裂那条路读 `EquipSystem.WORM_ASPD`
	## ⇒ **同一个数存两份**, 改常量只有一半跟着变。
	_s._units.clear()
	var d2: Dictionary = _mk(640.0, 380.0, "left")
	d2["equips"] = [{"id": "p2eq_033", "star": 3}]
	d2["eq_state"] = {}
	_s._units.append(d2)
	_s._units.append(_mk(900.0, 380.0, "right"))
	_s._equip_sys._eq_on_death(d2, null)
	var w2a: Array = _worms("left")
	_ok("② ★分母: 小虫在场", not w2a.is_empty())
	if not w2a.is_empty():
		var w2: Dictionary = w2a[0]
		_ok("② ★★攻击间隔 %.4f 秒 = 1 / WORM_ASPD(%.2f)"
			% [float(w2["atk_interval"]), ES.WORM_ASPD],
			absf(float(w2["atk_interval"]) - 1.0 / ES.WORM_ASPD) < 0.0001,
			"写死 0.65 的话, 改常量文案会变而代码不变")
		# ── ③ ★★诞生带 3 件 4/5 费装备 ───────────────────────────────
		var eq: Array = w2.get("equips", [])
		_ok("③ ★★★小虫带了 %d 件装备(应 3 件)" % eq.size(), eq.size() == 3,
			"文案: 诞生时随机携带 3 件")
		var costs: Array = []
		var bad_cost := 0
		var bad_star := 0
		for e in eq:
			var eid: String = str(e.get("id", ""))
			var cost := -1
			for it in DataRegistry.phase2_equipment:
				if str(it.get("id", "")) == eid:
					cost = int(it.get("cost", -1))
			costs.append(cost)
			if cost != ES.CONCH_COST_MIN and cost != ES.CONCH_COST_MAX:
				bad_cost += 1
			if int(e.get("star", 0)) != 3:
				bad_star += 1
		_ok("③ ★★三件都是 %d 费或 %d 费(实测 %s, 违规 %d 件)"
			% [ES.CONCH_COST_MIN, ES.CONCH_COST_MAX, str(costs), bad_cost],
			bad_cost == 0,
			"池子若为空, 产品是 push_warning + 不带装备, 不静默塞别的费用")
		_ok("③ ★★3 星携带者 ⇒ 三件都是 3 星(违规 %d 件)" % bad_star, bad_star == 0,
			"文案: 1/2/3 星, 跟携带者的星级")

	# ── ④ ★★★1×攻击力的【物理】伤害 ─────────────────────────────────
	_s._units.clear()
	var d4: Dictionary = _mk(640.0, 380.0, "left")
	d4["equips"] = [{"id": "p2eq_033", "star": 3}]
	d4["eq_state"] = {}
	_s._units.append(d4)
	var soft: Dictionary = _mk(900.0, 380.0, "right")
	soft["def"] = 0.0
	soft["mr"] = 0.0
	var hard: Dictionary = _mk(960.0, 380.0, "right")
	hard["def"] = 500.0        # ★物理 ⇒ 吃护甲
	hard["mr"] = 0.0
	var magy: Dictionary = _mk(1020.0, 380.0, "right")
	magy["def"] = 0.0
	magy["mr"] = 500.0         # 魔抗高但护甲 0 ⇒ 物理伤害不该被它挡
	_s._units.append(soft)
	_s._units.append(hard)
	_s._units.append(magy)
	_s._equip_sys._eq_on_death(d4, null)
	var w4a: Array = _worms("left")
	_ok("④ ★分母: 小虫在场", not w4a.is_empty())
	if not w4a.is_empty():
		var w4: Dictionary = w4a[0]
		var hs: float = float(soft["hp"])
		_s._damage._apply_damage_from(w4, soft, _s._resolve_dmg(w4, float(w4["atk"]), soft, false), Color.WHITE, 0.0, false, true)
		var ds: float = hs - float(soft["hp"])
		var hh: float = float(hard["hp"])
		_s._damage._apply_damage_from(w4, hard, _s._resolve_dmg(w4, float(w4["atk"]), hard, false), Color.WHITE, 0.0, false, true)
		var dh: float = hh - float(hard["hp"])
		var hm: float = float(magy["hp"])
		_s._damage._apply_damage_from(w4, magy, _s._resolve_dmg(w4, float(w4["atk"]), magy, false), Color.WHITE, 0.0, false, true)
		var dm: float = hm - float(magy["hp"])
		_ok("④ ★分母: 三个都掉血了(软 %.0f / 厚甲 %.0f / 厚魔抗 %.0f)" % [ds, dh, dm],
			ds > 0.0 and dh > 0.0 and dm > 0.0)
		_ok("④ ★★护甲 500 吃得明显少 ⇒ 是【物理伤害】(软 %.0f vs 厚甲 %.0f)" % [ds, dh],
			dh < ds * 0.5)
		_ok("④ ★★★魔抗 500 **挡不住**它(软 %.0f vs 厚魔抗 %.0f) ⇒ 不是魔法伤害" % [ds, dm],
			absf(ds - dm) < 1.0,
			"伤害类型是接线不是颜色: 物理必吃护甲、必不吃魔抗")

	# ── ⑤ ★★★3 星分裂: 每 WORM_SPLIT_IV 秒一只, 上限 WORM_CAP ─────────
	_s._units.clear()
	var d5: Dictionary = _mk(640.0, 380.0, "left")
	d5["equips"] = [{"id": "p2eq_033", "star": 3}]
	d5["eq_state"] = {}
	_s._units.append(d5)
	_s._units.append(_mk(1100.0, 380.0, "right"))
	_s._equip_sys._eq_on_death(d5, null)
	_ok("⑤ ★分母: 刚变虫时场上 %d 只(应 1 只)" % _worms("left").size(), _worms("left").size() == 1)
	_ok("⑤ ★★3 星的小虫带着分裂标记", not _worms("left").is_empty()
		and bool(_worms("left")[0].get("worm_split", false)))
	## 推到「差一点点还没到 WORM_SPLIT_IV」: 这时**不该**分裂(卡住「每 N 秒」那个 N)
	var almost: int = int((ES.WORM_SPLIT_IV - 0.15) * 60.0)
	for _k in range(almost):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("⑤ ★★差 0.15 秒时还没分裂(%d 只)" % _worms("left").size(), _worms("left").size() == 1,
		"卡住「每 %.1f 秒」那个数 —— 不卡的话周期改成 0.1 秒也照样绿" % ES.WORM_SPLIT_IV)
	for _k in range(20):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("⑤ ★★★满 %.1f 秒分裂出第二只(%d 只)" % [ES.WORM_SPLIT_IV, _worms("left").size()],
		_worms("left").size() == 2)
	## 一路推到封顶, 再多推一大截看它**不再涨**
	for _k in range(int(ES.WORM_SPLIT_IV * 60.0 * 6.0)):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("⑤ ★★★分裂封顶在 %d 只(实测 %d 只) —— 再推六个周期也不涨"
		% [ES.WORM_CAP, _worms("left").size()],
		_worms("left").size() == ES.WORM_CAP,
		"文案明写「上限 %d 只」" % ES.WORM_CAP)
	## ★1 星不该分裂
	_s._units.clear()
	var d6: Dictionary = _mk(640.0, 380.0, "left")
	d6["equips"] = [{"id": "p2eq_033", "star": 1}]
	d6["eq_state"] = {}
	_s._units.append(d6)
	_s._units.append(_mk(1100.0, 380.0, "right"))
	_s._equip_sys._eq_on_death(d6, null)
	var w6: Array = _worms("left")
	_ok("⑤ ★分母: 1 星也变出了小虫(%d 只)" % w6.size(), w6.size() == 1)
	_ok("⑤ ★★1 星的小虫**没有**分裂标记",
		not w6.is_empty() and not bool(w6[0].get("worm_split", false)),
		"文案里分裂是写在【3 星】那一条上的")
	## ★★判据量的是【整段里出现过的最大只数】而不是【推完之后还剩几只】——
	##   后者对随机不敏感这一条不成立: ★1 小虫底子只有 100 血, 而产品会随机塞给它
	##   3 件 4/5 费装备, 有些组合会让它在这 7.5 秒里死掉 ⇒ 同一份代码三次跑出
	##   「1 只 / 0 只 / 1 只」两种结果。那是**测试不稳**不是回归
	##   (memory [[fb-make-assertions-rng-insensitive]])。
	##   而「有没有分裂过」用最大值量, 死不死都不影响结论, 也照样卡得住变异。
	var max_seen: int = w6.size()
	for _k in range(int(ES.WORM_SPLIT_IV * 60.0 * 3.0)):
		_s._sim_step(_s.SIM_DT, false, false)
		max_seen = maxi(max_seen, _worms("left").size())
	_ok("⑤ ★★1 星**从头到尾没分裂过**(整段最多同时 %d 只, 应 ≤ 1)" % max_seen,
		max_seen <= 1,
		"推了三个 %.1f 秒周期; 量最大值而不是末值 —— 小虫可能中途被自己带的装备拖死" % ES.WORM_SPLIT_IV)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 22:
		print("  [FAIL] ★断言只有 %d 条(<22) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 033 复活海螺" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
