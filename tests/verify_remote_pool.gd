extends Node
## verify_remote_pool.gd — 阵容上传后端·客户端整层 (2026-08-26)
##
## 对应 `docs/plans/20260820-阵容上传后端.md` 的 V1~V5。
##
## ★★覆盖边界(必须写清楚, 否则这份门禁会被当成"V1~V5 全绿"):
##   · V1 离线不退化 —— **完整验**(而且用【真的 HTTPRequest 打不可达地址】, 不是假传输)
##   · V3 伪造快照被拒 —— 验的是**客户端这一侧**。服务端照抄同一个 `snapshot_valid()`,
##     但服务端还没开(要腾讯云账号+实名, 用户 2026-08-25「先不管」) ⇒ 服务端那半边**没验**。
##   · V2 A→B —— 验到"拉回来的快照能被 pool_find 匹配到"。**真·两台手机没验**(同上, 无服务器)。
##   · V4 schema 不匹配丢弃 / V5 失败不影响存档 —— 完整验。
##
## ★本文件最有价值的一条是 ②-b: 它是写这份门禁时**当场发现的真 bug** ——
##   `_is_self_ghost` 按 profile 名判自己, 而所有真人快照的名字都是写死的同一个,
##   ⇒ 接上服务器后 B 会把 A 的阵容全跳过。服务器还没开就先踩到了。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_remote_pool.tscn

const Backend = preload("res://scripts/net/backend.gd")
const RemotePool = preload("res://scripts/net/remote_pool.gd")
const P2 = preload("res://scripts/gamedata/phase2_config.gd")

