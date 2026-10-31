extends Node
## verify_premiere_join_wait.gd — 周日开播「观赛」进场: 不许对着按住的空场地干等、等的时候屏上要有字
## (2026-10-31 周日彩排 P14, 方案书 docs/plans/20261031c-周日赛事界面重做.md §4.1 D)
##
## ══════════════════════════════════════════════════════════════════════
##  由来(探针 tests/_probe_premiere_wait.gd, 内测服真流 9e27c7c7 · 81 块 / 4820 步)
## ══════════════════════════════════════════════════════════════════════
##   对阵图点开一场「开播」⇒ 进战斗场后守卫(stream_watch Guard)把播放器按住, 等块拉到「翻面至今」那一步再跳过去。
##   ① 「目标已过全场 ⇒ 从头放」原来只认 end.json(`src.ended()`) ⇒ 整场块要一块一块拉完才知道全场多长。
##      开播窗口 240 秒、一场常常 80 秒 ⇒ 翻面 100 秒后进来: 按住 15.5 秒(81 块 × 0.19 秒)+ 开场 10 秒 = 28.5 秒才见单位。
##   ② 按住的那段播放器是「playing + 已暂停」⇒ `status_text()` 回空 ⇒ 屏上一个字都没有。
##
## ══════════════════════════════════════════════════════════════════════
##  判据(走真入口: StreamWatch.enter 挂开播会话 → 真战斗场 → 真守卫 → 真播放器的提示标签)
## ══════════════════════════════════════════════════════════════════════
##   ① 目标已过全场、块只到了 1 块(没录完 / 没拉完): 守卫**当场放开**(不等整场下载完), 从开头放、不跳转
##   ② 目标在场内、块还不够: 守卫按住时屏上那句 = live_spectate.TXT_CONNECTING(标签真的可见);
##      块够了 ⇒ 跳到目标步、放开、那句收掉(分母: 按住真的会结束)
##   ③ 第一块还没到: 开播那句也是 TXT_CONNECTING; 不是开播(回放)照旧「同步中」(别的入口不受影响)
## ★块是本测试现造的空步块(合法格式、不带任何对象), 块来源 = 内存(limit 卡住「拉到了第几块」) —— 不碰网络。
## ★不抄屏幕字面量: 比的是 live_spectate 里那个常量。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_premiere_join_wait.tscn --quit-after 500

const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
const TOTAL := 1800                    # 全场 30 秒(30 块)
const REC_ID := "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const NAMES := {"l": "甲方玩家", "r": "乙方玩家"}

var _n := 0
var _fail := 0
var _chunks: Array = []
var _keep: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 一块合法的空步块(与 StreamRecorder 写盘同一个头: magic / 版本 / 序号 / 首步 / 步数 / 标志 / 原始长度 + ZSTD)。
func _chunk(seq: int, first: int, steps: int) -> PackedByteArray:
	var key: bool = seq % F.KEY_CHUNKS == 0
	var e := F.Enc.new()
	for i in range(steps):
		e.u8(F.OP_STEP)
		e.vu(first + i)
		if key and i == 0:
			e.u8(F.OP_KEYFRAME)
	var raw := e.take()
	var h := StreamPeerBuffer.new()
	h.big_endian = false
	h.put_data(F.MAGIC.to_ascii_buffer())
	h.put_u16(F.VERSION)
	h.put_u32(seq)
	h.put_u32(first)
	h.put_u16(steps)
	h.put_u8(F.FLAG_KEY if key else 0)
	h.put_u32(raw.size())
	var out: PackedByteArray = h.data_array
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


func _rec() -> Dictionary:
	return {"id": REC_ID, "v": ReplayRecorder.FORMAT_V, "client_version": ReplayRecorder.client_version(),
		"seed": 7, "state": {}, "events": [{"s": 600, "k": "fight"}], "cps": [], "end": {"s": TOTAL}}


func _guard_node() -> Node:
	for c in get_tree().root.get_children():
		if c is SW.Guard and not (c as Node).is_queued_for_deletion():
			return c
	return null


