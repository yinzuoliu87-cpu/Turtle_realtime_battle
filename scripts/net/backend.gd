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
static var match_src_counts: Dictionary = {"exact": 0, "bucket": 0, "bot": 0}
static func _tally(src: String) -> void:
	match_src_counts[src] = int(match_src_counts.get(src, 0)) + 1
const _P2 = preload("res://scripts/gamedata/phase2_config.gd")

# ─── 进度档 (设计§十三): 总战斗数 → 匹配档 0-8. 低档窄(对齐槽断点)/高档宽(保池子有人) ───
## ★2026-07-27 用户拍板: 档0 严格 = 【人生第一把】(total==0), 后面各档整体顺延一格。
##   起因: 原来 total<=1 让档0 同时装下两种人 —— 打过 0 场的(一分钱没有·全裸) 和
##   打过 1 场的(已逛过一次商店·约 6 件)。于是「档0 无装备」这条锚点与档0 的真实人口自相矛盾
##   (队列模拟直接暴露: 档0 快照平均 7.5 件装备)。
##   现在档0 只有真·第一把的人, 双方全裸 = 纯阵容/技能对决。各档宽度不变, 只是断点 -1。
## ★2026-07-27 二次调整(用户选「微调B」): 把高档间距拉近, 让档7/8 变成【真有人到得了】的档位。
##   起因(概率+实测双证): 8 条命 + 50% 胜率下, 打满 N 场的概率 = P(前 N-1 场里输 ≤7 次)。
##   旧断点(档7=30场 / 档8=40场) 下 1000 个玩家里只有 4 人到档7、0 人到档8 ——
##   档8 要约 28000 个玩家才期望出现 1 个, 而每档池子能装 50 支队。
##   首轮 32 只队列实测印证: 最远只打到第 29 场, 档7/8 产出快照 0 条。
##   新断点(档7=22场 / 档8=28场) → 1000 人里档7 有 95 人、档8 有 9.6 人, 池子填得起来。
##   (备选: 轻=24/31 档8仅2.6人; 再近些=20/25 档8 32人。用户取中档。)
static func bracket_for_battles(total: int) -> int:
	if total <= 0: return 0
	if total <= 2: return 1
	if total <= 4: return 2
	if total <= 7: return 3
	if total <= 11: return 4
	if total <= 16: return 5
	if total <= 21: return 6
	if total <= 27: return 7
	return 8

## 某档"代表总战斗数"(给 bot 配槽位/等级; 取档上界). 大致反 bracket_for_battles.
static func battles_for_bracket(bracket: int) -> int:
	match bracket:      # 与 bracket_for_battles 互逆(取档上界); 2026-07-27 随「微调B」同步
		0: return 0
		1: return 2
		2: return 4
		3: return 7
		4: return 11
		5: return 16
		6: return 21
		7: return 27
		_: return 33

# ─── ghost 池 (内存 Dictionary, 结构 {brackets:{"档":[snapshot...]}}) ───
## 把 snapshot 加进对应档桶 (新的在前, 封顶挤旧).
static func pool_add(pool: Dictionary, snapshot: Dictionary) -> void:
	if not pool.has("brackets"):
		pool["brackets"] = {}
	var b := str(int(snapshot.get("bracket", 0)))
	if not pool["brackets"].has(b):
		pool["brackets"][b] = []
	var bucket: Array = pool["brackets"][b]
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

