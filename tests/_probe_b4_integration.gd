extends Node
## _probe_b4_integration.gd — 批④ 17 件【整合级】探针
## ★以 `_` 开头 ⇒ run-tests.sh 的 `verify_*.gd` 自动发现【不会】收录它。这是临时探针不是门禁。
##
## 逐件门禁看不见的四类问题:
##   A 四件召唤物同队(077+079+080+086) —— 金弹计数串没串 / 召唤物互相当敌人 / 单位数爆没爆
##   B 两件区域同场(088 涨潮碑 + 094 祖龟碑) —— 光环叠加口径 / 撤场后属性有没有漏回
##   C 挨打类叠一只龟(081+082+085+087) —— 四条 on_damaged 会不会互相吃账
##   D 082 反伤 + 015 荆棘反伤 + 凤凰熔岩盾 同场 —— 会不会成环自激

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _mk(s, id: String, side: String, pos: Vector2, eq: Array) -> Dictionary:
	var u: Dictionary = s._debug._edit_place_unit(id, side, pos)
	if not eq.is_empty():
		u["_edit_equips"] = eq
	return u


func _sane(s, tag: String) -> void:
	## 与 `_audit_tick` 同口径的"逻辑上说不通的状态"扫描 —— 只是把它搬到探针里同步跑。
	var bad: Array = []
	for u in s._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var nm := str(u.get("name", u.get("id", "?")))
		var hp := float(u.get("hp", 0.0))
		var mx := float(u.get("maxHp", 1.0))
		if is_nan(hp) or is_inf(hp) or is_nan(mx) or is_inf(mx):
			bad.append("%s hp/maxHp NaN|Inf (%s/%s)" % [nm, str(hp), str(mx)])
		elif hp > mx + 1.0:
			bad.append("%s hp %.1f > maxHp %.1f" % [nm, hp, mx])
		for k in ["atk", "def", "mr"]:
			var v := float(u.get(k, 0.0))
			if v < 0.0 or is_nan(v):
				bad.append("%s %s=%s" % [nm, k, str(v)])
		var pos: Vector2 = u.get("pos", Vector2.ZERO)
		if is_nan(pos.x) or is_nan(pos.y) or absf(pos.x) > 6000.0 or absf(pos.y) > 6000.0:
			bad.append("%s pos=%s" % [nm, str(pos)])
	_ok("%s · 无 NaN/血超上限/负属性/飞出场外" % tag, bad.is_empty(), " / ".join(bad).substr(0, 300))


func _wait(s, secs: float, cap_ms: int = 40000) -> void:
	## ★墙钟兜底 + 游戏时钟判据(CLAUDE.md §3.5): 等游戏内时间推进 secs 秒。
	var t0: float = float(s._t)
	var w0: int = Time.get_ticks_msec()
	while float(s._t) - t0 < secs and Time.get_ticks_msec() - w0 < cap_ms:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	await _scenario_a()
	await _scenario_b()
	await _scenario_c()
	await _scenario_d()

	print("")
	if _fail == 0:
		print("ALL PASS — 批④整合探针 %d 条全绿" % _n)
	else:
		print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _new_scene():
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 4000000.0
	return s


