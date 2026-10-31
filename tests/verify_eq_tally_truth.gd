extends Node
## verify_eq_tally_truth.gd —— 装备统计「记到哪件装备头上」逐笔对账(2026-10-31)
##
## 用户 10-31 原话:「对局内那伤害统计啥的都对吗？别说有些装备它明明没有治疗效果，为什么它有治疗呢？
##                然后像那个什么二费的，那个剑带(= 银色箭袋 075)，那装备伤害统计肯定是有问题的」
##
## 查出来的根因(探针 tests/_probe_tally_truth.gd 全 96 件逐笔对账):
##   ① 装备打出的一段伤害, 引出的【反应】—— 携带者的生命偷取、法器余韵的盾、击杀引出的羁绊收殓 ——
##      跑在那件装备的统计上下文里 ⇒ 全记成了那件装备的「治疗 / 护盾」。46 件中招(吸血 30% 时)。
##   ② 075 箭雨在全局在途表里推进, 没有任何装备上下文 ⇒ 箭雨伤害与它挂的流血一分都没记(实发 7562 记 0)。
##   ③ 同形状: 090 猛砸(落地事件触发)/ 079 炮台的治疗 / 096 斧头偷盾 / 004 处决回血(借用击杀那一下的上下文)。
##   ④ 011 溢出转盾不走 _grant_shield ⇒ 「获得护盾」与 011 的账都漏它。
##
## 判据:
##   A 段(合成, 精确): 每个根因各造一笔, 量【单位级真实发生量】(_st_heal / _st_shield / _st_taken)当分母,
##     再看装备账有没有记、记对没有。
##   B 段(075 真入口): rain_start → 系统 tick 推完六跳 → 敌人承伤增量 == 075 伤害账增量; 流血一跳同样对账。
##   C 段(整类): 一组装备在真实小场上跑 30 秒, 每一笔伤害/治疗/护盾按【调用栈】独立判真值
##     (tests/_tally_truth_hook.gd), 与装备账逐笔对: 该记的全记、不该记的一笔不记。
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_tally_truth.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const HOOK := preload("res://tests/_tally_truth_hook.gd")
const EQS := preload("res://scripts/gamedata/equip_stats.gd")
const DT := 1.0 / 60.0

## C 段的件: 每个根因至少一件 + 治疗 / 护盾 / 弹道 / 召唤物 各类正常件(防「修过头」把该记的也切掉)。
##   006/053: 纯伤害件(根因① 吸血)  075: 根因②  079/090/096: 根因③
##   019 治疗 · 016 护盾 · 001 弹道(发射时的上下文) · 058 召唤物 · 067 DoT
const C_IDS := ["p2eq_006", "p2eq_053", "p2eq_075", "p2eq_079", "p2eq_090", "p2eq_096",
	"p2eq_019", "p2eq_016", "p2eq_001", "p2eq_058", "p2eq_067"]
const SHOULD := ["EQ", "SUMMON", "DEFER-EQ"]

var s = null
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= maxf(1.0, absf(b) * 0.002)


func _eqv(u: Dictionary, iid: String, k: String) -> float:
	return float(((u.get("_st_eq", {}) as Dictionary).get(iid, {}) as Dictionary).get(k, 0.0))


func _eqdmg(u: Dictionary, iid: String) -> float:
	return _eqv(u, iid, "phy") + _eqv(u, iid, "mag") + _eqv(u, iid, "tru")


func _taken(es: Array) -> float:
	var t := 0.0
	for x in es:
		t += float((x as Dictionary).get("_st_taken", 0))
	return t


