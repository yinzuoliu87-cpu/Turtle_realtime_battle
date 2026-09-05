extends Node
## verify_hourglass_values.gd — 059 沙漏的三个逐星数值（定格时长 / 龟能倍率 / 瞬间龟能）
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：这三个值以前**零门禁覆盖**
## ══════════════════════════════════════════════════════════════════
## 2026-09-06 用户要改沙漏三项，我改完一扫 `tests/` ——
## 全仓只有 `verify_uncovered_equips.gd:278` 验了「星级识别」，
## **定格时长 / 充能倍率 / 瞬间龟能 一条断言都没有**。
## 也就是说这三个数以前谁改都不会红。本文件补上。
##
## ══════════════════════════════════════════════════════════════════
##  ★★判据落在【产品跑出来的状态】，不引产品常量
## ══════════════════════════════════════════════════════════════════
## 期望值在本文件里**写死用户 2026-09-06 拍板的数**：
##   定格 4/7/20 秒 · 充能倍率 1.5/2/3 · 瞬间龟能 40/150/300
## 引 `TimestopSystem.TS_DUR` 之类就是拿被测对象证明自己（恒真式）。
##
## ★走真入口 `_ts_fire()`（`_ts_update_trigger` 在第 10 秒后触发它），
##   不直接读常量 —— 常量对不对不重要，**玩家吃到的秒数和龟能对不对**才重要。
##
## ★分母：① 时停真的进了（`_ts_active` 非空）② 三档读回来的值**互不相同**
##   （否则「按星级生效」是恒真的 —— 全星同值也能过）。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 用户 2026-09-06 逐字：「沙漏的定格时间调整为4/7/20秒，
## 在开始时停时立刻获得40/150/300龟能，额外龟能充能速率改为1.5/2/3倍」
const WANT_DUR := [4.0, 7.0, 20.0]
const WANT_ECHARGE := [1.5, 2.0, 3.0]
const WANT_INSTANT := [40.0, 150.0, 300.0]

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


func _mk(star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("fortune", "left", c + Vector2(-200, 0))
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	## ★**不能清空 active_skills** —— `_has_energy_system()` 的判据就是"它非空"
	##   (`RealtimeBattle3DScene.gd:5428`)，清空了 `_eq_grant_energy` 那一整段直接被跳过，
	##   瞬间龟能读回来永远是 0 —— 判据没错，是**被测对象不在场**
	##   (memory [[fb-gate-subject-never-constructed]])。留着它自带的技能。
	u["skill_cd"] = {}
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	u["equips"] = [{"id": "p2eq_059", "star": star}]
	_s._units.append(u)
	return u


## 冷却总和 —— 龟能被 `_apply_energy_bank` 吸走时冷却会变小，
## 所以"拿到多少龟能" = 银行增量 + **冷却减少量**。取负号让它和银行同向相加。
func _cd_sum(u: Dictionary) -> float:
	var t := 0.0
	for k in (u.get("skill_cd", {}) as Dictionary):
		t += float((u["skill_cd"] as Dictionary)[k])
	return -t


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 059 沙漏三项逐星数值（用户 2026-09-06）===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var got_dur: Array = []
	var got_ech: Array = []
	var got_ins: Array = []

	for star in [1, 2, 3]:
		var si: int = star - 1
		# ── 每档一场干净的局 ──
		_s._units.clear()
		var ts = _s._timestop
		ts._ts_fired = false
		ts._ts_active = []
		ts._ts_charging = false
		ts._ts_charge_casters = []
		ts._ts_remaining = 0.0
		var u: Dictionary = _mk(star)
		## ★龟能给进来后 `_apply_energy_bank()` 会把它**吸进技能冷却**，
		##   所以只读 `energy_bank` 会漏掉被吸走的那部分 ⇒ 量【银行 + 冷却减少量】的总和。
		var e0: float = float(u.get("energy_bank", 0.0)) + _cd_sum(u)

		## ★走真入口：`_ts_update_trigger` 会挑最高星、进蓄力、蓄力满调 `_ts_fire`
		_s._t = 999.0                       # 越过 TS_START_T
		ts._ts_update_trigger(0.016)        # → 进蓄力
		ts._ts_update_trigger(10.0)         # → 蓄力满 → _ts_fire()

		_ok("★分母[%d★]: 时停真的进了(_ts_active 非空)" % star,
			not (ts._ts_active as Array).is_empty(),
			"没进时停 ⇒ 下面三条全是空检查")

		var dur: float = float(ts._ts_remaining)
		var ech: float = float(u.get("_ts_echarge", -1.0))
		var ins: float = (float(u.get("energy_bank", 0.0)) + _cd_sum(u)) - e0
		got_dur.append(dur)
		got_ech.append(ech)
		got_ins.append(ins)

		_ok("① %d★ 定格时长 = %.0f 秒" % [star, WANT_DUR[si]],
			is_equal_approx(dur, WANT_DUR[si]), "实测 %.2f" % dur)
		_ok("② %d★ 时停期间龟能充能倍率 = %.1f" % [star, WANT_ECHARGE[si]],
			is_equal_approx(ech, WANT_ECHARGE[si]), "实测 %.3f" % ech)
		_ok("③ %d★ 定格瞬间立即获得龟能 = %.0f" % [star, WANT_INSTANT[si]],
			absf(ins - WANT_INSTANT[si]) < 0.51, "实测 %.2f" % ins)

	# ── ④ 分母：三档必须互不相同，否则「按星级生效」是恒真的 ──
	print("── ④ ★分母: 三档互不相同(全星同值也能过 ⇒ 上面就白验了) ──")
	for row in [["定格时长", got_dur], ["充能倍率", got_ech], ["瞬间龟能", got_ins]]:
		var seen := {}
		for v in (row[1] as Array):
			seen[snappedf(float(v), 0.001)] = true
		_ok("④ %s 三档读回 %d 种不同值" % [str(row[0]), seen.size()],
			seen.size() == 3,
			"只有 %d 种 —— 三档取的是同一个下标？(%s)" % [seen.size(), str(row[1])])

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