## 从池抽一个同档对手 (排除 exclude_ids). 桶空/全排除 → null (调用方 make_bot 兜底).
## ★A6 新参数 `exact_battles`: >=0 时只要【场数完全相同】的那些, 一个都没有就返回 null
##   (回落交给调用方 `find_opponent`, 那里要按 精确→同桶→bot 逐级记账)。
## ★**必须带默认值** —— 本函数有 10 处调用(产品 1 / 门禁 5 / 探针 4), 不带默认值会一起炸。
##   ⚠ 但带了默认值就意味着**老门禁全绿却一条新行为都没验到** ⇒ A6 自带新门禁
##   `tests/verify_exact_match.gd`, 不靠"现有门禁没红"当作没问题。
## ★★「倒序取最新」不需要时间戳字段: `pool_add` 用的是 `bucket.push_front(snapshot)`,
##   **桶本身就是上传倒序(新的在前)** ⇒ 按桶序取第一个命中的, 就是最新那份。
##   (我差点去给快照加一个 upload_ts 字段 —— 读了 pool_add 才发现现成的。)
static func pool_find(pool: Dictionary, bracket: int, exclude_ids: Array, rng: RandomNumberGenerator,
		exact_battles: int = -1):
	var brackets: Dictionary = pool.get("brackets", {})
	var b := str(bracket)
	if not brackets.has(b):
		return null
	var candidates: Array = []
	for g in brackets[b]:
		if _is_self_ghost(g): continue
		if not exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
			candidates.append(g)      # ★保持桶序 = 上传倒序
	if candidates.is_empty():
		return null
	if exact_battles >= 0:
		for g in candidates:
			if int((g as Dictionary).get("season_total_battles", -1)) == exact_battles:
				return g               # 桶序里第一个命中 = 同场次里最新的那份(D10)
		return null
	return candidates[rng.randi() % candidates.size()]

# ─── bot 生成 (池空/冷启动兜底 = 永久安全网, 设计§十三) ───
## 按档配资源(槽位/等级)随机一支队. rng 决定随机 → 确定可测. is_bot=true.
static func make_bot(bracket: int, rng: RandomNumberGenerator) -> Dictionary:
	var battles := battles_for_bracket(bracket)
	var bot_lv := clampi(2 + bracket, 1, 10)   # 档越高 bot 等级越高
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
		levels[pid] = bot_lv
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
	return {
		"schema_ver": SCHEMA_VER,
		"ghost_id": "bot_%d_%d" % [bracket, rng.randi() % 1000000],
		"is_bot": true,
		"bracket": bracket,
		"profile": {"name": "海域守卫", "avatar": str(leaders[0]) if leaders.size() > 0 else "basic", "id": "BOT"},
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": {},
		"equipped": equipped,
		"pet_levels": levels,
		"season_total_battles": battles,
		"season_eggs_killed": 0,
	}

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
static func leaderboard(pool: Dictionary, self_name: String, self_wins: int, self_hearts: int,
		self_sweeps: int, limit: int) -> Array:
	var rows: Array = [{"name": self_name, "wins": self_wins, "hearts": self_hearts,
		"sweeps": self_sweeps, "is_self": true}]
	var brackets: Dictionary = pool.get("brackets", {})
	for b in brackets.keys():
		for g in brackets[b]:
			var gd := g as Dictionary
			rows.append({
				"name": str(gd.get("profile", {}).get("name", "?")),
				"wins": int(gd.get("season_wins", 0)),
				"hearts": int(gd.get("hearts", 0)),
				"sweeps": int(gd.get("season_sweeps", 0)),
				"is_self": false})
	## ★字典序: 前一键相等才看后一键。写成「先比胜场, 相等再比余命, 再相等才比横扫」。
	rows.sort_custom(func(a, c):
		if int(a["wins"]) != int(c["wins"]):
			return int(a["wins"]) > int(c["wins"])
		if int(a["hearts"]) != int(c["hearts"]):
			return int(a["hearts"]) > int(c["hearts"])
		return int(a["sweeps"]) > int(c["sweeps"]))
	return rows.slice(0, limit) if rows.size() > limit else rows

# ─── 文件 I/O (薄包装, user://ghost_pool.json) ───
static func load_pool(path: String = POOL_PATH) -> Dictionary:
	var pool: Dictionary = {"brackets": {}}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text(); f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				pool = parsed
	if not pool.has("brackets"):
		pool["brackets"] = {}
	_drop_stale_schema(pool)   # ★老版本快照整批丢掉(用户 2026-08-14 拍板 A: 不做向后兼容)
	_ensure_seeded(pool)   # 冷启动/老档无种子 → 并入内置策划队(幂等, 已并过不重复); 下次 upload_ghost 落盘
	return pool


