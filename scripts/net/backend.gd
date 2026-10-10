extends RefCounted

## Backend — V2 异步 ghost 匹配 / bot 兜底 / 排行榜 的【本地实现】(阶段4/5 MVP).
##
## 用 preload 引 (不用 class_name):
##   const Backend = preload("res://scripts/net/backend.gd")
##
## MVP 全本地: ghost 池存 user://ghost_pool.json (按进度档分桶). 接口稳定,
## 以后换 RemoteBackend(Supabase) 不动调用方. 设计见 docs/design/V2模式策划 §十三.
##
## 纯逻辑(分档/快照/池增删/bot/榜) 操作内存 Dictionary → 可单测;
## 文件 I/O (load_pool/save_pool) 是薄包装; rng 由调用方传入 → 确定可测.

## 快照结构版本。★升它 = 老快照全部作废(载入时丢掉) —— 不做向后兼容是用户 2026-08-14 拍的板:
##   「直接全部老快照全消除掉, A, 重新制作新快照」。
##   ⚠ 升版本后池子会空一阵, 所有玩家下一局先遇 bot, 直到新快照灌进来。
const SCHEMA_VER := 2
const POOL_PATH := "user://ghost_pool.json"
const SEED_PATH := "res://data/ghost_seed.json"   # 内置 10 支策划队(按档分桶), 冷启动/老档无种子时并入
## 每档桶封顶 (防无限增长, 旧的挤出)。
## ★★A6(2026-09-19) 50 → 300。50 是按【一个玩家在一个档里只占一格】设计的 ——
##   那时 `ghost_id` 不带场次, `pool_add` 按 id 去重, 所以 50 格 ≈ 50 个不同的对手。
##   加了场次这一维之后, 同一个玩家在同一档里**每个场次各占一格**:
##   档宽见下面的「进度档」表, 最宽的档跨 6 场 ⇒ 50 ÷ 6 ≈ 8 个对手,
##   池子瘦成原来的 1/6, 而"必须同场次"本来就把候选切得更细 —— 两头一挤只剩 bot。
##   ⇒ 按【最宽的档 × 原来的人数】重定。
## ⚠ **这个数必须和「ghost_id 带场次」同时改, 不许提前**:
##   2026-09-18 有过一次单独提前改它的改动, 当时 ghost_id 还不带场次 ⇒
##   只是把桶撑大而无收益, 而且注释在描述一个不存在的状态。已撤回, 这次一起改。
const BUCKET_CAP := 300

## 匹配来源记账(A6·D10「每一场都记账」)。★让「有多少场是真·同场次」变成**可量的数** ——
##   A-R3 那条未决点(「精确同场次命中率多低算太低」)没有这个数就永远答不了。
## ★静态计数器, 进程内累计; 门禁与探针直接读它。不进存档(它是观测量不是玩法状态)。
## ★★2026-09-26 键跟着回落链收到两个(D5: 同场次 → bot)。沿革:
##   · 原来 exact/bucket/bot —— bucket = 「同【格子】里随便一个」
##   · 2026-09-25 拆成 exact/near/below/bot —— near = ±1、below = 往下逐格
##   · 现在只有 exact/bot ——「正负一」和「往下找」都被 D5 删了
##   ⇒ **留着已经不可能发生的键只会让报表恒为 0**, 而恒为 0 的格子看起来像"这条路没人走",
##     跟"这条路不存在"是两回事。删掉才是诚实的。
##
## ★★★2026-09-28 `exact` 拆出【真人 / 陪练】两格。为什么必须拆:
##   探针 `_probe_seed_exact` 实测 —— 池子 396 条**全是** `seed_` 陪练, 40 次抽对手
##   40 次命中陪练, 而 `match_src_counts` 报的是 `exact: 40 / bot: 0`。
##   ⇒ 「精确同场次命中率」看着 **100%**, 而**一个真人都没碰到**。
##   A-R3 那条未决点(「命中率多低算太低」)要是拿这个数去答, 答案是反的。
##
##   ★判据不是我新发明的: 排行榜那一侧**早就在用**同一条筛子(`leaderboard()` 里
##     「陪练不上榜」= `ghost_id` 的 `seed_` 前缀)。同一个判据本来只做了一半 ——
##     现在两处都调 `is_sparring()`, 一处改另一处不会落后(手抄的副本必然落后)。
##
##   ★**不是把陪练从 exact 里删掉**: 陪练是**合法对手**(内置种子池存在的全部意义
##     就是填池子, 打到它不是 bug, 也不该记成 bot —— 记成 bot 就把"池子里有人"
##     说成了"池子是空的", 那是另一个方向的谎)。
##     ⇒ `exact` 仍是**同场次命中总数**(语义一字未改, 老判据照旧读它),
##       下面两格是它的**互斥拆分**, 不变量: `exact == exact_human + exact_seed`。
##       要答 A-R3 的人读 `exact_human`。
##
##   ★闯关赛那条链**故意不拆**: 内置种子快照里**没有** `gl_w`/`gl_l`
##     (`data/ghost_seed.json` 实测字段表里没有这一维) ⇒ `gauntlet_pool_find` 的
##     标签检查一定把它们滤掉 ⇒ `gauntlet_seed` 会是一个**恒为 0** 的格子,
##     正是上面那段话说不该留的东西。(`tests/verify_pool_truth.gd` 有一条断言钉着
##     这个前提 —— 哪天种子带上 gl_ 标签了, 它会红, 那时才该拆。)
static var match_src_counts: Dictionary = {"exact": 0, "bot": 0,
	## `exact` 的互斥拆分: 这一场同场次对手, 是真人快照还是内置陪练。
	"exact_human": 0, "exact_seed": 0,
	## 周六闯关赛那条链单独记(见 `find_gauntlet_opponent`), 不与积分赛混在一起
	"gauntlet_label": 0, "gauntlet_bot": 0}
static func _tally(src: String) -> void:
	match_src_counts[src] = int(match_src_counts.get(src, 0)) + 1


## 同场次命中一次 —— 记总数, 同时把它记进【真人 / 陪练】里互斥的那一格。
## ★入参是**真的那份快照**, 不是我另算一遍: 记账要量产品自己交出去的对手。
static func _tally_exact(g) -> void:
	_tally("exact")
	_tally("exact_seed" if is_sparring(g) else "exact_human")
const _P2 = preload("res://scripts/gamedata/phase2_config.gd")
const _SkillChoice = preload("res://scripts/gamedata/skill_choice.gd")

# ─── 进度档(9 格): **已彻底删除** (2026-09-26) ───
## 删掉的是 `bracket_for_battles(total) -> 0..8` 与它的反函数 `battles_for_bracket`。
## 上游 D5(`docs/plans/20260916-大轮赛制v2周赛制.md:349`) + 用户 2026-09-26
## 「别再按9档, 给我彻底删掉」。方案书: `docs/plans/20260926-删掉9档进度档.md`。
##
## ★它同时是**两个东西**, 两个都没了:
##   ① 匹配的尺子 —— 换成【总场次完全相同】(见 `find_opponent`)
##   ② 池子的分桶索引 —— 换成直接按【场次】分桶(见 `pool_add`, 键 `by_battles`)
## ★bot 强度原来靠 `2 + 档`, 换成量出来的 `_P2.bot_level_for_battles`。
##
## ⚠ **别把它加回来**, 哪怕只是当"池子的索引"。2026-09-25 就是这么留的:
##   留着索引 ⇒ 选靶那一侧顺手拿它当尺子 ⇒ 5 场次的人打 7 场次的。
##   同名但**无关**的 `scripts/gamedata/bracket.gd`(周日单败对阵图)不在此列, 一个字没动。

# ─── ghost 池 (内存 Dictionary, 结构 {by_battles:{"<场次>":[snapshot...]}}) ───
## 池子的分桶字典在哪个键下。★写成常量而不是到处写字面量: 2026-09-26 换键名时,
##   全仓有 18 处字面量 `"brackets"`, 其中闯关赛那一处**抄错了一层**整整三天没人发现
##   (`for gid in pool.keys()` ⇒ 周六每场都是机器人)。一个常量 = 换名字时编译器帮着数。
const POOL_KEY := "by_battles"

## 把 snapshot 加进它**自己那个场次**的桶 (新的在前, 封顶挤旧).
##
## ★★★2026-09-26 分桶键从「档 0..8」换成【场次】, 键名 `brackets` → `by_battles`。
##   为什么连键名一起换: 旧名字是**谎**——桶里装的从来是"进度档", 而匹配要的是场次。
##   名字不换, 下一个人(包括我自己)读到 `pool["brackets"]["3"]` 会以为 3 是档。
## ★分桶键必须取 `season_total_battles`, **不许**再存一个 `bracket`/`battles` 镜像字段:
##   同一个量存两份必然漂(这次就是漂的: 快照里的 `bracket` 与它的真场次是两回事)。
## ★桶 = 场次 ⇒ `pool_find_battles` 直接 `by_battles[str(N)]` 一步命中, 不用遍历。
static func pool_add(pool: Dictionary, snapshot: Dictionary) -> void:
	if not pool.has(POOL_KEY):
		pool[POOL_KEY] = {}
	var b := str(maxi(0, int(snapshot.get("season_total_battles", 0))))
	if not pool[POOL_KEY].has(b):
		pool[POOL_KEY][b] = []
	var bucket: Array = pool[POOL_KEY][b]
	## ★去重: 同 ghost_id 先删旧再入。
	## ★★A6(2026-09-19) 这条注释的【含义变了】, 原文是
	##   「同ghost_id(同一玩家阵容跨场重传)先删旧再入→池里一个逻辑对手=一条」——
	##   那是**按档匹配**时代的说法, 在新规则下**是错的**:
	##   `ghost_id` 现在带场次维 ⇒ 同一玩家不同场次是**不同的 id**, 会并存在桶里,
	##   这正是「场次比你低的人也能匹配到你」所必需的。
	##   去重现在只挡【同一玩家同一场次重传】(例: 同一场重打/重传), 不再是"一个玩家一条"。
	##   ⇒ 不改这条注释, 下一个人会照着它把"一个玩家只留一条"的去重加回来, 把 A6 拆掉。
	var new_id := str(snapshot.get("ghost_id", ""))
	if new_id != "":
		for i in range(bucket.size() - 1, -1, -1):
			if str((bucket[i] as Dictionary).get("ghost_id", "")) == new_id:
				bucket.remove_at(i)
	bucket.push_front(snapshot)
	while bucket.size() > BUCKET_CAP:
		bucket.pop_back()

## 内置陪练(策划种子池)的 `ghost_id` 前缀。
##
## ★★这条前缀是**产品自己就在用**的那个判据, 三处读它:
##   · `_ensure_seeded`  认出"池里已经有种子了 / 该清哪些旧种子"
##   · `leaderboard`     「陪练不上榜」(2026-09-26 加, 真机上看见 11 行里 10 行是陪练才发现)
##   · `_tally_exact`    「碰到的是真人还是陪练」(2026-09-28 加, 见 match_src_counts 头注)
##   写成常量 + 一个函数, 是因为前两处原来各写一遍字面量, 而第三处**压根没写** ——
##   同一个判据做了一半正是那次 100% 虚高的成因。
const SEED_ID_PREFIX := "seed_"


## 这份快照是内置陪练吗?
## ★判据**只能**是 ghost_id 前缀。已经错过两次, 两次都是选错维度(见 `leaderboard` 里那段):
##   · 筛「缺 `season_wins`」⇒ 把真人的老格式快照也筛掉了
##   · 筛 `is_bot` ⇒ 门禁全绿而真机一条没滤掉(种子池 396 条的 `is_bot` 实测全是 false)
static func is_sparring(g) -> bool:
	if not (g is Dictionary):
		return false
	return str((g as Dictionary).get("ghost_id", "")).begins_with(SEED_ID_PREFIX)


## 这份快照的**分路是坏的**吗 —— 「不许当对手」的判据。
##
## ★★★2026-09-29 加。由来: `build_ghost_snapshot()` 三个月来把 `lane_assign` 写成空
##   (根因见那边的头注), 而**修好上传之后, 池子里那些坏快照仍然躺在里面** ——
##   它们在 `remote_pool.snapshot_valid()` 眼里**完全合法**: 那道入池校验查
##   schema / ghost_id / 场次 / leaders / pet_levels / equipped, **没有一条查分路**。
##   ⇒ 只修生产侧, 玩家下一局照样从池子里捞出坏的、照样打「6 个小将」。
##
## ★★★判据**只认一种形状**: `lane_assign` **在**, 而里面一个统领都没有。
##   拿真数据分了三类才这么定的(2026-09-29 实测):
##     A 有 `lane_assign` 且有统领 —— 真池 396 / 种子文件 396      ⇒ 正常
##     B 有 `lane_assign` 但**是空的** —— 真池 **30**(全是真人上传)  ⇒ **就是今天这个 bug**
##     C **压根没有** `lane_assign` —— 真池 **0** / 种子文件 **0**
##   ★C 故意**不判为坏**, 两个理由:
##     ① 生产链一份都不产 C(上面那两个 0 是分母); 只有门禁的手造 fixture 是 C
##        (`verify_matchmaking_phase._ghost` / `verify_exact_match` / `verify_self_match`
##         / `verify_pool_truth` 都只带身份与场次这一维)。
##     ② C 在消费侧**走不到**出 bug 的那条路: `_dual_foe_lane()` 的
##        `la.get(lane) is Array` 对 `{}` 就是 false ⇒ 它整条掉到 bot 兜底,
##        **不会**拼出 6 个小将。⇒ C 是另一件(更老、更轻)的事, 不在这条账里。
##        真要求「快照必须声明分路」, 那条规矩属于 `snapshot_valid()`(入池校验), 不属于这里。
##
## ★**不给任何来源开例外**(bot / 陪练 / 远端都过同一条): 它们本来就自己算分路、天然带统领,
##   给来源开例外就等于让"要不要检查"跟着来源走 —— 那正是 `is_sparring` 判据
##   选错维度(`is_bot`)那次的形状。
## ★装备为什么**不在**这条判据里: 0 件装备是**合法状态**(人生第一把就是 0 件,
##   `make_bot(0)` 的预算也是 0) ⇒ 拿"装备空"当非法会把新手的快照全打成 bot。
##   装备那一半的修法只有一条: 生产侧别再读那个空字段(已修)。
## ★★以下这段 2026-09-29 从 `RealtimeBattle3DScene` 的调用处搬来 ——
##   注释该跟它解释的那个函数住, 而不是堆在调用方(上帝文件行数也是预算)。
## ★★★2026-09-29 这道闸原来判的是「**这一路**的统领和小将是不是都空」——
##   而 `build_ghost_snapshot` 三个月来产的每一份真人快照 `lane_assign` **整个都是空的**
##   (根因见 `backend.gd:build_ghost_snapshot` 头注)。空数组也是 `Array`,
##   `minions` 那一路又非空 ⇒ **照样进来**, `specs` 里 0 个统领,
##   下面 `_foe_normalize_lane` 按「3 - 统领数」把这一路补到 **3 个小将**
##   ⇒ 玩家看到的就是「对手 6 个小将、一个统领都没有」。
## ⇒ 判据换成**整份快照排不排得出一支队**, 走匹配那一侧的**同一个函数**
##   `Backend.ghost_lanes_broken()` —— 分路坏掉就整条落到下面的 bot 兜底。
## ★为什么**不按路**判: 3 统领可以全排在一路 ⇒ 另一路 0 统领 + 3 小将是**合法阵型**
##   (用户 2026-07-18「3统领→0小将 / 空统领→3小将 皆合规」), 那一路该由
##   **这份快照**服务, 而不是掉到下面写死的 bot 池 —— 原来就会那样:
##   同一个对手上路是 bot 的龟、下路是鬼影的小将, 拼出来的对手根本不存在。
## ⚠ 这里是**第二道**。第一道在 `Backend.pool_find_battles`(坏快照压根选不上),
##   留两道是因为 `dual_ghost` 还能从别处被写(调试台/教程/手工录入)。
static func ghost_lanes_broken(g) -> bool:
	if not (g is Dictionary):
		return false
	var la = (g as Dictionary).get("lane_assign", null)
	if not (la is Dictionary):
		return false                  # 形状 C: 没表态 ⇒ 不是这条账管的事(见头注)
	for lk in ["top", "bottom"]:
		var arr = (la as Dictionary).get(lk, null)
		if arr is Array:
			for pid in (arr as Array):
				if str(pid) != "":
					return false      # 形状 A: 至少一路有统领
	return true                       # 形状 B: 表了态, 而一个统领都没有


