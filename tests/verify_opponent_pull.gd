extends Node
## verify_opponent_pull.gd — D-4b：匹配从 Supabase 拉【同周 + 同场次】的对手（2026-09-21）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## D5 拍板的匹配硬条件是**双方总场次相同**；D 方案书 §D-4b 补的是
## 「同一周 + 同场次 → 倒序最新 → **排除自己按 `account_id`**」。
##
## ★★**匹配路径一行网络代码都不许有**：这次拉取填的是【下一局】的池子，
##   本局对手在 `find_opponent()` 里用现有本地池算出来，一步都不等网络。
##   断网时整层是 no-op —— 「离线不退化」这条硬指标的落点。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 查询串是**纯函数**拼出来的 ⇒ 每一维都能逐条喂。三维缺一律返回 ""（不拉），
##    不拿 0 / 空串凑一个发出去：`account_id=neq.` 后面空着的话 PostgREST
##    会拿它当合法过滤器算，结果是**把自己也拉回来**。
## ★★① `battles` 必须同时含 **N 和 N+1**。只拉 N+1 会让一类玩家的池子永远是空的：
##    `_settle_season` 里 `season_total_battles += 1` 在【非表演赛】分支里 ⇒
##    **0 命玩家打表演赛时场次不涨**，卡在同一个数反复打。
## ★② 回包外层是**行** `[{"snapshot": {...}}]` 不是快照。直接把行喂给 `ingest_remote`
##    的话每条都会被 `snapshot_valid` 以「缺 ghost_id」拒掉 —— 那看起来像「服务端没数据」。
## ★★③ 脏数据必须被拒且**记进账**。这不是假想：`ghosts` 表**故意没给 delete 策略**
##    （防「打不过就把自己撤下来」），2026-09-21 验 upsert 时写进去的探针行删不掉、还在库里。
## ★★④ **走真入口** `Backend.find_opponent()`，判据落在
##    「**它拿哪三维去问的**」而不是「它调没调」——「调没调」是插一行数一行必绿。
##    ★场次那一维必须等于**选靶自己用的那个数**，不是我另算一遍喂给它的。
## ★⚠ 网络那一段门禁验不到（进程里后端指向 `127.0.0.1:9`）。真往返是
##    2026-09-21 用 `tests/_probe_d4b.gd` 打真 Supabase 验的：
##    A 传 → **A 自己拉 total=0**（排除自己）／**B 拉 total=1 added=1**（同周同场次只差账号）。
##    ③ 单独看是恒真式（「挡住了」和「库里没东西」都返回空）—— 是 ④ 让它成立。

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const RP := preload("res://scripts/net/remote_pool.gd")

## ★不可达地址：端口 9 是 discard，必定连不上 ⇒ 「启用了但打不通」，
##   正是要测的形状。这一招 `verify_remote_pool` 已经用了，照抄口径。
const DEAD_URL := "http://127.0.0.1:9"
const ENV_URL := "TURTLE_SUPABASE"

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}
const KEYS := ["account_id", "week_anchor_ts", "season_total_battles", "season_id",
	"season_leaders", "left_team", "hearts", "week_phase", "lane_results"]


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== D-4b 匹配拉取 ===")
	_t_query()
	_t_parse()
	_t_ingest()
	await _t_real_entry()
	for k in KEYS:
		GameState.set(k, _bak[k])
	SB._reset_pull_for_test()
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-4b 匹配拉取" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 查询串: 三维齐才拼, 缺一就不拉
# ─────────────────────────────────────────────────────────────
func _t_query() -> void:
	print("── ① 查询串(三维缺一就不拉) ──")
	var q := SB.opponents_query(1789948800, 5, "uid-me")
	_chk("① ★分母: 三维齐全时确实拼出了查询串(否则下面全是空检查)", q != "", q)
	_chk("① 周锚点进去了", q.contains("season_week=eq.1789948800"))
	_chk("① ★★场次【同时含 N 和 N+1】(只拉 N+1 会让 0 命表演赛玩家池子永远空)",
		q.contains("battles=in.(5,6)"), q)
	_chk("① ★排除自己是按 account_id(不是按 ghost_id 前缀)",
		q.contains("account_id=neq.uid-me"))
	_chk("① 按上传时刻倒序(D10: 新鲜度是排序不是过滤)", q.contains("order=uploaded_at.desc"))
	_chk("① 有上限(不许无限拉)", q.contains("limit=%d" % SB.PULL_LIMIT))
	_chk("① 只要快照那一列(其余列客户端用不着)", q.contains("select=snapshot"))

	var bads := [
		["缺 account_id", SB.opponents_query(1789948800, 5, "")],
		["缺周锚点(0)", SB.opponents_query(0, 5, "uid-me")],
		["周锚点为负", SB.opponents_query(-1, 5, "uid-me")],
		["场次为负(还没打过)", SB.opponents_query(1789948800, -1, "uid-me")],
	]
	var leaked := 0
	for b in bads:
		if str(b[1]) != "":
			leaked += 1
		_chk("① %s → 返回空(不拉)" % str(b[0]), str(b[1]) == "", str(b[1]))
	_chk("① ★★四种缺前提一个都没凑出查询(凑了会把【自己】也拉回来)",
		leaked == 0, "违例 %d/4" % leaked)


