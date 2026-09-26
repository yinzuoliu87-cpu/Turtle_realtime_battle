extends Node
## verify_exact_match.gd — D5：**只和总场次完全相同的人打**，同场次里取最新的那份
##
## ★★★2026-09-26 整份重写。上一版的第 ⑤/⑤b 条判据是**错的**，而且把错误焊死了：
##   它断言「窗口 [N-1, N+1] 两侧都抽得到、且大致各一半」。
##   而上游 D5（`docs/plans/20260916-大轮赛制v2周赛制.md:349`，2026-09-16 就定了）是
##   「硬条件是**双方总场次相同**（不再按 9 档）」，用户 2026-09-26 又复述一遍：
##   「从始至终应该都是同场次的人开打…**不应该有什么正负一**」。
##   ⇒ 那条判据**保证了**「5 场次的人打 6 场次的人」这件事不会被发现。
##
##   教训不是「我少读了一份文档」，是**我用自己发明的道理替掉了拍过板的需求**：
##   用户当时说「我的档是 5 场次的，我要和 6 场次的人打？这不合理啊」，
##   我把它读成「窗口不对称」（于是去补下面那一格），而他说的是「不该有差」。
##   同族 memory: fb-pin-user-words-dont-drift / fb-my-goal-can-be-wrong-not-just-my-code。
##
## ★现在的判据只有一句话：**对手的 `season_total_battles` 必须等于我的**，一次例外都不许。
##   ①~③ 量选靶原语 `pool_find_battles`；④ 量记账；⑤ 端到端真种子池；⑤b 量回落。
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
## ★★不再有 `bracket` 字段 —— 2026-09-26 删了, 分桶直接读 `season_total_battles`。
##   以前这里得手算 `bracket_for_battles(battles)` 才能让快照落进对的桶, 忘了写就
##   "永远抽不到"而看不出原因。现在**不可能写错**: 分桶键就是判据本身。
func _ghost(id: String, battles: int) -> Dictionary:
	return {
		"schema_ver": Backend.SCHEMA_VER,
		"ghost_id": id,
		"is_bot": false,
		"origin": Backend.ORIGIN_REMOTE,
		"profile": {"name": "对手%s" % id},
		"leaders": ["basic", "ninja", "stone"],
		"season_total_battles": battles,
	}

