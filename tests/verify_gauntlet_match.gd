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

	## ★★与积分赛那条**对照**: 那边的查询串是 `battles=in.(N, N+1)`, 这边是 `gw/gl=eq.`。
	##   ★★★2026-09-26 这条对照的**含义变了, 判据跟着变**:
	##     以前 `in.(…)` 意味着「积分赛允许差一场」—— 那是 D5 之前的行为。
	##     现在积分赛的**匹配**也是完全相同(D5), `in.(N, N+1)` 只剩
	##     【预取下一局】这一个身份(见 `phase2_config.PULL_BATTLES_AHEAD` 头注)。
	##   ⇒ 所以这里对照的不再是「两套匹配口径不同」, 而是
	##     「**闯关赛连预取都不多拉**」—— 30 分钟新鲜度是过滤而不是排序,
	##     多拉回来的隔夜快照一条都用不上。
	var rq: String = SB.opponents_query(1789344000, 7, "abc")
	_ok("① ★★分母: 积分赛那条的**预取**确实多拉一格(证明两条查询串真的不同)",
		rq.find("battles=in.(7,8)") >= 0, rq)
	_ok("① ★★积分赛预取**一格都不往下开**(往下那格永远匹配不上, 白占名额)",
		rq.find("battles=in.(6,") < 0, rq)

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
	## 生产的是 `{"_seed_ver": int, "by_battles": {"场次": [snapshot…]}}` ——
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
	for b in (pool.get(BE.POOL_KEY, {}) as Dictionary):
		for g in ((pool[BE.POOL_KEY] as Dictionary)[b] as Array):
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
	## ★★★2026-09-26 这三条的**理由变了, 断言本身不变**:
	##   以前它们不被选是因为 30 分钟窗口把它们**整条过滤掉**;
	##   现在 30 分钟是**排序偏好**(真人新 → 真人旧 → 机器人), 它们进的是「隔夜」那一桶,
	##   而这里**有两份新鲜的顶着** ⇒ 照样一次都轮不到。
	##   ⇒ 断言不变, 但它现在守的是「**有新鲜的就一定挑新鲜的**」(C3), 更有价值:
	##     把优先级写反(先挑隔夜)会当场红, 而旧写法下"先挑隔夜"是不可能发生的。
	##   (方案书 `docs/plans/20260926-周末赛制在各规模下会怎样.md`)
	_ok("② ★★★超窗的同标签快照一次都没被选(有新鲜的就必须挑新鲜的)",
		not picked.has("x_old"), str(keys))
	_ok("② ★★没时间戳的不算新鲜(缺字段 = 0 ⇒ now-0 远超窗)", not picked.has("x_nots"), str(keys))
	_ok("② ★★**未来时间戳**不算新鲜(否则 now-ts 为负 ⇒ 比任何阈值都小 ⇒ 永不过期)",
		not picked.has("x_future"), str(keys))

	## ★★另一侧: 把那份超窗的改成新鲜, 它就**必须**能被选中 ——
	##   只验"超窗不选"是半条判据, 那样"永远不选任何东西"也能绿。
	## ★按**真实结构**找到那一份再改 —— 扁平写法 `pool["x_old"]` 在真结构下是 null,
	##   而 `null["gl_ts"] = …` 会直接炸(或者更糟: 改了个空气, 下面那条变恒假)。
	for b2 in (pool.get(BE.POOL_KEY, {}) as Dictionary):
		for g4 in ((pool[BE.POOL_KEY] as Dictionary)[b2] as Array):
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
	## ★★★排除名单要列**全部**同标签的快照。2026-09-26 之前 `x_future` / `x_nots`
	##   是被 30 分钟**过滤**掉的, 所以不列也是 null; 现在它们进「隔夜」那一桶 ⇒
	##   不列就会被抽到, 而那**不是 bug** —— 它们本来就是同标签的真人快照,
	##   降级成隔夜候选正是新规则要的(伪造未来时间戳从此换不到任何好处, 只会被降级)。
	var all_same_label := ["x_a", "x_b", "x_old", "x_nots", "x_future"]
	var excluded := true
	for _i in range(30):
		var g3 = BE.gauntlet_pool_find(pool, 3, 1, all_same_label, rng)
		if g3 != null:
			excluded = false
			break
	_ok("② 把同标签的**全部**排除掉 → 返回 null(回落交给上一层, 不在这里兜底)", excluded)
	## 池里没有这一格 → null
	_ok("② 池里没有 0-0 这一格 → null", BE.gauntlet_pool_find(pool, 0, 0, [], rng) == null)

	_t_stale_fallback()


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