# ─────────────────────────────────────────────────────────────
# ② 回包解析: 外层是【行】不是快照
# ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ② 回包解析(外层是行不是快照) ──")
	var body := '[{"snapshot":{"ghost_id":"g_a","leaders":["basic"]}},' \
		+ '{"snapshot":{"ghost_id":"g_b","leaders":["ice"]}}]'
	var out: Array = SB.snapshots_from_body(body)
	_chk("② ★分母: 两行确实解析出两份", out.size() == 2, str(out.size()))
	_chk("② ★★抽出来的是【快照】不是【行】(直接喂行的话每条都会被判「缺 ghost_id」)",
		out.size() == 2 and (out[0] as Dictionary).has("ghost_id")
		and not (out[0] as Dictionary).has("snapshot"), str(out))

	var junk := [
		["空正文", SB.snapshots_from_body("")],
		["不是 JSON", SB.snapshots_from_body("<html>502</html>")],
		["是对象不是数组(PostgREST 报错时的形状)", SB.snapshots_from_body('{"message":"boom"}')],
		["行里没有 snapshot 键", SB.snapshots_from_body('[{"account_id":"x"}]')],
		["snapshot 是空字典", SB.snapshots_from_body('[{"snapshot":{}}]')],
		["snapshot 不是字典", SB.snapshots_from_body('[{"snapshot":"哈"}]')],
	]
	for j in junk:
		_chk("② %s → 空数组" % str(j[0]), (j[1] as Array).is_empty(), str(j[1]))


# ─────────────────────────────────────────────────────────────
# ③ 并池: 脏数据要被拒【并且记账】
# ─────────────────────────────────────────────────────────────
func _good_snap(gid: String) -> Dictionary:
	return {
		"schema_ver": BE.SCHEMA_VER, "ghost_id": gid, "is_bot": false, "bracket": 3,
		"profile": {"name": "别人", "avatar": "basic", "id": gid},
		"leaders": ["basic", "stone", "ice"], "lane_assign": {}, "minions": {},
		"loadouts": {}, "equipped": {}, "pet_levels": {"basic": 3},
		"season_total_battles": 5, "season_eggs_killed": 1,
		"season_wins": 2, "hearts": 6, "season_sweeps": 0,
	}


