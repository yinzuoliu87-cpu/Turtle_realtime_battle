extends Node
## verify_stream_edge_parity.gd — 逐帧直播: 「换个局面就露出来」的录放不一致, 每一类造一个确定的小局面, 原生录一遍、按流播一遍逐项比。
## 由来: 方案书 docs/plans/20261031e-训龟大师不受影响.md R7 —— 换直播门禁样本种子时 2000029 / 2000028 / 2000038 三局各露出一处,
##   根因与修法回填在同一份方案书 R7。真实快照局的种子随 sim 改动就会换局面(2000023 就是这么失效的),
##   所以这里不靠种子撞, 而是在调试场里**手推 sim 钟**(不跑 `_sim_step`, 场上除了这里摆的什么都不发生), 在指定步上摆出每一种形状:
##   ① 飘字合并按冒字那一刻的 `_t`: 步 202 冒一个「`_t` 还没推进」的数字, 步 204 同位置再冒一个 ⇒ 服务器差 0.05 秒不合并;
##      手机原来一律用步末的 `_t`(差 0.033)把第二个并进第一个(2000028 步 3391 / 3393「42」「77」)。
##   ② 全局 `t` 与单位时刻键(`*_until`)逐位等于服务器: 原来按 float32 发, 渲染步里 `_t >= baton_zap_until` 早一步成立
##      (2000028 步 8760 电击电弧手机早收)。
##   ③ keyframe 那一步变回类默认值的属性(显隐 → true / 帧号 → 0 / 颜色 → 白 / 材质颜色 → 白)与那一步被清掉的单位字段, 正在看的手机要收到
##      (2000029 触手预警带在 keyframe 步 9001 由隐变显, 手机一直停在隐)。
##   ④ 采样中间那一步的位置: 单位在采样步上瞬移 30 像素(冲撞起步同形), 中间那一步手机 == 服务器(2000028 / 2000038 插值差 14.7 / 14.4 像素)。
## 第五类(Sprite3D.material_override 白名单, 2000038)在 verify_stream_whitelist_alarm 的正对照里。
## ★分母: 每一类都先断言「服务器那一侧真的摆出了这个形状」(两条飘字、第二个 keyframe 落在步 601、中间步真的没动 …), 再比手机。

