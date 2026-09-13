extends Node
## verify_ice_fissure.gd — 029 冰封水母【冰道】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「该法器法力条集满时为自身获得 **100/160/250 点护盾**并砸地, 朝**最近的敌人**
##   推出一条冰道(长 IceSystem.FISSURE_REACH 码、中线两侧各 IceSystem.FISSURE_HALF_W 码),
##   **冰道推进到谁才结算谁**: 受到 **25/40/60 魔法伤害**,
##   被竖直击飞约 IceSystem.FISSURE_KNOCK_SEC 秒并**冰封 1/1.8/2.5 秒**。」
##
## ★★改之前**两层延时都挂在 tween 上**:
##   ① `_eq_ice_fissure` 的 0.3 秒砸地前摇 `tween_interval`
##   ② `_ice_fissure_go` 里【每个敌人各一条】的 `tween_interval(d)` —— 这一条就是文案写的
##      「冰道推进到谁才结算谁」, 也就是说**这条节拍本身是规格的一部分**。
##   tween 走**未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5)
##   ⇒ **整条冰道一个人都不结算**: 伤害 / 击飞 / 冰封全不落。
##   现在两层都走共享原语 `EquipTickSystem.schedule`(024/025/026/028 同一个)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ICE := preload("res://scripts/systems/skills/ice_system.gd")

