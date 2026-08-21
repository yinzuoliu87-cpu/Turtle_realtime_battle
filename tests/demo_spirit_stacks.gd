extends Node
## demo_spirit_stacks.gd — 【验收场景 A3/A5】灵物羁绊·拍击层数的攒与消费
##
## 用户 2026-08-20 原话:
##   「2件的时候改为触手在每5秒的时候获得一层拍击层数。触手空闲时会消耗这个拍击层数
##     来进行一次拍击，动作结束后就继续消耗。」
##   「如果射程内没敌人也不应该消耗层数吧」(⇒ A3)
##   「无上限，除了搬家和拍击应该就算空闲？」(⇒ A5: 搬家期间不算空闲, 不消费)
##
## 用户 2026-08-21:「验收也是我一个个验收，需要你提前配置好所有需要的演出场景」
## ⇒ 本场景【开箱即用】, 启动就能看, 三个阶段自动演完:
##
##   | 阶段 | 场面 | 你该看到 |
##   |---|---|---|
##   | ① 攒 | **场上一个敌人都没有** | 层数**一路涨**、触手一次不拍 |
##   | ② 搬家 | 假人出现在**很远处** ⇒ 触手钻地搬过去 | 搬家全程层数**一格不掉**(带着层搬) |
##   | ③ 放 | 假人瞬移到触手身边 | 层数**连续掉**、触手一拍接一拍 |
##
## ★为什么②要"远处有敌人"而不是"没有敌人": 实测**没有敌人时触手根本不搬家**
##   (没地方可搬) ⇒ A5 会验不到。收尾自证里那条「搬家出现过」就是防这个空过的。
##
## 怎么跑:
##   <godot> --path . res://tests/demo_spirit_stacks.tscn
##   STK_PHASE1=13  没有敌人攒多少秒(默认 13 ⇒ 攒到 2 层)
##   STK_PHASE2=10  远处有敌人(逼它搬家)多少秒
##   STK_SECS=34    总时长
##
## ★屏幕左上角有实时读数(层数/触手状态/射程内有无敌人), 不用盯控制台。
## ★★★为什么阶段①是"一个敌人都没有"而不是"把假人放到射程外"(我第一版就是那么写的):
##   **放远根本挡不住** —— 触手的「转移阵地」机制就是"连续 1 秒射程内没敌人就往有敌人的
##   地方搬"。探针实测: t=3 触手钻地搬家, t=4「射程内=true」, 之后每 5 秒产一层、
##   **同一帧就消费掉**, 逐帧采样永远读到 0 层 —— 看着像"层数机制没生效", 其实是场景配错了。
##   (memory [[fb-gate-subject-never-constructed]]: 判据没错, 被测对象不在那个状态。)
##
## ★★为什么要专门做这个场景: 门禁 `verify_synergy_rest5` 只能证明"数字对",
##   证明不了"**看得出来**在攒、在搬家时没掉" —— 那是人眼的事。

## 灵物装备 id(与 demo_spirit_slap 同一份, 取前 2 件 = 1 档)
const SPIRIT_IDS := ["p2eq_032", "p2eq_025"]
## 触手状态枚举(与 tentacle_vfx.gd 的 enum 同序)
const ST_NAME := ["出土", "待机", "蓄势", "拍下", "起身", "搬家(钻地)", "预警"]

var _scn = null
var _t0 := 0.0
var _lab: Label = null
var _phase := 1
var _last_stack := -1
var _reloc_seen := false
var _bad_state_drop := 0
var _prev_state := -1
var _out_of_range_drop := 0
var _slams := 0
var _dummies: Array = []
var _far_pos: Array = []
var _near_pos: Array = []