## 断网模拟: discard 端口, **立刻被拒**(不是超时) ⇒ CI 上不会因为等 6 秒而变慢/变飘。
const DEAD_URL := "http://127.0.0.1:9"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 一份【合法】快照 —— 拿产品自己的白名单表取真 id, 不手抄。
func _good() -> Dictionary:
	var pid := str(RemotePool._TS.STATS.keys()[0])
	var eid := str(RemotePool._ES.STATS.keys()[0])
	return {
		"schema_ver": Backend.SCHEMA_VER,
		"ghost_id": "g_1_" + pid,
		"is_bot": false,
		"bracket": 3,
		"profile": {"name": "玩家阵容", "avatar": pid, "id": "g_1_" + pid},
		"leaders": [pid],
		"pet_levels": {pid: 5},
		"equipped": {pid: [{"id": eid, "star": 1}]},
		"minions": {}, "loadouts": {}, "lane_assign": {},
		"season_total_battles": 12, "season_eggs_killed": 0,
		"chest_treasures_won": [], "chest_treasure_value": 0.0,
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 阵容上传后端·客户端层 (方案书 20260820) ===")

	# ────────── V3: 伪造快照被拒(客户端侧) ──────────
	## ★分母断言必须在最前: 若"合法的也被拒", 下面全部 reject 断言就是恒真式。
	var vg := RemotePool.snapshot_valid(_good())
	_ok("★分母: 一份【合法】快照必须被【接受】(否则下面全是恒真式)",
		bool(vg["ok"]), "reason=%s" % str(vg["reason"]))

	var f1 := _good()
	f1["leaders"] = ["不存在的龟id"]
	_ok("★V3-a 龟 id 不在白名单 → 拒", not bool(RemotePool.snapshot_valid(f1)["ok"]),
		str(RemotePool.snapshot_valid(f1)["reason"]))

	var pid0 := str(RemotePool._TS.STATS.keys()[0])
	var eid0 := str(RemotePool._ES.STATS.keys()[0])
	var over: Array = []
	for _i in range(P2.UNIT_EQUIP_CAP + 1):
		over.append({"id": eid0, "star": 1})
	var f2 := _good()
	f2["equipped"] = {pid0: over}
	_ok("★V3-b 单只装备 %d 件 > 上限 %d → 拒" % [over.size(), P2.UNIT_EQUIP_CAP],
		not bool(RemotePool.snapshot_valid(f2)["ok"]), str(RemotePool.snapshot_valid(f2)["reason"]))

	var f2b := _good()
	f2b["equipped"] = {pid0: [{"id": "p2eq_不存在", "star": 1}]}
	_ok("★V3-b2 装备 id 不在白名单 → 拒", not bool(RemotePool.snapshot_valid(f2b)["ok"]),
		str(RemotePool.snapshot_valid(f2b)["reason"]))

	var f3 := _good()
	f3["pet_levels"] = {pid0: P2.MAX_LEVEL + 1}
	_ok("★V3-c 等级 %d > 上限 %d → 拒" % [P2.MAX_LEVEL + 1, P2.MAX_LEVEL],
		not bool(RemotePool.snapshot_valid(f3)["ok"]), str(RemotePool.snapshot_valid(f3)["reason"]))
	## ★边界: 刚好等于上限必须【放行】—— 只验"超了拒"会把 > 写成 >= 的 off-by-one 放过。
	var b3 := _good()
	b3["pet_levels"] = {pid0: P2.MAX_LEVEL}
	_ok("★V3-c边界 等级 == 上限 %d 必须放行(挡住 off-by-one)" % P2.MAX_LEVEL,
		bool(RemotePool.snapshot_valid(b3)["ok"]), str(RemotePool.snapshot_valid(b3)["reason"]))

	# ────────── V4: schema_ver 不匹配丢弃 ──────────
	var old_snap := _good()
	old_snap["schema_ver"] = Backend.SCHEMA_VER - 1
	var pool4 := {"brackets": {}}
	var st4 := RemotePool.ingest_remote(pool4, [old_snap, _good()])
	_ok("★★V4 老 schema 的快照【不进本地池】(收 2 拒 1 入 1)",
		int(st4["total"]) == 2 and int(st4["rejected"]) == 1 and int(st4["added"]) == 1,
		"total=%d added=%d rejected=%d %s" % [int(st4["total"]), int(st4["added"]), int(st4["rejected"]), str(st4["reasons"])])

	# ────────── V2: A 传 → B 拉 → B 能匹配到 ──────────
	## B 手机的池: 全新空池, 只有从"服务端"拉回来的那份。
	var poolB := {"brackets": {}}
	var from_a := _good()
	from_a["ghost_id"] = "g_1_来自A手机"
	## ★A 那份在 A 自己机器上是 origin=local(upload_ghost 盖的)。这里刻意带上它,
	##   来验 ingest 是否**覆盖**成 remote —— 不覆盖的话 B 会把它当成"自己"跳过。
	from_a[Backend.ORIGIN_KEY] = Backend.ORIGIN_LOCAL
	var stB := RemotePool.ingest_remote(poolB, [from_a])
	_ok("★分母: A 的快照进了 B 的池", int(stB["added"]) == 1, str(stB["reasons"]))
	var got = Backend.pool_find(poolB, 3, [], RandomNumberGenerator.new())
	_ok("★★②-b V2 B 能【匹配到】A 的阵容(需求原话)",
		got != null and str((got as Dictionary).get("ghost_id", "")) == "g_1_来自A手机",
		"实得 %s" % ("null —— 被 _is_self_ghost 当成自己跳过了" if got == null else str((got as Dictionary).get("ghost_id", ""))))
	_ok("★②-b 佐证: 入池那份的 origin 被盖成 remote(不是 A 传来的 local)",
		got != null and str((got as Dictionary).get(Backend.ORIGIN_KEY, "")) == Backend.ORIGIN_REMOTE,
		"origin=%s" % ("-" if got == null else str((got as Dictionary).get(Backend.ORIGIN_KEY, "缺"))))

	## ★反面: 我【自己】传的那份仍然要被跳过(否则修好 V2 的代价是"能打到自己")。
	var poolS := {"brackets": {}}
	var mine := _good()
	mine["ghost_id"] = "g_1_我自己"
	mine[Backend.ORIGIN_KEY] = Backend.ORIGIN_LOCAL
	Backend.pool_add(poolS, mine)
	_ok("★★②-b反面: origin=local 的仍然被跳过(不会打到自己)",
		Backend.pool_find(poolS, 3, [], RandomNumberGenerator.new()) == null)
	## ★老池子兼容: 2026-08-26 前存的没有 origin 字段, 靠名字仍判自己。
	var poolO := {"brackets": {}}
	var legacy := _good()
	legacy["ghost_id"] = "g_1_老条目"
	legacy.erase(Backend.ORIGIN_KEY)
	Backend.pool_add(poolO, legacy)
	_ok("★②-b兼容: 老条目(无 origin + 名为玩家阵容)仍判自己",
		Backend.pool_find(poolO, 3, [], RandomNumberGenerator.new()) == null)

	# ────────── V1 / V5: 断网 ──────────
	## ★★2026-08-27 起 `project.godot` 里【真的填了地址】(Deno Deploy 已部署),
	##   所以这条不能再断言"未配置"。要守的东西变了 ——
	##   守的是【空 URL 时整层停用】这条硬保证本身, 而不是"现在恰好是空的"。
	##   ⇒ 用环境变量临时清空来验它。(env 优先级高于 ProjectSettings, 见 base_url()。)
	## ⚠ 要**删掉**环境变量而不是设成空串: `base_url()` 用 `has_environment` 判优先级,
	##   设成空串 = "env 里配了个空地址" ⇒ 仍然走 env 那条, 回不到 ProjectSettings。
	##   (顺带记下这个行为: 环境里若残留一个空的 TURTLE_BACKEND, 会**静默停用整层**。
	##    这是有意的 —— 空地址就该停用 —— 但排查时值得第一个想到。)
	OS.set_environment(RemotePool.ENV_KEY, " ")     # 空白串 = 停用
	_ok("★★分母: 【URL 为空时整层停用】—— 这条保证在, 断网/没配后端才不会退化",
		not RemotePool.enabled(), "base_url=[%s]" % RemotePool.base_url())
	OS.unset_environment(RemotePool.ENV_KEY)
	## ★★2026-09-01 改口径: 配置里的地址现在**是空的, 而且是有意的**。
	##   原因: Deno Deploy 那个部署没了(根路径回 404 DEPLOYMENT_NOT_FOUND), 而用户
	##   2026-09-01 明确「别deno了」; 腾讯云那套(server/cloudbase/)代码现成但要实名+备案,
	##   也被否掉 ⇒ 异步 PvP 先关。游戏本来就是"可选同步"设计, 离线完整可玩、对手用 bot。
	##   ⇒ 这条从"配置里必须有真地址"改成**"配置里就该是空的"**。
	##   ⚠ 但不能只改成"是空的就算过" —— 那样"启用路径"就没人验了, 哪天接上新后端
	##      发现根本启不起来。所以下面**紧接着**用 env 塞一个地址验它真能启用。
	_ok("★★配置里的后端地址是空的(2026-09-01 主动清空 —— 见 verify_backend_not_silent)",
		str(ProjectSettings.get_setting("turtle/backend_url", "")).strip_edges() == "",
		"base_url=[%s]" % RemotePool.base_url())
	OS.set_environment(RemotePool.ENV_KEY, "https://example.invalid")
	var _can_enable: bool = RemotePool.enabled() and RemotePool.base_url().begins_with("http")
	OS.unset_environment(RemotePool.ENV_KEY)
	_ok("★★分母: 塞一个地址进去本层**真的能启用** —— 否则将来接新后端会发现它是死的",
		_can_enable, "启用路径本身必须还活着")

	## ★冒烟测试数据不许入池 —— 它躺在【真的生产池】里, 客户端认前缀挡住。
	var smoke := _good()
	smoke["ghost_id"] = RemotePool.SMOKE_PREFIX + "A"
	_ok("★★冒烟测试快照(%s…)被拒, 永远不会变成谁的对手" % RemotePool.SMOKE_PREFIX,
		not bool(RemotePool.snapshot_valid(smoke)["ok"]),
		str(RemotePool.snapshot_valid(smoke)["reason"]))

	## 真装上一个**打不通**的地址, 走真 HTTPRequest。
	OS.set_environment(RemotePool.ENV_KEY, DEAD_URL)
	_ok("★分母: 已把后端指向不可达地址 %s(本层现在是启用的)" % DEAD_URL, RemotePool.enabled())

	var rp := RemotePool.new()
	add_child(rp)

	## V1 的真判据: **匹配路径不等网络**。先量 find_opponent 的墙钟。
	var t0 := Time.get_ticks_msec()
	var opp := Backend.find_opponent(3, [], RandomNumberGenerator.new())
	var dt := Time.get_ticks_msec() - t0
	_ok("★★V1 断网时仍能找到对手(离线不退化·硬指标)",
		opp is Dictionary and not (opp as Dictionary).is_empty(),
		"对手 %s" % str((opp as Dictionary).get("ghost_id", "?")))
	_ok("★★V1 匹配【一步都不等网络】: 耗时 %d ms ≪ 超时 %d ms" % [dt, int(RemotePool.TIMEOUT_SEC * 1000)],
		dt < 500, "实测 %d ms" % dt)

	## V5: 让上传和拉取都真的失败一次, 断言存档与池子【一个字节都没变】。
	var save_before := _read("user://save.json")
	var pool_before := _read(Backend.POOL_PATH)
	var fetched := {"done": false, "st": {}}
	rp.fetch_bracket(3, func(st: Dictionary) -> void:
		fetched["done"] = true
		fetched["st"] = st
	)
	rp.upload(_good())
	var w := 0
	while w < 900 and not bool(fetched["done"]):
		await get_tree().process_frame
		w += 1
	_ok("★分母: 拉取真的回调了(不是超时把测试拖到底)", bool(fetched["done"]), "等了 %d 帧" % w)
	_ok("★★V5 拉取失败 ⇒ 一份都没入池", int((fetched["st"] as Dictionary).get("added", -1)) == 0,
		str(fetched["st"]))
	_ok("★★V5 失败不影响【存档】(逐字节比对)", _read("user://save.json") == save_before)
	_ok("★★V5 失败不影响【本地池文件】(逐字节比对)", _read(Backend.POOL_PATH) == pool_before)

	## ★收尾还原: 不许把环境变量留给同进程后面的用例(CLAUDE.md 测试纪律)。
	## ★2026-09-01: 配置里的地址已清空(后端主动关掉), 所以删掉 env 之后本层是
	##   **停用**的 —— 这正是预期。判据从"回到真地址"改成"回到配置说了算"。
	OS.unset_environment(RemotePool.ENV_KEY)
	_ok("★收尾: 环境变量已删除, 本层回到【配置说了算】(配置为空 ⇒ 停用, 这是有意的)",
		not OS.has_environment(RemotePool.ENV_KEY)
		and RemotePool.base_url() == str(ProjectSettings.get_setting("turtle/backend_url", "")),
		"base_url=[%s]" % RemotePool.base_url())
	await _t_v6_5xx(rp)
	rp.queue_free()
	_done()


func _read(p: String) -> String:
	if not FileAccess.file_exists(p):
		return "<不存在>"
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f != null else "<打不开>"


func _done() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 34:
		print("  [FAIL] ★分母: 断言只有 %d 条(<34) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 阵容上传后端客户端层" if _fail == 0 else "FAIL x%d — 阵容上传后端客户端层" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# V6 ★★后端【连得上但返 5xx】也必须静默降级
#
#   ★由来(2026-08-30): 我去实测现用后端, 发现它**整个挂了** ——
#     GET / 、/health 、/ghost?bracket=3 **全部 503**,
#     正文是 "Deno Deploy encountered an error while processing this request."
#     而上面 V1/V5 验的是【连不上】(指向不可达地址), **没有一条验过"连得上但 5xx"**。
#     这两条是不同的代码路径: 连不上走 `RESULT_SUCCESS != result`,
#     5xx 走的是 `code` 分支, 而且**回调里带着一段 HTML 正文**(不是 JSON)。
#
#   ★用 `_transport` 注入(它就是为这个留的缝), 不需要真服务器。
# ─────────────────────────────────────────────────────────────
const DENO_503_BODY := "Deno Deploy encountered an error while processing this request."


func _t_v6_5xx(rp) -> void:
	print("── V6 后端 5xx(不是连不上) ──")
	var calls := {"n": 0}
	## 注入: 每次请求都回 503 + 一段【HTML 正文】(照实测的真实形态)
	## ★V6 要走到 `_transport`, 本层必须【是启用的】—— `upload()` 开头
	##   `if not enabled(): return`。配置清空之后这里得自己塞个地址进来,
	##   否则注入的传输层一次都不会被调到(2026-09-01 实测: 0 次)。
	OS.set_environment(RemotePool.ENV_KEY, "https://example.invalid")
	rp._transport = func(_m: String, _u: String, _b: String, cb: Callable) -> void:
		calls["n"] += 1
		if cb.is_valid():
			cb.call({"ok": false, "code": 503, "body": DENO_503_BODY})

	var save_before := _read("user://save.json")
	var pool_before := _read(Backend.POOL_PATH)
	rp._upload_flash = false
	var got := {"done": false, "st": {}}
	rp.fetch_bracket(3, func(st: Dictionary) -> void:
		got["done"] = true
		got["st"] = st
	)
	rp.upload(_good())
	var w2 := 0
	while w2 < 300 and not bool(got["done"]):
		await get_tree().process_frame
		w2 += 1

	## ★分母: 注入真的被走到了(否则下面全是恒真式 —— 没发请求当然什么都没坏)
	_ok("V6 ★分母: 注入的传输层真的被调用了(上传+拉取共 %d 次)" % int(calls["n"]),
		int(calls["n"]) >= 2, "只有 %d 次" % int(calls["n"]))
	_ok("V6 ★分母: 拉取真的回调了", bool(got["done"]), "等了 %d 帧" % w2)
	_ok("V6 ★★5xx ⇒ 一份都没入池", int((got["st"] as Dictionary).get("added", -1)) == 0,
		str(got["st"]))
	_ok("V6 ★★5xx ⇒ 不许显示「阵容已上传」(它是成功才亮的)",
		not bool(rp._upload_flash), "_upload_flash=%s" % str(rp._upload_flash))
	_ok("V6 ★★5xx 不影响【存档】(逐字节比对)", _read("user://save.json") == save_before)
	_ok("V6 ★★5xx 不影响【本地池文件】(逐字节比对)", _read(Backend.POOL_PATH) == pool_before)
	rp._transport = Callable()
	OS.unset_environment(RemotePool.ENV_KEY)   # ★收尾: 不许留给后面的用例

	## ★★V6-b 直接量【"算不算成功"那句判断】本身 —— 上面注入 `_transport` 会绕过它。
	##   反向验证抓到过: 把它改成不看状态码, 上面六条照样全绿。
	var OKR: int = HTTPRequest.RESULT_SUCCESS
	var BADR: int = HTTPRequest.RESULT_CANT_CONNECT
	_ok("V6-b ★分母: 200 必须算成功(不然下面全是恒真式)", RemotePool.resp_ok(OKR, 200))
	_ok("V6-b ★★503 不算成功(实测现用后端就是全线 503)", not RemotePool.resp_ok(OKR, 503))
	_ok("V6-b ★★500 / 502 / 429 / 404 / 301 都不算成功",
		not RemotePool.resp_ok(OKR, 500) and not RemotePool.resp_ok(OKR, 502)
		and not RemotePool.resp_ok(OKR, 429) and not RemotePool.resp_ok(OKR, 404)
		and not RemotePool.resp_ok(OKR, 301))
	_ok("V6-b 边界: 299 算成功 / 300 不算(挡 off-by-one)",
		RemotePool.resp_ok(OKR, 299) and not RemotePool.resp_ok(OKR, 300))
	_ok("V6-b 连不上时即使 code=200 也不算成功(两条路都要挡)",
		not RemotePool.resp_ok(BADR, 200))
