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
## ★★① `battles` 窗口是 **(N-1, N, N+1)**，而且判据量的是「**以 N 为中心**」不是字面串。
##    · 为什么要开三格：只拉 N 会让一类玩家的池子永远空 ——
##      `_settle_season` 里 `season_total_battles += 1` 在【非表演赛】分支里 ⇒
##      **0 命玩家打表演赛时场次不涨**，卡在同一个数反复打。
##    · 为什么必须**对称**（2026-09-25 用户原话：「我的档是 5 场次的，我要和 6 场次的
##      人打？这不合理啊」）：原来是 `(N, N+1)`，往上开一格往下不开 ⇒ 每个人都只可能
##      碰到和自己一样多、或比自己多打过一场的对手。多打一场 = 多一轮升级 + 多一次装备，
##      所以那一格是**系统性偏向对手**，没有一个人一辈子占过它的便宜。
##    · 为什么不能只断言字面 `"(4,5,6)"`：把窗口写成 `(5,6,7)` 也是三格宽、也含 N，
##      正是上面那种偏心错。⇒ 判据量【各格相对 N 的偏移之和】，对称 ⟺ 和为 0。
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
const _P2P := preload("res://scripts/gamedata/phase2_config.gd")
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


## 从查询串里把 `battles=in.(a,b,c)` 那几个数抠出来(升序)。
## ★存在的理由: 拿**字面串**比守不住「窗口偏心」那个形状(见 ① 里的长注释)。
##   判据要落在「这几个数相对 N 摆在哪」, 所以得先把数拿出来。
func _battles_window(q: String) -> Array:
	var out: Array = []
	var i := q.find("battles=in.(")
	if i < 0:
		return out
	var j := q.find(")", i)
	if j < 0:
		return out
	for s in q.substr(i + 12, j - i - 12).split(","):
		out.append(int(s))
	out.sort()
	return out


# ─────────────────────────────────────────────────────────────
# ① 查询串: 三维齐才拼, 缺一就不拉
# ─────────────────────────────────────────────────────────────
func _t_query() -> void:
	print("── ① 查询串(三维缺一就不拉) ──")
	var q := SB.opponents_query(1789948800, 5, "uid-me")
	_chk("① ★分母: 三维齐全时确实拼出了查询串(否则下面全是空检查)", q != "", q)
	_chk("① 周锚点进去了", q.contains("season_week=eq.1789948800"))
	## ★★★2026-09-26 这一段整段翻正。上一版断言的是「窗口各格相对 N 的偏移之和 = 0」
	##   (即上下对称 `(N-1, N, N+1)`), 而那条判据**是错的**:
	##
	##   D5(`docs/plans/20260916-大轮赛制v2周赛制.md:349`, 2026-09-16 拍板) 说的是
	##   「硬条件是**双方总场次相同**(不再按 9 档)」, 用户 2026-09-26 复述:
	##   「从始至终应该都是同场次的人开打…**不应该有什么正负一**」。
	##   我 09-25 把用户那句「我的档是 5 场次的, 我要和 6 场次的人打? 这不合理啊」
	##   读成了「窗口不对称」(于是去补下面那一格), 而他说的是「**不该有差**」。
	##   ⇒ 那条对称判据**保证了**「5 场次打 6 场次」这件事不会被发现。
	##
	## ★★现在这个窗口的身份变了: 它是**纯预取**, 不再是任何匹配判据
	##   (选靶那一侧只认完全相同, 见 `Backend.pool_find_battles`;
	##    `tools/nine_bracket_audit.py` 专门守「find_opponent 里不许出现 span」)。
	##   ⇒ 预取该往哪开就一目了然了: **我现在 N 场, 打完这局就是 N+1 场**
	##     ⇒ 往前开是给下一局暖池子; 而 N-1 我**永远回不去**, 拉回来一条都匹配不上
	##     ⇒ 往下开纯粹白占 PULL_LIMIT 的名额, 把真正有用的那一格挤掉。
	_chk("① ★★场次窗口 = [N, N+AHEAD](只往前开; 往下开的那一格永远匹配不上)",
		q.contains("battles=in.(5,6)"), q)

	## ★判据量【窗口相对 N 的两端】, 不是字面串 —— 只断言 "(5,6)" 挡不住把它
	##   写成 (4,5) 这种同样两格宽、同样含 N 的形状。
	var AHEAD: int = int(_P2P.PULL_BATTLES_AHEAD)
	for nn in [3, 5, 9, 40]:
		var ws := _battles_window(SB.opponents_query(1789948800, nn, "uid-me"))
		var lo_off: int = (int(ws[0]) - nn) if not ws.is_empty() else 999
		var hi_off: int = (int(ws[ws.size() - 1]) - nn) if not ws.is_empty() else 999
		_chk("① ★★★N=%d 窗口下界 == N(一格都不往下开; 实测偏移 %d, 窗口 %s)"
			% [nn, lo_off, str(ws)], lo_off == 0, str(ws))
		_chk("① ★★N=%d 窗口上界 == N+%d(预取下一局那一格; 实测偏移 %d)"
			% [nn, AHEAD, hi_off], hi_off == AHEAD, str(ws))
	## N=0(赛季第一场): 往下钳到 0。不许拼出 `battles=-1` —— PostgREST 会把它
	## 当一个合法值算, 于是那一格恒查不到, 而**第一场是人人都要打的**。
	var w0 := _battles_window(SB.opponents_query(1789948800, 0, "uid-me"))
	_chk("① ★N=0 时窗口不含负数(否则第一场的池子被白占一格)",
		w0.size() >= 2 and int(w0.min()) >= 0, str(w0))
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
	## ★★2026-09-25: 入参是**场次**不是粗格子。原来这里写的是
	##   `find_opponent(bracket_for_battles(11), …)` ⇒ 传进去的是 **4**(格子号),
	##   于是窗口中心变成 4 而不是 11。不要再把 `bracket_for_battles` 加回来。
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
	var g = BE.find_opponent(11, [], rng)

	## ★★判据落在「它拿哪三维去问的」，不是「它调没调」——
	##   后者是插一行数一行必绿(memory `fb-gate-must-measure-requirement-not-my-hook`)。
	var q := SB.last_query()
	_chk("④ ★★匹配真的发起了拉取(查询串非空)", q != "", q)
	## ★判据落在窗口的**中心**, 不是「11 出现在窗口里」—— 后者挡不住差一格:
	##   要是它拿 12 去问, 窗口就是 (11,12,13), 照样"含 11"而实际问错了人。
	var w4 := _battles_window(q)
	## ★★判据落在窗口的**下界**: 下界就是选靶自己用的那个数。
	##   要是它拿 12 去问, 窗口变成 (12,13) ⇒ 下界 12 ≠ 11, 当场红。
	##   (2026-09-26: 窗口从三格对称改成两格只往前, 所以这里量的是下界而不是中心。)
	_chk("④ ★★场次那一维 = 【选靶自己用的那个数】(窗口下界必须是 11, 实测 %s)" % str(w4),
		w4.size() == int(_P2P.PULL_BATTLES_AHEAD) + 1 and int(w4[0]) == 11, q)
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
	BE.find_opponent(11, [], rng)
	_chk("④ ★★没登录时【一个字都不问】(空 account_id 会让服务端把自己也返回来)",
		SB.last_query() == "", SB.last_query())

	OS.set_environment(ENV_URL, env_bak)
	_chk("★收尾: 后端地址已还原(不还原会波及同进程后面的用例)",
		OS.get_environment(ENV_URL) == env_bak)
	await get_tree().process_frame
