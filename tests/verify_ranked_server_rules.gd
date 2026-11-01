extends Node
## verify_ranked_server_rules.gd — 积分赛交给服务器: 服务端的规则 = 本机老规则(同输入同输出)。
## 方案书 docs/plans/20261101c-积分赛服务器裁判.md §6(验收 V1 / V2 / V5)。
##
## A 结算表对账: 读服务端检查脚本 `server/supabase/tests/20261101d_ranked_referee_check.sql` 里那张 RANKED_SETTLE_CASES 表
##   (同一张表在 PGlite 里喂 referee_complete, 逐格相等才 ALL PASS) ——
##   A1 每一行拿**本机老结算** `RealtimeBattle3DScene._settle_season` 真跑一遍(真战斗场脚本实例、真 GameState、齿轮铸币写进
##      `_equip_tick_sys`), 命 / 胜 / 横扫 / 碎蛋 / 场次 / 配额 / 这一局的币逐格 = 表 ⇒ 表就是老规则;
##   A2 同一个开局状态再走**新客户端记账** `RefereeWatch.settle_ranked`(喂服务端会回的那份账本 = 表的输出列),
##      本机存档里每一项(含账本以外的大轮经验 / 等级 / 糖果罐 / 096 砍伐 / 战绩页 / 总场次)与 A1 逐项相等 ⇒ 换成服务器记账,
##      玩家存档的变化与老结算一字不差。
## B 常量 / 形参对账(读迁移 20261101d 的文本): 命上限 / 配额 / 封盘秒数 / 收盘时刻 / 积分赛星期几 / 币公式 / 选靶只认同场次 /
##   开战形参 = 客户端请求体键 / 开关键名 / 账本键名 / 任务种类。
## C 对手池生成(bot_pool.gd generate_ranked): 两遍逐字节相同; 陪练 = 客户端池子里那 396 份(seed_as_human 同一个函数)、
##   机器人 = make_bot(场次) 同一个函数; 都摘了 origin、场次自洽、不带周六标签。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const BE := preload("res://scripts/net/backend.gd")
const CHECK_SQL := "res://server/supabase/tests/20261101d_ranked_referee_check.sql"
const MIG_SQL := "res://server/supabase/migrations/20261101d_ranked_referee.sql"
const MID := "7d2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

## 存档里这一局会动到的每一项(A2 逐项比)。
const FIELDS := ["hearts", "season_wins", "season_total_battles", "ranked_used", "season_sweeps", "season_eggs_killed",
	"meta_deepsea_coins", "season_xp", "season_level", "candy_jar_count", "axe_exp_total", "axe_exp_bar", "axe_stage",
	"battles_total", "battles_won"]