## 照对阵图 open_replay 的样子进场: 开播会话(翻面 `late` 秒前)→ StreamWatch.enter → 战斗场。块来源换成内存(只放出前 limit 块)。
func _open(late: int, limit: int, premiere: bool) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if premiere:
		LS.pending = {"kind": LS.KIND_PREMIERE, "flip_ts": now - late, "srv_now": now,
			"t_ms": Time.get_ticks_msec(), "key": "gate:%d:%d" % [late, now]}
	else:
		LS.pending = {}
	var w := SW.enter(null, _rec(), "", NAMES, {})
	## 入口建的是 HTTP 来源(指着本机死端口): 当场判成没有, 一个请求都不发; 换成内存来源
	var http = StreamPlayer.pending.get("source")
	if http is StreamSource.Http:
		(http as StreamSource.Http).state = StreamSource.Http.ST_GONE
		_keep.append(http)
	var src := StreamSource.Mem.new(_chunks, {"last_step": TOTAL, "chunks": _chunks.size()})
	src.limit = limit
	StreamPlayer.pending["source"] = src
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(b)
	get_tree().current_scene = b
	var g: Node = null
	var p = null
	for _i in range(90):
		await get_tree().process_frame
		g = _guard_node()
		p = b._replay.player if b.get("_replay") != null else null
		if g != null and g.battle != null and p != null and (limit == 0 or int(p.first_step) >= 0):
			break
	for _i in range(4):
		await get_tree().process_frame
	return {"w": w, "b": b, "g": g, "p": p, "src": src}


func _close(o: Dictionary) -> void:
	var b: Node = o.get("b")
	if b != null and is_instance_valid(b):
		b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = self
	SW.current = {}
	LS.pending = {}


func _label_shows(p, t: String) -> bool:
	var l = p._sync_lbl
	return l != null and is_instance_valid(l) and (l as Label).visible and (l as Label).text == t


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	OS.set_environment(SW.ENV_BASE, "http://127.0.0.1:9")
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	gs.tutorial_active = false
	gs.test_mode = true
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	print("=== 周日开播进场: 不干等 / 等的时候有字 (P14) ===")
	for i in range(TOTAL / F.CHUNK_STEPS):
		_chunks.append(_chunk(i, 1 + i * F.CHUNK_STEPS, F.CHUNK_STEPS))
	var d0 := F.parse_chunk(_chunks[0], {})
	_ok("分母 · 现造的块是合法格式(%d 块, 第 0 块首步 %d · %d 步 · keyframe %s)" % [_chunks.size(), int(d0.get("first_step", -1)),
		(d0.get("list", []) as Array).size(), str(d0.get("key", false))],
		bool(d0.get("ok", false)) and _chunks.size() == 30 and int(d0.get("first_step", -1)) == 1)
	await _t_past_end()
	await _t_hold_text()
	await _t_first_chunk()
	_keep.clear()
	OS.set_environment(SW.ENV_BASE, "")
	_finish()


## ① 翻面 90 秒后才进来(全场 30 秒): 目标已过全场 ⇒ 不等整场块拉完, 当场放开、从开头放
func _t_past_end() -> void:
	print("── ① 目标已过全场: 不等整场下载完 ──")
	var o: Dictionary = await _open(TOTAL / 60 + 60, 1, true)
	var g: Node = o["g"]
	var p = o["p"]
	var src: StreamSource.Mem = o["src"]
	_ok("① ★分母: 入口进场了、守卫认到了战斗场、播放器拿到了第一块", str(o["w"]) == "" and g != null and g.battle != null
		and p != null and int(p.first_step) >= 0, "w=「%s」 first=%d" % [str(o["w"]), int(p.first_step) if p != null else -9])
	if g == null or p == null:
		await _close(o)
		return
	var tgt: int = SW.premiere_target(SW.current.get("premiere", {}))
	_ok("① ★分母: 目标步确实已过全场(%d ≥ %d)、块确实没拉完(只放出 %d 块, 录完=%s)" % [tgt, TOTAL, src.available(), str(src.ended())],
		tgt >= TOTAL and not src.ended() and src.available() == 1)
	_ok("① ★★★没拉完整场也当场放开(原来要等 end.json ⇒ 实测按住 15.5 秒空场地)",
		not bool(g._prem_pending) and not bool(p.paused),
		"守卫按住=%s 暂停=%s 状态=%s" % [str(g._prem_pending), str(p.paused), str(p.state)])
	src.limit = -1
	for _i in range(12):
		await get_tree().process_frame
	_ok("① 从开头放(没有跳到别处, 播放头在开打之前)", int(p.seeks) == 0 and float(p.head) < 600.0 and str(p.state) != "error",
		"seeks=%d head=%.0f 状态=%s" % [int(p.seeks), float(p.head), str(p.state)])
	await _close(o)


