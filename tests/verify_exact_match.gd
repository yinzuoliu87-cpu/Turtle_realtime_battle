extends Node
## verify_exact_match.gd — A6：**只和场次完全相同的人打**，同场次里取最新的那份
##
## ★★为什么这条门禁非有不可（方案书 §2.3 自己写的警告）:
##   `pool_find` 有 **10 处调用**(产品 1 / 门禁 5 / 探针 4), 新参数必须带默认值,
##   否则一起炸。**但带了默认值就意味着老门禁全绿却一条新行为都没验到** ——
##   不能靠"现有门禁没红"当作没问题(同族 memory: 判据没错但被测对象不在场)。
##
## ★由来(母方案书 §10.35 C7): 旧 `player_ghost_id` **不含场次**, 而 `pool_add` 按 id 去重
##   ⇒ 同一玩家在池里只有最新一份 ⇒ **场次比你低的人永远匹配不到你**, 而且是静默的。
##
## ★D10「同场次的多份按上传时刻倒序取最新」**不需要时间戳字段**:
##   `pool_add` 用 `bucket.push_front(snapshot)` ⇒ 桶本身就是上传倒序。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_exact_match.tscn --quit-after 900

const Backend := preload("res://scripts/net/backend.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _ok := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 造一份【别人的】快照。★必须带 origin=remote, 否则 `_is_self_ghost` 会把它当自己跳掉,
## 那样"没选中"就成了**别的原因**造成的, 判据变恒真式。
func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": Backend.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"bracket": 3,
		"origin": Backend.ORIGIN_REMOTE,
		"profile": {"name": "对手%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}

func _ready() -> void:
	await get_tree().process_frame
	print("── A6: 精确同场次 + 倒序取最新 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919

	## ── ① 场数不同的三份 ⇒ 必须选中场数 == N 的那份 ──
	var pool := {"brackets": {}}
	Backend.pool_add(pool, _ghost("r_low", 5))
	Backend.pool_add(pool, _ghost("r_mine", 12))
	Backend.pool_add(pool, _ghost("r_high", 20))
	_chk("① ★分母: 桶里确实有 3 份", (pool["brackets"]["3"] as Array).size() == 3,
		"%d 份" % (pool["brackets"]["3"] as Array).size())
	## ★先证明【不加过滤】时这三份都可能被选中 —— 否则下面"选中了 r_mine"
	##   可能只是因为另外两份本来就进不了候选, 判据就没测到过滤。
	var seen := {}
	for i in range(60):
		var r = Backend.pool_find(pool, 3, [], rng)
		if r != null:
			seen[str(r.get("ghost_id", ""))] = true
	_chk("① ★分母: 不加过滤时三份都可能被选中(证明过滤才是起作用的那一步)",
		seen.size() == 3, "选到过 %s" % str(seen.keys()))

	var got = Backend.pool_find(pool, 3, [], rng, 12)
	_chk("① ★精确过滤: 选中了场数 12 的那份", got != null and str(got.get("ghost_id", "")) == "r_mine",
		str(got.get("ghost_id", "")) if got != null else "null")
	var none = Backend.pool_find(pool, 3, [], rng, 7)
	_chk("① ★池里没有场数 7 的人 ⇒ 返回 null(回落交给 find_opponent, 不在这里兜底)",
		none == null)

	## ── ② 两份同为 N 场、上传先后不同 ⇒ 必须选中【较新】的那份 ──
	var pool2 := {"brackets": {}}
	Backend.pool_add(pool2, _ghost("r_old", 12))    # 先传
	Backend.pool_add(pool2, _ghost("r_new", 12))    # 后传 ⇒ push_front ⇒ 在前
	_chk("② ★分母: 两份都在且场数相同", (pool2["brackets"]["3"] as Array).size() == 2)
	var got2 = Backend.pool_find(pool2, 3, [], rng, 12)
	_chk("② ★同场次取最新那份(桶序 = 上传倒序)",
		got2 != null and str(got2.get("ghost_id", "")) == "r_new",
		str(got2.get("ghost_id", "")) if got2 != null else "null")

	## ── ③ ghost_id 真的带上了场次维, 且同一人不同场次【并存】不互相顶掉 ──
	var id_a: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 3)
	var id_b: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 4)
	var id_old: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"])
	_chk("③ ★同一人同阵容、不同场次 ⇒ 不同 id", id_a != id_b, "%s vs %s" % [id_a, id_b])
	## ★判据要卡住【结尾的 _b<数字>】, 不能用 `contains("_b")` ——
	##   老格式 id 里的 `_basic` 就含 "_b", 第一版这么写当场误报。
	##   (同族: 「判据要刚好卡住那个形状」—— 宽一格就造出假 bug。)
	var re_suffix := RegEx.new()
	re_suffix.compile("_b[0-9]+$")
	_chk("③ ★带场次时结尾是 _b<数字>", re_suffix.search(id_a) != null, id_a)
	_chk("③ ★不传场次 = 老格式(留给只验 id 互不相同的老门禁)",
		re_suffix.search(id_old) == null, id_old)
	var pool3 := {"brackets": {}}
	Backend.pool_add(pool3, _ghost(id_a, 3))
	Backend.pool_add(pool3, _ghost(id_b, 4))
	_chk("③ ★★同一人的两个场次在池里【并存】(这正是「场次低的人也能匹配到你」的前提)",
		(pool3["brackets"]["3"] as Array).size() == 2,
		"%d 份" % (pool3["brackets"]["3"] as Array).size())

	## ── ④ 记账: 各来源各自计数(A-R3 靠它才答得了) ──
	var c0 := int(Backend.match_src_counts.get("exact", 0))
	Backend._tally("exact")
	_chk("④ ★匹配来源记账在走(exact 计数 +1)",
		int(Backend.match_src_counts.get("exact", 0)) == c0 + 1)
	## ★2026-09-25: 回落链从 exact/bucket/bot 变成 exact/near/below/bot。
	##   记账键漏一个 = 那一级的占比永远是 0 而没人发现(A-R3 那条未决点就答不了)。
	for k in ["exact", "near", "below", "bot"]:
		_chk("④ ★记账键 `%s` 在册(回落链改了而键没跟上 ⇒ 那一级恒为 0)" % k,
			Backend.match_src_counts.has(k), str(Backend.match_src_counts))

	_t_symmetry()
	_done()


# ─────────────────────────────────────────────────────────────
# ⑤ 端到端: 同场次命中率 + 硬边界 / ⑤b 窗口函数本身对称
## ══════════════════════════════════════════════════════════════════
## ★★★2026-09-25 第二版: 判据从「端到端抽样的上下比例」改成两条各就各位的。
##
## 第一版写的是「真种子池上抽 480 次, 往上/往下都得 > 0」。它在**旧池**上成立
## (偏斜 2.44:1), 而池子重做之后 **480/480 全是同场次** —— 第 ②③ 级根本不再触发,
## 那两条于是永远满足不了。
##
## ⚠ 这**不是判据太严, 是判据摆错了位置**: 窗口对称是 `pool_find_near` 这个
##   **窗口函数**的性质, 而「端到端抽到谁」还取决于池子有多密。池子够密时
##   第 ① 级(等场次)本来就该垄断 —— 那正是我们想要的结果, 不是缺陷。
##   ⇒ 对称性下移到 ⑤b 用**合成池**直接量窗口函数; 端到端这一侧改量
##     「同场次命中率」—— 它才是重跑真正买到的东西。
##
## ★★「同场次命中率」照样守得住第一版抓到的那个 bug: 当 `find_opponent`
##   忽略入参、照旧读 `GameState.season_total_battles`(门禁里恒为 0)时,
##   每一抽都会抽到 0 场次的快照 ⇒ 命中率掉到 0 ⇒ **当场红**。
##   (硬边界那条守不住它: 0 ≤ N+1 永远成立。)
const EXACT_RATE_FLOOR := 0.90     # 新池 0~24 每格 12 支 ⇒ 实测应接近 1.00
const SYM_SKEW_CAP := 1.5          # ⑤b 合成池上窗口两侧的最大偏斜

func _t_symmetry() -> void:
	print("── ⑤ 端到端: 同场次命中率 + 硬边界(真种子池) ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925
	var up := 0
	var down := 0
	var same := 0
	var bots := 0
	var over := 0
	var draws := 0
	var SPAN: int = int(_P2.MATCH_BATTLES_SPAN)
	for n in range(1, 25):            # 从 1 起 —— n=0 往下没有格子
		for _i in range(20):
			var g: Dictionary = Backend.find_opponent(n, [], rng)
			draws += 1
			if bool(g.get("is_bot", false)):
				bots += 1
				continue
			var gb := int(g.get("season_total_battles", -1))
			if gb > n + SPAN:
				over += 1
			elif gb > n:
				up += 1
			elif gb < n:
				down += 1
			else:
				same += 1
	_chk("⑤ ★分母: 抽够了(%d 次)" % draws, draws == 24 * 20, "实抽 %d" % draws)
	_chk("⑤ ★★分母: 真快照占多数(全是 bot 的话下面全是空检查)",
		draws - bots >= draws / 2, "真快照 %d / bot %d" % [draws - bots, bots])
	_chk("⑤ ★★★对手场次绝不比我多超过 %d" % SPAN, over == 0, "越线 %d 次" % over)
	var rate := float(same) / float(maxi(1, draws - bots))
	print("     实测: 等场次 %d / 往上 %d / 往下 %d / 越线 %d / bot %d  ⇒ 同场次命中率 %.3f"
		% [same, up, down, over, bots, rate])
	_chk("⑤ ★★★同场次命中率 ≥ %.2f(这是对手池按【场次】重做买到的东西; "
		% EXACT_RATE_FLOOR + "入参被忽略而照读全局时它会掉到 0)",
		rate >= EXACT_RATE_FLOOR, "实测 %.3f" % rate)
	_t_window_symmetry()


# ─────────────────────────────────────────────────────────────
# ⑤b ★★★窗口函数本身对称 —— 用合成池, 不靠真池子刚好有洞
# ─────────────────────────────────────────────────────────────
## 用户 2026-09-25:「我的档是 5 场次的, 我要和 6 场次的人打? 这不合理啊」
##
## 造一个**只有 N-1 和 N+1** 的池子(N 那一格故意空着), 让 `pool_find_near`
## 在 [N-1, N+1] 上抽很多次, 两侧都得抽得到、而且大致各一半。
##
## ★这样量才对: 真池子密的时候第 ① 级垄断, 端到端**永远走不到**这个窗口;
##   而「窗口偏心」恰恰是用户投诉的那件事 —— 它必须有自己的判据。
## ★反向验证: 把窗口改成 `(N, N+1)`(就是 2026-09-25 之前那版偏心窗口),
##   下面「往下抽得到」当场红; 改成只往下, 「往上抽得到」当场红。
func _t_window_symmetry() -> void:
	print("── ⑤b 窗口函数本身对称(合成池: N 那一格故意空着) ──")
	var N := 5
	var pool := {"brackets": {}}
	for k in range(6):
		Backend.pool_add(pool, _ghost_at("lo%d" % k, N - 1))
		Backend.pool_add(pool, _ghost_at("hi%d" % k, N + 1))
	_chk("⑤b ★分母: 合成池里 N=%d 那一格确实是空的(否则量的是别的东西)" % N,
		_count_at(pool, N) == 0, "N 那格 %d 条" % _count_at(pool, N))
	_chk("⑤b ★分母: N-1 与 N+1 两侧各 6 条", _count_at(pool, N - 1) == 6
		and _count_at(pool, N + 1) == 6,
		"%d / %d" % [_count_at(pool, N - 1), _count_at(pool, N + 1)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var lo := 0
	var hi := 0
	var span: int = int(_P2.MATCH_BATTLES_SPAN)
	for _i in range(400):
		var g = Backend.pool_find_near(pool, N - span, N + span, [], rng)
		if g == null:
			continue
		var gb := int((g as Dictionary).get("season_total_battles", -1))
		if gb < N:
			lo += 1
		elif gb > N:
			hi += 1
	_chk("⑤b ★分母: 400 次都抽到了东西", lo + hi == 400, "实得 %d" % (lo + hi))
	_chk("⑤b ★★★往【下】那一格抽得到(窗口只开上面 = 用户投诉的那个 bug)", lo > 0, "往下 %d" % lo)
	_chk("⑤b ★★★往【上】那一格抽得到(窗口只开下面 = 反过来的偏心)", hi > 0, "往上 %d" % hi)
	var skew := float(maxi(lo, hi)) / float(maxi(1, mini(lo, hi)))
	print("     实测: 往下 %d / 往上 %d  ⇒ 偏斜 %.2f:1" % [lo, hi, skew])
	_chk("⑤b ★★两侧大致各一半(偏斜 ≤ %.1f:1)" % SYM_SKEW_CAP,
		skew <= SYM_SKEW_CAP, "实测 %.2f:1" % skew)


## 造一份【别人的】快照, `bracket` 字段按真场次算 —— 不能写死。
## ★`pool_add` 按 `bracket` 字段分桶, 而 `pool_find_near` 按
##   `bracket_for_battles(n)` 去找桶: 两者对不上就永远抽不到
##   (N-1=4 在档2, N+1=6 在档3, 写死成 3 的话下面那一格根本进不了池)。
func _ghost_at(id: String, battles: int) -> Dictionary:
	var g := _ghost(id, battles)
	g["bracket"] = Backend.bracket_for_battles(battles)
	return g


func _count_at(pool: Dictionary, battles: int) -> int:
	var n := 0
	for bk in (pool.get("brackets", {}) as Dictionary):
		for g in (pool["brackets"][bk] as Array):
			if int((g as Dictionary).get("season_total_battles", -1)) == battles:
				n += 1
	return n

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 精确同场次匹配 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
