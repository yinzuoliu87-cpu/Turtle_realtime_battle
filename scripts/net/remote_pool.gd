extends Node

## RemotePool — 把 ghost 快照【送出去 / 取回来】的那一层 (2026-08-26)。
##
## 方案书: docs/plans/20260820-阵容上传后端.md (状态: 已拍板)
## 用 preload 引: const RemotePool = preload("res://scripts/net/remote_pool.gd")
##
## ★★本文件的设计铁律 —— 网络是【锦上添花的同步】, 不是【开局的依赖】:
##   · 匹配路径 `Backend.find_opponent()` **一行网络代码都不许有**, 它只读本地池;
##   · 拉取是【异步 + 事后并池】, 谁都不 await 它;
##   · `BASE_URL` 没配 ⇒ 整层是 no-op, 行为与接网络前【逐字节相同】。
##   为什么这么写: 现游戏离线完全可玩(策划队 + bot 兜底)。测试者在国内、靠 Sideloadly 装包,
##   一旦"必须连通"就等于一半人打不开 —— 那比没做还糟。
##
## ★分工: 传输(HTTP)在本文件下半, **校验/并池在上半且是纯静态** ——
##   纯静态那半是【服务端要照抄的同一份规则】(方案书 §落地步骤 5), 也是门禁真正要量的东西。
##   传输那半留了一个可注入的缝(`_transport`), 门禁不需要真服务器就能全链路走一遍。

const Backend = preload("res://scripts/net/backend.gd")
const _P2 = preload("res://scripts/gamedata/phase2_config.gd")
const _TS = preload("res://scripts/gamedata/turtle_stats.gd")
const _ES = preload("res://scripts/gamedata/equip_stats.gd")

## 服务端地址。**空 = 本层整体停用**(当前就是空 —— 服务端还没开, 见方案书 §未决点)。
## 配置方式: ProjectSettings `turtle/backend_url`, 或环境变量 `TURTLE_BACKEND` (调试用)。
## 冒烟测试快照的 ghost_id 前缀 —— 见 snapshot_valid() 里那条拒绝规则。
## 必须与 `tools/backend_smoke.py` 的 GID 前缀一致。
const SMOKE_PREFIX := "__smoke__"

const SETTING_KEY := "turtle/backend_url"
const ENV_KEY := "TURTLE_BACKEND"

## 网络请求的硬超时。★这个数不是随手写的: 它是"最坏情况下玩家要多等多久"的上限,
##   而因为没人 await 拉取, 它其实只决定"这条请求多久放弃", 不决定开局速度。
const TIMEOUT_SEC := 6.0
const FETCH_LIMIT := 20         # 一次拉几份(方案书 §接口表)

# ══════════════ 上半: 纯静态 —— 校验与并池(服务端照抄这一份) ══════════════