## 丢掉 schema_ver < SCHEMA_VER 的快照。
##
## ★为什么不做向后兼容(用户 2026-08-14 原话:「直接全部老快照全消除掉, A, 重新制作新快照」):
##   老快照缺 `chest_treasures_won` —— 兼容就意味着"缺字段时假装对手没开过箱",
##   那还是在编一个假的对手, 只是换了个假法。宁可池子空一阵。
## ★丢多少要【打印出来】, 不许静默(CLAUDE.md: 无声上限 = 假装覆盖全了)。
static func _drop_stale_schema(pool: Dictionary) -> int:
	var brackets: Dictionary = pool.get("brackets", {})
	var dropped := 0
	for b in brackets.keys():
		var arr: Array = brackets[b]
		var keep: Array = []
		for g in arr:
			if g is Dictionary and int((g as Dictionary).get("schema_ver", 0)) >= SCHEMA_VER:
				keep.append(g)
			else:
				dropped += 1
		brackets[b] = keep
	if dropped > 0:
		print("[Backend] 丢弃 %d 条老版本快照(schema < %d) —— 池子会先空一阵, 遇到的都是 bot" % [dropped, SCHEMA_VER])
	return dropped

## 内置种子池 (res:// 只读, 导出包里也在). 解析失败=空.
static func _load_seed() -> Dictionary:
	if not FileAccess.file_exists(SEED_PATH):
		return {"brackets": {}}
	var f := FileAccess.open(SEED_PATH, FileAccess.READ)
	if f == null:
		return {"brackets": {}}
	var parsed = JSON.parse_string(f.get_as_text()); f.close()
	if parsed is Dictionary and (parsed as Dictionary).has("brackets"):
		return parsed
	return {"brackets": {}}

const SEED_VER := 11  # ★2026-09-03 v11: 800 只机器人 × 14 个流派全量重跑(12718 条候选→184 支)。
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
	var brackets: Dictionary = pool.get("brackets", {})
	var have_seed := false
	for b in brackets.keys():
		for g in brackets[b]:
			if str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				have_seed = true
				break
		if have_seed: break
	if have_seed and int(pool.get("_seed_ver", 0)) >= SEED_VER:
		return
	for b in brackets.keys():                       # 清旧版seed_(玩家真ghost保留)
		var keep: Array = []
		for g in brackets[b]:
			if not str((g as Dictionary).get("ghost_id", "")).begins_with("seed_"):
				keep.append(g)
		brackets[b] = keep
	var seed := _load_seed()
	for b in seed.get("brackets", {}).keys():
		for g in seed["brackets"][b]:
			pool_add(pool, g)
	pool["_seed_ver"] = SEED_VER
	save_pool(pool)                                 # 升级立即落盘(否则要等下次upload才存)

## ★headless(测试/仿真/导出) 绝不写玩家真实池 —— 与 GameState.test_mode 同一条纪律(GameState.gd:570)。
## 起因(2026-07-27): GameState.save() 早有这个守卫, save_pool 一直没有 → 任何跑战斗的测试赢一把就
## upload_ghost 污染 user://ghost_pool.json; 更隐蔽的是 load_pool→_ensure_seeded→save_pool(L211),
## 【光是读池就会写盘】。存档目录里那个 savegame.json.bak-被测试污染 就是同类事故的遗迹。
## 只挡默认的 user:// 真实池; 显式传 path(自举仿真/离线产池) 照写不误。
static func save_pool(pool: Dictionary, path: String = POOL_PATH) -> void:
	if path == POOL_PATH and GameState != null and bool(GameState.test_mode):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(pool, "  ")); f.close()

