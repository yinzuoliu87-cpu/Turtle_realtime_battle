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
##   服务端每周二清掉之后本机照样能播)。只有解码 + 认出是这一场之后才存 —— 坏数据不落盘。
## ★本机缓存的清理: 进战绩页时 `prune_cache()`(见那里的头注)。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

## 一周的秒数(UTC 没有夏令时, 一周恒为 7×86400)。
const WEEK_SEC := 7 * 86400
## 服务端清理的时刻 = 每周一 00:00 UTC 之后多少秒(cron `'0 0 * * 2'` = 周二 00:00 UTC)。
## ★与 `server/supabase/schema.sql` 的 `purge_old_matches()` 同一条口径(U7「周一过完就没了」):
##   周二 00:00 删掉「本周一 00:00 UTC 之前」的全部对局 ⇒ 服务端任何时刻留着的只有
##   「本周的」+「(还没到本周二时)上周的」。
const PURGE_AFTER_MONDAY_SEC := 86400

## 原因码 → 玩家看到的那句话。原因码来自 `SupabaseNet.parse_fetched_match` / `fetch_match` 与下面的解码。
## ★"unplayable" 没有固定文案: 用 `ReplayRecorder.play` 自己给的原因(版本不同 / 格式不认识),
##   版本闸只有那一处判据, 文案也只出自那一处。
const MSG := {
	"no_backend": "这个版本没接服务器，只能看在这台设备上打的比赛",
	"no_token": "账号还没连上服务器，检查一下网络再试",
	"offline": "连不上服务器，检查一下网络再试",
	"server": "服务器这会儿出了点问题（%d），稍后再试",
	"missing": "服务器上找不到这场回放（每周二清掉上周的回放）",
	"corrupt": "这场回放的数据坏了，播不了",
	"timeout": "等了太久服务器都没回音，稍后再试",
}


## 这一行战绩出不出「回放」按钮。纯判据(只读一下本地录像文件在不在)。
##   本机有录像 ⇒ 出(本机文件不受服务端清理影响)。
##   本机没有 ⇒ 只有「id 是服务端认得的 uuid + 这个包接了服务器 + 服务端还留着(`server_keeps`)」才出。
##   ★旧的 S1 本机 id(24 位 hex)不是 uuid, 从没上传过 ⇒ 本机文件没了就不出。
##   ★没有 ts 的老行(写入侧 2026-07 才补 ts)不知道是哪周的 ⇒ 照旧出(点了服务端没有就说「找不到」)。
static func has_replay(m: Dictionary, now: int) -> bool:
	var id := str(m.get("replay_id", ""))
	if id == "" or not _safe_id(id):
		return false
	if local_available(id):
		return true
	if not SB.is_uuid(id) or not SB.enabled():
		return false
	var ts := int(m.get("ts", 0))
	return ts <= 0 or server_keeps(ts, now)


## 「现在」这一刻, 服务端还留着 `ts` 那一场吗。**纯函数**(时钟由调用方注入, 门禁拿边界喂)。
##   M = `now` 所在那周的周一 00:00 UTC(`Phase2Config.week_anchor_utc`, 与赛程同一个周界)。
##   ts ≥ M                          ⇒ 本周的, 留着。
##   M-7天 ≤ ts < M 且 now < M+1天   ⇒ 上周的、本周二 00:00 的清理还没跑 ⇒ 留着。
##   其余                            ⇒ 已经清掉。
## ★恰好周二 00:00 算「已清」: cron 准点开跑, 按钮宁可早一秒消失, 也不放一个点了必然失败的死按钮。
## ★ts 是**本机**结算那一刻的时间, 而服务端判的是上传那一刻的 `created_at`(≥ 结算时刻, 补传会更晚)
##   ⇒ 这里只会**偏保守**(服务端其实还留着、按钮先没了), 不会出死按钮 —— 除非本机时钟往后拨过。
static func server_keeps(ts: int, now: int) -> bool:
	var mon: int = P2C.week_anchor_utc(now)
	if ts >= mon:
		return true
	return now < mon + PURGE_AFTER_MONDAY_SEC and ts >= mon - WEEK_SEC


static func local_available(id: String) -> bool:
	return _safe_id(id) and FileAccess.file_exists(ReplayRecorder.SAVE_DIR + id + ".rpl")


## ── 本机缓存清理(进战绩页时调) ─────────────────────────────────────
## `user://replays/` 里的录像(本机录的 + 从服务端取回来缓存的)原来**从不清理**。
## 删哪些 —— 三条**同时**成立才删:
##   ① 那一场已经不在战绩列表里了(列表封顶 50 条, 挤出去的那一行再也点不到它);
##   ② 文件比「上周一 00:00 UTC」还旧(本周 / 上周的一律不动 —— 与服务端可见期同一个周界);
##   ③ 不在上传队列里(S2 还没回读确认传上去的, 删了就再也传不上去)。
## ★只碰 `<安全 id>.rpl`: 目录里别的东西(将来别的模块放的)一律不动。
## 返回删掉的 id 列表(门禁拿它当账)。
static func prune_cache(now: int) -> Array:
	var files: Array = []
	var dir := DirAccess.open(ReplayRecorder.SAVE_DIR)
	if dir == null:
		return []
	for fn in dir.get_files():
		if not fn.ends_with(".rpl"):
			continue
		var id: String = fn.get_basename()
		if not _safe_id(id):
			continue
		files.append({"id": id, "mtime": int(FileAccess.get_modified_time(ReplayRecorder.SAVE_DIR + fn))})
	var keep: Array = []
	if GameState != null:
		for m in GameState.match_history:
			if m is Dictionary:
				keep.append(str((m as Dictionary).get("replay_id", "")))
	var queued: Array = []
	if GameState != null:
		for e in GameState.replay_upload_pending:
			if e is Dictionary:
				queued.append(str((e as Dictionary).get("id", "")))
	var gone: Array = stale_cache_ids(files, keep, queued, now)
	var removed: Array = []
	for id in gone:
		if dir.remove(str(id) + ".rpl") == OK:
			removed.append(id)
	return removed


## 纯判据: 哪些缓存该删。`files` = [{id, mtime}]。见 `prune_cache` 头注的三条。
static func stale_cache_ids(files: Array, keep_ids: Array, queued_ids: Array, now: int) -> Array:
	var cutoff: int = P2C.week_anchor_utc(now) - WEEK_SEC     # 上周一 00:00 UTC
	var out: Array = []
	for f in files:
		if not (f is Dictionary):
			continue
		var id := str((f as Dictionary).get("id", ""))
		if id == "" or keep_ids.has(id) or queued_ids.has(id):
			continue
		var mt: int = int((f as Dictionary).get("mtime", 0))
		if mt <= 0 or mt >= cutoff:          # 读不到修改时间 ⇒ 不知道多旧 ⇒ 不删
			continue
		out.append(id)
	return out


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