func _new_scene() -> void:
	if s != null:
		s.queue_free()
		await get_tree().process_frame
	s = RB.new()
	add_child(s)
	for _j in range(6):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = true
	print("=== 装备统计: 记到哪件装备头上(逐笔对账) ===")
	await _new_scene()
	await _part_a()
	await _new_scene()
	await _part_b()
	await _part_c()
	print("")
	print("断言 %d 条 · 用帧 %d" % [_n, Engine.get_process_frames()])
	if _fail == 0 and _n >= 20:
		print("ALL PASS — 装备账只记装备自己的效果: 吸血/羁绊/击杀反应不记, 箭雨/猛砸/炮台治疗/偷盾/处决回血/溢出转盾都记上")
	else:
		print("FAIL x%d (断言 %d)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## 小场: 携带者(半血) + 3 个高血敌人; 都不动不打。
func _stage(iid: String = "") -> Array:
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	s._battle_rng.seed = 20261031
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-60, 0))
	u["maxHp"] = 6000.0; u["hp"] = 3000.0; u["atk"] = 120.0; u["no_move"] = true; u["no_basic"] = true
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(30.0 + 40.0 * float(i), -20.0 + 20.0 * float(i)))
		e["maxHp"] = 1.0e6; e["hp"] = 1.0e6; e["no_move"] = true; e["no_basic"] = true
		es.append(e)
	s._units.clear()
	s._units.append(u)
	s._units.append_array(es)
	s._edit_mode = false
	s._over = false
	u["equips"] = [] if iid == "" else [{"id": iid, "star": 3}]
	u["eq_state"] = {} if iid == "" else {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	return [u, es]


## 只推延时队列 2 秒(不推整步 sim: 不让别的单位在这期间出手)。
func _fly_pending() -> void:
	for _k in range(120):
		s._ballistics._step_pending_shots(DT)


# ─────────────────────────────── A. 合成: 每个根因各一笔 ───────────────────────────────
func _part_a() -> void:
	print("")
	print("— A. 合成段 —")
	var tl = s._equip_sys.tally
	var st: Array = await _stage()
	var u: Dictionary = st[0]
	var es: Array = st[1]

	## A1 根因①: 装备打出的一段触发携带者生命偷取 —— 伤害记这件, 偷取的回血不记
	u["lifesteal"] = 0.3
	var h0: float = float(u.get("_st_heal", 0)); var t0: float = _taken(es)
	var p0: Array = tl.push(u, "p2eq_901")
	s._damage._apply_damage_from(u, es[0], 400, Color.WHITE, 0.0, false, true)
	tl.pop(p0)
	var dh: float = float(u.get("_st_heal", 0)) - h0
	var dt: float = _taken(es) - t0
	_ok("A1 ★吸血: 这一段的伤害记给装备(== 承伤增量)", dt > 0.0 and _near(_eqdmg(u, "p2eq_901"), dt),
		"账 %.0f / 承伤 %.0f" % [_eqdmg(u, "p2eq_901"), dt])
	_ok("A1 ★吸血: 携带者确实回了血(分母), 但装备账治疗 = 0", dh > 0.0 and _eqv(u, "p2eq_901", "heal") == 0.0,
		"实际回血 %.1f / 装备账治疗 %.1f" % [dh, _eqv(u, "p2eq_901", "heal")])
	u["lifesteal"] = 0.0

	## A2 击杀反应(羁绊收殓: 敌人死 → 最近的携带盾者得盾) —— 两条伤害路各打死一个
	var shield_id: String = ""
	for k in EQS.STATS.keys():
		if s.Phase2Types.type_of(str(k)) == "盾":
			shield_id = str(k)
			break
	u["equips"] = [{"id": shield_id, "star": 1}]
	u["eq_state"] = {shield_id: {}}
	var tiers: Dictionary = s._synergy._by_side.get("left", {})
	tiers["盾"] = ShieldSynergySystem.REAP_TIER
	s._synergy._by_side["left"] = tiers
	var sh0: float = float(u.get("_st_shield", 0))
	p0 = tl.push(u, "p2eq_902")
	s._damage._apply_damage(es[1], 2000000, Color.WHITE, u, "tru")
	tl.pop(p0)
	_fly_pending()               # 收殓的盾随金球飞到才发(延时队列, 落地时切回入队那一刻的上下文)
	var dsh: float = float(u.get("_st_shield", 0)) - sh0
	_ok("A2 ★击杀反应(_apply_damage 路): 收殓的盾确实给了(分母), 打死它的装备账护盾 = 0",
		not es[1].get("alive", true) and dsh > 0.0 and _eqv(u, "p2eq_902", "shield") == 0.0,
		"%s 收殓盾 %.0f / 装备账护盾 %.0f" % [shield_id, dsh, _eqv(u, "p2eq_902", "shield")])
	sh0 = float(u.get("_st_shield", 0))
	p0 = tl.push(u, "p2eq_903")
	s._damage._apply_damage_from(u, es[2], 2000000, Color.WHITE, 0.0, true, true)
	tl.pop(p0)
	_fly_pending()
	dsh = float(u.get("_st_shield", 0)) - sh0
	_ok("A3 ★击杀反应(_apply_damage_from 路): 同上(两条伤害路 §3.3)",
		not es[2].get("alive", true) and dsh > 0.0 and _eqv(u, "p2eq_903", "shield") == 0.0,
		"收殓盾 %.0f / 装备账护盾 %.0f" % [dsh, _eqv(u, "p2eq_903", "shield")])
	tiers.erase("盾")

	## A4 法器余韵(受到治疗 → 额外得盾): 治疗记这件, 余韵的盾不记
	tiers["法器"] = 3
	u["hp"] = 3000.0
	h0 = float(u.get("_st_heal", 0)); sh0 = float(u.get("_st_shield", 0))
	p0 = tl.push(u, "p2eq_904")
	s._damage._heal(u, 300.0)
	tl.pop(p0)
	dh = float(u.get("_st_heal", 0)) - h0
	dsh = float(u.get("_st_shield", 0)) - sh0
	_ok("A4 ★余韵: 治疗照记(== 实际回血)", dh > 0.0 and _near(_eqv(u, "p2eq_904", "heal"), dh),
		"账 %.0f / 实际 %.0f" % [_eqv(u, "p2eq_904", "heal"), dh])
	_ok("A4 ★余韵: 余韵的盾确实给了(分母), 装备账护盾 = 0", dsh > 0.0 and _eqv(u, "p2eq_904", "shield") == 0.0,
		"余韵盾 %.0f / 装备账护盾 %.0f" % [dsh, _eqv(u, "p2eq_904", "shield")])
	tiers.erase("法器")

	## A5 根因④: 011 溢出转盾 —— 不在任何上下文里, 照样记给 011, 「获得护盾」也算它
	tl.use(null)
	u["overheal2shield_cap"] = 300.0
	u["shield"] = 0.0
	u["hp"] = float(u["maxHp"]) - 10.0
	var raw0: float = float(u["shield"]); sh0 = float(u.get("_st_shield", 0))
	var e11: float = _eqv(u, "p2eq_011", "shield")
	s._damage._heal(u, 120.0)
	var dsr: float = float(u["shield"]) - raw0
	_ok("A5 ★011 溢出转盾: 装备账护盾 == 实际涨的盾(分母 > 0)", dsr > 0.0 and _near(_eqv(u, "p2eq_011", "shield") - e11, dsr),
		"账 %.1f / 实涨 %.1f" % [_eqv(u, "p2eq_011", "shield") - e11, dsr])
	_ok("A5 ★011 溢出转盾: 单位「获得护盾」同样算进去", _near(float(u.get("_st_shield", 0)) - sh0, dsr),
		"_st_shield +%.1f / 实涨 %.1f" % [float(u.get("_st_shield", 0)) - sh0, dsr])
	u["overheal2shield_cap"] = 0.0

	## A6 根因③: 004 处决回血 —— 击杀那一下没有任何装备上下文(DoT 路打死), 照样记给 004
	st = await _stage("p2eq_004")
	u = st[0]; es = st[1]
	u["active_skills"] = []      # 没有龟能系统 ⇒ 处决改回血
	tl.use(null)
	h0 = float(u.get("_st_heal", 0))
	s._damage._apply_damage(es[0], 2000000, Color.WHITE, u, "tru")
	dh = float(u.get("_st_heal", 0)) - h0
	_ok("A6 ★004 处决回血: 回了(分母), 且记给 004", not es[0].get("alive", true) and dh > 0.0 and _near(_eqv(u, "p2eq_004", "heal"), dh),
		"账 %.0f / 实际 %.0f" % [_eqv(u, "p2eq_004", "heal"), dh])

	## A8 004 普攻处决(在 004 自己的上下文里直接击杀) —— 击杀引出的收殓盾不算 004
	u["equips"] = [{"id": "p2eq_004", "star": 3}, {"id": shield_id, "star": 1}]
	u["eq_state"] = {"p2eq_004": {}, shield_id: {}}
	tiers = s._synergy._by_side.get("left", {})
	tiers["盾"] = ShieldSynergySystem.REAP_TIER
	s._synergy._by_side["left"] = tiers
	es[1]["hp"] = float(es[1]["maxHp"]) * 0.01
	tl.use(null)
	sh0 = float(u.get("_st_shield", 0))
	s._damage._apply_damage_from(u, es[1], 10, Color.WHITE, 0.0, false, false, false, false, false, true)
	_fly_pending()
	dsh = float(u.get("_st_shield", 0)) - sh0
	_ok("A8 ★004 普攻处决: 处决了、收殓盾给了(分母), 004 的护盾账 = 0",
		not es[1].get("alive", true) and dsh > 0.0 and _eqv(u, "p2eq_004", "shield") == 0.0,
		"收殓盾 %.0f / 004 护盾账 %.0f" % [dsh, _eqv(u, "p2eq_004", "shield")])
	tiers.erase("盾")

	## A7 根因③: 079 炮台治疗 / 096 斧头偷盾 —— 各自的结算函数在召唤物的普攻里跑, 没有装备上下文
	st = await _stage("p2eq_096")
	u = st[0]; es = st[1]
	var ax = null
	for _k in range(60):
		s._sim_step(DT, false, false)
	for x in s._units:
		if x is Dictionary and x.get("_eq_axe", false):
			ax = x
	if ax is Dictionary:
		tl.use(null)
		es[0]["shield"] = 1000.0
		var a0: float = float(ax.get("_st_shield", 0)); var q0: float = _eqv(u, "p2eq_096", "shield")
		var took: float = s._equip_sys._axe.steal_shield(ax, es[0])
		var da: float = float(ax.get("_st_shield", 0)) - a0
		_ok("A7 ★096 斧头偷盾: 偷到了(分母), 记给携带者 · 096", took > 0.0 and da > 0.0 and _near(_eqv(u, "p2eq_096", "shield") - q0, da),
			"账 %.1f / 斧头实得 %.1f" % [_eqv(u, "p2eq_096", "shield") - q0, da])
	else:
		_ok("A7 ★096 斧头偷盾: 斧头登场了(分母)", false, "60 步内没找到斧头")


# ─────────────────────────────── B. 075 箭雨真入口 ───────────────────────────────
func _part_b() -> void:
	print("")
	print("— B. 075 银色箭袋(用户点名) —")
	var tl = s._equip_sys.tally
	var st: Array = await _stage("p2eq_075")
	var u: Dictionary = st[0]
	var es: Array = st[1]
	u["lifesteal"] = 0.3
	var bow = s._equip_sys._bow_sys
	tl.use(null)
	var t0: float = _taken(es); var h0: float = float(u.get("_st_heal", 0)); var q0: float = _eqdmg(u, "p2eq_075")
	bow.rain_start(u, 2)
	var steps: int = int(ceil(float(EqBowBatch.RAIN_HOPS) * EqBowBatch.RAIN_HOP_IV / DT)) + 10
	for _k in range(steps):
		bow.tick(DT)
	var dt: float = _taken(es) - t0
	var hops: int = int(u["eq_state"].get("p2eq_075", {}).get("rain_hops", 0))
	_ok("B1 ★箭雨六跳都落了(分母)", hops == EqBowBatch.RAIN_HOPS and dt > 0.0, "跳数 %d / 承伤 %.0f" % [hops, dt])
	_ok("B2 ★箭雨伤害全进 075 的账(== 敌人承伤增量)", _near(_eqdmg(u, "p2eq_075") - q0, dt),
		"账 %.0f / 承伤 %.0f" % [_eqdmg(u, "p2eq_075") - q0, dt])
	var dh: float = float(u.get("_st_heal", 0)) - h0
	_ok("B3 ★箭雨引出的吸血回了(分母), 075 的治疗账 = 0", dh > 0.0 and _eqv(u, "p2eq_075", "heal") == 0.0,
		"实际回血 %.0f / 075 治疗账 %.0f" % [dh, _eqv(u, "p2eq_075", "heal")])
	var bleed: int = 0
	for e in es:
		bleed += int((e.get("dot_stacks", {}) as Dictionary).get("bleed", 0))
	t0 = _taken(es); q0 = _eqdmg(u, "p2eq_075")
	tl.use(null)
	for e in es:
		s._tick_dot_stacks(e)
	dt = _taken(es) - t0
	_ok("B4 ★箭雨挂的流血: 有层(分母), 一跳全记给 075", bleed > 0 and dt > 0.0 and _near(_eqdmg(u, "p2eq_075") - q0, dt),
		"层 %d / 账 %.0f / 承伤 %.0f" % [bleed, _eqdmg(u, "p2eq_075") - q0, dt])


# ─────────────────────────────── C. 整类: 调用栈真值逐笔对账 ───────────────────────────────
func _part_c() -> void:
	print("")
	print("— C. 整类(%d 件 · 携带者吸血 30%%): 该记的全记、不该记的一笔不记 —" % C_IDS.size())
	for iid in C_IDS:
		await _new_scene()
		var h = HOOK.new(s)
		s._equip_sys.tally = h
		var st: Array = await _stage(str(iid))
		var u: Dictionary = st[0]
		u["no_basic"] = false
		u["energy"] = 100.0
		u["range_add"] = float(u.get("range_add", 0.0)) + 400.0
		u["lifesteal"] = float(u.get("lifesteal", 0.0)) + 0.3
		for e in st[1]:
			(e as Dictionary)["no_basic"] = false
			(e as Dictionary)["atk"] = 25.0
		for k in range(1800):
			s._sim_step(DT, false, false)
			if k % 120 == 0:
				await get_tree().process_frame
		s._over = true
		_judge(str(iid), h)


## 按「伤害 / 治疗 / 护盾」三类分开对账: 一件既打伤害又回血时, 伤害量级不许把治疗那边的漏记淹掉
##   (079: 炮台伤害 40 多万、治疗只有一百多 —— 合在一起比, 治疗整个漏掉也在 0.1% 容差里)。
func _judge(iid: String, h) -> void:
	var should: Dictionary = {"dmg": 0.0, "heal": 0.0, "shield": 0.0}
	var under: Dictionary = {"dmg": 0.0, "heal": 0.0, "shield": 0.0}
	var over := 0.0
	var where: Dictionary = {}
	## DoT 一跳的真值看【层是谁加的】: 这一类层全是装备加的 ⇒ 该全记; 一层都不是 ⇒ 一点都不该记; 混着的不判
	var dot_src: Dictionary = {}     # type → [装备加的层, 别的层]
	for a in h.dot_adds:
		var p: Array = dot_src.get(str(a["type"]), [0, 0])
		if str(a["truth"]) in SHOULD:
			p[0] = int(p[0]) + int(a["stacks"])
		else:
			p[1] = int(p[1]) + int(a["stacks"])
		dot_src[str(a["type"])] = p
	for e in h.events:
		var kind: String = str(e["kind"])
		var cred := 0.0
		for k in (e["credited"] as Dictionary).keys():
			if str(k).begins_with(iid + "|"):
				cred += float(e["credited"][k])
			else:
				over += float(e["credited"][k])
				where["别的件 " + str(k)] = 1
		var toward_ok: bool = (str(e["tgt_side"]) == "right") == (kind == "dmg")
		var tr: String = str(e["truth"])
		if tr == "DOT":
			var p2: Array = dot_src.get(str(e["where"]), [0, 0])
			if int(p2[0]) > 0 and int(p2[1]) == 0:
				tr = "EQ"
			elif int(p2[0]) == 0:
				tr = "NONE"
			else:
				continue
		if toward_ok and tr in SHOULD:
			should[kind] = float(should[kind]) + float(e["amt"])
			if float(e["amt"]) - cred > 0.5:
				under[kind] = float(under[kind]) + float(e["amt"]) - cred
				where["漏 %s %s@%s" % [tr, kind, e["where"]]] = 1
		elif not tr.begins_with("DEFER-") or tr in ["DEFER-NONE", "DEFER-REACT", "DEFER-SYN"] or not toward_ok:
			if cred > 0.5:
				over += cred
				where["多 %s %s@%s" % [tr, kind, e["where"]]] = 1
	for d in h.direct:   # credit() 直记(多件持续回复按份额拆)不经事件, 抵掉对应那一类的「漏」
		var dk: String = "dmg" if str(d["key"]) in ["phy", "mag", "tru"] else str(d["key"])
		under[dk] = float(under[dk]) - float(d["amt"])
	var ok: bool = over <= 1.0
	var tot := 0.0
	var txt: Array = []
	for k in ["dmg", "heal", "shield"]:
		var un: float = maxf(0.0, float(under[k]))
		tot += float(should[k])
		if float(should[k]) > 0.0 or un > 0.0:
			txt.append("%s 该记 %.0f 漏 %.0f" % [{"dmg": "伤害", "heal": "治疗", "shield": "护盾"}[k], float(should[k]), un])
		if un > maxf(1.0, float(should[k]) * 0.001):
			ok = false
	_ok("C %s: %s · 多记 %.0f" % [iid, " / ".join(txt), over], tot > 0.0 and ok, str(where.keys()).left(400))
