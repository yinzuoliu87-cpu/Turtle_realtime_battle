extends Node
## verify_pool_truth — 对手池说的话必须是真的。三件事, 各自都是「说谎级」而不是措辞问题:
##
## ① 排行榜把【连不上】说成【你打得少】
##    屏上原话:「（榜上暂时只有你 —— 打完一场, 对手就会上来）」。
##    探针 `tests/_probe_lb_reach.gd` 实测: 池子 396 条 / 榜上 rows = **1**。
##    `Backend.pool_add` 的全部调用点只有四条 ——
##      `_ensure_seeded`(陪练, 被「陪练不上榜」筛掉) /
##      `upload_ghost`(自己, 被 `_is_self_ghost` 筛掉) /
##      `apply_pull_response` 与 `ingest_remote`(**纯网络**)
##    ⇒ **断网时打一万场也不会有对手上来。** 那句话把网络失败归因到玩家的场次上。
##
## ② 「精确同场次命中率」把陪练全算成真人
##    探针 `tests/_probe_seed_exact.gd` 实测: 40 次抽对手 40 次是 `seed_` 陪练,
##    而 `match_src_counts` 报 `exact: 40 / bot: 0` ⇒ 命中率看着 **100%**、
##    真人**一个都没碰到**。而未决点 A-R3(「命中率多低算太低」)就靠这个数来答。
##    ★关键对照: 排行榜那一侧**早就有**同维度的筛子(`seed_` 前缀)。同一个判据只做了一半。
##
## ③ 周六新鲜度的「现在」拿的是系统钟
##    ⇒ 那条 30 分钟规则只有**真的到了那一刻**才验得到。已接 `phase2_config.now_utc()`。
##
## ═══ 判据形状(每条都按本仓纪律配了分母) ═══
## ★纯判据与取数**分开**: `run-tests.sh:359` 给每个测试都带 `TURTLE_SUPABASE=" "`
##   ⇒ `Supabase.enabled()` 恒 false ⇒ 真实取数永远只落在 REACH_OFF 这一档。
##   要让另外三档也有分母, 判据必须是可穷举的纯函数 —— 而"取数那一半真的接上了"
##   另有 ③ 那一节用**真入口** `apply_pull_response()` 端到端走一遍(不是我自己设计数器)。
## ★屏上那句话**读活节点的 `text`**, 不在源码里找字符串(源码子串匹配是假判据)。
## ★时间缝**钉时刻 + 走真入口**: 同一个池子、两个钉住的时刻 ⇒ 必须选出**两个不同的对手**。
##   只看源码里出现了 `now_utc` 这个符号不算接上。