func _t_ingest() -> void:
	print("── ③ 并池(脏数据要被拒并记账) ──")
	SB._reset_pull_for_test()
	var good := JSON.stringify([{"snapshot": _good_snap("g_other_1")}])

	_chk("③ HTTP 500 → 不入池", int(SB.apply_pull_response(true, 500, good).get("added", -1)) == 0)
	_chk("③ 传输失败 → 不入池", int(SB.apply_pull_response(false, 0, good).get("added", -1)) == 0)
	_chk("③ ★分母: 失败两次都记进了 try, 但一次都没记 ok",
		SB.pull_try_count() == 2 and SB.pull_ok_count() == 0,
		"try=%d ok=%d" % [SB.pull_try_count(), SB.pull_ok_count()])

	var st1: Dictionary = SB.apply_pull_response(true, 200, good)
	_chk("③ ★★合法快照入池", int(st1.get("added", -1)) == 1 and int(st1.get("total", -1)) == 1,
		str(st1))

	## ★这就是库里真实存在的那种脏数据: `{"probe": "..."}` —— 没 schema_ver 没 ghost_id。
	##   `ghosts` 表故意没给 delete 策略 ⇒ 2026-09-21 验 upsert 时写进去的行删不掉。
	var dirty := JSON.stringify([
		{"snapshot": {"probe": "d4a-second"}},
		{"snapshot": _good_snap("g_other_2")},
	])
	var st2: Dictionary = SB.apply_pull_response(true, 200, dirty)
	_chk("③ ★★脏行被拒、干净行照进(库里真有这种行, 见上面注释)",
		int(st2.get("total", -1)) == 2 and int(st2.get("added", -1)) == 1
		and int(st2.get("rejected", -1)) == 1, str(st2))
	_chk("③ ★拒的理由**记下来了**(静默丢弃 = 假装同步成功而池子一条没进)",
		not (st2.get("reasons", []) as Array).is_empty(), str(st2.get("reasons", [])))
	_chk("③ ★分母: 两次 2xx 都记进了 ok(上面两次失败没混进来)", SB.pull_ok_count() == 2,
		"ok=%d" % SB.pull_ok_count())


# ─────────────────────────────────────────────────────────────
# ④ ★★走真入口: find_opponent 拿哪三维去问的
# ─────────────────────────────────────────────────────────────
func _t_real_entry() -> void:
	print("── ④ 走真入口 Backend.find_opponent() ──")
	var env_bak := OS.get_environment(ENV_URL)
	OS.set_environment(ENV_URL, DEAD_URL)
	_chk("④ ★分母: 这一段里后端是【启用】的(停用的话下面全是空检查)", SB.enabled(),
		"url=%s" % SB.base_url())

	SB._reset_pull_for_test()
	_chk("④ ★分母: 查询串现在是空的(否则读到的是别处留下的)", SB.last_query() == "")

	GameState.account_id = "uid-me-4"
	GameState.week_anchor_ts = 1789948800
	GameState.season_total_battles = 11
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var g = BE.find_opponent(BE.bracket_for_battles(11), [], rng)

	## ★★判据落在「它拿哪三维去问的」，不是「它调没调」——
	##   后者是插一行数一行必绿(memory `fb-gate-must-measure-requirement-not-my-hook`)。
	var q := SB.last_query()
	_chk("④ ★★匹配真的发起了拉取(查询串非空)", q != "", q)
	_chk("④ ★★场次那一维 = 【选靶自己用的那个数】(11, 不是我另算一遍喂进去的)",
		q.contains("battles=in.(11,12)"), q)
	_chk("④ 周锚点那一维取的是 week_anchor_ts(与上传同一口径)",
		q.contains("season_week=eq.1789948800"), q)
	_chk("④ 身份那一维取的是 account_id", q.contains("account_id=neq.uid-me-4"), q)
	## ★匹配本身不许被网络影响: 打不通也要照样给出对手(bot 是永久安全网)。
	_chk("④ ★★打不通的时候匹配照样给得出对手(离线不退化)",
		g is Dictionary and not (g as Dictionary).is_empty(),
		"对手 id=%s" % str((g as Dictionary).get("ghost_id", "?")) if g is Dictionary else "null")

	## ★没登录就不该问。这条挡的是「`account_id=neq.` 后面空着 ⇒ 把自己也拉回来」。
	SB._reset_pull_for_test()
	GameState.account_id = ""
	BE.find_opponent(BE.bracket_for_battles(11), [], rng)
	_chk("④ ★★没登录时【一个字都不问】(空 account_id 会让服务端把自己也返回来)",
		SB.last_query() == "", SB.last_query())

	OS.set_environment(ENV_URL, env_bak)
	_chk("★收尾: 后端地址已还原(不还原会波及同进程后面的用例)",
		OS.get_environment(ENV_URL) == env_bak)
	await get_tree().process_frame
