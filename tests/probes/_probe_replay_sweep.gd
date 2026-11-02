extends Node
## _probe_replay_sweep —— 把一批真实录像逐场重放到底, 记「放完没有 / 分叉没有 / 分叉在哪一步」(2026-10-10 用户「回放你自己测一下」)。
## 探针, 不进门禁(文件名下划线开头)。
##
##   PROBE_MODE=local  逐场放本机 user://replays/ 里的录像(APPDATA 指向某个模拟号存档的副本)
##   PROBE_MODE=board  取本周周六赛况板上所有对局, 逐场走 ReplayFetcher.open(本机没有就去服务端取) —— 别的玩家点「观看」走的就是这条
##   PROBE_MAX=N       最多放几场(默认 999)
##   PROBE_SPEED=4     倍速(1/2/4, 默认 4; 校验点照样逐个比, 倍速不改步长)
##
## 输出: 每场一行 `[SWEEP] id | 结果 | 步数 | 校验点 | 分叉`, 最后一行汇总。
## ★本节点不当 current_scene: 每场都要换进战斗场, 当 current_scene 会被换场景一起释放。

const RR := preload("res://scripts/systems/replay/replay_recorder.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const MAX_FRAMES_PER := 40000

var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	## 让出 current_scene: 挂一个空节点当它, 自己留在 root 下活过换场景。
	var holder := Node.new()
	holder.name = "SweepHolder"
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	var mode := OS.get_environment("PROBE_MODE").strip_edges()
	var cap := int(OS.get_environment("PROBE_MAX")) if OS.get_environment("PROBE_MAX") != "" else 999
	var spd := float(OS.get_environment("PROBE_SPEED")) if OS.get_environment("PROBE_SPEED") != "" else 4.0
	print("[SWEEP] mode=%s cap=%d speed=%.0f version=%s" % [mode, cap, spd, RR.client_version()])
	var ids: Array = []
	if mode == "board" or mode == "download":
		ids = await _board_ids()
	else:
		ids = _local_ids()
	## PROBE_ID=<id>: 只放这一场(批量时每场一个进程 —— 同一进程连放, 第二场起换场景没切过去, 量到的是上一场)。
	var only := OS.get_environment("PROBE_ID").strip_edges()
	if only != "":
		ids = [only] if ids.has(only) or mode == "board" else []
	if OS.get_environment("PROBE_DUMP") != "":
		for id in ids:
			var r: Dictionary = RR.load_record(str(id))
			var st: Dictionary = r.get("state", {}) if r.get("state", null) is Dictionary else {}
			var dg = st.get("dual_ghost", {})
			var opp_tr = (dg as Dictionary).get("trainer", (dg as Dictionary).get("trainer_skill", "?")) if dg is Dictionary else "?"
			print("[DUMP] %s ver=%s keys=%s" % [str(id).left(8), str(r.get("client_version", "")), str(r.keys())])
			print("[DUMP]   my_trainer=%s opp_trainer=%s opp_leaders=%s my_leaders=%s end=%s" % [
				str(st.get("trainer_skill", st.get("trainer_skills", "?"))), str(opp_tr),
				str((dg as Dictionary).get("leaders", "?")) if dg is Dictionary else "?", str(st.get("season_leaders", "?")), str(r.get("end", {}))])
			if dg is Dictionary:
				print("[DUMP]   dual_ghost keys=%s" % str((dg as Dictionary).keys()))
		get_tree().quit(0)
		return
	## PROBE_MODE=download: 只下载(同一进程、同一账号, 顺序取) —— 多进程共用一份账号副本会让服务端判「凭证被重复使用」而作废会话。
	if mode == "download":
		var ok_n := 0
		for id in ids:
			if RF.local_available(str(id)):
				ok_n += 1
				continue
			var got := [null]
			if not SB.fetch_match_async(str(id), func(r: Dictionary) -> void: got[0] = r):
				print("[DL] %s 发不出" % str(id).left(8))
				continue
			var t0 := Time.get_ticks_msec()
			while got[0] == null and Time.get_ticks_msec() - t0 < 30000:
				await get_tree().process_frame
			var r = got[0]
			if r is Dictionary and str((r as Dictionary).get("err", "")) == "":
				var raw: PackedByteArray = RF.decode_b64(str((r as Dictionary).get("b64", "")))
				if not raw.is_empty():
					RF._cache(str(id), raw)
					ok_n += 1
					continue
			print("[DL] %s 失败 %s" % [str(id).left(8), str(r).left(120)])
		print("[DL] 下载完 %d / %d" % [ok_n, ids.size()])
		get_tree().quit(0)
		return
	if OS.get_environment("PROBE_LIST") != "":
		for id in ids:
			print("[SWEEP-ID] %s" % id)
		get_tree().quit(0)
		return
	print("[SWEEP] 待放 %d 场" % ids.size())
	var n := 0
	for id in ids:
		if n >= cap:
			break
		n += 1
		await _play_one(str(id), spd)
	_summary()
	get_tree().quit(0)


func _local_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open(RR.SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".rpl"):
			out.append(f.get_basename())
	out.sort()
	return out


func _board_ids() -> Array:
	var wk: int = P2C.week_anchor_utc(P2C.now_utc())
	var res = null
	for attempt in range(4):
		SB.ensure_signed_in_async()
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 4000:
			await get_tree().process_frame
		var got := [null]
		if not SB.fetch_gauntlet_board_async(wk, func(r: Dictionary) -> void: got[0] = r):
			print("[SWEEP] 没接后端")
			return []
		var t0 := Time.get_ticks_msec()
		while got[0] == null and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
		res = got[0]
		if res is Dictionary and (res as Dictionary).has("rows"):
			break
		print("[SWEEP] 第 %d 次取赛况板没成: %s" % [attempt + 1, str(res)])
	if not (res is Dictionary) or not (res as Dictionary).has("rows"):
		print("[SWEEP] 取赛况板失败: %s" % str(res))
		return []
	var out: Array = []
	var ver_n := {}
	for r in (res as Dictionary)["rows"]:
		if r is Dictionary:
			out.append(str(r.get("match_id", "")))
			var v := str(r.get("client_version", "?"))
			ver_n[v] = int(ver_n.get(v, 0)) + 1
	print("[SWEEP] 赛况板 %d 场, 版本分布 %s" % [out.size(), str(ver_n)])
	return out


func _battle():
	var cs = get_tree().current_scene
	if cs != null and is_instance_valid(cs) and ("_replay" in cs) and cs.get("_replay") != null:
		return cs
	return null


func _play_one(id: String, spd: float) -> void:
	var t0 := Time.get_ticks_msec()
	var code := ["~", ""]
	var before = get_tree().current_scene
	if OS.get_environment("PROBE_MODE").strip_edges() == "board":
		RF.open(get_tree(), id, func(c: String, m: String) -> void:
			code[0] = c
			code[1] = m)
	else:
		var rec: Dictionary = RR.load_record(id)
		var w: String = RR.play(get_tree(), rec, "", {})
		code[0] = "" if w == "" else "refused"
		code[1] = w
	## 等进战斗场(或被拒)
	var f := 0
	while f < 3000:
		await get_tree().process_frame
		f += 1
		if str(code[0]) not in ["~", ""]:
			break
		var b0 = _battle()
		if b0 != null and b0 != before and b0.get("_replay").is_playing():
			break
	var b = _battle()
	if b == null or not b.get("_replay").is_playing():
		_row(id, "打不开(%s: %s)" % [code[0], code[1]], -1, -1, -1, "")
		return
	var rp = b.get("_replay")
	rp.speed = spd
	f = 0
	while f < MAX_FRAMES_PER and is_instance_valid(b) and not rp.finished and rp.diverged_at < 0:
		await get_tree().process_frame
		f += 1
	if not is_instance_valid(b):
		_row(id, "战斗场中途没了", -1, -1, -1, "")
		return
	var end: Dictionary = rp.rec.get("end", {}) if rp.rec.get("end", null) is Dictionary else {}
	var st := "放完" if rp.finished and rp.diverged_at < 0 else ("分叉" if rp.diverged_at >= 0 else "超时没放完")
	_row(id, st, int(b.get("_sim_step_n")), int(end.get("s", -1)), int(rp.cp_checked),
		("第 %d 步 %s" % [rp.diverged_at, rp.diverge_why]) if rp.diverged_at >= 0 else "")
	print("        用时 %.1f 秒 / %d 帧" % [(Time.get_ticks_msec() - t0) / 1000.0, f])


func _row(id: String, st: String, steps: int, end_s: int, cps: int, why: String) -> void:
	_rows.append({"id": id, "st": st})
	print("[SWEEP] %s | %s | 步 %d/%d | 校验点 %d | %s" % [id.left(8), st, steps, end_s, cps, why])


func _summary() -> void:
	var c := {}
	for r in _rows:
		c[str(r["st"])] = int(c.get(str(r["st"]), 0)) + 1
	print("[SWEEP] 汇总 %d 场: %s" % [_rows.size(), str(c)])
