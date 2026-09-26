extends Node
## verify_gauntlet_match.gd — 周六闯关赛的匹配：**永不跨标签** (E-A4, 2026-09-22)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 原稿逐字：「只有战绩标签完全相同者互配（3-1 只碰 3-1）。同标签 ⟹ 同场数 ⟹
##   周六内供给完全一致；兜底链：同标签真人排队 → 同标签新鲜快照（30 分钟内）→ 机器人。
##   **永不跨标签**」。
##
## 这条规则**错了不会报错**，只会表现成「周六老是打到机器人」或者更糟 ——
## 打到一个战绩不同、因此经济供给差一整场的人，而双方都不知道。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 池子**自己造**（合成快照，不依赖真存档/真网络）——
##     拿随机 spawn 的真数据测精确匹配会 CI 偶发红（memory `fb-ci-vs-local-divergence`）。
## ★② 每条判据配**分母**：先证明池子里确实有那一格、也确实有别的格，
##     否则「没配到 3-2」可能只是因为池子是空的。
## ★③ 新鲜度窗口是**过滤**不是排序（与积分赛 D10 相反）⇒ 要验「超窗的同标签快照**不用**」，
##     而且要证明它超窗之前是**会被用**的 —— 只验一侧等于没验。
## ★④ 查询串是纯函数，逐字段比对：`gw=eq.` / `gl=eq.` **不能是** `in.()`。
##     放宽一格就是让 3-1 打 3-2，而那正是这个赛制唯一要守的东西。
## ★⑤ 回落到机器人时记的是**另一个计数**（`gauntlet_bot`）——
##     「周六有多少场是打机器人的」是方案书 R2 那条风险唯一能回答的数字。
##
## 跑法: <godot> --headless --path . res://tests/verify_gauntlet_match.tscn --quit-after 900

const BE := preload("res://scripts/net/backend.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 闯关赛匹配: 永不跨标签 (E-A4) ===")
	_t_query()
	_t_pool_pick(gs)
	_t_row()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 闯关赛匹配" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 查询串: 标签必须【完全相等】, 不许是区间
# ─────────────────────────────────────────────────────────────
func _t_query() -> void:
	print("── ① 查询串 ──")
	var q: String = SB.gauntlet_query(1789344000, 3, 1, "abc")
	print("  ① 实得: %s" % q)
	_ok("① ★分母: 查询串不是空的", q != "", q)
	_ok("① ★胜场用 eq(完全相等), **不是** in(区间)",
		q.find("gw=eq.3") >= 0 and q.find("gw=in.") < 0, q)
	_ok("① ★负场同样用 eq",
		q.find("gl=eq.1") >= 0 and q.find("gl=in.") < 0, q)
	_ok("① 排除自己", q.find("account_id=neq.abc") >= 0, q)
	_ok("① 限定本周", q.find("season_week=eq.1789344000") >= 0, q)

	## ★★与积分赛那条**对照**: 那边是 in.(N-1, N, N+1) 允许差一场, 这边一格都不让。
	##   这条对照就是「永不跨标签」的形状本身 —— 两条查询串长得一样才是出了问题。
	var rq: String = SB.opponents_query(1789344000, 7, "abc")
	_ok("① ★★分母: 积分赛那条**确实**是区间(证明两套口径真的不同)",
		rq.find("battles=in.(6,7,8)") >= 0, rq)

	## 入参不合法一律返回空串 —— 宁可不查, 也不要查出一池子别人的行
	_ok("① 负数标签 → 空串", SB.gauntlet_query(1789344000, -1, 0, "abc") == "")
	_ok("① 没账号 → 空串", SB.gauntlet_query(1789344000, 0, 0, "") == "")
	_ok("① 没周锚点 → 空串", SB.gauntlet_query(0, 0, 0, "abc") == "")


# ─────────────────────────────────────────────────────────────
# ② 选靶: 同标签才选, 超窗不选, 都没有才 null
# ─────────────────────────────────────────────────────────────
func _mk(gid: String, gw: int, gl: int, age_sec: int) -> Dictionary:
	## 合成快照: 只带匹配层真正读的那几个字段。
	## ★用合成的不用真存档 —— 拿随机 spawn 的真数据测精确匹配会 CI 偶发红。
	return {
		"ghost_id": gid, "name": "假人" + gid, "avatar": "basic",
		"gl_w": gw, "gl_l": gl,
		"gl_ts": int(Time.get_unix_time_from_system()) - age_sec,
	}