## ★★★C2: 新鲜的一个都没有时, **隔夜的同标签必须顶上**, 不许掉机器人。
## 这一条是 2026-09-26 那次改动的**全部价值**: 10 个人测一周时, 30 分钟窗内同标签的人
## 期望只有 **0.07 个** ⇒ 旧规则(30 分钟是硬过滤)下周六 **93% 的对局是机器人**,
## 而周六的全部意义是「同战绩的人互相淘汰」。
## (算法与数字见 `docs/plans/20260926-周末赛制在各规模下会怎样.md` §2.2)
##
## ⚠⚠ **自己造一个干净池子, 不许复用上面那个**。我第一版复用了, 判据**为错的理由通过**:
##   上面第 ② 段中途把 `x_old` 的 `gl_ts` 改成了"新鲜"(那是它自己的分母断言要的),
##   于是我这里看到的 `x_old` 被选中根本不是"隔夜回落起作用", 而是"它现在是新鲜的" ——
##   `stale` 那一桶一次都没被碰到。探针实测(自己的池子, 200 抽):
##   x_old 59 / x_future 65 / x_nots 76, 三份都该出现, 而复用池只出现 1 份。
##   (同族 memory: fb-gate-subject-never-constructed / 测试不许依赖别处留下的状态)
func _t_stale_fallback() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260926
	var fresh2: int = int(P2.FRESH_SNAPSHOT_SEC)
	var p2 := {}
	## 全部同标签 3-1, **一份新鲜的都没有**: 超窗 / 没时间戳 / 未来时间戳
	BE.pool_add(p2, _mk("s_old", 3, 1, fresh2 + 600))
	BE.pool_add(p2, {"ghost_id": "s_nots", "name": "无戳", "avatar": "basic",
		"gl_w": 3, "gl_l": 1})
	BE.pool_add(p2, _mk("s_future", 3, 1, -86400))
	## 跨标签的两份 —— 一格都不许跨, 隔夜也不行
	BE.pool_add(p2, _mk("s_cross1", 3, 2, 60))
	BE.pool_add(p2, _mk("s_cross2", 2, 1, 60))

	var now2 := int(Time.get_unix_time_from_system())
	var n_fresh := 0
	for b3 in (p2.get(BE.POOL_KEY, {}) as Dictionary):
		for g6 in ((p2[BE.POOL_KEY] as Dictionary)[b3] as Array):
			var gd6: Dictionary = g6
			if int(gd6.get("gl_w", -1)) != 3 or int(gd6.get("gl_l", -1)) != 1:
				continue
			var ts6 := int(gd6.get("gl_ts", 0))
			if ts6 <= now2 and now2 - ts6 <= fresh2:
				n_fresh += 1
	_ok("②C2 ★★分母: 这个池里同标签的**一份新鲜的都没有**(否则量的是别的东西)",
		n_fresh == 0, "新鲜 %d 份" % n_fresh)

	var hits := {}
	for _i in range(200):
		var g7 = BE.gauntlet_pool_find(p2, 3, 1, [], rng2)
		var k7: String = "<null>" if g7 == null else str(g7.get("ghost_id", "?"))
		hits[k7] = int(hits.get(k7, 0)) + 1
	var hk: Array = hits.keys()
	hk.sort()
	print("  ②C2 只剩隔夜时 200 次抽到: %s" % str(hits))
	_ok("②C2 ★★★隔夜的同标签顶上, **一次 null 都不许有**(null = 上一层掉机器人)",
		not hits.has("<null>"), str(hk))
	_ok("②C2 ★★★三份隔夜的**都**抽得到(只抽得到一份 = 判据在蒙)",
		hits.has("s_old") and hits.has("s_nots") and hits.has("s_future"), str(hk))
	_ok("②C2 ★★★隔夜也**绝不跨标签**(3-2 / 2-1 一次都不许)",
		not (hits.has("s_cross1") or hits.has("s_cross2")), str(hk))

