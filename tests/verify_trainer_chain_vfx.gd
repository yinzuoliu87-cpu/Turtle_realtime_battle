extends Node
## verify_trainer_chain_vfx.gd — 训龟大师钩锁的锁链(新画法)门禁。
##
## ★由来(用户 2026-11-20):「锁链特效主要现在这个锁链完全不行，你需要新设计一种方法」→ 看完 v1 视频「锁链差不多了」。
##   旧画法每个 sim 步在地上平铺一条拉长的铁链贴图、每条活 0.13 秒 ⇒ 同一根钩锁同时叠着 7 ~ 8 条在闪。
##   新画法(参考锤石 Q, docs/studies/20261120d-训龟大师锁链参考-锤石诺提勒斯逐帧.md): 一根链 = 一张常驻四边形(`TrainerChainVfx`)。
##
## 判据(真入口 `_cast_hook` + `_tick_hooks`, 手动按固定步长推, 不依赖 tween):
##   ① 飞行中: 场上锁链节点**恰好 1 个**(全程最多 1 个), 画成拖影带(ribbon = 1), 长度 = 大师手 → 钩头。
##   ② 钩中那一步: 同一个节点收成直链(ribbon = 0) + 亮光从目标那头起跑(glint 接近 1)。
##   ③ 拽的期间: 还是**同一个**节点(实例 id 不变), 亮光一路往大师跑(单调减), 正面朝镜头。
##   ④ 拽完: 收回到手里后节点删掉(表空 + 节点已释放)。
##   ⑤ 空放(线上没人): 飞满射程后同样收回删掉。
##   ⑥ 换路清场(`clear_flights`): 挂着的链立刻清掉。
## 反向验证(2026-11-20, 逐字节还原): 见文件末尾 `## 反向验证` 注释。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SH := "res://assets/shaders/trainer_chain.gdshader"
const DT := 1.0 / 60.0
var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s  %s" % [t, ex])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _chains() -> Array:
	var out: Array = []
	for n in _s._world.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.is_queued_for_deletion():
			continue
		var m = mi.material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path == SH:
			out.append(mi)
	return out


func _p(mi: MeshInstance3D, k: String) -> float:
	var v = (mi.material_override as ShaderMaterial).get_shader_parameter(k)
	return -999.0 if v == null else float(v)


func _step() -> void:
	_s._t += DT
	_s._trainer_sys._tick_hooks(DT)


