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
	_ok("★分母: 当前【未配置后端】⇒ 本层停用, 行为与接网前相同",
		not RemotePool.enabled(), "base_url=[%s]" % RemotePool.base_url())

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
	OS.set_environment(RemotePool.ENV_KEY, "")
	_ok("★收尾: 环境变量已还原, 本层回到停用", not RemotePool.enabled())
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
	if _n < 20:
		print("  [FAIL] ★分母: 断言只有 %d 条(<20) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 阵容上传后端客户端层" if _fail == 0 else "FAIL x%d — 阵容上传后端客户端层" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
