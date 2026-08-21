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
##   MU_CASE=2  免控目标 —— 看它【原地结算不拉过去】(默认轮流演)
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


func _ready() -> void:
	await get_tree().process_frame
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

	_mn = _scn._spawn._make_unit("__minion__", "left", Vector2(cx - 380.0, cy),
		{"minion": true, "role": "front"})
	_mn["deathfloor_until"] = 999999.0
	_mn["energy"] = 999.0
	_scn._units.append(_mn)

	_tgt = _scn._spawn._make_unit("basic", "right", Vector2(cx + 60.0, cy))
	_tgt["no_move"] = true
	_tgt["no_basic"] = true
	_tgt["move_spd"] = 0.0
	_tgt["active_skills"] = []
	_tgt["maxHp"] = 4000.0
	_tgt["hp"] = 4000.0
	_tgt["deathfloor_until"] = 999999.0
	if case_i == 2:
		_tgt["cc_immune_until"] = 1e9        # 永久免控 ⇒ 触发免控分支
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
	var el: float = now - _t0
	var want: float = float(int(OS.get_environment("MU_SECS"))) if OS.has_environment("MU_SECS") else 60.0
	if el >= want:
		print("")
		print("  合计丢了 %d 次眩晕, 其中 %d 次被不可阻挡挡下" % [_stun_n, _blocked_n])
		print("  目标剩余血量 %.0f / 4000" % float(_tgt.get("hp", 0.0)))
		print("DEMO DONE")
		get_tree().quit(0)