## ② 翻面 15 秒后进来(目标在场内), 块只拉到 3 块: 守卫按住, 屏上要有那句; 块够了 ⇒ 跳过去、放开、那句收掉
func _t_hold_text() -> void:
	print("── ② 按住等块的时候屏上有字 ──")
	var o: Dictionary = await _open(15, 3, true)
	var g: Node = o["g"]
	var p = o["p"]
	var src: StreamSource.Mem = o["src"]
	if g == null or p == null:
		_ok("② ★分母: 进场了", false, "守卫或播放器没起来")
		await _close(o)
		return
	var tgt: int = SW.premiere_target(SW.current.get("premiere", {}))
	_ok("② ★分母: 守卫真的按住了(目标 %d 在场内、块只到 %d 块、第一块已解出 首步 %d)" % [tgt, src.available(), int(p.first_step)],
		bool(g._prem_pending) and bool(p.paused) and tgt < TOTAL and int(p.first_step) >= 0)
	_ok("② ★★★按住的时候屏上那句 = 「%s」(原来是空的 ⇒ 空场地一个字都没有)" % LS.TXT_CONNECTING,
		p.status_text() == LS.TXT_CONNECTING and _label_shows(p, LS.TXT_CONNECTING),
		"status_text=「%s」 标签=%s" % [p.status_text(),
			("「%s」可见=%s" % [(p._sync_lbl as Label).text, str((p._sync_lbl as Label).visible)]) if p._sync_lbl != null else "没建"])
	src.limit = -1
	for _i in range(12):
		await get_tree().process_frame
	var tgt2: int = SW.premiere_target(SW.current.get("premiere", {}))
	_ok("② ★分母: 块够了 ⇒ 跳到目标步、放开(按住真的会结束)", not bool(g._prem_pending) and not bool(p.paused)
		and int(p.seeks) >= 1 and absi(int(p.applied) - tgt2) <= 2 * F.CHUNK_STEPS,
		"按住=%s seeks=%d applied=%d 目标=%d" % [str(g._prem_pending), int(p.seeks), int(p.applied), tgt2])
	_ok("② 放开之后那句收掉", p.status_text() != LS.TXT_CONNECTING, "status_text=「%s」" % p.status_text())
	await _close(o)


## ③ 第一块还没到: 开播 = TXT_CONNECTING; 回放(不是开播)照旧「同步中」
func _t_first_chunk() -> void:
	print("── ③ 第一块还没到 ──")
	var o: Dictionary = await _open(15, 0, true)
	var p = o["p"]
	_ok("③ ★分母: 播放器起来了、一块都没有", p != null and int(p.first_step) < 0, "first=%d" % (int(p.first_step) if p != null else -9))
	if p != null:
		_ok("③ ★★开播: 第一块到之前屏上那句 = 「%s」" % LS.TXT_CONNECTING,
			p.status_text() == LS.TXT_CONNECTING and _label_shows(p, LS.TXT_CONNECTING), "status_text=「%s」" % p.status_text())
	await _close(o)
	var o2: Dictionary = await _open(15, 0, false)
	var p2 = o2["p"]
	_ok("③ 回放(不是开播)不受影响: 照旧「%s」" % LS.TXT_SYNC, p2 != null and p2.status_text() == LS.TXT_SYNC
		and str(SW.current.get("kind", "")) == SW.KIND_REPLAY,
		"status_text=「%s」 会话=%s" % [p2.status_text() if p2 != null else "-", str(SW.current.get("kind", ""))])
	await _close(o2)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n >= 10:
		print("ALL PASS — 周日开播进场不干等、等的时候有字")
		get_tree().quit(0)
	else:
		print("FAIL x%d (断言 %d 条)" % [_fail, _n])
		get_tree().quit(1)