var _fail := 0
var _n := 0
var _gs
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	for k in FIELDS + ["match_history", "titles", "season_leaders", "left_team", "persistent_bench", "lane_results",
			"week_phase", "week_anchor_ts", "season_start_ts", "referee_pending", "replay_pending_id", "candy_jar_broken",
			"tutorial_active", "test_mode", "ghost_upload_pending", "chest_treasure_value", "chest_treasures_won",
			"incense_marks", "incense_charge"]:
		var v = _gs.get(k)
		_bak[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	_gs.test_mode = true
	_gs.tutorial_active = false
	## 钟钉在本周周二 12:00(积分赛日): 结算里的 ensure_season 不滚轮、不补收盘
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 86400 + 12 * 3600
	await _t_settle_table()
	_t_static()
	_t_pool()
	P2C.now_override_ts = 0
	for k in _bak:
		_gs.set(k, _bak[k])
	_finish()


# ─────────────────────────────── A 结算表 ───────────────────────────────
## 检查脚本里那张表 → [{id, h0, w0, s0, e0, b0, won, top, bottom, fin, coins, eh, ew, es, ee, eb, eu, er}]。
static func cases_from_sql(txt: String) -> Array:
	var a := txt.find("-- >>> RANKED_SETTLE_CASES")
	var b := txt.find("-- <<< RANKED_SETTLE_CASES")
	if a < 0 or b < a:
		return []
	var rx := RegEx.create_from_string(
		"\\('(\\w+)', (\\d+), (\\d+), (\\d+), (\\d+), (\\d+), (true|false), '(\\w*)', '(\\w*)', '(\\w*)', (\\d+), (\\d+), (\\d+), (\\d+), (\\d+), (\\d+), (\\d+), (\\d+)\\)")
	var out: Array = []
	for m in rx.search_all(txt.substr(a, b - a)):
		var g: Array = []
		for i in range(1, 19):
			g.append(m.get_string(i))
		out.append({"id": g[0], "h0": int(g[1]), "w0": int(g[2]), "s0": int(g[3]), "e0": int(g[4]), "b0": int(g[5]),
			"won": g[6] == "true", "top": g[7], "bottom": g[8], "fin": g[9], "coins": int(g[10]),
			"eh": int(g[11]), "ew": int(g[12]), "es": int(g[13]), "ee": int(g[14]), "eb": int(g[15]), "eu": int(g[16]),
			"er": int(g[17])})
	return out


func _start_state(c: Dictionary) -> void:
	_gs.season_leaders = ["candy", "basic", "stone"]     # 糖果罐(选糖果龟当统领才有)
	_gs.left_team.assign(_gs.season_leaders)
	_gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]   # 背包里一把小木斧 ⇒ 打完一场 +砍伐经验
	_gs.hearts = int(c["h0"])
	_gs.season_wins = int(c["w0"])
	_gs.season_sweeps = int(c["s0"])
	_gs.season_eggs_killed = int(c["e0"])
	_gs.season_total_battles = int(c["b0"])
	_gs.ranked_used = int(c["b0"])
	_gs.meta_deepsea_coins = 100
	_gs.season_xp = 1
	_gs.season_level = 3
	_gs.candy_jar_count = 10
	_gs.candy_jar_broken = false
	_gs.axe_exp_total = 40
	_gs.axe_exp_bar = 0
	_gs.axe_stage = 0
	_gs.battles_total = 50
	_gs.battles_won = 20
	_gs.match_history = []
	_gs.titles = []
	_gs.week_phase = P2C.PHASE_RANKED
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.season_start_ts = _gs.week_anchor_ts
	_gs.referee_pending = {}
	_gs.replay_pending_id = ""
	var lr := {}
	for k in ["top", "bottom", "final"]:
		var v := str(c["fin" if k == "final" else k])
		if v != "":
			lr[k] = v
	_gs.lane_results = lr


func _cap() -> Dictionary:
	var d := {}
	for k in FIELDS:
		d[k] = int(_gs.get(k))
	d["match_history"] = (_gs.match_history as Array).size()
	d["titles"] = (_gs.titles as Array).size()
	return d


