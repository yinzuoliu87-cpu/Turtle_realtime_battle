extends RefCounted
## 回放 S3: 战绩页点「回放」→ **本机有录像就直接播, 没有就按 match_id 去服务端取** → 解码 → 比版本 → 播。
## 方案书: docs/plans/20261003-跨设备回放.md S3 / 门禁 `tests/verify_replay_watch.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  这一层只管「从哪拿到录像、拿不到怎么说」
## ══════════════════════════════════════════════════════════════════════
##   播放本身一律走 S1 的 `ReplayRecorder.play`(版本闸 / 备份 GameState / 结算跳过 / 离场还原都在那里),
##   这里**不另起一套**(memory fb-verify-must-run-the-real-path)。
##   取录像走 `SupabaseNet.fetch_match_async`(先等令牌, 不拿匿名钥匙读; 自带看门狗)。
##
## ★★每一种失败给**不同的一句人话**, 而且按钮一定回来(不会一直转):
##   网络层每条路恰好回调一次 + 看门狗兜底(见 supabase.gd `fetch_match`)。
##
## ★取回来的录像**存一份到本机** user://replays/<id>.rpl(方案书 R11: 整份拉到本地, 之后不再依赖服务端;
##   服务端 14 天清掉之后本机照样能播)。只有解码 + 认出是这一场之后才存 —— 坏数据不落盘。

const SB := preload("res://scripts/net/supabase.gd")

## 服务端留多久(秒)。★与 `server/supabase/schema.sql` 的 `purge_old_matches()`「14 days」同一个数。
##   超过这个岁数、本机又没有录像的那一行 ⇒ 服务端那一行已经被清了 ⇒ 不出按钮(不出必然失败的死按钮)。
const SERVER_KEEP_SEC := 14 * 86400

## 原因码 → 玩家看到的那句话。原因码来自 `SupabaseNet.parse_fetched_match` / `fetch_match` 与下面的解码。
## ★"unplayable" 没有固定文案: 用 `ReplayRecorder.play` 自己给的原因(版本不同 / 格式不认识),
##   版本闸只有那一处判据, 文案也只出自那一处。
const MSG := {
	"no_backend": "这个版本没接服务器，只能看在这台设备上打的比赛",
	"no_token": "账号还没连上服务器，检查一下网络再试",
	"offline": "连不上服务器，检查一下网络再试",
	"server": "服务器这会儿出了点问题（%d），稍后再试",
	"missing": "服务器上找不到这场回放（回放只保留两周）",
	"corrupt": "这场回放的数据坏了，播不了",
	"timeout": "等了太久服务器都没回音，稍后再试",
}


## 这一行战绩出不出「回放」按钮。纯判据(只读一下本地录像文件在不在)。
##   本机有录像 ⇒ 出。
##   本机没有 ⇒ 只有「id 是服务端认得的 uuid + 这个包接了服务器 + 服务端还没清掉」才出。
##   ★旧的 S1 本机 id(24 位 hex)不是 uuid, 从没上传过 ⇒ 本机文件没了就不出。
static func has_replay(m: Dictionary, now: int) -> bool:
	var id := str(m.get("replay_id", ""))
	if id == "" or not _safe_id(id):
		return false
	if local_available(id):
		return true
	if not SB.is_uuid(id) or not SB.enabled():
		return false
	var ts := int(m.get("ts", 0))
	return ts <= 0 or now - ts < SERVER_KEEP_SEC


static func local_available(id: String) -> bool:
	return _safe_id(id) and FileAccess.file_exists(ReplayRecorder.SAVE_DIR + id + ".rpl")


## id 要拼进文件路径 —— 只放行十六进制与连字符(uuid / S1 的 24 位 hex 都是这个字符集)。
static func _safe_id(id: String) -> bool:
	if id.length() < 8 or id.length() > 64:
		return false
	for c in id:
		if not ("0123456789abcdef-".contains(c)):
			return false
	return true