## 一份快照【能不能进池】。返回 {"ok": bool, "reason": String}。
##
## ★为什么客户端也要校验, 而不是只在服务端拦(方案书 风险 2 只写了服务端):
##   服务端拦的是"别人别塞脏数据"; 客户端拦的是"**塞进来了我也不能崩**"。
##   这两件事的失败后果完全不同 —— 后者是所有人开局崩, 而我控制不了服务器什么时候被绕过。
##   ⇒ 同一份规则两边各跑一次, 是**冗余不是重复**。
##
## ★判据只用【本地事实源】: 龟 id 查 turtle_stats.STATS, 装备 id 查 EquipStats.STATS,
##   等级上限查 P2.MAX_LEVEL, 单只装备上限查 P2.UNIT_EQUIP_CAP ——
##   全部是产品自己的表, 不是本文件手抄的常量(手抄的副本必然落后)。
static func snapshot_valid(snap) -> Dictionary:
	if not (snap is Dictionary):
		return {"ok": false, "reason": "不是 Dictionary"}
	var d: Dictionary = snap
	if int(d.get("schema_ver", 0)) != Backend.SCHEMA_VER:
		return {"ok": false, "reason": "schema_ver=%s ≠ %d" % [str(d.get("schema_ver", "缺")), Backend.SCHEMA_VER]}
	var gid := str(d.get("ghost_id", ""))
	if gid == "":
		return {"ok": false, "reason": "缺 ghost_id"}
	## ★冒烟测试(`tools/backend_smoke.py`)会往【真的生产池】里传一条快照来验 V2 往返,
	##   而它验完是删不掉的(服务端故意没有公开的删除接口)。
	##   ⇒ 客户端认这个前缀并**拒绝入池**: 测试数据永远不会变成谁的对手。
	##   放在客户端而不是服务端: 服务端一旦拒收, V2「传上去能拉回来」就没法验了。
	if gid.begins_with(SMOKE_PREFIX):
		return {"ok": false, "reason": "冒烟测试数据(%s…), 不入池" % SMOKE_PREFIX}
	var br := int(d.get("bracket", -1))
	if br < 0 or br > 8:
		return {"ok": false, "reason": "bracket=%d 越界" % br}

	var leaders = d.get("leaders", null)
	if not (leaders is Array) or (leaders as Array).is_empty() or (leaders as Array).size() > 3:
		return {"ok": false, "reason": "leaders 不是 1~3 只"}
	for pid in (leaders as Array):
		if not _TS.STATS.has(str(pid)):
			return {"ok": false, "reason": "龟 id `%s` 不在白名单" % str(pid)}

	var levels = d.get("pet_levels", {})
	if levels is Dictionary:
		for k in (levels as Dictionary).keys():
			var lv := int((levels as Dictionary)[k])
			if lv < 1 or lv > _P2.MAX_LEVEL:
				return {"ok": false, "reason": "%s 等级 %d 越界(1~%d)" % [str(k), lv, _P2.MAX_LEVEL]}

	var eqp = d.get("equipped", {})
	if eqp is Dictionary:
		for k in (eqp as Dictionary).keys():
			var arr = (eqp as Dictionary)[k]
			if not (arr is Array):
				return {"ok": false, "reason": "%s 的 equipped 不是 Array" % str(k)}
			if (arr as Array).size() > _P2.UNIT_EQUIP_CAP:
				return {"ok": false, "reason": "%s 带了 %d 件装备(上限 %d)" % [str(k), (arr as Array).size(), _P2.UNIT_EQUIP_CAP]}
			for e in (arr as Array):
				var eid := str((e as Dictionary).get("id", "")) if e is Dictionary else str(e)
				if not _ES.STATS.has(eid):
					return {"ok": false, "reason": "装备 id `%s` 不在白名单" % eid}
	return {"ok": true, "reason": ""}


## 把一批远端快照并进本地池。**返回统计, 且统计要被打印** ——
## 静默丢弃 = 假装"同步成功了", 而池子其实一条没进(CLAUDE.md: 无声上限 = 假装覆盖全了)。
static func ingest_remote(pool: Dictionary, arr) -> Dictionary:
	var st := {"total": 0, "added": 0, "rejected": 0, "reasons": []}
	if not (arr is Array):
		return st
	for g in (arr as Array):
		st["total"] = int(st["total"]) + 1
		var v := snapshot_valid(g)
		if not bool(v["ok"]):
			st["rejected"] = int(st["rejected"]) + 1
			if (st["reasons"] as Array).size() < 5:
				(st["reasons"] as Array).append(str(v["reason"]))
			continue
		## ★★盖 origin=remote 章, 且**必须覆盖**服务端传来的任何值 ——
		##   服务端存的那份是 A 上传时的原样, 它在 A 自己机器上是 local;
		##   到了 B 这里就是别人的。不覆盖就等于让 A 决定 B 怎么判"是不是我自己",
		##   而那正好会让 B 把 A 跳过(见 Backend._is_self_ghost 的沿革)。
		var mark: Dictionary = (g as Dictionary).duplicate(true)
		mark[Backend.ORIGIN_KEY] = Backend.ORIGIN_REMOTE
		Backend.pool_add(pool, mark)
		st["added"] = int(st["added"]) + 1
	return st


## 本层是否启用。**空 URL = 停用 = 当前状态**。
static func base_url() -> String:
	if OS.has_environment(ENV_KEY):
		return OS.get_environment(ENV_KEY).strip_edges()
	var v = ProjectSettings.get_setting(SETTING_KEY, "")
	return str(v).strip_edges()


static func enabled() -> bool:
	return base_url() != ""

# ══════════════ 下半: 传输 —— 唯一碰 HTTP 的地方 ══════════════

## 可注入的传输。签名: func(method: String, url: String, body: String, cb: Callable) -> void
## cb 收 {"ok": bool, "code": int, "body": String}。
## ★留这条缝是为了让门禁**走真实的校验/并池代码**而不用真服务器 ——
##   被测的是上半那两个纯函数, 缝只是替掉"网线"。
var _transport: Callable = Callable()

## 请求回来就自我销毁(给 push_async / pull_async 用的一次性实例)。
var _autofree := false