## 快照的【来源】—— 判"是不是我自己那份"只能靠它, 不能靠名字。见 _is_self_ghost 的长注释。
const ORIGIN_KEY := "origin"
const ORIGIN_LOCAL := "local"      # 本机打完一局自己传的
const ORIGIN_REMOTE := "remote"    # 从服务器拉回来的别人的(RemotePool.ingest_remote 盖章)

## 玩家自己上传的快照? 匹配一律跳过, 防撞自己阵容。
##
## ★★2026-08-26 改判据: 从【按 profile 名】改成【按来源】。
##   原来这么写(用户 2026-07-18「按名一网打尽」)在**单机本地池**里是对的 ——
##   池里名叫"玩家阵容"的条目确实全都是我自己。
##   但 `build_ghost_snapshot` 把 `profile.name` **写死**成 "玩家阵容"
##   (RealtimeBattle3DScene.gd:7814, 不是玩家输入) ⇒ 一旦接上服务器,
##   **别人传上来的快照名字也全是"玩家阵容"** ⇒ 我拉回来之后一条都匹配不到,
##   而且是**静默的**: 池子看着满的, 打的却永远是 bot。
##   这正是方案书 V2「A 手机打完 → B 手机能匹配到 A」的需求原话会失败的地方,
##   写 `verify_remote_pool.gd` 时才发现 —— 服务器还没开就先踩到了。
##   ⇒ 判据换成"这份是不是**本机产的**", 与名字脱钩。
## ★老池子向后兼容: 2026-08-26 之前存的条目没有 origin 字段, 而它们**确实全是本机产的**
##   (那时没有任何远端来源) ⇒ 无 origin + 名为"玩家阵容" 仍判自己。内置策划队两条都不满足, 照旧可匹配。
static func _is_self_ghost(g) -> bool:
	## ★SELF_GHOST=1: 允许匹配到自己录的阵容(2026-08-15 用户要手打录入多套, 得能自测)。
	##   默认仍然跳过 —— 单机下撞上自己那套是明显的穿帮。这是个**开发/自测开关**, 不是玩法。
	if OS.has_environment("SELF_GHOST"):
		return false
	if not (g is Dictionary):
		return false
	var d: Dictionary = g
	## ★★第一判据: ghost_id 是不是【本机这个赛季】产的。
	##   这条必须排在 origin 前面 —— 因为自己那份从服务器绕一圈回来时 origin 会被盖成
	##   `remote`(服务端存的是上传原样, 不带 origin), 而 `pool_add` 按 ghost_id 去重
	##   会把本地那份 `local` 顶掉 ⇒ **只看 origin 就会打到自己**(2026-08-27 探针实测)。
	##   id 是确定性的、绕多少圈都不变, 所以它才是可靠的那一维。
	var gid := str(d.get("ghost_id", ""))
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gid != "" and gs != null:
		var pre := self_season_prefix(int(gs.get("season_id")))
		if pre != "g_" and gid.begins_with(pre):
			return true
	## 第二判据: 本机刚上传、还没绕过服务器的那份。
	if d.has(ORIGIN_KEY):
		return str(d[ORIGIN_KEY]) == ORIGIN_LOCAL
	## 第三判据(老池子兼容): 2026-08-26 前存的没有 origin 字段, 而它们确实全是本机产的。
	return str((d.get("profile", {}) as Dictionary).get("name", "")) == "玩家阵容"

## 从池里抽一个【总场次完全相同】的对手 (排除 exclude_ids). 没有 → null (调用方兜底 bot).
##
## ★★★2026-09-26 这是选靶的**唯一**原语。它替掉了三个:
##   · `pool_find(pool, bracket, …, exact_battles)` —— 入参是【档】, 场次只是个可选过滤
##   · `pool_find_near(pool, lo, hi, …)`            —— 区间 = ±N 窗口, D5 不允许
##   · `pool_find_window(pool, lo, hi, …)`          —— 同上, 而且是【档】区间
##   三个并存的后果就是 2026-09-25 那次: 尺子有三把, 谁都能挑一把顺手的。
##
## ★判据量的是**快照自己报的 `season_total_battles`**, 不是桶的键名。
##   桶的键只用来一步定位(`pool_add` 保证两者一致), 但手造的池子/远端并入的脏数据
##   可能把一条 7 场次的快照塞进 "5" 桶 ⇒ 那时必须以快照自己的账为准。
##   (memory fb-gate-must-measure-requirement-not-my-hook: 量产品自己的账, 不量我的钩子。)
##
## ★★「取最新那份」不需要时间戳字段: `pool_add` 用 `bucket.push_front(snapshot)`,
##   **桶本身就是上传倒序** ⇒ 桶序里第一个命中的就是最新那份(D10: 新鲜度是排序不是过滤)。
##   ⇒ 所以这里**不随机**, 直接取第一个。`_rng` 留在签名里是给"同场次多人时要不要打散"
##   这条未决点用的; 现在按 D10 取最新, 一个字都不随机。
static func pool_find_battles(pool: Dictionary, battles: int, exclude_ids: Array,
		rng: RandomNumberGenerator):
	if battles < 0:
		return null
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	var b := str(battles)
	if not buckets.has(b):
		return null
	## ★★2026-10-06 改: 从「同场次里最新的 POOL_PICK_TOP 份」随机抽一份, 不再固定取第一份。
	##   60 人实操第 1 批(台账 A1)实测: 116 局里同一场次的所有人打的都是同一份快照
	##   (第 2~14 场 100% 是同一个玩家), 一份快照决定整批输赢, 模拟号之间一次都没碰上。
	##   用户 2026-10-06 同意(「你可以开始了」, 对「从最新的 5 份里随机抽一份」那条提议)。
	##   ★仍是 D5「总场次完全相同」, 仍按上传倒序取前 N 份 = 新鲜度照样优先(D10 的本意), 只是不再一人独占。
	## ★★★2026-10-08 再改: 从【全部】同场次快照里等概率抽, 不再只抽最新 5 份, 也不加「最近打过就排除」。
	##   用户实打到后面「只匹配到固定 3，4 个对手」—— 生产库每个场次有 23~71 个不同的人,
	##   但每格最新 5 份几乎都是同一批最近在玩的号(气场觉醒龟王 / 熔岩之心龟王 / 石头教头…)。
	##   用户原话:「抽签范围扩大到全部同场次呢，不要排除快照吧」。
	##   ⇒ D10 的「新鲜度优先」在选靶这一步不再生效(拉取仍按上传倒序, 只决定拉到哪些)。
	var cands: Array = []
	for g in buckets[b]:
		if not (g is Dictionary):
			continue
		if _is_self_ghost(g):
			continue
		## ★★★分路坏掉的快照**不是对手**(2026-09-29, 判据与三类形状的分母见
		##   `ghost_lanes_broken` 的头注)。这不是放宽/收紧匹配尺子 ——
		##   D5 的「总场次完全相同」就在下面那一行, 一个字没动; 这是**合法性**筛,
		##   与同循环里的 `_is_self_ghost` / `exclude_ids` 同一档。
		##   筛光了本函数返回 null ⇒ 调用方落到 bot(D5 认可的唯一回落)。
		## ★放在循环里 = 坏快照压在好快照上面时, **自动接着往下找**,
		##   而不是"抽到一份坏的就整场掉机器人"(那会把真人对手一起扔掉)。
		if ghost_lanes_broken(g):
			continue
		if int((g as Dictionary).get("season_total_battles", -1)) != battles:
			continue                  # ★以快照自己的账为准, 不信桶的键名
		if exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
			continue
		cands.append(g)
	if cands.is_empty():
		return null
	if rng == null or cands.size() == 1:
		return cands[0]
	return cands[rng.randi_range(0, cands.size() - 1)]


# ─── bot 生成 (池空/冷启动兜底 = 永久安全网, 设计§十三) ───
## 按【总场次】配资源(装备预算)随机一支队. rng 决定随机 → 确定可测. is_bot=true.
##
## ★★★2026-09-26 入参从**档**换成**场次**, 两处跟着变:
##   ① `season_total_battles` 如实报入参 —— 原来报的是 `battles_for_bracket(档)` =
##      **那一格的上界**, 于是 5 场次的玩家会看到一个自称"7 场次"的对手。
##      匹配现在要求场次完全相同 ⇒ 这个字段**从标签变成了判据**, 报谎就等于跨场次匹配。
##   ② 强度从 `2 + 档` 换成 `_P2.bot_level_for_battles(场次)`(量出来的, 见那边头注)。
##      旧算法在**场次 0** 那格是错的: 给 bot 2 件装备, 而真人人生第一把是 0 件。
##
## ★bot 等级**唯一**的去处是装备预算。快照里的 `pet_levels` 虽然也写它, 但
##   战斗侧读的是 `leaders / equipped / lane_assign / minions / loadouts` ——
##   **没有一处读 ghost 的 `pet_levels`**(2026-09-26 grep 全仓确认, 只有
##   `remote_pool.snapshot_valid` 检查它存在)。所以"bot 多强"= "bot 有几件装备"。
## ★★★2026-10-04 用户「不能让玩家知道是机器人，以及对手的场次一定要相同」——
##   卡片(v0.19.521)之外, **快照本身**也不许露馅: 对手快照会原样进录像(`var_to_bytes`,
##   **类型也保留**)和 `matches.right_snapshot`, 任何登录用户都读得到。
##   量出来的差异(门禁 `verify_bot_snapshot_shape` 对着 `build_ghost_snapshot` 递归逐层比):
##     · 缺键: trainer_skill / season_wins / hearts / season_sweeps /
##       chest_treasures_won / chest_treasure_value / origin(真人对手经 `ingest_remote` 盖章)
##       / 周六的 gl_w / gl_l / gl_ts
##     · 类型: 真人对手是**从 JSON 解出来的**(服务端拉回 / `load_pool` 读盘) ⇒ 数字全是 float;
##       机器人是现造的 int ⇒ 录像里一眼分得出。⇒ 末尾过一遍同样的 JSON 往返。
##     · 值域: `pet_levels` 真人恒为 1(`get_pet_level` 默认, 只有调试面板改), 机器人写的是赛季等级;
##       `profile.id` 真人 = 自己的 ghost_id(`g_<12hex>_<赛季>_<三龟>_b<场次>`), 机器人是 `#123456`;
##       `season_eggs_killed` 真人随胜场涨, 机器人恒 0。
##   ⚠ `is_bot` / `ghost_id` **留着**(门禁与匹配记账要分得清), 它们只在本机:
##     出站的两条路(录像 / right_snapshot)都过 `ReplayUploader.GHOST_STRIP` 摘掉。
## ★`gw / gl` = 周六战绩标签(-1 = 积分赛)。周六的真人快照带 gl_w/gl_l/gl_ts, 机器人也得带。
static func make_bot(battles: int, rng: RandomNumberGenerator, gw: int = -1, gl: int = -1) -> Dictionary:
	var bot_lv := _P2.bot_level_for_battles(battles)
	# ★装备容量统一规则(2026-07-27): 与玩家同一套 —— 全队合计 team_equip_cap(等级), 单只 ≤ UNIT_EQUIP_CAP。
	#   原来这里走 equip_slots_for_battles(每只固定N件) = 敌我两把尺子, 已废。
	var budget := _P2.team_equip_cap(bot_lv)
	# 随机 3 龟
	var all_ids: Array = []
	for p in DataRegistry.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	_shuffle(all_ids, rng)
	var leaders: Array = all_ids.slice(0, 3) if all_ids.size() >= 3 else all_ids
	# 分路: 前2上 / 后1下 (= auto_split 2/1)
	var lane_assign := {"top": [], "bottom": []}
	for i in range(leaders.size()):
		(lane_assign["bottom"] if i >= 2 else lane_assign["top"]).append(leaders[i])
	# 装备: 每龟随机 slots 件 shopAvailable 装备
	var shop_ids: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop_ids.append(str((e as Dictionary)["id"]))
	var equipped := {}
	var levels := {}
	# 先给统领分, 每只最多 UNIT_EQUIP_CAP; 分完剩下的留给小将(下面)。总数受 budget 硬约束。
	for pid in leaders:
		## ★写 1 不写 bot_lv: 真人快照这里是 `GameState.get_pet_level()` —— 默认 1、只有调试面板改,
		##   真机池 30/30 条全是 1。写赛季等级就是一个真人产不出来的值。战斗侧不读它(见上面头注)。
		levels[pid] = 1
		var eqs: Array = []
		while eqs.size() < _P2.UNIT_EQUIP_CAP and budget > 0 and shop_ids.size() > 0:
			eqs.append({"id": shop_ids[rng.randi() % shop_ids.size()], "star": 1})
			budget -= 1
		if eqs.size() > 0:
			equipped[pid] = eqs
	# 小将补位到每路3单位 + 随机装备(用户2026-07-18「快照里对面小将没有装备」根因: make_bot原来根本没minions字段→bot小将全裸; 镜像build_ghost_snapshot补上)
	var minions := {"top": [], "bottom": []}
	for lk in ["top", "bottom"]:
		var lead_cnt: int = (lane_assign[lk] as Array).size()
		var want: int = clampi(3 - lead_cnt, 0, 3)
		for mi in range(want):
			var meqs: Array = []
			while meqs.size() < _P2.UNIT_EQUIP_CAP and budget > 0 and shop_ids.size() > 0:
				meqs.append({"id": shop_ids[rng.randi() % shop_ids.size()], "star": 1})
				budget -= 1
			var m := {"role": "front" if mi == 0 else "back", "elite": (lead_cnt == 0 and mi == 0)}
			if meqs.size() > 0:
				m["equips"] = meqs
			(minions[lk] as Array).append(m)
	var ghost_id := "bot_%d_%d" % [battles, rng.randi() % 1000000]
	## ★★用户 2026-10-04「不能让玩家知道是机器人」: 原来全体机器人同名「海域守卫」、同号(hash("BOT") 恒为 #451562),
	##   打两场就认得出。⇒ 名字用**真人默认名的同一个生成器**(2026-10-07 起是 kevin_99 / 不吃香菜 这类), 不用「龟主-xxxxx」兜底名
	##   (用户 2026-10-04:「龟主-32c6c这是真人会用的名字？」)。
	var nick: String = _P2.nickname_suggest_at(rng.randi(), rng.randi())
	## ★`profile.id` 与真人同形: 真人四个上传点都传 `{"id": gid}`, 即 `player_ghost_id()` 拼的那串。
	##   卡片上的号读 `profile.tag`(真人 = 账号算的, 机器人 = `fake_person_tag(ghost_id)`, 同一个算法同一种长相;
	##   门禁 verify_bot_card_honest / verify_player_tag)。
	var fake_uid := "%06x%06x" % [rng.randi() % 0x1000000, rng.randi() % 0x1000000]
	var sorted_ldr: Array = leaders.duplicate()
	sorted_ldr.sort()
	var sid: int = int(GameState.season_id) if GameState != null else 1
	var pid_str := "g_%s_%d_%s" % [fake_uid, sid, "-".join(PackedStringArray(sorted_ldr))]
	pid_str += ("_g%d-%d" % [gw, maxi(0, gl)]) if gw >= 0 else ("_b%d" % battles)
	var loadouts: Dictionary = _SkillChoice.pick_loadouts(leaders,
		func(pid: String) -> Dictionary: return DataRegistry.pet_by_id.get(pid, {}), rng)
	var rec := _bot_season_record(battles, rng, gw, gl)
	var snap := {
		"schema_ver": SCHEMA_VER,
		"ghost_id": ghost_id,
		"is_bot": true,
		"profile": {"name": nick, "avatar": str(leaders[0]) if leaders.size() > 0 else "basic", "id": pid_str,
			"tag": fake_person_tag(ghost_id)},
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		## ★★2026-09-25 用户「每次机器人选的龟都只选了默认技能」「得修」。
		##   这里原本写死 `{}` ⇒ 消费侧(`RealtimeBattle3DScene.gd:5184` `var idx := 1`)
		##   永远走默认签名技, 而 28 只龟全部有 2~3 个已实装替代技 ⇒ 对手身上只体现
		##   三分之一的技能多样性。判据不在这里手写 —— 见 `SkillChoice` 的头注:
		##   同一个形状原本有三个生产者, 09-17 那次只补了"玩家上传"那一个。
		"loadouts": loadouts,
		"equipped": equipped,
		"pet_levels": levels,
		## 敌方大师读它(`battle_spawn.gd`)。从玩家**能选的那张表**里抽, 真人谁都在这七个里。
		"trainer_skill": _bot_trainer_skill(rng),
		"season_total_battles": battles,
		"season_eggs_killed": int(rec["wins"]),
		"season_wins": int(rec["wins"]),
		"hearts": int(rec["hearts"]),
		"season_sweeps": int(rec["sweeps"]),
		## 宝箱进度: 空/0 = 「没养宝箱龟」的真人的值, 也是这两个键缺失时战斗侧的回落值
		##   (`battle_spawn` 宝箱分支) ⇒ 补键不改变任何一场机器人战斗。
		"chest_treasures_won": [],
		"chest_treasure_value": 0.0,
		## 真人对手都是从服务端拉回来的, `RemotePool.ingest_remote` 必盖这个章。
		ORIGIN_KEY: ORIGIN_REMOTE,
	}
	if gw >= 0:
		## 与 `upload_gauntlet_ghost` 同三键。时间戳落在 30 分钟新鲜窗里(`gauntlet_pool_find` 只挑新鲜的)。
		snap["gl_w"] = gw
		snap["gl_l"] = maxi(0, gl)
		snap["gl_ts"] = int(_P2.now_utc()) - rng.randi_range(60, 25 * 60)
	## ★最后一步: 过一遍真人对手走过的同一个 JSON 往返(服务端拉回 `snapshots_from_body` / `load_pool` 读盘)。
	##   不做的话数字是 int 而真人是 float, `var_to_bytes` 的录像里类型是保留的。
	return JSON.parse_string(JSON.stringify(snap))