func _env_f(k: String, d: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else d


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame

	# 场上清干净: 只留我们自己配的单位
	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	var cx: float = _scn.ARENA.position.x + _scn.ARENA.size.x * 0.5
	var cy: float = _scn.ARENA.position.y + _scn.ARENA.size.y * 0.5

	# ── 我方携带者: 站桩·不攻击·不死 ⇒ 场上唯一的变量就是层数 ──
	var carrier: Dictionary = _scn._spawn._make_unit("basic", "left", Vector2(cx - 320.0, cy))
	carrier["no_move"] = true
	carrier["no_basic"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["deathfloor_until"] = 999999.0
	var eqs: Array = []
	for i in range(SPIRIT_IDS.size()):
		eqs.append({"id": SPIRIT_IDS[i], "star": 1})
	carrier["equips"] = eqs
	_scn._units.append(carrier)

	## ★假人一律相对【触手根部】摆 —— 根部不在携带者身上(在场地宽 18% 处)。
	##   按携带者摆会全摆错(demo_spirit_slap 的注释里记过这个坑)。
	var root: Vector2 = _scn._tentacle_vfx.default_root("left", 0)
	var rng: float = float(_scn._tentacle_vfx.attack_range_2d)
	for i in range(2):
		var far: Vector2 = Vector2(root.x + rng + 500.0, root.y - 90.0 + 180.0 * float(i))
		var near: Vector2 = Vector2(root.x + 220.0 + 130.0 * float(i), root.y)
		var d: Dictionary = _scn._spawn._make_unit("basic", "right", far)
		d["no_move"] = true
		d["no_basic"] = true
		d["move_spd"] = 0.0
		d["active_skills"] = []
		d["base_def"] = 0.0
		d["base_mr"] = 0.0
		_scn._recalc_stats(d)
		d["maxHp"] = 900000.0
		d["hp"] = 900000.0
		d["deathfloor_until"] = 999999.0
		## ★阶段①**不**把假人放进场 —— 场上有敌人触手就会搬过去(见文件头长注)。
		##   先造好放兜里, 阶段②再入场。
		_dummies.append(d)
		_far_pos.append(far)
		_near_pos.append(near)

	## ★★档位必须重算 —— 装备是 `_make_unit` 之后才塞进去的, 不重算档位是 0,
	##   触手压根不登场(demo_spirit_slap 第一版就栽在这)。
	## ★★必须先 `clear()` 再 `apply_all()` —— `apply_all` 里有一道 `is_empty()` 守卫,
	##   缓存非空就**不重算**。战斗启动时已按默认队算过一次 ⇒ 我换掉的阵容会被忽略。
	##   实测症状: 敌方档位 = 0、右边那条触手压根不出现(A6 场景第一版就栽在这)。
	##   左边"碰巧"能用只是因为默认左队没羁绊、缓存正好是空的 —— 那是运气不是正确。
	##   正规顺序见 `dual_lane_flow.gd:540`(换路时就是 clear + apply_all)。
	_scn._synergy.clear()
	_scn._synergy.apply_all()
	var tier: int = _scn._spirit_syn._side_tier("left")
	print("  ★分母自证: 重算后我方灵物档位 = %d (0 就是没配上, 下面什么都不会发生)" % tier)
	print("  ★分母自证: 触手射程 = %.0f 码; 阶段①场上敌人数 = %d (必须是 0, 否则触手会搬过去)"
		% [rng, _n_foes()])

	_mk_hud()
	print("=== 【验收场景 A3/A5】拍击层数: 攒 → 搬家不掉 → 进射程连放 ===")
	print("  ① 前 %.0f 秒: 场上没有敌人 ⇒ 层数只涨不掉、触手一次不拍"
		% _env_f("STK_PHASE1", 13.0))
	print("  ② 中段假人在【很远处】入场 ⇒ 触手带着层数钻地搬家, 搬家全程层数不许掉")
	print("  ③ 之后假人瞬移到触手身边 ⇒ 层数连续掉、触手一拍接一拍")
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0


## 场上还活着的敌人数 —— 分母用: 阶段①必须是 0。
func _n_foes() -> int:
	var n := 0
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "right" and u.get("alive", false):
			n += 1
	return n


func _mk_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90
	add_child(cl)
	var pan := PanelContainer.new()
	pan.position = Vector2(14, 12)
	cl.add_child(pan)
	_lab = Label.new()
	_lab.add_theme_font_size_override("font_size", 19)
	pan.add_child(_lab)


func _process(_dt: float) -> void:
	if _scn == null or _lab == null:
		return
	var el: float = float(Time.get_ticks_msec()) / 1000.0 - _t0
	var p1: float = _env_f("STK_PHASE1", 13.0)

	# ── 阶段切换 ──
	if _phase == 1 and el >= p1:
		_phase = 2
		## ②【逼它搬家】: 假人入场但放在**很远**处 ⇒ 触手连续 1 秒够不着就钻地搬过去。
		##   此刻手上已经攒了 2 层 ⇒ 正好验"带着层数搬家, 一格不掉"。
		for i in range(_dummies.size()):
			var d2: Dictionary = _dummies[i]
			d2["pos"] = _far_pos[i]
			_scn._units.append(d2)
		print("")
		print("  ▼ %.1fs 假人在【很远处】入场 —— 触手会钻地搬过去; 搬家全程层数不许掉" % el)
	elif _phase == 2 and el >= p1 + _env_f("STK_PHASE2", 10.0):
		_phase = 3
		## ③ 摆到触手【当前】根部旁 —— 不是 default_root, 它已经搬过家了。
		var rnow: Vector2 = _scn._tentacle_vfx.root_pos("left", 0)
		for i in range(_dummies.size()):
			(_dummies[i] as Dictionary)["pos"] = Vector2(
				rnow.x + 200.0 + 120.0 * float(i), rnow.y)
		print("")
		print("  ▼ %.1fs 假人瞬移到触手身边 —— 从这里开始层数应该一拍一拍地被消费" % el)

	var stk: int = int(_scn._spirit_syn.stack_of("left", 0))
	var st: int = int(_scn._tentacle_vfx.state_of("left", 0))
	var in_rng: bool = bool(_scn._spirit_syn._foe_in_range("left", 0))

	# ── 记账: 放在【事件发生处且无条件】, 不靠采样猜(CLAUDE.md §7) ──
	## ★★判据必须看【掉层那一刻的**前一帧**状态】, 不能看当帧 ——
	##   合法消费会立刻 `strike()` 把状态推成"预警", 拿当帧判会把**每一次正常拍击**
	##   都报成违规。(反向验证时发现的: 好的那一版实测"层数 3→2 触手=预警"。)
	if _last_stack >= 0 and stk < _last_stack:
		if _prev_state >= 0 and _prev_state != 1:
			_bad_state_drop += 1          # 非待机(出土/拍击/起身/搬家)却掉层 = 违反
		if not in_rng:
			_out_of_range_drop += 1       # 射程内没敌人却掉层 = A3 违反
	if st == 5:
		_reloc_seen = true
	if st == 3 and _last_stack >= 0 and stk < _last_stack:
		_slams += 1
	if _last_stack >= 0 and stk != _last_stack:
		print("    %5.1fs  层数 %d → %d   触手=%s   射程内有敌人=%s"
			% [el, _last_stack, stk, ST_NAME[clampi(st, 0, 6)], "是" if in_rng else "否"])
	## [临时探针] 每秒无条件打一次, 别靠有变化才打去猜
	if int(el) != int(el - _dt) and OS.has_environment("STK_PROBE"):
		print("    [探针] %4.1fs 层数=%d 状态=%d 射程内=%s tier=%d 敌人数=%d _t_slap=%.2f" % [
			el, stk, st, in_rng, _scn._spirit_syn._side_tier("left"),
			_n_foes(),
			float(_scn._spirit_syn._t_slap)])
	_last_stack = stk
	_prev_state = st

	_lab.text = ("【A3/A5 拍击层数】%.1fs\n阶段 %s\n层数 %d\n触手 %s\n射程内有敌人 %s\n"
		+ "—— 自证 ——\n搬家出现过 %s\n搬家中掉层 %d 次(应为 0)\n射程外掉层 %d 次(应为 0)") % [
		el, ["", "①攒(场上没有敌人)", "②搬家(敌人在远处)", "③放(敌人在身边)"][clampi(_phase, 1, 3)],
		stk, ST_NAME[clampi(st, 0, 6)], "是" if in_rng else "否",
		"是" if _reloc_seen else "还没", _bad_state_drop, _out_of_range_drop]

	if el >= _env_f("STK_SECS", 34.0):
		print("")
		print("  ── 收尾自证 ──")
		print("  搬家出现过: %s" % ("是" if _reloc_seen else "★否 —— 没看到搬家, A5 这次没验到"))
		print("  非待机时掉层 %d 次(应为 0) · 射程内没敌人却掉层 %d 次(应为 0)"
			% [_bad_state_drop, _out_of_range_drop])
		## ★★诚实记录一条【我验不到的】: 「搬家期间不消费」是**结构性保证**, 不是这里验出来的。
		##   搬家的前提是"射程内没敌人", 而消费要求"射程内有敌人" —— 两个条件**互斥**,
		##   所以我把守卫改成"搬家也允许消费"做反向验证时**根本不会红**(实测过, 空判据)。
		##   守卫真正在守的是【出土/拍击/起身】期间不消费 —— 那个反向验证会红
		##   (拆掉守卫后实测: 出土期间 0.1 秒内连烧 2 层)。上面那条计数守的就是它。
		print("DEMO DONE")
		get_tree().quit(0)
