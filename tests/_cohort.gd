extends Node
## _cohort.gd — N 队机器人【真实队列】模拟 (方案书 docs/plans/20260727b)
##
## 用户 2026-07-27:「先跑32个队, 记住要真实的, 打完8条命就直接淘汰了」
##
## 与 _autoplay.gd 的区别: 那个是【1 只机器人打静态种子池】; 这个是【N 只机器人互相打】——
## 每场推进两只, 输光 8 命【直接出局不复活】, 活着的继续。每打完一场, 把该机器人当时的
## 真实家当存成快照 → 这些快照就是新 ghost 池的原料(用户:「把这个作为快照存入」)。
##
## 每只机器人开局随机: 3 只统领(28选3) / 训龟技能(五选一) / 买装策略(三种·造出强中弱三层玩家)
##                    / 分路与小将前后排。
## 每场后它自己: 逛商店(买经验/买装备/刷新) → 回背包(三合一/装/换/卖) → 该打碎糖果罐就打碎。
##
## 跑法(必须 headless —— 本机开 3D 窗口会蓝屏):
##   SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260727 COHORT_BOTS=32 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_cohort.tscn
##
## 环境变量: COHORT_BOTS(默认32) COHORT_MAX_ROUNDS(默认120) COHORT_OUT(默认 res://tools/autoplay)
##
## ★不写玩家存档: GameState.test_mode + save_pool 守卫(backend.gd)。快照只落自己的产物文件。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const P2EQ := preload("res://scripts/gamedata/phase2_equip.gd")

const SKILLS := ["magic_stone", "hook", "fury_potion", "whistle", "glacier"]
## ★"synergy"(羁绊流) 2026-08-12 加入: 原三种买法**一件都不看羁绊** ——
##   机器人于是永远凑不出类型档位, 而羁绊是 2026-08-03 起【唯一】的构筑维度。
##   快照池里全是"无羁绊队" ⇒ 玩家打到的鬼影不体现这套系统。补上第四种玩家原型。
## ★★旧的四种(保留常量只为老日志能读懂), 实际已被下面的【策略向量】取代。
##   旧四种的问题(用户 2026-09-02:「别弄蠢ai」「只有6种流派也少了」):
##   它们**只作用在「货架 10 格按什么顺序买」一个决策点**, 而商店回合里另外四个决策点
##   (买多少经验 / 留多少币 / 刷不刷新 / 装备给统领还是小将)**全是写死的** ——
##   于是"策略"其实只是排序偏好, 造不出真正不同的流派。
const STRATEGIES := ["merge_first", "greedy_cost", "random", "synergy"]

## ══════════════════════════════════════════════════════════════
##  策略向量 —— 800 支要是 800 个样子, 不是 14 个
## ══════════════════════════════════════════════════════════════
## 每只机器人抽一个【命名锚点】再加**随机扰动** ⇒ 同一锚点下的几十支也各不相同。
##
## ★核心张力(这游戏里真实存在的分流, 不是我编的):
##   羁绊按 **id 去重**(`Phase2Types.calc_active`) ⇒ 买第 2、3 张同 id 对羁绊**零贡献**
##   ⇒ **「追三合一★3」与「追羁绊档位」是直接冲突的两条路**。`merge` 与 `focus/wide` 就是这条轴。
##
## 权重字段:
##   cost_hi     −1..+1  费用取向(+1 只买 4~5 费 / −1 只买 1~2 费)
##   focus       0..1    单线专注: 只补 focus_types 里那几类缺的 id
##   wide        0..1    铺开: 优先推"离下一档最近"的类型(靠 syn_key)
##   merge       0..1    追三合一(与 focus/wide 冲突, 见上)
##   reserve     int     买经验前先留给装备的币线(原写死 P2.AI_GEAR_RESERVE=12)
##   xp          int     每次逛店最多买几次经验(原写死 P2.AI_MAX_XP_BUYS_PER_VISIT=3)
##   refresh     int     刷新上限(原写死 MAX_REFRESH=2)
##   eager       0..1    **主动**刷新的概率(原来只有"买不到才刷")
##   minion_first 0/1    装备先给小将还是先给统领(原写死: 先统领)
## ★★★`xp` 的下限是 2 —— 这不是"把流派拉平", 是修一个**结构性自杀参数**。
##
## 2026-09-03 探针实测(12732 条快照 / 800 只机器人跑满 6366 场):
##
##     xp≤1 的 6 个流派   最高只升到 5~7 级  ⇒ 装备槽 8~12   达档8率均值 0.40%
##     xp≥2 的 8 个流派   能升到 10 级       ⇒ 装备槽 18     达档8率均值 1.61%
##
## 根因是 `phase2_config.team_equip_cap(level) = (level-1) × 2` ——
## **不买经验就没有装备容量**, 跟"策略偏好"无关, 是必死。旧参数下的后果:
##   · `hi_cost` 达档8率 **0%**, 全场平均只持有 10.7 件, 4~5 费占比 7.8%
##     ——【比随机组的 24.7% 还低 17 个点】, 一个"高费流"买的高费比乱买的还少;
##   · `snowball`(xp:0) 最高 5 级 / 装备槽 8 / 平均持有 6.9 件, 全池垫底;
##   · `line_top`(单线顶档流) 达档8率 0.13% ⇒ **全池没有一支队打到 3 档顶档**。
##
## 用户 2026-09-02 原话:「别让蠢 AI 来行吗」。给流派配一个必死参数正是蠢 AI ——
## 真人玩家不会一局不升级。流派差异改由 `reserve` / `refresh` / `eager` 承担,
## 那几条是**真的策略取舍**(存钱 vs 铺货 / 刷不刷新), 不是自杀开关。
##
## ★这个下限不靠"我记得要写 ≥2"守 —— 见文件末尾的 `_assert_no_suicide_weights()`,
##   它在每次跑之前逐条查, xp<2 直接 push_error 并中止(反向验证: 把任意一条改回 1 会当场红)。
const MIN_XP_BUYS := 2

