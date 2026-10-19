extends Node
## verify_stream_parity.gd — 逐帧直播 S2: 「本机直接跑」与「录流再播放」画面一致。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「画面一致」/ R2; 容差的来历见方案书 §2.3「S2 parity 剖面」。
##
## 同一进程里先原生跑一遍(同时录流, 块留在内存), 在若干采样时刻拍快照; 再建一个播放模式的战斗场按流播,
## 在**同一批步号**拍同样的快照, 逐项比:
##   · 采样步(服务器每 2 步跑一次渲染步、采一次样的那些步, 每秒取一个):
##       单位: 集合相同; 位置 / 高度 / 血 / 盾 / 最大血 在量化容差内, 存活完全相同
##       镜像节点: id 集合相同; 类名 / 显隐 / 帧号 / 贴图 / 网格完全相同(程序贴图 / 程序网格比内容签名: 像素 / 顶点, S3); 位置 / 旋转 / 缩放 / 颜色在量化容差内
##       `_world` 全量普查(按类名计数, 含地图 / 单位外观 / 手机渲染步按状态造的特效): 完全相同
##   · 采样步后一步(两次采样中间, 手机在插值): 单位位置与原生 sim 的差 ≤ 插值容差(剖面量出来的)
##   · 飘字: 整局「新冒出来的飘字 Label 文本」序列完全相同(两边都按 `_ui_layer` 新加的 Label 普查, 不经录流器)
## 覆盖: tests/_stream_jobs.gd 两局(三路打满) + DetScenarios 前 4 个场景。
## ★分母: 每局比过的采样点数、单位数、镜像节点数、飘字数都 > 0; 播放端真的应用了全部步数。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")
const SIM_DT := 1.0 / 60.0
const EVERY := 60                 # 每 60 步(1 秒)取一个采样点
## 量化容差(格式 v2 的量化步长的一半, 再留一点 float32 余量): 位置 1/128、旋转 1/1024、缩放 1/4096、颜色 1/255
const TOL_POS := 0.5 / 128.0 * 1.75   # 三轴合成长度
const TOL_ROT := 0.5 / 1024.0 + 1.0e-5
const TOL_SCL := 0.5 / 4096.0 + 1.0e-5
const TOL_COL := 0.5 / 255.0 + 1.0e-5
const TOL_UNIT := 0.01            # 单位字段 float32 往返(位置是像素坐标, 血量上万)
## 插值容差(两次采样中间那一步, 单位位置与原生 sim 的差; 像素坐标)。剖面见方案书 §2.3:
##   两局 + det 15 场景中位 0、p99 ≤ 3.6、最大 10.0(det ⑨ 骰子龟冲刺, 两次采样之间走了 ≈ 20 像素的弧线, 线性插值差半段)。
##   判据是「≤ 半段位移 + 0.5」(线性插值的形状), 外加一道最大 12 像素的硬顶。
const TOL_INTERP := 12.0
const TOL_MID := 0.01
const DET_N := 15
const TOL_FLOAT_STEP := 2

var _pl: StreamPlayer = null
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
	var only := OS.get_environment("S2_ONLY")
	var jobs := [["镜像快照局", "m"], ["真实快照局(最重)", "h"]]
	for jj in jobs:
		if only != "" and only != str(jj[1]):
			continue
		var job: Dictionary = J.mirror(gs) if str(jj[1]) == "m" else J.heavy()
		var nat: Dictionary = await P.record_referee(self, job, func(n: int) -> bool: return n % EVERY <= 2)
		var res: Dictionary = nat["res"]
		_ok("分母 · %s 原生一遍三路打满、录到块" % str(jj[0]), bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3
			and (res.get("stream_chunks", []) as Array).size() > 100, "开打 %d 块 %d" % [int(res.get("fights", 0)), (res.get("stream_chunks", []) as Array).size()])
		await _play_and_compare(str(jj[0]), res.get("stream_chunks", []), res.get("stream", {}), nat)
	if only == "" or only == "d":
		var k := 0
		var det_n: int = int(OS.get_environment("S2_DET_N")) if OS.get_environment("S2_DET_N") != "" else DET_N
		for sc in SC.all():
			if k >= det_n:
				break
			k += 1
			var nat2: Dictionary = await _record_det(sc as Dictionary)
			await _play_and_compare("det " + str((sc as Dictionary)["tag"]), nat2["chunks"], nat2["meta"], nat2)
	_finish()