## 机器人的赛季战绩: 「打了 battles 场」的真人会有的胜负/命/横扫。
## ★约束都来自产品自己的规则: 积分赛每输一场掉一命(`lose_heart`), 0 命不能再打积分赛;
##   周六的人一定已晋级(`PROMOTE_WINS` 胜); 周六场次不掉命、不记横扫(`gauntlet_settle`)。
##   胜一场 `season_wins` 与 `season_eggs_killed` 同时 +1(各结算路径都成对加)。
static func _bot_season_record(battles: int, rng: RandomNumberGenerator, gw: int, gl: int) -> Dictionary:
	var g_w := maxi(0, gw)
	var g_l := maxi(0, gl)
	var ladder_n := maxi(0, battles - g_w - g_l)
	var need_w := mini(int(_P2.PROMOTE_WINS), ladder_n) if gw >= 0 else 0
	var w := 0
	var l := 0
	var sweeps := 0
	for i in range(ladder_n):
		var left_after := ladder_n - i - 1
		## 必须赢: 再输就凑不够晋级胜场 / 再输就 0 命而后面还有场要打(0 命不能再打积分赛)。
		var must_win: bool = (w + left_after + 1 <= need_w) \
			or (l >= int(_P2.HEARTS_MAX) - 1 and (left_after > 0 or gw >= 0))
		if must_win or rng.randf() < 0.5:
			w += 1
			if rng.randf() < 0.5:
				sweeps += 1
		else:
			l += 1
	return {"wins": w + g_w, "hearts": int(_P2.HEARTS_MAX) - l, "sweeps": sweeps}


## 机器人大师装配的技能 —— 从训龟大师配置界面的 `SKILLS`(玩家的全部选项)里抽。
static func _bot_trainer_skill(rng: RandomNumberGenerator) -> String:
	var TC = load("res://scripts/scenes/TrainerConfigScene.gd")
	var ids: Array = []
	if TC != null:
		for s in TC.SKILLS:
			ids.append(str((s as Dictionary).get("id", "")))
	if ids.is_empty():
		return "hook"
	return str(ids[rng.randi() % ids.size()])

## Fisher-Yates 洗牌 (rng 确定).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]; arr[i] = arr[j]; arr[j] = t

# ─── 排行榜 (MVP: 信任本地 season_eggs_killed, 不复算; 防作弊=上线后端的事, 设计§十五#3) ───
## 池里所有 ghost 按击杀蛋数降序 + 插入自己; 返回前 limit 行 [{name,eggs,is_self}].
## ★★A8(2026-09-19): 排序键从【只比碎蛋数】换成**字典序「胜场 → 余命 → 横扫」**。
##   · 胜场 = 打赢多少场(主指标)
##   · 余命 = 还剩几颗心(同胜场时, 命多的排前面 —— 赢得更干净)
##   · 横扫 = 2-0 拿下的场数(再同, 比谁赢得更利落)
## ★旧快照没有这三个字段 ⇒ 一律 `get(..., 0)` 兜底, **不作废旧池**(用户拍板不重开档)。
## ★`self_*` 参数从"只传蛋数"扩成三个键。调用点 `LeaderboardScene.gd:58` 同步。
## 「这份快照是**谁**产的」—— `ghost_id` 里那一维【人】。找不到返回 ""。
##
## ★★★判据不是新发明的: `player_ghost_id()` 拼的就是
##     `self_prefix(赛季)` + `<赛季>` + `_` + `"-".join(排序后的三龟)` [+ `_b<场次>`]
##   而 `self_prefix()` = `g_<install_uid>_`。⇒ 去掉「三龟」以及它后面的一切,
##   剩下的 `g_<uid>_<赛季>_` **正好就是 `self_season_prefix(赛季)`** ——
##   也就是 `_is_self_ghost()` 第一判据用的那同一个串(它 `begins_with` 的就是它)。
##   ⇒ 「谁」这一维在本文件里**只有一个定义**, 这里是把它**读出来**而不是另立一套。
##   门禁把这条等式钉住了(`verify_ghost_upload` ⑥: 自己那份快照的 owner tag
##   必须与 `self_season_prefix(赛季)` 逐字相同)。
##
## ★换龟也算同一个人: 三龟那一段被整段切掉 ⇒ 同赛季换过阵容仍是同一维
##   (这正是 `_is_self_ghost` 头注里「自己同赛季换过龟之后的旧阵容」要挡住的那件事)。
##
## ★★★2026-09-30 换成**只读 `ghost_id` 自己**(`owner_tag_of_id`), 原来那版读的是
##   「快照的 `leaders` 排序后拼出来的那一段, 再在 id 里找它」。
##   换的理由是**真机池量出来的**(探针跑 `user://ghost_pool.json`, 426 条里 30 条真人):
##     旧解析成功 **13/30**, 另外 **17 条静默返回 ""** ⇒ 掉到 `person_key` 的
##     第三判据(昵称) —— 而它的头注自己写着「会撞 / 改名会裂 / 排第三不排第一」。
##   17 条失败的形状**一模一样**: `ghost_id` 里写的三龟与快照 `leaders` 字段**不是同一套**
##     实测: `gid=g_c0adac635229_3_diamond-ghost-two_head` 而 `leaders=["angel","ice","ninja"]`
##   —— 因为这两个量**不同源**: `ghost_id` 由调用点用 `GameState.season_leaders` 拼
##   (`RealtimeBattle3DScene.gd:7647`), 而 `leaders` 由 `build_ghost_snapshot` 从
##   `get_dual_lineup()` 的**分路**里取(见那段「统领名单与分路同源」的注释)。
##   两者平时一致, 不一致时旧解析就**整条认不出人**。
##   ⇒ 身份这一维不该挂在"另一个字段恰好对得上"这个前提上。
##   新解析在旧解析成功的 13 条上结果**逐字相同**(探针: 不一致 0 条), 失败的 17 条全部救回
##   ⇒ 30/30。纯增益, 不改任何已经对的答案。
## ★旧解析仍留作**兜底**: 万一有不按 `g_<uid>_<赛季>_` 拼的历史 id, 覆盖率只会 ≥ 从前。
static func ghost_owner_tag(g) -> String:
	if not (g is Dictionary):
		return ""
	var d: Dictionary = g
	var gid := str(d.get("ghost_id", ""))
	if gid == "":
		return ""
	var byid := owner_tag_of_id(gid)
	if byid != "":
		return byid
	var ldr = d.get("leaders", null)
	if not (ldr is Array) or (ldr as Array).is_empty():
		return ""
	var arr: Array = []
	for x in (ldr as Array):
		arr.append(str(x))
	arr.sort()
	var at := gid.find("_" + "-".join(PackedStringArray(arr)))
	return gid.substr(0, at + 1) if at > 0 else ""


## `install_uid` 的长度 —— `GameState.get_install_uid()` 是 `generate_random_bytes(6).hex_encode()`。
## ★它是下面那条解析**唯一**用到的形状假设(拿它把 `g_<uid>_<赛季>_` 与 `g_<赛季>_` 分开),
##   所以门禁里有一条断言直接量 `get_install_uid().length()` —— 改了长度当场红,
##   而不是静默把所有人的身份解析成另一个串。
const UID_HEX_LEN := 12


## `player_ghost_id()` 的**反函数**: 从 id 里切出 `g_<uid>_<赛季>_` 这一段。
##
## 拼法(`player_ghost_id` + `self_prefix`)是:
##   `"g_"` [+ `<uid>` + `"_"`] + `<赛季>` + `"_"` + `"-".join(排序后三龟)` [+ `"_b<场次>"`]
##                                                                        [+ `"_g<胜>-<负>"`]
## ⇒ 按 `_` 切开后, 头两/三段一定是 `g` / (uid) / 赛季, **三龟那一段及其后面一概不看**
##   —— 所以龟 id 自带下划线(`two_head`)也影响不到它(旧注释担心的"数位置一定会错"
##   指的是从**右往左**数; 从左往右只数到赛季那一段就停, 是安全的)。
##
## ★uid 空 / 非空两种拼法怎么分开(`self_prefix` 在拿不到 GameState 时给 `"g_"`):
##   uid 是 **12 位十六进制**, 而赛季是个小整数 ⇒ 第 2 段长度是 12 且全是十六进制字符
##   就是 uid, 否则它就是赛季。赛季要长到 12 位数才会撞, 那不可能。
## ★形状不对就返回 "" —— `bot_*` / `seed_*` / `coh_*` / 空串都落在这里(它们本来也不该有 owner)。
## ⚠ 已知缺口(与旧解析**同款**, 不是这次带进来的): uid 为空那一支拼出来的是 `g_<赛季>_`,
##   **不含「谁」** ⇒ 两个都拿不到 GameState 的玩家在同一赛季会合成一行。
##   真机池里这种 id 只有 1 条(`g_1_bamboo-basic-stone`), 旧解析对它给的也是 `g_1_`
##   ⇒ 覆盖率没退步, 但这个洞还在。要堵它得在**上传那一侧**保证 uid 非空, 不是在这里猜。
static func owner_tag_of_id(gid: String) -> String:
	if gid == "":
		return ""
	var parts: PackedStringArray = gid.split("_")
	if parts.size() < 3 or parts[0] != "g":
		return ""
	var si := -1                    # 赛季那一段的下标
	if parts[1].length() == UID_HEX_LEN and parts[1].is_valid_hex_number(false):
		si = 2
	elif parts[1].is_valid_int():
		si = 1
	if si < 0 or si >= parts.size() or not parts[si].is_valid_int():
		return ""
	## ★赛季后面必须**还有东西**(三龟那一段) —— 否则 `g_<uid>_3` 这种截断串也会被
	##   当成合法身份。旧解析的 `at > 0` 守的就是这件事, 这里不能丢掉。
	if si + 1 >= parts.size() or parts[si + 1] == "":
		return ""
	var out := "g_"
	if si == 2:
		out += parts[1] + "_"
	return out + parts[si] + "_"


## 「榜上这一行是**谁**」—— 排行榜去重的那一维(DEDUP_BY_PERSON)。
##
## ★★★2026-09-29 加。由来: `leaderboard()` 的去重**只筛了自己**(`_is_self_ghost`),
##   别人的历史快照一条都没合 —— 而 `ghost_id` 带**场次**这一维(A6),
##   `pool_add` 又只按精确 id 去重 ⇒ **同一个人每打一场就在榜上多一行**。
##   后果两条, 都是真机上看得见的:
##     · 面板只画 11 行 ⇒ 「前 11 名」里其实只有 6 个真人, 另外 5 行是同几个人的旧场次
##     · `LeaderboardScene.gd:200` 的「本周共 %d 人上榜」拿的是 `rows.size()`
##       ⇒ 它数的是**快照条数**, 不是人数
##   ★所以这一层去重之后, 那句「N 人上榜」**不用改屏**就变成真的了
##     (它传的 limit 是 `1 << 30` = 全量, `rows.size()` 就是去重后的人数)。
##
## ★★★四级判据, 强的在前。**每一级都是量出来才排上的**:
##
##   ① `ghost_owner_tag()` = `g_<uid>_<赛季>_` —— 真正的「谁」。
##      撞不了(uid 是 6 字节随机的 12 位十六进制), 改名不裂(不含名字), 换龟不裂(三龟被切掉)。
##
##   ② `profile.id`, **且它不等于 `ghost_id`**。这一条挡的是队列模拟那一族
##      (`_cohort._snapshot_of` 的 `profile.id` = `COH0-11` = 一个机器人一个号,
##       而它的 `ghost_id` 是 `coh_0_b3` 每场一个)。
##      ⚠ **`profile.id` 不能无条件当身份用**: 真人快照的 `profile.id` 就是
##        `ghost_id` **本身**(`upload_ghost` 的调用点传的是同一个 `gid`) ——
##        2026-09-29 拿真机池数过: 30 条真人快照 `profile.id` **22 个互不相同**,
##        与 `ghost_id` 的 22 个**一一对应** ⇒ 拿它当身份就是**一条都不合**,
##        而覆盖率是 100%(30/30 有这个字段) ⇒ **只看"带不带"会以为它可用**。
##        这正是 `is_sparring` 头注记的那个形状:「只量了带不带, 没量它的值」。
##
##   ③ `profile.tag`(玩家 ID, 账号算的) —— 只在上面两条都取不到时才用(缺 `leaders` 的畸形快照)。
##      ★原来这一级是【昵称】; 2026-10-04 起名字允许重复, 昵称**不再当任何键**(见下方函数体)。
##
##   ④ `ghost_id` —— 一条一行, 与改之前逐字相同(不会把不同的人误合)。
static func person_key(g) -> String:
	if not (g is Dictionary):
		return ""
	var d: Dictionary = g
	var owner := ghost_owner_tag(d)
	if owner != "":
		return "o:" + owner
	var gid := str(d.get("ghost_id", ""))
	var pr = d.get("profile", null)
	if pr is Dictionary:
		var pid := str((pr as Dictionary).get("id", "")).strip_edges()
		if pid != "" and pid != gid:
			return "a:" + pid
		## ★★2026-10-04 第三级从【昵称】换成【玩家 ID】(`profile.tag`, 账号算出来的)。
		##   名字现在明确**允许重复**(用户 2026-10-04 拍板「名字可以重, 靠 ID 分」) ⇒
		##   拿昵称当键 = 两个同名的人在榜上合成一行、其中一个人消失。
		##   ID 由账号单向算出(快照里不放 account_id 本身), 改名也不裂。
		var tg := str((pr as Dictionary).get("tag", ""))
		if _P2.tag_valid(tg):
			return "t:" + tg
	return "g:" + gid


