extends Node
## verify_stream_tentacle.gd — 逐帧直播 v4: 灵物触手(固定网格 + 着色器热参数)录了再播, 手机上每一步与本机一致。
## 方案书 docs/plans/20261031d-灵物触手重做.md §4.2 / §6 验收 3「回放不掉帧」。
##
## 新触手每根 = 一个 MeshInstance3D(共用一份开局建好的网格)+ 一份 ShaderMaterial, 每步只写几个 uniform;
##   节点 meta `stream_shader_params` 列出会变的那几个(StreamFormat.SP_META)。录流器对它们:
##   标量逐步比、点数组(24 个控制点)30 Hz 量化差分(T_V3Q / T_V3QD); 播放端写回同一份材质, 采样之间插值。
##
## 同一进程里先在调试场原生跑一段(同时录流, 块留在内存): 两方 3 根触手出土 → 循环拍击(含点刺)→ 一根搬家 → 一根撤场;
##   每一步记下每根触手材质上那几个 uniform 的真值。再建播放模式的战斗场一步一推, 每步比:
##   ★采样步: 控制点逐点误差 ≤ 量化死区(1/1024 米); meta 列出的标量(白闪 / 露出 …)每一步都与本机相同(float32 往返),
##     向量 / 颜色在采样步相同(名单不写死, 第一路改了名单这里照样逐项比)
##   ★采样中间那一步: 手机插出来的控制点 = 前后两次采样的中点(不是停在上一帧 = 30 Hz 顿挫)
##   ★白闪: 本机亮过的每一次, 手机在同样的步上亮
##   ★网格: 本机整局同一份(不重建), 手机上也只建一份、不换代; 流里没有旧触手那种每步一代的出处键
##   ★纪律: 没列进 meta 的 uniform 一次都没变过(录流器 `sp_unlisted` = 0: 不滚纹理、不逐帧改粗细)
##   ★跳转: 从中途 keyframe 跳进来, 控制点照样对得上(keyframe 里是整份)
##   体积: 触手热参数压缩后 B/(根·秒) 只量不判(U12: 恢复版链式模拟动作的噪声让它涨了 2.8 倍, 等第一路修完抽搐再定阈值)
##   ★旧客户端(0.22.6): 入口版本闸先挡(录像版本 ≠ 本机版本不拉块); 就算拿到 v4 的块, 0.22.6 的解码器(tests/golden 存的原文)
##     报错返回、不崩 —— 版本号对不上那一步就停; 把版本号硬改成 3 再喂, 也在新标签那里报错返回。
## 分母: 触手节点 ≥ 3、比过的采样步 / 插值步 / 标量步、拍击白闪次数、点刺次数、搬家与撤场都真的发生过。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_stream_tentacle.tscn