## ═══════════════ 播放并逐采样点比 ═══════════════
func _play_and_compare(tag: String, chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	print("=== %s ===" % tag)
	var gs = get_node_or_null("/root/GameState")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var au = get_node_or_null("/root/Audio")
	var muted0: bool = bool(au.mute_sfx) if au != null else false
	if au != null:
		au.mute_sfx = true
	var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}))
	b.set_process(false)
	await get_tree().process_frame      # 建场里有 call_deferred(前景带搬进世界), 原生那边也是隔帧才跑的
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_pl = p
	_ok("分母 · %s 播放模式建起来了(mode=stream, 有播放器)" % tag, p != null and str(b._replay.mode) == "stream")
	if p == null:
		return
	var cur := [-1]
	var floats := {}
	var fl := P._float_hook(floats, cur)
	get_tree().node_added.connect(fl)
	p.on_applied = func(s: int) -> void: cur[0] = s
	var snaps: Dictionary = nat["snaps"]
	var keys: Array = snaps.keys()
	keys.sort()
	var st := {"cmp": 0, "interp": 0, "u_n": 0, "n_n": 0, "u_bad": [], "n_bad": [], "c_bad": [], "i_max": 0.0, "i_list": [],
		"pos_max": 0.0, "rot_max": 0.0, "scl_max": 0.0, "col_max": 0.0, "ux_max": 0.0, "tex_gen": 0, "mesh_proc": 0, "missing_n": 0, "extra_n": 0}
	var ki := 0
	var guard := 0
	p.advance(0.0)
	while ki < keys.size() and p.state != "error" and guard < 200000:
		guard += 1
		var nxt: int = int(keys[ki])
		var hd := int(roundf(p.head))
		if nxt <= hd:
			ki += 1
			continue
		if nxt == hd + 1 and (ki > 0 and int(keys[ki - 1]) == hd):
			p.advance(SIM_DT)
			_cmp_interp(snaps[hd], snaps[nxt], snaps.get(nxt + 1, {}), P.snap_player(p), st)
			p.advance(SIM_DT)
			ki += 1
			continue
		p.advance(2.0 * SIM_DT)
		if int(roundf(p.head)) % 30 == 0:
			await get_tree().process_frame   # 原生裁判一帧推 20~30 步: 隔帧才跑的(queue_free / call_deferred)这边也隔帧跑
		if int(roundf(p.head)) == nxt:
			_cmp(nxt, snaps[nxt], P.snap_player(p), st)
			ki += 1
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		p.advance(2.0 * SIM_DT)
	get_tree().node_added.disconnect(fl)
	print("  [量] %s 播放: 解块 %d / 应用 %d 步 / 镜像建 %d 删 %d 改 %d · 占位 程序贴图 %d 程序网格 %d 其它 %d · 父兜底 %d · 事件 %s · 状态 %s %s" % [tag,
		p.chunks_decoded, p.steps_applied, p.mirror.built, p.mirror.deleted, p.mirror.sets, p.mirror.ph_gen_tex, p.mirror.ph_proc_mesh,
		p.mirror.ph_other, p.mirror.parent_fallback, str(p.events), p.state, p.err])
	print("  [量] %s 换父节点 %d 次 · keyframe 兜底删 %d · 时停全屏层 开过 %d 次(流里 %d 次)、在时停里的采样点 %d · 出处键参数别名 %d" % [tag,
		p.mirror.reparents, p.mirror.kf_dropped, p.mirror.fx_built, int(meta.get("ts_screen", 0)), int(st.get("ts_n", 0)), p.mirror.gen_alias])
	print("  [量] %s 采样点 %d · 单位·点 %d · 节点·点 %d · 误差上限 位置 %.5f 旋转 %.6f 缩放 %.6f 颜色 %.5f 单位 %.5f · 程序贴图 节点·点 %d / 程序网格 节点·点 %d(S3 起逐个比内容)" % [tag,
		int(st["cmp"]), int(st["u_n"]), int(st["n_n"]), float(st["pos_max"]), float(st["rot_max"]), float(st["scl_max"]), float(st["col_max"]),
		float(st["ux_max"]), int(st["tex_gen"]), int(st["mesh_proc"])])
	var il: Array = st["i_list"]
	il.sort()
	var p99: float = float(il[int(il.size() * 0.99)]) if not il.is_empty() else 0.0
	var p50: float = float(il[int(il.size() * 0.5)]) if not il.is_empty() else 0.0
	print("  [量] %s 插值剖面(采样中间一步, 单位位置差, 像素): 点 %d 中位 %.3f p99 %.3f 最大 %.3f" % [tag, il.size(), p50, p99, float(st["i_max"])])
	var steps := int(meta.get("steps", 0))
	_ok("分母 · %s 播放端解了全部块、应用了全部步(%d / %d)、播到结尾" % [tag, p.steps_applied, steps],
		p.chunks_decoded == chunks.size() and p.steps_applied == steps and p.state == "ended", "%s %s" % [p.state, p.err])
	_ok("分母 · %s 比过的采样点 %d、单位·点 %d、节点·点 %d、插值点 %d" % [tag, int(st["cmp"]), int(st["u_n"]), int(st["n_n"]), int(st["interp"])],
		int(st["cmp"]) >= maxi(3, steps / EVERY - 1) and int(st["u_n"]) > 0 and int(st["n_n"]) > 0 and int(st["interp"]) >= maxi(3, steps / EVERY - 2))
	_ok("★★%s 单位: 集合 / 存活一致, 位置 / 血 / 盾在容差内" % tag, (st["u_bad"] as Array).is_empty(), str((st["u_bad"] as Array).slice(0, 4)))
	_ok("★★%s 镜像节点: id 集合 / 类名 / 显隐 / 帧号 / 贴图一致, 变换与颜色在量化容差内" % tag, (st["n_bad"] as Array).is_empty(),
		"缺 %d 多 %d · %s" % [int(st["missing_n"]), int(st["extra_n"]), str((st["n_bad"] as Array).slice(0, 4))])
	_ok("★★%s _world 全量普查(按类名计数)一致" % tag, (st["c_bad"] as Array).is_empty(), str((st["c_bad"] as Array).slice(0, 3)))
	## S3: 占位清零 —— 程序贴图 / 程序网格全部按出处键现生成(占位次数 = 0, 生成失败 = 0); 分母: 现生成过 > 0 次
	_ok("分母 · %s 程序网格比过内容的节点·点 %d > 流里还没发新一代(按自己频率发)而没比的 %d" % [tag, int(st["mesh_proc"]), int(st.get("mesh_lag", 0))],
		int(st["mesh_proc"]) >= int(st.get("mesh_lag", 0)))
	_ok("★%s 时停全屏层: 手机开过的次数 %d = 流里服务器时停次数 %d" % [tag, p.mirror.fx_built, int(meta.get("ts_screen", 0))],
		p.mirror.fx_built == int(meta.get("ts_screen", 0)))
	_ok("★★%s 占位 = 0: 程序贴图 %d / 程序网格 %d / 其它 %d / 生成失败 %d %s; 现生成 %d 次、复用 %d 次" % [tag, p.mirror.ph_gen_tex,
		p.mirror.ph_proc_mesh, p.mirror.ph_other, p.mirror.gen_fail, str(p.mirror.gen_fail_ids), p.mirror.gen_built, p.mirror.gen_reused],
		p.mirror.ph_gen_tex == 0 and p.mirror.ph_proc_mesh == 0 and p.mirror.ph_other == 0 and p.mirror.gen_fail == 0 and p.mirror.gen_built > 0)
	_ok("★%s 插值: 采样中间一步手机插出的 = 前后两次采样的中点(偏离 > %.2f 的 %d / %d 点, 最大偏离 %.4f), 与原生真位置差最大 %.3f ≤ %.1f 像素" % [tag,
		TOL_MID, int(st.get("i_over", 0)), int(st.get("i_seg", 0)), float(st.get("i_mid_max", 0.0)), float(st["i_max"]), TOL_INTERP],
		int(st.get("i_over", 0)) == 0 and int(st.get("i_seg", 0)) > 0 and float(st["i_max"]) <= TOL_INTERP)
	var fa: Array = _flat(nat["floats"])
	var fb: Array = _flat(floats)
	## 文本逐条相同; 步号允许差 TOL_FLOAT_STEP(渲染步里冒的那几种: 原生在采样回调前、播放在应用后各记一次步号)
	var first := -1
	for i in range(mini(fa.size(), fb.size())):
		if str(fa[i][1]) != str(fb[i][1]) or absi(int(fa[i][0]) - int(fb[i][0])) > TOL_FLOAT_STEP:
			first = i
			break
	if OS.get_environment("S2_DIAG") != "":
		var ma := {}
		for e in fa:
			ma[str(e[1])] = int(ma.get(str(e[1]), 0)) + 1
		for e in fb:
			ma[str(e[1])] = int(ma.get(str(e[1]), 0)) - 1
		var dd := {}
		for k in ma:
			if int(ma[k]) != 0:
				dd[k] = ma[k]
		print("    [诊断] 飘字文本差(原生 - 播放): ", dd)
		for i in range(maxi(0, first - 3), mini(fa.size(), first + 6)):
			print("    [诊断] #%d 原生 %s / 播放 %s" % [i, str(fa[i]), str(fb[i]) if i < fb.size() else "-"])
		if first >= 0:
			var fs: int = int(fa[first][0])
			var stt := {}
			for c in chunks:
				var d := StreamFormat.parse_chunk(c, stt)
				for stp in (d.get("list", []) as Array):
					if absi(int(stp[0]) - fs) <= 2:
						for op in (stp[2] as Array):
							if int(op[0]) == StreamFormat.OP_EVENT and str(op[1]) in ["float", "dotacc"]:
								print("    [诊断] 流 步%d %s %s" % [int(stp[0]), str(op[1]), str(op[2])])
	_ok("★★%s 飘字序列一致(原生 %d 条 / 播放 %d 条)" % [tag, fa.size(), fb.size()], fa.size() == fb.size() and first < 0 and fa.size() > 0,
		"第一处不同 #%d: %s / %s" % [first, str(fa[first]) if first >= 0 else "", str(fb[first]) if first >= 0 else ""])
	_ok("%s 地图种子 / 主题一致" % tag, not p.seed_mismatch() and not p.theme_mismatch(), "%s / %s" % [p._theme_seen, ArenaTheme.active])
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true
	if au != null:
		au.mute_sfx = muted0


