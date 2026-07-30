extends Node
## verify_ms_tier_vfx.gd — 魔法石叠层【阈值特效】(用户 2026-07-30:「层数到几个阈值的时候你加个精美的特效吧」)
##
## 方案书: docs/plans/20260730c-魔法石叠层阈值特效.md
##
## ★阈值写【字面值】不引用 MS_TIER_STACKS —— 引用常量就是拿代码跟它自己比 = 恒真式
##   (verify_trainer_magicstone 第一版栽过: 把 10 改成 1, 测试照样 ALL PASS)。
##
## 查五件事, 每件都打真数字:
##   ① tier 纯函数的边界(9/10 · 24/25 · 49/50 各差一层)
##   ② 常驻节点数随 tier 变 —— 走【真实每帧链路】_ms_tick_aura() 后数 _world 里的节点
##   ③ 跨阈值只放一次 —— 连喂同 tier 多帧, 迸裂计数不增
##   ④ 撤场干净 —— 换掉被动 / 大师死亡 → 节点回 0
##   ⑤ 脚下符文环【真的平铺】(|世界法线·上| ≈ 1.000) —— 2026-07-30 刚踩过竖环的坑
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_ms_tier_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

# ── 需求字面值(方案书 §0 定的三档) ──
const WANT_T1 := 10
const WANT_T2 := 25
const WANT_T3 := 50
const WANT_MOTES := {1: 3, 2: 3, 3: 6}      # 各 tier 晶石数
const MOTE_TEX := "res://assets/sprites/vfx/ms-mote.png"
const RING_TEX := "res://assets/sprites/vfx/ms-rune-ring.png"
const BURST_TEX := "res://assets/sprites/vfx/ms-resonance-burst.png"

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	gs.trainer_skill = "magic_stone"
	print("=== 魔法石叠层阈值特效 ===")

	# ★分母①: 三张素材必须真在磁盘上(缺图代码会 push_warning 然后不画 —— 那时下面全是空检查)
	for t in [MOTE_TEX, RING_TEX, BURST_TEX]:
		_chk("★分母: 素材在位 %s" % t.get_file(), ResourceLoader.exists(t))

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame
	var ts = s._trainer_sys
	var tr = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u; break
	if tr == null:
		print("  [FAIL] ★分母: 场上没有我方大师 —— 后面全是空检查"); _fail += 1; _done(s); return
	print("  ★分母: 大师 _tr_passive=%s" % str(tr.get("_tr_passive", "")))
	_chk("★分母: 大师真的带着魔法石被动", str(tr.get("_tr_passive", "")) == "magic_stone")

	# ── ① tier 边界(各差一层) ──
	print("")
	print("  ① tier 边界(阈值 %d / %d / %d):" % [WANT_T1, WANT_T2, WANT_T3])
	var cases := [[0, 0], [WANT_T1 - 1, 0], [WANT_T1, 1], [WANT_T2 - 1, 1],
		[WANT_T2, 2], [WANT_T3 - 1, 2], [WANT_T3, 3], [999, 3]]
	for cs in cases:
		var got: int = ts._ms_tier(int(cs[0]))
		print("     %3d 层 → tier %d  (需求 %d)  %s" % [cs[0], got, cs[1], "ok" if got == int(cs[1]) else "★差"])
		_chk("① %d 层 = tier %d" % [cs[0], cs[1]], got == int(cs[1]))

	# ── ② 常驻节点数随 tier 变(走真实每帧链路) ──
	print("")
	print("  ② 常驻节点(走 _ms_tick_aura 真实链路后数 _world):")
	for pair in [[0, 0], [WANT_T1, 1], [WANT_T2, 2], [WANT_T3, 3]]:
		tr["_ms_stacks"] = int(pair[0])
		ts._ms_tick_aura(0.016)
		await get_tree().process_frame
		var nm: int = _count(s, MOTE_TEX)
		var nr: int = _count(s, RING_TEX)
		var tier: int = int(pair[1])
		var want_m: int = int(WANT_MOTES.get(tier, 0))
		var want_r: int = 1 if tier >= 2 else 0
		print("     %3d 层(tier %d): 晶石 %d(需求 %d)  脚下环 %d(需求 %d)" % [
			pair[0], tier, nm, want_m, nr, want_r])
		_chk("② tier %d → 晶石 %d 颗" % [tier, want_m], nm == want_m)
		_chk("② tier %d → 脚下环 %d 个" % [tier, want_r], nr == want_r)

	# ── ⑤ 脚下符文环真的平铺(此刻是 tier 3, 环在) ──
	print("")
	var ring = tr.get("_ms_ring", null)
	_chk("⑤ ★分母: 脚下环节点在", is_instance_valid(ring))
	if is_instance_valid(ring):
		var rs: Sprite3D = ring
		var local_n := Vector3.BACK
		match rs.axis:
			Vector3.AXIS_X: local_n = Vector3.RIGHT
			Vector3.AXIS_Y: local_n = Vector3.UP
		var wn: Vector3 = (rs.global_transform.basis * local_n).normalized()
		var d: float = absf(wn.dot(Vector3.UP))
		print("  ⑤ 环 |世界法线·上| = %.3f  axis=%d rot=%s   (平铺该 ≈1.000 · 竖立是 0.000)" % [
			d, rs.axis, str(rs.rotation_degrees)])
		print("     ★2026-07-30 猎龟令/驯服两圈就是 axis=AXIS_Y 又叠 rotation.x=-90 → 立了一整场")
		_chk("⑤ ★★脚下环真的平铺(别再叠 -90 旋转)", d > 0.99)
		var dia: float = rs.texture.get_width() * rs.pixel_size
		print("     环直径 %.2f m (龟身高 %.2f m)" % [dia, s.TARGET_BODY_H])
		_chk("⑤ 环直径在 [1.5, 4.0] m(不许拿'效果半径'当贴片尺寸)", dia >= 1.5 and dia <= 4.0)

	# ── ③ 跨阈值只放一次 ──
	print("")
	print("  ③ 跨阈值迸裂只放一次:")
	var dummy := _dummy(s)
	if dummy.is_empty():
		print("     [FAIL] ★分母: 找不到靶子 —— ③ 是空检查"); _fail += 1
	else:
		tr["_ms_stacks"] = WANT_T1 - 1
		tr["_ms_burst_n"] = 0
		ts._trainer_magicstone_onhit(tr, dummy)          # 这一击跨过 tier1
		var n1: int = int(tr.get("_ms_burst_n", 0))
		print("     第 %d 层那一击(跨 tier1): 迸裂计数 %d (需求 1)" % [WANT_T1, n1])
		_chk("③ 跨过阈值那一击放一次", n1 == 1)
		# ★这里的击数必须【停在 tier1 之内】—— 我第一版打 20 下, 层数到 30 就跨过了 tier2 的
		#   25, 迸裂计数变 2 是【正确行为】, 我却断言它该是 1 = 测试写错, 不是功能错。
		var room: int = WANT_T2 - 1 - int(tr["_ms_stacks"])    # 打到 tier2 前一层为止
		for _i in range(room):
			if dummy.get("alive", false):
				ts._trainer_magicstone_onhit(tr, dummy)
		var n2: int = int(tr.get("_ms_burst_n", 0))
		print("     再打 %d 下到 %d 层(仍 tier1): 迸裂计数 %d (需求仍 1)" % [room, int(tr["_ms_stacks"]), n2])
		_chk("③ ★同一 tier 内不重放(不是每帧看层数)", n2 == 1)
		# 再打一下正好跨进 tier2 → 必须放第 2 次(否则上一条可能是"永远不放"的假绿灯)
		ts._trainer_magicstone_onhit(tr, dummy)
		var n3: int = int(tr.get("_ms_burst_n", 0))
		print("     再打 1 下到 %d 层(跨进 tier2): 迸裂计数 %d (需求 2)" % [int(tr["_ms_stacks"]), n3])
		_chk("③ ★★跨进下一 tier 又放一次(反向: 证明上一条不是'永远不放')", n3 == 2)

	# ── ④ 撤场干净 ──
	print("")
	print("  ④ 撤场:")
	tr["_ms_stacks"] = WANT_T3
	ts._ms_tick_aura(0.016)
	await get_tree().process_frame
	print("     tier3 时 晶石 %d / 环 %d" % [_count(s, MOTE_TEX), _count(s, RING_TEX)])
	_chk("④ ★分母: 撤之前确实有节点", _count(s, MOTE_TEX) > 0)
	tr["_tr_passive"] = ""                                # 换掉被动
	ts._ms_tick_aura(0.016)
	await get_tree().process_frame
	print("     换掉魔法石被动后 晶石 %d / 环 %d (需求 0/0)" % [_count(s, MOTE_TEX), _count(s, RING_TEX)])
	_chk("④ 换掉被动 → 撤干净", _count(s, MOTE_TEX) == 0 and _count(s, RING_TEX) == 0)
	tr["_tr_passive"] = "magic_stone"
	ts._ms_tick_aura(0.016)
	await get_tree().process_frame
	_chk("④ ★分母: 装回来又建出来了(证明上一条不是'永久坏了')", _count(s, MOTE_TEX) > 0)
	tr["alive"] = false                                   # 大师死亡
	ts._ms_tick_aura(0.016)
	await get_tree().process_frame
	print("     大师死亡后 晶石 %d / 环 %d (需求 0/0)" % [_count(s, MOTE_TEX), _count(s, RING_TEX)])
	_chk("④ 大师死亡 → 撤干净(不留孤儿节点)", _count(s, MOTE_TEX) == 0 and _count(s, RING_TEX) == 0)

	_done(s)


## _world 里用某张贴图的 Sprite3D 个数。
## ★按【贴图路径】数而不是按节点名 —— 环境气泡之类也是 Sprite3D, 按名字数会数错
##   (2026-07-30 探针踩过: 程序生成的贴图 resource_path 是空串)。
func _count(s, tex_path: String) -> int:
	var n := 0
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null \
			and str((c as Sprite3D).texture.resource_path) == tex_path:
			n += 1
	return n


func _dummy(s) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) == "right" and not u.get("is_trainer", false) and u.get("alive", false):
			u["maxHp"] = 100000.0; u["hp"] = 100000.0     # 打不死, 好连打 20 下
			return u
	return {}


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 魔法石叠层阈值特效" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
