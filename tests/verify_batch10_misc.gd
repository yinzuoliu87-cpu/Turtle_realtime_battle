extends Node
## verify_batch10_misc.gd — 第十批 095 / 087 × 092 / 093 五条修正(E1 E6 E7 E12 E14)
##
## ★由来(2026-09-15, 087~096 调查 · 方案书 20260915c):
##   E1 095 反击没传 from_equip ⇒ 双方都有圣盾时反击回钩对方的受伤钩子, 互弹成无限循环。
##   E6 087 压载层与 092 剧毒缓速各自快照「原始移速」再整体改写 `move_perm`, 互相覆盖。
##   E7 093 远程携带者的附带伤害挂在出手钩子, 弹体还没到目标就先掉血。
##   E12 反击判的是圣盾值, 而圣盾值不随护盾吸收扣减 ⇒ 盾打穿了照样反击(无头 / 血条没刷新时)。
##   E14 圣盾 3 秒计时 `_t_holy` 是全局的, 换路清场不归零。
## ★判据量产品自己的账(有效生命 = 血 + 盾 / move_perm / 延后队列), 不数我插的标记。
const HOLY := "p2eq_095"

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
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _eff(u: Dictionary) -> float:
	return float(u.get("hp", 0.0)) + float(u.get("shield", 0.0))


func _drain(sec: float) -> void:
	var k: int = int(round(sec / 0.02))
	for _i in range(k):
		_s._ballistics._step_pending_shots(0.02)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 第十批 095 / 087×092 / 093 (E1 E6 E7 E12 E14) ===")
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	_s._units.clear()

	_t_e1_riposte_no_loop()
	_t_e12_riposte_needs_live_shield()
	_t_e14_holy_timer_reset()
	_t_e6_move_perm_compose()
	_t_e7_incense_on_hit()

	print("")
	if _n < 23:
		_fail += 1
		print("  [FAIL] ★分母: 断言只有 %d 条(<23) —— 有整段被跳过了" % _n)
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


# ── E1 双方都有圣盾: 一段伤害只反击一次 ──
func _t_e1_riposte_no_loop() -> void:
	print("── E1 095 反击不互弹 ──")
	_s._units.clear()
	var a: Dictionary = _mk("green", "left", Vector2(-120.0, 0.0))
	var b: Dictionary = _mk("green", "right", Vector2(120.0, 0.0))
	for u in [a, b]:
		u["equips"] = [{"id": HOLY, "star": 3}]
		u["shield"] = 1000.0
		u["_holyShieldVal"] = 1000.0
	_s._synergy._by_side = {"left": {"盾": 1}, "right": {"盾": 1}}
	_s._pending_shots.clear()
	var a0: float = _eff(a)
	var b0: float = _eff(b)
	_s._damage._apply_damage_from(a, b, 10, Color.WHITE)
	_drain(4.0)
	var la: float = a0 - _eff(a)
	var lb: float = b0 - _eff(b)
	_ok("★分母: b 真的反击了 a(a 掉 %.1f, 应为 %.0f)" % [la, _s._shield_syn.RIPOSTE_FLAT],
		absf(la - _s._shield_syn.RIPOSTE_FLAT) < 0.01)
	_ok("★★E1 反击不回弹: b 只挨了那一段 10(实测 %.1f; 修前 3 秒内双方各挨 5 次反击)" % lb,
		absf(lb - 10.0) < 0.01)
	_ok("E1 4 秒后延后队列里没有还挂着的反击", _s._pending_shots.is_empty(),
		"剩 %d 条" % _s._pending_shots.size())
	_s._synergy._by_side = {}


# ── E12 护盾已被打穿而圣盾值残留: 不反击, 盾板也不亮 ──
func _t_e12_riposte_needs_live_shield() -> void:
	print("── E12 反击要护盾真的在 ──")
	_s._units.clear()
	var me: Dictionary = _mk("green", "left", Vector2(-120.0, 0.0))
	var foe: Dictionary = _mk("green", "right", Vector2(120.0, 0.0))
	me["equips"] = [{"id": HOLY, "star": 3}]
	_s._synergy._by_side = {"left": {"盾": 1}, "right": {}}
	_s._pending_shots.clear()
	me["shield"] = 0.0
	me["_holyShieldVal"] = 30.0
	var f0: float = _eff(foe)
	_s._shield_syn.on_damaged(me, foe, 10)
	_drain(2.0)
	_ok("★★E12 护盾 0 / 圣盾值残留 30: 不反击(实测敌掉 %.1f)" % (f0 - _eff(foe)), absf(f0 - _eff(foe)) < 0.01)
	_ok("★★E12 同一时刻盾板也不亮(与反击同一判据, 两者永远同步)",
		not _s._shield_syn._holy_vfx._should_hold(me))
	me["shield"] = 30.0
	f0 = _eff(foe)
	_s._shield_syn.on_damaged(me, foe, 10)
	_drain(2.0)
	_ok("★分母: 护盾还在(30/30)时照常反击 %.0f(实测 %.1f)" % [_s._shield_syn.RIPOSTE_FLAT, f0 - _eff(foe)],
		absf(f0 - _eff(foe) - _s._shield_syn.RIPOSTE_FLAT) < 0.01)
	_ok("★分母: 护盾还在时盾板亮着", _s._shield_syn._holy_vfx._should_hold(me))
	_s._synergy._by_side = {}