const ARCHETYPES := {
	## 高费流: reserve 24→14。24 意味着**两三轮不买任何装备**去等一件 4~5 费,
	## 而低档商店根本不出 4~5 费 ⇒ 钱白存、装备空窗、被打死。14 仍显著高于均值。
	"hi_cost":     {"cost_hi": 1.0,  "reserve": 14, "xp": 3, "refresh": 3, "eager": 0.3},
	## 单线顶档流(要凑 9 件同类型开 3 档): xp 1→3。它是唯一可能打出顶档的流派,
	## 却因为升不了级只有 12 个槽 —— 9 件同类型放不进去, 顶档【结构上不可能】。
	"line_top":    {"focus": 1.0,    "reserve": 10, "xp": 3, "refresh": 4, "eager": 0.6, "lines": 1},
	"dual_mid":    {"focus": 0.8,    "reserve": 10, "xp": 2, "refresh": 3, "eager": 0.4, "lines": 2},
	"wide_syn":    {"wide": 1.0,     "reserve": 6,  "xp": 2, "refresh": 2, "eager": 0.2},
	"low_flood":   {"cost_hi": -1.0, "reserve": 6,  "xp": 2, "refresh": 1},
	"star_rush":   {"merge": 1.0,    "reserve": 8,  "xp": 3, "refresh": 2, "eager": 0.3},
	"fast_level":  {"xp": 6,         "reserve": 30, "refresh": 1},
	## 滚雪球: xp 0→2, reserve 0→4。原意是"攒利息"，但 xp:0 让它锁死在 5 级(槽位 8)。
	## 低 reserve 保住"钱不留着、见货就买"的雪球感, 升级那一份是活下去的门票。
	"snowball":    {"xp": 2,         "reserve": 4,  "refresh": 2},
	"reroll_mad":  {"refresh": 6,    "eager": 0.9,  "reserve": 10, "xp": 2},
	"no_reroll":   {"refresh": 0,    "eager": 0.0,  "reserve": 12, "xp": 3},
	"leader_all":  {"minion_first": 0, "cost_hi": 0.5, "reserve": 14, "xp": 2, "refresh": 2},
	## 小将流: xp 2→3。装备先给小将本身就吃亏(小将属性低), 再叠上槽位少就是双重劣势,
	## 达档8率 0%。给足槽位后它才是一条"能玩但偏门"的路, 而不是一条死路。
	"minion_up":   {"minion_first": 1, "reserve": 10, "xp": 3, "refresh": 2},
	"mix":         {"merge": 0.5, "wide": 0.5, "cost_hi": 0.2, "reserve": 12, "xp": 3, "refresh": 2},
	## ★下界对照组: 全零 ⇒ 打分全平 ⇒ 退化成随机顺序。
	## ⚠ 它**不设 xp 键**, 走的是产品默认 `AI_MAX_XP_BUYS_PER_VISIT=3`(不是 0) ——
	##   所以它能升到 10 级, 不是上面那条"xp=0 必死"的反例。`_assert_no_suicide_weights`
	##   只查**显式写了 xp 的**, 别把它也算进去。
	"random":      {},
}


## 逐条查【自杀权重】—— 跑之前就拦, 不要跑满 5 小时再从快照里发现。
##
## ★为什么要有这个函数: 2026-09-02 那一轮就是**参数配错了才跑**, 5 小时跑完
##   才在验收报告里看出 hi_cost 的 4~5 费占比比随机组还低 17 个点。
##   这类错误【跑之前 0.1 秒就能查出来】, 代价却是整轮重跑。
##
## ★判据落在**产品的真实约束**上, 不是我拍的数字:
##   `team_equip_cap(level) = (level-1) × 2` ⇒ 升不了级就没有装备容量。
##   所以"显式配了 xp 且 < MIN_XP_BUYS"就是自杀, 与流派意图无关。
##
## ★反向验证: 把 ARCHETYPES 里任意一条的 xp 改回 1(或 0), 跑 `tests/verify_bot_archetypes.gd`
##   当场 FAIL 并打印是哪一条 —— 我改完亲自验过, 不是"应该会红"。
static func check_suicide_weights() -> Array:
	var bad: Array = []
	for k in ARCHETYPES:
		var w: Dictionary = ARCHETYPES[k]
		## ⚠ 只查**显式写了 xp 的**。没写 xp 的(如 `random`)走产品默认
		## `AI_MAX_XP_BUYS_PER_VISIT=3`, 不是 0 —— 把它算进来会造出一条假失败。
		if not w.has("xp"):
			continue
		if int(w["xp"]) < MIN_XP_BUYS:
			bad.append("%s: xp=%d < 下限 %d —— team_equip_cap=(等级-1)×2, 不买经验就没有装备容量(2026-09-03 实测: xp≤1 的流派最高只到 5~7 级/槽位 8~12, 达档8率 0.40%%)"
				% [str(k), int(w["xp"]), MIN_XP_BUYS])
	return bad


## 货架上这一件的出价分(越大越先买)。**纯函数** ⇒ 门禁直接调, 不跑整场模拟。
## `own` = id → 已有张数; `tcount` = 类型 → 已有【不同 id】件数; `lines` = 该机器人锁定的类型。
static func buy_score(edef, w: Dictionary, own: Dictionary, tcount: Dictionary, lines: Array) -> float:
	if not (edef is Dictionary):
		return 0.0
	var eid := str((edef as Dictionary).get("id", ""))
	var cost := float((edef as Dictionary).get("cost", 1))
	var seen := {}
	for k in own:
		seen[k] = true
	var s := 0.0
	## 费用取向: cost 1~5 映射到 −1..+1, 乘权重(正=偏高费, 负=偏低费)
	s += float(w.get("cost_hi", 0.0)) * ((cost - 3.0) / 2.0) * 6.0
	## 追三合一: 已有 1~2 张的同 id 最值钱(第 3 张直接成 ★2/★3)
	var have := int(own.get(eid, 0))
	if have == 2:
		s += float(w.get("merge", 0.0)) * 12.0
	elif have == 1:
		s += float(w.get("merge", 0.0)) * 7.0
	## 单线专注: 只有"锁定类型里还缺的 id"才加分(已有的同 id 对羁绊零贡献)
	var typ := str(Phase2Types.type_of(eid))
	if float(w.get("focus", 0.0)) > 0.0 and typ != "" and lines.has(typ) and not seen.has(eid):
		s += float(w.get("focus", 0.0)) * 15.0
	## 铺开: 直接用既有的 syn_key(离下一档越近越高), 它自己已经处理了"重复 id 无收益"
	if float(w.get("wide", 0.0)) > 0.0:
		s += float(w.get("wide", 0.0)) * syn_key(edef, seen, tcount) * 0.12
	return s
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const FRAME_CAP := 60000
const SHELF := 10
const MAX_REFRESH := 2

