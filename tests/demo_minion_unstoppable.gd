extends Node
## demo_minion_unstoppable.gd — 【验收场景 A9/A10/A11】近战小将·不可阻挡 + 目标免控分支
##
## 用户 2026-08-20 拍板:
##   ·「在释放技能时会给自己不可阻挡的状态…跳起来放完技能完成最后的跳出动作后解除」
##   · 按 LoL 奥拉夫 R 那一档:「免所有硬控」+「免推开，推开不就是控制技能吗」
##   ·「如果这个技能的目标免疫控制则…直接造成10%最大生命值加1.5ATK物理伤害而不会把自己拉向对方」
##   ·「途中目标免疫则中断伤害并跳回地面」
##
## 怎么跑:  <godot> --path . res://tests/demo_minion_unstoppable.tscn
##   MU_CASE=1  普通目标 —— 看完整的人体浪板(拉过去 + 踩滑), 且施法期间被眩晕【打不断】
##   MU_CASE=2  免控目标 —— 看它【原地结算不拉过去】(默认)
##   MU_CASE=3  ★途中变免控 —— 小将跳到空中了才给目标加免控 ⇒ 中断伤害并落地
##   MU_SECS=60
##
## 配置表(逐条写死):
##   · 我方 1 只近战小将: 龟能给满 ⇒ 一进场就放技, 不用等
##   · 敌方目标 1 个: 锁血 4000 不还手不移动
##       CASE 2 时给它**永久免控** ⇒ 触发免控分支
##   · 敌方【干扰者】1 个: 每 1.2 秒对小将丢一次眩晕 ⇒ 看"不可阻挡"是不是真的挡住了
##   · 相机拉近
##
## ★为什么要一个专门丢眩晕的干扰者: 不可阻挡这件事**看不见** —— 只有"被控了却没被打断"
##   才能证明它生效。没有干扰者就等于什么都没验(memory: 判据没错但被测对象不在场)。

var _scn = null
var _t0 := 0.0
var _mn: Dictionary = {}
var _tgt: Dictionary = {}
var _next_stun := 0.0
var _stun_n := 0
var _blocked_n := 0
## -- A10/A11 的账(都量产品自己的数, 不数我插的标记) --
var _min_dist := 1e9        # 全程小将离目标最近到过多少码(被拉过去就会接近 0)
var _start_dist := 0.0
var _hp_drops: Array = []   # 每次目标掉血: [掉了多少, 掉的那一刻小将离目标多远]
var _last_hp := 0.0
var _a11_armed := false     # 用例3: 已在空中把目标改成免控
var _a11_open := false      # 加免控之后、小将落地之前的窗口
var _a11_worst := 0.0       # 该窗口内目标吃到的最大一次掉血
var _cast_t0 := -1.0        # 本次施法开始时的【战斗时钟】
var _a10_open := false      # 免控分支已出伤、小将还没落地的窗口
var _a10_min := 1e9         # 该窗口内小将离目标最近到过多少码
var _exp_ib := 0.0
var _case := 2
var _fail := 0


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if cond else "FAIL", nm, detail])