static func leaderboard(pool: Dictionary, self_name: String, self_wins: int, self_hearts: int,
		self_sweeps: int, limit: int) -> Array:
	## ★`tag` = 玩家 ID。界面只在**真的重名**时才把它摆出来(`_P2.names_needing_tag`)。
	var rows: Array = [{"name": self_name, "wins": self_wins, "hearts": self_hearts,
		"sweeps": self_sweeps, "is_self": true, "tag": my_tag()}]
	## ★字典序: 前一键相等才看后一键。写成「先比胜场, 相等再比余命, 再相等才比横扫」。
	## ★★提成变量是为了**只有一份**: 排序用它, 下面「同一个人留哪一行」也用它。
	var cmp := func(a, c) -> bool:
		if int(a["wins"]) != int(c["wins"]):
			return int(a["wins"]) > int(c["wins"])
		if int(a["hearts"]) != int(c["hearts"]):
			return int(a["hearts"]) > int(c["hearts"])
		return int(a["sweeps"]) > int(c["sweeps"])
	var by_person: Dictionary = {}     ## person_key → 这个人目前最好的那一行
	var seen_order: Array = []         ## person_key 的首次出现序(让同分时的次序确定)
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	for b in buckets.keys():
		for g in buckets[b]:
			var gd := g as Dictionary
			## ★★★2026-09-26 两道筛, 都是拿真数据量出来要加的:
			##
			## ① **自己的历史快照不上榜**。`ghost_id` 带**场次**这一维(A6), 而
			##    `pool_add` 只按精确 id 去重 ⇒ 同一个玩家**每个场次各占一条**,
			##    而快照里的 `profile.name` 就是他自己的昵称
			##    ⇒ 一周打 N 场, 榜上就有 **N 行他自己的名字**, 而面板只画 11 行。
			##    跨周还会叠(`start_new_season` 一个字都不碰 ghost 池) ⇒ 周一打开榜,
			##    榜首是**上周的自己**, 而「◀ 你」被钉在末行显示 0 胜。
			##    ★同文件三处匹配路径都有 `_is_self_ghost`, 只有这里漏了。
			if _is_self_ghost(gd):
				continue
			## ② **陪练不上榜**。种子池(队列模拟造的 396 条)原来一律按 0/0/0 参与排序
			##    并且**占掉名次** ⇒ 10 个人测试会看到「#57 你」这种数字。
			##
			## ★★★判据是 `ghost_id` 的 **`seed_` 前缀** —— 这是**产品自己已经在用**的那条
			##   (`_ensure_seeded` 靠它认种子、升版时清旧种子), 不另立一套。
			##
			## ⚠ 我在这里连错两版, 都是**判据选错维度**:
			##   · 第一版筛「缺 `season_wins`」⇒ `verify_leaderboard_sort` ④ 当场红:
			##     那一段明确要求**真人的老格式快照**(缺字段)仍要上榜、当 0 排在后面。
			##   · 第二版改筛 `is_bot` ⇒ 门禁全绿, **而真机上一条都没滤掉** ——
			##     种子池 396 条的 `is_bot` 实测全是 **false**(它们是队列模拟跑出来的
			##     "真玩家"数据, 不是 `make_bot` 合成的)。
			##     ★我当时只量了「带不带这个字段」(396/396 带), **没量它的值**。
			##     而门禁 ⑦b 绿是因为我在那里**手动把 `is_bot` 置成 true** 造了个陪练
			##     ⇒ 判据在测我自己喂进去的东西, 不是真池子。
			##   ⇒ 是**真机上点开排行榜**看见 11 行里 10 行是陪练才发现的。
			## ★★2026-09-28 这一行原来是就地写的 `begins_with("seed_")`, 已收进
			##   `is_sparring()` —— 匹配记账那一侧要用**同一条**判据(见它的头注)。
			if is_sparring(gd):
				continue
			## ★★★③ **同一个人只占一行**(2026-09-29, 判据见 `person_key` 头注)。
			##   留哪一行 = 这个人**最好**的那一行, 而「最好」用的是**下面排序那同一个比较器**
			##   `cmp`(所以下面才把它先提出来成一个变量) —— 各写一份必然漂
			##   (memory `fb-hand-rolled-copies-drift`)。
			var row := {
				"name": str(gd.get("profile", {}).get("name", "?")),
				"wins": int(gd.get("season_wins", 0)),
				"hearts": int(gd.get("hearts", 0)),
				"sweeps": int(gd.get("season_sweeps", 0)),
				## 总场次(排行榜「总场次」列, 2026-10-06)。老快照没这个字段 ⇒ -1, 屏上画「—」不编 0。
				"battles": int(gd.get("season_total_battles", -1)),
				"is_self": false,
				"tag": profile_tag(gd.get("profile", {}) if gd.get("profile") is Dictionary else {})}
			var pk := person_key(gd)
			if by_person.has(pk):
				if cmp.call(row, by_person[pk]):
					by_person[pk] = row
			else:
				by_person[pk] = row
				seen_order.append(pk)      # 首次出现序 = 桶序(上传倒序) ⇒ 全平时次序稳定
	for pk2 in seen_order:
		rows.append(by_person[pk2])
	rows.sort_custom(cmp)
	return rows.slice(0, limit) if rows.size() > limit else rows


# ─── 「问没问到别人」—— 池子这一侧的事实 (2026-09-28) ───
##
## ★★★由来: 排行榜在只有自己一行时印的是
##   「（榜上暂时只有你 —— 打完一场, 对手就会上来）」。**离线时那是假话。**
##   `pool_add` 的全部调用点只有四条:
##     · `_ensure_seeded`        内置陪练 —— 被 `leaderboard` 的「陪练不上榜」筛掉
##     · `upload_ghost`          自己     —— 被 `_is_self_ghost` 筛掉
##     · `apply_pull_response` / `ingest_remote`   **纯网络**
##   ⇒ 断网时打一万场也不会有任何人上榜。那句话把**网络失败**归因到玩家的场次上。
##
## ★修法照本仓已经立过两次的规矩(2026-09-25 的 `too_few`、2026-09-27 的
##   `supabase.UNREACHABLE`): 「**问不到**」和「**问到了, 答案是没有**」是两句话。
##   而且「**还没问**」也要单列 —— `supabase.gd:37-49` 把 `ST_UNKNOWN` 从
##   `ST_UNREACHABLE` 里分出来的理由逐字适用: 一次都没发过请求就说"连不上",
##   是把一个没发生的网络故障说成发生了, 那只是换了个谎。
const REACH_OFF := "off"          ## 没配后端 ⇒ 这台机器上的榜就是本地的
const REACH_UNKNOWN := "unknown"  ## 配了, 但这个进程还没问过(刚开机就是它)
const REACH_FAIL := "fail"        ## 配了, 问过, 一次都没问到
const REACH_OK := "ok"            ## 这个进程真的问到过 ⇒ 「打完一场对手就会上来」才是真的

## 纯判据 —— 四个输入定一档, 可穷举。
## ★★做成纯函数是因为门禁**跑不到**另外三档: `run-tests.sh:359` 每个测试都带
##   `TURTLE_SUPABASE=" "` ⇒ `enabled()` 恒 false ⇒ 真实取数永远只落在 REACH_OFF。
##   把判据和取数分开, 四档才都有分母(而取数那一半另有一条端到端断言看着)。
static func reach_of(configured: bool, ok_n: int, try_n: int, known_down: bool) -> String:
	if not configured:
		return REACH_OFF
	## ★成功压过失败: 这个进程只要问到过一次, 管子就是通的(之后抖一下不改变"别人会上来")。
	if ok_n > 0:
		return REACH_OK
	if try_n > 0 or known_down:
		return REACH_FAIL
	return REACH_UNKNOWN


## 真事实版: 两层网络层各取一次, 落成上面四档之一。
## ★用 `load` 不用 `preload`: `remote_pool.gd` 反过来 preload 本文件, 循环 preload 编译失败
##   (与 `upload_ghost` 里那条同一个理由)。
static func pool_reach() -> String:
	var configured := false
	var ok_n := 0
	var try_n := 0
	var down := false
	var SB = load("res://scripts/net/supabase.gd")
	if SB != null:
		configured = configured or bool(SB.enabled())
		ok_n += int(SB.pull_ok_count())
		try_n += int(SB.pull_try_count())
		## ★`/service_status` 那条独立的健康检查也算一条"问不到"的证据 ——
		##   玩家可能压根还没打过一场(那时拉对手的计数是 0), 但主菜单已经问过服务状态了。
		down = down or (str(SB.service_state()) == str(SB.ST_UNREACHABLE))
	var RP = load("res://scripts/net/remote_pool.gd")
	if RP != null:
		configured = configured or bool(RP.enabled())
		ok_n += int(RP.ok_count)
		try_n += int(RP.ok_count) + int(RP.fail_count)
		down = down or bool(RP.looks_broken())   # 现成的原语: 配了地址但一次都没成功过
	return reach_of(configured, ok_n, try_n, down)

# ─── 文件 I/O (薄包装, user://ghost_pool.json) ───
## 【门禁注入点】非空时 `load_pool()` 直接返回它, 不读文件。
##
## ★为什么必须有它(2026-09-27): 门禁想量**真排行榜**(11 行别人), 而
##   `save_pool()` 在 `test_mode` 下**直接 return**(保护真存档) ⇒ 门禁灌进内存的
##   快照一个字节都落不了盘, 场景读文件读到空池 ⇒ 榜上只有自己一行
##   (`[LB] rows=1`), 量的是**占位屏**。本仓 Record 2026-08-21 正是这么假绿过一整晚。
##
## ★开在 `load_pool` 而不是逐个场景: 它有 7 个消费者(本文件 3 处 +
##   remote_pool / supabase / LeaderboardScene / MatchmakingScene),
##   逐个开缝就是抄 7 遍(memory `fb-hand-rolled-copies-drift`)。
## ★默认空 ⇒ **玩家路径一字不动**。与 `SettingsScene.acct_override` /
##   `clock_override_ts` 同一个模式。
## ⚠ 用完必须清空 —— 它是 static, 活过场景切换。
static var pool_override: Dictionary = {}


static func load_pool(path: String = POOL_PATH) -> Dictionary:
	if not pool_override.is_empty():
		return pool_override
	var pool: Dictionary = {POOL_KEY: {}}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text(); f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				pool = parsed
	_migrate_brackets_to_battles(pool)   # ★老存档是按【档】分桶的, 就地重分到【场次】
	if not pool.has(POOL_KEY):
		pool[POOL_KEY] = {}
	_drop_stale_schema(pool)   # ★老版本快照整批丢掉(用户 2026-08-14 拍板 A: 不做向后兼容)
	_ensure_seeded(pool)   # 冷启动/老档无种子 → 并入内置策划队(幂等, 已并过不重复); 下次 upload_ghost 落盘
	return pool


## 老存档迁移: `{"brackets": {"<档>": [...]}}` → `{"by_battles": {"<场次>": [...]}}`。
##
## ★★为什么做迁移而不是像 `_drop_stale_schema` 那样整批丢: 丢的理由一向是
##   「缺字段 ⇒ 兼容就等于编一个假对手」。这次**一个字段都不缺** ——
##   每条快照自己就带着 `season_total_battles`, 重分桶是**无损**的纯搬家。
##   丢掉的话会连带丢掉玩家从 Supabase 拉回来的真人快照(要重新攒)。
## ★幂等: 搬完删掉旧键 ⇒ 下次进来 `has("brackets")` 就是 false, 整个函数是 no-op。
## ★搬多少要**打印**(CLAUDE.md: 无声上限 = 假装覆盖全了)。
static func _migrate_brackets_to_battles(pool: Dictionary) -> int:
	if not pool.has("brackets"):
		return 0
	var old = pool["brackets"]
	pool.erase("brackets")
	if not (old is Dictionary):
		return 0
	if not pool.has(POOL_KEY):
		pool[POOL_KEY] = {}
	var moved := 0
	for b in (old as Dictionary).keys():
		var arr = (old as Dictionary)[b]
		if not (arr is Array):
			continue
		## ★倒着灌: `pool_add` 是 `push_front`, 顺着灌会把桶序(上传倒序)反过来,
		##   而"取第一个 = 最新那份"整条 D10 都靠那个顺序。
		var a: Array = arr as Array
		for i in range(a.size() - 1, -1, -1):
			if a[i] is Dictionary:
				pool_add(pool, a[i] as Dictionary)
				moved += 1
	if moved > 0:
		print("[Backend] 池子迁移: %d 条快照从【档】重分到【场次】桶(无损)" % moved)
	return moved


## 丢掉 schema_ver < SCHEMA_VER 的快照。
##
## ★为什么不做向后兼容(用户 2026-08-14 原话:「直接全部老快照全消除掉, A, 重新制作新快照」):
##   老快照缺 `chest_treasures_won` —— 兼容就意味着"缺字段时假装对手没开过箱",
##   那还是在编一个假的对手, 只是换了个假法。宁可池子空一阵。
## ★丢多少要【打印出来】, 不许静默(CLAUDE.md: 无声上限 = 假装覆盖全了)。
static func _drop_stale_schema(pool: Dictionary) -> int:
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	var dropped := 0
	for b in buckets.keys():
		var arr: Array = buckets[b]
		var keep: Array = []
		for g in arr:
			if g is Dictionary and int((g as Dictionary).get("schema_ver", 0)) >= SCHEMA_VER:
				keep.append(g)
			else:
				dropped += 1
		buckets[b] = keep
	if dropped > 0:
		print("[Backend] 丢弃 %d 条老版本快照(schema < %d) —— 池子会先空一阵, 遇到的都是 bot" % [dropped, SCHEMA_VER])
	return dropped

## 内置种子池 (res:// 只读, 导出包里也在). 解析失败=空.
static func _load_seed() -> Dictionary:
	if not FileAccess.file_exists(SEED_PATH):
		return {POOL_KEY: {}}
	var f := FileAccess.open(SEED_PATH, FileAccess.READ)
	if f == null:
		return {POOL_KEY: {}}
	var parsed = JSON.parse_string(f.get_as_text()); f.close()
	if parsed is Dictionary and (parsed as Dictionary).has(POOL_KEY):
		return parsed
	return {POOL_KEY: {}}

const SEED_VER := 16  # ★★2026-10-07 v16: 种子文件没动, 陪练入池时的名字换成新昵称生成器(真人用户名的长相)。
                      #   不升版老池里那 396 条还叫「石头统领」这类旧名, 而真人的默认名已经换了 ⇒ 一眼分得出谁是陪练。
                      # ★★2026-10-04 v15: 种子文件没动, 陪练入池时多盖一个 `profile.tag`(玩家 ID, 与真人同一套算法 ——
                      #   `fake_person_tag`)。不升版老池里那 396 条没有这个键, 与真人快照不同形。
                      # ★★2026-10-04 v14: **种子文件一个字节没动**, 升版只为一件事:
                      #   陪练入池时改成**真人对手的形状**(`seed_as_human`, 用户 2026-10-04
                      #   「不能让玩家知道是机器人」)。老存档池里那 396 条是旧形状
                      #   (带 `_strategy` / `season_level`、`profile.id` = `COHxx`、缺 hearts 等),
                      #   不升版它们永远留在池里 ⇒ 必须清掉重并。
                      # ★★2026-09-26 v13: **快照内容一条没变**(还是 v12 那 396 支),
                      #   升版只为一件事: 种子文件的**分桶键**从「档」换成「场次」
                      #   (`brackets` → `by_battles`, 见 `POOL_KEY` / 方案书
                      #   `docs/plans/20260926-删掉9档进度档.md`)。
                      #   老池里的 seed_ 是按档分的桶, 不升版就会与新键**并存两套**。
                      # ★★2026-09-25 v12: 800 只全量重跑(12744 条候选→396 支), 两件事一起改:
                      #   ① **按【场次】挑, 不再按【档】挑**。v11 的 184 支只落在 **9 个场次**上
                      #      (0/1/3/5/8/12/17/22/28, 每档正好一个点) —— 那是 `cohort_to_seed`
                      #      「每档挑 20 条」的产物。而匹配的尺子 2026-09-25 换成了【场次 ±1】
                      #      (用户:「不应该有这些东西啊粗格子…你 5 场次在『5-7』」) ⇒ 尺子一细,
                      #      池子立刻全是洞: 想找同场次的人, 十次里三次找不到, 落到「往下找」。
                      #      v12 覆盖 **36 个场次**, 0~24 每一格 12 支(自检: 空一格就拒写)。
                      #   ② **第一次带 `loadouts`(每只龟的 3选1 主动技)**。v11 是 0/184 条带,
                      #      原料 0/12718 条带 ⇒ 玩家打到的每个对手每只龟都走默认签名技
                      #      (消费侧 `var idx := 1`), 而 28 只龟全部有 2~3 个已实装替代技
                      #      ⇒ 只体现三分之一的技能花样。v12: 396/396 条带, 位次分布 394/408/386。
                      #   装备覆盖 95/95 件(含覆盖补选追加的 5 支)。
                      # 2026-09-03 v11: 800 只机器人 × 14 个流派全量重跑(12718 条候选→184 支)。
                      #   ★必须 +1 —— 否则老存档的 `_seed_ver >= SEED_VER` 判定成立, **新池永远并不进去**,
                      #   玩家匹配到的还是旧的四种蠢 AI(用户 2026-09-03「快照全部要重新跑因为你装了蠢ai」)。
                      #   旧 v10 的池由 xp≤1 的自杀参数跑出: 高费流达档8率 0%、4~5 费占比比随机瞎买还低 17 个点。
                      #   小场子(11 只)约 23 轮就把人淘汰光, 而爬到档8 要打 ~28 场 —— 只有大场子里
                      #   那几只一路赢的才活得到顶档。全池 184 支, 新装备遇到率 91%。
                      # 2026-08-15 v9: 只用【新原料】重生成 —— v8 误把 tools/autoplay/c1~c5
                      #   (2026-07-27 那几次跑的, 早于 060~094 那批装备)一起自动并入, 占满每档名额,
                      #   结果"装备覆盖 94/94"却只有 6% 的队真带新装备。c1~c5 已改名归档为 _c1~_c5。
                      #   v9 实测: 80% 的队身上有新装备(档1~7 为 70~100%)。
                      # 2026-08-15 v8: 20 批×11 只 + 覆盖补选 ⇒ 193 支(9档各≥20)。
                      #   与 v7 的实质差别: ①全部 schema_ver=2, 带 chest_treasures_won/value
                      #   ②装备覆盖 57 → **94/94 件**(v7 缺 060~084 那批新装备, 因为它生成于那批装备存在之前)
                      #   ③敌我宝箱阈值统一(删掉单场旧制 [80,130,240,360,590])
                      # 2026-08-12 v7: 32 只机器人真实队列重跑(30 轮打到只剩 1 队·510 条快照)——含新装备 060~076 与第四种买法【羁绊流】(149/510 条)。