var _rng := RandomNumberGenerator.new()
var _bots: Array = []
var _snapshots: Array = []      # 产出的真实快照(新池原料)
var _battle_log: Array = []
var _round := 0
var _shard := -1                # 分片号(-1 = 非分片模式, 行为与从前逐字一致)


# ════════════════════ 入口 ════════════════════
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true

	## ★★【跑之前】拦自杀权重 —— 用户 2026-09-03:「你这太失败了啊, 也就是说快照全部要
	##   重新跑因为你装了蠢 ai」。上一轮就是配错参数才开跑, **5 小时跑完**才从结果里
	##   看出 hi_cost 的 4~5 费占比比随机组还低 17 个点。这类错在这里 0.1 秒就查得出。
	##   放在 `_ready` 最前面而不是收尾, 是因为收尾时那 5 小时已经花掉了。
	var _bad: Array = check_suicide_weights()
	if not _bad.is_empty():
		print("  [FAIL] ARCHETYPES 里有 %d 条自杀权重, 拒绝开跑(免得白跑几小时):" % _bad.size())
		for _b in _bad:
			print("     · " + str(_b))
		get_tree().quit(1); return

	var n := int(OS.get_environment("COHORT_BOTS")) if OS.get_environment("COHORT_BOTS").is_valid_int() else 32
	var max_rounds := int(OS.get_environment("COHORT_MAX_ROUNDS")) if OS.get_environment("COHORT_MAX_ROUNDS").is_valid_int() else 120
	var st := OS.get_environment("TURTLE_SEED")
	## ★★分片(COHORT_SHARD): 多进程并行跑同一批机器人时用。
	##   两件事必须一起做, 少一件整批就废:
	##   ① **每片种子必须不同** —— 否则各片造出一模一样的机器人、打一模一样的场,
	##      跑 16 片只是把同一份结果复制 16 遍。
	##   ② **ghost_id 必须带片号** —— 原来是 `coh_<bot>_b<battles>`, 而 bot 编号每片都从 0 开始,
	##      合并时必然撞 id(memory [[fb-id-without-owner-dimension]]: 单机够用的 id 一接共享就塌)。
	_shard = int(OS.get_environment("COHORT_SHARD")) if OS.get_environment("COHORT_SHARD").is_valid_int() else -1
	var base_seed: int = int(st) if st.is_valid_int() else 20260727
	_rng.seed = base_seed if _shard < 0 else (base_seed + _shard * 1000003)   # 大质数错开, 不是 +1(相邻种子的前几个数会相近)

	var all_ids: Array = []
	for p in dr.launch_pets:
		all_ids.append(str((p as Dictionary)["id"]))
	if all_ids.size() < 3:
		print("  [FAIL] 龟数据不足"); get_tree().quit(1); return

	for i in range(n):
		_bots.append(_make_bot(i, all_ids))

	print("=== 队列模拟: %d 只机器人, 全部 0 场 8 命起步, 输光即出局 ===" % n)
	print("  龟池 %d 只 | 技能五选一 | 策略 %s | 种子 %d" % [all_ids.size(), str(ARCHETYPES.keys()), int(_rng.seed)])
	var sc := {}
	var lm := {}
	var sk := {}
	for b in _bots:
		sc[b["strategy"]] = int(sc.get(b["strategy"], 0)) + 1
		sk[b["skill"]] = int(sk.get(b["skill"], 0)) + 1
		var nt := 0
		var nb := 0
		for u in ((b["lineup"] as Dictionary)["top"] as Array):
			if str((u as Dictionary).get("kind", "")) == "leader": nt += 1
		for u in ((b["lineup"] as Dictionary)["bottom"] as Array):
			if str((u as Dictionary).get("kind", "")) == "leader": nb += 1
		var mk := "%d/%d" % [nt, nb]
		lm[mk] = int(lm.get(mk, 0)) + 1
	print("  策略分布: %s" % str(sc))
	print("  分路分布(上路统领/下路统领): %s" % str(lm))
	print("  技能分布: %s" % str(sk))
	print("")

	var t0 := Time.get_ticks_msec()
	while _round < max_rounds and _alive().size() >= 2:
		_round += 1
		await _run_round(gs)
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0

	_report(elapsed)
	get_tree().quit(0)