func _t_settle_table() -> void:
	print("── A 结算表: 本机老结算 _settle_season / 新客户端记账 settle_ranked / 服务端 referee_complete 同一张表 ──")
	var cases := cases_from_sql(FileAccess.get_file_as_string(CHECK_SQL))
	_ok("A ★分母: 检查脚本里那张表读到 10 行(服务端那一半用同一张表跑 referee_complete)", cases.size() == 10, str(cases.size()))
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame
	_ok("A 分母: 真战斗场脚本实例起来了(结算要的系统对象都在)", scene.get("_equip_tick_sys") != null and scene.get("_replay") != null)
	var a1_bad: Array = []
	var a2_bad: Array = []
	var minted_seen := 0
	for c in cases:
		## A1 本机老结算
		_start_state(c)
		scene._equip_tick_sys._gear_coins = {"left": int(c["coins"]), "right": 0}
		if int(c["coins"]) > 0 and EquipTickSystem.match_minted(scene) == int(c["coins"]):
			minted_seen += 1
		var c0 := int(_gs.meta_deepsea_coins)
		scene._settle_season(bool(c["won"]))
		var r1 := _cap()
		var got := [int(_gs.hearts), int(_gs.season_wins), int(_gs.season_sweeps), int(_gs.season_eggs_killed),
			int(_gs.season_total_battles), int(_gs.ranked_used), int(_gs.meta_deepsea_coins) - c0]
		var want := [c["eh"], c["ew"], c["es"], c["ee"], c["eb"], c["eu"], c["er"]]
		if got != want:
			a1_bad.append("%s 本机 %s ≠ 表 %s" % [c["id"], str(got), str(want)])
		## A2 新客户端记账: 同一个开局状态, 喂服务端会回的那份(= 表的输出列)
		_start_state(c)
		_gs.referee_pending = RW.ranked_bill(77, MID, int(_gs.week_anchor_ts), {"leaders": ["ninja"], "profile": {"name": "kevin_99"}})
		var st := {"won": 1 if bool(c["won"]) else 0, "coins": int(c["coins"]), "match_id": MID,
			"ranked": {"battles": c["eb"], "wins": c["ew"], "hearts": c["eh"], "sweeps": c["es"], "eggs": c["ee"],
				"used": c["eu"], "reward": c["er"], "sweep": int(c["es"]) > int(c["s0"])}}
		var v: Dictionary = RW.settle(_gs, 77, st)
		var r2 := _cap()
		var row0: Dictionary = (_gs.match_history as Array)[0] if (_gs.match_history as Array).size() > 0 else {}
		if v.is_empty() or r2 != r1 or not (_gs.referee_pending as Dictionary).is_empty() or str(row0.get("replay_id", "")) != MID 				or str(row0.get("foe_name", "")) != "kevin_99":
			a2_bad.append("%s 老 %s / 新 %s / view %s" % [c["id"], str(r1), str(r2), str(v)])
	_ok("A ★分母: 带战斗内铸币的几行, 铸币真的从结算读的那个出口出来(match_minted)", minted_seen == 5, str(minted_seen))
	_ok("A1 ★本机老结算 _settle_season 逐行 = 表(命 / 胜 / 横扫 / 碎蛋 / 场次 / 配额 / 币)⇒ 表就是现行规则", cases.size() == 10 and a1_bad.is_empty(),
		"\n      ".join(PackedStringArray(a1_bad)))
	_ok("A2 ★新客户端记账(照抄服务器账本)与老结算对本机存档的改动逐项相同(%d 项 × 10 行, 含经验 / 等级 / 糖果罐 / 砍伐 / 战绩页);单子销了、战绩页那一行挂上服务器录像与对手名" % (FIELDS.size() + 2),
		cases.size() == 10 and a2_bad.is_empty(), "\n      ".join(PackedStringArray(a2_bad)))
	## A3 分母: 糖果罐 / 砍伐 / 经验 这几项在表里真的动过(否则 A2 比的是一堆不变的数)
	_start_state(cases[0])
	var b0 := _cap()
	scene._equip_tick_sys._gear_coins = {"left": 0, "right": 0}
	scene._settle_season(true)
	var b1 := _cap()
	_ok("A3 分母: 一局下来糖果罐 / 砍伐经验 / 大轮经验 / 战绩页确实都动了(A2 不是在比不变的数)",
		b1["candy_jar_count"] != b0["candy_jar_count"] and b1["axe_exp_total"] != b0["axe_exp_total"]
		and b1["season_xp"] != b0["season_xp"] and b1["match_history"] != b0["match_history"], "%s → %s" % [str(b0), str(b1)])
	## A4 记账只认服务器的数: 账本说 3 胜, 本机原来 9 胜 ⇒ 记完是 3(不是 9 + 1)
	_start_state(cases[0])
	_gs.season_wins = 9
	_gs.referee_pending = RW.ranked_bill(78, MID, int(_gs.week_anchor_ts), {})
	RW.settle(_gs, 78, {"won": 1, "coins": 0, "ranked": {"battles": 1, "wins": 3, "hearts": int(P2C.HEARTS_MAX), "sweeps": 0, "eggs": 1,
		"used": 1, "reward": 20, "sweep": false}})
	_ok("A4 ★胜场照抄服务器账本(本机 9 胜 ⇒ 记完 3 胜, 不是本机 +1)", int(_gs.season_wins) == 3, str(_gs.season_wins))
	## A5 预演(跟播沙盒里)不销单、不写录像号; 上一周的单子不记
	_start_state(cases[1])
	_gs.referee_pending = RW.ranked_bill(79, MID, int(_gs.week_anchor_ts), {})
	var pv: Dictionary = RW.settle(_gs, 79, {"won": 0, "coins": 0, "ranked": {"battles": 1, "wins": 0, "hearts": 5, "sweeps": 0,
		"eggs": 0, "used": 1, "reward": 15, "sweep": false}}, true)
	_ok("A5 预演: 回 view(积分赛口径)、单子还在、录像号没写", str(pv.get("kind", "")) == RW.KIND_RANKED
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == 79 and str(_gs.replay_pending_id) == "", str(pv))
	_start_state(cases[1])
	_gs.referee_pending = RW.ranked_bill(80, MID, int(_gs.week_anchor_ts) - 7 * 86400, {})
	var h0 := int(_gs.hearts)
	var old: Dictionary = RW.settle(_gs, 80, {"won": 0, "coins": 0, "ranked": {"battles": 1, "wins": 0, "hearts": 5, "sweeps": 0,
		"eggs": 0, "used": 1, "reward": 15, "sweep": false}})
	_ok("A6 上一周交的单子: 不记(命不动)、销单", old.is_empty() and int(_gs.hearts) == h0 and (_gs.referee_pending as Dictionary).is_empty())
	_start_state(cases[1])
	_gs.referee_pending = RW.ranked_bill(81, MID, int(_gs.week_anchor_ts), {})
	var none: Dictionary = RW.settle(_gs, 81, {"won": 0, "coins": 0})
	_ok("A7 回包里没有账本(老服务端 / 结果不明)⇒ 不记、单子留着", none.is_empty() and int(_gs.hearts) == int(cases[1]["h0"])
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == 81)
	_gs.referee_pending = {}
	scene.queue_free()
	await get_tree().process_frame