## 原因码 → 一句话。
static func message(code: String, http_code: int = 0) -> String:
	var t := str(MSG.get(code, MSG["corrupt"]))
	return t % http_code if t.contains("%d") else t


# ─────────────────────────────── 入口 ───────────────────────────────

## 点「回放」。`done.call(code: String, msg: String)` —— **恰好一次**:
##   code == "" ⇒ 已进战斗场(`ReplayRecorder.play` 换场景了); 否则 msg 是给玩家看的那句话。
##   本机有录像时**同步**回调(一个请求都不发); 要去服务端取时异步回调。
##   调用方已经离场(`done` 失效)时: 不回调, 也**不播**(人已经走了, 别把他拽进回放)。
static func open(tree: SceneTree, id: String, done: Callable) -> void:
	if local_available(id):
		var rec: Dictionary = ReplayRecorder.load_record(id)
		if not rec.is_empty():
			_play(tree, rec, done)
			return
		## 本机那份读不出(文件坏了) ⇒ 往下走服务端那条, 而不是直接报坏。
	if not SB.enabled():
		_reply(done, "no_backend", message("no_backend"))
		return
	var started: bool = SB.fetch_match_async(id, func(res: Dictionary) -> void: _on_fetched(tree, id, res, done))
	if not started:
		_reply(done, "corrupt", message("corrupt"))


static func _on_fetched(tree: SceneTree, id: String, res: Dictionary, done: Callable) -> void:
	if not done.is_valid():
		return
	var err := str(res.get("err", ""))
	if err != "":
		_reply(done, err, message(err, int(res.get("code", 0))))
		return
	var raw := decode_b64(str(res.get("b64", "")))
	var rec: Dictionary = ReplayRecorder.decode(raw) if not raw.is_empty() else {}
	## ★认出「是这一场」: 录像里的 id 必须就是我点的那一行(id 在 `save_record` 时写进录像本体)。
	##   缺了 events / cps / end 的也不认 —— 播出来会在第一步就「对不上」, 不如现在就说清楚。
	if rec.is_empty() or str(rec.get("id", "")) != id or not (rec.get("events", null) is Array) \
			or not (rec.get("cps", null) is Array) or not (rec.get("end", null) is Dictionary):
		_reply(done, "corrupt", message("corrupt"))
		return
	_cache(id, raw)
	_play(tree, rec, done)


static func _play(tree: SceneTree, rec: Dictionary, done: Callable) -> void:
	var why := ReplayRecorder.play(tree, rec)
	if why != "":
		_reply(done, "unplayable", why)
		return
	_reply(done, "", "")


static func _reply(done: Callable, code: String, msg: String) -> void:
	if done.is_valid():
		done.call(code, msg)


## base64 → 录像字节。★先自己验形状再交给引擎: 引擎的 `base64_to_raw` / `decompress_dynamic`
##   遇到坏数据会往日志喷 `Condition "..." is true` 一类 ERROR(探针实测) —— 预期内的分支不该留下
##   长得像故障的日志。能在这里挡的挡掉: 字符集 / 长度 / zlib 头(Godot 的 DEFLATE 模式带 zlib 头 0x78)。
##   ⚠ 挡不住的: 头对但中段被改 / 截断 —— 那种照样交给引擎解, 解不出来同样报「坏了」, 只是日志里多一行 ERROR。
static func decode_b64(b64: String) -> PackedByteArray:
	if b64.length() < 8 or b64.length() % 4 != 0:
		return PackedByteArray()
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9+/]+={0,2}$")
	if re.search(b64) == null:
		return PackedByteArray()
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() < 6 or raw[0] != 0x78 or ((int(raw[0]) << 8) | int(raw[1])) % 31 != 0:
		return PackedByteArray()
	return raw


static func _cache(id: String, raw: PackedByteArray) -> void:
	if not _safe_id(id) or local_available(id):
		return
	DirAccess.make_dir_recursive_absolute(ReplayRecorder.SAVE_DIR)
	var f := FileAccess.open(ReplayRecorder.SAVE_DIR + id + ".rpl", FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(raw)
	f.close()