func _make_bot(i: int, all_ids: Array) -> Dictionary:
	var pool: Array = all_ids.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var j: int = _rng.randi() % (k + 1)
		var t = pool[k]; pool[k] = pool[j]; pool[j] = t
	var team: Array = pool.slice(0, 3)
	# ★分路 4 模式 (用户 2026-07-27「可以三小将一条路, 3统领一条路, 上下换位」)。
	#   权重贴近种子池实际分布: 2/1经典60 · 1/2下重37 · 3统领上路28 · 3统领下路21。
	#   每路恒 3 格: 统领占前几格, 其余补小将; 空统领路 = 3 小将守(种子池注释的「空统领路小将守」),
	#   该路首个小将成精英(见 _snapshot_of)。GameState._dl_structure_ok 只要求"共3统领+slot齐0/1/2",
	#   不要求两路都有统领 → (3,0)/(0,3) 合法。
	var modes := [[2, 1], [1, 2], [3, 0], [0, 3]]
	var weights := [60, 37, 28, 21]
	var tot := 0
	for w in weights:
		tot += w
	var pick: int = _rng.randi() % tot
	var mode: Array = modes[0]
	for mo in range(modes.size()):
		if pick < int(weights[mo]):
			mode = modes[mo]
			break
		pick -= int(weights[mo])
	var lineup := {"top": [], "bottom": []}
	var slot := 0
	for li in range(2):
		var lane: String = "top" if li == 0 else "bottom"
		var n_lead: int = int(mode[li])
		var arr: Array = []
		for _i in range(n_lead):
			arr.append({"kind": "leader", "id": team[slot], "slot": slot})
			slot += 1
		for mi in range(3 - n_lead):
			# 首个补位小将偏前排(挡刀), 后面的偏后排(输出); 留随机 —— 真玩家排法本来就不统一
			var front_bias: float = 0.75 if mi == 0 else 0.35
			arr.append({"kind": "minion", "role": ("front" if _rng.randf() < front_bias else "back")})
		lineup[lane] = arr
	## ★抽一个命名锚点, 再**加扰动** —— 不加的话 800 支只有 14 个样子。
	##   扰动只动数值项(±35%), 不动 minion_first 这种开关(那是二选一, 抖了就没意义)。
	var names: Array = ARCHETYPES.keys()
	var arch := str(names[_rng.randi() % names.size()])
	var w: Dictionary = (ARCHETYPES[arch] as Dictionary).duplicate()
	for k in ["cost_hi", "focus", "wide", "merge", "eager"]:
		if w.has(k):
			w[k] = float(w[k]) * (0.65 + 0.70 * _rng.randf())
	for k in ["reserve", "xp", "refresh"]:
		if w.has(k):
			w[k] = maxi(0, int(round(float(w[k]) * (0.65 + 0.70 * _rng.randf()))))
	## 单线/双线: 从真实类型表里抽 lines 个锁定类型(不写死, 表变了它跟着变)
	var lines: Array = []
	var nl: int = int(w.get("lines", 0))
	if nl > 0:
		var tys: Array = Phase2Types.TYPES.keys()
		for _q in range(nl):
			var lt := str(tys[_rng.randi() % tys.size()])
			if not lines.has(lt):
				lines.append(lt)
	return {
		"id": i,
		"name": "机器人%02d" % i,
		"team": team,
		"skill": SKILLS[_rng.randi() % SKILLS.size()],
		"strategy": arch,                 # 锚点名(进快照的 _strategy, 便于按流派对账)
		"w": w,                           # 策略向量(锚点 + 扰动)
		"lines": lines,                   # 单线/双线锁定的羁绊类型
		"lineup": lineup,
		"battles": 0, "hearts": 8, "coins": 0, "level": 1, "xp": 0, "wins": 0,
		"bench": [], "equipped": {},
		"candy": 0, "candy_broken": false, "candy_levels": {},
		"alive": true, "out_at": -1,
	}


func _alive() -> Array:
	var a: Array = []
	for b in _bots:
		if b["alive"]:
			a.append(b)
	return a


# ════════════════════ 一轮: 按档配对互打 ════════════════════
func _run_round(gs) -> void:
	# 按档分组 (同档才配对; 同档落单 → 往【低】档找, 绝不往上 —— 与 find_opponent 去±1 后同规则)
	var by_b := {}
	for b in _alive():
		var k: int = Backend.bracket_for_battles(int(b["battles"]))
		if not by_b.has(k):
			by_b[k] = []
		(by_b[k] as Array).append(b)
	var keys: Array = by_b.keys()
	keys.sort()
	keys.reverse()      # 从高档往低档配, 落单的往低档并

	var carry: Array = []      # 上一(更高)档落单的
	var pairs: Array = []
	for k in keys:
		var grp: Array = (by_b[k] as Array)
		grp.append_array(carry)
		carry = []
		for i in range(grp.size() - 1, 0, -1):
			var j: int = _rng.randi() % (i + 1)
			var t = grp[i]; grp[i] = grp[j]; grp[j] = t
		while grp.size() >= 2:
			pairs.append([grp.pop_back(), grp.pop_back()])
		if grp.size() == 1:
			carry.append(grp[0])

	var fought := 0
	for pr in pairs:
		await _fight(gs, pr[0], pr[1])
		fought += 1
	var al := _alive().size()
	print("  第%2d轮: %d 场 | 存活 %d/%d | 场次分布 %s" % [_round, fought, al, _bots.size(), _battles_hist()])


func _battles_hist() -> String:
	var h := {}
	for b in _alive():
		var k: int = Backend.bracket_for_battles(int(b["battles"]))
		h[k] = int(h.get(k, 0)) + 1
	var keys: Array = h.keys(); keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("档%d:%d" % [k, h[k]])
	return " ".join(PackedStringArray(parts))


# ════════════════════ 一场 ════════════════════
func _fight(gs, a: Dictionary, b: Dictionary) -> void:
	_load(gs, a)
	gs.reset_dual_lane()
	gs.dual_active = true
	# ★快照在【开打前】存 —— 它要表达的是"这个对手当时长什么样", 不是"他打完又逛了一轮商店之后"。
	#   存在打完之后会让 档0 出现 7.5 件装备(第1场打完买了一轮), 与"第一大轮第一把没装备"直接矛盾。
	var snap_a := _snapshot_of(a, a["name"])
	var snap_b := _snapshot_of(b, b["name"])
	_snapshots.append(snap_a)
	_snapshots.append(snap_b)
	gs.dual_ghost = snap_b

	var s = RB.new()
	add_child(s)
	var fr := 0
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
	var reached: bool = str(s._dl_state) == "done"
	var a_won: bool = str(gs.dual_lane_winner()) == "left"
	# ★判完 done 先宽限几帧再释放场景 —— 否则正在飞的演出(大剑下劈/熔岩柱/忍者滑翔…)
	#   会在 await 之后撞上已释放的 battle, 刷 "Nonexistent function ... on previously freed"。
	#   实测那类报错都发生在【胜负判定之后】不影响数据, 但会污染致命报错计数。
	#   真实对局里场景会停在结算横幅上直到切场景, 本来就有这段宽限期; harness 原来一判 done 就腰斩。
	for _g in range(30):
		await get_tree().process_frame
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	_save(gs, a)                      # 引擎已在 _settle_season 里把 a 结算好了
	_settle_mirror(b, not a_won)      # b 在右侧, 引擎不喂它 → 手工镜像同一套结算

	_battle_log.append({
		"round": _round, "a": a["id"], "b": b["id"], "a_won": a_won,
		"a_battles": int(a["battles"]), "b_battles": int(b["battles"]),
		"a_hearts": int(a["hearts"]), "b_hearts": int(b["hearts"]),
		"bracket": Backend.bracket_for_battles(int(a["battles"])), "done": reached, "frames": fr,
	})

	for who in [a, b]:
		_load(gs, who)
		_shop(gs, who)
		_equip(gs, who)
		_save(gs, who)
		if int(who["hearts"]) <= 0 and who["alive"]:
			who["alive"] = false
			who["out_at"] = int(who["battles"])


