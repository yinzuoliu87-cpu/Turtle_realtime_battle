extends Node
## verify_cyber_drone_passive.gd — 赛博龟被动【浮游炮】(2026-08-13)
##
## ★由来: 赛博的被动**一条门禁都没有** —— 现存两个只覆盖充能与侵入技。
##   而 2026-08-13 用户一次改了三处数值(弹伤拍平 3%→4% · 机甲生命/攻击/护甲全上调),
##   没有门禁 = 下次谁动一下没人知道。
##
## ★判据一律【从常量推导】, 不抄数字 —— 抄一次, 下次调数值就红一片
##   (092 毒蛾茧那次五条断言同时红, 全是当初把数字抄进测试造成的)。
##
## 跑法: <godot> --headless --path . res://tests/verify_cyber_drone_passive.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CyberSystem := preload("res://scripts/systems/skills/cyber_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 赛博龟被动: 浮游炮 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("cyber", "left", c + Vector2(-150, 0))
	u["atk"] = 100.0                     # 好算: 4% = 4
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(150, 0))
	e["maxHp"] = 1.0e7
	e["hp"] = 1.0e7
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false

	# ── ① 弹伤 = 赛博ATK × DRONE_SHOT_COEF (用户: 拍平成一层 4%) ─────────────
	##   ★这条是 2026-08-13 的改动本身: 原来是两层(炮攻=25%本体, 弹伤=12%炮攻 = 3%)。
	##     用户:「不再需要给每个浮游炮攻击力, 浮游炮的伤害直接等于赛博龟攻击力的4%」
	_ok("★分母: 浮游炮弹伤系数已登记为常量", CyberSystem.DRONE_SHOT_COEF > 0.0,
		"DRONE_SHOT_COEF=%.3f" % CyberSystem.DRONE_SHOT_COEF)
	_ok("★★弹伤系数 = 4%(不是两层叠出来的 3%)",
		absf(CyberSystem.DRONE_SHOT_COEF - 0.04) < 1e-6,
		"实得 %.4f" % CyberSystem.DRONE_SHOT_COEF)
	var src_rb: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★★开火处【引用常量】而不是写死数字(改一处就改到底)",
		src_rb.find("CyberSystem.DRONE_SHOT_COEF") >= 0)
	_ok("★反面: 旧的两层写法已经不在源码里(0.25 * 0.12)",
		src_rb.find("0.25 * 0.12") < 0)

	# ── ② 阵亡齐射: 每道贯穿激光 = 赛博ATK × VOLLEY_COEF ─────────────────────
	_ok("★齐射系数 = 0.4×ATK", absf(CyberSystem.VOLLEY_COEF - 0.4) < 1e-6,
		"实得 %.3f" % CyberSystem.VOLLEY_COEF)
	## 满编 20 门炮若最近敌是同一个 ⇒ 该目标最多吃 20×0.4 = 8×ATK(用户 2026-08-13 问的就是这个)
	_ok("★满编 20 炮打同一目标的理论上限 = 8×ATK",
		absf(20.0 * CyberSystem.VOLLEY_COEF - 8.0) < 1e-6,
		"20 × %.2f = %.2f" % [CyberSystem.VOLLEY_COEF, 20.0 * CyberSystem.VOLLEY_COEF])

	# ── ③ 生成: 每 2 秒 +1, 上限 20 ─────────────────────────────────────────
	u["drone_n"] = 0
	u["_ptimer"] = 0.0
	var n0: int = int(u.get("drone_n", 0))
	for _f in range(int(2.1 * 60.0)):
		s._sim_step(1.0 / 60.0, false, false)
	var n1: int = int(u.get("drone_n", 0))
	_ok("★分母: 起始 0 门炮", n0 == 0, "实得 %d" % n0)
	_ok("★★2 秒后 +1 门(不是不涨, 也不是一次涨一堆)", n1 == 1, "实得 %d" % n1)
	u["drone_n"] = 20
	u["_ptimer"] = 0.0
	for _f2 in range(int(2.1 * 60.0)):
		s._sim_step(1.0 / 60.0, false, false)
	_ok("★★上限 20 —— 满了不再涨", int(u.get("drone_n", 0)) == 20,
		"实得 %d" % int(u.get("drone_n", 0)))

	# ── ④ 机甲属性公式(用户 2026-08-13 上调) ────────────────────────────────
	##   ★判据从源码常量读, 而不是抄一份数字放这儿 —— 抄了就等于两份事实源。
	var src_cy: String = FileAccess.get_file_as_string("res://scripts/systems/skills/cyber_system.gd")
	_ok("★★机甲生命 = (100 + 2×等级) × 炮数",
		## ★比【常量的值】不比源码里的字面串 —— 2026-08-22 文案根除把它们提成了具名常量,
		## 比字面串等于把写法焊死(挡的是正常重构), 比值才是在挡数值被改。
		is_equal_approx(CyberSystem.MECH_HP_BASE, 100.0) and is_equal_approx(CyberSystem.MECH_HP_PER_LV, 2.0))
	_ok("★★机甲攻击 = (8 + 0.1×等级) × 炮数",
		is_equal_approx(CyberSystem.MECH_ATK_BASE, 8.0) and is_equal_approx(CyberSystem.MECH_ATK_PER_LV, 0.1))
	_ok("★★机甲护甲魔抗 = 110 + 2×等级(【不吃】炮数 —— 用户定的口径)",
		is_equal_approx(CyberSystem.MECH_DEF_BASE, 110.0) and is_equal_approx(CyberSystem.MECH_DEF_PER_LV, 2.0))
	_ok("★组装期【不可被索敌】(用户 2026-08-13 指出: 所以那 5 秒不承担风险)",
		src_cy.find("untargetable_until") >= 0)

	# ── ⑤ 选靶闸: 浮游炮开火【不能】选到训龟大师/围栏内的蛋 ──────────────────
	##   ★浮游炮是"对随机敌人射一发" = 单体指向 ⇒ 必须走 _pick_enemies_of(§PICK-TARGET)。
	##     阵亡贯穿激光走 _enemies_of 是对的 —— 那是直线扫过的 AOE。
	_ok("★★浮游炮开火走【单体指向闸】_pick_enemies_of",
		src_rb.find("var es := _targeting._pick_enemies_of(u)") >= 0)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 赛博龟被动: 浮游炮")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