# ── E14 换路清场: 圣盾 3 秒计时归零 ──
func _t_e14_holy_timer_reset() -> void:
	print("── E14 换路清场圣盾计时归零 ──")
	_s._units.clear()
	var hu: Dictionary = _mk("green", "left", Vector2(0.0, 0.0))
	hu["equips"] = [{"id": HOLY, "star": 3}]
	var syn = _s._shield_syn
	syn._t_holy = syn.HOLY_PERIOD - 0.1
	syn.clear()
	var s0: float = float(hu["shield"])
	syn.tick(0.2)
	_ok("★★E14 换路清场后 0.2 秒不出首盾(修前清场前攒的 2.9 秒还在, 0.2 秒就出)",
		is_equal_approx(float(hu["shield"]), s0), "盾 %.0f → %.0f" % [s0, float(hu["shield"])])
	syn._t_holy = syn.HOLY_PERIOD - 0.1
	syn.tick(0.2)
	_ok("★分母: 不清场时同样 0.2 秒就出盾(证明上面那条量得到)", float(hu["shield"]) > s0,
		"盾 %.0f → %.0f" % [s0, float(hu["shield"])])


# ── E6 087 压载层 × 092 剧毒缓速: 任意先后, move_perm = 基础 × 压载 × 缓速 ──
func _mk_diver(off: Vector2) -> Dictionary:
	var v: Dictionary = _mk("fortune", "left", off, 10000.0)
	v["move_perm"] = 1.0
	v["equips"] = [{"id": "p2eq_087", "star": 3}]
	v["_b4_eq"] = true
	_s._equip_sys._gadget_sys.on_spawn(v, "p2eq_087", 2)
	## 首帧 tick_unit 才给压载舱注满容量(on_spawn 只把 cap 置 0) —— 同 verify_eq_gadget_batch 的 _step。
	## 第一版漏了这一行: 舱是空的, 伤害全绕过去, 压载层恒为 0, A②/B② 两条恒真, 靠三条分母断言抓到。
	_s._equip_sys._gadget_sys.tick_unit(v, 0.05)
	return v


func _want_mp(v: Dictionary, base: float) -> float:
	var dive: float = 1.0 + EqGadgetBatch.DIVE_MOVE_PER * float(maxi(0, int(v.get("_dive_stk", 0))))
	var k: int = int(v.get("_vslow_n", 0))
	var slow: float = _s._equip_sys._venom.vslow_move_mult(k) if k > 0 else 1.0
	return base * dive * slow


