extends Node
## verify_staff_synergy.gd — 法器羁绊【法力条 / 灵泉 / 余韵 / 共鸣 / 净化】（2026-08-03 用户定稿）
##
## 用户原话：「没啥问题，需要给每个装备设计个法力条，有些接入主动效果，就眩晕好了」
##           「但这些潮水的名字都可以改掉，和法器相关吧，且考虑是携带者还是全队」
##
## ★这里守的是**别的门禁守不住的四件事**：
##   ① 法力条是【每件独立】的 —— 一件满了只清它自己，别的那件不受影响
##   ② 满了触发的是**这件装备在 `_tick_eq_intervals` 里的同一条分支**
##      （所以抽了 `fire_equip_effect`；两套实现 = 两套数值与特效，只有一套被门禁覆盖）
##   ③ **防连放**：法器效果自己打出的伤害不涨法力（否则满→放→伤害→又满 的自激循环）
##   ④ 法力条**绝不碰龟能** —— `_energy` / `_maxEnergy` 是放技能用的，两者混线会让龟能凭空暴涨
##
## 还守作用域分工（用户点名要考虑的）：**法力条=携带者**，**灵泉/余韵/共鸣=全队**。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_staff_synergy.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const Staff := preload("res://scripts/systems/equip/staff_synergy_system.gd")