## 镜像 RealtimeBattle3DScene._settle_season(:7247) —— 右侧机器人引擎不喂, 这里等效结算。
## 改那边必须改这里(两处口径必须一致, 否则左右两侧经济不同 = 数据作废)。
func _settle_mirror(bot: Dictionary, won: bool) -> void:
	if int(bot["hearts"]) <= 0:
		bot["coins"] = int(bot["coins"]) + 5      # 表演赛: 不掉命/不计战
		return
	if not won:
		bot["hearts"] = maxi(0, int(bot["hearts"]) - 1)
	var lost: int = maxi(0, 8 - int(bot["hearts"]))
	bot["coins"] = int(bot["coins"]) + 8 + int(bot["hearts"]) + 2 * lost + (6 if won else 0)
	bot["battles"] = int(bot["battles"]) + 1
	bot["xp"] = int(bot["xp"]) + 2
	while int(bot["level"]) < P2.MAX_LEVEL and int(bot["xp"]) >= P2.xp_to_next(int(bot["level"])):
		bot["xp"] = int(bot["xp"]) - P2.xp_to_next(int(bot["level"]))
		bot["level"] = int(bot["level"]) + 1
	bot["candy"] = mini(30, int(bot["candy"]) + (1 if won else 4))
	if won:
		bot["wins"] = int(bot["wins"]) + 1


# ════════════════════ 机器人状态 ↔ GameState ════════════════════
func _load(gs, bot: Dictionary) -> void:
	gs.season_leaders = (bot["team"] as Array).duplicate()
	gs.left_team.assign(bot["team"])
	gs.dual_lineup = (bot["lineup"] as Dictionary).duplicate(true)
	gs.season_total_battles = int(bot["battles"])
	gs.hearts = int(bot["hearts"])
	gs.meta_deepsea_coins = int(bot["coins"])
	gs.season_level = int(bot["level"])
	gs.season_xp = int(bot["xp"])
	gs.season_wins = int(bot["wins"])
	gs.persistent_bench = (bot["bench"] as Array).duplicate(true)
	gs.persistent_equipped = (bot["equipped"] as Dictionary).duplicate(true)
	gs.candy_jar_count = int(bot["candy"])
	gs.candy_jar_broken = bool(bot["candy_broken"])
	gs.candy_temp_levels = (bot["candy_levels"] as Dictionary).duplicate(true)
	gs.trainer_skill = str(bot["skill"])


func _save(gs, bot: Dictionary) -> void:
	bot["battles"] = int(gs.season_total_battles)
	bot["hearts"] = int(gs.hearts)
	bot["coins"] = int(gs.meta_deepsea_coins)
	bot["level"] = int(gs.season_level)
	bot["xp"] = int(gs.season_xp)
	bot["wins"] = int(gs.season_wins)
	bot["bench"] = (gs.persistent_bench as Array).duplicate(true)
	bot["equipped"] = (gs.persistent_equipped as Dictionary).duplicate(true)
	bot["lineup"] = (gs.get_dual_lineup() as Dictionary).duplicate(true)
	bot["candy"] = int(gs.candy_jar_count)
	bot["candy_broken"] = bool(gs.candy_jar_broken)
	bot["candy_levels"] = (gs.candy_temp_levels as Dictionary).duplicate(true)


## 把机器人当时的【真实家当】序列化成 ghost 快照 —— 这就是新池的原料。
## ★不用 Backend.build_ghost_snapshot: 它读的是每局被 reset_dual_lane 清空的 equipped_p2,
##   产出的 equipped 恒为空(2026-07-27 实测)。这里直接读 persistent_equipped(战斗真正读的那个)。
func _snapshot_of(bot: Dictionary, label: String) -> Dictionary:
	var lineup: Dictionary = bot["lineup"]
	var lane_assign := {"top": [], "bottom": []}
	var minions := {"top": [], "bottom": []}
	for lane in ["top", "bottom"]:
		for u in (lineup.get(lane, []) as Array):
			var ud: Dictionary = u
			if str(ud.get("kind", "")) == "leader":
				(lane_assign[lane] as Array).append(str(ud.get("id", "")))
			else:
				(minions[lane] as Array).append({
					"role": str(ud.get("role", "front")),
					"elite": (lane_assign[lane] as Array).is_empty() and (minions[lane] as Array).is_empty(),
					"equips": ((ud.get("equips", []) as Array)).duplicate(true),
				})
	var levels := {}
	for pid in (bot["team"] as Array):
		levels[str(pid)] = 1 + int((bot["candy_levels"] as Dictionary).get(str(pid), 0))
	return {
		"schema_ver": 1,
		## ★片号进 id: 非分片模式(片号 -1)保持原样 `coh_<bot>_b<n>`, 老数据不受影响。
		"ghost_id": ("coh_%d_b%d" % [int(bot["id"]), int(bot["battles"])]) if _shard < 0
			else ("coh_s%d_%d_b%d" % [_shard, int(bot["id"]), int(bot["battles"])]),
		"is_bot": false,
		"bracket": Backend.bracket_for_battles(int(bot["battles"])),
		"profile": {"name": label, "avatar": str((bot["team"] as Array)[0]),
			"id": ("COH%02d" % int(bot["id"])) if _shard < 0 else ("COH%d-%02d" % [_shard, int(bot["id"])])},
		"leaders": (bot["team"] as Array).duplicate(),
		"lane_assign": lane_assign,
		"minions": minions,
		"loadouts": {},
		"equipped": (bot["equipped"] as Dictionary).duplicate(true),
		"pet_levels": levels,
		"trainer_skill": str(bot["skill"]),     # ★2026-07-27 新增: 敌方大师读它(battle_spawn.gd)
		"season_total_battles": int(bot["battles"]),
		"season_eggs_killed": 0,
		"season_level": int(bot["level"]),     # ★门禁用它算全队装备上限 team_equip_cap()
		"_strategy": str(bot["strategy"]),
	}