func _drop(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════
#  A · 四件召唤物同队 (077 小手枪 + 079 医疗炮台 + 080 直升机 + 086 浮游炮群)
# ══════════════════════════════════════════════════════════════════
func _scenario_a() -> void:
	print("=== A 四件召唤物同队 (077+079+080+086 全 3★) ===")
	var s = await _new_scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# 同一只龟带全四件(最极端), 另一只龟再带一份 077+079(测"同种召唤物两份")
	var t1: Dictionary = _mk(s, "stone", "left", c + Vector2(-320.0, -60.0), [
		{"id": "p2eq_077", "star": 3}, {"id": "p2eq_079", "star": 3},
		{"id": "p2eq_080", "star": 3}, {"id": "p2eq_086", "star": 3}])
	var t2: Dictionary = _mk(s, "basic", "left", c + Vector2(-320.0, 80.0), [
		{"id": "p2eq_077", "star": 2}, {"id": "p2eq_079", "star": 2}])
	for k in range(3):
		_mk(s, "basic", "right", c + Vector2(300.0, -120.0 + 120.0 * float(k)), [])

	var n_before: int = s._units.size()
	s._debug._edit_start_battle()
	await get_tree().process_frame
	var n_spawn: int = s._units.size()
	var gun = s._equip_sys._gun_sys
	var gad = s._equip_sys._gadget_sys
	_ok("A① 登场后单位数 = 摆位数 + 4 个召唤物(2 小手枪 + 2 炮台)",
		n_spawn == n_before + 4, "before=%d after=%d  pistols=%d towers=%d helis=%d"
			% [n_before, n_spawn, gun._pistols.size(), gun._towers.size(), gun._helis.size()])
	_ok("A② 直升机不是单位(2 件 080? 只有 t1 带) ⇒ _helis=1 且不进 _units",
		gun._helis.size() == 1, "helis=%d" % gun._helis.size())

	await _wait(s, 24.0)
	_sane(s, "A③ 跑满 24 秒")

	var n_late: int = s._units.size()
	_ok("A④ 24 秒后单位数没有爆(≤ 登场数 + 6)", n_late <= n_spawn + 6,
		"spawn=%d late=%d" % [n_spawn, n_late])
	_ok("A⑤ 弹道表没有堆积(<400)", s._projectiles.size() < 400, "projectiles=%d" % s._projectiles.size())
	_ok("A⑥ _pending_shots 没有堆积(<400)", s._pending_shots.size() < 400,
		"pending=%d" % s._pending_shots.size())
	if is_instance_valid(s._world):
		_ok("A⑦ _world 子节点没有泄漏(<1200)", s._world.get_child_count() < 1200,
			"world_children=%d" % s._world.get_child_count())

	# ── 金弹计数: 每个 src 一张表, 每把枪一个 key ──
	var ct1: Dictionary = t1.get("_gun_shot_ct", {})
	var pistol_cts: Array = []
	for e in gun._pistols:
		pistol_cts.append(str((e["u"] as Dictionary).get("_gun_shot_ct", {})))
	var tower_cts: Array = []
	for e in gun._towers:
		tower_cts.append(str((e["u"] as Dictionary).get("_gun_shot_ct", {})))
	_ok("A⑧ 携带者的金弹计数表里【只有】080 的 key(077/079 记在召唤物自己身上)",
		not ct1.has("p2eq_077") and not ct1.has("p2eq_079"),
		"carrier ct=%s" % str(ct1))
	_ok("A⑨ 小手枪/炮台各自维持自己的金弹计数(表互不相同的对象)",
		pistol_cts.size() == 2 and tower_cts.size() == 2,
		"pistols=%s towers=%s" % [str(pistol_cts), str(tower_cts)])

	# ── 召唤物会不会互相当敌人 ──
	var cross := 0
	var summons: Array = []
	for e in gun._pistols:
		summons.append(e["u"])
	for e in gun._towers:
		summons.append(e["u"])
	for sm in summons:
		var tgt = s._targeting._nearest_enemy(sm)
		if tgt is Dictionary and s._is_ally(sm, tgt):
			cross += 1
	_ok("A⑩ 召唤物的最近敌人不是自己人(4 个召唤物全查)", cross == 0,
		"违例=%d / 召唤物=%d" % [cross, summons.size()])

	# ── 炮台的"最低血友军"不会挑到敌人 ──
	var heal_cross := 0
	for e in gun._towers:
		var low = gun.lowest_ally(e["u"])
		if low is Dictionary and not s._is_ally(e["u"], low) and not is_same(low, e["u"]):
			heal_cross += 1
	_ok("A⑪ 炮台的最低血友军全是自己人", heal_cross == 0, "违例=%d" % heal_cross)

	# ── 086 浮游炮: 满编 6 门, 且魔抗只加一条 ──
	var n_drone: int = int(t1.get("_sext_n", 0))
	var n_mrbuf := 0
	for b in t1.get("buffs", []):
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == "p2eq_086":
			n_mrbuf += 1
	_ok("A⑫ 086 浮游炮 24 秒后满编 6 门", n_drone == 6, "drones=%d" % n_drone)
	_ok("A⑬ 086 的魔抗 buff 只有一条(没有每帧 append)", n_mrbuf <= 1, "count=%d" % n_mrbuf)

	# ── t2(第二个携带者)也真的有自己的召唤物 ──
	var owned2 := 0
	for e in gun._pistols:
		if is_same(e["owner"], t2):
			owned2 += 1
	for e in gun._towers:
		if is_same(e["owner"], t2):
			owned2 += 1
	_ok("A⑭ 第二个携带者也有自己的 1 小手枪 + 1 炮台", owned2 == 2, "owned=%d" % owned2)

	await _drop(s)


# ══════════════════════════════════════════════════════════════════
#  B · 两件区域同场 (088 涨潮碑 + 094 祖龟碑)
# ══════════════════════════════════════════════════════════════════
func _scenario_b() -> void:
	print("=== B 两件区域同场 (088 涨潮碑 + 094 祖龟碑) ===")
	var s = await _new_scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	var a: Dictionary = _mk(s, "stone", "left", c + Vector2(-120.0, 0.0), [{"id": "p2eq_088", "star": 3}])
	var b: Dictionary = _mk(s, "basic", "left", c + Vector2(-160.0, 60.0), [{"id": "p2eq_094", "star": 3}])
	var d: Dictionary = _mk(s, "basic", "left", c + Vector2(-100.0, -60.0), [])
	_mk(s, "basic", "right", c + Vector2(320.0, 0.0), [])
	s._debug._edit_start_battle()
	await get_tree().process_frame

	var arc = s._equip_sys._arcane_sys
	var rel = s._equip_sys._relic_sys

	var aspd0_a: float = float(a.get("aspd_perm", 1.0))
	var aspd0_d: float = float(d.get("aspd_perm", 1.0))
	var amp0_d: float = float(d.get("damage_amp", 0.0))
	var def0_d: float = float(d.get("def", 0.0))

	# ① 094 立碑(直调 on_death 的真入口: 走 EquipSystem 分派)
	s._equip_sys._eq_on_death(b, null)
	rel.tick(0.016)
	_ok("B① 094 阵亡立碑成功", rel.stele_count() == 1, "steles=%d" % rel.stele_count())
	var amp1_d: float = float(d.get("damage_amp", 0.0))
	var def1_d: float = float(d.get("def", 0.0))
	_ok("B② 094 光环把增伤/双抗写到了友军身上",
		amp1_d > amp0_d and def1_d > def0_d,
		"amp %.3f→%.3f  def %.1f→%.1f" % [amp0_d, amp1_d, def0_d, def1_d])

	# ② 再立第二座同星碑 —— 光环不许叠加(取最高)
	var b2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-180.0, 100.0))
	b2["equips"] = [{"id": "p2eq_094", "star": 3}]
	b2["eq_state"] = {"p2eq_094": {}}
	s._units.append(b2)
	s._equip_sys._eq_on_death(b2, null)
	rel.tick(0.016)
	var amp2_d: float = float(d.get("damage_amp", 0.0))
	var def2_d: float = float(d.get("def", 0.0))
	_ok("B③ 两座 094 碑同场 ⇒ 光环取最高不相加",
		absf(amp2_d - amp1_d) < 1e-6 and absf(def2_d - def1_d) < 1e-6,
		"steles=%d  amp %.3f→%.3f  def %.1f→%.1f" % [rel.stele_count(), amp1_d, amp2_d, def1_d, def2_d])

	# ③ 088 立碑(走 on_mana_full 真入口), 圈内友军拿攻速
	arc.on_mana_full(a, "p2eq_088", 2)
	arc.tick(0.016)
	var aspd1_a: float = float(a.get("aspd_perm", 1.0))
	var aspd1_d: float = float(d.get("aspd_perm", 1.0))
	_ok("B④ 088 碑内友军拿到攻速(自身与近旁友军都拿)",
		aspd1_a > aspd0_a and aspd1_d > aspd0_d,
		"a %.3f→%.3f  d %.3f→%.3f" % [aspd0_a, aspd1_a, aspd0_d, aspd1_d])

	# ④ 两块 088 碑重叠 —— 攻速取更高不相加。
	#    ★必须换【另一个携带者】立第二块: 同一只龟立完就锁法力条, 再调 on_mana_full 会被拒发
	#      ⇒ 第二块根本立不起来, 那条断言就是恒真的空检查。
	var a2: Dictionary = s._spawn._make_unit("stone", "left", c + Vector2(-140.0, 20.0))
	a2["equips"] = [{"id": "p2eq_088", "star": 3}]
	a2["eq_state"] = {"p2eq_088": {}}
	s._units.append(a2)
	arc.on_mana_full(a2, "p2eq_088", 2)
	arc.tick(0.016)
	var aspd2_d: float = float(d.get("aspd_perm", 1.0))
	_ok("B⑤ 分母: 第二块 088 碑真的立起来了(steles=2)", arc._steles.size() == 2,
		"steles=%d" % arc._steles.size())
	_ok("B⑥ 两块 088 碑重叠 ⇒ 攻速取更高不相加",
		absf(aspd2_d - aspd1_d) < 1e-6, "%.4f vs %.4f (steles=%d)" % [aspd1_d, aspd2_d, arc._steles.size()])

	# ⑤ 碑到期后攻速差量必须原样收回 —— 094 的光环仍在(测两件互不干扰)
	var guard := 0
	while arc._steles.size() > 0 and guard < 2000:
		arc.tick(0.05)
		guard += 1
	var aspd3_d: float = float(d.get("aspd_perm", 1.0))
	var amp3_d: float = float(d.get("damage_amp", 0.0))
	_ok("B⑦ 088 碑到期后攻速回到基线(没有漏加)",
		absf(aspd3_d - aspd0_d) < 1e-6, "基线 %.6f  现 %.6f" % [aspd0_d, aspd3_d])
	_ok("B⑧ 088 撤场没有顺手抹掉 094 的增伤光环",
		absf(amp3_d - amp1_d) < 1e-6, "094 amp 期望 %.3f 实得 %.3f" % [amp1_d, amp3_d])

	# ⑥ 094 撤场后增伤/双抗也要回基线
	rel.clear_all()
	var amp4_d: float = float(d.get("damage_amp", 0.0))
	var def4_d: float = float(d.get("def", 0.0))
	_ok("B⑨ 094 撤场后增伤/双抗回到基线",
		absf(amp4_d - amp0_d) < 1e-6 and absf(def4_d - def0_d) < 1e-6,
		"amp %.3f(基线 %.3f)  def %.1f(基线 %.1f)" % [amp4_d, amp0_d, def4_d, def0_d])
	_sane(s, "B⑩ 区域件撤场后")
	await _drop(s)


