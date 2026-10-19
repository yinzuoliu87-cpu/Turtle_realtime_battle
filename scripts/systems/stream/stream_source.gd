class_name StreamSource
extends RefCounted
## 服务器逐帧直播 · 块来源(S2 手机播放)。方案书 docs/plans/20261019-服务器逐帧直播.md §4。
##
## 播放器只问块来源三件事: 现在有几块可读(`available`)、第 i 块的字节(`chunk`)、服务器那一局录完了没有(`ended`)。
## 三个实现:
##   · `Dir`  本地目录(裁判 `--stream=<目录>` 写出来的 `<6 位序号>.bin` + `end.json`), 每次问都重新看盘 ⇒ 边录边播也能用
##   · `Mem`  内存里的块字节(门禁: 裁判 `keep` 模式留下的 `stream_chunks`); `limit` 可以人为卡住「服务器才录到第几块」
##   · `Http` 裁判机上的 Caddy(S4 部署 / S5 接线, server/stream/README.md): `<base>/<match_id>/<6 位序号>.bin` + `end.json`; 另有 `probe`(只问一次有没有这份流)
##
## ★块来源只管「有没有、是什么」, 不判对错: 版本 / 魔数 / 解压失败由播放器判, 判了就停在「无法播放」(绝不改成本机重算)。


## 接口(鸭子类型, 播放器只调这四个; 新的来源照这个形状写一个内部类即可):
##   available() -> int                 现在能读到第几块之前(连续的块数)
##   chunk(i: int) -> PackedByteArray   第 i 块的整个文件字节; 读不到返回空
##   ended() -> bool                    服务器那一局已经录完(收尾元数据已写)
##   end_meta() -> Dictionary           收尾元数据(end.json); 没有就是空


class Dir extends RefCounted:
	var dir := ""
	var _n := 0                   # 已确认存在的连续块数(只增不减: 文件不会被撤回)
	var _end: Dictionary = {}

	func _init(d: String) -> void:
		dir = d

	func available() -> int:
		while FileAccess.file_exists(dir.path_join("%06d.bin" % _n)):
			_n += 1
		return _n

	func chunk(i: int) -> PackedByteArray:
		var p := dir.path_join("%06d.bin" % i)
		if not FileAccess.file_exists(p):
			return PackedByteArray()
		return FileAccess.get_file_as_bytes(p)

	func ended() -> bool:
		return not end_meta().is_empty()

	func end_meta() -> Dictionary:
		if _end.is_empty():
			var p := dir.path_join("end.json")
			if FileAccess.file_exists(p):
				var d = JSON.parse_string(FileAccess.get_file_as_string(p))
				if d is Dictionary:
					_end = d
		return _end


class Mem extends RefCounted:
	var chunks: Array = []
	var meta: Dictionary = {}
	var limit := -1               # ≥0 ⇒ 只放出前 limit 块(模拟服务器还没录到), 而且不算录完

	func _init(c: Array, m: Dictionary = {}) -> void:
		chunks = c
		meta = m

	func available() -> int:
		return chunks.size() if limit < 0 else mini(limit, chunks.size())

	func chunk(i: int) -> PackedByteArray:
		if i < 0 or i >= available():
			return PackedByteArray()
		return chunks[i]

	func ended() -> bool:
		return limit < 0

	func end_meta() -> Dictionary:
		return meta if ended() else {}