## 沿革: v6(2026-07-27) = 队列模拟产出的真实玩家快照 180 支/9 档各 20; 装备是真背包历史
## (1~5 费混搭·便宜的星高贵的星低), 非按目标强度反推。升版 → 老档清旧 seed_ 并入新种子
## (玩家上传的真 ghost 保留)。
## 种子并入(版本化): 无seed_ 或 池版本<SEED_VER → 清旧seed_+并入新种子+落盘. 修真机bug"老池挡住新种子永不升级"(用户2026-07-15).
static func _ensure_seeded(pool: Dictionary) -> void:
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	var have_seed := false
	for b in buckets.keys():
		for g in buckets[b]:
			if is_sparring(g):
				have_seed = true
				break
		if have_seed: break
	var sid := _seed_season_id()
	if have_seed and int(pool.get("_seed_ver", 0)) >= SEED_VER:
		## ★换赛季了: 陪练的 `profile.id` 里那一段赛季号要跟着换(真人对手都是本周的)。
		##   **就地**重盖、桶序不动 —— 清掉重并会让 396 条陪练整批 `push_front` 压到
		##   真人快照前面, 而「桶序第一个 = 最新那份」是匹配取人的顺序(D10)。
		if int(pool.get(SEED_SEASON_KEY, -1)) != sid:
			for b in buckets.keys():
				var arr: Array = buckets[b]
				for i in range(arr.size()):
					if is_sparring(arr[i]):
						arr[i] = seed_as_human(arr[i] as Dictionary, sid)
			pool[SEED_SEASON_KEY] = sid
			save_pool(pool)
		return
	for b in buckets.keys():                       # 清旧版seed_(玩家真ghost保留)
		var keep: Array = []
		for g in buckets[b]:
			if not is_sparring(g):
				keep.append(g)
		buckets[b] = keep
	var seed := _load_seed()
	for b in seed.get(POOL_KEY, {}).keys():
		for g in seed[POOL_KEY][b]:
			if g is Dictionary:
				pool_add(pool, seed_as_human(g as Dictionary, sid))
	pool["_seed_ver"] = SEED_VER
	pool[SEED_SEASON_KEY] = sid
	save_pool(pool)                                 # 升级立即落盘(否则要等下次upload才存)


## 池子里的陪练是按哪个赛季盖的 `profile.id`(见 `seed_as_human`)。与 `_seed_ver` 同住池子顶层,
##   `int` 值 ⇒ 各处遍历池子时被 `is Dictionary` / `POOL_KEY` 跳过, 与 `_seed_ver` 同一档。
const SEED_SEASON_KEY := "_seed_season"


static func _seed_season_id() -> int:
	return int(GameState.season_id) if GameState != null else 1


## 内置陪练 → **真人对手的形状**。入池那一刻转(`_ensure_seeded`), 文件不动。
##
## ★★用户 2026-10-04「不能让玩家知道是机器人，以及对手的场次一定要相同」。
##   v0.19.529 把 `make_bot` 做成了与真人同形, 而种子池这几百支**也不是真人**(队列模拟跑出来的),
##   冷启动/断网时它们就是玩家遇到的全部对手, 原样进录像(`var_to_bytes`)与 `matches.right_snapshot`。
##   门禁 `verify_bot_snapshot_shape` 的陪练那一段量出来的差异(改之前, 396 支逐条比):
##     · 多键: `_strategy`(队列模拟的买法流派) / `season_level` —— 真人快照里没有
##     · 缺键: `season_wins` / `hearts` / `season_sweeps` / `origin`
##     · 值域: `profile.id` 是 `COH0-49` 这种内部号(真人是 `g_<uid>_<赛季>_<三龟>_b<场次>`);
##       名字 17 个不是玩家起得出来的(`nickname_valid` 不过); 同一个「人」每个场次换一个名字;
##       小将 `equips: []` 589 处、`equipped` 空数组 82 处(真人上传时**不写**空的);
##       `pet_levels` 有 2(真人恒 1); `season_eggs_killed` 恒 0。
## ★★战斗强度**一点不动**: 战斗场读的是 `leaders / lane_assign / minions / equipped / loadouts /
##   trainer_skill / chest_*`(全仓 grep `dual_ghost` 的读者), 这些原样搬; 只删了**空**装备数组
##   (`_dual_foe_lane` 对空数组与缺键走同一条: 敌方 `_dl_spec_equips` 都返回 `[]`)。
##   `pet_levels` 战斗侧没人读(见 `make_bot` 头注)。门禁拿**战斗场自己的** `_dual_foe_lane`
##   把 396 支原样/转换后各读一遍, 逐字相同。
## ★`_strategy` / `season_level` 只删在**池子里这一份**: 种子文件原样保留, 量 bot 强度曲线的
##   `tools/bot_level_fit_audit.py`、`verify_seed_battles_gear`、流派报表都读文件, 不读池子。
## ★`ghost_id` 保留 `seed_` 前缀: 那是 `is_sparring` 的唯一判据(陪练不上榜 / 匹配记账分真人陪练 /
##   升版清旧种子), 而它只在本机 —— 出站两条路都过 `ReplayUploader.GHOST_STRIP` 摘掉(与 `is_bot` 同)。
## ★同一个「人」(ghost_id 去掉 `_b<场次>`)各场次: uid / 名字相同, 胜场随场次不减 ——
##   全部由这个人的 id 做种子确定性生成, 换机器/重开都一样。
## ★幂等: 对已经转过的再转一次, 只会换赛季号(换赛季时 `_ensure_seeded` 就靠这个就地重盖)。
static func seed_as_human(g: Dictionary, season_id: int) -> Dictionary:
	var gid := str(g.get("ghost_id", ""))
	var battles := maxi(0, int(g.get("season_total_battles", 0)))
	var leaders: Array = []
	for x in (g.get("leaders", []) as Array):
		leaders.append(str(x))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_person_of(gid))
	var fake_uid := "%06x%06x" % [rng.randi() % 0x1000000, rng.randi() % 0x1000000]
	var nick: String = _P2.nickname_suggest_at(rng.randi(), rng.randi())
	var rec := _seed_record(battles, rng)
	var sorted_ldr: Array = leaders.duplicate()
	sorted_ldr.sort()
	var pid_str := "g_%s_%d_%s_b%d" % [fake_uid, season_id, "-".join(PackedStringArray(sorted_ldr)), battles]
	## 分路 / 小将: 与 `build_ghost_snapshot` 同序同键; 小将只在**有**装备时写 `equips`。
	var src_la: Dictionary = g.get("lane_assign", {}) if g.get("lane_assign") is Dictionary else {}
	var src_mn: Dictionary = g.get("minions", {}) if g.get("minions") is Dictionary else {}
	var lane_assign := {"top": [], "bottom": []}
	var minions := {"top": [], "bottom": []}
	for lk in ["top", "bottom"]:
		if src_la.get(lk) is Array:
			lane_assign[lk] = (src_la[lk] as Array).duplicate(true)
		if src_mn.get(lk) is Array:
			for m in (src_mn[lk] as Array):
				if not (m is Dictionary):
					continue
				var md: Dictionary = m
				var m2 := {"role": md.get("role", "front"), "elite": md.get("elite", false)}
				var meq = md.get("equips", null)
				if meq is Array and not (meq as Array).is_empty():
					m2["equips"] = (meq as Array).duplicate(true)
				(minions[lk] as Array).append(m2)
	## 统领装备 / 等级: 按统领序, 只收非空的(同 `build_ghost_snapshot`)。
	var src_eq: Dictionary = g.get("equipped", {}) if g.get("equipped") is Dictionary else {}
	var equipped := {}
	var levels := {}
	for pid in leaders:
		var eqs = src_eq.get(pid, null)
		if eqs is Array and not (eqs as Array).is_empty():
			equipped[pid] = (eqs as Array).duplicate(true)
		levels[pid] = 1               # 真人恒 1(`get_pet_level` 默认); 战斗侧不读
	var prof_src: Dictionary = g.get("profile", {}) if g.get("profile") is Dictionary else {}
	var avatar := str(prof_src.get("avatar", leaders[0] if not leaders.is_empty() else "basic"))
	var snap := {
		"schema_ver": SCHEMA_VER,
		"ghost_id": gid,
		"is_bot": false,
		"profile": {"name": nick, "avatar": avatar, "id": pid_str, "tag": fake_person_tag(seed_person_of(gid))},
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": (g.get("loadouts", {}) as Dictionary).duplicate(true) if g.get("loadouts") is Dictionary else {},
		"equipped": equipped,
		"pet_levels": levels,
		"trainer_skill": str(g.get("trainer_skill", "")),
		"season_total_battles": battles,
		"season_eggs_killed": int(rec["wins"]),
		"season_wins": int(rec["wins"]),
		"hearts": int(rec["hearts"]),
		"season_sweeps": int(rec["sweeps"]),
		"chest_treasures_won": (g.get("chest_treasures_won", []) as Array).duplicate(true) if g.get("chest_treasures_won") is Array else [],
		"chest_treasure_value": float(g.get("chest_treasure_value", 0.0)),
		ORIGIN_KEY: ORIGIN_REMOTE,
	}
	## 与真人对手同一个 JSON 往返(数字一律 float)。
	return JSON.parse_string(JSON.stringify(snap))


## 陪练的「这个人」= ghost_id 去掉末尾的 `_b<场次>`(同一只队列机器人在各场次的快照)。
static func seed_person_of(gid: String) -> String:
	var i := gid.rfind("_b")
	if i > 0 and gid.substr(i + 2).is_valid_int():
		return gid.substr(0, i)
	return gid


## 陪练的赛季战绩 —— 逐场走, 所以同一个人(同一个种子)场次越多胜场只增不减。
## ★规则同 `_bot_season_record`: 输一场掉一命, 剩最后一命时不再输(0 命打不了积分赛);
##   胜场 = 碎蛋数; 横扫 ≤ 胜场。每场固定抽两次随机数 ⇒ 前缀一致。
static func _seed_record(battles: int, rng: RandomNumberGenerator) -> Dictionary:
	var w := 0
	var l := 0
	var sweeps := 0
	for i in range(battles):
		var r_win := rng.randf()
		var r_sweep := rng.randf()
		if l >= int(_P2.HEARTS_MAX) - 1 or r_win < 0.5:
			w += 1
			if r_sweep < 0.5:
				sweeps += 1
		else:
			l += 1
	return {"wins": w, "hearts": int(_P2.HEARTS_MAX) - l, "sweeps": sweeps}

## ★headless(测试/仿真/导出) 绝不写玩家真实池 —— 与 GameState.test_mode 同一条纪律(GameState.gd:570)。
## 起因(2026-07-27): GameState.save() 早有这个守卫, save_pool 一直没有 → 任何跑战斗的测试赢一把就
## upload_ghost 污染 user://ghost_pool.json; 更隐蔽的是 load_pool→_ensure_seeded→save_pool(L211),
## 【光是读池就会写盘】。存档目录里那个 savegame.json.bak-被测试污染 就是同类事故的遗迹。
## 只挡默认的 user:// 真实池; 显式传 path(自举仿真/离线产池) 照写不误。
## 换周: 对手池里只留内置陪练(`seed_`), 真人快照全清。
## ★用户 2026-10-08「每周快照会刷掉对吧」「改」: 选靶只认「总场次相同」、不认哪一周 ⇒
##   不清的话新一周还会抽到上周存下来的同场次阵容。服务端拉取本来就只拉本周(`season_week=eq.`),
##   清掉本机这份之后, 新一周的真人对手全部来自本周的服务端快照。返回清掉了几条。
static func drop_week_snapshots(pool: Dictionary) -> int:
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	var n := 0
	for b in buckets.keys():
		var keep: Array = []
		for g in (buckets[b] as Array):
			if g is Dictionary and str((g as Dictionary).get("ghost_id", "")).begins_with(SEED_ID_PREFIX):
				keep.append(g)
			else:
				n += 1
		buckets[b] = keep
	return n


## 换周时调(GameState.start_new_season): 读池 → 清真人快照 → 落盘。
static func wipe_week_snapshots(path: String = POOL_PATH) -> int:
	var pool := load_pool(path)
	var n := drop_week_snapshots(pool)
	save_pool(pool, path)
	return n


static func save_pool(pool: Dictionary, path: String = POOL_PATH) -> void:
	if path == POOL_PATH and GameState != null and bool(GameState.test_mode):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(pool, "  ")); f.close()

# ─── 高层 orchestration (gameplay 调这俩) ───
## 匹配用的【单一受控 PRNG】(Riot 确定性做法: 一个隔离的、可种子化的随机源)。
## 默认 randomize() —— 与线上行为字节一致, 玩家侧永远随机。
## 仅当环境变量 TURTLE_SEED=<整数> 时改用固定种子 → 同种子必得同对手 → 测试/复现可确定。
## 这是"结构治理·切片1": 把匹配随机收束到一个入口, 后续战斗 RNG 也走同一模式。
static func make_match_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var s := OS.get_environment("TURTLE_SEED")
	if s != "" and s.is_valid_int():
		r.seed = int(s)
	else:
		r.randomize()
	return r