func _ready() -> void:
	await get_tree().process_frame
	## ★★验收场景一律强制 `test_mode` —— **窗口模式下它默认是 false, 会写真存档**
	##   (headless 才自动开; 见 `GameState.gd:912`)。2026-08-21 我跑了一次带窗口的 demo,
	##   往 `match_history` 写进一条对局记录, `verify_ui_consistency` 当场红。
	##   铁律: 测试/演示不许污染玩家存档。
	## ★★验收场景【不判胜负】—— `NOVERDICT` 走的是 `_check_end` 里那道守卫。
	##   由来(2026-08-21 用户实拍截图): `demo_spirit_stacks` 阶段①要"场上一个敌人都没有"
	##   才演得出"射程内没敌人就只攒不放", 结果正好撞上「敌方全灭 = 胜利」⇒
	##   演到一半弹出「胜利」结算屏把画面全盖住了。
	## ⚠ 不借 `VFXPREVIEW`: 那个开关会连带开一整套技能预览并改相机 fov(battle_vfx.gd:603)。
	## ⚠ 也不新增成员变量: 上帝文件有行数预算(`tools/arch_budget.py`), 改已有那行守卫净增 0 行。
	OS.set_environment("NOVERDICT", "1")
	var _gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_gs.test_mode = true
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame

	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	var cx: float = _scn.ARENA.position.x + _scn.ARENA.size.x * 0.5
	var cy: float = _scn.ARENA.position.y + _scn.ARENA.size.y * 0.5
	var case_i: int = int(OS.get_environment("MU_CASE")) if OS.has_environment("MU_CASE") else 2
	_case = case_i

	_mn = _scn._spawn._make_unit("__minion__", "left", Vector2(cx - 380.0, cy),
		{"minion": true, "role": "front"})
	_mn["deathfloor_until"] = 999999.0
	_mn["energy"] = 999.0
	## ★暴击必须钉成 0 —— `_resolve_dmg` 会掷暴击, 不钉的话期望值在两个数之间来回跳。
	##   (触手门禁上栽过两次: 期望 460/690 反复横跳。)
	_mn["crit"] = 0.0
	_scn._units.append(_mn)

	_tgt = _scn._spawn._make_unit("basic", "right", Vector2(cx + 60.0, cy))
	_tgt["no_move"] = true
	_tgt["no_basic"] = true
	_tgt["move_spd"] = 0.0
	_tgt["active_skills"] = []
	_tgt["base_def"] = 0.0
	_tgt["base_mr"] = 0.0
	_scn._recalc_stats(_tgt)
	_tgt["maxHp"] = 4000.0
	_tgt["hp"] = 4000.0
	_tgt["deathfloor_until"] = 999999.0
	if case_i == 2:
		_tgt["cc_immune_until"] = 1e9        # 永久免控 ⇒ 触发免控分支
	## 用例3 开局**不**免控 —— 要等小将跳起来了才现加(见 _process)
	_scn._units.append(_tgt)

	# 干扰者: 站远处, 只负责每隔一会儿对小将丢眩晕
	var jam: Dictionary = _scn._spawn._make_unit("basic", "right", Vector2(cx + 300.0, cy - 160.0))
	jam["no_move"] = true
	jam["no_basic"] = true
	jam["move_spd"] = 0.0
	jam["active_skills"] = []
	jam["deathfloor_until"] = 999999.0
	_scn._units.append(jam)

	if _scn._cam != null and is_instance_valid(_scn._cam):
		_scn._cam.fov = 32.0

	print("=== 【验收场景】近战小将·不可阻挡 / 目标免控分支 ===")
	print("  用例 %d: %s" % [case_i, "普通目标(看完整浪板)" if case_i == 1 else "★目标免控(看原地结算·不拉过去)"])
	print("  ★分母自证: 目标 cc_immune_until = %.0f (用例2 该是个很大的数)"
		% float(_tgt.get("cc_immune_until", 0.0)))
	print("  干扰者每 1.2 秒对小将丢一次眩晕 —— 施法期间【应当被挡下】。")
	_start_dist = Vector2(_mn["pos"]).distance_to(Vector2(_tgt["pos"]))
	_last_hp = float(_tgt.get("hp", 0.0))
	var hs = _scn._hiding_sys
	var pct: float = float(hs.IMMUNE_BRANCH_MAXHP_PCT)
	var coef: float = float(hs.IMMUNE_BRANCH_ATK_COEF)
	_exp_ib = float(_tgt.get("maxHp", 0.0)) * pct + float(_mn.get("atk", 0.0)) * coef
	## ★期望值用**产品自己的常量**算出来当对照 —— 手抄一个 400 进来, 常量一改就成了假对照。
	print("  ★分母自证: 起始距离 %.0f 码 · 免控分支期望伤害 = %.0f%%x%.0f + %.1fxATK(%.0f) = %.0f"
		% [_start_dist, pct * 100.0, float(_tgt.get("maxHp", 0.0)), coef,
			float(_mn.get("atk", 0.0)), _exp_ib])
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	set_process(true)