## 挂到场景树根上跑一次请求, 完成后自己走。
##
## ★为什么不做成 autoload: 本层**默认停用**(URL 空), 为一个 no-op 常驻一个单例不划算,
##   而且 autoload 会进每一个测试进程、每份门禁都得跟着适配。用完即走干净得多。
## ★调用方必须先判 `enabled()`, 否则这个节点会挂在树上没人收(upload/fetch 里会提前 return)。
static func _spawn():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var rp = new()
	rp._autofree = true
	tree.root.add_child(rp)
	return rp


## 发一份快照到服务端。**发完就忘**; 未配置后端 = 什么都不做。
static func push_async(snapshot: Dictionary) -> void:
	if not enabled():
		return
	var rp = _spawn()
	if rp != null:
		rp.upload(snapshot)


## 拉一档对手并池。**给【下一局】用** —— 本局的匹配早就用本地池算完了, 谁都不等它。
static func pull_async(bracket: int) -> void:
	if not enabled():
		return
	var rp = _spawn()
	if rp != null:
		rp.fetch_bracket(bracket)


func _bye() -> void:
	if _autofree:
		queue_free()


func _http(method: String, url: String, body: String, cb: Callable) -> void:
	if _transport.is_valid():
		_transport.call(method, url, body, cb)
		return
	## ★★宿主节点不在场景树上就【不许发】—— HTTPRequest 必须在树里才能工作。
	##   会走到这里是因为: 调用方可能在场景正在建树/正在拆的时刻触发上传或拉取,
	##   此时 `add_child` 被推迟, 而 `request()` 立刻就调 ⇒ 引擎刷
	##   `Condition "!is_inside_tree()" is true` 报错(实测 verify_match_seed 一次三条)。
	##   网络层的第一原则是**永远不能把游戏搞坏**, 所以这里当成一次普通失败静默处理。
	if not is_inside_tree():
		if cb.is_valid():
			cb.call({"ok": false, "code": 0, "body": ""})
		_bye()
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray) -> void:
		var ok := (result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300)
		if cb.is_valid():
			cb.call({"ok": ok, "code": code, "body": data.get_string_from_utf8()})
		req.queue_free()
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(url, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, body)
	if err != OK:
		## ★立刻回调失败, 不能静默 —— 否则调用方永远等不到回调, 看着像"卡住了"。
		if cb.is_valid():
			cb.call({"ok": false, "code": 0, "body": ""})
		req.queue_free()


## 上传一份快照。**发完就忘**: 不等结果、失败不弹错、不碰存档。
func upload(snapshot: Dictionary) -> void:
	if not enabled():
		_bye()
		return
	var v := snapshot_valid(snapshot)
	if not bool(v["ok"]):
		## 自己都过不了校验就别发 —— 发了也会被服务端拒, 白费一次请求。
		print("[RemotePool] 本地快照未通过校验, 不上传: %s" % str(v["reason"]))
		_bye()
		return
	_http("POST", base_url().rstrip("/") + "/ghost", JSON.stringify(snapshot),
		func(r: Dictionary) -> void:
			if not bool(r.get("ok", false)):
				print("[RemotePool] 上传失败(code=%d), 忽略 —— 本地池不受影响" % int(r.get("code", 0)))
			_bye()
	)


## 拉一档对手并入本地池。**没有人 await 它**; 完成后自己存盘。
## done 回调可选(门禁用), 参数是 ingest_remote 的统计。
func fetch_bracket(bracket: int, done: Callable = Callable()) -> void:
	if not enabled():
		if done.is_valid():
			done.call({"total": 0, "added": 0, "rejected": 0, "reasons": ["未配置后端"]})
		_bye()
		return
	var url := "%s/ghosts?bracket=%d&limit=%d" % [base_url().rstrip("/"), bracket, FETCH_LIMIT]
	_http("GET", url, "", func(r: Dictionary) -> void:
		var st := {"total": 0, "added": 0, "rejected": 0, "reasons": []}
		if bool(r.get("ok", false)):
			var parsed = JSON.parse_string(str(r.get("body", "")))
			var arr = parsed.get("ghosts", []) if parsed is Dictionary else parsed
			var pool := Backend.load_pool()
			st = ingest_remote(pool, arr)
			if int(st["added"]) > 0:
				Backend.save_pool(pool)
			print("[RemotePool] 拉回 %d 份, 入池 %d, 拒 %d %s"
				% [int(st["total"]), int(st["added"]), int(st["rejected"]), str(st["reasons"])])
		else:
			print("[RemotePool] 拉取失败(code=%d), 忽略 —— 照旧打本地池/bot" % int(r.get("code", 0)))
		if done.is_valid():
			done.call(st)
		_bye()
	)