func _ready() -> void:
	await get_tree().process_frame
	print("── D5: 总场次完全相同 + 同场次取最新 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919
	var K: String = Backend.POOL_KEY

	## ── ① 三个不同场次 ⇒ 按场次取, 取到的必须正好是那一个 ──
	var pool := {K: {}}
	Backend.pool_add(pool, _ghost("r_low", 5))
	Backend.pool_add(pool, _ghost("r_mine", 12))
	Backend.pool_add(pool, _ghost("r_high", 20))
	_chk("① ★分母: 三份分别落进【三个】场次桶(不是挤在一个桶里)",
		(pool[K] as Dictionary).size() == 3,
		"桶: %s" % str((pool[K] as Dictionary).keys()))
	_chk("① ★分母: 桶键就是场次本身", (pool[K] as Dictionary).has("5")
		and (pool[K] as Dictionary).has("12") and (pool[K] as Dictionary).has("20"))

	## ★三个场次各查一次 —— 三次都得**只**命中对应那一份。
	##   只查一次是不够的: 「永远返回桶里第一个」这种实现也能通过单次查询。
	var want := {"5": "r_low", "12": "r_mine", "20": "r_high"}
	for bk in want.keys():
		var g = Backend.pool_find_battles(pool, int(bk), [], rng)
		_chk("① ★查场次 %s ⇒ 命中 %s" % [bk, want[bk]],
			g != null and str(g.get("ghost_id", "")) == str(want[bk]),
			str(g.get("ghost_id", "")) if g != null else "null")

	## ★★★这条是整份门禁的核心: 池里只有 5/12/20, 查 6 必须是 **null**。
	##   回落不在这里做(交给 `find_opponent` 记账后兜 bot) —— 这里一放宽, 上面
	##   "不应该有正负一"就从代码里消失了。
	for miss in [4, 6, 7, 11, 13, 19, 21]:
		_chk("① ★★★池里没有场次 %d ⇒ 必须 null(绝不拿邻格顶上)" % miss,
			Backend.pool_find_battles(pool, miss, [], rng) == null)

	## ── ①c ★★★用 exclude_ids 在【真池子】上凿一个洞: 邻格满着, 我这格空 ──
	## ★★这一条补的是 2026-09-26 反向验证抓到的**判据洞**: 我在 `find_opponent` 里
	##   把「±1 回落」加回去做反向验证, **五条判据一条都没红**。原因是
	##   端到端那几条(⑤)走不到回落那一级 —— 真池子 0~24 每格都有 12 支,
	##   第 ① 级永远命中; 而 ⑤b 用的 500 场次连**邻格也是空的**, 照样落到 bot。
	##   ⇒ 「回落只能是 bot」这件事, 必须在【我这格空 + 邻格满】的局面下量才算数。
	## ★洞是用**产品自己的机制**凿的(`exclude_ids` = 最近打过的对手, 本来就在用),
	##   不是给 find_opponent 加测试参数 —— 判据仍然跑的是真入口、真池子。
	var rng_h := RandomNumberGenerator.new()
	rng_h.seed = 777
	var real_pool: Dictionary = Backend.load_pool()
	var HOLE := 12
	var hole_ids: Array = []
	for g3 in ((real_pool.get(K, {}) as Dictionary).get(str(HOLE), []) as Array):
		hole_ids.append(str((g3 as Dictionary).get("ghost_id", "")))
	var nb_lo: int = ((real_pool.get(K, {}) as Dictionary).get(str(HOLE - 1), []) as Array).size()
	var nb_hi: int = ((real_pool.get(K, {}) as Dictionary).get(str(HOLE + 1), []) as Array).size()
	_chk("①c ★分母: 场次 %d 那格本来有人(排除了才空)" % HOLE, hole_ids.size() >= 5,
		"%d 条" % hole_ids.size())
	_chk("①c ★★分母: 邻格 %d / %d 是满的(否则回落无处可去, 判据恒真)" % [HOLE - 1, HOLE + 1],
		nb_lo >= 5 and nb_hi >= 5, "%d / %d 条" % [nb_lo, nb_hi])
	var hole_bots := 0
	var hole_wrong: Array = []
	for _i in range(30):
		var gh: Dictionary = Backend.find_opponent(HOLE, hole_ids, rng_h)
		if bool(gh.get("is_bot", false)):
			hole_bots += 1
		else:
			hole_wrong.append("%s(%d 场)" % [str(gh.get("ghost_id", "?")),
				int(gh.get("season_total_battles", -1))])
	_chk("①c ★★★我这格被排空、邻格满着 ⇒ 30 次全是 bot(有任何 ±N 回落都会在这里露出来)",
		hole_bots == 30, "bot %d/30; 抽到的真快照: %s"
		% [hole_bots, str(hole_wrong.slice(0, 3))])

	## ── ② 两份同为 N 场、上传先后不同 ⇒ 必须选中【较新】的那份 ──
	var pool2 := {K: {}}
	Backend.pool_add(pool2, _ghost("r_old", 12))    # 先传
	Backend.pool_add(pool2, _ghost("r_new", 12))    # 后传 ⇒ push_front ⇒ 在前
	_chk("② ★分母: 两份都在同一个场次桶里", ((pool2[K] as Dictionary)["12"] as Array).size() == 2)
	var got2 = Backend.pool_find_battles(pool2, 12, [], rng)
	_chk("② ★同场次取最新那份(桶序 = 上传倒序)",
		got2 != null and str(got2.get("ghost_id", "")) == "r_new",
		str(got2.get("ghost_id", "")) if got2 != null else "null")

	## ── ②b 桶键与快照自报的场次不符时, 以【快照自己的账】为准 ──
	## ★为什么要这条: 远端并入 / 手造池子都可能把一条 7 场次的快照塞进 "5" 桶。
	##   判据要是只看桶键, 那条脏数据就会变成 5 场次玩家的对手 —— 而这正是
	##   "存两份必然漂"的老形状(memory fb-read-a-field-nobody-writes 同族)。
	var pool2b := {K: {"5": [_ghost("liar", 7)]}}
	_chk("②b ★★桶键说 5、快照自报 7 ⇒ 查 5 必须 null(以快照的账为准)",
		Backend.pool_find_battles(pool2b, 5, [], rng) == null)
	## ★★差**正好 1** 的那一份要单独摆一条: 差 2 的那条挡不住「把判据放宽成 ±1」
	##   这种改法(2026-09-26 反向验证实测: 只改这一行的变异, 五条判据一条都没红,
	##   因为 `absi(7-5)=2 > 1` 照样被拒)。判据要刚好卡住那个形状。
	var pool2c := {K: {"5": [_ghost("liar1", 6)]}}
	_chk("②c ★★★桶键说 5、快照自报 6(只差 1) ⇒ 查 5 仍必须 null(没有容差)",
		Backend.pool_find_battles(pool2c, 5, [], rng) == null)

	## ── ③ ghost_id 真的带上了场次维, 且同一人不同场次【并存】不互相顶掉 ──
	var id_a: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 3)
	var id_b: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"], 4)
	var id_old: String = Backend.player_ghost_id(1, ["basic", "ninja", "stone"])
	_chk("③ ★同一人同阵容、不同场次 ⇒ 不同 id", id_a != id_b, "%s vs %s" % [id_a, id_b])
	## ★判据要卡住【结尾的 _b<数字>】, 不能用 `contains("_b")` ——
	##   老格式 id 里的 `_basic` 就含 "_b", 第一版这么写当场误报。
	var re_suffix := RegEx.new()
	re_suffix.compile("_b[0-9]+$")
	_chk("③ ★带场次时结尾是 _b<数字>", re_suffix.search(id_a) != null, id_a)
	_chk("③ ★不传场次 = 老格式(留给只验 id 互不相同的老门禁)",
		re_suffix.search(id_old) == null, id_old)
	var pool3 := {K: {}}
	Backend.pool_add(pool3, _ghost(id_a, 3))
	Backend.pool_add(pool3, _ghost(id_b, 4))
	_chk("③ ★★同一人的两个场次在池里【并存】(这正是「场次低的人也能匹配到你」的前提)",
		(pool3[K] as Dictionary).size() == 2,
		"桶 %s" % str((pool3[K] as Dictionary).keys()))

	## ── ④ 记账: 只剩两个来源, 而且**删掉的那两个不许还在** ──
	var c0 := int(Backend.match_src_counts.get("exact", 0))
	Backend._tally("exact")
	_chk("④ ★匹配来源记账在走(exact 计数 +1)",
		int(Backend.match_src_counts.get("exact", 0)) == c0 + 1)
	for k in ["exact", "bot"]:
		_chk("④ ★记账键 `%s` 在册" % k,
			Backend.match_src_counts.has(k), str(Backend.match_src_counts))
	## ★★★反向的那一半: `near`/`below` 是 2026-09-25 那两级回落的记账键, D5 把那两级删了。
	##   键留着的话报表会有两个**恒为 0** 的格子, 而「这条路没人走」与「这条路不存在」
	##   是两回事 —— 前者会让下一个人以为可以放心把它接回来。
	for dead in ["near", "below", "bucket"]:
		_chk("④ ★★已删回落级的记账键 `%s` 不许还在册" % dead,
			not Backend.match_src_counts.has(dead), str(Backend.match_src_counts.keys()))

	_t_exact_e2e()
	_done()