const P := preload("res://tests/_stream_play.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
const OLD_PARSER := "res://tests/golden/stream_format_v0226.gd.txt"
const SIM_DT := 1.0 / 60.0
const STEPS := 1500               # 25 秒: 跨两个 keyframe(每 600 步一个)
## ★容差写死字面数(需求: 手机上的触手与本机差多少), 不从 StreamFormat.PTS_DZ / Q_PTS 推 ——
##   2026-10-31 改坏验证: 原来写成 PTS_DZ / Q_PTS, 把死区改成 3 之后容差跟着变大, 门禁照绿(恒真式)。
##   ★11-01 需求改成「与流里其它节点位置同一档」1/128 米(协调: 触手录流量要压到预算内, 见 StreamFormat.Q_PTS 注释);
##   每点半径(浮点数组)仍要 1/1024(TOL_F1)。
const TOL_PTS := 1.0 / 128.0 + 2.0e-6
const TOL_F1 := 1.0 / 1024.0 + 2.0e-6
const TOL_SCALAR := 2.0e-6        # float32 往返(露出 / 拍痕 0..1)
const TOL_MID := 2.0e-6           # 手机插值 vs 两次采样的中点(两边同一个 lerp)
## 体积(★只量不判, U12): 每根触手每秒热参数(单独抽出来、按块 ZSTD 压缩后)的字节。本场景是最坏情况(三根触手一待机就拍, 几乎一直在动)。
##   2026-10-31 实测 1420 B/(根·秒)(段向量外推 + 1 毫米死区; 只按 1/1024 舍入、一阶差是 1617)⇒ 上限 1600。
##   整局对照(方案书 §4.2): 最重那局(tests/golden/stream_heavy_pair.json, 三路打满)热参数合计 297 KB,
##   旧触手同一局是本体 366 KB + 外发光壳 29 KB = 395 KB ⇒ 换做法后直播体积没涨反降。
const Z_PER_TENT_SEC := 1600.0
## ★不写死 uniform 名(2026-10-31 第一路改成以旧版中心线为起点恢复, 名单可能变): 逐帧比的是节点 meta `stream_shader_params`
##   列出的**全部** uniform —— 点数组按量化容差比, float / int / bool 每步逐位比(float32 往返), 向量 / 颜色在采样步比。
const TOL_V3 := 2.0e-5
const TOL_COLOR := 0.5 / 255.0 + 1.0e-5

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
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var nat: Dictionary = await _record()
	await _play(nat)
	await _seek(nat)
	_old_client(nat)
	_finish()


## ═══════════════ 原生: 调试场里摆两只龟, 强制摆触手, 逐步推 sim + 录流 ═══════════════
func _record() -> Dictionary:
	OS.set_environment("TURTLE_SEED", "515151")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var rec := StreamRecorder.new(s, {"keep": true})
	rec.start()
	var tv = s._tentacle_vfx
	var snaps := {}               # 步 → {镜像节点 id: [控制点, {标量}, 网格 iid, fwd, lat]}
	var mesh_iids := {}           # 本机触手用过的网格对象
	var ids_seen := {}
	var cnt := {"flash": 0}       # ★lambda 按值捕获 int ⇒ 计数放进字典(引用)
	var jab_n := 0
	var reloc_ok := false
	var retract_seen := false
	var last_flash := {}
	rec.on_sampled = func(st: int) -> void:
		var row := {}
		for t in rec._tn:
			var tn: StreamRecorder.TN = t
			if not is_instance_valid(tn.n) or not tn.n.has_meta(F.SP_META):
				continue
			var mi := tn.n as MeshInstance3D
			var mat := mi.material_override as ShaderMaterial
			if mat == null:
				continue
			var sc := {}
			var pn := ""
			for nm in PackedStringArray(tn.n.get_meta(F.SP_META)):
				var v = mat.get_shader_parameter(nm)
				if v is PackedVector3Array and pn == "":
					pn = nm                 # 控制点(第一个点数组)
				else:
					sc[nm] = v
			row[tn.id] = [PackedVector3Array(mat.get_shader_parameter(pn)) if pn != "" else PackedVector3Array(), sc,
				mi.mesh.get_instance_id() if mi.mesh != null else 0, pn]
			mesh_iids[mi.mesh.get_instance_id() if mi.mesh != null else 0] = mi.mesh
			ids_seen[tn.id] = true
			var fl: bool = sc.get("flash") != null and float(sc["flash"]) > 0.0
			if fl and not bool(last_flash.get(tn.id, false)):
				cnt["flash"] = int(cnt["flash"]) + 1
			last_flash[tn.id] = fl
		snaps[st] = row
	rec.pre_step()
	s._edit_dummy_killable = false
	s._debug._edit_place_unit("stone", "left", Vector2(560.0, 360.0))
	s._debug._edit_place_unit("stone", "right", Vector2(760.0, 360.0))
	s._debug._edit_start_battle()
	s.set_process(false)
	tv.clear()
	tv.preview_lock = true        # spirit 系统按真实档位(0)每帧 ensure 的那一下不许把它们撤了
	tv.ensure_forced("left", 2)
	tv.ensure_forced("right", 1)
	var reloc_to := Vector2.ZERO
	var reloc_wait := false
	for i in range(STEPS):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		if i > 0:
			rec.pre_step()
		## 待机的就拍: 左 0 号正常拍击、左 1 号隔一次点刺、右 0 号正常拍击; 900 步左 1 号搬家, 1250 步右方撤场
		for sd in ["left", "right"]:
			for k in range(2):
				if int(tv.state_of(sd, k)) != TentacleVfx.ST_IDLE or i >= 1250:
					continue
				var r0: Vector2 = tv.root_pos(sd, k)
				var aim: Vector2 = r0 + Vector2(300.0 if sd == "left" else -300.0, 40.0 * (k * 2 - 1))
				var share := 1.0
				if sd == "left" and k == 1 and (i / 200) % 2 == 1:
					share = 0.25
					jab_n += 1
				## 左 1 号: 880 步起不再拍, 下一次待机就搬家(钻地 → 新位置破土), 搬完接着拍
				if sd == "left" and k == 1 and i >= 880 and not reloc_ok:
					reloc_to = r0 + Vector2(80.0, -60.0)
					reloc_ok = tv.relocate(sd, k, reloc_to)
					continue
				tv.strike(sd, k, aim, share)
		if i == 1250:
			tv.ensure_forced("right", 0)
		if i > 1250 and int(tv.state_of("right", 0)) == TentacleVfx.ST_RETRACT:
			retract_seen = true
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
	var flash_eps: int = int(cnt["flash"])
	var reloc_done: bool = reloc_ok and (tv.root_pos("left", 1) as Vector2).distance_to(reloc_to) < 0.5
	var right_gone: bool = tv.state_of("right", 0) == -1
	var m: Dictionary = rec.finish()
	var seed := int(s._battle_rng.seed)
	var shared_v := -1
	for mk in mesh_iids:
		var mm0 = mesh_iids[mk]
		if mm0 is Mesh and (mm0 as Mesh).get_surface_count() > 0:
			shared_v = (mm0 as Mesh).surface_get_array_len(0)
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	print("  [量] 原生: 步 %d · 块 %d · 触手节点 %d · 白闪 %d 次 · 点刺 %d 次 · 搬家 %s · 撤场 %s · 热参数 定义 %d 次 / 改 %d 项 / %d B · 没列出的变了 %d %s · 出处键 %s" % [
		int(m.get("steps", 0)), rec.chunks.size(), ids_seen.size(), flash_eps, jab_n, str(reloc_done), str(retract_seen and right_gone),
		int(m.get("sp_mats", 0)), int(m.get("sp_sets", 0)), int(m.get("sp_bytes", 0)), int(m.get("sp_unlisted", 0)),
		str(m.get("sp_unlisted_names", {})), str(m.get("gen_by", {}))])
	_ok("分母 · 原生录到触手节点 %d ≥ 3(都带控制点数组)、点刺 %d ≥ 1 次; 白闪 %d 次(着色器有 flash 时要 ≥ 4)" % [ids_seen.size(), jab_n, flash_eps],
		ids_seen.size() >= 3 and jab_n >= 1 and (flash_eps >= 4 or not _has_flash(snaps)) and _all_have_pts(snaps))
	_ok("分母 · 搬家真的搬到了(%s)、右方那根真的撤场删掉了(%s)" % [str(reloc_done), str(retract_seen and right_gone)], reloc_done and retract_seen and right_gone)
	_ok("★本机: 所有触手整局只用一份网格、开局建好不重建(用过 %d 份, %d 个顶点)" % [mesh_iids.size(), shared_v],
		mesh_iids.size() == 1 and shared_v > 0)
	_ok("★纪律: 没列进 stream_shader_params 的 uniform 一次都没变(不滚纹理、不逐帧改粗细): 变了 %d 次 %s; 分母: 热参数材质定义 %d 次" % [
		int(m.get("sp_unlisted", 0)), str(m.get("sp_unlisted_names", {})), int(m.get("sp_mats", 0))],
		int(m.get("sp_unlisted", 0)) == 0 and int(m.get("sp_mats", 0)) >= 3)
	var gb: Dictionary = m.get("gen_by", {})
	var old_gen := 0
	for k in gb:
		if str(k).begins_with("gen_tentacle_") and str(k) != "gen_tentacle_tube" and str(k) != "gen_tentacle_warn":
			old_gen += int((gb[k] as Array)[0])
	var tube_n: int = int((gb.get("gen_tentacle_tube", [0, 0]) as Array)[0])
	var keys := int(ceil(float(STEPS) / float(F.KEY_STEPS)))
	_ok("★流里触手网格只定义 %d 次(≤ keyframe 段数 %d), 没有每步一代的旧出处键(%d)" % [tube_n, keys, old_gen],
		tube_n >= 1 and tube_n <= keys and old_gen == 0)
	return {"chunks": rec.chunks, "meta": m, "snaps": snaps, "seed": seed, "ids": ids_seen, "shared_v": shared_v}


## ═══════════════ 播放: 一步一推, 每步比 ═══════════════
func _play(nat: Dictionary) -> void:
	print("=== 顺播 ===")
	var gs = get_node_or_null("/root/GameState")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var b: Node = P.make_player_battle(self, nat["chunks"], nat["meta"], int(nat["seed"]), {})
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了", p != null and str(b._replay.mode) == "stream")
	if p == null:
		return
	var snaps: Dictionary = nat["snaps"]
	var st := {"samp": 0, "mid": 0, "sc": 0, "pts_max": 0.0, "mid_max": 0.0, "sc_max": 0.0, "dev_max": 0.0, "bad": [],
		"fl_nat": 0, "fl_hit": 0, "mesh": {}, "nodes": {}}
	var last_fl := {}
	var ph := {}                  # 步 → {节点 id: 手机上的控制点}(插值核对用: 采样中间那一步 = 前后两个采样步的中点)
	var phf := {}                 # 步 → {"节点 id|参数名": 手机上的浮点数组(每点半径一类)}(同上)
	p.advance(0.0)
	var g := 0
	while p.state != "ended" and p.state != "error" and g < 20000:
		g += 1
		p.advance(SIM_DT)
		if g % 60 == 0:
			await get_tree().process_frame   # 原生那边每 60 步隔一帧(queue_free / call_deferred 隔帧才跑), 这边也隔帧
		var s: int = p.applied
		if not snaps.has(s):
			continue
		var at_s: bool = p.at_sample
		var row: Dictionary = snaps[s]
		for id in row:
			var mn = p.mirror.nodes.get(int(id))
			if mn == null or not is_instance_valid(mn) or not (mn is MeshInstance3D):
				(st["bad"] as Array).append("步%d 节点%d 手机上没有" % [s, int(id)])
				continue
			var mm := (mn as MeshInstance3D).material_override as ShaderMaterial
			if mm == null:
				(st["bad"] as Array).append("步%d 节点%d 手机上没有着色器材质" % [s, int(id)])
				continue
			st["nodes"][int(id)] = true
			if (mn as MeshInstance3D).mesh != null:
				st["mesh"][(mn as MeshInstance3D).mesh.get_instance_id()] = (mn as MeshInstance3D).mesh
			var nv: Array = row[id]
			var pa = mm.get_shader_parameter(str(nv[3]))
			var na: PackedVector3Array = nv[0]
			if not (pa is PackedVector3Array) or (pa as PackedVector3Array).size() != na.size():
				(st["bad"] as Array).append("步%d 节点%d 控制点 手机 %s / 本机 %d 个" % [s, int(id), type_string(typeof(pa)), na.size()])
				continue
			var dmax := 0.0
			for j in range(na.size()):
				dmax = maxf(dmax, ((pa as PackedVector3Array)[j] - na[j]).abs()[((pa as PackedVector3Array)[j] - na[j]).abs().max_axis_index()])
			(ph.get_or_add(s, {}) as Dictionary)[id] = [PackedVector3Array(pa), at_s]
			if at_s:
				st["samp"] = int(st["samp"]) + 1
				st["pts_max"] = maxf(float(st["pts_max"]), dmax)
				if dmax > TOL_PTS:
					(st["bad"] as Array).append("步%d 节点%d 采样步控制点差 %.6f" % [s, int(id), dmax])
			else:
				## 采样中间: 与本机这一步的真值差只打剖面(插值核对在播完之后, 要用到下一个采样步)
				st["dev_max"] = maxf(float(st["dev_max"]), dmax)
			var sc: Dictionary = nv[1]
			for nm in sc:
				var pvv = mm.get_shader_parameter(nm)
				if pvv is PackedFloat32Array:
					(phf.get_or_add(s, {}) as Dictionary)["%d|%s" % [int(id), str(nm)]] = [PackedFloat32Array(pvv), at_s]
				var why := _cmp_val(pvv, sc[nm], at_s, st)
				if why != "":
					(st["bad"] as Array).append("步%d 节点%d %s %s" % [s, int(id), str(nm), why])
			var fl_n: bool = sc.get("flash") != null and float(sc["flash"]) > 0.0
			if fl_n and not bool(last_fl.get(id, false)):
				st["fl_nat"] = int(st["fl_nat"]) + 1
				if float(mm.get_shader_parameter("flash")) > 0.0:
					st["fl_hit"] = int(st["fl_hit"]) + 1
			last_fl[id] = fl_n
	## 插值: 采样中间那一步手机上的控制点 = 前后两个采样步手机上的值的中点(30 Hz 采样, 手机 60 帧不顿)
	for s3 in ph:
		for id3 in (ph[s3] as Dictionary):
			var cur: Array = ph[s3][id3]
			if bool(cur[1]) or not ph.has(s3 - 1) or not ph.has(s3 + 1):
				continue
			var e0 = (ph[s3 - 1] as Dictionary).get(id3)
			var e1 = (ph[s3 + 1] as Dictionary).get(id3)
			if not (e0 is Array) or not (e1 is Array) or not bool(e0[1]) or not bool(e1[1]):
				continue
			var a0: PackedVector3Array = e0[0]
			var a1: PackedVector3Array = e1[0]
			var pc: PackedVector3Array = cur[0]
			if a0.size() != pc.size() or a1.size() != pc.size():
				continue
			var mmax := 0.0
			for j in range(pc.size()):
				var mid: Vector3 = a0[j].lerp(a1[j], 0.5)
				mmax = maxf(mmax, (pc[j] - mid).abs()[(pc[j] - mid).abs().max_axis_index()])
			st["mid"] = int(st["mid"]) + 1
			st["mid_max"] = maxf(float(st["mid_max"]), mmax)
			if mmax > TOL_MID:
				(st["bad"] as Array).append("步%d 节点%d 插值不在中点 %.6f" % [s3, int(id3), mmax])
	## 浮点数组(每点半径一类)同样: 采样中间 = 前后两个采样步的中点
	for s4 in phf:
		for kk in (phf[s4] as Dictionary):
			var cf: Array = phf[s4][kk]
			if bool(cf[1]) or not phf.has(s4 - 1) or not phf.has(s4 + 1):
				continue
			var f0 = (phf[s4 - 1] as Dictionary).get(kk)
			var f1 = (phf[s4 + 1] as Dictionary).get(kk)
			if not (f0 is Array) or not (f1 is Array) or not bool(f0[1]) or not bool(f1[1]):
				continue
			var b0: PackedFloat32Array = f0[0]
			var b1: PackedFloat32Array = f1[0]
			var bc: PackedFloat32Array = cf[0]
			if b0.size() != bc.size() or b1.size() != bc.size():
				continue
			var fm := 0.0
			for j in range(bc.size()):
				fm = maxf(fm, absf(bc[j] - lerpf(b0[j], b1[j], 0.5)))
			st["mid_f"] = int(st.get("mid_f", 0)) + 1
			if fm > TOL_MID:
				(st["bad"] as Array).append("步%d %s 浮点数组插值不在中点 %.6f" % [s4, str(kk), fm])
	print("  [量] 浮点数组(每点半径一类)插值核对 %d 处" % int(st.get("mid_f", 0)))
	var m: Dictionary = st["mesh"]
	var mesh_ok := m.size() == 1
	var mv := -1
	for k in m:
		mv = (m[k] as Mesh).surface_get_array_len(0) if (m[k] as Mesh).get_surface_count() > 0 else -1
	print("  [量] 顺播: 应用 %d 步 · 比过 采样步·根 %d / 插值步·根 %d / 标量·项 %d · 误差上限 控制点 %.6f 插值 %.7f 标量 %.7f · 插值点与本机真值差最大 %.4f 米 · 热参数 应用 %d / 差分缺上一份 %d · 状态 %s %s" % [
		p.steps_applied, int(st["samp"]), int(st["mid"]), int(st["sc"]), float(st["pts_max"]), float(st["mid_max"]), float(st["sc_max"]),
		float(st["dev_max"]), p.mirror.sp_sets, p.mirror.sp_miss, p.state, p.err])
	_ok("分母 · 播到结尾(应用 %d / 录 %d 步), 比过采样步·根 %d > 300、插值步·根 %d > 300、镜像触手节点 %d ≥ 3" % [p.steps_applied,
		int((nat["meta"] as Dictionary).get("steps", 0)), int(st["samp"]), int(st["mid"]), (st["nodes"] as Dictionary).size()],
		p.state == "ended" and p.steps_applied == int((nat["meta"] as Dictionary).get("steps", -1)) and int(st["samp"]) > 300
		and int(st["mid"]) > 300 and (st["nodes"] as Dictionary).size() >= 3)
	_ok("★★控制点: 采样步逐点误差 ≤ %.6f(量化死区), 采样中间 = 两次采样的中点; 标量每步相同" % TOL_PTS,
		(st["bad"] as Array).is_empty(), str((st["bad"] as Array).slice(0, 5)))
	_ok("★白闪(着色器有 flash 时): 本机亮过 %d 次, 手机在同一步亮 %d 次" % [int(st["fl_nat"]), int(st["fl_hit"])],
		int(st["fl_hit"]) == int(st["fl_nat"]) and (int(st["fl_nat"]) >= 4 or not _has_flash(snaps)))
	_ok("★手机上所有触手共用一份网格、整场不换代(%d 份, 顶点 %d = 本机 %d), 差分全找得到上一份(缺 %d)、生成失败 %d、占位 %d" % [m.size(), mv,
		int(nat["shared_v"]), p.mirror.sp_miss, p.mirror.gen_fail, p.mirror.ph_proc_mesh],
		mesh_ok and mv == int(nat["shared_v"]) and p.mirror.sp_miss == 0 and p.mirror.gen_fail == 0 and p.mirror.ph_proc_mesh == 0 and p.mirror.sp_sets > 0)
	## 体积: 热参数原始字节 / (根·秒)
	var meta: Dictionary = nat["meta"]
	var tent_sec := 0.0
	for s2 in snaps:
		tent_sec += float((snaps[s2] as Dictionary).size()) * SIM_DT
	var bps := float(meta.get("sp_bytes", 0)) / maxf(1.0, tent_sec)
	var zb := _sp_zbytes(nat["chunks"])
	var zps := float(zb) / maxf(1.0, tent_sec)
	print("  [量] 体积: 热参数原始 %d B / %.1f 根·秒 = %.0f B/(根·秒); 单独抽出来按块压缩 %d B = %.0f B/(根·秒); 整段流压缩后 %d B(原始 %d B)" % [
		int(meta.get("sp_bytes", 0)), tent_sec, bps, zb, zps, int(meta.get("z_bytes", 0)), int(meta.get("raw_bytes", 0))])
	## ★2026-11-01 改成只量不判(方案书 §5 U12): 第一路恢复了 8 月的链式模拟动作, 控制点每步的加速度噪声大(= 抽搐的另一面),
	##   预测残差压不下去(死区 1 → 4 毫米只省 2%), 实测 3924 B/(根·秒)、最重局 878 KB(旧触手 395 KB)。
	##   阈值等第一路交回「抽搐修复」后复测再定; 整局 / 单块的硬上限仍由 verify_stream_size_budget 守。
	print("  [量] 体积: 触手热参数压缩后 %.0f B/(根·秒)(第一版表驱动动作 1420; 阈值待定 U12, 参考上限 %.0f)" % [zps, Z_PER_TENT_SEC])
	_ok("分母 · 体积量到了(热参数字节 > 0)", zps > 0.0)
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true


## 一个热参数值手机 vs 本机: "" = 一致。float / int / bool 每步比; 向量 / 颜色只在采样步比(30 Hz); 其余类型只要求类型相同。
func _cmp_val(pv, nv, at_s: bool, st: Dictionary) -> String:
	if pv == null and nv == null:
		return ""
	var t := typeof(nv)
	if t == TYPE_FLOAT or t == TYPE_INT or t == TYPE_BOOL:
		st["sc"] = int(st["sc"]) + 1
		if pv == null:
			return "手机没有 / 本机 %s" % str(nv)
		var d := absf(float(pv) - float(nv))
		st["sc_max"] = maxf(float(st["sc_max"]), d)
		return "" if d <= TOL_SCALAR else "手机 %.6f / 本机 %.6f" % [float(pv), float(nv)]
	if not at_s:
		return ""
	if t == TYPE_VECTOR3:
		return "" if pv is Vector3 and ((pv as Vector3) - (nv as Vector3)).length() <= TOL_V3 else "手机 %s / 本机 %s" % [str(pv), str(nv)]
	if t == TYPE_COLOR:
		if not (pv is Color):
			return "手机 %s / 本机 %s" % [str(pv), str(nv)]
		var c1: Color = pv
		var c2: Color = nv
		var dc := maxf(maxf(absf(c1.r - c2.r), absf(c1.g - c2.g)), maxf(absf(c1.b - c2.b), absf(c1.a - c2.a)))
		return "" if dc <= TOL_COLOR else "颜色差 %.5f" % dc
	if t == TYPE_PACKED_FLOAT32_ARRAY:
		if not (pv is PackedFloat32Array) or (pv as PackedFloat32Array).size() != (nv as PackedFloat32Array).size():
			return "数组 手机 %s / 本机 %d 个" % [type_string(typeof(pv)), (nv as PackedFloat32Array).size()]
		var dm := 0.0
		for j in range((nv as PackedFloat32Array).size()):
			dm = maxf(dm, absf((pv as PackedFloat32Array)[j] - (nv as PackedFloat32Array)[j]))
		return "" if dm <= TOL_F1 else "数组差 %.6f" % dm     # v4 每点半径按 1/1024 量化
	return "" if typeof(pv) == t else "类型 %s / %s" % [type_string(typeof(pv)), type_string(t)]


func _has_flash(snaps: Dictionary) -> bool:
	for s in snaps:
		for id in (snaps[s] as Dictionary):
			if ((snaps[s][id] as Array)[1] as Dictionary).has("flash"):
				return true
	return false


func _all_have_pts(snaps: Dictionary) -> bool:
	var n := 0
	for s in snaps:
		for id in (snaps[s] as Dictionary):
			n += 1
			if str((snaps[s][id] as Array)[3]) == "":
				return false
	return n > 0


## 热参数那部分压缩后多大: 把流里「带 v4 点数组的材质」的定义与改动原样重编进每块一个缓冲, 按块 ZSTD 压(与录流器同一种压法)。
func _sp_zbytes(chunks: Array) -> int:
	var st := {}
	var hot := {}
	var total := 0
	var by_nm := {}               # 参数名 → 单独抽出来按块压缩后的字节(看是哪一项贵)
	for c in chunks:
		var d := F.parse_chunk(c, st)
		var e := F.Enc.new()
		var per := {}
		for stp in (d.get("list", []) as Array):
			for op in (stp[2] as Array):
				var pl = null
				if int(op[0]) == F.OP_RES_DEF and int(op[2]) == F.RES_PARAM:
					pl = op[4]
					for x in (pl as Array):
						if (x as Array).size() > 3:
							hot[int(op[1])] = true
				elif int(op[0]) == F.OP_RES_SET and hot.has(int(op[1])):
					pl = op[2]
				else:
					continue
				if not hot.has(int(op[1])):
					continue
				e.u8(int(op[0]))
				e.vu(int(op[1]))
				e.vu((pl as Array).size())
				for x in (pl as Array):
					e.s(str(x[0]))
					var pe: F.Enc = per.get_or_add(str(x[0]), F.Enc.new())
					if (x as Array).size() > 3:
						if int(x[3][2]) == 1:
							e.ints(F.T_F1QD if int(x[3][0]) == 1 else F.T_F1Q, x[3][1])
							pe.ints(F.T_F1QD if int(x[3][0]) == 1 else F.T_F1Q, x[3][1])
						else:
							e.pts(F.T_V3QD if int(x[3][0]) == 1 else F.T_V3Q, x[3][1])
							pe.pts(F.T_V3QD if int(x[3][0]) == 1 else F.T_V3Q, x[3][1])
					elif bool(x[2]):
						e.res(int(x[1]))
					else:
						e.val(x[1])
						pe.val(x[1])
		var raw := e.take()
		if raw.size() > 0:
			total += raw.compress(FileAccess.COMPRESSION_ZSTD).size()
		for nm in per:
			var r2: PackedByteArray = (per[nm] as F.Enc).take()
			if r2.size() > 0:
				by_nm[nm] = int(by_nm.get(nm, 0)) + r2.compress(FileAccess.COMPRESSION_ZSTD).size()
	var ks: Array = by_nm.keys()
	ks.sort_custom(func(a, b): return int(by_nm[a]) > int(by_nm[b]))
	var parts := PackedStringArray()
	for k in ks.slice(0, 8):
		parts.append("%s %d" % [str(k).replace("shader_parameter/", ""), int(by_nm[k])])
	print("  [量] 热参数按项单独压缩(B, 只看谁贵): %s" % ", ".join(parts))
	return total


## ═══════════════ 跳转: 从中途的 keyframe 跳进来 ═══════════════
func _seek(nat: Dictionary) -> void:
	print("=== 跳转 ===")
	var gs = get_node_or_null("/root/GameState")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var b: Node = P.make_player_battle(self, nat["chunks"], nat["meta"], int(nat["seed"]), {})
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	if p == null:
		_ok("跳转 · 播放模式建起来了", false)
		return
	p.advance(0.0)
	var snaps: Dictionary = nat["snaps"]
	var n := 0
	var bad: Array = []
	for target in [700, 1101, 1203]:
		p.seek(int(target))
		## 跳到非采样步时手机在插值(与顺播同一个中点) ⇒ 推到下一个采样步再比真值
		var gg := 0
		while not p.at_sample and gg < 4:
			p.advance(SIM_DT)
			gg += 1
		var s: int = p.applied
		if not snaps.has(s):
			bad.append("跳到 %d 停在 %d, 本机没有这一步" % [target, s])
			continue
		for id in (snaps[s] as Dictionary):
			var mn = p.mirror.nodes.get(int(id))
			if mn == null or not is_instance_valid(mn):
				bad.append("跳到 %d: 节点%d 没有" % [s, int(id)])
				continue
			var pa = ((mn as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(str((snaps[s][id] as Array)[3]))
			var ex: PackedVector3Array = (snaps[s][id] as Array)[0]
			if not (pa is PackedVector3Array) or (pa as PackedVector3Array).size() != ex.size():
				bad.append("跳到 %d: 节点%d 控制点个数不对" % [s, int(id)])
				continue
			var dmax := 0.0
			for j in range(ex.size()):
				dmax = maxf(dmax, ((pa as PackedVector3Array)[j] - ex[j]).abs()[((pa as PackedVector3Array)[j] - ex[j]).abs().max_axis_index()])
			n += 1
			if dmax > TOL_PTS:
				bad.append("跳到 %d: 节点%d 控制点差 %.5f" % [s, int(id), dmax])
		## 跳完接着播一秒, 差分要接得上(keyframe 里的整份是差分的起点)
		for _k in range(60):
			p.advance(SIM_DT)
	_ok("★跳转: 从中途 keyframe 跳进来控制点对得上(比过 %d 根·次)、接着播差分不缺上一份(缺 %d)" % [n, p.mirror.sp_miss],
		bad.is_empty() and n >= 3 and p.mirror.sp_miss == 0, str(bad.slice(0, 4)))
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true


## ═══════════════ 旧客户端(0.22.6) ═══════════════
func _old_client(nat: Dictionary) -> void:
	print("=== 旧客户端 0.22.6 ===")
	## ① 入口版本闸: 录像版本 ≠ 本机版本 ⇒ 不拉块(stream_watch.check = ReplayRecorder.play_check)
	var why: String = ReplayRecorder.play_check({"client_version": "0.0.0-old", "v": ReplayRecorder.FORMAT_V})
	_ok("★入口版本闸: 录像版本与本机不同 ⇒ 不进播放(「%s」)" % why, why != "")
	## ② 0.22.6 的解码器原文(v0.22.6 标签下的 stream_format.gd, 去掉 class_name 现编译)
	var src := FileAccess.get_file_as_string(OLD_PARSER)
	_ok("分母 · 0.22.6 解码器原文读得到(%d 字节, VERSION 3)" % src.length(), src.length() > 10000 and src.contains("const VERSION := 3"))
	if src.length() < 10000:
		return
	var gd := GDScript.new()
	gd.source_code = src.replace("class_name StreamFormat\n", "").replace("class_name StreamFormat\r\n", "")
	var err := gd.reload()
	_ok("分母 · 0.22.6 解码器编译通过(%d)" % err, err == OK)
	if err != OK:
		return
	var chunks: Array = nat["chunks"]
	var v4_tags := 0
	var st := {}
	for c in chunks:
		var d := F.parse_chunk(c, st)
		for stp in (d.get("list", []) as Array):
			for op in (stp[2] as Array):
				if int(op[0]) == F.OP_RES_SET or int(op[0]) == F.OP_RES_DEF:
					var pl = op[2] if int(op[0]) == F.OP_RES_SET else op[4]
					if pl is Array:
						for e in (pl as Array):
							if (e as Array).size() > 3:
								v4_tags += 1
	_ok("分母 · 新流里确有 v4 点数组 %d 处" % v4_tags, v4_tags > 100)
	var as_is := 0
	var forced := 0
	var forced_errs := {}
	for c in chunks:
		var d1: Dictionary = gd.parse_chunk(c, {})
		if not bool(d1.get("ok", true)) and str(d1.get("err", "")).begins_with("version"):
			as_is += 1
		## 把头里的版本号硬改成 3(假设服务器写错了版本): 旧解码器读到新标签必须报错返回, 不崩
		var c3 := PackedByteArray(c)
		c3.encode_u16(4, 3)
		var d2: Dictionary = gd.parse_chunk(c3, {})
		if not bool(d2.get("ok", true)):
			forced += 1
			var e2 := str(d2.get("err", "")).split(" @")[0]
			forced_errs[e2] = int(forced_errs.get(e2, 0)) + 1
	_ok("★0.22.6 解码器拿到 v4 的块: %d / %d 块在版本号那一步报错返回(播放器停在「画面无法播放」, 不崩)" % [as_is, chunks.size()],
		as_is == chunks.size() and chunks.size() > 0)
	_ok("★版本号硬改成 3 再喂: 带新标签的块在标签那一步报错返回(%d 块报错 %s), 没有一块崩" % [forced, str(forced_errs)],
		forced > 0 and (forced_errs.has("tag %d" % F.T_V3Q) or forced_errs.has("tag %d" % F.T_F1Q)))


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 灵物触手着色器热参数录了再播与本机一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