const SHIELD := [100.0, 160.0, 250.0]
const FREEZE := [1.0, 1.8, 2.5]

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
	u["mr"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 029 冰封水母: 冰道长 %.0f 码 · 半宽 %.0f 码 ===" % [ICE.FISSURE_REACH, ICE.FISSURE_HALF_W])
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ── ① ★分母 + 几何: ±90 码那条带 ────────────────────────────────
	_ok("① ★分母: 冰道 %.0f 码长 / 半宽 %.0f 码" % [ICE.FISSURE_REACH, ICE.FISSURE_HALF_W],
		absf(ICE.FISSURE_REACH - 500.0) < 0.01 and absf(ICE.FISSURE_HALF_W - 90.0) < 0.01)
	## ★取样点用**写死的绝对码数**, 不拿被测常量去算 —— 那是恒真式(024 的 M5 抓到过)
	var org := Vector2(500.0, 400.0)
	var dir := Vector2.RIGHT
	_ok("① 带内算命中(±45 码)", _s._on_line(org, dir, Vector2(700.0, 445.0), ICE.FISSURE_HALF_W))
	_ok("① ★边界含在内(±89 码)", _s._on_line(org, dir, Vector2(700.0, 489.0), ICE.FISSURE_HALF_W))
	_ok("① ★★带外不算(±120 码 —— 挡多了也是错)",
		not _s._on_line(org, dir, Vector2(700.0, 520.0), ICE.FISSURE_HALF_W))

	# ── ② ★★释放即上盾 100/160/250(吃星级) ────────────────────────
	for si in [0, 1, 2]:
		_s._units.clear()
		ets._bolt_q.clear()
		var cs: Dictionary = _mk(500.0, 400.0, "left")
		cs["shield"] = 0.0
		_s._units.append(cs)
		_s._units.append(_mk(700.0, 400.0, "right"))
		_s._equip_sys._eq_ice_fissure(cs, si)
		_ok("② ★★★%d 星释放即上盾 %.0f 点(应 %.0f)" % [si + 1, float(cs["shield"]), SHIELD[si]],
			absf(float(cs["shield"]) - SHIELD[si]) < 0.5,
			"文案: 为自身获得 100/160/250 点护盾")

	# ── ③ ★★★「冰道推进到谁才结算谁」—— 这条节拍是规格, 要量出来 ──────
	## 远的那个**必须比近的晚**结算。改之前两层都在 tween 上 ⇒ 两个都永远不结算。
	_s._units.clear()
	ets._bolt_q.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	var near: Dictionary = _mk(560.0, 400.0, "right")      # 沿线 60 码 ⇒ 很早
	var far: Dictionary = _mk(980.0, 400.0, "right")       # 沿线 480 码 ⇒ 接近最远端
	_s._units.append(c3)
	_s._units.append(near)
	_s._units.append(far)
	var hn0: float = float(near["hp"])
	var hf0: float = float(far["hp"])
	_s._equip_sys._eq_ice_fissure(c3, 2)
	## 推到「前摇 + 冰道走了一半」: 近的该结算了, 远的还不该
	var half_steps: int = int((ICE.FISSURE_WINDUP + ICE.FISSURE_SWEEP_SEC * 0.5) * 60.0) + 2
	for _k in range(half_steps):
		_s._sim_step(_s.SIM_DT, false, false)
	var dn_half: float = hn0 - float(near["hp"])
	var df_half: float = hf0 - float(far["hp"])
	_ok("③ ★★★半程时: 近的已结算(%.0f) 而远的还没(%.0f)" % [dn_half, df_half],
		dn_half > 0.0 and df_half <= 0.0,
		"文案明写「冰道推进到谁才结算谁」—— 两个同时掉血就不是一条在推进的冰道")
	## 再推完剩下的半程 + 余量
	for _k in range(120):
		_s._sim_step(_s.SIM_DT, false, false)
	var df_end: float = hf0 - float(far["hp"])
	_ok("③ ★★★推完全程之后远的也结算了(%.0f)" % df_end, df_end > 0.0,
		"若为 0: 结算埋在 tween 里而 tween 无头下推不动 —— 就是 §3.5 那条老病")
	_ok("③ 共享延时队列已排空(没有漏结算的项)", ets._bolt_q.is_empty(),
		"剩 %d 项" % ets._bolt_q.size())

	# ── ④ ★★带外的人**不该**被冰道扫到(挡多了也是错) ──────────────────
	_s._units.clear()
	ets._bolt_q.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left")
	var inside: Dictionary = _mk(700.0, 445.0, "right")
	var outside: Dictionary = _mk(700.0, 560.0, "right")   # 偏离中线 160 码 > 90
	var beyond: Dictionary = _mk(1200.0, 400.0, "right")   # 沿线 700 码 > 500
	_s._units.append(c4)
	_s._units.append(inside)
	_s._units.append(outside)
	_s._units.append(beyond)
	var hi: float = float(inside["hp"])
	var ho: float = float(outside["hp"])
	var hb: float = float(beyond["hp"])
	_s._equip_sys._eq_ice_fissure(c4, 2)
	for _k in range(150):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("④ ★分母: 带内那个挨打了(%.0f)" % (hi - float(inside["hp"])), hi - float(inside["hp"]) > 0.0)
	_ok("④ ★★偏离中线 160 码的没挨打(%.0f)" % (ho - float(outside["hp"])),
		absf(ho - float(outside["hp"])) < 0.01)
	_ok("④ ★★沿线 700 码(超出 %.0f 码冰道)的没挨打(%.0f)"
		% [ICE.FISSURE_REACH, hb - float(beyond["hp"])],
		absf(hb - float(beyond["hp"])) < 0.01)

	# ── ⑤ 数值: 伤害吃星级 + 魔法伤害 + 冰封时长 + 击飞 ────────────────
	_s._units.clear()
	ets._bolt_q.clear()
	var c5: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c5)
	var got: Array = []
	var frz: Array = []
	for si in [0, 1, 2]:
		var o: Dictionary = _mk(700.0 + 60.0 * si, 400.0, "right")
		_s._units.append(o)
		var h: float = float(o["hp"])
		_s._ice_sys._ice_fissure_hit(c5, o, si)
		got.append(h - float(o["hp"]))
		frz.append(float(o.get("stun_until", 0.0)) - _s._t)
	_ok("⑤ ★分母: 三个星级都掉血了(%.0f / %.0f / %.0f)" % [got[0], got[1], got[2]],
		got[0] > 0.0 and got[1] > 0.0 and got[2] > 0.0)
	_ok("⑤ ★★伤害比例对得上 25:40:60(实测 %.0f:%.0f:%.0f)" % [got[0], got[1], got[2]],
		absf(float(got[1]) / float(got[0]) - 40.0 / 25.0) < 0.05
			and absf(float(got[2]) / float(got[0]) - 60.0 / 25.0) < 0.05)
	_ok("⑤ ★★★冰封时长吃星级 %.1f / %.1f / %.1f(应 1.0 / 1.8 / 2.5)" % [frz[0], frz[1], frz[2]],
		absf(frz[0] - FREEZE[0]) < 0.1 and absf(frz[1] - FREEZE[1]) < 0.1
			and absf(frz[2] - FREEZE[2]) < 0.1)
	var knocked: Dictionary = _mk(900.0, 400.0, "right")
	_s._units.append(knocked)
	_s._ice_sys._ice_fissure_hit(c5, knocked, 2)
	_ok("⑤ ★★被竖直击飞(airborne=%s, vy=%.1f)"
		% [str(knocked.get("airborne", false)), float(knocked.get("vy", 0.0))],
		bool(knocked.get("airborne", false)) and float(knocked.get("vy", 0.0)) > 0.0,
		"文案明写「被竖直击飞约 %.1f 秒」" % ICE.FISSURE_KNOCK_SEC)
	var hardy: Dictionary = _mk(960.0, 400.0, "right")
	hardy["mr"] = 500.0
	_s._units.append(hardy)
	var hy: float = float(hardy["hp"])
	_s._ice_sys._ice_fissure_hit(c5, hardy, 2)
	var dy: float = hy - float(hardy["hp"])
	_ok("⑤ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】(软 %.0f vs 硬 %.0f)" % [got[2], dy],
		dy < float(got[2]) * 0.5)

	# ── ⑥ ★★★上盾走的是【通用护盾罩】, 不是 029 自绘的那个球 ──────────
	## 原来 `_eq_ice_fissure` 在 `_grant_shield` 之后又调了一次自绘的 `_shield_bubble`:
	##   那个球用 `VfxTex._make_fire_glow_tex()`(程序生成) + `tween_property(pixel_size)`
	##   (**连续缩放像素贴图**, 被否过的那个糊), 实拍是一个把龟整个吞掉的不透明米色实心球,
	##   而且它盖在**通用护盾罩**上面 —— 通用罩 2026-09-11 才刚做好(用户否掉地上金圈之后)。
	## memory [[fb-hand-rolled-copies-drift]]: 共享原语到位之后, 单件的手抄副本永远落后一次。
	var VX2 = load("res://scripts/scenes/battle/battle_vfx.gd")
	_s._units.clear()
	ets._bolt_q.clear()
	_s._follow_vfx.clear()
	var c6: Dictionary = _mk(500.0, 400.0, "left")
	c6["shield"] = 0.0
	_s._units.append(c6)
	_s._units.append(_mk(700.0, 400.0, "right"))
	_ok("⑥ ★分母: 放之前跟随特效表是空的", _s._follow_vfx.is_empty())
	_s._equip_sys._eq_ice_fissure(c6, 2)
	var shells := 0
	var others := 0
	for f in _s._follow_vfx:
		var sp = f["spr"]
		if not is_instance_valid(sp) or sp.texture == null:
			continue
		if not is_same(f["unit"], c6):
			continue
		if str(sp.texture.resource_path) == VX2.SHELL_TEX:
			shells += 1
		else:
			others += 1
	_ok("⑥ ★★★上盾那一下罩的是【通用护盾罩】(%d 个)" % shells, shells == 1,
		"0 个 = 没走通用原语; 2 个 = 叠了两层")
	_ok("⑥ ★★携带者身上没有第二层自绘的护盾演出(多出来 %d 个)" % others, others == 0,
		"自绘的球会把通用罩整个盖住")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 21:
		print("  [FAIL] ★断言只有 %d 条(<21) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 029 冰封水母" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