# ═══════════════════════════════════════════════════════════════════════
#  HTTP(S5 · 逐帧直播客户端传输)。服务端口径见 server/stream/README.md:
#    GET <base>/<match_id>/<6 位序号>.bin   200 = 整块(写完才 rename 出来, 不会读到半块)/ 404 = 还没写到
#    GET <base>/<match_id>/end.json         200 = 这一局录完了(所有块都已在外面)/ 404 = 还没录完或根本没有这份流
#    两种都要请求头 X-Client-Version ≥ 最低版本, 否则 426(不带头 / 看不懂也是 426)
#  ★三种「拿不到」分开处理, **没有一种会改成本机重算**(方案书「出入」第 4 条 · verify_stream_transport):
#    · 404 = 块还没生成 ⇒ 退避重试(0.5 → 1 → 2 → 4 秒封顶, 拿到一块就回到 0.5)。播放器那边自然停在缓冲尾部「同步中」。
#      调用方说「这一局服务器早算完了」(`finished`)而 404 连着 `giveup_sec` 秒都不消失 ⇒ 这一场没有状态流(开流之前算的 /
#      被清了)⇒ `gone`: 已拿到的块照常播完, 然后播放器停在「画面无法播放」。
#    · 426 = 版本过旧 ⇒ 交给版本墙(`on_update_required`, 由 stream_watch 接到 SupabaseNet 的版本闸)⇒ `update_required`,
#      播放器同样停在「画面无法播放」。不重试(重试也是 426)。
#    · 网络失败 / 超时 / 5xx ⇒ 「同步中」并按同一条退避一直重试; 永远不判 `gone`(断网不等于没有这份流)。
#  ★块只按顺序一块一块拉(一个请求在飞)。一局 0.9~2.5 MB / 约 175 块, 1 倍播放每秒只吃一块; 追帧 / 回放时一口气拉完。
# ═══════════════════════════════════════════════════════════════════════
class Http extends RefCounted:
	const RETRY_MIN := 0.5
	const RETRY_MAX := 4.0
	const GIVEUP_SEC := 60.0
	const TIMEOUT_SEC := 15.0
	const HDR_VERSION := "X-Client-Version"
	## 状态: fetching 还在拉 / complete 全部拿到(end.json 也拿到了)/ gone 没有这份流 / update_required 版本过旧(426)
	const ST_FETCHING := "fetching"
	const ST_COMPLETE := "complete"
	const ST_GONE := "gone"
	const ST_UPDATE := "update_required"

	var base := ""
	var match_id := ""
	var version := ""
	var finished := false              # 调用方已知服务器那一局算完了 ⇒ 404 长时间不消失才可能判 gone
	var giveup_sec := GIVEUP_SEC
	var on_update_required: Callable = Callable()
	var state := ST_FETCHING
	var why := ""
	## 计数(门禁分母)
	var requests := 0
	var got_200 := 0
	var got_404 := 0
	var got_426 := 0
	var net_fail := 0
	var retries := 0
	var max_backoff := 0.0
	var _chunks: Array = []
	var _end: Dictionary = {}
	var _total := -1
	var _host: _Pump = null
	var _busy := false
	var _wait := 0.0
	var _backoff := RETRY_MIN
	var _nf_since_ms := -1             # 这一串 404 从什么时候开始(墙钟; 拿到 200 清零)
	var _want_end := false

	## opts: version(请求头里的版本, 默认本机版本)/ finished / giveup_sec
	func _init(b: String, mid: String, opts: Dictionary = {}) -> void:
		base = b.rstrip("/")
		match_id = mid
		version = str(opts.get("version", ProjectSettings.get_setting("application/config/version", "")))
		finished = bool(opts.get("finished", false))
		giveup_sec = float(opts.get("giveup_sec", GIVEUP_SEC))
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root == null:
			state = ST_GONE
			why = "no tree"
			return
		var h := _Pump.new()
		h.name = "StreamFetch"
		h.src = weakref(self)
		_host = h
		## ★延后挂: 这里可能正在别的节点的 _ready / 换场景途中被调(root 正忙着加子节点会报错)
		tree.root.add_child.call_deferred(h)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _host != null and is_instance_valid(_host):
			_host.queue_free()

	## ── 播放器只调这四个 ──
	func available() -> int:
		## gone / 426: 多报一块, 它的字节是空的 ⇒ 播放器播完已到的那些之后停在「画面无法播放」(它的既有判据, 不另开口子)
		return _chunks.size() + (1 if (state == ST_GONE or state == ST_UPDATE) else 0)

	func chunk(i: int) -> PackedByteArray:
		if i < 0 or i >= _chunks.size():
			return PackedByteArray()
		return _chunks[i]

	func ended() -> bool:
		return state == ST_COMPLETE

	func end_meta() -> Dictionary:
		return _end if state == ST_COMPLETE else {}

	## 已拿到的块数(观测量)
	func fetched() -> int:
		return _chunks.size()

	func url_of(i: int) -> String:
		return "%s/%s/%06d.bin" % [base, match_id, i]

	func end_url() -> String:
		return "%s/%s/end.json" % [base, match_id]

	## ── 由宿主节点每帧调 ──
	func _tick(dt: float) -> void:
		if _busy or state != ST_FETCHING or _host == null or not is_instance_valid(_host) or _host.req == null:
			return
		if _wait > 0.0:
			_wait -= dt
			return
		var url := end_url() if _want_end else url_of(_chunks.size())
		var err: int = _host.req.request(url, PackedStringArray([HDR_VERSION + ": " + version]))
		if err != OK:
			_fail_net()
			return
		_busy = true
		requests += 1

	func _on_done(result: int, code: int, body: PackedByteArray) -> void:
		_busy = false
		if state != ST_FETCHING:
			return
		if result != HTTPRequest.RESULT_SUCCESS or code == 0:
			_fail_net()
			return
		match code:
			200:
				got_200 += 1
				_nf_since_ms = -1
				_backoff = RETRY_MIN
				if _want_end:
					var j := JSON.new()
					if j.parse(body.get_string_from_utf8()) != OK or not (j.data is Dictionary):
						_fail_net()                   # 半截 / 被代理改过的 end.json: 当网络问题重试
						return
					_end = j.data
					_total = int(_end.get("chunks", -1))
					_want_end = false
					if _total < 0:
						_gone("end.json 没有块数")
					elif _chunks.size() >= _total:
						state = ST_COMPLETE
				else:
					_chunks.append(body)
					if _total >= 0 and _chunks.size() >= _total:
						state = ST_COMPLETE
			404:
				got_404 += 1
				var now := Time.get_ticks_msec()
				if _nf_since_ms < 0:
					_nf_since_ms = now
				var long_gone := float(now - _nf_since_ms) / 1000.0 > giveup_sec
				if _want_end or _total >= 0:
					## end.json 也没有(还在算 / 没有这份流), 或 end.json 说还有块而块不在(被清了 / 撤回重录)
					_want_end = false
					if (finished or _total >= 0) and long_gone:
						_gone("404 %.0f 秒" % (float(now - _nf_since_ms) / 1000.0))
					else:
						_retry()
				else:
					_want_end = true                  # 块没有 ⇒ 立刻问一次 end.json: 录完了就是全了, 没录完就等
			426:
				got_426 += 1
				state = ST_UPDATE
				why = "426"
				if on_update_required.is_valid():
					on_update_required.call()
			_:
				_fail_net()                           # 5xx / 其它: 与断网同一条(重试, 不判没有)

	func _fail_net() -> void:
		net_fail += 1
		_retry()

	func _retry() -> void:
		retries += 1
		_wait = _backoff
		max_backoff = maxf(max_backoff, _backoff)
		_backoff = minf(_backoff * 2.0, RETRY_MAX)

	func _gone(w: String) -> void:
		state = ST_GONE
		why = w
		push_warning("[StreamSource] %s: 没有这份状态流(%s)" % [match_id, w])