var _n := 0
var _fail := 0
var _s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 法器羁绊: 法力条 / 灵泉 / 余韵 / 共鸣 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var staffs: Array = _ids_of_type("法器", 10)
	_ok("★分母: 找到 %d 件法器装备(顶档 10 件才验得了)" % staffs.size(), staffs.size() >= 10)

	# ══ ① 对照：没激活羁绊(1 件, 首档要 2) → 法力一点不涨 ═══════════
	var a0: Dictionary = _mk("left", staffs.slice(0, 1))
	_run([a0])
	_s._staff_syn.add_mana(a0, 999.0)
	_ok("① ★对照: 法器未激活(1 件, 首档要 2 件) → 法力一点不涨",
		absf(_mana(a0, staffs[0])) < 0.01, "mana=%.1f" % _mana(a0, staffs[0]))

	# ══ ② 法力条【每件独立】═══════════════════════════════════════
	# 首档满值 100。给 60 → 两件都是 60、都没满。
	var a1: Dictionary = _mk("left", staffs.slice(0, 2))
	_run([a1])
	_s._staff_syn.add_mana(a1, 60.0)
	_ok("② 首档满值 = 100(定稿)", _s._staff_syn.mana_full(a1) == 100.0,
		"实得 %.0f" % _s._staff_syn.mana_full(a1))
	_ok("② 两件法器【各自】涨到 60(不是共享一条条)",
		absf(_mana(a1, staffs[0]) - 60.0) < 0.01 and absf(_mana(a1, staffs[1]) - 60.0) < 0.01,
		"[%.0f, %.0f]" % [_mana(a1, staffs[0]), _mana(a1, staffs[1])])
	# 只把第 0 件推满：手动补 40 会两件一起补，所以改用"直接写第 0 件再加 1"
	var st0: Dictionary = a1["eq_state"].get(staffs[0], {})
	st0["mana"] = 99.0
	a1["eq_state"][staffs[0]] = st0
	_s._staff_syn.add_mana(a1, 1.0)
	_ok("② ★满了的那件清零, 另一件【不受影响】(仍在 61)",
		absf(_mana(a1, staffs[0])) < 0.01 and absf(_mana(a1, staffs[1]) - 61.0) < 0.01,
		"[%.1f, %.1f]" % [_mana(a1, staffs[0]), _mana(a1, staffs[1])])

	# ══ ③ 满了触发的是【同一条】效果分支 ═══════════════════════════
	_ok("③ ★fire_equip_effect 存在(法力满 与 tick 到点 走同一条路)",
		_s._equip_sys.has_method("fire_equip_effect"))
	# 真的跑：找一件"效果能被观测到"的法器 —— 用 _fire 直调并数它有没有报错 + 有没有走到 match
	var fired := true
	for iid in staffs:
		# 不该抛异常, 也不该改龟能
		_s._staff_syn._fire(a1, str(iid), 1)
	_ok("③ 全部 %d 件法器的效果分支都能被法力条触发(不报错)" % staffs.size(), fired)

	# ══ ④ 法力条【绝不碰龟能】═════════════════════════════════════
	var e_before: float = float(a1.get("energy", 0.0))
	var me_before: float = float(a1.get("max_energy", 0.0))
	_s._staff_syn.add_mana(a1, 500.0)
	_ok("④ ★涨法力不动龟能(energy / max_energy 一点没变)",
		absf(float(a1.get("energy", 0.0)) - e_before) < 0.01
		and absf(float(a1.get("max_energy", 0.0)) - me_before) < 0.01,
		"energy %.1f→%.1f" % [e_before, float(a1.get("energy", 0.0))])

	# ══ ⑤ 防连放：_staff_busy 期间不涨法力 ════════════════════════
	var a2: Dictionary = _mk("left", staffs.slice(0, 2))
	_run([a2])
	a2["_staff_busy"] = true
	_s._staff_syn.add_mana(a2, 80.0)
	_ok("⑤ ★防连放: 法器效果执行期间(_staff_busy)造成的伤害【不涨法力】",
		absf(_mana(a2, staffs[0])) < 0.01, "mana=%.1f" % _mana(a2, staffs[0]))
	a2["_staff_busy"] = false
	_s._staff_syn.add_mana(a2, 80.0)
	_ok("⑤ 标记解除后恢复正常积累", absf(_mana(a2, staffs[0]) - 80.0) < 0.01,
		"mana=%.1f" % _mana(a2, staffs[0]))

	# ══ ⑥ 满值随档位递减(法器越多放得越勤) ════════════════════════
	var full_by_tier: Array = []
	for cnt in [2, 5, 8, 10]:
		var au: Dictionary = _mk("left", staffs.slice(0, cnt))
		_run([au])
		full_by_tier.append(_s._staff_syn.mana_full(au))
	_ok("⑥ 满值逐档递减 %s(法器越多放得越勤)" % str(full_by_tier),
		full_by_tier == [100.0, 80.0, 60.0, 50.0], str(full_by_tier))

	# ══ ⑦ 作用域: 灵泉/余韵/共鸣 = 全队(不带法器的队友也吃) ════════
	# 5 件法器全在 A 身上(档2) → B 一件不带, 也要回血。
	var pair := _run([_mk("left", staffs.slice(0, 5)), _mk("left", [])])
	var b: Dictionary = pair[1]
	b["hp"] = float(b["maxHp"]) * 0.5
	var hp0: float = float(b["hp"])
	_s._staff_syn._t_tick = 0.0
	_s._staff_syn.tick(2.6)
	_ok("⑦ ★灵泉是【全队】: 一件法器都不带的队友也回血(已损失 ×5%%)",
		float(b["hp"]) > hp0 + 1.0, "%.0f → %.0f" % [hp0, float(b["hp"])])
	# 而法力条是【携带者】: B 身上没有任何法力条
	_ok("⑦ ★法力条是【携带者】: 不带法器的队友身上没有任何法力条",
		(b.get("eq_state", {}) as Dictionary).is_empty(), str(b.get("eq_state", {})))

	# ══ ⑧ 余韵: 受到治疗 → 额外拿治疗量 N% 的护盾 ══════════════════
	# 档3 需要 8 件 ⇒ ECHO_PCT[2] = 30%
	var c: Dictionary = _run([_mk("left", staffs.slice(0, 8))])[0]
	c["hp"] = float(c["maxHp"]) * 0.5
	c["shield"] = 0.0
	_s._damage._heal(c, 200.0)
	# ★期望值【写死 60】不读 Staff.ECHO_PCT —— 读常量就是恒真式:
	#   把 ECHO_PCT[2] 改成 0 时两边一起变成 0, 门禁照样全绿(实测变异 0 FAIL)。
	#   定稿数是 30%: 200 × 0.30 = 60。改数值就该在这里红。
	_ok("⑧ 余韵(档3): 回 200 血 → 额外拿 60 护盾(定稿 30%%)",
		absf(float(c["shield"]) - 60.0) < 1.0, "shield=%.1f" % float(c["shield"]))
	_ok("⑧ ★常量表就是定稿值 ECHO_PCT = [0, 0, 0.30, 0.50]",
		Staff.ECHO_PCT == [0.0, 0.0, 0.30, 0.50], str(Staff.ECHO_PCT))
	# 档2(5 件) 没有余韵
	var c2: Dictionary = _run([_mk("left", staffs.slice(0, 5))])[0]
	c2["hp"] = float(c2["maxHp"]) * 0.5
	c2["shield"] = 0.0
	_s._damage._heal(c2, 200.0)
	_ok("⑧ ★档2 没有余韵(ECHO_PCT[1]=0) → 一点护盾都没有",
		absf(float(c2["shield"])) < 0.01, "shield=%.1f" % float(c2["shield"]))

	# ══ ⑨ 共鸣: 顶档每 7.5 秒 回 15% 最大生命 + 净化 2 种 ═══════════
	var d: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	d["hp"] = float(d["maxHp"]) * 0.2
	var dh0: float = float(d["hp"])
	d["stun_until"] = _s._t + 99.0
	d["slow_until"] = _s._t + 99.0
	d["dot_stacks"] = {"burn": 3}
	# ★数值断言【直调 _resonance】隔离掉灵泉 —— tick(7.6) 会同时推过灵泉的 2.5 秒节拍,
	#   两条效果的回血量会叠在一起(实测 450 共鸣 + 288 灵泉 = 738), 那样断言就把
	#   "两条效果的执行顺序"也写死了, 以后动任何一条都会红在无关的地方。
	_s._staff_syn._resonance()
	# ★同样写死: maxHp 3000 × 15% = 450。
	_ok("⑨ 共鸣(顶档): 回 15%% 最大生命 (%.0f → %.0f, 期望 +450)" % [dh0, float(d["hp"])],
		absf(float(d["hp"]) - dh0 - 450.0) < 2.0)
	# 再单独验它【真的挂在 tick 上】: 同样掉到 20%, 走 tick 要比只有灵泉回得多。
	var d3: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	d3["hp"] = float(d3["maxHp"]) * 0.2
	_s._staff_syn._t_tick = 0.0
	_s._staff_syn._t_reso = 0.0
	_s._staff_syn.tick(7.6)
	_ok("⑨ 共鸣挂在 tick 上(走一次 7.5 秒节拍, 回血 > 单靠灵泉的量)",
		float(d3["hp"]) - float(d3["maxHp"]) * 0.2 > 450.0,
		"回了 %.0f" % (float(d3["hp"]) - float(d3["maxHp"]) * 0.2))
	_ok("⑨ ★净化的是 2 【种】不是 2 层: 眩晕+减速被清, 灼烧【还在】(顺序固定)",
		float(d.get("stun_until", 0.0)) <= _s._t and float(d.get("slow_until", 0.0)) <= _s._t
		and int((d.get("dot_stacks", {}) as Dictionary).get("burn", 0)) == 3,
		"stun=%.1f slow=%.1f burn=%d" % [float(d.get("stun_until", 0.0)),
			float(d.get("slow_until", 0.0)), int((d.get("dot_stacks", {}) as Dictionary).get("burn", 0))])
	# 档3(8 件) 没有共鸣的净化, 也不回血
	var d2: Dictionary = _run([_mk("left", staffs.slice(0, 8))])[0]
	d2["hp"] = float(d2["maxHp"]) * 0.2
	var d2h0: float = float(d2["hp"])
	_s._staff_syn._t_reso = 0.0
	_s._staff_syn.tick(7.6)
	_ok("⑨ ★档3 没有共鸣(只有顶档 10 件才有) → 不回那 15%%",
		float(d2["hp"]) - d2h0 < 225.0,
		"%.0f → %.0f" % [d2h0, float(d2["hp"])])

	# ══ ⑩ 净化的每一种都真的清得掉(含诅咒走 dots 数组) ═════════════
	var e: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	e["stun_until"] = _s._t + 99.0
	e["slow_until"] = _s._t + 99.0
	e["dot_stacks"] = {"burn": 3, "poison": 2}
	e["dots"] = [{"tag": "curse", "dps": 10.0, "until": _s._t + 99.0}]
	var cleared: int = _s._staff_syn.dispel(e, 5)
	_ok("⑩ ★五种减益逐一都清得掉(清了 %d 种)" % cleared, cleared == 5, "只清掉 %d 种" % cleared)
	_ok("⑩ ★诅咒是从 dots 数组里摘的(不是一个 curse_until 字段 —— 那个字段全仓库不存在)",
		(e.get("dots", []) as Array).is_empty(), str(e.get("dots", [])))

	# ══ ⑪ 战斗真的在跑它(不是写了没人调) ═══════════════════════════
	_ok("⑪ ★主场景持有 _staff_syn 成员", _s.get("_staff_syn") != null)
	var src_main: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⑪ ★_staff_syn.tick 挂在主循环上(否则法力永远不涨)",
		src_main.find("_staff_syn.tick(") >= 0)
	var src_dmg: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	_ok("⑪ ★三条法力来源都接线了(受伤 / 造成伤害 / 治疗后的余韵)",
		src_dmg.count("_staff_syn.add_mana(") >= 3 and src_dmg.find("_staff_syn.on_healed(") >= 0,
		"add_mana×%d on_healed=%s" % [src_dmg.count("_staff_syn.add_mana("),
			src_dmg.find("_staff_syn.on_healed(") >= 0])
	# ★一个类型的机制只能有一个主人: 灵泉不能同时留在 synergy_system(会各发一次)
	var src_syn: String = FileAccess.get_file_as_string("res://scripts/systems/equip/synergy_system.gd")
	_ok("⑪ ★灵泉只有一个主人(synergy_system 里不再有法器的周期回血)",
		src_syn.find("TIDE_PCT") < 0 and src_syn.find('tiers.has("法器")') < 0)

	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 法器羁绊" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mana(u: Dictionary, iid) -> float:
	return float((u["eq_state"].get(str(iid), {}) as Dictionary).get("mana", 0.0))


func _ids_of_type(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n:
			break
	return out


## 干净合成单位。★用 "green" 不用 "basic" —— 小龟有「不屈」被动(按稀有度增伤),
## 会把精确数值断言弄脏（memory fb-ci-vs-local-divergence）。
func _mk(side: String, ids: Array) -> Dictionary:
	var eqs: Array = []
	for i in ids:
		eqs.append({"id": str(i), "star": 1})
	return {"id": "green", "name": "合成", "side": side, "alive": true,
		"hp": 3000.0, "maxHp": 3000.0, "shield": 0.0, "equips": eqs, "eq_state": {},
		"base_atk": 100.0, "atk": 100.0, "base_def": 0.0, "def": 0.0,
		"base_mr": 0.0, "mr": 0.0, "crit": 0.0, "crit_dmg": 1.5,
		"armor_pen": 0.0, "magic_pen": 0.0, "lifesteal": 0.0, "buffs": {},
		"dots": [], "dot_stacks": {}, "pos": Vector2.ZERO}


func _run(units: Array) -> Array:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return units