# ─────────────────────────────────────────────────────────────
# ⑤ 端到端(真种子池): 对手场次 == 我的场次, 一次例外都不许
# ─────────────────────────────────────────────────────────────
## ★★★判据就是需求本身: `对手.season_total_battles == 我的场次`。
##
## ★这一条同时守住两个历史 bug, 都不是靠"硬边界"守的:
##   ① 2026-09-25 我把签名从 `bracket` 改成 `battles` 却忘了改函数体里那行
##      `GameState.season_total_battles`(门禁里恒为 0) ⇒ 每一抽都拿 0 去找
##      ⇒ 这里 `gb == n` 全部不成立, **当场红**。
##      (老判据 `gb <= n + 1` 守不住它: 0 ≤ n+1 永远成立。)
##   ② 池子按【档】分桶时, 查 5 会翻到整个 5-7 桶 ⇒ 抽到 6/7 ⇒ 当场红。
##
## ★★必须配一条**分母**: 全是 bot 的话「场次都相等」是空检查(bot 如实报我的场次)。
##   ⇒ 单独统计 bot 占比, 并要求真快照占多数。
##   bot 占比本身就是 D5 的代价账 —— 「同场次找不到人就打机器人」到底多常见,
##   这个数说话, 不靠猜(方案书 §6.2 U1)。
const BOT_RATE_CAP := 0.10         # 新池 0~24 每格 12 支 ⇒ 实测应接近 0

