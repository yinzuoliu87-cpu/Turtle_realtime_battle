extends Node
## verify_eq_zero_gate.gd — 补上最后两件【零门禁装备】(2026-08-31)
##
## ★由来: 常驻队列里有一条「16 件零门禁装备」。2026-08-31 逐个核实,
##   **那 16 件早就全有门禁了**(又一次照旧账念·[[fb-registered-todos-rot]]);
##   全仓 95 件里真正一次都没被门禁提到的只剩 2 件 —— 011 与 054。
##   两件都**已实现**, 缺的是"数值有没有对"这一层。
##
## ★054 的判据必须是【端到端量掉血】而不是"标记设了没有":
##   `eq_cannot_be_dodged` 这个标记是我在 equip_stats_apply 里看到的,
##   断言它存在 = 断言我自己看到的那一行, 守不住"消费侧还读不读它"
##   ([[fb-verify-must-run-the-real-path]])。所以拿 100% 闪避的目标去打。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + off)
	for k in ["shield", "flat_dr", "def", "mr", "base_def", "base_mr", "dodge_bonus",
			"damage_reduction", "damage_amp", "crit", "armor_pen", "magic_pen",
			"armor_pen_pct", "magic_pen_pct", "lifesteal", "heal_amp"]:
		u[k] = 0.0
	u["maxHp"] = hp
	u["hp"] = hp
	u["dots"] = []
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 最后两件零门禁装备: 054 瞄准镜 / 011 饮血护符坠 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	await _t054()
	_t011_cap()

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 7:
		print("  [FAIL] ★分母: 断言只有 %d 条(<7) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 零门禁装备补齐" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ── 054 瞄准镜: 造成的伤害无视闪避(必中) ──────────────────
func _t054() -> void:
	print("── 054 瞄准镜: 必中 ──")
	## ① 对照: 目标 100% 闪避, 攻击者【不带】054 ⇒ 必须一下都打不中
	_s._units.clear()
	var a: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var d: Dictionary = _mk("right", Vector2(120.0, 0.0))
	d["dodge_bonus"] = 1.0
	var h0: float = float(d["hp"])
	for _i in range(40):
		_s._damage._apply_damage_from(a, d, 100, Color("#ffffff"))
	var lost_ctrl: float = h0 - float(d["hp"])
	_ok("054 ★分母·对照: 100%% 闪避的目标, 不带 054 时 40 下【一下都打不中】",
		lost_ctrl <= 0.0, "掉了 %.0f 血" % lost_ctrl)

	## ② 带 054 ⇒ 40 下全中
	_s._units.clear()
	var a2: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var d2: Dictionary = _mk("right", Vector2(120.0, 0.0))
	d2["dodge_bonus"] = 1.0
	a2["equips"] = [{"id": "p2eq_054", "star": 3}]
	a2["eq_state"] = {"p2eq_054": {}}
	_s._equip_sys._stats._eq_apply_all_stats()
	var h1: float = float(d2["hp"])
	for _i in range(40):
		_s._damage._apply_damage_from(a2, d2, 100, Color("#ffffff"))
	var lost: float = h1 - float(d2["hp"])
	_ok("054 ★★带 054 时同样 40 下【全部命中】(端到端量掉血, 不是断言标记存在)",
		lost >= 4000.0, "掉了 %.0f 血(期望 ≥4000)" % lost)
	_ok("054 佐证: 携带者身上确实立了 eq_cannot_be_dodged",
		bool(a2.get("eq_cannot_be_dodged", false)))
	await get_tree().process_frame


## ── 011 饮血护符坠: 溢出治疗转血护盾, 上限 200/350/500 ────
func _t011_cap() -> void:
	print("── 011 饮血护符坠: 溢出治疗转血护盾(上限 200/350/500) ──")
	var want := [200.0, 350.0, 500.0]
	var got := []
	for si in range(3):
		_s._units.clear()
		var u: Dictionary = _mk("left", Vector2(-120.0, 0.0))
		u["equips"] = [{"id": "p2eq_011", "star": si + 1}]
		u["eq_state"] = {"p2eq_011": {}}
		_s._equip_sys._stats._eq_apply_all_stats()
		got.append(float(u.get("overheal2shield_cap", -1.0)))
	_ok("011 ★★逐星血护盾上限 = 200/350/500(文案数)", got == want, str(got))

	## 连斩刀数: 5/6/8 —— 从产品常量读不出来(是字面量), 所以拿源码对
	## ★这两条原本是拿【源码子串】对字面量的。子串判据证明的是"源码里有这串字",
	##   不是"跑起来真是这样"; 而且代码一搬家就红(2026-09-10 011 搬进 eq_blood_combo.gd 就红了一次)。
	##   ⇒ 两个量都抽成了纯函数, 这里**真调它们**(memory `fb-weld-visual-lessons-into-gate`)。
	var bd = _s._equip_sys._blood_sys
	_ok("011 ★分母: 连斩子系统在位", bd != null)
	_ok("011 连斩刀数 = 5/6/8: [%d, %d, %d]" % [bd.combo_hits(0), bd.combo_hits(1), bd.combo_hits(2)],
		bd.combo_hits(0) == 5 and bd.combo_hits(1) == 6 and bd.combo_hits(2) == 8)
	## ★这条原本是 `src.contains("pow(0.85, k)")` —— 源码子串是**假判据**
	##   (memory `fb-weld-visual-lessons-into-gate`: 要走真函数)。2026-09-10 那个表达式被抽成了
	##   `EqBloodCombo.blood_decay(k)`(伤害与斩痕宽度**共用**它), 于是这条当场红了 ——
	##   而产品其实是对的。⇒ 改成**真调它**, 顺带把 0 刀/末刀两端也钉住。
	_ok("011 每刀衰减 0.85^k: [0]=%.3f [1]=%.3f [7]=%.4f" % [bd.blood_decay(0), bd.blood_decay(1), bd.blood_decay(7)],
		is_equal_approx(bd.blood_decay(0), 1.0) and is_equal_approx(bd.blood_decay(1), 0.85)
			and absf(bd.blood_decay(7) - pow(0.85, 7)) < 1e-6)
	## ★多件取最大上限(注释承诺的行为), 拿两件不同星级验
	_s._units.clear()
	var m: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	## ★★3★ 放【前面】、1★ 放后面 —— 顺序很关键:
	##   反向验证抓到我第一版把 1★ 放前 3★ 放后, 那样"取最大"和"取最后一件"
	##   **答案都是 500**, 两种行为分不开 ⇒ 把 maxf() 换成直接赋值门禁照样绿。
	##   倒过来之后: 取最大 = 500, 取最后一件 = 200, 判据才卡得住这个形状。
	m["equips"] = [{"id": "p2eq_011", "star": 3}, {"id": "p2eq_011", "star": 1}]
	m["eq_state"] = {"p2eq_011": {}}
	_s._equip_sys._stats._eq_apply_all_stats()
	_ok("011 多件同款【取最大上限】(3★ 在前 1★ 在后 ⇒ 必须是 500 不是 200)",
		is_equal_approx(float(m.get("overheal2shield_cap", -1.0)), 500.0),
		"实得 %.0f" % float(m.get("overheal2shield_cap", -1.0)))