func _process(_dt: float) -> void:
	if _scn == null or not is_instance_valid(_scn):
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	## ★★第一版我搞砸了: 每 1.2 秒无条件丢眩晕 ⇒ 小将被控着**根本起不了手**,
	##   技能一次都没放, "不可阻挡"永远 false —— 等于什么都没验。
	##   ⇒ 开场先丢**一次**作对照(证明不在施法时眩晕真会生效), 之后**只在它施法期间**丢。
	var casting: bool = bool(_mn.get("_unstoppable", false))
	if _stun_n >= 1 and not casting:
		_next_stun = now + 0.15         # 没在施法就先别丢, 让它起手
	if now >= _next_stun:
		_next_stun = now + (1.2 if _stun_n == 0 else 0.35)
		var before: float = float(_mn.get("stun_until", 0.0))
		_scn._damage._stun(_mn, 2.0, "demo_jam", true)
		_stun_n += 1
		var after: float = float(_mn.get("stun_until", 0.0))
		var blocked: bool = after <= before
		if blocked:
			_blocked_n += 1
		print("  [眩晕#%d] %s   (不可阻挡=%s · 高度=%.2f)"
			% [_stun_n, "★被挡下(施法中·不可阻挡)" if blocked else "生效了(此刻没在施法·对照组)",
				str(bool(_mn.get("_unstoppable", false))), float(_mn.get("height", 0.0))])
	## ══ A10/A11 的记账: 放在【事件发生处且无条件】, 不采样猜 ══
	## ★★回读外部状态一律 null 安全: 实测这两个 dict 有几帧没有 `pos` 键,
	##   直接下标会抛 "Invalid access to key" —— 而那**会让 `_process` 当场中止**,
	##   下面 A10/A11 的记账那几帧被**静默跳过**, 自证却照样打绿。
	##   (memory [[fb-null-readback-makes-test-silently-abort]] 那一族。)
	if not (_mn.has("pos") and _tgt.has("pos")):
		return
	var dist: float = Vector2(_mn["pos"]).distance_to(Vector2(_tgt["pos"]))
	_min_dist = minf(_min_dist, dist)
	var hp_now: float = float(_tgt.get("hp", 0.0))
	if hp_now < _last_hp - 0.5:
		_hp_drops.append([_last_hp - hp_now, dist, float(_mn.get("height", 0.0))])
		## ★A11 的真判据: 「中断伤害」—— 加了免控之后到落地之前, 目标不许再吃这一击。
		##   普攻(实测 42)不算, 所以只看"大额"掉血。
		if _a11_open:
			_a11_worst = maxf(_a11_worst, _last_hp - hp_now)
		## ★A10「不会把自己拉向对方」要看**这一击之后**有没有贴上去 ——
		##   拉回发生在射链命中后 0.6 秒(0.68→1.28), 只量"出伤那一刻的距离"根本看不到它。
		##   (反向验证时发现的: 把 abort 拆掉, 那条判据照样绿 = 空判据。)
		if _case == 2 and absf((_last_hp - hp_now) - _exp_ib) <= maxf(2.0, _exp_ib * 0.02):
			_a10_open = true
			_a10_min = 1e9
		print("  [目标掉血] %.0f   (此刻小将离目标 %.0f 码 · 高度 %.2f)"
			% [_last_hp - hp_now, dist, float(_mn.get("height", 0.0))])
	_last_hp = hp_now
	## 用例3(A11): 等小将真的跳到空中了, 才把目标改成免控 ⇒ 途中变免控该【中断伤害并落地】
	## ★★用例3(A11) 的加免控时机必须【卡在绳索命中之后、拉回完成之前】。
	##   技能的时间轴(`hiding_system` 的 `_pending_shots`): 0.68s 射链命中 → 1.28s 拉己俯冲。
	##   · 免控发生在 **0.68 之前** ⇒ 走的是 **A10** 分支(463 伤害 + 不拉过去) —— 那是对的行为;
	##     我第一版按"高度 > 2.0"加免控, 实测在 0.68 之前就触发了, 于是量到 463 判成 FAIL,
	##     **判据没错、用例错了**。
	##   · 免控发生在 **0.68~1.28 之间** 才是用户说的「途中目标免疫则中断伤害并跳回地面」。
	## ★用【战斗时钟】不用墙钟: `_pending_shots` 走的是钳制后的 sim delta(CLAUDE.md §3.5)。
	if _case == 3:
		if casting and _cast_t0 < 0.0:
			_cast_t0 = float(_scn._t)
		elif not casting and not _a11_armed:
			_cast_t0 = -1.0
		if not _a11_armed and _cast_t0 >= 0.0 and float(_scn._t) - _cast_t0 >= 0.90:
			_a11_armed = true
			_tgt["cc_immune_until"] = 1e9
			_a11_open = true
			print("  ▼ 施法后 %.2f 秒(绳索已命中·尚未拉回)给目标加免控 —— 高度 %.2f"
				% [float(_scn._t) - _cast_t0, float(_mn.get("height", 0.0))])

	## 窗口在小将落地时关闭 —— 之后它还会再放技能, 那时目标已经是"开局就免控"的 A10 情形。
	if _a11_open and float(_mn.get("height", 0.0)) < 0.5 and not casting:
		_a11_open = false
	## A10 窗口: 出伤 → 落地。落地后小将会走上去普攻(贴到 99 码), 那不算被拉。
	if _a10_open:
		_a10_min = minf(_a10_min, dist)
		if float(_mn.get("height", 0.0)) < 0.5 and not casting:
			_a10_open = false

	var el: float = now - _t0
	var want: float = float(int(OS.get_environment("MU_SECS"))) if OS.has_environment("MU_SECS") else 60.0
	if el >= want:
		print("")
		print("  ── 收尾自证 ──")
		print("  A9  不可阻挡: 丢了 %d 次眩晕, %d 次被挡下" % [_stun_n, _blocked_n])
		_ok("A9 分母: 施法期间真的丢过眩晕(否则这条是空的)", _stun_n >= 2, "只丢了 %d 次" % _stun_n)
		_ok("A9 施法期间的眩晕【全被挡下】", _blocked_n >= _stun_n - 1,
			"%d/%d" % [_blocked_n, _stun_n])
		print("  起始距离 %.0f 码 · 全程最近到过 %.0f 码 · 目标共掉血 %d 次"
			% [_start_dist, _min_dist, _hp_drops.size()])
		if _case == 2:
			## ★★判据必须卡在【那一击自己发生的时刻】, 不能看全程最近距离 ——
			##   小将平时会走上去**普攻**(实测贴到 99 码), 全程最近距离当然小,
			##   拿它判"有没有被拉过去"会把正常普攻误报成失败。
			##   (memory [[fb-judge-must-fit-the-shape]]: 判据要刚好卡住那个形状。)
			## ⇒ 找出"伤害 == 免控分支期望值"的那一击, 看**它发生时**小将在哪。
			var found: Array = []
			for d in _hp_drops:
				if absf(float(d[0]) - _exp_ib) <= maxf(2.0, _exp_ib * 0.02):
					found.append(d)
			_ok("A10 有一击 == 免控分支期望值 %.0f (10%%最大生命 + 1.5ATK)" % _exp_ib,
				not found.is_empty(),
				"实测掉血清单 %s" % str(_hp_drops.map(func(x): return int(x[0]))))
			if not found.is_empty():
				var far_ok := false
				var air_ok := false
				for d2 in found:
					if float(d2[1]) > 150.0:
						far_ok = true
					if float(d2[2]) > 2.0:
						air_ok = true
				_ok("A10 那一击发生时小将【离目标还很远】(>150 码 = 没被拉过去)", far_ok,
					"实测 %.0f 码" % float((found[0] as Array)[1]))
				_ok("A10 这一击【之后到落地之前】也没贴上去(>150 码 = 真的没被拉)",
					_a10_min > 150.0, "窗口内最近 %.0f 码" % _a10_min)
				_ok("A10 那一击发生时小将【还在空中】(证明是技能不是普攻)", air_ok,
					"高度 %.2f" % float((found[0] as Array)[2]))
		elif _case == 3:
			_ok("A11 分母: 真的在空中给目标加过免控", _a11_armed)
			_ok("A11 小将【落回地面】(高度 ≈ 0)", float(_mn.get("height", 0.0)) < 0.5,
				"高度 %.2f" % float(_mn.get("height", 0.0)))
			## ★这条才是需求原话「途中目标免疫则【中断伤害】并跳回地面」的前半句。
			##   只断言"落地了"守不住它 —— 伤害照打也能落地。
			_ok("A11 加免控之后到落地之前【没再吃到这一击的伤害】(普攻 42 不算)",
				_a11_worst < 100.0, "窗口内最大一次掉血 %.0f" % _a11_worst)
		print("  结论: %s" % ("全部通过" if _fail == 0 else "★有 %d 条不达标" % _fail))
		print("DEMO DONE")
		get_tree().quit(0)
