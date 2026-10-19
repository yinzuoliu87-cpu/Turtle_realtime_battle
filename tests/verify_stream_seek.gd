extends Node
## verify_stream_seek.gd — 逐帧直播 S2: 从中间的 keyframe 跳进去, 画面与顺着播到同一步一致。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「缓冲与追帧 … keyframe 跳转后的画面和顺着播到同一步时一致」。
##
## 同一份流(两局: 镜像快照局 / 最重那局, 都是三路打满)播两遍:
##   A 顺播: 从头按 2 步一帧播到目标步 S, 拍快照; 再接着播 600 步到 S+600 再拍一次。
##   B 跳播: 新建一个播放模式的战斗场, `seek(S)`(从 S 之前最近的 keyframe 块解起, 快进不放事件), 拍快照; 再接着播到 S+600 拍一次。
## B 先跳到目标后面约 1800 步、再跳回目标(第二次跳转要把第一次的状态清干净)。
## 目标步取在 keyframe 块之后 37 步、跨换路的几处(第一路中段 / 第二路 / 终极路), 避开恰好落在 keyframe 上(那样测不到「keyframe 之后的普通块也解得开」)。
## 比: 单位(位置 / 高度 / 血 / 盾 / 存活 / 最大血)完全相等; 镜像节点 id 集合 / 类名 / 显隐 / 帧号 / 贴图 / 变换 / 颜色完全相等;
##   `_world` 全量普查(按类名计数)相等。
## ★分母: 跳播真的从 keyframe 解起(解块数 < 顺播)、目标步上单位 > 0、镜像节点 > 0。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
const SIM_DT := 1.0 / 60.0
const AFTER := 600

var _fail := 0
var _dec_first := 0
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
	for jj in [["镜像快照局", "m"], ["真实快照局(最重)", "h"]]:
		var job: Dictionary = J.mirror(gs) if str(jj[1]) == "m" else J.heavy()
		var nat: Dictionary = await P.record_referee(self, job, func(_n2: int) -> bool: return false)
		var res: Dictionary = nat["res"]
		var chunks: Array = res.get("stream_chunks", [])
		_ok("分母 · %s 录到三路打满的流(%d 块)" % [str(jj[0]), chunks.size()], bool(res.get("ok", false)) and chunks.size() > 100)
		var first := int((res.get("stream", {}) as Dictionary).get("first_step", 1))
		var targets: Array = []
		for kc in [10, 60, 110]:
			if kc * F.CHUNK_STEPS + 37 + AFTER < int((res.get("stream", {}) as Dictionary).get("steps", 0)):
				targets.append(first + kc * F.CHUNK_STEPS + 37)   # first + 37 是奇数偏移 ⇒ 渲染采样步(见 verify_stream_parity)
		for tgt in targets:
			await _one("%s 跳到第 %d 步" % [str(jj[0]), int(tgt)], chunks, res.get("stream", {}), nat, int(tgt))
	_finish()


func _one(tag: String, chunks: Array, meta: Dictionary, nat: Dictionary, tgt: int) -> void:
	print("=== %s ===" % tag)
	var backup: Dictionary = ReplayRecorder.capture_all()
	## A 顺播
	var a: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}))
	a.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var pa: StreamPlayer = a._replay.player
	pa.advance(0.0)
	var sa: Array = []
	for want in [tgt, tgt + AFTER]:
		while int(roundf(pa.head)) < want and pa.state != "error" and pa.state != "ended":
			pa.advance(minf(2.0, float(want) - pa.head) * SIM_DT)
			if int(roundf(pa.head)) % 30 == 0:
				await get_tree().process_frame
		await get_tree().process_frame
		sa.append(P.snap_player(pa))
	var dec_a := pa.chunks_decoded
	a.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore(backup)
	## B 跳播
	var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}))
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var pb: StreamPlayer = b._replay.player
	## 先跳到后面再跳回来: 第二次跳转要把第一次留下的镜像 / 代理 / 手机自造的特效全清掉(拖进度条来回拖就是这样)
	var far := mini(tgt + 1837, int(meta.get("last_step", tgt)) - 10)
	var ok_seek := pb.seek(far)
	_dec_first = pb.chunks_decoded
	for _i in range(3):
		await get_tree().process_frame
	ok_seek = pb.seek(tgt) and ok_seek
	await get_tree().process_frame
	var sb: Array = [P.snap_player(pb)]
	var dec_seek := pb.chunks_decoded - _dec_first
	while int(roundf(pb.head)) < tgt + AFTER and pb.state != "error" and pb.state != "ended":
		pb.advance(minf(2.0, float(tgt + AFTER) - pb.head) * SIM_DT)
		if int(roundf(pb.head)) % 30 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	sb.append(P.snap_player(pb))
	_ok("分母 · %s 跳播从 keyframe 解起(跳到时解了 %d 块 < 顺播 %d 块)、目标步上有单位 %d 个 / 镜像节点 %d 个" % [tag, dec_seek, dec_a,
		(sb[0]["units"] as Dictionary).size(), (sb[0]["nodes"] as Dictionary).size()],
		ok_seek and dec_seek < dec_a and dec_seek <= F.KEY_CHUNKS + 1 and (sb[0]["units"] as Dictionary).size() > 0
		and (sb[0]["nodes"] as Dictionary).size() > 0 and pb.seeks == 2)
	for i in range(2):
		var at := tgt + i * AFTER
		var d := _diff(sa[i], sb[i])
		_ok("★★%s: 第 %d 步跳播与顺播一致(单位 / 镜像节点 / 全量普查)" % [tag, at], d.is_empty(), str(d.slice(0, 4)))
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore(backup)


func _diff(x: Dictionary, y: Dictionary) -> Array:
	var out: Array = []
	var ux: Dictionary = x["units"]
	var uy: Dictionary = y["units"]
	if ux.keys().size() != uy.keys().size():
		out.append("单位数 %d / %d" % [ux.size(), uy.size()])
	for k in ux:
		if not uy.has(k) or str((ux[k] as Array).slice(0, 6)) != str((uy[k] as Array).slice(0, 6)):
			out.append("单位%d %s / %s" % [int(k), str((ux[k] as Array).slice(0, 6)), str((uy[k] as Array).slice(0, 6)) if uy.has(k) else "-"])
	var nx: Dictionary = x["nodes"]
	var ny: Dictionary = y["nodes"]
	for k in nx:
		if not ny.has(k):
			out.append("节点%d(%s) 跳播没有" % [int(k), str(nx[k][0])])
		elif str((nx[k] as Array).slice(0, 8)) != str((ny[k] as Array).slice(0, 8)):
			out.append("节点%d %s / %s" % [int(k), str((nx[k] as Array).slice(0, 8)), str((ny[k] as Array).slice(0, 8))])
	for k in ny:
		if not nx.has(k):
			out.append("节点%d(%s) 顺播没有" % [int(k), str(ny[k][0])])
	if str(x["census"]) != str(y["census"]):
		var cd := {}
		for k in x["census"]:
			if int(x["census"][k]) != int((y["census"] as Dictionary).get(k, 0)):
				cd[k] = [x["census"][k], (y["census"] as Dictionary).get(k, 0)]
		for k in y["census"]:
			if not (x["census"] as Dictionary).has(k):
				cd[k] = [0, y["census"][k]]
		if not cd.is_empty():
			out.append("普查 %s" % str(cd))
	return out


func _restore(backup: Dictionary) -> void:
	var gs = get_node_or_null("/root/GameState")
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true


func _finish() -> void:
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — keyframe 跳转与顺播到同一步一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