## 抽对手: 找一个【总场次完全相同】的 ghost, 没有就 bot. 永远返回一个可打的对手.
##
## ★★★回落只有两级 —— 这是 D5(`docs/plans/20260916-大轮赛制v2周赛制.md:349`)
##   「硬条件是**双方总场次相同**(不再按 9 档)」+ 用户 2026-09-26「不应该有什么正负一」:
##     ① 场次完全相同
##     ② 机器人
##
## ★★★被删掉的两级, 连同它们当时的理由, 留在这里当路标:
##   · ~~±MATCH_BATTLES_SPAN(对称)~~ —— 理由是「池子薄时只查等场次会查不到人」。
##     那是**拉取**那一侧的理由, 我 2026-09-25 把它套到了选靶上。
##   · ~~往【下】逐格找最近的(绝不往上)~~ —— 理由是 2026-07-27「绝不撞到明显更强的对手」。
##     那条约束当年只能用"格子"表达, 因为没有更细的尺子; 现在尺子就是场次本身,
##     「完全相同」比「只往下」更紧 ⇒ 那一级的意图**已经被 ① 完全覆盖**, 不是被放弃。
##   ⇒ 供给不够的正解是**把池子做厚**(SEED_VER v12 按每个场次各 12 支重做), 不是放宽尺子。
##     `match_src_counts` 就是这条决定的账, 拿真数据说话。
##     ⚠ **要看的那一格是 `exact_human`, 不是 `exact`**(2026-09-28 改):
##       `exact` 把内置陪练也算进来 —— 实测 396 条种子池下它是 **100%** 而真人 0 次。
##       「池子做厚了吗」问的是真人供给, 拿总数去答会得出"已经够厚了"这种反的结论。
##
## ★★★入参就是唯一的尺子。**不许在这里再读一遍 GameState** ——
##   2026-09-25 我把签名从 `bracket` 改成 `battles` 却忘了改函数体里那一行,
##   于是参数进来被无声无息地丢掉、照旧读全局 ⇒ 正是我声称刚消灭的"两把尺子"。
##   抓到它的是 `verify_bracket_gear` 那条「窗口往上真的开着吗」(往上 0 次 / 往下 360 次),
##   不是任何硬边界判据 —— 类型相同、名字没变、编译器不拦。
static func find_opponent(battles: int, exclude_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	## ★远端同步: 顺手发一次拉取, 但**它给的是【下一局】的池子** —— 本局的对手就在
	##   下面几行用现在这个 pool 算出来, 一步都不等网络。这是"离线不退化"的落点:
	##   断网时这两行是 no-op, 下面照常跑。
	##   (verify_remote_pool 用真 HTTPRequest 打不可达地址量过: 匹配耗时 8ms ≪ 超时 6000ms。)
	var RP = load("res://scripts/net/remote_pool.gd")
	if RP != null:
		RP.pull_async(battles)
	## ★场次直接用选靶用的**同一个入参** —— 不是两处各读一次。
	##   这是「传上去的和拉回来的对不上」那类静默 bug 唯一可靠的防法:
	##   只要有一维取的不是同一个量, 池子就永远是空的而没任何报错。
	var SB = load("res://scripts/net/supabase.gd")
	if SB != null and GameState != null:
		SB.pull_opponents_async(int(GameState.week_anchor_ts), battles,
			str(GameState.account_id))
	## ① 场次完全相同
	## ★★选靶器内部另有一道**合法性**筛(`ghost_lanes_broken`, 2026-09-29):
	##   分路坏掉的快照不算对手, 筛光了这里就拿到 null ⇒ 落到 ② bot。
	##   匹配的**尺子**一个字没动(D5「总场次完全相同」), 回落也还是只有 bot。
	var ge = pool_find_battles(pool, battles, exclude_ids, rng)
	if ge != null:
		## ★记账要分得开【真人 / 陪练】—— 不分的话这个数 100% 虚高(见 match_src_counts 头注)。
		_tally_exact(ge)
		return ge
	## ② 机器人(永久安全网)
	_tally("bot")
	return make_bot(maxi(0, battles), rng)


## ★★E-A4(2026-09-22) 周六闯关赛的匹配 —— 与上面那条**是两套**, 不是加个参数。
##
## 原稿逐字:「只有战绩标签完全相同者互配(3-1 只碰 3-1)。同标签 ⟹ 同场数 ⟹
##   周六内供给完全一致; 兜底链: 同标签真人排队 → 同标签新鲜快照(30 分钟内)→ 机器人。
##   **永不跨标签**」。
##
## ★与积分赛那条的三处**有意不同**, 每处都有理由:
##   ① 积分赛允许 `battles=in.(N-1, N, N+1)` 差一场(池子薄时的让步, **上下对称**);
##      闯关赛**完全相等** —— 放宽一格就是让 3-1 打 3-2, 两人经济供给差一整场,
##      而"同战绩的人互相淘汰"正是这个赛制的全部意义。
##   ② 积分赛的新鲜度是**排序**(D10: 池子薄, 卡时间窗会经常凑不出人);
##      闯关赛的 30 分钟是**过滤**(U3b: 淘汰赛宁可等、宁可打机器人, 也不要打一份隔夜快照)。
##   ③ 回落**不降标签**, 只降到机器人 —— 上面那条会 `for b in range(bracket, -1, -1)`
##      往低档找, 这里一格都不许降。
##
## ⚠ 本函数**一行网络代码都没有**(与 `find_opponent` 同一条纪律): 本局就用现在这个本地池算。
##   下面那次拉取的是**当前**标签 —— 打完这场标签就换了, 它只在「取消匹配再进来」时用得上。
##   ★真正喂池子的是 `prefetch_gauntlet_pool()`(主菜单 + 每场结算后, 提前一格拉)。
static func find_gauntlet_opponent(gw: int, gl: int, exclude_ids: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	if GameState != null:
		var SB2 = load("res://scripts/net/supabase.gd")
		if SB2 != null:
			SB2.pull_gauntlet_async(int(GameState.week_anchor_ts), gw, gl,
				str(GameState.account_id))
	## ① 同标签的新鲜快照。**一格都不降**。
	## ★`gauntlet_pool_find` 内部与积分赛那条**调同一个**合法性筛 `ghost_lanes_broken`。
	var ge = gauntlet_pool_find(pool, gw, gl, exclude_ids, rng)
	if ge != null:
		_tally("gauntlet_label")
		return ge
	## ② 机器人(永久安全网)。★记成**另一个**计数, 不与积分赛的 bot 混在一起 ——
	##    「周六有多少场是打机器人的」是 R2 那条风险唯一能回答的数字。
	_tally("gauntlet_bot")
	return make_bot(gauntlet_bot_battles(
		int(GameState.season_total_battles) if GameState != null else 0, gw, gl), rng, gw, gl)


## 周六机器人按几场的强度造。
## ★★2026-10-03 用户实打:「周六对手什么装备都没有，这怎么可能？整个机制就是坏的啊」。
##   原来是 `make_bot(gw + gl)` —— 拿**周六的标签**当**本大轮场次**用。两个不同的量:
##   周六第一场标签是 0-0 ⇒ 场次 0 ⇒ `bot_level_for_battles(0)=1` ⇒ `team_equip_cap(1)=0` ⇒ **一件装备都没有**;
##   而走到周六的人已经打了整个积分赛(探针: 24 场的人该配 16 件)。
##   而且 0-0 这一格**永远没有真人快照**(快照是打完才按新标签传的), 所以周六第一场**每个人都**碰到这个裸机器人。
## ★取 `season_total_battles`(它本来就含周六场次, `gauntlet_settle` 里 +1), 兜底不低于标签算出的场数。
static func gauntlet_bot_battles(season_total: int, gw: int, gl: int) -> int:
	return maxi(season_total, gw + gl)


## 周六打完一场 → 产出一份**带战绩标签**的快照, 入本地池并传云端。
##
## ★★标签取的是**打完之后**的战绩: 下一场要找的是"跟我现在同样几胜几负"的人。
##   传打之前那个标签, 等于把自己挂在**上一格**上 —— 别人按新标签找永远找不到我,
##   而这件事**不会报任何错**, 只会表现成"周六老是匹配到机器人"。
## ★三个 `gl_*` 字段是匹配层唯一的依据(`gauntlet_pool_find` 读它们)。
##   ghost_id 也要带标签, 否则 `pool_add` 按 id 去重会让同一个人只剩最新一格
##   —— 那正是 A6 给积分赛 id 加"场次"那一维的同一个理由。
## 本进程里周六快照真的产出过几份(记在事件发生处·无条件)。只读用途: 门禁 verify_finals_settle ③
##   —— 周六快照的上传曾经整块错放在周日分支里, 一份都没传过, 而且不报任何错。
static var gauntlet_uploads: int = 0

static func upload_gauntlet_ghost(gw: int, gl: int) -> void:
	if GameState == null:
		return
	var leaders = GameState.season_leaders
	var base := player_ghost_id(int(GameState.season_id), leaders, -1)
	var gid := "%s_g%d-%d" % [base, gw, gl]
	var av := str(leaders[0]) if (leaders is Array and (leaders as Array).size() > 0) else "basic"
	## ★名字用玩家昵称(没设就是兜底短码) —— 排行榜显示的就是这个字段。
	var snap := build_ghost_snapshot(gid, {"name": player_display_name(), "avatar": av, "id": gid})
	if snap.is_empty():
		return
	snap["gl_w"] = gw
	snap["gl_l"] = gl
	snap["gl_ts"] = int(Time.get_unix_time_from_system())
	gauntlet_uploads += 1
	## 老通道: 只进本地池。★★不进积分赛的 `ghosts` 表(2026-10-10 周六实操查实): 原来这一句也排进了 ladder 队列,
	##   每打一场闯关赛就往积分赛那张表写一行「第 17、18…场」⇒ 服务端周榜(每人取最新一行)周六还在变,
	##   「积分赛终榜」上出现总场次 20(上限 16)、名次被闯关赛改写。周六那份走下面自己的 gauntlet 队列。
	upload_ghost(snap, false)
	## ★E7: 同积分赛那一份, 进落盘队列, 回读确认才销单(`ghost_uploader.gd`)。
	var GU3 = load("res://scripts/net/ghost_uploader.gd")
	if GU3 != null:
		GU3.enqueue_gauntlet(snap, int(GameState.week_anchor_ts), gw, gl,
			str(ProjectSettings.get_setting("application/config/version", "")))
	## ★传完我这一格, 顺手把这一格别人的拉回来 —— 这正是下一场要匹配的那一格(见 `prefetch_gauntlet_pool` 头注)。
	prefetch_gauntlet_pool()


## 周日决赛日报到。★只有**这一场把我打成「晋级」**时才报 ——
##   判据走 `GameState.gauntlet_state()`(与 UI、补发同一个答案), 不在这里另写一份。
## ★快照与 `upload_gauntlet_ghost` 取的是同一份(同一场、同一套阵容)。
static func report_finals_entry() -> void:
	if GameState == null:
		return
	if str(GameState.gauntlet_state()) != "in":
		return                        # 还在打 / 已出局 —— 都不该报到
	var leaders = GameState.season_leaders
	var gid := player_ghost_id(int(GameState.season_id), leaders, -1)
	var av := str(leaders[0]) if (leaders is Array and (leaders as Array).size() > 0) else "basic"
	var snap := build_ghost_snapshot(gid, {"name": player_display_name(), "avatar": av, "id": gid})
	if snap.is_empty():
		return
	var SB4 = load("res://scripts/net/supabase.gd")
	if SB4 == null:
		return
	SB4.enter_finals_async(int(GameState.week_anchor_ts), player_display_name(),
		snap, int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))


## ★★★补报: 周六晋级了但那一刻没报上去 ⇒ 下次打开主菜单时补一次。
##
## `report_finals_entry()` 在**第 4 胜那一刻**调, 而那一刻可能: 没网 / token 刚过期 /
## 玩家顺手杀了 App。原来那条路是**发了就不管**(回调空), 漏了就永远漏了 ——
## 周日他进不去, 而屏幕说他「晋级才进得来」, 他明明打到了 4 胜、也没有自救办法。
##
## ★这里**只判补报特有的那两条**, 「该不该报」本身不重判:
##   ① 周锚点是个正数(赛季没初始化时别乱报, 报了也记不清是哪一周)
##   ② 这一周**还没确认报成**(`finals_entered` 读 `finals_entered_week`)——
##      少了它就变成"每次开主菜单都往服务端捶一下"。
## ★★「战绩是不是晋级」由 `report_finals_entry()` 自己判, 这里**不抄第二遍**。
##   我第一版在这里也写了一道 `gauntlet_state() != "in"` ⇒ 反向验证时**拿掉它没红**,
##   因为内层那道照样挡着 ⇒ 它是死代码, 而我的注释还声称"少一条就会出问题"
##   (memory fb-mutation-not-reddening-can-mean-dead-code: 打不红要问"这行在任何
##    输入下都会改变结果吗"; 同 `login_wall_on` 那条纪律: 判据只留一处)。
## ★服务端 RPC 是 `on conflict do update` ⇒ 重复报安全; 真的补不上(桶已切)时
##   它回 `already_seated`, `finals_enter_ok` 判 false ⇒ 不会把标记写成"成功"。
## ★★周六进场先传一份 0-0 快照(用户 2026-10-04 拍板「行」)。
##   由来: 周六快照原来**打完一场才传**、按新战绩归档 ⇒ 0-0 这一格永远是空的 ⇒ 每个人第一把必配机器人。
##   ⇒ 有资格打周六、还没开打(0-0)、本周还没传过 ⇒ 用此刻阵容(= 积分赛收尾阵容, 0-0 的人经济完全相同)传一份。
##   之后进来的人第一把就能配到先来者的 0-0 真人阵容。当天第一个进来的人仍会回落机器人(不跨周用旧快照: 不公平)。
## 返回: 这一次真的传了没有(门禁用)。
static func ensure_gauntlet_entry_snapshot(now: int = 0) -> bool:
	if GameState == null:
		return false
	var ts: int = now if now > 0 else int(_P2.now_utc())
	if _P2.phase_at_utc(ts) != _P2.PHASE_GAUNTLET or not _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		return false
	var wk: int = int(GameState.week_anchor_ts)
	if wk <= 0 or int(GameState.gauntlet_entry_week) == wk:
		return false
	if not GameState.gauntlet_eligible():
		return false
	if int(GameState.gauntlet_wins) != 0 or int(GameState.gauntlet_losses) != 0:
		return false
	upload_gauntlet_ghost(0, 0)
	GameState.gauntlet_entry_week = wk
	GameState.save()
	return true


## ★★周六对手池要【提前一格】拉(2026-10-10 60 人实操查实)。
##   `find_gauntlet_opponent` 里那次拉取拉的是**当前**标签, 而它照纪律不等网络、当场用本地池算 ——
##   积分赛那条拉 N 与 N+1 场次, 下一局用得上; 闯关赛**打完这一场标签就换了, 永远不会回到这一格**
##   ⇒ 拉回来的真人一份都用不上。实测 p14 0-0 拉回 9 份真人、入池 9, 照样配了机器人。
## ⇒ 在【已经知道下一场是哪一格】的两个时刻拉: 进主菜单(当前格: 管第一场与重开 App)、
##   每场闯关赛结算后(新格)。匹配那一步仍然一行网络都不碰。
## 返回: 这一次真的发了没有(门禁用)。
static func prefetch_gauntlet_pool(now: int = 0) -> bool:
	if GameState == null:
		return false
	var ts: int = now if now > 0 else int(_P2.now_utc())
	if _P2.phase_at_utc(ts) != _P2.PHASE_GAUNTLET or not _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		return false
	if not GameState.gauntlet_eligible():
		return false
	if str(GameState.gauntlet_state()) != _P2.GAUNTLET_RUNNING:
		return false
	var SB2 = load("res://scripts/net/supabase.gd")
	if SB2 == null:
		return false
	SB2.pull_gauntlet_async(int(GameState.week_anchor_ts), int(GameState.gauntlet_wins),
		int(GameState.gauntlet_losses), str(GameState.account_id))
	return true


static func ensure_finals_entry() -> void:
	if GameState == null:
		return
	var wk: int = int(GameState.week_anchor_ts)
	if wk <= 0:
		return
	var SB5 = load("res://scripts/net/supabase.gd")
	if SB5 == null or SB5.finals_entered(wk):
		return
	report_finals_entry()


## 最近一次**交给网络层**的决赛结果上报参数。观测量, 进程内, 不进存档。
##
## ★★为什么要有它: 上报是"发完就忘"的, 而 `report_finals_async` 有四条早退
##   (`_token == ""` 是其中一条, 而 token **只活在内存、每次冷启动都是空的**) ——
##   那几条走掉时**一点痕迹都不留**, 客户端毫不知情。⇒ 在交接的那一刻记一笔。
## ★它**不是**「我插一行数一行」那种假门禁: 判据量的是**流过这个交接口的值对不对**
##   —— 补报必须带【那一场】的 seed 与周号, 不是「现在」的那个
##   (探针 `tests/_probe_finals_retry.gd` 量到过 4242 ↔ 999 的分岔)。
##   与 `match_src_counts` 同一条纪律: 记账放在**事件发生处且无条件**。
## ⚠ 它记的是「交给网络层了」, **不是**「发出去了」。「真报成了」的唯一判据仍是
##   `SupabaseNet.finals_reported()`(只在 2xx 回调里置真) —— 两者不许混。
static var last_finals_report: Dictionary = {}


## E-B6: 把决赛日某一场的结果报上去。
## ★与 `report_finals_entry` 同一层、同一形状：**周号从 GameState 取**，
##   战斗场那边只负责说「哪个桶、第几轮、第几场、哪一侧赢」——
##   在主场景里再拼一次 `week_anchor_ts` 就是同一判据存两份。
## ★`winner_side` 已经由 `BracketMapScene.winner_side_for()` 算好，这里不重算。
##
## ★★★`seed_used` 是**入参**, 不在函数体里读 `GameState.battle_seed`(2026-09-28 改)。
##   由来: 补报那条路(`retry_finals_report`)报的是**过去某一场**, 而
##   `GameState.battle_seed` 是**现在这一场**的 —— 探针 `tests/_probe_finals_retry.gd`
##   量出来的分岔就是这个: 补报单上存着 `seed=4242`, 而函数体读到的是 `999`。
##   ⇒ 补报单里那个 `seed` 字段**一个读者都没有**(全仓 grep 过), 而报上去的是另一个数。
##   `p_seed` 是服务端确定性复算用的种子 ⇒ 报错了就等于报了一场复算不出来的比赛。
##   ⚠ 这正是 memory `fb-read-a-field-nobody-writes` / `fb-zero-caller-is-a-whole-class`
##     那一族: 「写了没人读」。**入参化**之后, 两个调用点各自说清自己报的是哪一场的种子,
##     编译器帮着数(少传一个直接不编译), 不会再有第二个人在函数体里偷偷换尺子。
##   (`0` 的含义仍是「这一场没留下可复算的种子」—— 服务端 `coalesce(p_seed, 0)` 本来就收 0。)
static func report_finals_result(bucket: int, round_no: int,
		match_no: int, winner_side: int, seed_used: int) -> void:
	if GameState == null or bucket < 0 or round_no < 1 or match_no < 0:
		return
	var SB5 = load("res://scripts/net/supabase.gd")
	if SB5 == null:
		return
	var wk := int(GameState.week_anchor_ts)
	## ★★留痕 —— 见 `last_finals_report` 的头注。写在**交接的那一刻**且无条件。
	last_finals_report = {"week": wk, "bucket": bucket, "round": round_no,
		"match": match_no, "side": winner_side, "seed": seed_used}
	SB5.report_finals_async(wk, bucket, round_no, match_no, winner_side, seed_used)


## E-B6: 这一局如果是决赛日对阵图里的某一场，把结果报上去；不是就什么都不做。
## ★★**住在这一层而不是主战斗文件里**：它一行每帧逻辑都没有，属于「结算期接线」——
##   CLAUDE.md §5 的判据只有一条「不在 `_sim_step` 调用链上的，不进主文件」。
##   第一版写在 `RealtimeBattle3DScene` 里，`arch_budget` 当场红（8770 → 8778 行）；
##   凑行数的正确动作是**把函数搬到该在的文件**，不是删注释
##   （[[fb-line-filter-eats-code-on-mixed-eol]]）。
## ★**纯接线**，一行判据都不在这儿：哪一侧是我由 `BracketMapScene.winner_side_for()`
##   在开局时算好、存进 `finals_match.side`；同一场报不报第二次由
##   `SupabaseNet.report_finals_async()` 自己挡。这里只做 `side if won else 1-side`。
## ★★**无论报没报成功都清空**：留着它的唯一后果是
##   下一场普通对局被当成决赛再报一次（而且报的是另一场的场号）。
static func report_finals_if_any(won: bool) -> void:
	if GameState == null:
		return
	var fm = GameState.get("finals_match")
	if not (fm is Dictionary) or (fm as Dictionary).is_empty():
		return
	var d: Dictionary = fm
	## ★★★2026-09-27 结果封存(原稿 §五.5)。记 pending 必须在**清空 `finals_match` 之前** ——
	##   它就是这一局的身份, 清掉就没了。
	##   周日是双方各自在本机打对方的快照(两场不同的战斗, 都可能算出自己赢),
	##   所以打完**不宣布胜负**: 吃胜负的那几项封存, 等对阵图的 feed 揭晓
	##   (唯一权威 = `finals_view` 的 `done`, 一个桶里只有一个值)。
	##   方案书 `docs/plans/20260927-周日结果封存.md`。
	var r := int(d.get("round", -1))
	var m := int(d.get("match", -1))
	if r >= 1 and m >= 0:
		## ★带组号(2026-10-07 冠军杯赛): 杯与小组赛坐标相同, 不带组号就会拿小组赛那张的 `done` 去揭晓杯那一场。
		GameState.finals_pending_reveal = {"round": r, "match": m, "bucket": int(d.get("bucket", -1))}
	var side := int(d.get("side", -1))
	if side == 0 or side == 1:
		var ws: int = side if won else (1 - side)
		## ★★★**先把补报单写进存档, 再发**。上面那句「无论报没报成功都清空
		##   `finals_match`」对它自己是对的(它是「我现在在哪一场」), 但那也意味着
		##   **一旦发失败就再也没有重试所需的身份了**。
		##   ⇒ 另存一份能过夜的补报单, 与 v0.19.446 的 `finals_entered_week` 同一个样板。
		## ★★单子上的 seed 与真发出去的那个**必须是同一个表达式算出来的** ——
		##   各读一遍就是同一个量存两份, 而这两份一分岔, 补报报的就是另一场
		##   (2026-09-28 查实: 补报那条路原来真的分岔了, 见 `report_finals_result` 头注)。
		var sd := int(GameState.battle_seed)
		GameState.finals_report_pending = {
			"bucket": int(d.get("bucket", -1)), "round": r, "match": m,
			"side": ws, "seed": sd,
		}
		report_finals_result(int(d.get("bucket", -1)), r, m, ws, sd)
	GameState.finals_match = {}


## E-B6b: 上次那一场的结果报上去了吗? 没有就补一次(2026-09-27)。
##
## ★★与 `ensure_finals_entry`(报名补报)同一层、同一形状 —— 主菜单每次打开各调一次。
##   两者都是「那一刻可能没网, 而那一刻只有一次」。
## ★判据是 `SupabaseNet.finals_reported()`(**只在真报成之后才为真**), 不是「发过了」。
## ★报重了无害: 服务端 `finals_report` 是 `on conflict do nothing`(先到先得);
##   而漏报会让那一场只能靠 960 秒宽限兜, **可能把错的人送进下一轮**。
##   ⇒ 宁可多报一次, 不可漏一次。
static func retry_finals_report() -> void:
	if GameState == null:
		return
	var p = GameState.get("finals_report_pending")
	if not (p is Dictionary) or (p as Dictionary).is_empty():
		return
	var d2: Dictionary = p
	var r2 := int(d2.get("round", -1))
	var m2 := int(d2.get("match", -1))
	if r2 < 1 or m2 < 0:
		GameState.finals_report_pending = {}
		return
	var SB6 = load("res://scripts/net/supabase.gd")
	if SB6 == null:
		return
	if SB6.finals_reported(r2, m2, int(d2.get("bucket", -1))):
		GameState.finals_report_pending = {}       # 已经报成了, 销单
		GameState.save()
		return
	## ★★★侧别坏掉的单子**报不出去也要销掉**(2026-09-28)。`report_finals_async` 对
	##   `winner_side != 0/1` 是无条件早退 ⇒ 留着它就是**每次开主菜单都往那儿捶一下**,
	##   而且永远捶不成(`ensure_finals_entry` 头注里点名不许出现的那种形状)。
	##   ⇒ 这不是"漏报也要销单": 只有**结构上报不出去**的单子才销。
	var sd2 := int(d2.get("side", -1))
	if sd2 != 0 and sd2 != 1:
		GameState.finals_report_pending = {}
		GameState.save()
		return
	## ★★★seed 取**单子上那份**, 不是 `GameState.battle_seed` ——
	##   后者是「现在这一场」的, 而补报报的是过去某一场。探针量到过 4242 ↔ 999 的分岔。
	report_finals_result(int(d2.get("bucket", -1)), r2, m2, sd2,
		int(d2.get("seed", 0)))


## 玩家显示名 —— **全仓唯一出处**。有昵称用昵称, 没有用确定性兜底短码。
## ★昵称在**绑定邮箱**那一屏与邮箱同时填(用户 2026-09-24「这个在创建账号应该一起吧」)——
##   那是玩家唯一感知得到的「创建账号」时刻: 首启建匿名号是**静默**的, 没有任何界面。
## ★没绑邮箱的匿名号用兜底短码, 不强制 —— 规则与文案都在 `phase2_config` 那一节。
static func player_display_name() -> String:
	if GameState == null:
		return "?"
	## ★自己起过名 ⇒ 用它; 没起过 ⇒ `GameState.default_nickname()`(首次生成并落盘, 之后不变 ——
	##   用户 2026-10-04 拍板, 防昵称池变化把默认名换掉)。判据与 `_P2.display_name` 同一条。
	var s := _P2.nickname_clean(str(GameState.nickname))
	if s.length() >= _P2.NICK_MIN:
		return s
	return str(GameState.default_nickname())


## 我自己的玩家 ID(`#XXXXXX`, 见 `_P2.player_tag`)。
## ★种子与默认名同一条规则(`nickname_seed`): 有账号用账号 ⇒ 换设备 / 重装后用邮箱取回同一个号,
##   ID 不变; 还没拿到账号(首启离线 / 没配后端)时用本机安装号。
## ★拿到账号那一刻 ID 会从「安装号算的」**换成**「账号算的」, 而且故意不冻结:
##   对阵图上别人看到的我的号是拿 `finals_view` 回包里的 account_id **在他那台机器上现算**的,
##   冻结一个安装号算出来的旧号 ⇒ 我在设置页看到的和别人看到的对不上。
##   而没账号的阶段什么都传不上服务端(`ghost_row_from_snapshot` 缺 account_id 直接不传),
##   那串旧号从来没被别人看见过 ⇒ 换掉不会让任何人困惑。
static func my_tag() -> String:
	if GameState == null:
		return ""
	return _P2.player_tag(_P2.nickname_seed(str(GameState.account_id), str(GameState.get_install_uid())))


## 一份对手资料(快照里的 `profile`)该显示哪个 ID。
## ① 快照自带 `tag`(2026-10-04 起真人 / 机器人 / 陪练都带) ⇒ 用它。
## ② 老快照没有 ⇒ 从 `profile.id` 里切出「谁」(`owner_tag_of_id` 的 uid 段)现算 ——
##    同一个人各场次是同一个号; 实在切不出就拿整串算(仍是同一格式, 不会冒出另一种长相)。
## ★任何分支给出来的都是 `_P2.tag_valid` 的形状 —— 卡片上不许出现第二种格式
##   (第二种格式 = 一眼认得出是哪一类对手, 用户 2026-10-04「不能让玩家知道是机器人」)。
static func profile_tag(prof: Dictionary) -> String:
	var t := str(prof.get("tag", ""))
	if _P2.tag_valid(t):
		return t
	var pid := str(prof.get("id", "")).strip_edges()
	if pid == "":
		return ""
	var owner := owner_tag_of_id(pid)
	if owner != "":
		var parts := owner.split("_")
		## `g_<uid>_<赛季>_` ⇒ parts = [g, uid, 赛季, ""]; 没 uid 的 `g_<赛季>_` 只剩赛季, 不能拿它算(人人相同)。
		if parts.size() >= 4 and parts[1].length() == UID_HEX_LEN:
			return _P2.player_tag(parts[1])
	return _P2.player_tag(pid)


## 机器人 / 陪练的那串 ID 从哪个身份算。
## ★★不能拿 `profile.id` 里那段 uid 算: 真人的号是**账号**算的, 与 uid 无关;
##   要是机器人的号恰好 = f(uid), 任何拿到快照的人都能逐条验出「这是机器人」(用户 2026-10-04
##   「不能让玩家知道是机器人」)。⇒ 用 `ghost_id` 这一维 —— 它是用机器人自己的随机数生成的,
##   而且只在本机(出站两条路都过 `ReplayUploader.GHOST_STRIP` 摘掉), 别人拿不到。
## ★陪练用 `seed_person_of(ghost_id)`(去掉场次那一段) ⇒ 同一个人各场次同一个号。
static func fake_person_tag(person: String) -> String:
	return _P2.player_tag("acct:" + person)


## 在本地池里找【同标签且新鲜】的一份快照。找不到返回 null(回落交给上面那个函数)。
## ★新鲜度用快照自带的 `gl_ts`(上传时刻), 缺这个字段的一律当**不新鲜**排除 ——
##   老快照没有这一维, 把它当新鲜就等于"永不过期", 那条 30 分钟规则会静默失效。
static func gauntlet_pool_find(pool: Dictionary, gw: int, gl: int,
		exclude_ids: Array, rng: RandomNumberGenerator):
	## ★★★2026-09-26 修: 原来这里写的是 `for gid in pool.keys()` —— **读错了一层**。
	##   真实池子的顶层只有两个键(实测玩家存档 `ghost_pool.json`):
	##     `_seed_ver`(int) ⇒ 被下面的 `is Dictionary` 跳过
	##     `brackets`(Dictionary) ⇒ **过了**类型检查, 但它没有 `gl_w` ⇒ 被标签检查跳过
	##   ⇒ `cands` **恒为空** ⇒ 恒返回 null ⇒ 周六**每一场都是机器人**, 而且一声不吭。
	##   同文件另外三处(`pool_find` / `pool_find_near` / `pool_find_window`)读的都是
	##   `pool.get(POOL_KEY, {})` 再进数组 —— 只有闯关赛这一个抄错了形状。
	## ★★门禁当时全绿, 因为 `verify_gauntlet_match` 手造的池子是**扁平** `{id: snap}` ——
	##   那个形状 `load_pool()` / `pool_add()` **从来不生产**
	##   (memory fb-gate-subject-never-constructed: 判据没错但被测对象不在场)。
	## ★id 从快照自己的 `ghost_id` 取(池子里是数组, 没有外层键当 id 用了)。
	## ★★「现在」走 `_P2.now_utc()` 这条**可注入的时间缝**, 不直接读系统钟(2026-09-28 接)。
	##   为什么: 下面那条 30 分钟新鲜度是**唯一**决定「周六打真人还是打机器人」的尺子,
	##   而拿系统钟当尺子的判据只有"真的到了那一刻"才验得到 ——
	##   本仓已经为此吃过一次(`_status_row` 那条只有真周六才执行得到)。
	##   缝默认关着(`now_override_ts == 0` ⇒ 逐字节就是原来那个表达式) ⇒ 玩家路径一字未动。
	##   门禁 `tests/verify_pool_truth.gd` ⑧ 钉住一个时刻、走**真入口** `gauntlet_pool_find`,
	##   证明新鲜/隔夜的判定真的跟着钉的钟走(不是只在源码里出现了这个符号)。
	var now: int = int(_P2.now_utc())
	var buckets: Dictionary = pool.get(POOL_KEY, {})
	var cands: Array = []      # 同标签 + 新鲜(30 分钟内)
	var stale: Array = []      # 同标签 + 隔夜 —— 新鲜的一个都没有时才用它(见下面那段长注释)
	var by_id := {}
	for b in buckets.keys():
		for g in (buckets[b] as Array):
			if not (g is Dictionary):
				continue
			var gid := str((g as Dictionary).get("ghost_id", ""))
			if gid == "":
				continue
			if gid.begins_with(self_prefix(int(GameState.season_id) if GameState != null else 0)):
				continue                  # 自己(含同赛季换过龟的旧阵容)
			if exclude_ids.has(gid):
				continue
			## ★分路坏掉的不是对手 —— 与积分赛那条**调同一个函数**
			##   (`ghost_lanes_broken`, 2026-09-29)。两处各写一遍就等于下次改判据时漏一处
			##   (`is_sparring` 的头注记着同一件事做了一半的代价)。
			if ghost_lanes_broken(g):
				continue
			if int(g.get("gl_w", -1)) != gw or int(g.get("gl_l", -1)) != gl:
				continue                  # ★标签必须完全相同
			var ts: int = int(g.get("gl_ts", 0))
			## ★★★2026-09-26 30 分钟从【过滤】改成【排序偏好】。
			##
			## 原稿的兜底链是三级:「同标签真人排队 → 同标签新鲜快照(30 分钟内) → 机器人」,
			## 而 U3b 那次我把 30 分钟做成了**硬过滤**(「淘汰赛宁可打机器人也不要打隔夜快照」)。
			## 算出来的代价(方案书 `docs/plans/20260926-周末赛制在各规模下会怎样.md` §2.2):
			##
			##   人数 |  10  | 100 | 1000
			##   机器人| 93% | 49% | 0.1%
			##
			## ⇒ **10 个人测一周, 周六 93% 的对局是机器人**, 而周六的全部意义是
			##   「同战绩的人互相淘汰」。而第①级(同标签真人排队)一行没做, 它本来是主力。
			##
			## ★这不是把 U3b 推翻, 是**按原稿链的优先级排**: 原稿把**任何真人路径**都排在
			##   机器人前面。一份隔夜快照仍然是真人的阵容(而且周六同战绩 ⇒ 经济供给一致);
			##   机器人是合成的。⇒ 真人(新) → 真人(旧) → 机器人。
			## ★供给够的时候行为**逐字不变**: 有新鲜的就一定挑新鲜的(下面先看 fresh 那一桶)。
			##
			## ★**未来时间戳仍然一律当不新鲜**: `now - ts` 为负比任何阈值都小 ⇒
			##   不挡的话那份快照永不过期。(设备时钟走快、或者有人改过那一行都会造出这种行。)
			##   ⚠ 缺字段那一半是装饰(缺了就是 0, `now - 0` 本来就超窗) —— 2026-09-22
			##   反向验证查实过, 别再以为它在守什么。
			var fresh: bool = ts <= now and now - ts <= int(_P2.FRESH_SNAPSHOT_SEC)
			if fresh:
				cands.append(gid)
			else:
				stale.append(gid)
			by_id[gid] = g
	## ① 同标签 + 新鲜 ② 同标签 + 隔夜 ③ 都没有 → null(调用方兜 bot)
	## ★★跨标签一格都不许 —— 两个桶装的都是**同标签**的人, 区别只在快照新旧。
	var pick: Array = cands if not cands.is_empty() else stale
	if pick.is_empty():
		return null
	pick.sort()                           # 先定序, 再按种子抽 —— 不然同种子两次结果不同
	return by_id[pick[rng.randi() % pick.size()]]

## 玩家自己那份快照的 ghost_id = 大轮 + 【三龟组合】。
##
## ★放这里而不是放战斗场: 这条 id 规则的唯一消费者是下面的 `pool_add`(它按 id 去重),
##   规则和消费者贴在一起才不会各改各的; 而且它不在 `_sim_step` 调用链上, 按项目约定不进主文件。
##
## 沿革与两条【都要同时守住】的约束:
##   · 2026-07-18 原来 id 带战斗秒数 ⇒ 每场 upload 都是新 id 但同一套阵容 ⇒
##     池里同队堆几十条, "排除最近 3 场"形同虚设。改成 `g_<赛季>` 稳定 id 治好了这个。
##   · 但 `g_<赛季>` 一个大轮只有一个 id ⇒ 玩家在同一赛季里录第二套阵容会把第一套**顶掉**。
##     这条是用户 2026-08-15 要「我手打」录入多套阵容时才暴露出来的。
## ⇒ 粒度从"一个赛季"细到"一套阵容": 同一套重打仍是同一条(更新, 不堆), 换一套龟就是另一条(并存)。
## ★三龟【先排序】再拼 —— 同样三只龟换个上场顺序不该算两套阵容。
## ★★2026-08-27 加了【uid】这一维: `g_<uid>_<赛季>_<三龟>`。
##   原来是 `g_<赛季>_<三龟>`, **不带"是谁"** —— 单机本地池够用, 共享池立刻出两个洞:
##     · 两个玩家用同样三只龟 ⇒ **同一个 id** ⇒ 服务端互相覆盖, 后传的抹掉先传的
##     · 自己那份从服务器绕回来会顶掉本地那份(pool_add 按 id 去重) ⇒ **打到自己**
##   (28 只选 3 = 3276 种组合, 人少时不常撞, 但**热门组合会天天撞**, 而且是静默的。)
## ★★A6(2026-09-19) 加了【场次】这一维, 第三个参数。
##   由来(母方案书 §10.35 C7): 旧 id 不含场次, 而 `pool_add` 按 id 去重 ⇒
##   **同一玩家在池里只有最新一份快照** ⇒ **场次比你低的人永远匹配不到你**。
##   新规则要求"只和同场次的人打", 那就必须让同一个人的不同场次在池里【并存】。
## ★`battles < 0` = 不带这一维(老格式)。留这个默认值是为了让"只验 id 互不相同"的
##   老门禁继续有意义, **不是**为了让产品侧偷懒 —— 产品两处调用都必须传真实场次。
static func player_ghost_id(season_id: int, leaders, battles: int = -1) -> String:
	var arr: Array = (leaders as Array).slice(0, 3) if leaders is Array else []
	arr.sort()
	var base := "%s%d_%s" % [self_prefix(season_id), season_id, "-".join(PackedStringArray(arr))]
	return base if battles < 0 else "%s_b%d" % [base, battles]


## 本机在【某个赛季】产出的所有 ghost_id 的公共前缀 —— `g_<uid>_`。
##
## ★用它做前缀匹配就能一次挡住两种"自己":
##   · 自己当前这套(id 完全相同)
##   · **自己同赛季换过龟之后的旧阵容**(uid 同、赛季同、三龟不同)
## ★而【上个赛季的自己】故意不挡 —— 用户 2026-08-27 拍板「先不排除」:
##   赛季**一个自然周**一轮(UTC 周一 00:00 换轮·2026-09-20 起; 旧注释写的「5 天一轮」已作废)、切轮全重置,
##   上赛季的你阵容等级都不一样了, 当对手是合理的;
##   而且池子越空越不该自己往外剔。
static func self_prefix(_season_id: int) -> String:
	var uid := ""
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameState") if Engine.get_main_loop() != null else null
	if gs != null and gs.has_method("get_install_uid"):
		uid = str(gs.get_install_uid())
	return "g_%s_" % uid if uid != "" else "g_"


## 本机在【当前赛季】产出的 id 前缀 `g_<uid>_<赛季>_` —— 挡"这个赛季的自己"用。
static func self_season_prefix(season_id: int) -> String:
	return "%s%d_" % [self_prefix(season_id), season_id]


## 上传自己阵容快照进池 (玩家配好 build / 赢一场后).
## ★进本地池的这一份盖 origin=local 章 —— 匹配时靠它认出"这是我自己"(见 _is_self_ghost)。
##   ⚠ 盖在**副本**上: 调用方那份快照还要原样发给服务端, 不该带本机的来源标记。
## `ladder = false`: 只进本地池, 不往积分赛那张 `ghosts` 表排队(周六闯关赛用, 见 `upload_gauntlet_ghost`)。
static func upload_ghost(snapshot: Dictionary, ladder: bool = true) -> void:
	var mine := snapshot.duplicate(true)
	mine[ORIGIN_KEY] = ORIGIN_LOCAL
	var pool := load_pool()
	pool_add(pool, mine)
	save_pool(pool)
	if not ladder:
		return
	## ★远端同步(方案书 20260820 §落地步骤 2): 本地那步**先做完且一定成功**, 远端是追加的一次 POST,
	##   失败静默、不回滚、不碰存档 —— 网络是锦上添花, 不是开局的依赖。
	## ★用 load 不用 preload: remote_pool.gd 反过来 preload 本文件, **循环 preload 会编译失败**。
	##   (未配置后端时 `push_async` 直接 return, 连节点都不建 ⇒ 当前行为与接网前逐字节相同。)
	var RP = load("res://scripts/net/remote_pool.gd")
	if RP != null:
		RP.push_async(snapshot)
	## ★★D-4a(2026-09-21): 同一份快照也发一份到 Supabase 的 `ghosts`。
	##   两条路**暂时并存**: 旧层走旧后端协议(现在 `backend_url` 是空的 ⇒ 它是 no-op),
	##   新层走 Supabase REST。等 D-4b 把匹配也搬过去之后, 旧层整个退役。
	## ★主键要的三维在这里凑齐:
	##   · `account_id`   谁 —— 没登录就**不传**(见 `ghost_row_from_snapshot` 的前提判断)
	##   · `season_week`  哪一周 —— 用 `GameState.week_anchor_ts`(周锚点, 与赛程判定同一口径)
	##   · `battles`      第几场 —— 快照里的 `season_total_battles`
	##   ⚠ 少任何一维都会让两个人在服务端**静默互相覆盖**(memory `fb-id-without-owner-dimension`)。
	## ★★E7(2026-10-04): 不再发完就忘 —— 先进**落盘队列**, 回读确认才销单(`ghost_uploader.gd` 头注)。
	##   行在发的那一刻用 `SupabaseNet.ghost_row_from_snapshot` 拼; 周号/场次/版本取**此刻**的, 跟着单子走。
	##   账号没有也照样排队(发的时候用当时的账号) —— 原来 row 为空就直接不传了, 新装头几秒打完的那场就丢了。
	var GU = load("res://scripts/net/ghost_uploader.gd")
	if GU != null:
		GU.enqueue_ladder(snapshot, int(GameState.week_anchor_ts),
			int(snapshot.get("season_total_battles", -1)),
			str(ProjectSettings.get_setting("application/config/version", "")))

## 从玩家刚打的这局序列化成 ghost 快照 (上传自己用). ghost_id/profile 调用方给.
##
## ★★★2026-09-29 分路与装备的**来源换了** —— 原来读的那两个字段没有任何人往里写:
##
##   · `GameState.lane_assign` —— 全仓只有三处: `GameState.gd:132` 声明成空、
##     `:194` `reset_dual_lane()` 重置成空、**这里读它**。`grep` 全仓零个写入点。
##     真数据在 `dual_lineup`(玩家在背包里排的阵, `_save_dict` 里存的也是它)。
##   · `GameState.equipped_p2` —— 是**局内临时**的: `reset_dual_lane()` 每局清空、
##     **不在 `_save_dict()` 里**。持久 build 在 `persistent_equipped`,
##     战斗自己读的就是它(`RealtimeBattle3DScene:8105` / `dual_lane_flow._dl_spec_equips`)。
##     `tests/_cohort.gd:510` 三个月前就把这件事写在注释里了(「产出的 equipped 恒为空」),
##     所以它宁可自己重写一份快照生成 —— 而**生产侧没跟着改**。
##
## ⇒ 后果(2026-09-29 拿真机池 `user://ghost_pool.json` 量的):
##   非种子(真人上传)快照 **30/30** 两个字段全空; 396 条内置种子**一条都不空**
##   (种子走 `make_bot` / `_cohort._snapshot_of`, 它们**自己从阵容算分路**, 不读这两个字段)
##   ⇒ 坏的只有"上传"这一步。
##   消费侧 `RealtimeBattle3DScene._dual_foe_lane()` 拿到「0 统领 + N 小将」照样进分支,
##   `_foe_normalize_lane()` 把每路补到 3 个小将 ⇒ **对手上场 6 个小将、一个统领都没有、全裸**。
##   (真机实测的两种形状: `minions` 1/2 ⇒ 两路各补到 3; `minions` 0/3 ⇒ 上路连小将都没有,
##    那一路整条掉到写死的 bot 池。)
##
## ★形状不是我新定的 —— 照 `_cohort.gd:_snapshot_of()` 与 `make_bot()` 抄同一套,
##   而那正是 `_dual_foe_lane()` 期望的那套:
##     `lane_assign` = {"top": [pet_id…], "bottom": […]}          纯 id 串
##     `minions`     = {"top": [{role, elite, equips?}…], …}
##     `equipped`    = {pet_id: [{id, star}…]}                    只收本快照这几只
static func build_ghost_snapshot(ghost_id: String, profile: Dictionary) -> Dictionary:
	## ★走 `get_dual_lineup()` 而不是裸读 `dual_lineup`: 它会按 `slot` 把统领 id 回填成
	##   `season_leaders[slot]`(幂等), 结构不合法时重置成默认阵 —— 背包/战斗两侧读的都是它。
	var dl: Dictionary = {}
	if GameState != null and GameState.has_method("get_dual_lineup"):
		var _dl = GameState.get_dual_lineup()
		if _dl is Dictionary:
			dl = _dl
	var lane_assign := {"top": [], "bottom": []}
	# 小将(dual_lineup)配置+装备也存进快照(用户2026-07-18"快照里小将也应该有装备")→对手小将不再裸装
	var minions := {"top": [], "bottom": []}
	for lk in ["top", "bottom"]:
		var arr: Array = dl.get(lk, []) if dl.get(lk) is Array else []
		## ★精英判据与战斗侧**逐字相同**(`battle_spawn._spawn_lane_side`:「该路 0 统领 ⇒ 首个小将精英」)。
		##   所以先数一遍这一路真有几个统领, 再走第二遍。
		var lead_n := 0
		for uu in arr:
			if not (uu is Dictionary):
				continue
			if str((uu as Dictionary).get("kind", "")) != "leader":
				continue
			if str((uu as Dictionary).get("id", "")) != "":
				lead_n += 1
		var m_seen := 0
		for uu in arr:
			if not (uu is Dictionary):
				continue
			var ud: Dictionary = uu
			if str(ud.get("kind", "")) == "leader":
				## ★空 id = 大轮还没选统领时的占位(`_resolve_leader_slots` 填的 "")。
				##   传上去会让对手场上多一只 id="" 的龟 ⇒ 跳过, 让 normalize 补小将。
				if str(ud.get("id", "")) != "":
					(lane_assign[lk] as Array).append(str(ud.get("id", "")))
			else:
				var m := {"role": str(ud.get("role", "front")),
					"elite": (lead_n == 0 and m_seen == 0)}
				var meq = ud.get("equips", null)
				if meq is Array and not (meq as Array).is_empty():
					m["equips"] = (meq as Array).duplicate(true)
				(minions[lk] as Array).append(m)
				m_seen += 1
	## ★统领名单与分路**同源**。原来读 `GameState.left_team`, 而它只在【赢了】那支分支里
	##   才被回填(`RealtimeBattle3DScene:7623` 就在 `if won:` 里面) ⇒ 输的那局传上去的快照
	##   `leaders` 可能是空的, 而 `remote_pool.snapshot_valid` 以「leaders 不是 1~3 只」
	##   把它整条**静默**拒掉。分路里那几只就是这一场真正上场的, 用它。
	var leaders: Array = []
	for lk in ["top", "bottom"]:
		for pid in (lane_assign[lk] as Array):
			if not leaders.has(str(pid)):
				leaders.append(str(pid))
	if leaders.is_empty() and GameState != null and GameState.left_team is Array:
		leaders = (GameState.left_team as Array).duplicate()   # 兜底: 阵容一次都没排过
	var equipped := {}
	var levels := {}
	## ★★2026-09-17 补上一直是空的技能选择(U10)。
	##   消费侧一直活着: `RealtimeBattle3DScene.gd:5192` 读 `GameState.foe_loadouts[id]` 决定
	##   **敌方龟用哪个技能**, 注释写着「敌侧: ghost快照的技能选择(用户 2026-07-15 ghost带技能)」;
	##   而生产侧这里原本写死 `"loadouts": {}`, 全仓 0 处补写 ⇒ **打到的鬼影永远用 idx=1 签名技**
	##   (`:5183` `var idx := 1`), 一个用户要过的功能静默失效了两个月。
	## ★只收这份快照里真有的那几只 —— 不把玩家对别的龟的选择一起传上云(同 `levels` 的口径)。
	var lo_out := {}
	var pe: Dictionary = {}
	if GameState != null and GameState.persistent_equipped is Dictionary:
		pe = GameState.persistent_equipped
	for pid in leaders:
		var p := str(pid)
		var eqs = pe.get(p, [])            # 统领装备的**持久** build(小将的在 dual_lineup 里, 上面已收)
		if eqs is Array and not (eqs as Array).is_empty():
			equipped[p] = (eqs as Array).duplicate(true)
		levels[p] = GameState.get_pet_level(p)
		var _lo = GameState.loadouts.get(p, null) if GameState.loadouts is Dictionary else null
		if _lo is int or _lo is float:
			lo_out[p] = int(_lo)
	## ★玩家 ID(2026-10-04): 快照自带我的号, 对手卡片 / 排行榜直接读它(`profile_tag`)。
	##   调用方给了就不覆盖(门禁 / 教程会自己造 profile)。
	var prof_out: Dictionary = profile.duplicate()
	if not prof_out.has("tag"):
		prof_out["tag"] = my_tag()
	return {
		## ★schema 1 → 2(2026-08-15, 用户拍板 A): 快照开始带【宝箱进度】。
		##   老快照没有这两个字段, 而敌方宝箱龟要靠它决定开几件 ——
		##   不做向后兼容, 直接升版本号, 载入时把 <2 的整批丢掉(见 `SCHEMA_VER` / `load_pool`)。
		"schema_ver": SCHEMA_VER,
		"ghost_id": ghost_id,
		"is_bot": false,
		## ★★★2026-09-26 原来这里有个 `"bracket": bracket_for_battles(…)` 字段, 已删。
		##   它是 `season_total_battles`(就在下面几行)的**有损镜像** —— 同一个量存两份,
		##   而分桶用镜像、匹配用原件 ⇒ 必然漂。现在只留原件, 分桶也读原件。
		"profile": prof_out,
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": lo_out,
		"equipped": equipped,
		"pet_levels": levels,
		## ★★★2026-09-29 第三个漏掉的字段: 训龟大师装配的那个技能。
		##   消费侧 `battle_spawn.gd:575` 读 `dual_ghost.trainer_skill` 决定**敌方大师**用什么,
		##   取不到就回落 `"hook"`(钩锁) —— 那一段 2026-07-27 的注释写着
		##   「原来恒为 hook…玩家能选七种, 对手永远只会钩锁, 是系统性不对称」,
		##   而**它当时只接上了队列模拟那一侧**(`_cohort._snapshot_of` 写了 `trainer_skill`),
		##   玩家上传这一侧一直没写 ⇒ 打真人对手时大师又退回只会钩锁。
		##   (同一个形状在本文件出现过第三次: `loadouts` 09-17、分路/装备今天、这一条。
		##    判据都一样 —— 消费侧在读, 生产侧没写。)
		"trainer_skill": str(GameState.trainer_skill) if GameState != null else "",
		"season_total_battles": int(GameState.season_total_battles),
		"season_eggs_killed": int(GameState.season_eggs_killed),
		## ★★A8(2026-09-19) 终榜三键。排序换成字典序「胜场 → 余命 → 横扫」,
		##   原来只比 `season_eggs_killed`(碎蛋数)。三个都要带, 否则榜上排不出先后。
		##   ⚠ 旧快照没有这三个字段 ⇒ 读的时候一律 `get(..., 0)` 兜底, **不作废旧池**。
		"season_wins": int(GameState.season_wins),
		"hearts": int(GameState.hearts),
		"season_sweeps": int(GameState.season_sweeps),
		## ★宝箱进度(用户 2026-08-14 查清后拍板 A)。
		##   查清楚的事实: 敌方 = 真人玩家的 ghost 快照, 带了龟/装备/等级, **唯独宝箱战利品一件不带**,
		##   代码却用「单场 590 伤害开满 5 件」去补偿 —— 对面那只宝箱龟凭空多出五件传说。
		##   现在带上真实进度, 敌方按对手【真的攒到哪】开箱。
		"chest_treasures_won": (GameState.chest_treasures_won as Array).duplicate() if GameState.chest_treasures_won is Array else [],
		"chest_treasure_value": float(GameState.chest_treasure_value),
	}
