extends Node
## verify_minion_unstoppable.gd — 近战小将【不可阻挡】+ 目标免控分支
##
## 用户 2026-08-20 拍板(逐句过方案书):
##   ·「在释放技能时会给自己不可阻挡的状态，就是免疫控制，跳起来放完技能完成最后的跳出动作后解除」
##   · 按 LoL 奥拉夫 R 那一档:「免所有硬控」+「免推开，推开不就是控制技能吗」⇒ 含减速、含位移
##   ·「如果这个技能的目标免疫控制则在绳索拉到对方后直接造成10%最大生命值加1.5ATK物理伤害
##      而不会把自己拉向对方」·「途中目标免疫则中断伤害并跳回地面」
##
## ★判据量【产品自己的账】: 直接读 `cc_immune_until` / `stun_until` / 位移 / 掉血,
##   不数我插的标记(铁律: 断言自己插的触发标记 = 插一行数一行必绿)。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(scn, side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = scn._spawn._make_unit("basic", side, at)
	u["deathfloor_until"] = 999999.0
	return u


func _done(scn) -> void:
	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 小将不可阻挡" if _fail == 0 else "FAIL")
	if scn != null:
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 近战小将·不可阻挡 / 目标免控分支 ===")

	var hs = scn._hiding_sys
	_ok("★分母: hiding_system 在场", hs != null)
	if hs == null:
		_done(scn)
		return

	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5

	# ── ① 施法期间不可阻挡: 被眩晕也不该真的晕上 ──
	var mn := _mk(scn, "left", Vector2(cx - 300.0, cy))
	var foe := _mk(scn, "right", Vector2(cx + 100.0, cy))
	hs._sk_minion_bodysurf(mn, foe)
	await get_tree().process_frame
	_ok("① 施法瞬间开启不可阻挡(cc_immune_until 在未来)",
		float(mn.get("cc_immune_until", 0.0)) > scn._t,
		"cc_immune_until=%.2f  _t=%.2f" % [float(mn.get("cc_immune_until", 0.0)), scn._t])
	_ok("① 同时免击飞(_knock_immune)", bool(mn.get("_knock_immune", false)))
	# 拿真闸门试: _stun 该被挡下
	scn._damage._stun(mn, 3.0, "test", true)
	_ok("① ★被眩晕挡下了(stun_until 没被推到未来)",
		float(mn.get("stun_until", 0.0)) <= scn._t,
		"stun_until=%.2f" % float(mn.get("stun_until", 0.0)))
	# 减速也该被清掉
	mn["spd_move_mult"] = 0.4
	hs._unstoppable_apply(mn)
	_ok("① ★减速也免(spd_move_mult 被清回 1.0)",
		float(mn.get("spd_move_mult", 1.0)) >= 1.0,
		"spd_move_mult=%.2f" % float(mn.get("spd_move_mult", 1.0)))
	hs._unstoppable_clear(mn)
	_ok("① 解除后 cc_immune_until 归零且不再免击飞",
		float(mn.get("cc_immune_until", 0.0)) <= 0.0 and not mn.has("_knock_immune"))

	# ── ② 目标免控 → 原地结算, 不把自己拉过去 ──
	var mn2 := _mk(scn, "left", Vector2(cx - 300.0, cy + 120.0))
	var foe2 := _mk(scn, "right", Vector2(cx + 100.0, cy + 120.0))
	foe2["maxHp"] = 4000.0
	foe2["hp"] = 4000.0
	foe2["base_def"] = 0.0
	foe2["base_mr"] = 0.0
	scn._recalc_stats(foe2)
	foe2["maxHp"] = 4000.0
	foe2["hp"] = 4000.0
	foe2["cc_immune_until"] = scn._t + 99.0        # 目标免控
	var from2: Vector2 = Vector2(mn2["pos"])
	var hp0: float = float(foe2["hp"])
	hs._sk_minion_bodysurf(mn2, foe2)
	# 等射链那一刻(0.68s)过去 —— 用墙钟轮询, 不等 tween(CLAUDE.md §3.5)
	var w := 0
	while w < 900 and float(foe2["hp"]) >= hp0:
		await get_tree().process_frame
		w += 1
	var dealt: float = hp0 - float(foe2["hp"])
	## ★暴击必须钉成 0 再算期望 —— `_resolve_dmg` 会掷 `_battle_rng.randf() < crit`,
	##   不钉的话期望值时高时低: 并行门禁里实测掉 552 而期望算成 690(掷中暴击) ⇒ 假红。
	##   (memory: 拿随机数测精确数值 = CI 偶发红, 要用干净合成单位隔离。)
	var _cs2: float = float(mn2.get("crit", 0.0))
	mn2["crit"] = 0.0
	var want: float = float(maxi(1, int(scn._resolve_dmg(mn2, 4000.0 * hs.IMMUNE_BRANCH_MAXHP_PCT + float(mn2.get("atk", 0.0)) * hs.IMMUNE_BRANCH_ATK_COEF, foe2, false))))
	mn2["crit"] = _cs2
	print("     免控分支: 实掉 %.0f / 期望 %.0f(±20%%容差·稀有度增伤)" % [dealt, want])
	_ok("② ★目标免控时结算了 10%%最大生命 + 1.5ATK 物理", dealt >= want * 0.9,
		"实掉 %.0f, 期望≥%.0f" % [dealt, want * 0.9])
	# 等它落地
	var w2 := 0
	while w2 < 900 and float(mn2.get("height", 0.0)) > 0.01:
		await get_tree().process_frame
		w2 += 1
	var moved: float = from2.distance_to(Vector2(mn2["pos"]))
	print("     小将位移 %.0f 码(后跳约 120, 拉到目标要 400+)" % moved)
	_ok("② ★没有把自己拉向目标(位移只有后跳那一段)", moved < 260.0,
		"位移 %.0f" % moved)
	_ok("② 落地了(height 归零)", float(mn2.get("height", 0.0)) <= 0.01)

	_done(scn)