## Http 的宿主节点: 挂在 root 下(换场景不受影响), 每帧推一下拉取; 来源对象一释放它就跟着走。
class _Pump extends Node:
	var src: WeakRef = null
	var req: HTTPRequest = null

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		req = HTTPRequest.new()
		req.timeout = Http.TIMEOUT_SEC
		req.accept_gzip = true
		add_child(req)
		req.request_completed.connect(_on_completed)

	func _process(dt: float) -> void:
		var s = src.get_ref() if src != null else null
		if s == null:
			queue_free()
			return
		s._tick(dt)

	func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var s = src.get_ref() if src != null else null
		if s != null:
			s._on_done(result, code, body)


# ═══════════════════════════════════════════════════════════════════════
#  Probe: 只问一次 end.json —— 「这一场服务器那边有没有一份录完的状态流」。
#  `done.call(code)` 恰好一次: 200 有 / 404 没有 / 426 版本过旧 / 0 网络问题(已按退避重试过 TRIES 次)。
#  ★网络问题不会被说成「没有」: 调用方拿到 0 只能报「网络」, 不许当 404 去走本机重算。
# ═══════════════════════════════════════════════════════════════════════
class Probe extends Node:
	const TRIES := 3
	var url := ""
	var version := ""
	var done: Callable = Callable()
	var tries := 0
	var _req: HTTPRequest = null
	var _wait := 0.0
	var _busy := false
	var _replied := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_req = HTTPRequest.new()
		_req.timeout = Http.TIMEOUT_SEC
		add_child(_req)
		_req.request_completed.connect(_on_completed)

	func _process(dt: float) -> void:
		if _replied or _busy:
			return
		if _wait > 0.0:
			_wait -= dt
			return
		tries += 1
		if _req.request(url, PackedStringArray([Http.HDR_VERSION + ": " + version])) != OK:
			_net()
			return
		_busy = true

	func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_busy = false
		if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500:
			_net()
			return
		_reply(code if code in [200, 404, 426] else 0)

	func _net() -> void:
		if tries >= TRIES:
			_reply(0)
			return
		_wait = Http.RETRY_MIN * DetMath.dpow(2.0, float(tries - 1))

	func _reply(code: int) -> void:
		if _replied:
			return
		_replied = true
		if done.is_valid():
			done.call(code)
		if is_inside_tree():
			queue_free()


## 问一次(见 Probe)。没有场景树 ⇒ 同步回 0。
static func probe(b: String, mid: String, ver: String, cb: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		if cb.is_valid():
			cb.call(0)
		return
	var p := Probe.new()
	p.name = "StreamProbe"
	p.url = "%s/%s/end.json" % [b.rstrip("/"), mid]
	p.version = ver
	p.done = cb
	tree.root.add_child.call_deferred(p)