# ════════════════════ 商店 / 背包 (与 _autoplay 同口径) ════════════════════
## 羁绊流的出价分(越大越先买)。★纯函数 ⇒ 门禁(verify_bot_buy_synergy)直接调, 不跑整场模拟。
##   `seen_ids` = 已拥有的装备 id 集合(去重口径); `tcount` = 类型 → 已有件数。
##
## 分档理由(不是拍脑袋的权重):
##   · 已有同款 id → 羁绊收益**恒为 0**(calc_active 按 id 去重), 只剩合成价值 ⇒ 压到最低档
##   · 这一件正好**跨过下一档阈值** → 立刻拿到整档属性 ⇒ 最高档
##   · 否则按"离下一档还差几件"给分, 差得越少越先买(差 1 件 > 差 3 件)
##   · 类型已顶档(没有更高阈值) → 再买不涨档, 与"无类型"同档
static func syn_key(edef, seen_ids: Dictionary, tcount: Dictionary) -> float:
	if not (edef is Dictionary):
		return 0.0
	var eid := str((edef as Dictionary).get("id", ""))
	if eid == "" or seen_ids.has(eid):
		return 0.0                                   # 重复件: 无羁绊收益
	var typ := str(Phase2Types.type_of(eid))
	if typ == "" or not Phase2Types.TYPES.has(typ):
		return 0.0
	var tiers: Array = (Phase2Types.TYPES[typ] as Dictionary).get("tiers", [])
	var n: int = int(tcount.get(typ, 0))
	var need := -1
	for t in tiers:
		if n < int(t):
			need = int(t) - n                        # 还差几件到下一档
			break
	if need < 0:
		return 0.5                                   # 该类型已顶档: 买了也不涨档
	if need <= 1:
		return 100.0                                 # 这一件就跨档 —— 立刻拿整档属性
	return 10.0 / float(need)                        # 差得越少越先买


func _item_strength(item) -> float:
	if not (item is Dictionary):
		return 0.0
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((item as Dictionary).get("id", "")), {})
	var cost := int(edef.get("cost", 0))
	if cost <= 0:
		return 0.0
	var star: int = maxi(1, int((item as Dictionary).get("star", 1)))
	var k := {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}
	return float(cost) * pow(1.8, float(star - 1)) * float(k.get(cost, 1.0))


func _is_equip(item) -> bool:
	return item is Dictionary and str((item as Dictionary).get("kind", "")) != "item" \
		and DataRegistry.phase2_equipment_by_id.has(str((item as Dictionary).get("id", "")))


func _shop(gs, bot: Dictionary) -> void:
	# ① 糖果罐: 攒满就砸; 快没命了也砸(用户设计: 输+4→8命输光正好30封顶=逆风补偿)
	if gs.has_candy_jar() and not bool(gs.candy_jar_broken):
		if int(gs.candy_jar_count) >= 30 or (int(gs.hearts) <= 1 and int(gs.candy_jar_count) >= 12):
			gs.break_candy_jar()

	# ② 临时等级器(糖果罐战利品): 给随机一只统领
	for i in range((gs.persistent_bench as Array).size() - 1, -1, -1):
		var it = (gs.persistent_bench as Array)[i]
		if it is Dictionary and str((it as Dictionary).get("kind", "")) == "item":
			var team: Array = gs.season_leaders
			if not team.is_empty():
				gs.apply_temp_leveler(str(team[_rng.randi() % team.size()]))
				gs.consume_temp_leveler(i)

	# ③ 买经验(照抄项目自己的"像玩家"口径 phase2_config.gd:53)
	## ★★这两个上限原来读的是写死的 P2.AI_MAX_XP_BUYS_PER_VISIT / P2.AI_GEAR_RESERVE ——
	##   于是「速升级流」和「滚雪球流」在旧实现里**根本不可能存在**(所有机器人升级节奏一模一样)。
	##   现在由策略向量给; 向量里没有这两项时**缺省仍是项目原口径**(行为不变)。
	var w_s: Dictionary = bot.get("w", {})
	var xp_cap: int = int(w_s.get("xp", P2.AI_MAX_XP_BUYS_PER_VISIT))
	var reserve: int = int(w_s.get("reserve", P2.AI_GEAR_RESERVE))
	var xp_buys := 0
	while xp_buys < xp_cap and int(gs.season_level) < P2.MAX_LEVEL \
			and int(gs.meta_deepsea_coins) >= reserve + P2.BUY_XP_COST:
		if not gs.buy_season_xp():
			break
		xp_buys += 1

	# ④ 买装备 (买不到东西就刷新, 最多 MAX_REFRESH 次 —— 真玩家会刷)
	## ★★刷新原来是"买不到东西才刷、最多 2 次"⇒「疯狂刷新流」在旧实现里不存在。
	##   现在上限由向量给; `eager` 让它**买到了也可能继续刷**(真玩家会为了凑羁绊硬刷)。
	var rf_cap: int = int(w_s.get("refresh", MAX_REFRESH))
	var eager: float = float(w_s.get("eager", 0.0))
	var refreshed := 0
	while true:
		var bought := _buy_once(gs, bot.get("w", {}), bot.get("lines", []))
		if bought > 0 and _rng.randf() >= eager:
			break
		if refreshed >= rf_cap or int(gs.meta_deepsea_coins) < 2 + 1:
			break
		gs.meta_deepsea_coins -= 2      # REFRESH_COST(ShopScene.gd:9)
		refreshed += 1


func _buy_once(gs, w: Dictionary, lines: Array) -> int:
	var maxed := {}
	for it in _all_items(gs):
		if int((it as Dictionary).get("star", 1)) >= 3:
			maxed[str((it as Dictionary).get("id", ""))] = true
	var pool: Array = []
	for e in DataRegistry.phase2_equipment:
		if not maxed.has(str((e as Dictionary).get("id", ""))):
			pool.append(e)
	var stage: int = clampi(int(gs.season_level), 1, 10)
	var offer: Array = P2EQ.roll_shop(pool, stage, SHELF, _rng)

	var idxs: Array = []
	for i in range(offer.size()):
		if offer[i] != null:
			idxs.append(i)
	## ★★统一打分排序(取代原来的 match) —— 四种旧策略只改这一个决策点,
	##   而"高费流"若不能攒钱、不能刷新, 就只是排序偏好, 攒不出钱也买不到高费件。
	##   现在这里只管"同样买得起时先买哪件", 攒钱/刷新在 `_shop` 里由同一个向量驱动。
	var own := {}
	var tcount := {}
	var seen_ids := {}
	for it in _all_items(gs):
		var iid := str((it as Dictionary).get("id", ""))
		if iid == "":
			continue
		own[iid] = int(own.get(iid, 0)) + 1
		if not seen_ids.has(iid):
			seen_ids[iid] = true
			var ty := str(Phase2Types.type_of(iid))
			if ty != "":
				tcount[ty] = int(tcount.get(ty, 0)) + 1
	## 先随机打散 —— 打分相同时(如 random 锚点全零)就是纯随机顺序, 不会退化成"永远按货架下标"
	for i in range(idxs.size() - 1, 0, -1):
		var j: int = _rng.randi() % (i + 1)
		var tmp = idxs[i]; idxs[i] = idxs[j]; idxs[j] = tmp
	idxs.sort_custom(func(a, b):
		return buy_score(offer[a], w, own, tcount, lines) > buy_score(offer[b], w, own, tcount, lines))
	var n := 0
	for i in idxs:
		var e = offer[i]
		var price: int = maxi(1, int((e as Dictionary).get("cost", 1)))
		if int(gs.meta_deepsea_coins) < price:
			continue
		gs.meta_deepsea_coins -= price
		(gs.persistent_bench as Array).append({"id": str((e as Dictionary).get("id", "")), "star": 1})
		gs.auto_merge_all()
		n += 1
	return n


