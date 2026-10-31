extends Node
## 探针(2026-10-31 周日彩排 P14): 对阵图点「观赛」(开播)后 15~30 秒空场地。
## 用彩排那一场的真录像(PROBE_RPL = 本机缓存的 .rpl)+ 内测服上**真的状态流**(只读 GET, TURTLE_STREAM_BASE),
##   走真入口 StreamWatch.enter(开播会话 = 对阵图 open_replay 挂的那一份), 真战斗场 + 真守卫, 每 0.25 秒打一行:
##   进场后多少毫秒 / 守卫在不在等 / 目标步 / 播放器 state / paused / 已拉块数 / 已应用步 / 幕布状态 / 屏上那句话。
## env: PROBE_RPL(绝对路径) · LATE(进场时距翻面已过几秒, 默认 6) · RUN_SEC(默认 40)
## 跑法: TURTLE_SUPABASE=" " TURTLE_STREAM_BASE=https://stream.turtlearena.xyz/beta/streams PROBE_RPL=... <godot> --headless --audio-driver Dummy --path . res://tests/_probe_premiere_wait.tscn

const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")


func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k).strip_edges()
	return s if s != "" else d


func _guard() -> Node:
	for c in get_tree().root.get_children():
		if c is SW.Guard:
			return c
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	GameState.tutorial_active = false
	GameState.test_mode = true
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var raw := FileAccess.get_file_as_bytes(_env("PROBE_RPL", ""))
	var rec: Dictionary = ReplayRecorder.decode(raw)
	print("=== 探针 P14  录像 id=%s 版本=%s seed=%d end=%s ===" % [str(rec.get("id", "")), str(rec.get("client_version", "")),
		int(rec.get("seed", 0)), str(rec.get("end", {}))])
	var evs: Array = []
	for e in rec.get("events", []):
		if e is Dictionary:
			evs.append("%s@%d" % [str(e.get("k", "")), int(e.get("s", 0))])
	print("  录像事件: ", " ".join(PackedStringArray(evs)))
	print("  流地址: ", SW.base_url())
	var late := float(_env("LATE", "6"))
	var run_sec := float(_env("RUN_SEC", "40"))
	var now := int(Time.get_unix_time_from_system())
	LS.pending = {"kind": LS.KIND_PREMIERE, "flip_ts": now - int(late), "srv_now": now,
		"t_ms": Time.get_ticks_msec(), "key": "probe:%d" % now}
	var t0 := Time.get_ticks_msec()
	var w := SW.enter(null, rec, "", {"l": "甲", "r": "乙"}, {})
	print("  SW.enter → 「%s」 会话=%s" % [w, str(SW.current.get("kind", ""))])
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(b)
	get_tree().current_scene = b
	print("  战斗场建好: %d ms" % (Time.get_ticks_msec() - t0))
	var last := ""
	var first_unit_ms := -1
	var fight_ms := -1
	var unpaused_ms := -1
	while Time.get_ticks_msec() - t0 < int(run_sec * 1000.0):
		await get_tree().create_timer(0.25).timeout
		var ms := Time.get_ticks_msec() - t0
		var rp = b.get("_replay")
		var p = rp.player if rp != null else null
		if p == null:
			print("  t=%5d  (播放器还没建)" % ms)
			continue
		var g := _guard()
		var prem: Dictionary = SW.current.get("premiere", {}) if SW.current.get("premiere", null) is Dictionary else {}
		var tgt: int = SW.premiere_target(prem) if not prem.is_empty() else -1
		var src = p.src
		var nunits: int = (b._units as Array).size()
		if first_unit_ms < 0 and nunits > 0:
			first_unit_ms = ms
		if fight_ms < 0 and str(b._dl_state) == "fight":
			fight_ms = ms
		if unpaused_ms < 0 and not bool(p.paused) and str(p.state) == "playing":
			unpaused_ms = ms
		var line := "guard_wait=%s paused=%s state=%s 屏=「%s」 dl=%s units=%d" % [
			str(g._prem_pending) if g != null else "-", str(p.paused), str(p.state), p.status_text(), str(b._dl_state), nunits]
		var nums := "tgt=%d first=%d applied=%d head=%.0f 块=%d/%s req=%d" % [tgt, int(p.first_step), int(p.applied), float(p.head),
			int(src.fetched()) if src != null and src.has_method("fetched") else -1, str(src.state) if src != null else "-",
			int(src.requests) if src != null else -1]
		if line != last or ms % 2000 < 250:
			print("  t=%5d  %s  %s" % [ms, line, nums])
			last = line
	print("RESULT late=%.0f  播放器解除暂停=%d ms  第一个单位=%d ms  开打(fight)=%d ms" % [late, unpaused_ms, first_unit_ms, fight_ms])
	get_tree().quit(0)
