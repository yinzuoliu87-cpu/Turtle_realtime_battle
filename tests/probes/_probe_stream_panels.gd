extends Node
## _probe_stream_panels.gd —— 11-03 用户「怎么对局内所有的信息系统、统计系统全崩掉了？」
## 拿正式服当天一局积分赛的真实状态流（.out/streamchk/*.bin + end.json，裁判机 0.22.7 录的），
## 按「跟播自己这一局」的入口形状在本机播放，播到对局中段后像玩家那样：
##   ① 点每只单位开详情面板（_hud._show_unit_info_panel）→ 读回面板里的全部文字
##   ② 点 📊 开伤害统计（_on_dmg_stats_toggle）→ 读回各行数字
## 同时把单位身上的关键字段打出来，看播放端还原的单位缺什么。探针，不进门禁。
## 跑法：STREAM_DIR=<chunks 目录> STREAM_SEED=<种子> <godot> --headless --audio-driver Dummy --path . res://tests/probes/_probe_stream_panels.tscn --quit-after 200000
const SIM_DT := 1.0 / 60.0

func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	var dir := OS.get_environment("STREAM_DIR")
	var seed := int(OS.get_environment("STREAM_SEED"))
	var chunks: Array = []
	var i := 0
	while FileAccess.file_exists(dir.path_join("%06d.bin" % i)):
		chunks.append(FileAccess.get_file_as_bytes(dir.path_join("%06d.bin" % i)))
		i += 1
	var meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("end.json")))
	print("[PROBE] chunks=%d meta=%s seed=%d" % [chunks.size(), str(meta != null), seed])
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, meta if meta is Dictionary else {}), "seed": seed, "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p = b._replay.player
	print("[PROBE] mode=%s player=%s" % [str(b._replay.mode), str(p != null)])
	if p == null:
		get_tree().quit(1)
		return
	p.advance(0.0)
	var targets := [1800, 4200, 6600]
	var ti := 0
	var guard := 0
	while p.state != "ended" and p.state != "error" and guard < 400000 and ti < targets.size():
		guard += 1
		p.advance(2.0 * SIM_DT)
		var step := int(p.get("step")) if p.get("step") != null else guard * 2
		if step >= targets[ti] and str(b._dl_state) == "fight":
			_inspect(b, step)
			ti += 1
		if guard % 30 == 0:
			await get_tree().process_frame
	print("[PROBE] end state=%s err=%s guard=%d inspected=%d" % [str(p.state), str(p.get("err")), guard, ti])
	if ti == 0:
		_inspect(b, -1)
	get_tree().quit(0)


func _texts(n: Node, out: Array) -> void:
	if n is Label or n is RichTextLabel or n is Button:
		var t := str(n.get("text")).strip_edges()
		if t != "" and (n as CanvasItem).is_visible_in_tree():
			out.append(t.replace("\n", " / "))
	for c in n.get_children():
		_texts(c, out)


func _inspect(b: Node, step: int) -> void:
	var units: Array = b._units
	var alive := 0
	var dealt := 0
	for u in units:
		if u.get("alive", false):
			alive += 1
		dealt += int(u.get("_st_dealt", 0))
	print("\n[PROBE] ===== step %d  dl=%s  units=%d alive=%d  sum _st_dealt=%d =====" % [step, str(b._dl_state), units.size(), alive, dealt])
	var shown := 0
	for u in units:
		if not u.get("alive", false) or shown >= 3:
			continue
		shown += 1
		var keys: Array = (u as Dictionary).keys()
		keys.sort()
		print("[PROBE] unit %s side=%s keys(%d)=%s" % [str(u.get("id", u.get("name", "?"))), str(u.get("side", "?")), keys.size(), str(keys).left(900)])
		print("[PROBE]   atk=%s def=%s mr=%s crit=%s aspd=%s range=%s maxHp=%s hp=%s equips=%s" % [str(u.get("atk")), str(u.get("def")), str(u.get("mr")), str(u.get("crit")), str(u.get("atkSpd", u.get("aspd"))), str(u.get("range")), str(u.get("maxHp")), str(u.get("hp")), str(u.get("equips", u.get("_equips")))])
		b._hud._show_unit_info_panel(u)
		var ip = b.get("_info_panel")
		var tx: Array = []
		if ip != null and is_instance_valid(ip):
			_texts(ip, tx)
		print("[PROBE]   info panel open=%s lines=%d: %s" % [str(ip != null and is_instance_valid(ip)), tx.size(), str(tx).left(1200)])
		b._hud._close_info_panel()
	b._on_dmg_stats_toggle()
	var sp = b._dmg_stats.panel if b._dmg_stats != null else null
	var st: Array = []
	if sp != null and is_instance_valid(sp):
		_texts(sp, st)
	print("[PROBE]   dmg stats open=%s lines=%d: %s" % [str(sp != null and is_instance_valid(sp)), st.size(), str(st).left(1500)])
	b._on_dmg_stats_toggle()