func _t_e6_move_perm_compose() -> void:
	print("── E6 087 × 092 移速合成 ──")
	_s._units.clear()
	var vd = _s._equip_sys._venom
	var foe: Dictionary = _mk("green", "right", Vector2(260.0, 0.0))
	# 顺序 A: 先压载 → 再中毒 → 压载层变 → 毒清
	var v: Dictionary = _mk_diver(Vector2(-200.0, 0.0))
	var base: float = float(v["move_perm"])
	_s._damage._apply_damage_from(foe, v, 3000, Color.WHITE)
	var n1: int = int(v.get("_dive_stk", -1))
	_ok("★分母: 挨打后 087 压载层 > 0(%d 层)" % n1, n1 > 0)
	vd.add_vslow(v, 10)
	_ok("A① 中毒 10 层: move_perm = 基础 × 压载 × 缓速(%.4f vs %.4f)" % [float(v["move_perm"]), _want_mp(v, base)],
		absf(float(v["move_perm"]) - _want_mp(v, base)) < 1e-4)
	_s._damage._apply_damage_from(foe, v, 2000, Color.WHITE)
	var n2: int = int(v.get("_dive_stk", -1))
	_ok("★分母: 再挨一下压载层真的变了(%d → %d)" % [n1, n2], n2 != n1)
	_ok("★★E6 A② 中毒期间压载层变: 缓速没被抹掉(%.4f vs %.4f; 修前 1.12 vs 0.896)"
		% [float(v["move_perm"]), _want_mp(v, base)], absf(float(v["move_perm"]) - _want_mp(v, base)) < 1e-4)
	vd._set_vslow(v, 0)
	_ok("★★E6 A③ 毒清掉: 回到 基础 × 压载(%.4f vs %.4f)" % [float(v["move_perm"]), _want_mp(v, base)],
		absf(float(v["move_perm"]) - _want_mp(v, base)) < 1e-4)
	# 顺序 B: 先中毒 → 再首次同步压载层 → 毒清
	var w: Dictionary = _mk_diver(Vector2(-200.0, 120.0))
	var base_w: float = float(w["move_perm"])
	vd.add_vslow(w, 10)
	_s._damage._apply_damage_from(foe, w, 3000, Color.WHITE)
	_ok("★分母: B 先中毒后压载层 > 0(%d 层)" % int(w.get("_dive_stk", -1)), int(w.get("_dive_stk", -1)) > 0)
	_ok("E6 B① 先毒后压载: 两者都在(%.4f vs %.4f)" % [float(w["move_perm"]), _want_mp(w, base_w)],
		absf(float(w["move_perm"]) - _want_mp(w, base_w)) < 1e-4)
	vd._set_vslow(w, 0)
	_ok("★★E6 B② 毒清掉后不留永久减速: 回到 基础 × 压载(%.4f vs %.4f; 修前 0.618 vs 1.03)"
		% [float(w["move_perm"]), _want_mp(w, base_w)], absf(float(w["move_perm"]) - _want_mp(w, base_w)) < 1e-4)


# ── E7 093 附带伤害随普攻命中结算 ──
func _t_e7_incense_on_hit() -> void:
	print("── E7 093 附带伤害挂命中侧 ──")
	_s._units.clear()
	var u: Dictionary = _mk("green", "left", Vector2(-300.0, 0.0))
	var tgt: Dictionary = _mk("green", "right", Vector2(300.0, 0.0), 5000.0)
	u["equips"] = [{"id": "p2eq_093", "star": 3}]
	u["_b4_eq"] = true
	var inc = _s._equip_sys._incense
	inc.on_spawn(u, "p2eq_093", 2)
	inc.tick_unit(u, 12.1)
	var stt: Dictionary = u["eq_state"]["p2eq_093"]
	_ok("★分母: 满 12 秒强化 4 次普攻", int(stt.get("emp", 0)) == 4, "emp=%d" % int(stt.get("emp", 0)))
	var want: float = 80.0 + 5000.0 * 0.02
	var h0: float = float(tgt["hp"])
	_s._equip_sys._eq_on_basic_attack(u, tgt)          # 出手那一帧(真入口)
	_ok("★分母: 出手消耗了一次强化(4 → %d)" % int(stt.get("emp", 0)), int(stt.get("emp", 0)) == 3)
	_ok("★★E7 出手那一帧目标不掉血(修前当帧就掉 %.0f)" % want, absf(h0 - float(tgt["hp"])) < 0.01,
		"掉了 %.1f" % (h0 - float(tgt["hp"])))
	_s._damage._apply_damage_from(u, tgt, 10, Color.WHITE, 0.0, false, false, false, true, true, true)
	var dealt: float = h0 - float(tgt["hp"])
	_ok("★★E7 弹体命中(普攻)时附带伤害才落地: 掉 %.0f(普攻 10 + 附带 %.0f)" % [dealt, want],
		absf(dealt - (10.0 + want)) <= 2.0)
	var h1: float = float(tgt["hp"])
	_s._equip_sys._eq_on_basic_attack(u, tgt)
	_s._damage._apply_damage_from(u, tgt, 10, Color.WHITE, 0.0, false, false, false, true, true, false)
	_ok("E7 技能命中不兑现附带(只认普攻命中 · 掉 %.0f 应为 10)" % (h1 - float(tgt["hp"])),
		absf((h1 - float(tgt["hp"])) - 10.0) < 0.01)
	var h2: float = float(tgt["hp"])
	_s._damage._apply_damage_from(u, tgt, 10, Color.WHITE, 0.0, false, false, false, true, true, true)
	_ok("E7 下一次普攻命中兑现刚才那一发(掉 %.0f 应为 %.0f)" % [h2 - float(tgt["hp"]), 10.0 + want],
		absf((h2 - float(tgt["hp"])) - (10.0 + want)) <= 2.0)