func _flat(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	var out: Array = []
	for k in ks:
		for t in (d[k] as Array):
			out.append([int(k), str(t)])
	return out


func _cmp(s: int, a: Dictionary, b: Dictionary, st: Dictionary) -> void:
	st["cmp"] = int(st["cmp"]) + 1
	var ua: Dictionary = a["units"]
	var ub: Dictionary = b["units"]
	for idx in ua:
		st["u_n"] = int(st["u_n"]) + 1
		if not ub.has(idx):
			(st["u_bad"] as Array).append("步%d 单位%d 播放端没有" % [s, idx])
			continue
		var x: Array = ua[idx]
		var y: Array = ub[idx]
		var dpos: float = (x[0] as Vector2).distance_to(y[0])
		var dh: float = absf(float(x[1]) - float(y[1]))
		var dhp: float = absf(float(x[2]) - float(y[2])) / maxf(1.0, absf(float(x[2])))
		var dsh: float = absf(float(x[3]) - float(y[3])) / maxf(1.0, absf(float(x[3])))
		var dmx: float = absf(float(x[5]) - float(y[5])) / maxf(1.0, absf(float(x[5])))
		var m := maxf(maxf(dpos / maxf(1.0, (x[0] as Vector2).length()), dh), maxf(dhp, maxf(dsh, dmx)))
		st["ux_max"] = maxf(float(st["ux_max"]), m)
		if bool(x[4]) != bool(y[4]) or m > TOL_UNIT:
			(st["u_bad"] as Array).append("步%d 单位%d 原生%s 播放%s" % [s, idx, str(x), str(y)])
	for idx in ub:
		if not ua.has(idx):
			(st["u_bad"] as Array).append("步%d 单位%d 原生没有" % [s, idx])
	var na: Dictionary = a["nodes"]
	var nb: Dictionary = b["nodes"]
	for id in na:
		st["n_n"] = int(st["n_n"]) + 1
		if not nb.has(id):
			st["missing_n"] = int(st["missing_n"]) + 1
			if OS.get_environment("S2_DIAG") != "" and int(st["missing_n"]) <= 6:
				var pn = _pl.mirror.nodes.get(int(id))
				print("    [诊断] 原生同步有 41? %s  有 40? %s; 原生 %d = %s" % [str(na.has(41)), str(na.has(40)), int(id), str(na[id])])
				print("    [诊断] 缺节点 %d: 镜像表里 %s 有效 %s 在树 %s 删除排队 %s 父 %s" % [int(id), str(_pl.mirror.nodes.has(int(id))),
					str(pn != null and is_instance_valid(pn)), str(pn != null and is_instance_valid(pn) and (pn as Node).is_inside_tree()),
					str(pn != null and is_instance_valid(pn) and (pn as Node).is_queued_for_deletion()),
					str((pn as Node).get_parent()) if pn != null and is_instance_valid(pn) else "-"])
			(st["n_bad"] as Array).append("步%d 节点%d(%s) 播放端没有" % [s, id, str(na[id][0])])
			continue
		var x: Array = na[id]
		var y: Array = nb[id]
		var why := ""
		if x[0] != y[0]:
			why = "类 %s/%s" % [x[0], y[0]]
		elif x[1] != y[1]:
			why = "显隐 %s/%s" % [x[1], y[1]]
		elif int(x[5]) != int(y[5]):
			why = "帧 %d/%d" % [int(x[5]), int(y[5])]
		elif str(x[6]) != str(y[6]):
			why = "贴图 %s/%s" % [x[6], y[6]]
		elif str(x[9]) != str(y[9]) and str(x[9]) != "<lag>":
			why = "网格 %s/%s" % [x[9], y[9]]
		## S3 起不再豁免: 程序贴图 / 程序网格按出处键现生成, 比**内容签名**(像素 / 顶点)必须相同。下面只计数(分母)。
		if str(x[6]).begins_with("<gen:"):
			st["tex_gen"] = int(st["tex_gen"]) + 1
		if str(x[9]).begins_with("<proc:"):
			st["mesh_proc"] = int(st["mesh_proc"]) + 1
		if str(x[9]) == "<lag>":
			st["mesh_lag"] = int(st.get("mesh_lag", 0)) + 1
		if why == "" and x[2] != null:
			var dp: float = (x[2] as Vector3).distance_to(y[2])
			var dr := 0.0
			for ax in range(3):
				dr = maxf(dr, absf(angle_difference(float((x[3] as Vector3)[ax]), float((y[3] as Vector3)[ax]))))
			var ds: float = ((x[4] as Vector3) - (y[4] as Vector3)).abs()[((x[4] as Vector3) - (y[4] as Vector3)).abs().max_axis_index()]
			st["pos_max"] = maxf(float(st["pos_max"]), dp)
			st["rot_max"] = maxf(float(st["rot_max"]), dr)
			st["scl_max"] = maxf(float(st["scl_max"]), ds)
			if dp > TOL_POS:
				why = "位置差 %.5f %s/%s" % [dp, str(x[2]), str(y[2])]
			elif dr > TOL_ROT:
				why = "旋转差 %.6f" % dr
			elif ds > TOL_SCL:
				why = "缩放差 %.6f %s/%s %s" % [ds, str(x[4]), str(y[4]), str(x[8])]
		if why == "" and x[7] != null and y[7] != null:
			var c1: Color = x[7]
			var c2: Color = y[7]
			var dc := maxf(maxf(absf(c1.r - c2.r), absf(c1.g - c2.g)), maxf(absf(c1.b - c2.b), absf(c1.a - c2.a)))
			st["col_max"] = maxf(float(st["col_max"]), dc)
			if dc > TOL_COL:
				why = "颜色差 %.5f" % dc
		if why != "":
			(st["n_bad"] as Array).append("步%d 节点%d(%s) %s" % [s, id, str(x[0]), why])
			if OS.get_environment("S2_DIAG") != "" and (st["n_bad"] as Array).size() <= 2 and a.has("own") and (a["own"] as Dictionary).has(id):
				var oi := int(str(a["own"][id]).split(" ")[0])
				print("    [诊断] 节点%d 主人 %s 原生 %s / 播放 %s" % [id, str(a["own"][id]), str(ua[oi][6]) if ua.has(oi) else "-", str(ub[oi][6]) if ub.has(oi) else "-"])
	for id in nb:
		if not na.has(id):
			st["extra_n"] = int(st["extra_n"]) + 1
			(st["n_bad"] as Array).append("步%d 节点%d(%s) 原生没有" % [s, id, str(nb[id][0])])
	## S3: 时停全屏层(CanvasLayer, 不在 _world 里): 服务器在时停里 ⇔ 手机全屏层开着
	if bool(a.get("ts_screen", false)):
		st["ts_n"] = int(st.get("ts_n", 0)) + 1
	if bool(a.get("ts_screen", false)) != bool(b.get("ts_screen", false)):
		(st["n_bad"] as Array).append("步%d 时停全屏层 原生 %s / 播放 %s" % [s, str(a.get("ts_screen")), str(b.get("ts_screen"))])
	var ca: Dictionary = a["census"]
	var cb: Dictionary = b["census"]
	var diff := {}
	for k in ca:
		if int(ca[k]) != int(cb.get(k, 0)):
			diff[k] = [int(ca[k]), int(cb.get(k, 0))]
	for k in cb:
		if not ca.has(k):
			diff[k] = [0, int(cb[k])]
	if not diff.is_empty():
		(st["c_bad"] as Array).append("步%d %s" % [s, str(diff)])
		if a.has("loose") and (st["c_bad"] as Array).size() <= 2:
			var la: Dictionary = a["loose"]
			var lb: Dictionary = b["loose"]
			for k in la:
				if int(la[k]) != int(lb.get(k, 0)):
					print("    [诊断] 步%d 非镜像 %s: 原生 %d / 播放 %d" % [s, k, int(la[k]), int(lb.get(k, 0))])
			for k in lb:
				if not la.has(k):
					print("    [诊断] 步%d 非镜像 %s: 原生 0 / 播放 %d" % [s, k, int(lb[k])])
			for idx in ua:
				print("    [诊断] 步%d 单位%d 原生 %s / 播放 %s" % [s, idx, str(ua[idx][6]), str(ub[idx][6]) if ub.has(idx) else "-"])


## 两次采样中间那一步, 两件事分开量:
##   ① 手机插得对不对: 插出来的位置 == 原生前后两次采样的中点(只差 float32 往返, 判 ≤ 0.01 像素);
##   ② 插值本身丢了多少: 中点 vs 原生 sim 这一步的真位置(拐弯 / 变速 / 冲刺来回时必然有差) —— 打剖面, 只设一道硬顶。
func _cmp_interp(a0: Dictionary, a: Dictionary, a2: Dictionary, b: Dictionary, st: Dictionary) -> void:
	st["interp"] = int(st["interp"]) + 1
	var ua: Dictionary = a["units"]
	var ub: Dictionary = b["units"]
	var u0: Dictionary = a0["units"]
	var u2: Dictionary = a2.get("units", {})
	for idx in ua:
		if not ub.has(idx) or not bool(ua[idx][4]):
			continue
		var d: float = (ua[idx][0] as Vector2).distance_to(ub[idx][0])
		(st["i_list"] as Array).append(d)
		if u0.has(idx) and u2.has(idx) and bool(u0[idx][4]) and bool(u2[idx][4]):
			var mid: Vector2 = (u0[idx][0] as Vector2).lerp(u2[idx][0], 0.5)
			st["i_seg"] = int(st.get("i_seg", 0)) + 1
			var dm: float = mid.distance_to(ub[idx][0])
			st["i_mid_max"] = maxf(float(st.get("i_mid_max", 0.0)), dm)
			if dm > TOL_MID and d > TOL_MID:   # 这一步恰是 keyframe(全量重发)时手机直接拿到真值, 也算对
				st["i_over"] = int(st.get("i_over", 0)) + 1
				if OS.get_environment("S2_DIAG") != "":
					print("    [诊断] 插值不在中点: 单位%d 前 %s 后 %s 原生 %s 播放 %s" % [int(idx), str(u0[idx][0]), str(u2[idx][0]), str(ua[idx][0]), str(ub[idx][0])])
		if OS.get_environment("S2_DIAG") != "" and d > 4.0:
			print("    [诊断] 插值差 %.2f 单位%d 原生 %s 播放 %s" % [d, int(idx), str(ua[idx][0]), str(ub[idx][0])])
		st["i_max"] = maxf(float(st["i_max"]), d)


## ═══════════════ det 场景: 与 verify_stream_whitelist_alarm 同一套建场, 逐步推 sim + 录流 ═══════════════
func _record_det(sc: Dictionary) -> Dictionary:
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	var s = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(s)
	## ★先关 _process 再等帧: 调试场开场会恢复上次存的布置(debug_setup.json), 那几帧的渲染步会按旧布置造跟随特效
	##   (忍者标记), `_edit_clear` 清单位时不清它们 ⇒ 原生世界里多出几个孤儿节点, 而它们在录流开始之前、流里没有。
	s.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	## ★录流器在摆兵之前就开, 摆兵 + 开打算进第 1 步(与裁判机同形: 那边从 _ready 起一切都在 sim 步里发生) ——
	##   否则开打前就建好的节点(海盗船、直升机、标记)在流里根本没有, 手机自然画不出来。
	var rec := StreamRecorder.new(s, {"keep": true})
	rec.start()
	var snaps := {}
	var floats := {}
	var cur := [-1]
	rec.on_sampled = func(st: int) -> void:
		cur[0] = st
		if rec._step_n % EVERY <= 2:
			snaps[st] = P.snap_native(rec)
	var fl := P._float_hook(floats, cur)
	get_tree().node_added.connect(fl)
	rec.pre_step()
	var lo: Dictionary = sc.get("loadouts", {})
	if not lo.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		for k in lo:
			gs2.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	s.set_process(false)
	for i in range(int(sc["frames"])):
		if i % 60 == 0 and i > 0:
			await get_tree().process_frame
		if i > 0:
			rec.pre_step()
		s._sim_step(SIM_DT, float(s._hitstop) > 0.0, not (s._timestop._ts_active as Array).is_empty())
		rec.post_step()
	get_tree().node_added.disconnect(fl)
	var m: Dictionary = rec.finish()
	var seed := int(s._battle_rng.seed)
	OS.set_environment("TURTLE_SEED", "")
	s.queue_free()
	RB.DEBUG_EDIT = false
	await get_tree().process_frame
	await get_tree().process_frame
	return {"chunks": rec.chunks, "meta": m, "snaps": snaps, "floats": floats, "state": {}, "seed": seed}


func _finish() -> void:
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 录流再播放与本机直接跑在采样点一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