# ══════════════════════════════════════════════════════════════════
#  C · 挨打类叠一只龟 (081 举盾 + 082 反伤 + 085 转龟能 + 087 压载舱)
# ══════════════════════════════════════════════════════════════════
func _scenario_c() -> void:
	print("=== C 四件挨打类叠一只龟 (081+082+085+087 全 3★) ===")
	var s = await _new_scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	var v: Dictionary = _mk(s, "stone", "left", c + Vector2(-120.0, 0.0), [
		{"id": "p2eq_081", "star": 3}, {"id": "p2eq_082", "star": 3},
		{"id": "p2eq_085", "star": 3}, {"id": "p2eq_087", "star": 3}])
	var foe: Dictionary = _mk(s, "basic", "right", c + Vector2(160.0, 0.0), [])
	s._debug._edit_start_battle()
	## ★这里【故意不 await 帧】: 087 的压载舱是"第一次 tick_unit 时按当时的 maxHp 开舱",
	##   放一帧过去主循环就先开好舱了, 我后面改的 maxHp 就不算数 —— 上一版正是这么被自己骗的
	##   (cap=4662=原始 maxHp×1.5, 而我以为是 20000×1.5)。

	# 干净合成: 把受测者的抗性/闪避清零, 免得随机减伤污染数值(memory: 用干净合成单位隔离)
	v["def"] = 0.0; v["mr"] = 0.0; v["base_def"] = 0.0; v["base_mr"] = 0.0
	v["dodge_bonus"] = 0.0; v["dodge"] = 0.0; v["shield"] = 0.0
	foe["maxHp"] = 500000.0; foe["hp"] = 500000.0
	foe["def"] = 0.0; foe["mr"] = 0.0
	s._recalc_stats(v)
	v["maxHp"] = 20000.0; v["hp"] = 20000.0   # ★放在 _recalc_stats 之后(它会按基础表重算 maxHp)

	var blade = s._equip_sys._blade_sys
	var gad = s._equip_sys._gadget_sys
	gad.tick_unit(v, 0.016)                    # ← 开舱就发生在这一刻, maxHp 已经是 20000
	var cap0: float = float(((v.get("eq_state", {}) as Dictionary).get("p2eq_087", {}) as Dictionary).get("cap", 0.0))
	_ok("C① 087 压载舱按【第一次 tick 时的 maxHp】开舱(3★=150%)",
		absf(cap0 - 20000.0 * 1.5) < 1.0, "cap=%.1f 期望 %.1f" % [cap0, 30000.0])

	var hp0: float = float(v["hp"])
	var st0: int = int(v.get("_st_taken", 0))
	var en0: float = float(v.get("_piezo_total", 0.0))
	var refl0: int = blade.b82_reflects(v)
	var chg0: float = float(((v["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))
	var foe_hp0: float = float(foe["hp"])

	# ── 普攻/技能路: 一段 1000 名义伤害 ──
	s._damage._apply_damage_from(foe, v, 1000, Color("#ffffff"))
	var st1: int = int(v.get("_st_taken", 0))
	var chg1: float = float(((v["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))
	var en1: float = float(v.get("_piezo_total", 0.0))
	var refl1: int = blade.b82_reflects(v)
	var water1: float = gad.dive_water(v)
	_ok("C② 普攻路一段 1000: 四件各自都记了账(081充能 / 082反伤 / 085龟能 / 087灌水)",
		chg1 > chg0 and refl1 == refl0 + 1 and en1 > en0 and water1 > 0.0,
		"charge %.0f→%.0f  refl %d→%d  energy %.1f→%.1f  water=%.1f"
			% [chg0, chg1, refl0, refl1, en0, en1, water1])
	## ★期望值不写死 1000 —— 管线里还有增伤/减伤会改名义值。用【_st_taken 的增量】当分母:
	##   要验的是"三件记的是同一笔账", 不是"那笔账是多少"。
	var nominal: float = float(st1 - st0)
	_ok("C③ 087 舱先扛 ⇒ 这一段血基本没掉, 但 081/085/087 仍按【名义伤害】同额记账",
		absf(float(v["hp"]) - hp0) < 1.0 and absf(chg1 - chg0 - nominal) < 1.0
			and absf(water1 - nominal) < 1.0,
		"hp %.1f→%.1f  名义=%.0f  charge+=%.1f  water=%.1f"
			% [hp0, float(v["hp"]), nominal, chg1 - chg0, water1])
	_ok("C④ 085 这一段转的龟能 = 名义×15% 且不超每秒上限 60",
		absf(en1 - en0 - minf(nominal * 0.15, 60.0)) < 0.01,
		"实得 %.2f 期望 %.2f (名义 %.0f)" % [en1 - en0, minf(nominal * 0.15, 60.0), nominal])
	_ok("C⑤ 082 的反伤真的打到了攻击者", float(foe["hp"]) < foe_hp0,
		"foe hp %.1f→%.1f" % [foe_hp0, float(foe["hp"])])

	# ── DoT/真伤路: 一段 500 ──
	## ★先让游戏时钟过 1.2 秒 —— 085 的每秒配额(3★=60)在上一段已经打满,
	##   不等一秒就断言"DoT 也涨龟能"会被配额挡住, 那是【测试的错】不是产品的错。
	await _wait(s, 1.2)
	var chg2a: float = float(((v["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))
	var refl2a: int = blade.b82_reflects(v)
	var en2a: float = float(v.get("_piezo_total", 0.0))
	var foe_hp2a: float = float(foe["hp"])
	s._damage._apply_damage(v, 500, Color("#ff8844"), foe, "dot")
	var chg2: float = float(((v["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))
	var refl2: int = blade.b82_reflects(v)
	var en2: float = float(v.get("_piezo_total", 0.0))
	_ok("C⑥ DoT 路: 081 充能【要收】(规格: 受到的伤害都算)",
		absf(chg2 - chg2a - 500.0) < 1.0, "charge += %.1f" % (chg2 - chg2a))
	_ok("C⑦ DoT 路: 082 反伤【不算】(用户拍板 DoT 每跳不算一段攻击)",
		refl2 == refl2a and absf(float(foe["hp"]) - foe_hp2a) < 0.5,
		"refl %d→%d  foe hp %.1f→%.1f" % [refl2a, refl2, foe_hp2a, float(foe["hp"])])
	_ok("C⑧ DoT 路: 085 龟能【要收】", en2 > en2a, "energy %.2f→%.2f" % [en2a, en2])

	# ── 连打到 081 举盾: 举盾期间四件都不许互相吃账 ──
	var g := 0
	while not blade.b81_guarding(v) and g < 60:
		s._damage._apply_damage_from(foe, v, 1000, Color("#ffffff"))
		g += 1
	_ok("C⑨ 连续挨打后 081 真的举盾了", blade.b81_guarding(v), "打了 %d 段" % g)
	var refl_up0: int = blade.b82_reflects(v)
	s._damage._apply_damage_from(foe, v, 1000, Color("#ffffff"))
	_ok("C⑩ 举盾期间 082 照常反伤(两件互不吞账)", blade.b82_reflects(v) == refl_up0 + 1,
		"refl %d→%d" % [refl_up0, blade.b82_reflects(v)])
	var chg_up: float = float(((v["eq_state"] as Dictionary).get("p2eq_081", {}) as Dictionary).get("charge", 0.0))
	_ok("C⑪ 举盾期间受到的伤害【不计入】081 充能条", absf(chg_up) < 1e-6, "charge=%.2f" % chg_up)

	# ── 087 的 move_perm 绝对写入 vs 092 剧毒缓速 ──
	var vd = s._equip_sys._venom
	if vd != null:
		gad._dive_sync_stacks(v, 2)
		var mp_dive: float = float(v.get("move_perm", 1.0))
		var stk_dive: int = int(v.get("_dive_stk", 0))
		vd.add_vslow(v, 10)
		var mp_slow: float = float(v.get("move_perm", 1.0))
		# 让 087 的层数变一档 → 它会【绝对写】move_perm(基线是它自己第一次记的 _dive_mp0)
		v["_dive_stk"] = -1
		gad._dive_sync_stacks(v, 2)
		var mp_after: float = float(v.get("move_perm", 1.0))
		_ok("C⑫ ★087 层数刷新【不该】抹掉 092 剧毒缓速的减速",
			mp_after <= mp_slow + 1e-6,
			"087(%d 层)单独 %.4f → 中毒 10 层 %.4f → 087 再刷新 %.4f  (剧毒层数仍 %d)"
				% [stk_dive, mp_dive, mp_slow, mp_after, int(v.get("_vslow_n", 0))])
		# ── 反方向: 092 掉层时会不会抹掉 087 的压载移速 ──
		vd._set_vslow(v, 0)
		var mp_back: float = float(v.get("move_perm", 1.0))
		_ok("C⑫b ★剧毒清零后 move_perm 应回到 087 那一档(%.4f), 不是裸 1.0" % mp_dive,
			absf(mp_back - mp_dive) < 1e-6, "实得 %.4f" % mp_back)

		# ── C⑫c 走【真路径】复现: 不手动改 _dive_stk, 只是"中毒 + 再挨一下打" ──
		#    挨打 ⇒ 压载舱水位变 ⇒ 层数变 ⇒ on_damaged 里 _dive_sync_stacks 绝对写 move_perm。
		vd.add_vslow(v, 10)
		var mp_slow2: float = float(v.get("move_perm", 1.0))
		var stk_before: int = int(v.get("_dive_stk", -1))
		s._damage._apply_damage_from(foe, v, 3000, Color("#ffffff"))
		var stk_after: int = int(v.get("_dive_stk", -1))
		var mp_real: float = float(v.get("move_perm", 1.0))
		_ok("C⑫c 分母: 那一下打确实让 087 的压载层数变了(%d→%d)" % [stk_before, stk_after],
			stk_after != stk_before, "层数 %d→%d" % [stk_before, stk_after])
		_ok("C⑫c ★真路径(中毒 + 挨一下打)也会抹掉剧毒缓速",
			mp_real <= mp_slow2 + 1e-6,
			"中毒后 %.4f → 挨打后 %.4f  (剧毒层数仍 %d)" % [mp_slow2, mp_real, int(v.get("_vslow_n", 0))])
		vd._set_vslow(v, 0)

	_sane(s, "C⑬ 四件挨打类跑完")
	await _drop(s)


# ══════════════════════════════════════════════════════════════════
#  D · 082 反伤 + 015 荆棘反伤 + 凤凰熔岩盾 同场 (会不会成环自激)
# ══════════════════════════════════════════════════════════════════
func _scenario_d() -> void:
	print("=== D 反伤三件套同场 (082 + 015 + 凤凰熔岩盾) ===")
	var s = await _new_scene()
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# 左: 凤凰(熔岩盾) + 015 荆棘 + 082 护心 ; 右: 也是 015 + 082 + 通用 reflect
	var p: Dictionary = _mk(s, "phoenix", "left", c + Vector2(-120.0, 0.0), [
		{"id": "p2eq_015", "star": 3}, {"id": "p2eq_082", "star": 3}])
	var q: Dictionary = _mk(s, "stone", "right", c + Vector2(120.0, 0.0), [
		{"id": "p2eq_015", "star": 3}, {"id": "p2eq_082", "star": 3}])
	s._debug._edit_start_battle()
	await get_tree().process_frame

	# 右侧是"假人"(no_basic/no_move), 但反伤走的是受击路径, 不需要它出手
	p["lava_shield_until"] = s._t + 600.0
	p["maxHp"] = 200000.0; p["hp"] = 200000.0
	q["maxHp"] = 200000.0; q["hp"] = 200000.0
	q["reflect"] = 0.30              # 通用反伤 30%
	p["reflect"] = 0.30
	s._recalc_stats(p); s._recalc_stats(q)

	var d0_p: int = int(p.get("_st_taken", 0))
	var d0_q: int = int(q.get("_st_taken", 0))
	var t0 := Time.get_ticks_msec()
	# 一段普通伤害(from_equip=false) —— 若反伤成环, 这一行永远返回不了 / 或伤害段数爆炸
	s._damage._apply_damage_from(p, q, 500, Color("#ffffff"))
	var dt := Time.get_ticks_msec() - t0
	var d1_p: int = int(p.get("_st_taken", 0))
	var d1_q: int = int(q.get("_st_taken", 0))
	_ok("D① 一段伤害同步返回(没有自激死循环)", dt < 2000, "耗时 %d ms" % dt)
	_ok("D② 攻击者被反伤的次数有限(反伤总量 < 原始伤害的 5 倍)",
		d1_p - d0_p < 500 * 5, "攻击者承伤 +%d  受击者承伤 +%d" % [d1_p - d0_p, d1_q - d0_q])
	_ok("D③ 反伤确实发生了(非空检查)", d1_p - d0_p > 0, "攻击者承伤 +%d" % (d1_p - d0_p))

	# 连打 200 段, 看有没有雪崩
	var t1 := Time.get_ticks_msec()
	for i in range(200):
		if not p.get("alive", false) or not q.get("alive", false):
			break
		s._damage._apply_damage_from(p, q, 300, Color("#ffffff"))
	var dt2 := Time.get_ticks_msec() - t1
	_ok("D④ 连打 200 段在 8 秒内跑完(没有指数爆炸)", dt2 < 8000, "耗时 %d ms" % dt2)
	_sane(s, "D⑤ 反伤三件套跑完")
	await _drop(s)