# ─── 高层 orchestration (gameplay 调这俩) ───
## 在 [lo,hi] 档窗口内汇总所有候选(排除exclude)随机抽一个. 空→null.
static func pool_find_window(pool: Dictionary, lo: int, hi: int, exclude_ids: Array, rng: RandomNumberGenerator):
	var brackets: Dictionary = pool.get("brackets", {})
	var candidates: Array = []
	for bi in range(maxi(0, lo), hi + 1):
		var b := str(bi)
		if not brackets.has(b):
			continue
		for g in brackets[b]:
			if _is_self_ghost(g): continue   # 跳过自己上传的快照(防撞自己·新旧id一网打尽)
			if not exclude_ids.has(str((g as Dictionary).get("ghost_id", ""))):
				candidates.append(g)
	if candidates.is_empty():
		return null
	return candidates[rng.randi() % candidates.size()]

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

## 抽对手: 同档 ghost, 没有就 bot. 永远返回一个可打的对手 (永久安全网).
##
## ★2026-07-27 用户「±1 这东西去掉」: 改回【只抽本档, 空了只往【低】档回落, 绝不往上】。
##   废掉的是 2026-07-18 的 [档-1, 档+1] 窗口 —— 它当初是为了治"匹配多了总撞同一阵容"
##   (那时单档只~7 支种子)。但自动玩家 30 把实测它的代价远大于收益:
##     · 第 2 把(档0·自己 0 件装备) 撞到档1 带 3 件的队
##     · 第 7 把 我方强度 43.0 撞到 99.0 (2.3 倍)
##     · 第 10 把 45.8 撞到 118.6 (2.6 倍)
##   而多样性问题现在已不成立: 种子池 146 支, 单档 12~20 支, 再排除最近 3 个 → 9~17 个候选够用。
##   ★不许往上回落是硬约束: "档N 的玩家绝不该遇到 >N 档的对手"(verify_bracket_gear 新增断言守这条)。
static func find_opponent(bracket: int, exclude_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	## ★远端同步(方案书 §落地步骤 3): 顺手发一次拉取, 但**它给的是【下一局】的池子** ——
	##   本局的对手就在下面几行用现在这个 pool 算出来, 一步都不等网络。
	##   这是"离线不退化"这条硬指标的落点: 断网时这一行是 no-op, 下面照常跑。
	##   (verify_remote_pool 用真 HTTPRequest 打不可达地址量过: 匹配耗时 8ms ≪ 超时 6000ms。)
	var RP = load("res://scripts/net/remote_pool.gd")
	if RP != null:
		RP.pull_async(bracket)
	## ★★A6 回落顺序(D10): 精确同场次 → 同桶其它人 → 机器人, **每一级都记账**。
	##   记账不是为了好看 —— A-R3「精确同场次命中率多低算太低」这条未决点,
	##   没有这个数就永远答不了。
	var my_battles := int(GameState.season_total_battles) if GameState != null else -1
	## ★★D-4b(2026-09-21): 同一时刻也向 Supabase 拉一次【同周 + 同场次】的对手。
	##   两条路**暂时并存**: 旧层走旧后端协议(`backend_url` 是空的 ⇒ 它是 no-op),
	##   新层走 Supabase REST。同样是【填下一局】的池子, 一步不等网络。
	## ★场次直接用下面选靶用的 `my_battles` **同一个变量** —— 不是两处各读一次。
	##   这是「传上去的和拉回来的对不上」那类静默 bug 唯一可靠的防法:
	##   只要有一维取的不是同一个量, 池子就永远是空的而没任何报错。
	var SB = load("res://scripts/net/supabase.gd")
	if SB != null and GameState != null:
		SB.pull_opponents_async(int(GameState.week_anchor_ts), my_battles,
			str(GameState.account_id))
	## ① 精确同场次(本档优先, 再就近低档)
	if my_battles >= 0:
		for b in range(bracket, -1, -1):
			var ge = pool_find(pool, b, exclude_ids, rng, my_battles)
			if ge != null:
				_tally("exact")
				return ge
	## ② 同桶其它人(老行为)
	for b in range(bracket, -1, -1):
		var g = pool_find(pool, b, exclude_ids, rng)
		if g != null:
			_tally("bucket")
			return g
	## ③ 机器人(永久安全网)
	_tally("bot")
	return make_bot(bracket, rng)


## ★★E-A4(2026-09-22) 周六闯关赛的匹配 —— 与上面那条**是两套**, 不是加个参数。
##
## 原稿逐字:「只有战绩标签完全相同者互配(3-1 只碰 3-1)。同标签 ⟹ 同场数 ⟹
##   周六内供给完全一致; 兜底链: 同标签真人排队 → 同标签新鲜快照(30 分钟内)→ 机器人。
##   **永不跨标签**」。
##
## ★与积分赛那条的三处**有意不同**, 每处都有理由:
##   ① 积分赛允许 `battles=in.(N, N+1)` 差一场(池子薄时的让步);
##      闯关赛**完全相等** —— 放宽一格就是让 3-1 打 3-2, 两人经济供给差一整场,
##      而"同战绩的人互相淘汰"正是这个赛制的全部意义。
##   ② 积分赛的新鲜度是**排序**(D10: 池子薄, 卡时间窗会经常凑不出人);
##      闯关赛的 30 分钟是**过滤**(U3b: 淘汰赛宁可等、宁可打机器人, 也不要打一份隔夜快照)。
##   ③ 回落**不降标签**, 只降到机器人 —— 上面那条会 `for b in range(bracket, -1, -1)`
##      往低档找, 这里一格都不许降。
##
## ⚠ 本函数**一行网络代码都没有**(与 `find_opponent` 同一条纪律): 顺手发一次拉取填
##   【下一局】的池子, 本局就用现在这个本地池算。断网时那一行是 no-op, 下面照常跑。
static func find_gauntlet_opponent(gw: int, gl: int, exclude_ids: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var pool := load_pool()
	if GameState != null:
		var SB2 = load("res://scripts/net/supabase.gd")
		if SB2 != null:
			SB2.pull_gauntlet_async(int(GameState.week_anchor_ts), gw, gl,
				str(GameState.account_id))
	## ① 同标签的新鲜快照。**一格都不降**。
	var ge = gauntlet_pool_find(pool, gw, gl, exclude_ids, rng)
	if ge != null:
		_tally("gauntlet_label")
		return ge
	## ② 机器人(永久安全网)。★记成**另一个**计数, 不与积分赛的 bot 混在一起 ——
	##    「周六有多少场是打机器人的」是 R2 那条风险唯一能回答的数字。
	_tally("gauntlet_bot")
	return make_bot(bracket_for_battles(gw + gl), rng)


## 周六打完一场 → 产出一份**带战绩标签**的快照, 入本地池并传云端。
##
## ★★标签取的是**打完之后**的战绩: 下一场要找的是"跟我现在同样几胜几负"的人。
##   传打之前那个标签, 等于把自己挂在**上一格**上 —— 别人按新标签找永远找不到我,
##   而这件事**不会报任何错**, 只会表现成"周六老是匹配到机器人"。
## ★三个 `gl_*` 字段是匹配层唯一的依据(`gauntlet_pool_find` 读它们)。
##   ghost_id 也要带标签, 否则 `pool_add` 按 id 去重会让同一个人只剩最新一格
##   —— 那正是 A6 给积分赛 id 加"场次"那一维的同一个理由。
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
	upload_ghost(snap)                 ## 老通道: 进本地池(+ 旧后端, 现在是 no-op)
	var SB3 = load("res://scripts/net/supabase.gd")
	if SB3 != null:
		var row: Dictionary = SB3.gauntlet_row_from_snapshot(
			snap, str(GameState.account_id), int(GameState.week_anchor_ts),
			gw, gl, str(ProjectSettings.get_setting("application/config/version", "")))
		SB3.upload_gauntlet_async(row)


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


## E-B6: 把决赛日某一场的结果报上去。
## ★与 `report_finals_entry` 同一层、同一形状：**周号从 GameState 取**，
##   战斗场那边只负责说「哪个桶、第几轮、第几场、哪一侧赢」——
##   在主场景里再拼一次 `week_anchor_ts` 就是同一判据存两份。
## ★`winner_side` 已经由 `BracketMapScene.winner_side_for()` 算好，这里不重算。
static func report_finals_result(bucket: int, round_no: int,
		match_no: int, winner_side: int) -> void:
	if GameState == null or bucket < 0 or round_no < 1 or match_no < 0:
		return
	var SB5 = load("res://scripts/net/supabase.gd")
	if SB5 == null:
		return
	## `p_seed` = 确定性重算用的种子（B 阶段第二步服务端复算要用）。
	## ★用 `GameState.battle_seed` —— 它是**真实存在**的那个字段。
	##   我第一版写了 `last_battle_seed`，全仓**只有我那两行**在用（凭空编的字段名，
	##   本仓踩过三次，见 [[fb-gate-subject-never-constructed]]）。
	## ★0 的含义是「这一场没留下可复算的种子」（没设 TURTLE_SEED 时就是 0），
	##   不是出错 —— 服务端那边 `coalesce(p_seed, 0)` 本来就收 0。
	var sd := int(GameState.battle_seed)
	SB5.report_finals_async(int(GameState.week_anchor_ts), bucket, round_no,
		match_no, winner_side, sd)


## 玩家显示名 —— **全仓唯一出处**。有昵称用昵称, 没有用确定性兜底短码。
## ★昵称在**绑定邮箱**那一屏与邮箱同时填(用户 2026-09-24「这个在创建账号应该一起吧」)——
##   那是玩家唯一感知得到的「创建账号」时刻: 首启建匿名号是**静默**的, 没有任何界面。
## ★没绑邮箱的匿名号用兜底短码, 不强制 —— 规则与文案都在 `phase2_config` 那一节。
static func player_display_name() -> String:
	if GameState == null:
		return "?"
	return _P2.display_name(str(GameState.nickname), str(GameState.account_id))


## 在本地池里找【同标签且新鲜】的一份快照。找不到返回 null(回落交给上面那个函数)。
## ★新鲜度用快照自带的 `gl_ts`(上传时刻), 缺这个字段的一律当**不新鲜**排除 ——
##   老快照没有这一维, 把它当新鲜就等于"永不过期", 那条 30 分钟规则会静默失效。
static func gauntlet_pool_find(pool: Dictionary, gw: int, gl: int,
		exclude_ids: Array, rng: RandomNumberGenerator):
	var now: int = int(Time.get_unix_time_from_system())
	var cands: Array = []
	for gid in pool.keys():
		var g = pool[gid]
		if not (g is Dictionary):
			continue
		if str(gid).begins_with(self_prefix(int(GameState.season_id) if GameState != null else 0)):
			continue                      # 自己(含同赛季换过龟的旧阵容)
		if exclude_ids.has(gid):
			continue
		if int(g.get("gl_w", -1)) != gw or int(g.get("gl_l", -1)) != gl:
			continue                      # ★标签必须完全相同
		var ts: int = int(g.get("gl_ts", 0))
		## ★30 分钟窗口是【过滤】不是排序(与积分赛 D10 相反)。
		## ★★缺字段的不用单独判: 缺了就是 0, 而 `now - 0` 本来就远超窗口。
		##   我第一版写了 `ts <= 0 or ...`, **反向验证打不红** ——
		##   那一半是装饰。真正没人守的是**未来时间戳**:
		##   `now - ts` 为负 ⇒ 比任何阀值都小 ⇒ 当成新鲜的永不过期。
		##   (设备时钟走快、或者有人改过那一行, 都会造出这种行。)
		if ts > now or now - ts > int(_P2.FRESH_SNAPSHOT_SEC):
			continue
		cands.append(gid)
	if cands.is_empty():
		return null
	cands.sort()                          # 先定序, 再按种子抽 —— 不然同种子两次结果不同
	return pool[cands[rng.randi() % cands.size()]]

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
static func upload_ghost(snapshot: Dictionary) -> void:
	var mine := snapshot.duplicate(true)
	mine[ORIGIN_KEY] = ORIGIN_LOCAL
	var pool := load_pool()
	pool_add(pool, mine)
	save_pool(pool)
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
	var SB = load("res://scripts/net/supabase.gd")
	if SB != null:
		var row: Dictionary = SB.ghost_row_from_snapshot(
			snapshot,
			str(GameState.account_id),
			int(GameState.week_anchor_ts),
			int(snapshot.get("season_total_battles", -1)),
			str(ProjectSettings.get_setting("application/config/version", "")))
		SB.upload_ghost_async(row)      # row 为空(缺身份/缺场次) 时它自己 return

## 从玩家刚打的这局 (left 侧) 序列化成 ghost 快照 (上传自己用). ghost_id/profile 调用方给.
static func build_ghost_snapshot(ghost_id: String, profile: Dictionary) -> Dictionary:
	var leaders: Array = GameState.left_team.duplicate() if GameState.left_team is Array else []
	var lane_assign: Dictionary = GameState.lane_assign.duplicate(true) if GameState.lane_assign is Dictionary else {}
	var equipped := {}
	var levels := {}
	## ★★2026-09-17 补上一直是空的技能选择(U10)。
	##   消费侧一直活着: `RealtimeBattle3DScene.gd:5192` 读 `GameState.foe_loadouts[id]` 决定
	##   **敌方龟用哪个技能**, 注释写着「敌侧: ghost快照的技能选择(用户 2026-07-15 ghost带技能)」;
	##   而生产侧这里原本写死 `"loadouts": {}`, 全仓 0 处补写 ⇒ **打到的鬼影永远用 idx=1 签名技**
	##   (`:5183` `var idx := 1`), 一个用户要过的功能静默失效了两个月。
	## ★只收这份快照里真有的那几只 —— 不把玩家对别的龟的选择一起传上云(同 `levels` 的口径)。
	var lo_out := {}
	for pid in leaders:
		var p := str(pid)
		var eqs: Array = GameState.equipped_p2.get(p, [])   # left 侧裸 pet_id (无 right:: 前缀)
		if not eqs.is_empty():
			equipped[p] = eqs.duplicate(true)
		levels[p] = GameState.get_pet_level(p)
		var _lo = GameState.loadouts.get(p, null) if GameState.loadouts is Dictionary else null
		if _lo is int or _lo is float:
			lo_out[p] = int(_lo)
	# 小将(dual_lineup)配置+装备也存进快照(用户2026-07-18"快照里小将也应该有装备")→对手小将不再裸装
	var minions := {}
	if GameState.dual_lineup is Dictionary:
		for lk in ["top", "bottom"]:
			var arr: Array = (GameState.dual_lineup as Dictionary).get(lk, [])
			var mlist: Array = []
			for uu in arr:
				if uu is Dictionary and str((uu as Dictionary).get("kind", "")) == "minion":
					var m := {"role": str((uu as Dictionary).get("role", "front")), "elite": bool((uu as Dictionary).get("elite", false))}
					var meq = (uu as Dictionary).get("equips", null)
					if meq is Array and not (meq as Array).is_empty():
						m["equips"] = (meq as Array).duplicate(true)
					mlist.append(m)
			minions[lk] = mlist
	return {
		## ★schema 1 → 2(2026-08-15, 用户拍板 A): 快照开始带【宝箱进度】。
		##   老快照没有这两个字段, 而敌方宝箱龟要靠它决定开几件 ——
		##   不做向后兼容, 直接升版本号, 载入时把 <2 的整批丢掉(见 `SCHEMA_VER` / `load_pool`)。
		"schema_ver": SCHEMA_VER,
		"ghost_id": ghost_id,
		"is_bot": false,
		"bracket": bracket_for_battles(int(GameState.season_total_battles)),
		"profile": profile,
		"leaders": leaders,
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": lo_out,
		"equipped": equipped,
		"pet_levels": levels,
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