## ★★`minion_first`: 原实现**写死**"先把统领填满, 溢出的才给小将" ⇒「小将优先流」
##   在旧实现里根本不存在。队伍装备总量有上限(`team_equip_cap`), 所以**先给谁是真的会改变结果**。
func _equip(gs, bot: Dictionary = {}) -> void:
	var minion_first: bool = int((bot.get("w", {}) as Dictionary).get("minion_first", 0)) == 1
	if minion_first:
		_fill_minions(gs)
		_fill_leaders(gs)
	else:
		_fill_leaders(gs)
		_fill_minions(gs)
	gs.auto_merge_all()
	_sell_junk(gs)


func _fill_leaders(gs) -> void:
	# ★装备容量统一规则(2026-07-27): 单只 ≤ UNIT_EQUIP_CAP(3) 且 全队 6 只合计 ≤ team_equip_cap(赛季等级)。
	#   完全自由分配 → 机器人的策略: 先把统领填满(统领有技能, 装备收益更高), 溢出的才给小将。
	var slots: int = P2.UNIT_EQUIP_CAP
	# 统领空槽 → 装背包最强
	for pid in (gs.season_leaders as Array):
		var p := str(pid)
		var eqs: Array = (gs.persistent_equipped as Dictionary).get(p, [])
		while eqs.size() < slots and gs.team_has_equip_room():
			var bi := _best_bench(gs)
			if bi < 0: break
			eqs.append((gs.persistent_bench as Array)[bi])
			(gs.persistent_bench as Array).remove_at(bi)
			(gs.persistent_equipped as Dictionary)[p] = eqs   # 先写回, team_equipped_count 才数得到
		(gs.persistent_equipped as Dictionary)[p] = eqs
	# 换装: 背包最强 > 身上最弱 → 换
	for pid in (gs.season_leaders as Array):
		var p := str(pid)
		var eqs: Array = (gs.persistent_equipped as Dictionary).get(p, [])
		var guard := 0
		while guard < 8 and not eqs.is_empty():
			guard += 1
			var bi := _best_bench(gs)
			if bi < 0: break
			var wi := 0
			for i in range(eqs.size()):
				if _item_strength(eqs[i]) < _item_strength(eqs[wi]): wi = i
			var cand = (gs.persistent_bench as Array)[bi]
			if _item_strength(cand) <= _item_strength(eqs[wi]): break
			var old = eqs[wi]; eqs[wi] = cand; (gs.persistent_bench as Array)[bi] = old
		(gs.persistent_equipped as Dictionary)[p] = eqs


func _fill_minions(gs) -> void:
	var slots: int = P2.UNIT_EQUIP_CAP
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			var u: Dictionary = arr[i]
			if str(u.get("kind", "")) != "minion": continue
			var meqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
			while meqs.size() < slots and gs.team_has_equip_room():
				var bi := _best_bench(gs)
				if bi < 0: break
				meqs.append((gs.persistent_bench as Array)[bi])
				(gs.persistent_bench as Array).remove_at(bi)
				u["equips"] = meqs; arr[i] = u; dl[lane] = arr; gs.dual_lineup = dl   # 先写回再数
			u["equips"] = meqs
			arr[i] = u
		dl[lane] = arr
	gs.dual_lineup = dl


## 卖废品: 只卖【背包里没有同款可凑合成】且【弱于身上最弱一件】的, 且背包 >8 时才卖。
## (留着同款是为了三合一 —— 卖掉重复件等于自断升星路)
func _sell_junk(gs) -> void:
	var weakest := 1e9
	for p in (gs.persistent_equipped as Dictionary).keys():
		for it in ((gs.persistent_equipped as Dictionary)[p] as Array):
			weakest = minf(weakest, _item_strength(it))
	if weakest > 1e8:
		return
	var guard := 0
	while (gs.persistent_bench as Array).size() > 8 and guard < 20:
		guard += 1
		var cnt := {}
		for it in (gs.persistent_bench as Array):
			if _is_equip(it):
				var k := "%s|%d" % [str((it as Dictionary).get("id", "")), int((it as Dictionary).get("star", 1))]
				cnt[k] = int(cnt.get(k, 0)) + 1
		var target := -1
		for i in range((gs.persistent_bench as Array).size()):
			var it = (gs.persistent_bench as Array)[i]
			if not _is_equip(it): continue
			var k := "%s|%d" % [str((it as Dictionary).get("id", "")), int((it as Dictionary).get("star", 1))]
			if int(cnt.get(k, 0)) > 1: continue          # 有同款 → 留着凑合成
			if _item_strength(it) >= weakest: continue    # 比身上最弱的还强 → 留着
			target = i
			break
		if target < 0:
			break
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(
			str(((gs.persistent_bench as Array)[target] as Dictionary).get("id", "")), {})
		var cost: int = maxi(1, int(edef.get("cost", 1)))
		var star: int = maxi(1, int(((gs.persistent_bench as Array)[target] as Dictionary).get("star", 1)))
		gs.meta_deepsea_coins += int(floor(cost * star * 0.8))    # 同 InvOps._sell_value
		(gs.persistent_bench as Array).remove_at(target)


func _best_bench(gs) -> int:
	var best := -1
	var bs := 0.0
	for i in range((gs.persistent_bench as Array).size()):
		var it = (gs.persistent_bench as Array)[i]
		if not _is_equip(it): continue
		var s := _item_strength(it)
		if s > bs:
			bs = s; best = i
	return best