func _t_exact_e2e() -> void:
	print("── ⑤ 端到端(真种子池): 对手场次必须 == 我的场次 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926
	var mismatch := 0
	var same := 0
	var bots := 0
	var draws := 0
	var worst := ""
	for n in range(0, 25):
		for _i in range(20):
			var g: Dictionary = Backend.find_opponent(n, [], rng)
			draws += 1
			var gb := int(g.get("season_total_battles", -1))
			if bool(g.get("is_bot", false)):
				bots += 1
				## ★bot 也要如实报场次 —— 它现在是**判据**不是标签:
				##   报上界(旧行为)等于让 5 场次的玩家看到"7 场次"的对手。
				if gb != n:
					mismatch += 1
					worst = "bot 报 %d 而我 %d" % [gb, n]
				continue
			if gb == n:
				same += 1
			else:
				mismatch += 1
				worst = "真快照 %d 场 vs 我 %d 场" % [gb, n]
	_chk("⑤ ★分母: 抽够了(%d 次)" % draws, draws == 25 * 20, "实抽 %d" % draws)
	_chk("⑤ ★★分母: 真快照占多数(全是 bot 的话下面那条是空检查)",
		draws - bots >= draws / 2, "真快照 %d / bot %d" % [draws - bots, bots])
	var bot_rate := float(bots) / float(maxi(1, draws))
	print("     实测: 同场次 %d / 不同场次 %d / bot %d  ⇒ bot 占比 %.3f"
		% [same, mismatch, bots, bot_rate])
	_chk("⑤ ★★★对手场次 == 我的场次, 一次例外都没有", mismatch == 0,
		"%d 次不符%s" % [mismatch, ("  最后一例: " + worst) if worst != "" else ""])
	_chk("⑤ ★bot 占比 ≤ %.2f(供给够 = 严格同场次做得成; 这是 D5 的代价账)" % BOT_RATE_CAP,
		bot_rate <= BOT_RATE_CAP, "实测 %.3f" % bot_rate)
	_t_fallback_is_bot()


# ─────────────────────────────────────────────────────────────
# ⑤b 回落: 同场次没人 ⇒ 机器人, **绝不往别的场次找**
# ─────────────────────────────────────────────────────────────
## 用户 2026-09-26:「不应该有什么正负一」。往下找也是正负一, 同样不许。
##
## ★两段量法, 各管一件事:
##   (a) 选靶原语上: 造一个**只有 N-1 和 N+1** 的池子(N 空着) ⇒ 查 N 必须 null,
##       而查 N-1 / N+1 得查得到（分母：证明池子真有东西、不是"池空所以 null"）。
##   (b) 端到端: 拿一个真种子池**肯定没有**的场次(500 场) ⇒ 必须返回 bot,
##       且 bot 如实报 500 场、装备预算走量出来的等级曲线。
##
## ★反向验证: 在 `find_opponent` 里把「往下逐格找」那一级加回来, (b) 会拿到一份
##   真快照而不是 bot ⇒ 当场红。把 `pool_find_battles` 的场次判据放宽成 ±1, (a) 红。
func _t_fallback_is_bot() -> void:
	print("── ⑤b 回落: 同场次没人 ⇒ 机器人(绝不往邻格找) ──")
	var K: String = Backend.POOL_KEY
	var N := 5
	var pool := {K: {}}
	for k in range(6):
		Backend.pool_add(pool, _ghost("lo%d" % k, N - 1))
		Backend.pool_add(pool, _ghost("hi%d" % k, N + 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	_chk("⑤b ★分母: 合成池里 N=%d 那一格确实是空的" % N,
		not (pool[K] as Dictionary).has(str(N)), "桶 %s" % str((pool[K] as Dictionary).keys()))
	_chk("⑤b ★分母: N-1 / N+1 两侧各 6 条(池子不是空的)",
		((pool[K] as Dictionary)[str(N - 1)] as Array).size() == 6
		and ((pool[K] as Dictionary)[str(N + 1)] as Array).size() == 6)
	_chk("⑤b ★分母: 查 N-1 / N+1 确实查得到(证明 null 不是「池子没货」造成的)",
		Backend.pool_find_battles(pool, N - 1, [], rng) != null
		and Backend.pool_find_battles(pool, N + 1, [], rng) != null)
	var nulls := 0
	for _i in range(200):
		if Backend.pool_find_battles(pool, N, [], rng) == null:
			nulls += 1
	_chk("⑤b ★★★两侧各 6 条、N 空着 ⇒ 200 次查 N 全部 null", nulls == 200,
		"null %d / 200" % nulls)

	## (b) 端到端: 真种子池覆盖 0~35, 500 场次一定没人
	var far := 500
	var g: Dictionary = Backend.find_opponent(far, [], rng)
	_chk("⑤b ★★★同场次一个人都没有 ⇒ 返回机器人(不是邻格的真快照)",
		bool(g.get("is_bot", false)), "is_bot=%s ghost_id=%s"
		% [str(g.get("is_bot", false)), str(g.get("ghost_id", ""))])
	_chk("⑤b ★★机器人如实报我的场次(报上界是旧 bug: 5 场次的人看到「7 场次」对手)",
		int(g.get("season_total_battles", -1)) == far,
		"报 %d / 我 %d" % [int(g.get("season_total_battles", -1)), far])
	## ★bot 强度 = 装备件数(快照的 pet_levels 战斗侧没人读)。量它走没走那条量出来的曲线。
	var lv: int = _P2.bot_level_for_battles(far)
	var cap: int = _P2.team_equip_cap(lv)
	var items := 0
	for pid in (g.get("equipped", {}) as Dictionary).keys():
		items += ((g["equipped"] as Dictionary)[pid] as Array).size()
	for lk in (g.get("minions", {}) as Dictionary).keys():
		for m in ((g["minions"] as Dictionary)[lk] as Array):
			items += ((m as Dictionary).get("equips", []) as Array).size()
	_chk("⑤b ★机器人装备预算 = team_equip_cap(bot_level_for_battles(%d)) = %d 件" % [far, cap],
		items == cap, "实得 %d 件 (Lv%d)" % [items, lv])
	## ★★场次 0 那一格: 真人在人生第一把是**全裸**的(UNIT_EQUIP_CAP 头注那条锚点),
	##   而旧算法 `2 + 档0` = Lv2 = 2 件 ⇒ bot 比真人多两件。新曲线把它修回 Lv1。
	_chk("⑤b ★★★场次 0 的机器人必须全裸(旧算法给 2 件, 违反「人生第一把没装备」)",
		_P2.team_equip_cap(_P2.bot_level_for_battles(0)) == 0,
		"cap=%d Lv=%d" % [_P2.team_equip_cap(_P2.bot_level_for_battles(0)),
			_P2.bot_level_for_battles(0)])


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 总场次完全相同匹配 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