func _mk(id: String, side: String, pos: Vector2, extra: Dictionary = {}) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, pos, extra)
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	print("=== 训龟大师钩锁: 新锁链(一根链 = 一张常驻四边形) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s.set_process(false)                      # 不让场景自己推 sim(本门禁手动推 _tick_hooks)
	_s.set_physics_process(false)
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var tr: Dictionary = _mk(_s.TRAINER_ID, "left", c + Vector2(-500.0, 0.0), {"trainer": true})
	var foe: Dictionary = _mk("stone", "right", c + Vector2(100.0, 0.0))
	tr["_active_cd"] = 0.0
	_s._t = 100.0
	_s._trainer_sys.clear_flights()            # 场景开场原有大师的在途钩子 / 链清掉(不清会有一根正在收回的旧链算进 ①)

	# ── ① 飞行 ──
	_ok("★分母: 出手成功", _s._trainer_sys._cast_hook(tr, Vector2(1, 0)) == true)
	var max_n := 0
	var fly_ok := true
	var fly_n := 0
	var first: MeshInstance3D = null
	var hit_step := -1
	for i in range(400):
		_step()
		var cs: Array = _chains()
		max_n = maxi(max_n, cs.size())
		if foe.has("_hooked_by"):
			hit_step = i
			break
		if cs.size() == 1:
			fly_n += 1
			if first == null:
				first = cs[0]
			if _p(cs[0], "ribbon") < 0.5:
				fly_ok = false
	_ok("★分母: 飞了 %d 步才钩中(有飞行段可量)" % fly_n, hit_step > 0 and fly_n >= 5)
	_ok("① 飞行中场上锁链节点最多 1 个(旧画法每步一条, 叠 7 ~ 8 条)", max_n == 1, "最多 %d 个" % max_n)
	_ok("① 飞行中画成拖影带(ribbon = 1)", fly_ok)

	# ── ② 钩中那一步 ──
	var cs2: Array = _chains()
	var mi: MeshInstance3D = cs2[0] if cs2.size() == 1 else null
	_ok("② 钩中那一步还是同一个节点", mi != null and first != null and mi == first)
	if mi == null:
		_finish()
		return
	_ok("② 同一步收成直链(ribbon = 0)", _p(mi, "ribbon") < 0.5, "ribbon=%.1f" % _p(mi, "ribbon"))
	_ok("② 亮光从目标那头起跑(glint ≈ 1)", _p(mi, "glint") > 0.85, "glint=%.2f" % _p(mi, "glint"))
	var hand: Vector3 = _s._world_pos(tr["pos"], TrainerChainVfx.HAND_H)
	var body: Vector3 = _s._world_pos(foe["pos"], TrainerChainVfx.BODY_H)
	_ok("② 四边形长边 = 大师手 → 目标身上", absf(mi.global_transform.basis.x.length() - hand.distance_to(body)) < 0.05,
		"%.2f vs %.2f" % [mi.global_transform.basis.x.length(), hand.distance_to(body)])
	var nrm: Vector3 = mi.global_transform.basis.z.normalized()
	_ok("② 正面朝镜头(法线 ∥ 视线)", absf(nrm.dot(BattleCam.FORWARD)) > 0.98, "%.3f" % absf(nrm.dot(BattleCam.FORWARD)))

	# ── ③ 拽的期间 ──
	var iid: int = mi.get_instance_id()
	var same := true
	var g_prev := 2.0
	var g_mono := true
	var g_seen := 0
	var g_starts := 0
	var g_was := true
	var first_run := true
	var pull_steps := 0
	while _s._t < float(foe.get("_hook_pull_until", 0.0)) and pull_steps < 600:
		_step()
		pull_steps += 1
		var cs3: Array = _chains()
		if cs3.size() != 1 or (cs3[0] as Object).get_instance_id() != iid:
			same = false
			break
		var g: float = _p(cs3[0], "glint")
		if g >= 0.0 and not g_was:
			g_starts += 1                              # 新起跑一道
			first_run = false
		if g >= 0.0 and first_run:                     # 钩中那一道: 一路跑完不许倒回去
			if g > g_prev + 0.0001:
				g_mono = false
			g_prev = g
			g_seen += 1
		if g < 0.0:
			first_run = false
		g_was = g >= 0.0
	_ok("★分母: 拽了 %d 步" % pull_steps, pull_steps > 60)
	_ok("③ 拽的全程是同一个节点(常驻, 不重建)", same)
	_ok("③ 钩中那道亮光一路从目标跑到大师, 中途不倒回(glint 单调减, 量了 %d 步)" % g_seen, g_mono and g_seen >= 5)
	_ok("③ 之后每拽一下再跑一道(又起跑 %d 道)" % g_starts, g_starts >= 2)

	# ── ④ 拽完收回 ──
	for _k in range(int(TrainerChainVfx.RETRACT_T / DT) + 4):
		_step()
	_ok("④ 拽完收回到手里后删掉", _chains().is_empty() and (_s._trainer_sys.chain_fx._chains as Array).is_empty(),
		"还剩 %d" % _chains().size())

	# ── ⑤ 空放 ──
	foe["alive"] = false
	tr["_active_cd"] = 0.0
	_s._trainer_sys._cast_hook(tr, Vector2(0, 1))
	var seen5 := false
	for _k in range(int((_s.HOOK_WINDUP + _s.HOOK_RANGE / _s.HOOK_MISSILE_SPD) / DT) + 10):
		_step()
		if _chains().size() == 1:
			seen5 = true
	for _k in range(int(TrainerChainVfx.RETRACT_T / DT) + 4):
		_step()
	_ok("⑤ 空放: 飞的时候有链(分母)、飞满射程收回后删掉", seen5 and _chains().is_empty())

	# ── ⑥ 换路清场 ──
	foe["alive"] = true
	foe.erase("_hooked_by")
	tr["_active_cd"] = 0.0
	_s._trainer_sys._cast_hook(tr, Vector2(1, 0))
	for _k in range(400):
		_step()
		if foe.has("_hooked_by"):
			break
	var had: int = _chains().size()
	_s._trainer_sys.clear_flights()
	_ok("⑥ 换路清场: 挂着的链立刻清掉(清之前 %d 根)" % had, had == 1 and _chains().is_empty() and (_s._trainer_sys.chain_fx._chains as Array).is_empty())
	_finish()


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()

## 反向验证(2026-11-20, 逐字节还原):
##   `_find` 永远找不到(每步新建一根) ⇒ ① 红; `latch` 不改模式 ⇒ ② 红; `end_step` 不收回 ⇒ ④⑤ 红; `clear` 不清 ⇒ ⑥ 红。