# ─────────────────────────────── B 常量 / 形参 ───────────────────────────────
## 迁移里 `public.<fn>() returns int language sql immutable as $$ select N $$` 的 N; 没有 ⇒ -1。
static func sql_const(txt: String, fn: String) -> int:
	var rx := RegEx.create_from_string("function public\\.%s\\(\\) returns int language sql immutable as \\$\\$ select (\\d+) \\$\\$" % fn)
	var m := rx.search(txt)
	return int(m.get_string(1)) if m != null else -1


## 迁移里某个函数的整段(从 create 到下一个 `end $$;`)。
static func sql_func(txt: String, fn: String) -> String:
	var a := txt.find("create or replace function public.%s(" % fn)
	if a < 0:
		return ""
	var b := txt.find("end $$;", a)
	return txt.substr(a, (b - a) if b > a else -1)


func _t_static() -> void:
	print("── B 服务端常量 / 形参 = 客户端 ──")
	var t := FileAccess.get_file_as_string(MIG_SQL).replace("\r\n", "\n")
	_ok("B ★分母: 读到迁移 20261101d", t.length() > 10000, str(t.length()))
	_ok("B1 命上限 = HEARTS_MAX", sql_const(t, "ranked_hearts_max") == int(P2C.HEARTS_MAX), "%d / %d" % [sql_const(t, "ranked_hearts_max"), int(P2C.HEARTS_MAX)])
	_ok("B2 配额 = RANKED_QUOTA", sql_const(t, "ranked_quota") == int(P2C.RANKED_QUOTA), "%d / %d" % [sql_const(t, "ranked_quota"), int(P2C.RANKED_QUOTA)])
	_ok("B3 封盘秒数 = CLOSE_LOCKOUT_SEC", sql_const(t, "ranked_lockout_sec") == int(P2C.CLOSE_LOCKOUT_SEC))
	var win := sql_func(t, "ranked_window_open")
	var close_expr := "p_week + %d * 86400 + %d * 3600 - public.ranked_lockout_sec()" % [int(P2C.RANKED_CLOSE_WD) - 1, int(P2C.WEEK_CLOSE_HOUR_UTC)]
	_ok("B4 收盘时刻 = ranked_close_ts(周五 23:00)− 封盘", win.contains(close_expr), close_expr)
	var days_ok := P2C.phase_of_weekday(1) == P2C.PHASE_REST and P2C.phase_of_weekday(6) == P2C.PHASE_GAUNTLET
	for wd in range(2, 6):
		days_ok = days_ok and P2C.phase_of_weekday(wd) == P2C.PHASE_RANKED
	_ok("B5 开门 = 周二 00:00(周一休赛、周二~周五积分赛、周六闯关 —— 与 phase_of_weekday 同一张表)",
		days_ok and win.contains("public.app_now() >= to_timestamp(p_week + 86400)"))
	var cmp := sql_func(t, "referee_complete")
	_ok("B6 币公式 = _settle_season 那一行(8 + 余命 + 2×已失命 + 胜 6)", cmp.contains("v_reward := 8 + v_hearts + 2 * v_lost + case when won then 6 else 0 end;"))
	var pick := sql_func(t, "referee_ranked_pick")
	_ok("B7 ★选靶只认场次完全相同(D5): 真人 / 陪练都是 = p_battles, 函数里没有 ±N / between / 往下找",
		pick.contains("g.battles = p_battles") and pick.contains("p.battles = p_battles") and not pick.contains("p_battles - 1")
		and not pick.contains("p_battles + 1") and not pick.to_lower().contains("between") and pick.contains("order by random()"))
	var sig := RegEx.create_from_string("function public\\.referee_ranked_start\\(([^)]*)\\)").search(t)
	var params: Array = []
	if sig != null:
		for p in sig.get_string(1).split(","):
			var w := p.strip_edges().split(" ")
			if w.size() > 0 and str(w[0]).begins_with("p_"):
				params.append(str(w[0]))
	var body_keys: Array = RN.ranked_start_body(1, {}, 0).keys()
	_ok("B8 ★开战请求体的键 ⊆ 服务端形参, 且只有 周 / 阵容 / 第几场(没有对手、种子、胜负、成绩)",
		params.size() == 5 and body_keys.size() == 3 and body_keys.all(func(k) -> bool: return params.has(k)),
		"%s ⊆ %s" % [str(body_keys), str(params)])
	_ok("B9 开关键名: 客户端 K_RANKED = 服务端 referee_flags 回的那个键", t.contains("'%s', public.referee_ranked_on()" % RN.K_RANKED))
	var peek := sql_func(t, "ranked_ledger_peek")
	var keys_ok := true
	for k in RN.LEDGER_KEYS:
		keys_ok = keys_ok and peek.contains("'%s', " % k)
	_ok("B10 账本键名: 客户端 LEDGER_KEYS 六个都在服务端回包里", keys_ok, str(RN.LEDGER_KEYS))
	_ok("B11 任务种类: 裁判程序认 ranked、服务端约束也认", RefereeJob.MODES.has("ranked") and t.contains("check (kind in ('gauntlet', 'finals', 'ranked'))"))
	var cv := str(ProjectSettings.get_setting("application/config/version", ""))
	var mc := RegEx.create_from_string("ranked_min_client\\(\\) returns text\\s+language sql immutable as \\$\\$ select '([0-9.]+)' \\$\\$").search(t)
	_ok("B12 积分赛服务器局的最低客户端版本是合法版本号(> 0.22.6 = 改动前最后一版)", mc != null
		and VersionGate.version_less("0.22.6", mc.get_string(1)), "min=%s 本机=%s" % [mc.get_string(1) if mc != null else "?", cv])