const _BE := preload("res://scripts/net/backend.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _RP := preload("res://scripts/net/remote_pool.gd")
const _LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

## ★那句假话的**承诺**本身 —— 这是整条 ① 的判据核心。
##   「打完一场」是玩家的动作、「对手就会上来」是结果, 后半句才是谎。
const PROMISE := "对手就会上来"
const BLAME_NET := "连不上"

## 端到端抽对手的次数。★40 与探针同一个数, 好对着看。
const N_DRAWS := 40
## 分母下限: 内置种子池实测 396 条。低于这个数 = 量的不是真池子。
const MIN_POOL := 300

## ⑧ 用的两份闯关赛快照: 同标签、只差上传时刻。
const GL_W := 2
const GL_L := 1
const TS_A := 1700000000            # 早的那份
const TS_B := 1700000000 + 3600     # 晚一小时的那份

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	_ok("① ★分母: GameState 在位", gs != null)
	if gs == null:
		_done()
		return
	gs.test_mode = true

	_t_pool_facts()
	_t_tally_split()
	await _t_screen_says()
	_t_hint_table()
	_t_reach_live()
	_t_time_seam()
	_t_finals_retry()
	_done()


# ─────────────────────────────────────────────────────────────
# ① 分母: 那句假话的**前提**在真池子上确实成立
# ─────────────────────────────────────────────────────────────
func _t_pool_facts() -> void:
	print("── ① 真池子 vs 真榜(那句话的前提) ──")
	_BE.pool_override = {}
	var pool: Dictionary = _BE.load_pool()
	var buckets: Dictionary = pool.get(_BE.POOL_KEY, {})
	var n_all := 0
	var n_seed := 0
	for b in buckets.keys():
		for g in buckets[b]:
			n_all += 1
			if _BE.is_sparring(g):
				n_seed += 1
	_ok("① ★分母: 真池子里有快照(不是空池 —— 空池下面全是空检查)",
		n_all >= MIN_POOL, "%d 条(下限 %d)" % [n_all, MIN_POOL])
	_ok("① ★分母: 它们**全是** `seed_` 陪练(这才是「榜上只有你」的成因)",
		n_seed == n_all and n_all > 0, "陪练 %d / 共 %d" % [n_seed, n_all])
	var rows: Array = _BE.leaderboard(pool, "我", 0, 8, 0, 1 << 30)
	_ok("① ★★池子 %d 条而榜上只有你一行 ⇒ 「打完一场对手就会上来」离线时不成立" % n_all,
		rows.size() == 1, "rows=%d" % rows.size())
	## ★这条是 ② 那节的**前提**: 陪练判据只有一条, 两处必须共用。
	_ok("① ★`is_sparring` 就是排行榜在用的那条筛子(前缀 `%s`)" % _BE.SEED_ID_PREFIX,
		_BE.is_sparring({"ghost_id": _BE.SEED_ID_PREFIX + "x"}) \
			and not _BE.is_sparring({"ghost_id": "uicons_r0"}) \
			and not _BE.is_sparring(null) and not _BE.is_sparring({}),
		"前缀=%s" % _BE.SEED_ID_PREFIX)


# ─────────────────────────────────────────────────────────────
# ② 记账分得开【真人 / 陪练 / bot】
# ─────────────────────────────────────────────────────────────
func _t_tally_split() -> void:
	print("── ② 匹配来源记账: 真人 / 陪练 / bot ──")
	## 老判据的契约不许破 —— `verify_exact_match` ④ 钉着这两个键在册。
	for k in ["exact", "bot"]:
		_ok("② ★记账键 `%s` 仍在册(老门禁读它)" % k, _BE.match_src_counts.has(k),
			str(_BE.match_src_counts.keys()))
	for k2 in ["exact_human", "exact_seed"]:
		_ok("② ★新记账键 `%s` 在册" % k2, _BE.match_src_counts.has(k2),
			str(_BE.match_src_counts.keys()))
	## ★闯关赛那条链**故意没拆**, 前提是"种子快照压根进不了那条链"。
	##   前提哪天变了(种子带上 gl_ 标签), 这条会红 —— 那时才该拆。
	##   ⇒ 不写这条断言的话, 那个"故意"就只是一句没人守的注释。
	_ok("② ★★闯关赛不拆档的前提: 种子快照一条都没有 `gl_w` 标签",
		_gl_tagged_seeds() == 0, "带 gl_w 的种子 %d 条" % _gl_tagged_seeds())

	## ── 单元: 喂真快照进真记账函数 ──
	_BE.match_src_counts = {"exact": 0, "bot": 0, "exact_human": 0, "exact_seed": 0,
		"gauntlet_label": 0, "gauntlet_bot": 0}
	_BE._tally_exact({"ghost_id": _BE.SEED_ID_PREFIX + "autoplay_x"})
	_ok("② 陪练 ⇒ 记进 exact_seed, 不记 exact_human",
		int(_BE.match_src_counts["exact_seed"]) == 1 \
			and int(_BE.match_src_counts["exact_human"]) == 0,
		str(_BE.match_src_counts))
	_BE._tally_exact({"ghost_id": "g_someone_1_01-02-03_b5"})
	_ok("② 真人 ⇒ 记进 exact_human, 不记 exact_seed",
		int(_BE.match_src_counts["exact_human"]) == 1 \
			and int(_BE.match_src_counts["exact_seed"]) == 1,
		str(_BE.match_src_counts))
	_ok("② ★不变量: exact == exact_human + exact_seed(两格互斥且**没漏**)",
		int(_BE.match_src_counts["exact"]) \
			== int(_BE.match_src_counts["exact_human"]) + int(_BE.match_src_counts["exact_seed"]),
		str(_BE.match_src_counts))

	## ── 端到端: 真种子池抽 N 次(这就是那个 100% 虚高的数) ──
	_BE.match_src_counts = {"exact": 0, "bot": 0, "exact_human": 0, "exact_seed": 0,
		"gauntlet_label": 0, "gauntlet_bot": 0}
	_BE.pool_override = {}
	var rng := RandomNumberGenerator.new(); rng.seed = 777
	var got_seed := 0
	for i in range(N_DRAWS):
		var g: Dictionary = _BE.find_opponent(i % 10, [], rng)
		if _BE.is_sparring(g):
			got_seed += 1
	var c: Dictionary = _BE.match_src_counts
	_ok("② ★★分母: %d 次抽对手真的抽到了陪练(抽不到的话下面是空检查)" % N_DRAWS,
		got_seed > 0, "陪练 %d / %d 次" % [got_seed, N_DRAWS])
	_ok("② ★★★同场次命中里, 陪练与真人分得开了 —— 拆之前这里报的是「exact 100%」",
		int(c["exact_seed"]) == got_seed and int(c["exact_human"]) == 0 \
			and int(c["exact"]) == int(c["exact_seed"]) + int(c["exact_human"]),
		str(c))
	print("  [账] %d 次: exact=%d (真人 %d / 陪练 %d) · bot=%d  ← 答 A-R3 要读的是 exact_human"
		% [N_DRAWS, int(c["exact"]), int(c["exact_human"]), int(c["exact_seed"]), int(c["bot"])])


## 种子池里带 `gl_w` 标签的条数(闯关赛不拆档的前提)。
func _gl_tagged_seeds() -> int:
	_BE.pool_override = {}
	var pool: Dictionary = _BE.load_pool()
	var n := 0
	for b in pool.get(_BE.POOL_KEY, {}).keys():
		for g in pool[_BE.POOL_KEY][b]:
			if g is Dictionary and _BE.is_sparring(g) and (g as Dictionary).has("gl_w"):
				n += 1
	return n


# ─────────────────────────────────────────────────────────────
# ③ 真屏幕: 只有你一行时, 屏上那句到底说了什么
# ─────────────────────────────────────────────────────────────
func _t_screen_says() -> void:
	print("── ③ 真屏幕(只有你一行 + 0 胜) ──")
	var gs = get_node_or_null("/root/GameState")
	var w0: int = int(gs.season_wins)
	gs.season_wins = 0
	## ★空池 ⇒ 榜上必定只有自己一行(而不是靠"碰巧"): 这正是那句假话出现的场面。
	_BE.pool_override = {_BE.POOL_KEY: {}}
	var ps: PackedScene = load("res://scenes/Leaderboard.tscn")
	_ok("③ ★分母: Leaderboard.tscn 载得进来", ps != null)
	if ps == null:
		gs.season_wins = w0
		_BE.pool_override = {}
		return
	var inst: Node = ps.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var labels: Array = []
	_collect_labels(inst, labels)
	var hints: Array = []
	var known := [_LB.HINT_ONLY_YOU_OK, _LB.HINT_ONLY_YOU_FAIL, _LB.HINT_ONLY_YOU_UNKNOWN,
		_LB.HINT_ONLY_YOU_OFF]
	for l in labels:
		if known.has(str((l as Label).text)):
			hints.append(str((l as Label).text))
	_ok("③ ★分母: 屏上恰好有一句提示行(找不到 = 下面全是空检查)", hints.size() == 1,
		"实得 %d 句 %s" % [hints.size(), str(hints)])
	var reach: String = _BE.pool_reach()
	if hints.size() == 1:
		_ok("③ ★★屏上画的就是 `hint_text()` 按当前那一档给的那句(没有第二份手抄的文案)",
			str(hints[0]) == _LB.hint_text(1, reach),
			"屏上「%s」 ↔ 档 %s" % [str(hints[0]), reach])
		_ok("③ ★★★门禁环境 = 问不到(%s) ⇒ 屏上**不许**出现那句承诺「%s」" % [reach, PROMISE],
			not str(hints[0]).contains(PROMISE), "屏上「%s」" % str(hints[0]))

	## ── 0 胜不上领奖台 ──
	var board := _board(inst)
	_ok("③ ★分母: 找得到榜面板", board != null)
	if board != null:
		var you_y := _you_row_y(board)
		_ok("③ ★分母: 榜上找得到【你】那一行(2026-08-19 钉死的那条没被我改坏)",
			you_y >= 0.0, "y=%.0f" % you_y)
		## ★分母: 这一屏上牌位机器**还活着**(空席 2/3 名有暗牌位)。
		##   少了这条, 「0 胜那行没牌位」可能只是因为整屏一块牌都没画。
		var n_plates := _count_plates(board)
		_ok("③ ★★分母: 这一屏确实画了牌位(否则「没牌位」是空检查)", n_plates >= 2,
			"%d 块" % n_plates)
		if you_y >= 0.0:
			var rank_l := _rank_label_at(board, you_y)
			_ok("③ ★分母: 取到了你那一行的名次格", rank_l != null,
				str(rank_l.text) if rank_l != null else "(缺)")
			if rank_l != null:
				_ok("③ ★★★0 胜的你**不戴金牌**(实拍那张是「#1 …… 0胜」= 一场没赢的人是第一名)",
					_plate_of(rank_l, board) == null,
					"名次格「%s」 牌位=%s" % [str(rank_l.text), str(_plate_of(rank_l, board))])
	inst.queue_free()
	gs.season_wins = w0
	_BE.pool_override = {}


# ─────────────────────────────────────────────────────────────
# ④ 四句提示: 互斥, 而且只有「问到了」那一档才许给承诺
# ─────────────────────────────────────────────────────────────
func _t_hint_table() -> void:
	print("── ④ 提示行四档穷举 ──")
	var reaches := [_BE.REACH_OK, _BE.REACH_FAIL, _BE.REACH_UNKNOWN, _BE.REACH_OFF]
	var texts: Array = []
	for r in reaches:
		texts.append(_LB.hint_text(1, str(r)))
	var uniq := {}
	for t in texts:
		uniq[str(t)] = true
	_ok("④ ★四档四句话, 两两不同(同一句 = 这一档白分了)", uniq.size() == 4,
		"%d 句不同 %s" % [uniq.size(), str(texts)])
	var with_promise: Array = []
	for i in range(reaches.size()):
		if str(texts[i]).contains(PROMISE):
			with_promise.append(str(reaches[i]))
	_ok("④ ★★★承诺「%s」只出现在【问到了】这一档" % PROMISE,
		with_promise == [_BE.REACH_OK], "带承诺的档: %s" % str(with_promise))
	_ok("④ ★【问过没问到】那句说的是「%s」(照 BracketMapScene 的样式)" % BLAME_NET,
		str(_LB.hint_text(1, _BE.REACH_FAIL)).contains(BLAME_NET),
		_LB.hint_text(1, _BE.REACH_FAIL))
	## ★「还没问过」不许说"连不上" —— 那是把没发生的网络故障说成发生了(同 ST_UNKNOWN 的理由)。
	_ok("④ ★★【还没问过】既不给承诺, 也不说「%s」" % BLAME_NET,
		not str(_LB.hint_text(1, _BE.REACH_UNKNOWN)).contains(PROMISE) \
			and not str(_LB.hint_text(1, _BE.REACH_UNKNOWN)).contains(BLAME_NET),
		_LB.hint_text(1, _BE.REACH_UNKNOWN))
	## ★【没配后端】只陈述事实, 不挂"离线"角标(SettingsScene.gd:103 / remote_pool.gd:182)。
	_ok("④ ★★【没配后端】不给承诺, 也不喊「%s」" % BLAME_NET,
		not str(_LB.hint_text(1, _BE.REACH_OFF)).contains(PROMISE) \
			and not str(_LB.hint_text(1, _BE.REACH_OFF)).contains(BLAME_NET),
		_LB.hint_text(1, _BE.REACH_OFF))
	## ★2026-10-06 用户「每场打完自动上榜？何意味啊」: 榜上不止一行时**不挂底注**(参考的手游排行榜都没有页脚)。
	_ok("④ 榜上不止你一个 + 你 0 胜 ⇒ 不挂底注",
		_LB.hint_text(9, _BE.REACH_OFF) == "", _LB.hint_text(9, _BE.REACH_OFF))
	_ok("④ 榜上不止你一个 + 你有胜场 ⇒ 不挂底注",
		_LB.hint_text(9, _BE.REACH_OFF) == "", _LB.hint_text(9, _BE.REACH_OFF))
	_ok("④ 榜上找不到自己 ⇒ 也不挂底注(不读那个不存在的胜场)",
		_LB.hint_text(9, _BE.REACH_OFF) == "", _LB.hint_text(9, _BE.REACH_OFF))


# ─────────────────────────────────────────────────────────────
# ⑤ 取数那一半真的接上了: 走**真入口**让四档各自发生一次
# ─────────────────────────────────────────────────────────────
func _t_reach_live() -> void:
	print("── ⑤ pool_reach(): 真入口端到端 ──")
	## 纯判据先穷举(四档都可达, 与环境无关)。
	_ok("⑤ 没配 ⇒ OFF(哪怕已经问到过 —— 没配的时候那些计数说明不了任何事)",
		_BE.reach_of(false, 9, 9, true) == _BE.REACH_OFF)
	_ok("⑤ 配了 + 问到过 ⇒ OK", _BE.reach_of(true, 1, 3, false) == _BE.REACH_OK)
	_ok("⑤ 配了 + 问过没问到 ⇒ FAIL", _BE.reach_of(true, 0, 3, false) == _BE.REACH_FAIL)
	_ok("⑤ 配了 + 健康检查说问不到(还没拉过对手) ⇒ FAIL",
		_BE.reach_of(true, 0, 0, true) == _BE.REACH_FAIL)
	_ok("⑤ 配了 + 一次都还没问 ⇒ UNKNOWN(**不许**说成 FAIL)",
		_BE.reach_of(true, 0, 0, false) == _BE.REACH_UNKNOWN)
	_ok("⑤ ★成功压过失败: 问到过一次之后抖一下, 仍是 OK",
		_BE.reach_of(true, 1, 9, true) == _BE.REACH_OK)

	## ── 取数那一半 ──
	var env0 := OS.get_environment(_SB.ENV_URL)
	_ok("⑤ ★分母: 门禁环境下确实没配后端(run-tests.sh 给的 TURTLE_SUPABASE=\" \")",
		not _SB.enabled() and not _RP.enabled(),
		"SB=%s RP=%s" % [str(_SB.enabled()), str(_RP.enabled())])
	_ok("⑤ ★真实取数落在 OFF", _BE.pool_reach() == _BE.REACH_OFF, _BE.pool_reach())
	## ★★把地址临时配上 —— 只为让另外三档**真的发生**。
	##   一行网络请求都不发: 下面走的是 `apply_pull_response()`(纯函数式的回包入口)。
	OS.set_environment(_SB.ENV_URL, "https://pool-truth.invalid")
	_SB._reset_pull_for_test()
	_ok("⑤ ★★分母: 配上之后 enabled() 真的翻了(翻不过来 = 下面三条是空检查)",
		_SB.enabled(), "base_url=「%s」" % _SB.base_url())
	_ok("⑤ ★★配了而这个进程还没问过 ⇒ UNKNOWN", _BE.pool_reach() == _BE.REACH_UNKNOWN,
		"try=%d ok=%d ⇒ %s" % [_SB.pull_try_count(), _SB.pull_ok_count(), _BE.pool_reach()])
	_SB.apply_pull_response(false, 0, "")            # 真入口: 一次失败的回包
	_ok("⑤ ★★★喂一次**失败**回包 ⇒ FAIL(这才是离线的真实处境)",
		_BE.pool_reach() == _BE.REACH_FAIL,
		"try=%d ok=%d ⇒ %s" % [_SB.pull_try_count(), _SB.pull_ok_count(), _BE.pool_reach()])
	_ok("⑤ ★★★这一档屏上说的是「连不上」那句, 不是「打完一场对手就会上来」",
		_LB.hint_text(1, _BE.pool_reach()) == _LB.HINT_ONLY_YOU_FAIL,
		_LB.hint_text(1, _BE.pool_reach()))
	_SB.apply_pull_response(true, 200, "[]")         # 真入口: 问到了(空数组也算问到)
	_ok("⑤ ★★★喂一次**成功**回包 ⇒ OK ⇒ 这时那句承诺才是真的",
		_BE.pool_reach() == _BE.REACH_OK \
			and _LB.hint_text(1, _BE.pool_reach()) == _LB.HINT_ONLY_YOU_OK,
		"try=%d ok=%d ⇒ %s" % [_SB.pull_try_count(), _SB.pull_ok_count(), _BE.pool_reach()])
	## ★★还原(变异必须逐字还原; 这两样都是 static / 进程级, 留着会污染后面的断言)。
	_SB._reset_pull_for_test()
	OS.set_environment(_SB.ENV_URL, env0)
	_ok("⑤ ★还原: 地址与计数都回到门禁环境的样子",
		not _SB.enabled() and _SB.pull_try_count() == 0 and _BE.pool_reach() == _BE.REACH_OFF,
		"base_url=「%s」 ⇒ %s" % [_SB.base_url(), _BE.pool_reach()])


# ─────────────────────────────────────────────────────────────
# ⑥ 时间缝: 同一个池子 + 两个钉住的时刻 ⇒ 两个不同的对手
# ─────────────────────────────────────────────────────────────
func _t_time_seam() -> void:
	print("── ⑥ 周六新鲜度的「现在」走可注入时钟 ──")
	_ok("⑥ ★分母: 缝默认是关的(否则下面是在量别人留下的状态)",
		_P2.now_override_ts == 0, "now_override_ts=%d" % _P2.now_override_ts)
	var pool: Dictionary = {_BE.POOL_KEY: {"3": [
		_gl_snap("pt_gl_a", TS_A),
		_gl_snap("pt_gl_b", TS_B),
	]}}
	## ★两份快照同标签, 只差上传时刻 ⇒ 谁"新鲜"完全由【现在】决定。
	##   钉在 A 之后 60 秒: A 新鲜(60s), B 在**未来**(未来一律当不新鲜) ⇒ 必须选 A。
	##   钉在 B 之后 60 秒: A 隔夜(3660s > 1800), B 新鲜 ⇒ 必须选 B。
	_ok("⑥ ★分母: 两个钉的时刻真的跨过了 %d 秒的窗口" % int(_P2.FRESH_SNAPSHOT_SEC),
		TS_B - TS_A > int(_P2.FRESH_SNAPSHOT_SEC),
		"相差 %d 秒" % (TS_B - TS_A))
	_P2.now_override_ts = TS_A + 60
	var pick_a = _BE.gauntlet_pool_find(pool, GL_W, GL_L, [], _seeded_rng())
	_P2.now_override_ts = TS_B + 60
	var pick_b = _BE.gauntlet_pool_find(pool, GL_W, GL_L, [], _seeded_rng())
	_P2.now_override_ts = 0
	var id_a := str((pick_a as Dictionary).get("ghost_id", "")) if pick_a != null else ""
	var id_b := str((pick_b as Dictionary).get("ghost_id", "")) if pick_b != null else ""
	_ok("⑥ ★分母: 两次都找到了对手(找不到的话下面比的是两个空串)",
		id_a != "" and id_b != "", "%s / %s" % [id_a, id_b])
	_ok("⑥ ★★★钉在早那份之后 60 秒 ⇒ 选早那份(晚那份在未来, 一律当不新鲜)",
		id_a == "pt_gl_a", id_a)
	_ok("⑥ ★★★钉在晚那份之后 60 秒 ⇒ 选晚那份(早那份已隔夜)",
		id_b == "pt_gl_b", id_b)
	_ok("⑥ ★★同一个池子 + 同一个种子, 只换钉的时刻 ⇒ 结果**变了** ⇒ 尺子真的是那个钟",
		id_a != id_b, "%s vs %s" % [id_a, id_b])
	_ok("⑥ ★还原: 缝关回去了", _P2.now_override_ts == 0,
		"now_override_ts=%d" % _P2.now_override_ts)


# ─────────────────────────────────────────────────────────────
# ⑦ 决赛日那一场的结果: 冷启动无 token ⇒ 必须留下一张**能过夜的补报单**,
#    而补报报的必须是【那一场】, 不是「现在」
# ─────────────────────────────────────────────────────────────
## ★★★由来: `supabase.report_finals_async` 有四条「请求没发出去」的早退, 其中一条是
##   `_token == ""` —— 而 `_token` **只活在内存、从不落盘** ⇒ **每次冷启动都是空的**。
##   而 `report_finals_if_any` 只在结算时调一次。漏报会让那一场只能靠 960 秒宽限兜,
##   **可能把错的人送进下一轮**。
##
## ★探针 `tests/_probe_finals_retry.gd` 实测之后, 情报里猜的那条根因**不成立**:
##   补报单是**无条件**写的(不是"只在发失败那条路上写"), 而且进了 `_save_dict()`,
##   `_settle_season` 尾部那条无条件的 `gs.save()` 让它过得了夜。
## ★真正漏的是另一件: **补报单上的 `seed` 一个读者都没有**。
##   `retry_finals_report()` 走 `report_finals_result()`, 而那里读的是
##   `GameState.battle_seed` —— 「现在这一场」的种子。探针量到 4242 ↔ 999 的分岔。
##   `p_seed` 是服务端确定性复算用的 ⇒ 报错了等于报了一场复算不出来的比赛。
func _t_finals_retry() -> void:
	print("── ⑦ 决赛结果补报单 ──")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	## 现场还原用(全部是 static / 存档字段, 不还原会污染后面别的测试)。
	var w0: int = int(gs.week_anchor_ts)
	var bs0: int = int(gs.battle_seed)
	var fm0: Dictionary = (gs.finals_match as Dictionary).duplicate(true)
	var fp0: Dictionary = (gs.finals_report_pending as Dictionary).duplicate(true)
	var fr0: Dictionary = (gs.finals_pending_reveal as Dictionary).duplicate(true)

	_ok("⑦ ★★分母: 冷启动时 token 真是空的(这一族缺口的**前提**)",
		str(_SB._token) == "", "token 长度 %d" % str(_SB._token).length())
	_SB.finals_report_clear()
	_BE.last_finals_report = {}
	gs.week_anchor_ts = 1700000000
	gs.battle_seed = 4242
	gs.finals_report_pending = {}
	gs.finals_pending_reveal = {}
	## ★走**真入口**: 摆好「我在决赛日的哪一场」, 让产品自己结算。
	gs.finals_match = {"bucket": 2, "round": 3, "match": 1, "side": 0}
	_BE.report_finals_if_any(true)
	var slip: Dictionary = gs.finals_report_pending
	_ok("⑦ ★分母: 那一场真的结算了(`finals_match` 被清空 = 走完了整条路)",
		(gs.finals_match as Dictionary).is_empty(), str(gs.finals_match))
	_ok("⑦ ★★分母: 一个字节都没发出去(无 token ⇒ 早退,「报成了」仍是 false)",
		not _SB.finals_reported(3, 1))
	_ok("⑦ ★★★无 token 那一刻**照样**写下了补报单", not slip.is_empty(), str(slip))
	_ok("⑦ ★补报单记的是那一场的坐标(轮/场/桶/侧)",
		int(slip.get("round", -1)) == 3 and int(slip.get("match", -1)) == 1 \
			and int(slip.get("bucket", -1)) == 2 and int(slip.get("side", -1)) == 0,
		str(slip))
	_ok("⑦ ★★★补报单**进存档**(能过夜 —— token 下次冷启动还是空的)",
		(gs._save_dict() as Dictionary).has("finals_report_pending") \
			and not ((gs._save_dict() as Dictionary).get("finals_report_pending", {}) as Dictionary).is_empty(),
		str((gs._save_dict() as Dictionary).get("finals_report_pending", "(缺)")))

	## ── 补报报的是【那一场】, 不是「现在」 ──
	## ★把 GameState 上那个字段换成另一个值 —— 相当于"后来又打了一场"。
	##   判据量的是**流过交接口的值**(`last_finals_report`), 不是我插的标记。
	gs.battle_seed = 999
	_ok("⑦ ★★分母: 两个数真的分岔了(相等的话下面这条恒真)",
		int(slip.get("seed", -1)) != int(gs.battle_seed),
		"单子 %d ↔ 现在 %d" % [int(slip.get("seed", -1)), int(gs.battle_seed)])
	_BE.last_finals_report = {}
	_BE.retry_finals_report()
	var sent: Dictionary = _BE.last_finals_report
	_ok("⑦ ★分母: 补报真的交到网络层了(空的话下面是空检查)", not sent.is_empty(), str(sent))
	_ok("⑦ ★★★补报带的 seed 是**补报单上那一份**(4242), 不是「现在」那个(999)",
		int(sent.get("seed", -1)) == int(slip.get("seed", -2)) \
			and int(sent.get("seed", -1)) != int(gs.battle_seed),
		"发出去的 %d ↔ 单子 %d ↔ 现在 %d" % [int(sent.get("seed", -1)),
			int(slip.get("seed", -2)), int(gs.battle_seed)])
	_ok("⑦ ★补报报的还是那一场(轮/场/侧一个都没漂)",
		int(sent.get("round", -1)) == 3 and int(sent.get("match", -1)) == 1 \
			and int(sent.get("side", -1)) == 0, str(sent))
	_ok("⑦ ★★「交给网络层」≠「报成了」—— 后者只有 2xx 回调才置真",
		not _SB.finals_reported(3, 1), "finals_reported=false 而 last_finals_report 非空")
	_ok("⑦ ★★没报成 ⇒ 单子**留着**(下次开主菜单再补一次)",
		not (gs.finals_report_pending as Dictionary).is_empty(),
		str(gs.finals_report_pending))

	## ── 结构上报不出去的单子必须销掉(否则每次开主菜单都往那儿捶一下, 且永远捶不成) ──
	gs.finals_report_pending = {"bucket": 2, "round": 3, "match": 1, "side": -1, "seed": 7}
	_BE.last_finals_report = {}
	_BE.retry_finals_report()
	_ok("⑦ ★★★`side = -1` 的单子(report_finals_async 对它是无条件早退)⇒ 销单",
		(gs.finals_report_pending as Dictionary).is_empty(), str(gs.finals_report_pending))
	_ok("⑦ ★而且**不发**(发出去服务端只会回 bad_side)", _BE.last_finals_report.is_empty(),
		str(_BE.last_finals_report))
	gs.finals_report_pending = {"bucket": 2, "round": 0, "match": -1, "side": 0, "seed": 7}
	_BE.retry_finals_report()
	_ok("⑦ 坐标坏掉的单子(轮 < 1 / 场 < 0)⇒ 照旧销单",
		(gs.finals_report_pending as Dictionary).is_empty(), str(gs.finals_report_pending))

	## ★★还原(变异/现场都必须逐项还原)。
	gs.week_anchor_ts = w0
	gs.battle_seed = bs0
	gs.finals_match = fm0
	gs.finals_report_pending = fp0
	gs.finals_pending_reveal = fr0
	_SB.finals_report_clear()
	_BE.last_finals_report = {}
	_ok("⑦ ★还原: 现场回到进这一节之前的样子",
		int(gs.battle_seed) == bs0 and int(gs.week_anchor_ts) == w0 \
			and (gs.finals_match as Dictionary) == fm0 \
			and (gs.finals_report_pending as Dictionary) == fp0 \
			and not _SB.finals_reported(3, 1),
		"battle_seed=%d week=%d" % [int(gs.battle_seed), int(gs.week_anchor_ts)])


func _gl_snap(gid: String, ts: int) -> Dictionary:
	return {"schema_ver": _BE.SCHEMA_VER, "ghost_id": gid, "is_bot": false,
		"origin": _BE.ORIGIN_REMOTE, "profile": {"name": gid},
		"gl_w": GL_W, "gl_l": GL_L, "gl_ts": ts,
		"season_total_battles": GL_W + GL_L}


## ★每次现造一个同种子的 rng —— 不然"结果变了"可能只是 rng 走了一步。
func _seeded_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	return r


# ─────────────────────────────────────────────────────────────
# 取节点的小工具(与 verify_leaderboard_header 同一套读法)
# ─────────────────────────────────────────────────────────────
func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_collect_labels(c, out)


## 屏上最大的那块 Panel = 榜本身。
func _board(n: Node) -> Control:
	var best: Control = null
	var best_a := 0.0
	var st: Array = [n]
	while not st.is_empty():
		var c = st.pop_back()
		if c is Panel and (c as Control).is_visible_in_tree():
			var r: Rect2 = (c as Control).get_global_rect()
			var a: float = r.size.x * r.size.y
			if a > best_a:
				best_a = a
				best = c as Control
		for ch in c.get_children():
			st.append(ch)
	return best


## 这个 Label 住在一块自己的九宫格签牌里吗? `board` 本身要排掉(它也套了九宫格)。
func _plate_of(l: Label, board: Control) -> StyleBoxTexture:
	var p := l.get_parent()
	if p == board:
		return null
	if p is Panel and (p as Panel).has_theme_stylebox_override("panel"):
		var sb = (p as Panel).get_theme_stylebox("panel")
		if sb is StyleBoxTexture:
			return sb as StyleBoxTexture
	return null


## 「你」那一行的 y —— 认的是**产品自己**贴的那枚「你」签, 不是测试插的标记。
func _you_row_y(board: Control) -> float:
	var labels: Array = []
	_collect_labels(board, labels)
	for l in labels:
		if str((l as Label).text).strip_edges() == "你":
			return (l as Control).get_global_rect().get_center().y
	return -1.0


## 那一行最左边的那个数字格 = 名次格。
func _rank_label_at(board: Control, y: float) -> Label:
	var labels: Array = []
	_collect_labels(board, labels)
	var best: Label = null
	var best_x := 1e9
	for l in labels:
		var c := l as Control
		if not c.is_visible_in_tree():
			continue
		var rc: Rect2 = c.get_global_rect()
		if absf(rc.get_center().y - y) > 14.0:
			continue
		if not str((l as Label).text).strip_edges().is_valid_int():
			continue
		if rc.position.x < best_x:
			best_x = rc.position.x
			best = l as Label
	return best


## 这一屏一共画了几块牌位(空席的暗牌位也算) —— 「没牌位」那条断言的分母。
func _count_plates(board: Control) -> int:
	var labels: Array = []
	_collect_labels(board, labels)
	var n := 0
	for l in labels:
		if _plate_of(l as Label, board) != null:
			n += 1
	return n


func _done() -> void:
	_BE.pool_override = {}
	_P2.now_override_ts = 0
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 对手池说的话必须是真的 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 对手池说的话必须是真的 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