const P := preload("res://tests/_stream_play.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
const SIM_DT := 1.0 / 60.0
const N_STEPS := 680
const KF_I := 600            # 循环下标 600 的 post_step 是第 601 步 = 第二个 keyframe(第一个是第 1 步)
const FLOAT_A_I := 201       # 第 202 步: 「`_t` 推进之前」冒的数字
const FLOAT_B_I := 203       # 第 204 步: 推进之后同位置再冒一个
const JUMP_I := 301          # 第 302 步(采样步)单位 A 瞬移 +30 像素; 第 301 步是中间那一步
const SET_I := 299           # 第 300 步(采样步): 节点 / 材质 / 单位字段改成非默认值
const UNTIL_I := 401         # 第 402 步: 单位 B 写一个带零头的时刻键
const TXT_A := "9871"
const TXT_B := "13"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	## ── 原生: 调试场, 手推 sim 钟 + 录流 ──
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var ua: Dictionary = s._debug._edit_place_unit("basic", "left", Vector2(520.0, 300.0))
	var ub: Dictionary = s._debug._edit_place_unit("basic", "right", Vector2(900.0, 420.0))
	s.set_process(false)
	var rec := StreamRecorder.new(s, {"keep": true})
	rec.start()
	var t_log := {}
	var pos_log := {}
	var cur := [-1]
	rec.on_sampled = func(st: int) -> void:
		cur[0] = st
		t_log[st] = float(s._t)
		pos_log[st] = ua["pos"]
	var nat_f := {}
	var fl := P._float_hook(nat_f, cur)
	get_tree().node_added.connect(fl)
	var fpos: Vector2 = Vector2(700.0, 360.0)
	var mi: MeshInstance3D = null
	var mat: StandardMaterial3D = null
	var sp: Sprite3D = null
	var until_v := 0.0
	var s0: int = int(s._sim_step_n)     # 录流第 k 步(录流器自己数, 从 1 起)= sim 步号 s0 + k
	for i in range(N_STEPS):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		rec.pre_step()
		s._sim_step_n += 1
		if i == 100:
			mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mat = StandardMaterial3D.new()
			mi.material_override = mat
			mi.position = Vector3(1.0, 0.5, 1.0)
			s._world.add_child(mi)
			sp = Sprite3D.new()
			sp.texture = load("res://assets/sprites/vfx/baton-shock.png")
			sp.hframes = 6
			sp.position = Vector3(2.0, 0.5, 1.0)
			s._world.add_child(sp)
		elif i == SET_I:
			mi.visible = false
			mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
			sp.frame = 3
			sp.modulate = Color(0.5, 0.6, 0.7, 0.8)
			ua["true_fire_until"] = 99999.0
		elif i == KF_I:
			mi.visible = true
			mat.albedo_color = Color.WHITE
			sp.frame = 0
			sp.modulate = Color.WHITE
			ua.erase("true_fire_until")
		s._t = float(s._t) + SIM_DT
		if i == FLOAT_A_I:
			## 「这一步里 `_t` 还没推进」时冒的数字(单位 tick 里冒的那一类): sim 步号已是这一步, `_t` 还是上一步的
			var tk: float = s._t
			s._t = tk - SIM_DT
			s._vfx._float_text(fpos, TXT_A, Color(1, 1, 1), false, "damage", "true")
			s._t = tk
		elif i == FLOAT_B_I:
			s._vfx._float_text(fpos, TXT_B, Color(1, 1, 1), false, "damage", "true")
		elif i == JUMP_I:
			ua["pos"] = (ua["pos"] as Vector2) + Vector2(30.0, 0.0)
		elif i == UNTIL_I:
			until_v = float(s._t) + 0.123456789012345
			ub["spd_dbf_until"] = until_v
		rec.post_step()
	get_tree().node_added.disconnect(fl)
	var meta: Dictionary = rec.finish()
	var chunks: Array = rec.chunks
	var id_mi: int = (rec._tn_by_iid[mi.get_instance_id()] as StreamRecorder.TN).id if rec._tn_by_iid.has(mi.get_instance_id()) else -1
	var id_sp: int = (rec._tn_by_iid[sp.get_instance_id()] as StreamRecorder.TN).id if rec._tn_by_iid.has(sp.get_instance_id()) else -1
	var idx_a: int = rec._uidx(ua)
	var idx_b: int = rec._uidx(ub)
	var seed := int(s._battle_rng.seed)
	var nat_mi := [mi.visible, mat.albedo_color]
	var nat_sp := [sp.frame, sp.modulate]
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame

	## ── 流本身: keyframe 落点 / 全局 t 与时刻键逐位 ──
	var kf_steps: Array = []
	var t_n := 0
	var t_bad: Array = []
	var u_seen := false
	var u_val = null
	var stt := {}
	for c in chunks:
		var d := F.parse_chunk(c, stt)
		for stp in (d.get("list", []) as Array):
			var sn := int(stp[0])
			if bool(stp[1]):
				kf_steps.append(sn)
			for op in (stp[2] as Array):
				if int(op[0]) == F.OP_GLOBAL and (op[1] as Dictionary).has("t"):
					t_n += 1
					var tv = (op[1] as Dictionary)["t"]
					if typeof(tv) != TYPE_FLOAT or float(tv) != float(t_log.get(sn, -1.0)):
						if t_bad.size() < 3:
							t_bad.append("步%d 流 %.17f / 服务器 %.17f" % [sn, float(tv), float(t_log.get(sn, -1.0))])
						else:
							t_bad.append(null)
				elif int(op[0]) == F.OP_UNIT_SET and int(op[1]) == idx_b and (op[2] as Dictionary).has("spd_dbf_until"):
					u_seen = true
					u_val = (op[2] as Dictionary)["spd_dbf_until"]
	print("  [量] 录了 %d 步 / %d 块 · keyframe 步 %s · 全局 t 出现 %d 次 · 冒字早于推进 %s 次 · 中间步位置 @mp %s 次 · 节点 id 网格 %d 精灵 %d · 单位 A=%d B=%d" % [
		int(meta.get("steps", 0)), chunks.size(), str(kf_steps), t_n, str(meta.get("float_t_early", 0)), str(meta.get("mid_pos", 0)), id_mi, id_sp, idx_a, idx_b])
	_ok("分母 · 录满 %d 步, 第二个 keyframe 落在第 %d 步" % [N_STEPS, s0 + KF_I + 1], int(meta.get("steps", 0)) == N_STEPS and kf_steps.has(s0 + KF_I + 1),
		str(kf_steps))
	_ok("分母 · 两个节点、两个单位都进了流", id_mi > 0 and id_sp > 0 and idx_a >= 0 and idx_b >= 0)
	_ok("★②全局 t 逐位等于服务器的 `_t`(比过 %d 次)" % t_n, t_n > 100 and t_bad.is_empty(), "不同 %d 次 %s" % [t_bad.size(), str(t_bad.slice(0, 3))])
	_ok("★②单位时刻键 spd_dbf_until 逐位等于服务器(%.17f)" % until_v, u_seen and typeof(u_val) == TYPE_FLOAT and float(u_val) == until_v,
		"流里 %s" % str(u_val))

	## ── 播放: 一次推一步(60 帧手机) ──
	var b: Node = P.make_player_battle(self, chunks, meta, seed, {})
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了", p != null and str(b._replay.mode) == "stream")
	if p == null:
		_finish()
		return
	var ply_f := {}
	var pcur := [-1]
	var pfl := P._float_hook(ply_f, pcur)
	get_tree().node_added.connect(pfl)
	p.on_applied = func(st: int) -> void: pcur[0] = st
	var ply_pos := {}
	var kf_checked := false
	var ply_mi := []
	var ply_sp := []
	var ply_tf = "未查"
	p.advance(0.0)
	var g := 0
	while p.state != "ended" and p.state != "error" and g < 5000:
		g += 1
		p.advance(SIM_DT)
		var h := int(roundf(p.head))
		var pu = p.units.get(idx_a)
		if pu is Dictionary and float(p.head) == float(h):
			ply_pos[h] = pu["pos"]
		if not kf_checked and p.applied >= s0 + KF_I + 3:
			kf_checked = true
			var nm = p.mirror.nodes.get(id_mi)
			var ns = p.mirror.nodes.get(id_sp)
			if nm != null and is_instance_valid(nm):
				var mo = (nm as MeshInstance3D).material_override
				ply_mi = [(nm as Node3D).visible, (mo as StandardMaterial3D).albedo_color if mo is StandardMaterial3D else null]
			if ns != null and is_instance_valid(ns):
				ply_sp = [(ns as Sprite3D).frame, (ns as Sprite3D).modulate]
			ply_tf = ("键还在: %s" % str((p.units[idx_a] as Dictionary)["true_fire_until"])) if (p.units.has(idx_a) and (p.units[idx_a] as Dictionary).has("true_fire_until")) 				else (null if p.units.has(idx_a) else "没有单位")
		if g % 30 == 0:
			await get_tree().process_frame
	get_tree().node_added.disconnect(pfl)
	_ok("分母 · 播到结尾(应用 %d / %d 步)" % [p.steps_applied, int(meta.get("steps", 0))], p.state == "ended" and p.steps_applied == int(meta.get("steps", 0)),
		"%s %s" % [p.state, p.err])

	## ① 飘字
	var na: Array = _texts(nat_f)
	var nb: Array = _texts(ply_f)
	_ok("分母 · ①服务器冒了两个不合并的数字「%s」「%s」" % [TXT_A, TXT_B], na.has(TXT_A) and na.has(TXT_B), str(na))
	_ok("★①手机也冒两个(按冒字那一刻的 `_t` 判合并), 不把「%s」并进「%s」" % [TXT_B, TXT_A], nb.has(TXT_A) and nb.has(TXT_B) and nb.size() == na.size(),
		"原生 %s / 播放 %s" % [str(na), str(nb)])

	## ③ keyframe 那一步变回默认值
	_ok("分母 · ③服务器: 第 %d 步(keyframe)网格由隐变显、材质变回白、精灵帧号回 0、颜色回白、单位真火时刻被清掉" % (KF_I + 1),
		bool(nat_mi[0]) and nat_mi[1] == Color.WHITE and int(nat_sp[0]) == 0 and nat_sp[1] == Color.WHITE)
	_ok("★③手机: 网格显隐 / 材质颜色与服务器相同", ply_mi.size() == 2 and bool(ply_mi[0]) == bool(nat_mi[0]) and ply_mi[1] is Color
		and _col_near(ply_mi[1], nat_mi[1]), "原生 %s / 播放 %s" % [str(nat_mi), str(ply_mi)])
	_ok("★③手机: 精灵帧号 / 颜色与服务器相同", ply_sp.size() == 2 and int(ply_sp[0]) == int(nat_sp[0]) and _col_near(ply_sp[1], nat_sp[1]),
		"原生 %s / 播放 %s" % [str(nat_sp), str(ply_sp)])
	## 清掉 = 代理上也没有这个键(不是留一个 null: 渲染步 `float(u.get("true_fire_until", 0.0))` 读到 null 会报错)
	_ok("★③手机: 单位真火时刻(keyframe 那一步被清掉)代理上也清掉了", ply_tf == null, "播放端 %s" % str(ply_tf))

	## ④ 中间步位置
	var mid := s0 + JUMP_I     # 循环下标 JUMP_I 那一步(采样步, 瞬移)之前的中间步
	var nm0 = pos_log.get(mid)
	var nm1 = pos_log.get(mid + 1)
	_ok("分母 · ④服务器: 中间步(第 %d 步)还在原地、下一采样步跳了 30 像素" % mid, nm0 is Vector2 and nm1 is Vector2 and pos_log.get(mid - 1) is Vector2
		and (nm0 as Vector2).is_equal_approx(pos_log[mid - 1]) and absf((nm1 as Vector2).distance_to(nm0) - 30.0) < 0.01, "%s → %s → %s" % [
		str(pos_log.get(mid - 1)), str(nm0), str(nm1)])
	var pm = ply_pos.get(mid)
	var dmax := 0.0
	var dn := 0
	for st in ply_pos:
		if pos_log.has(st):
			dn += 1
			dmax = maxf(dmax, (ply_pos[st] as Vector2).distance_to(pos_log[st]))
	_ok("★④手机中间步的位置 == 服务器(差 %.4f 像素 ≤ %.2f)" % [(pm as Vector2).distance_to(nm0) if pm is Vector2 and nm0 is Vector2 else -1.0, F.MID_TOL],
		pm is Vector2 and nm0 is Vector2 and (pm as Vector2).distance_to(nm0) <= F.MID_TOL, "播放 %s / 原生 %s" % [str(pm), str(nm0)])
	_ok("★④整段每一步手机位置与服务器差 ≤ %.2f 像素(比过 %d 步, 最大 %.4f)" % [F.MID_TOL, dn, dmax], dn > N_STEPS / 2 and dmax <= F.MID_TOL)
	b.queue_free()
	await get_tree().process_frame
	_finish()


func _texts(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	var out: Array = []
	for k in ks:
		for t in (d[k] as Array):
			if str(t) == TXT_A or str(t) == TXT_B or str(t).to_int() == TXT_A.to_int() + TXT_B.to_int():
				out.append(str(t))
	return out


func _col_near(a, b) -> bool:
	if not (a is Color) or not (b is Color):
		return false
	var x: Color = a
	var y: Color = b
	return absf(x.r - y.r) <= 0.003 and absf(x.g - y.g) <= 0.003 and absf(x.b - y.b) <= 0.003 and absf(x.a - y.a) <= 0.003


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 直播局面边角(飘字合并时刻 / 双精度时刻 / keyframe 变回默认值 / 中间步位置)录放一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