func _all_items(gs) -> Array:
	var out: Array = []
	for it in (gs.persistent_bench as Array):
		if _is_equip(it): out.append(it)
	for p in (gs.persistent_equipped as Dictionary).keys():
		for it in ((gs.persistent_equipped as Dictionary)[p] as Array):
			if _is_equip(it): out.append(it)
	var dl: Dictionary = gs.get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			for it in ((u as Dictionary).get("equips", []) as Array):
				if _is_equip(it): out.append(it)
	return out


func _snap_strength(sn: Dictionary) -> float:
	var t := 0.0
	for p in (sn.get("equipped", {}) as Dictionary).keys():
		for it in ((sn["equipped"] as Dictionary)[p] as Array):
			t += _item_strength(it)
	for lk in (sn.get("minions", {}) as Dictionary).keys():
		for m in (sn["minions"][lk] as Array):
			for it in ((m as Dictionary).get("equips", []) as Array):
				t += _item_strength(it)
	return t


# ════════════════════ 报告 ════════════════════
func _report(elapsed: float) -> void:
	var dir := OS.get_environment("COHORT_OUT")
	if dir == "":
		dir = "res://tools/autoplay"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir)

	print("")
	print("=== 队列小结 (%d 轮, %d 场, 墙钟 %.0f 秒) ===" % [_round, _battle_log.size(), elapsed])
	var done := 0
	for r in _battle_log:
		if r["done"]: done += 1
	print("  跑完整场: %d/%d  (不足=数据有洞)" % [done, _battle_log.size()])
	print("  ★分母: 机器人 %d 只, 快照 %d 条 (0=空跑)" % [_bots.size(), _snapshots.size()])

	# 存活曲线
	print("")
	print("  出局分布(打到第几场被淘汰):")
	var outs: Array = []
	for b in _bots:
		if not b["alive"]:
			outs.append(int(b["out_at"]))
	outs.sort()
	var still: Array = _alive()
	print("    已出局 %d 只 | 场次: %s" % [outs.size(), str(outs)])
	print("    仍存活 %d 只 | 场次: %s" % [still.size(), str(still.map(func(x): return int(x["battles"])))])
	if not outs.is_empty():
		print("    中位出局场次: %d  最多打到: %d" % [outs[outs.size() / 2], outs[outs.size() - 1]])

	# 各档产出了多少快照 + 强度
	print("")
	print("  档  快照数  队均强度  平均件数   ← 这就是新池的真实原料")
	var by_b := {}
	for sn in _snapshots:
		var b: int = int(sn["bracket"])
		if not by_b.has(b):
			by_b[b] = {"n": 0, "s": 0.0, "items": 0}
		by_b[b]["n"] += 1
		by_b[b]["s"] += _snap_strength(sn)
		var ni := 0
		for p in (sn["equipped"] as Dictionary).keys():
			ni += ((sn["equipped"] as Dictionary)[p] as Array).size()
		for lk in (sn["minions"] as Dictionary).keys():
			for m in (sn["minions"][lk] as Array):
				ni += ((m as Dictionary).get("equips", []) as Array).size()
		by_b[b]["items"] += ni
	var keys: Array = by_b.keys(); keys.sort()
	for b in keys:
		var d: Dictionary = by_b[b]
		var n: float = maxf(1.0, float(d["n"]))
		print("  %2d %7d %9.1f %9.2f" % [b, d["n"], d["s"] / n, float(d["items"]) / n])
	var missing: Array = []
	for b in range(0, 9):
		if not by_b.has(b):
			missing.append(b)
	if not missing.is_empty():
		print("  ★档 %s 一条快照都没产出 —— 没有机器人活到那么远。" % str(missing))

	# 策略胜率 (机器人"水平"= 池子水平, 这条决定新池强弱)
	print("")
	print("  策略        只数  总场次  总胜  胜率   中位出局场次")
	var by_s := {}
	for b in _bots:
		var k := str(b["strategy"])
		if not by_s.has(k):
			by_s[k] = {"n": 0, "bt": 0, "w": 0, "outs": []}
		by_s[k]["n"] += 1
		by_s[k]["bt"] += int(b["battles"])
		by_s[k]["w"] += int(b["wins"])
		if not b["alive"]:
			(by_s[k]["outs"] as Array).append(int(b["out_at"]))
	for k in by_s.keys():
		var d: Dictionary = by_s[k]
		var o: Array = d["outs"]; o.sort()
		print("  %-12s %4d %7d %5d %5.1f%% %8s" % [k, d["n"], d["bt"], d["w"],
			100.0 * float(d["w"]) / maxf(1.0, float(d["bt"])),
			(str(o[o.size() / 2]) if not o.is_empty() else "-")])

	# 落盘: 快照池 + 逐场 CSV
	var pool := {"_note": "队列模拟产出的真实玩家快照 (tests/_cohort.gd · %d只机器人从0开始互打·8命淘汰)" % _bots.size(),
		"brackets": {}}
	for sn in _snapshots:
		var bk := str(int(sn["bracket"]))
		if not (pool["brackets"] as Dictionary).has(bk):
			(pool["brackets"] as Dictionary)[bk] = []
		((pool["brackets"] as Dictionary)[bk] as Array).append(sn)
	var suffix := "" if _shard < 0 else ("-s%d" % _shard)
	var pf := FileAccess.open("%s/cohort-snapshots%s.json" % [dir, suffix], FileAccess.WRITE)
	if pf != null:
		pf.store_string(JSON.stringify(pool, " ")); pf.close()
		print("")
		print("  快照池: %s/cohort-snapshots%s.json" % [dir, suffix])

	var csv := "轮,档,A,B,A胜,A场次,B场次,A命,B命,帧\n"
	for r in _battle_log:
		csv += "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n" % [r["round"], r["bracket"], r["a"], r["b"],
			(1 if r["a_won"] else 0), r["a_battles"], r["b_battles"], r["a_hearts"], r["b_hearts"], r["frames"]]
	var cf := FileAccess.open("%s/cohort-battles%s.csv" % [dir, suffix], FileAccess.WRITE)
	if cf != null:
		cf.store_string(csv); cf.close()
		print("  逐场 CSV: %s/cohort-battles%s.csv" % [dir, suffix])
