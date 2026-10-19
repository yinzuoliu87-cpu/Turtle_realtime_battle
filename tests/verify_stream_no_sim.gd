extends Node
## verify_stream_no_sim.gd — 逐帧直播 S2: 手机播放模式一步 sim 都不跑。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「播放模式一步 sim 都不跑」(verify_stream_never_resim 的 S2 部分)。
##
## 先在本进程跑一局裁判局录流(镜像快照局, 三路打满, 块留在内存), 再建一个播放模式的战斗场, **由引擎真的每帧调 `_process`**
## (生产路径: `_process → ReplayRecorder.sim_feed → StreamPlayer.advance`), 块来源模拟「服务器边录边放」:
##   ① 一开始只放出 2 块 ⇒ 播放器停在缓冲(「同步中」), 画面不动;
##   ② 放到 8 块 ⇒ 开播, 追上之后停在直播边沿(「同步中」), 播放头不超过已到的最后一步;
##   ③ 全部放出 + 标记录完 ⇒ 播到结尾。
##   ④ 坏块 / 版本号不对 ⇒ 停在「画面无法播放」, 不崩、不改成本机重算。
## ★判据: 整个过程 `_sim_step_n` 恒 0、`sim_stepped` 信号 0 次、`ReplayRecorder.pre_step`(只在 `_sim_step` 第一行调)0 次。
## ★分母: 播放器真的应用了全部步数、解了全部块、建过 > 1000 个镜像节点、放过 > 100 个事件、单位代理 > 0 ——
##   否则「0 次 sim」可能只是什么都没播。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")

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
	var nat: Dictionary = await P.record_referee(self, J.mirror(gs), func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	var chunks: Array = res.get("stream_chunks", [])
	var meta: Dictionary = res.get("stream", {})
	_ok("分母 · 录到一局三路打满的流(%d 块 / %d 步)" % [chunks.size(), int(meta.get("steps", 0))],
		bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3 and chunks.size() > 100)
	await _live_play(chunks, meta, nat)
	await _bad_play(chunks, meta, nat, "坏块(负载被改)", _corrupt(chunks, 3, false))
	await _bad_play(chunks, meta, nat, "版本号不对", _corrupt(chunks, 3, true))
	_finish()


## 一块的副本: 改版本号, 或者把压缩负载中间改坏。
func _corrupt(chunks: Array, at: int, version: bool) -> Array:
	var out: Array = chunks.duplicate()
	var b: PackedByteArray = (chunks[at] as PackedByteArray).duplicate()
	if version:
		b.encode_u16(4, F.VERSION + 1)
	else:
		for i in range(F.HEADER_BYTES + 8, mini(b.size(), F.HEADER_BYTES + 40)):
			b[i] = b[i] ^ 0x5a
	out[at] = b
	return out


func _live_play(chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	print("=== 边录边播(引擎每帧驱动) ===")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}), 2)
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了(mode=stream)", p != null and str(b._replay.mode) == "stream")
	if p == null:
		return
	var src = p.src
	var emits := [0]
	b.sim_stepped.connect(func() -> void: emits[0] += 1)
	p.speed = 40.0                  # 只改每帧推几步(与倍速同一个口子), 不改「应用」本身
	## ① 只有 2 块: 缓冲
	for _i in range(30):
		await get_tree().process_frame
	_ok("① 只到 2 块时停在缓冲, 显示「同步中」, 一步没应用(状态 %s / 应用 %d)" % [p.state, p.steps_applied],
		p.state == "buffering" and p.status_text() == StreamPlayer.Live.TXT_SYNC and p.steps_applied == 0)
	## ② 放到 8 块: 开播 → 追上直播边沿停住
	src.limit = 8
	var stalled := false
	var over_edge := false
	for _i in range(4000):
		await get_tree().process_frame
		if p.head > float(p._last_step) + 0.001:
			over_edge = true
		if p.state == "stalled":
			stalled = true
			break
	var h_st := p.head
	var applied_st := p.applied
	for _i in range(20):
		await get_tree().process_frame
	_ok("② 追上服务器后停在直播边沿「同步中」(状态 %s, 播放头 %.1f = 已到最后一步 %d), 停着时不前进" % [p.state, p.head, p._last_step],
		stalled and p.status_text() == StreamPlayer.Live.TXT_SYNC and int(roundf(h_st)) == p._last_step
		and p.applied == applied_st and not over_edge)
	## ③ 全部放出: 播到结尾
	src.limit = -1
	for _i in range(60000):
		await get_tree().process_frame
		if p.state == "ended" or p.state == "error":
			break
	var steps := int(meta.get("steps", 0))
	print("  [量] 解块 %d / 应用 %d 步 / 镜像建 %d 删 %d / 单位代理 %d / 事件 %s / sim 步号 %d / sim_stepped %d 次 / pre_step %d 次" % [
		p.chunks_decoded, p.steps_applied, p.mirror.built, p.mirror.deleted, p.units.size(), str(p.events),
		int(b._sim_step_n), emits[0], p.sim_calls])
	var evn := 0
	for k in p.events:
		evn += int(p.events[k])
	_ok("分母 · ③ 播到结尾: 解了全部 %d 块、应用了全部 %d 步" % [chunks.size(), steps],
		p.state == "ended" and p.chunks_decoded == chunks.size() and p.steps_applied == steps, "%s %s" % [p.state, p.err])
	_ok("分母 · 真的画了东西: 镜像节点建过 %d 个、事件放过 %d 个、单位代理 %d 个" % [p.mirror.built, evn, p.units.size()],
		p.mirror.built > 1000 and evn > 100 and p.units.size() > 0)
	_ok("★★播放全程 _sim_step 一次都没跑: 步号 %d、sim_stepped %d 次、pre_step %d 次" % [int(b._sim_step_n), emits[0], p.sim_calls],
		int(b._sim_step_n) == 0 and emits[0] == 0 and p.sim_calls == 0)
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore(backup)


func _bad_play(chunks: Array, meta: Dictionary, nat: Dictionary, tag: String, bad: Array) -> void:
	print("=== %s ===" % tag)
	var backup: Dictionary = ReplayRecorder.capture_all()
	var b: Node = P.make_player_battle(self, bad, meta, int(nat["seed"]), nat.get("state", {}))
	var p: StreamPlayer = b._replay.player
	if p == null:
		_ok("%s 播放模式建起来了" % tag, false)
		return
	var emits := [0]
	b.sim_stepped.connect(func() -> void: emits[0] += 1)
	p.speed = 40.0
	for _i in range(600):
		await get_tree().process_frame
		if p.state == "error" or p.state == "ended":
			break
	var a0 := p.applied
	for _i in range(20):
		await get_tree().process_frame
	_ok("★%s ⇒ 停在「%s」(状态 %s: %s), 之后不再前进, 一步 sim 都没跑(步号 %d / sim_stepped %d)" % [tag, StreamPlayer.TXT_ERROR, p.state, p.err,
		int(b._sim_step_n), emits[0]], p.state == "error" and p.status_text() == StreamPlayer.TXT_ERROR and p.applied == a0
		and int(b._sim_step_n) == 0 and emits[0] == 0 and p.sim_calls == 0)
	_ok("分母 · %s 坏块之前的块照常播了(应用到第 %d 步)" % [tag, p.applied], p.steps_applied >= 3 * F.CHUNK_STEPS - 1)
	b.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore(backup)


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
		print("ALL PASS — 播放模式一步 sim 都不跑, 缓冲 / 直播边沿 / 坏块都停住不重算 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