# ─────────────────────────────── C 对手池 ───────────────────────────────
func _t_pool() -> void:
	print("── C 积分赛对手池(陪练 = 客户端池子那份 / 机器人 = make_bot)──")
	var p1: Dictionary = BP.generate_ranked()
	var p2: Dictionary = BP.generate_ranked()
	_ok("C1 两遍逐字节相同(种子按 规则版本 / 场次 / 序号 定)", JSON.stringify(p1) == JSON.stringify(p2))
	var src: Dictionary = BE._load_seed()
	var n_src := 0
	for k in (src.get(BE.POOL_KEY, {}) as Dictionary).keys():
		for g in (src[BE.POOL_KEY][k] as Array):
			if g is Dictionary:
				n_src += 1
	var seeds: Array = p1.get("seed_rows", [])
	_ok("C2 ★陪练份数 = 客户端内置种子池份数(分母)", n_src >= 300 and seeds.size() == n_src, "%d / %d" % [seeds.size(), n_src])
	var bad_seed: Array = []
	var by_id := {}
	for k in (src.get(BE.POOL_KEY, {}) as Dictionary).keys():
		for g in (src[BE.POOL_KEY][k] as Array):
			if g is Dictionary:
				by_id[str((g as Dictionary).get("ghost_id", ""))] = g
	for r in seeds:
		var s: Dictionary = r["snapshot"]
		var g = by_id.get(str(s.get("ghost_id", "")), null)
		var want: Dictionary = BE.seed_as_human(g as Dictionary, BP.RANKED_SEED_SID) if g is Dictionary else {}
		want.erase(BE.ORIGIN_KEY)
		if s.has(BE.ORIGIN_KEY) or int(s.get("season_total_battles", -1)) != int(r["battles"]) or JSON.stringify(s) != JSON.stringify(want):
			bad_seed.append(str(s.get("ghost_id", "?")))
	_ok("C3 ★每一份陪练 = seed_as_human(种子) 摘掉 origin, 场次 = 快照自报", bad_seed.is_empty(), str(bad_seed.slice(0, 5)))
	var bots: Array = p1.get("bot_rows", [])
	_ok("C4 机器人 = 场次 0..%d × 每格 %d 份" % [BP.MAX_BATTLES, BP.VARIANTS], bots.size() == (BP.MAX_BATTLES + 1) * BP.VARIANTS, str(bots.size()))
	var bad_bot: Array = []
	for r in bots:
		var s: Dictionary = r["snapshot"]
		var rng := RandomNumberGenerator.new()
		rng.seed = BP.ranked_seed_for(int(r["battles"]), int(r["variant"]))
		var want: Dictionary = BE.make_bot(int(r["battles"]), rng)
		want.erase(BE.ORIGIN_KEY)
		if s.has(BE.ORIGIN_KEY) or s.has("gl_w") or s.has("gl_ts") or int(s.get("season_total_battles", -1)) != int(r["battles"]) \
				or (s.get("leaders", []) as Array).size() != 3 or JSON.stringify(s) != JSON.stringify(want):
			bad_bot.append("%s/%s" % [str(r["battles"]), str(r["variant"])])
	_ok("C5 ★每一份机器人 = make_bot(场次, 同一个种子) 摘掉 origin、不带周六标签、三统领", bad_bot.is_empty(), str(bad_bot.slice(0, 5)))
	_ok("C6 池子带版本 / 规则版本(服务端按 rules_ver 存)", str(p1.get("client_version", "")) == ReplayRecorder.client_version()
		and int(p1.get("rules_ver", 0)) == int(P2C.RULES_VER))


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 积分赛服务端规则 = 本机老规则" if _fail == 0 and _n >= 25 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