func _t_pool_pick(gs) -> void:
	print("── ② 选靶(本地池) ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	## ★★★2026-09-26: 池子改成**产品真正生产的那个形状**。
	##
	## 原来这里手写的是**扁平** `{ghost_id: snapshot}`, 而 `load_pool()` / `pool_add()`
	## 生产的是 `{"_seed_ver": int, "brackets": {"档": [snapshot…]}}` ——
	## **那个扁平形状全仓没有任何地方会产生**。
	## 后果: `gauntlet_pool_find` 里写的是 `for gid in pool.keys()`(读错了一层),
	## 真实池子下 `cands` **恒为空** ⇒ 周六**每一场都是机器人**, 而这份门禁
	## 一直是绿的(memory fb-gate-subject-never-constructed: 判据没错但被测对象不在场)。
	##
	## ⇒ 现在一律走 `BE.pool_add()` 灌池 —— 形状由**产品自己**决定, 我不再手写一份。
	var pool := {}
	for sn in [_mk("x_a", 3, 1, 60),        # 同标签, 新鲜
			_mk("x_b", 3, 1, 120),          # 同标签, 新鲜
			_mk("x_c", 3, 2, 60),           # ★差一格 —— 绝不能选中
			_mk("x_d", 2, 1, 60),           # ★差一格
			_mk("x_e", 4, 0, 60)]:          # ★已晋级的人
		BE.pool_add(pool, sn)
	var fresh: int = int(P2.FRESH_SNAPSHOT_SEC)
	BE.pool_add(pool, _mk("x_old", 3, 1, fresh + 600))   # 同标签但**超窗**
	## ★★有标签、**没时间戳**的快照(老格式/写一半的行)。
	##   不放这一份的话, 产品里那句 `ts <= 0` 的防御分支**一次都没被执行过**
	##   —— 实测变异(把那一半拿掉)没红, 因为池里压根没这种形状
	##   (memory `fb-gate-subject-never-constructed`)。
	BE.pool_add(pool, {"ghost_id": "x_nots", "name": "无时间戳", "avatar": "basic",
		"gl_w": 3, "gl_l": 1})
	## ★★**未来时间戳**(设备时钟走快 / 伪造的行): `now - ts` 为负
	##   ⇒ 比任何阀值都小 ⇒ 不守的话它就是一份**永不过期**的快照。
	BE.pool_add(pool, _mk("x_future", 3, 1, -86400))

	## ★分母: 池子里确实同时有"同标签"和"别的格", 否则下面全是空检查
	var same := 0
	var other := 0
	for b in (pool.get("brackets", {}) as Dictionary):
		for g in ((pool["brackets"] as Dictionary)[b] as Array):
			if int((g as Dictionary).get("gl_w", -1)) == 3 and int((g as Dictionary).get("gl_l", -1)) == 1:
				same += 1
			else:
				other += 1
	## ★★这一条同时是「池子形状对不对」的分母: 手写扁平池时它也是 5/3,
	##   所以它守不住形状 —— 形状由下面那条「真实结构下也选得中」守。
	_ok("② ★分母: 池里同标签 5 份(超窗/没时间戳/未来时间戳 各一) + 别的格 3 份",
		same == 5 and other == 3, "同标签 %d / 其它 %d" % [same, other])

	## 连抽 30 次 —— 一次抽中对的可能是运气, 30 次都对才说明判据在起作用
	var picked := {}
	for _i in range(30):
		var g = BE.gauntlet_pool_find(pool, 3, 1, [], rng)
		if g == null:
			picked["<null>"] = true
		else:
			picked[str(g.get("ghost_id", "?"))] = true
	var keys: Array = picked.keys()
	keys.sort()
	print("  ② 30 次抽到的集合: %s" % str(keys))
	_ok("② ★30 次抽到的**全部**是同标签且新鲜的那两份(x_a/x_b)",
		keys == ["x_a", "x_b"], str(keys))
	_ok("② ★★一次都没抽到差一格的(3-2 / 2-1 / 4-0) —— 永不跨标签",
		not (picked.has("x_c") or picked.has("x_d") or picked.has("x_e")), str(keys))
	_ok("② ★超窗的同标签快照一次都没被选(30 分钟窗口是【过滤】)",
		not picked.has("x_old"), str(keys))
	_ok("② ★★有标签但**没时间戳**的一律当不新鲜排除(否则等于永不过期)",
		not picked.has("x_nots"), str(keys))
	_ok("② ★★**未来时间戳**的快照一次都没被选(否则它永不过期)",
		not picked.has("x_future"), str(keys))

	## ★★另一侧: 把那份超窗的改成新鲜, 它就**必须**能被选中 ——
	##   只验"超窗不选"是半条判据, 那样"永远不选任何东西"也能绿。
	## ★按**真实结构**找到那一份再改 —— 扁平写法 `pool["x_old"]` 在真结构下是 null,
	##   而 `null["gl_ts"] = …` 会直接炸(或者更糟: 改了个空气, 下面那条变恒假)。
	for b2 in (pool.get("brackets", {}) as Dictionary):
		for g4 in ((pool["brackets"] as Dictionary)[b2] as Array):
			if str((g4 as Dictionary).get("ghost_id", "")) == "x_old":
				(g4 as Dictionary)["gl_ts"] = int(Time.get_unix_time_from_system()) - 30
	var seen_old := false
	for _i in range(60):
		var g2 = BE.gauntlet_pool_find(pool, 3, 1, [], rng)
		if g2 != null and str(g2.get("ghost_id", "")) == "x_old":
			seen_old = true
			break
	_ok("② ★★分母: 同一份快照改成新鲜之后【会】被选中(证明上一条不是恒假)", seen_old)

	## 排除名单要生效
	var excluded := true
	for _i in range(30):
		var g3 = BE.gauntlet_pool_find(pool, 3, 1, ["x_a", "x_b", "x_old"], rng)
		if g3 != null:
			excluded = false
			break
	_ok("② 把同标签的都排除掉 → 返回 null(回落交给上一层, 不在这里兜底)", excluded)

	## 池里没有这一格 → null
	_ok("② 池里没有 0-0 这一格 → null", BE.gauntlet_pool_find(pool, 0, 0, [], rng) == null)


# ─────────────────────────────────────────────────────────────
# ③ 上传行: 标签进得去, 缺前提就不传
# ─────────────────────────────────────────────────────────────
func _t_row() -> void:
	print("── ③ 上传行 ──")
	var snap := {"ghost_id": "g_x", "name": "阵容"}
	var row: Dictionary = SB.gauntlet_row_from_snapshot(snap, "acc-1", 1789344000, 3, 1, "0.0.1")
	_ok("③ ★分母: 行建出来了", not row.is_empty(), str(row.keys()))
	_ok("③ 标签两维都进了行", int(row.get("gw", -1)) == 3 and int(row.get("gl", -1)) == 1,
		"gw=%s gl=%s" % [str(row.get("gw")), str(row.get("gl"))])
	_ok("③ 账号/周锚点/版本号都在",
		str(row.get("account_id", "")) == "acc-1"
		and int(row.get("season_week", 0)) == 1789344000
		and str(row.get("client_version", "")) == "0.0.1", str(row))

	## ★缺前提就**不传**, 不是填个默认值 —— 填 0/空串会在服务端造出一行
	##   "看起来合法"的垃圾, 而且可能撞主键覆盖别人(与积分赛那条同一个理由)。
	_ok("③ ★没账号 → 空行(不传)",
		SB.gauntlet_row_from_snapshot(snap, "", 1789344000, 3, 1, "v").is_empty())
	_ok("③ ★没周锚点 → 空行",
		SB.gauntlet_row_from_snapshot(snap, "a", 0, 3, 1, "v").is_empty())
	_ok("③ ★负标签 → 空行",
		SB.gauntlet_row_from_snapshot(snap, "a", 1789344000, -1, 1, "v").is_empty())
	_ok("③ ★空快照 → 空行",
		SB.gauntlet_row_from_snapshot({}, "a", 1789344000, 3, 1, "v").is_empty())
