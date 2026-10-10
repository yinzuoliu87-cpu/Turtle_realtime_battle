extends Node
## verify_champion_cup.gd — 冠军杯赛端到端(方案书 docs/plans/20261007-冠军杯赛.md)
##
## 用户 2026-10-07「那么上午就叫小组赛啊，晚上叫冠军杯赛」;
## 原稿 §四「20:00 开赛：全部桶冠军补轮空进最近的 2 的幂签表，单败打到决赛……奖励：冠军/亚军/四强/…/桶冠军」。
##
## 段落:
##   ① 用词: 产品代码里的字符串不再出现旧词(我的分组 / 本周冠军 / 冠军赛 / 冠军签表 / 各组冠军 / 分桶赛);
##      两个页签就叫「小组赛」「冠军杯赛」
##   ② SQL: 迁移文件 = schema.sql 里同一段(逐字); 保留组号 / 开赛钟点 = 客户端常量;
##      座次构造与 `bracket.gd` 同一公式, 并把 `finals_champion_seed` 逐行翻成 GDScript 与 `bracket.champion_seed`
##      在 n=1..40 × 随机结果上逐个对; 杯种子与分组同一条排序; 「我那个组」与组列表都排除杯
##   ③ 开赛前(周日 12:00): 冠军杯赛页 = 倒计时 + 两名组冠军(假传输走真联网路径)
##   ④ 成表(20:05): 默认切到冠军杯赛; 我的那一场可打 —— 购物窗 / 倒计时跟着杯那一张;
##      点格子 ⇒ 弹卡「开始对战」⇒ 问对手带杯的组号
##   ⑤ 报结果: 小组赛与冠军杯赛同坐标(1-0)两场都真的发出去(去重带组号), 待揭晓那一单带组号
##   ⑥ 翻面开播: 决赛在开播窗口里 ⇒ 不写胜负、没有「冠军 · 名字」; 揭晓只按杯那一张(不拿小组赛的 done)
##   ⑦ 窗口过后: 顶上「冠军 · 名字」; 我(决赛输)拿【亚军】+【组冠军】, 没有【冠军】; 回放 / 上传都认杯的组号
##   ⑧ 1 人表: 冠军杯赛只有 1 人 ⇒「直接夺冠」, 组里的名次不兜底; 1 人组 ⇒「直接晋级冠军杯赛」+【组冠军】
##   ⑨ 排行榜头衔(纯函数): 多组 + 杯 / 1 人杯 / 1 人组 / 杯没部署
##   ⑩ 分组容量(用户 2026-10-07 新规则): SQL `finals_bucket_size` 与 `bracket.bucket_size_for` 在 N=1..1000 逐个一致;
##      1 人组坐下即收盘
## 每条新断言都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「实施回填」。

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const B := preload("res://scripts/gamedata/bracket.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const MIGRATION := "res://server/supabase/migrations/20261007b_champion_cup.sql"
const SCHEMA := "res://server/supabase/schema.sql"
const MARK_BEGIN := "-- >>> BEGIN champion_cup 20261007b >>>"
const MARK_END := "-- <<< END champion_cup 20261007b <<<"
const ME := "11111111-2222-4333-8444-555555555555"
const KEYS := ["titles", "ranked_used", "promoted", "week_anchor_ts", "account_id", "season_wins",
	"finals_deepest_round", "finals_rounds_total", "finals_champion", "finals_runner_up",
	"finals_pending_reveal", "finals_report_pending", "finals_match", "week_phase", "battle_seed",
	"finals_cup_deepest", "finals_cup_total", "finals_cup_champion", "finals_cup_runner_up",
	"gauntlet_wins", "gauntlet_losses", "test_mode"]

var _n := 0
var _fail := 0
var _bak := {}
var _reqs: Array = []
var _mine_body := ""
var _week_body := ""
var _wk := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	for k in KEYS:
		_bak[k] = GameState.get(k)
	GameState.test_mode = true
	print("=== 冠军杯赛 ===")
	_t_copy()
	_t_sql()
	_backend_on()
	await _t_flow()
	await _t_solo()
	await _t_group_solo()
	_t_leaderboard()
	_t_sizing()
	_backend_off()
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n >= 60:
		print("ALL PASS — 冠军杯赛")
		get_tree().quit(0)
	else:
		print("FAIL x%d (断言 %d 条)" % [_fail, _n])
		get_tree().quit(1)


# ─────────────────────────────────────────────────────────────
# ① 用词
# ─────────────────────────────────────────────────────────────
func _gd_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."):
				_gd_files(dir.path_join(f), out)
		elif f.ends_with(".gd"):
			out.append(dir.path_join(f))
		f = d.get_next()


func _t_copy() -> void:
	print("── ① 用词 ──")
	_ok("① ★两个名字 = 用户原话", P2C.STAGE_GROUP == "小组赛" and P2C.STAGE_CUP == "冠军杯赛",
		"%s / %s" % [P2C.STAGE_GROUP, P2C.STAGE_CUP])
	var files: Array = []
	_gd_files("res://scripts", files)
	_gd_files("res://autoload", files)
	var re := RegEx.new()
	re.compile("\"[^\"\\n]*(我的分组|本周冠军|冠军赛|冠军签表|各组冠军|分桶赛|桶冠军)[^\"\\n]*\"")
	var hits: Array = []
	var lines := 0
	for p in files:
		var t := FileAccess.get_file_as_string(str(p))
		for ln in t.split("\n"):
			var s := str(ln).strip_edges()
			if s.begins_with("#"):
				continue
			lines += 1
			## 行尾注释里的引号不算(注释不是屏幕上的字)
			var code := s
			var hash := s.find("##")
			if hash > 0:
				code = s.substr(0, hash)
			if re.search(code) != null:
				hits.append("%s: %s" % [str(p).get_file(), s.substr(0, 80)])
	_ok("① ★分母: 扫了 scripts/ + autoload/ 的代码行", files.size() > 150 and lines > 50000,
		"%d 个文件 %d 行" % [files.size(), lines])
	_ok("① ★★★产品字符串里旧词 0 处", hits.is_empty(), str(hits.slice(0, 4)))
	_ok("① ★分母: 正则真的会命中旧词(拿旧稿那句试)", re.search("\"冠军赛 %d 小时后开始\"") != null
		and re.search("\"我的分组\"") != null)
	_ok("① 页签字: 冠军杯赛没成表 / 成表", BMS.finals_tab_text(0) == "冠军杯赛 · 未开赛"
		and BMS.finals_tab_text(8) == "冠军杯赛", "%s / %s" % [BMS.finals_tab_text(0), BMS.finals_tab_text(8)])
	_ok("① 结算副标题按组号说是哪一段", P2C.finals_stage_name(P2C.FINALS_CUP_BUCKET) == "冠军杯赛"
		and P2C.finals_stage_name(0) == "小组赛" and P2C.finals_stage_name(-1) == "小组赛")


# ─────────────────────────────────────────────────────────────
# ② SQL
# ─────────────────────────────────────────────────────────────
func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p).replace("\r\n", "\n")


func _seg(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b2 := t.find(MARK_END)
	return t.substr(a, b2 + MARK_END.length() - a) if a >= 0 and b2 > a else ""


func _fn(t: String, name: String) -> String:
	var a := t.find("create or replace function public.%s(" % name)
	if a < 0:
		return ""
	var e := t.find("end $$;", a)
	var e2 := t.find("$$;", a)
	var stop := e if e >= 0 else e2
	return t.substr(a, stop - a) if stop > a else ""


## `finals_seed_at_seat` 逐行翻成 GDScript(镜像展开: seats=[0]; 每轮追加 x 与 2·sz−1−x)。
func _sql_seed_at_seat(slots: int, pos: int) -> int:
	if slots < 1 or pos < 0 or pos >= slots:
		return -1
	var seats: Array = [0]
	var sz := 1
	while sz < slots:
		var nxt: Array = []
		for x in seats:
			nxt.append(int(x))
			nxt.append(sz * 2 - 1 - int(x))
		seats = nxt
		sz *= 2
	return int(seats[pos])


## `finals_champion_seed` 逐行翻成 GDScript(从决赛往下追: m := m*2 + s; 第 1 轮 ⇒ 座位 2m+s)。
## ★`done` 是**服务端那种**(收盘的组每一轮每一场都有行, 轮空补 side 0)。
func _sql_champion(n: int, done: Dictionary, closed: bool) -> int:
	if not closed:
		return -1
	if n == 1:
		return 0
	var slots := 1
	var total := 0
	while slots < n:
		slots *= 2
		total += 1
	var r := total
	var m := 0
	while r >= 1:
		var key := "%d-%d" % [r, m]
		if not done.has(key):
			return -1
		var s := int(done[key])
		if s != 0 and s != 1:
			return -1
		if r == 1:
			var sd := _sql_seed_at_seat(slots, m * 2 + s)
			if sd < 0 or sd >= n:
				return -1
			return sd
		m = m * 2 + s
		r -= 1
	return -1


## 服务端那种 done: 每一轮每一场都有行(轮空补 side 0 —— finals_advance 的那条无条件 insert)。
func _server_done(n: int, rng: RandomNumberGenerator) -> Dictionary:
	var slots := B.slots_for(n)
	var cur: Array = []
	for i in range(slots):
		var sd := B.seed_at_seat(i, n)
		cur.append(sd if sd >= 0 and sd < n else -2)
	var done := {}
	var r := 1
	while cur.size() > 1:
		var nxt: Array = []
		for m in range(cur.size() / 2):
			var x: int = cur[m * 2]
			var y: int = cur[m * 2 + 1]
			var side := 0 if y == -2 else rng.randi_range(0, 1)
			done["%d-%d" % [r, m]] = side
			nxt.append(x if side == 0 else y)
		cur = nxt
		r += 1
	return done


func _t_sql() -> void:
	print("── ② SQL ──")
	var mig := _read(MIGRATION)
	var sch := _read(SCHEMA)
	var seg := _seg(mig)
	_ok("② ★分母: 迁移文件在、首尾标记各一", seg != "" and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1,
		"%d 字" % mig.length())
	_ok("② ★schema.sql 里同一段逐字相同(只出现一次)", sch.count(MARK_BEGIN) == 1 and _seg(sch) == seg)
	_ok("② ★★保留组号 = 客户端常量", seg.find("as $$ select %d $$" % P2C.FINALS_CUP_BUCKET) >= 0
		and _fn(seg, "finals_cup_no").find("select %d" % P2C.FINALS_CUP_BUCKET) >= 0, str(P2C.FINALS_CUP_BUCKET))
	_ok("② ★★开赛钟点(UTC) = 客户端常量", _fn(seg, "finals_cup_hour").find("select %d" % P2C.FINALS_START_HOUR_UTC) >= 0,
		str(P2C.FINALS_START_HOUR_UTC))
	var sat := _fn(seg, "finals_seed_at_seat")
	_ok("② ★★座次构造与 bracket.gd 同一公式(x 与 2·sz−1−x 交错)",
		sat.find("nxt := array_append(nxt, x);") >= 0 and sat.find("nxt := array_append(nxt, sz * 2 - 1 - x);") >= 0
		and sat.find("return seats[p_pos + 1];") >= 0, "%d 字" % sat.length())
	var ch := _fn(seg, "finals_champion_seed")
	_ok("② ★★冠军追溯与 occupant_seed 同一口径(m := m*2+s; 第 1 轮座位 2m+s)",
		ch.find("m := m * 2 + s;") >= 0 and ch.find("finals_seed_at_seat(slots, m * 2 + s)") >= 0, "%d 字" % ch.length())
	## 翻译版 vs bracket.gd: 座次逐坑 + 冠军逐个
	var seat_bad := 0
	var seat_n := 0
	for slots in [1, 2, 4, 8, 16, 32, 64]:
		for pos in range(slots):
			seat_n += 1
			var n_for: int = slots       # slots_for(slots) == slots
			if _sql_seed_at_seat(slots, pos) != B.seed_at_seat(pos, n_for):
				seat_bad += 1
	_ok("② ★★★座次表: SQL 翻译版与 bracket.gd 逐坑一致", seat_bad == 0 and seat_n == 127,
		"%d 坑 / 不一致 %d" % [seat_n, seat_bad])
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cases := 0
	var bad: Array = []
	for n in range(1, 41):
		for k in range(10):
			var done := _server_done(n, rng) if n > 1 else {}
			cases += 1
			var a := _sql_champion(n, done, true)
			var b2 := B.champion_seed(n, done)
			if a != b2 or a < 0:
				bad.append("n=%d k=%d sql=%d gd=%d" % [n, k, a, b2])
	_ok("② ★★★组冠军: SQL 翻译版与 bracket.champion_seed 在 n=1..40 × 10 组结果上逐个一致", bad.is_empty() and cases == 400,
		"%d 例 / 不一致 %s" % [cases, str(bad.slice(0, 3))])
	_ok("② ★分母: 没收盘 ⇒ SQL 版不认冠军", _sql_champion(4, {"1-0": 0, "1-1": 0, "2-0": 0}, false) == -1)
	var cs := _fn(seg, "finals_cup_seat")
	var seat_fn := _fn(sch, "finals_seat")
	_ok("② ★★杯种子按周六战绩, 与分组同一条排序(gw desc, gl asc, account_id)",
		cs.find("order by gw desc, gl asc, e.account_id") >= 0 and seat_fn.find("order by gw desc, gl asc, account_id") >= 0)
	_ok("② ★只收已收盘组的冠军; 到点前不成表; 1 人表直接收盘",
		cs.find("b.closed) c") >= 0 and cs.find("if now() < start_at then") >= 0 and cs.find("i <= 1") >= 0)
	var fv := _fn(seg, "finals_view")
	_ok("② ★★「我那个组」不许查到冠军杯赛", fv.find("and e.bucket_no <> public.finals_cup_no()") >= 0)
	var wv := _fn(seg, "finals_week_view")
	_ok("② ★★组列表排除杯、杯放回包顶层 cup", wv.find("and b.bucket_no <> cup;") >= 0
		and wv.find("'cup', cp") >= 0 and wv.find("b.closed or r.round < b.round") >= 0)
	_ok("② ★不剧透: 杯那一张也只给已翻面的轮次", wv.count("(b.closed or r.round < b.round)") == 2)
	## ★第二道锁: 服务端哪天回退、把杯又放进组列表 ⇒ 客户端照样不把它当成一个组
	var leak: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": 1, "now": 1, "buckets": [
		{"bucket": 0, "n": 2, "round": 1, "closed": false, "done": {}, "entrants": [_ent(0, "甲", "a"), _ent(1, "乙", "b")]},
		{"bucket": P2C.FINALS_CUP_BUCKET, "n": 2, "round": 1, "closed": false, "done": {},
			"entrants": [_ent(0, "丙", "c"), _ent(1, "丁", "d")]}]}), "", 1)
	_ok("② ★★组列表里混进杯 ⇒ 客户端再筛掉(只剩 1 组)", (leak.get("buckets", []) as Array).size() == 1
		and not leak.has("cup"), str((leak.get("buckets", []) as Array).size()))
	_ok("② 定时任务: 周日 20:00 起每 5 分钟、可重复执行", seg.find("cron.unschedule(jobid) from cron.job where jobname = 'finals_cup_seat'") >= 0
		and seg.find("'*/5 %d-23 * * 0'" % P2C.FINALS_START_HOUR_UTC) >= 0)


# ─────────────────────────────────────────────────────────────
# ③~⑦ 端到端(假传输走真联网路径)
# ─────────────────────────────────────────────────────────────
var _env0 := ""
var _key0 = null


func _backend_on() -> void:
	_env0 = OS.get_environment(SB.ENV_URL)
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	GameState.account_id = ME
	SB._token = "gate-token"
	SB._transport_for_test = _spy


func _backend_off() -> void:
	SB._transport_for_test = Callable()
	SB.finals_clear()
	SB.finals_week_clear()
	SB.finals_report_clear()
	SB.opponent_clear()
	SB._token = ""
	OS.set_environment(SB.ENV_URL, _env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
	P2C.now_override_ts = 0


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"url": str(url), "body": str(body)})
	var u := str(url)
	if u.ends_with("/finals_week_view"):
		cb.call({"ok": true, "code": 200, "body": _week_body})
	elif u.ends_with("/finals_view"):
		cb.call({"ok": true, "code": 200, "body": _mine_body})
	elif u.ends_with("/finals_opponent"):
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "wrong_round", "round": 2})})
	elif u.ends_with("/finals_report"):
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true})})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _reqs_to(tail: String) -> Array:
	return _reqs.filter(func(r): return str(r["url"]).ends_with(tail))


func _ent(seed: int, name: String, acc: String) -> Dictionary:
	return {"seed": seed, "name": name, "account_id": acc}


## 两个 2 人组(都打完): 第 1 组我赢、第 2 组丁龟赢。
func _groups() -> Array:
	return [
		{"bucket": 0, "n": 2, "round": 1, "closed": true, "round_at": 0, "revealed_at": 0, "done": {"1-0": 0},
			"entrants": [_ent(0, "我龟", ME), _ent(1, "乙龟", "uid-b")]},
		{"bucket": 1, "n": 2, "round": 1, "closed": true, "round_at": 0, "revealed_at": 0, "done": {"1-0": 1},
			"entrants": [_ent(0, "丙龟", "uid-c"), _ent(1, "丁龟", "uid-d")]}]


func _set_bodies(now: int, cup) -> void:
	var g: Dictionary = (_groups()[0] as Dictionary).duplicate(true)
	g["ok"] = true
	g["now"] = now
	g["next_at"] = 480
	_mine_body = JSON.stringify(g)
	_week_body = JSON.stringify({"ok": true, "week": _wk, "now": now, "buckets": _groups(), "cup": cup})


func _refresh(m) -> void:
	SB.finals_clear()
	SB.finals_week_clear()
	m._pull()
	await _frames(2)
	m._on_poll()
	await _frames(2)


func _find_btn(m, rm: Vector2i) -> Button:
	for c in _all(m):
		if c is Button and str(c.name) == BMS.N_NODE_BTN and c.has_meta("rm") and c.get_meta("rm") == rm:
			return c
	return null


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _reset_gs() -> void:
	GameState.titles = []
	GameState.week_anchor_ts = _wk
	GameState.ranked_used = 0
	GameState.promoted = false
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 0
	GameState.finals_deepest_round = 0
	GameState.finals_rounds_total = 0
	GameState.finals_champion = false
	GameState.finals_runner_up = false
	GameState.finals_pending_reveal = {}
	GameState.finals_report_pending = {}
	GameState.finals_match = {}
	GameState._clear_cup_progress()


func _t_flow() -> void:
	_wk = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	_reset_gs()
	var noon := _wk + 6 * 86400 + 12 * 3600
	var t1 := _wk + 6 * 86400 + 20 * 3600 + 5 * 60

	print("── ③ 开赛前(周日 12:00 UTC) ──")
	P2C.now_override_ts = noon
	_set_bodies(noon, null)
	_reqs.clear()
	var m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	_ok("③ ★分母: 真的发了 finals_view 与 finals_week_view", _reqs_to("/finals_view").size() >= 1
		and _reqs_to("/finals_week_view").size() >= 1, "%d 条请求" % _reqs.size())
	_ok("③ 中午默认看小组赛", str(m._view) == L.VIEW_BUCKET, str(m._view))
	m.pick_view(L.VIEW_FINALS)
	await _frames(1)
	var et := str(m._empty_lb.text)
	print("    冠军杯赛页: 「%s」" % et.replace("\n", " / "))
	_ok("③ ★★分类 = 开赛前", str(m._empty_kind()) == BMS.EK_FINALS_SOON, str(m._empty_kind()))
	_ok("③ ★★倒计时数到 20:00 UTC(8 小时 0 分)", et.begins_with("冠军杯赛 8 小时 0 分后开赛"), et)
	_ok("③ ★★列出两名组冠军(进冠军杯赛的人)", et.find("我龟") >= 0 and et.find("丁龟") >= 0
		and et.find("乙龟") < 0 and et.find("丙龟") < 0, et)
	_ok("③ 页签「冠军杯赛 · 未开赛」", str((m._tabs.get_child(1) as Button).text) == "冠军杯赛 · 未开赛",
		str((m._tabs.get_child(1) as Button).text))
	_ok("③ 没成表 ⇒ 没有「冠军 · 名字」那一行", not m._champ_lb.visible)
	m.queue_free()
	await _frames(2)

	print("── ④ 成表(20:05) ──")
	P2C.now_override_ts = t1
	var cup := {"bucket": P2C.FINALS_CUP_BUCKET, "n": 2, "round": 1, "closed": false,
		"round_at": t1 - 30, "revealed_at": 0, "next_at": t1 - 30 + 480, "done": {},
		"entrants": [_ent(0, "我龟", ME), _ent(1, "丁龟", "uid-d")]}
	_set_bodies(t1, cup)
	_reqs.clear()
	SB.finals_clear()
	SB.finals_week_clear()
	m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	_ok("④ ★★成表 ⇒ 默认切到冠军杯赛", str(m._view) == L.VIEW_FINALS, str(m._view))
	_ok("④ ★分母: 画的是杯那一张(2 人、组号 = 保留组号、我是 0 号)", int(m.cur().get("size", 0)) == 2
		and int(m.cur().get("bucket", -1)) == P2C.FINALS_CUP_BUCKET and int(m.cur().get("me", -9)) == 0, str(m.cur().get("bucket")))
	_ok("④ 页签「冠军杯赛」", str((m._tabs.get_child(1) as Button).text) == "冠军杯赛")
	_ok("④ ★★我那一场能打", m.should_fetch_opponent(1, 0) and m.my_opponent_seed(1, 0) == 1)
	## 购物窗那一行每拍算一次(轮询 0.5 秒一拍); 杯那一张是上一拍才到手的。
	## ★收包时刻对齐到钉住的钟: 剩余秒数 = 服务端钟 + (本屏的「现在」− 收包时刻), 而收包时刻是真实系统钟,
	##   门禁把「现在」钉在周日 ⇒ 不对齐的话差出好几天(产品里两者是同一个钟, 差不出来)。
	m._finals["recv_at"] = t1
	m._on_poll()
	await _frames(1)
	var shop := str(m._shop_row.text)
	_ok("④ ★★购物窗跟着杯那一张(我那组早收盘了, 用组那张会说「已结束」)", shop.begins_with("备战购物 · 还剩 2 分 30 秒"), shop)
	_ok("④ ★倒计时跟着杯那一张", m._tip.visible and str(m._tip.text).find("后开播") >= 0, str(m._tip.text))
	var nb := _find_btn(m, Vector2i(1, 0))
	_ok("④ ★分母: 那一格有热区按钮", nb != null)
	if nb != null:
		nb.pressed.emit()
		await _frames(1)
		var go: Button = null
		for c in _all(m):
			if c is Button and str(c.name) == BMS.N_POPUP_GO:
				go = c
		_ok("④ 弹卡主按钮「开始对战」", go != null and go.text == "开始对战", go.text if go != null else "(没有)")
		var info := ""
		for c in _all(m):
			if c is Label and str((c as Label).text).find("冠军杯赛") >= 0:
				info = str((c as Label).text)
		_ok("④ 弹卡副标写「决赛 · 冠军杯赛」(不是「第 1000001 组」)", info == "决赛 · 冠军杯赛", info)
		_reqs.clear()
		if go != null:
			go.pressed.emit()
			await _frames(3)
		var oq := _reqs_to("/finals_opponent")
		_ok("④ ★分母: 真的去问了对手", oq.size() == 1, "%d" % oq.size())
		if oq.size() == 1:
			var ob: Dictionary = JSON.parse_string(str(oq[0]["body"]))
			_ok("④ ★★★问对手带的是杯的组号、对手 1 号种子", int(ob.get("p_bucket", -1)) == P2C.FINALS_CUP_BUCKET
				and int(ob.get("p_seed", -1)) == 1 and int(ob.get("p_round", -1)) == 1, str(ob))
	m._await_match = Vector2i(-1, -1)

	print("── ⑤ 报结果(小组赛与冠军杯赛同坐标 1-0) ──")
	SB.finals_report_clear()
	_reqs.clear()
	GameState.battle_seed = 4242
	BMS.stamp_finals_match(GameState, 0, 1, 0, 0, t1)
	Backend.report_finals_if_any(true)
	await _frames(3)
	BMS.stamp_finals_match(GameState, P2C.FINALS_CUP_BUCKET, 1, 0, 0, t1)
	Backend.report_finals_if_any(false)
	await _frames(3)
	var rq := _reqs_to("/finals_report")
	_ok("⑤ ★★★两场都真的发出去了(去重带组号, 杯那一场没被当成「报过了」)", rq.size() == 2, "%d 条" % rq.size())
	if rq.size() == 2:
		var b1: Dictionary = JSON.parse_string(str(rq[1]["body"]))
		_ok("⑤ ★第二条报的是杯: 组号 = 保留组号、我输 ⇒ 报对手那一侧", int(b1.get("p_bucket", -1)) == P2C.FINALS_CUP_BUCKET
			and int(b1.get("p_winner_side", -1)) == 1, str(b1))
	_ok("⑤ ★分母: 报成了按组号记账", SB.finals_reported(1, 0, P2C.FINALS_CUP_BUCKET) and SB.finals_reported(1, 0, 0))
	_ok("⑤ ★★待揭晓那一单带杯的组号", int(GameState.finals_pending_reveal.get("bucket", -1)) == P2C.FINALS_CUP_BUCKET,
		str(GameState.finals_pending_reveal))
	_ok("⑤ 开局那一刻的阶段 = 决赛日(按决赛日结算)", str(GameState.week_phase) == P2C.PHASE_FINALS)
	m.queue_free()
	await _frames(2)

	print("── ⑥ 翻面开播(决赛在开播窗口里) ──")
	var t2 := t1 + 500
	P2C.now_override_ts = t2
	var cup2 := cup.duplicate(true)
	cup2["closed"] = true
	cup2["done"] = {"1-0": 1}
	cup2["revealed_at"] = t2 - 20
	_set_bodies(t2, cup2)
	var wins0 := int(GameState.season_wins)
	SB.finals_clear()
	SB.finals_week_clear()
	m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	_ok("⑥ ★分母: 杯已收盘、在冠军杯赛页", bool(m._finals.get("closed", false)) and str(m._view) == L.VIEW_FINALS, str(m._view))
	_ok("⑥ ★★决赛在开播窗口里 ⇒ 格子状态 = 开播(不显示胜负)", m.match_state(1, 0) == BMS.ST_PREMIERE, m.match_state(1, 0))
	_ok("⑥ ★★★开播窗口里没有「冠军 · 名字」(名字就是剧透)", not m._champ_lb.visible and m.cup_champion_line() == "",
		m.cup_champion_line())
	_ok("⑥ ★★★揭晓按杯那一张: 我决赛输 ⇒ 胜场不加(拿小组赛那张会算成赢)", int(GameState.season_wins) == wins0,
		"%d → %d" % [wins0, int(GameState.season_wins)])
	_ok("⑥ ★分母: 那一单确实揭晓了(清掉了)", (GameState.finals_pending_reveal as Dictionary).is_empty(),
		str(GameState.finals_pending_reveal))
	m.queue_free()
	await _frames(2)

	print("── ⑦ 窗口过后 ──")
	var t3 := t2 + 600
	P2C.now_override_ts = t3
	_set_bodies(t3, cup2)
	SB.finals_clear()
	SB.finals_week_clear()
	m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	var tg := P2C.player_tag("uid-d")
	_ok("⑦ ★★顶上「冠军 · 丁龟 #ID」", m._champ_lb.visible and str(m._champ_lb.text) == "冠军 · 丁龟 " + tg,
		str(m._champ_lb.text))
	_ok("⑦ 决赛格显示胜负了", m.match_state(1, 0) == BMS.ST_DONE and m.winner_side(1, 0) == 1)
	_ok("⑦ ★★★我(冠军杯赛决赛输) ⇒【亚军】+【组冠军】", P2C.title_has(GameState.titles, P2C.TITLE_RUNNER_UP, _wk)
		and P2C.title_has(GameState.titles, P2C.TITLE_GROUP_CHAMPION, _wk), str(GameState.titles))
	_ok("⑦ ★★★没有【冠军】(冠军是丁龟)", not P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, _wk), str(GameState.titles))
	_ok("⑦ ★分母: 杯进度记进存档字段", int(GameState.finals_cup_total) == 1 and bool(GameState.finals_cup_runner_up)
		and not bool(GameState.finals_cup_champion))
	## 回放上传: 杯里那一场要等杯那一张翻面
	var e := {"ph": RU.PH_FINALS, "wk": _wk, "fk": {"b": P2C.FINALS_CUP_BUCKET, "r": 1, "m": 0, "s": 0}}
	_ok("⑦ ★★杯里那一场: 杯翻面后才放行上传(上传判据看得到杯那一张)", RU.finals_upload_ready(e, t3, RU._cached_buckets()))
	_ok("⑦ ★分母: 杯没翻面时不放行", not RU.finals_upload_ready(e, t3, [cup]))
	## 看回放: 请求带杯的组号
	_reqs.clear()
	m.open_replay(1, 0)
	await _frames(3)
	var rp := _reqs.filter(func(r): return str(r["url"]).find("finals_replay") >= 0)
	_ok("⑦ ★★看回放问的是杯的组号", rp.size() >= 1 and str(rp[0]["body"]).find(str(P2C.FINALS_CUP_BUCKET)) >= 0,
		str(rp[0]["body"]) if not rp.is_empty() else "(没发)")
	m.queue_free()
	await _frames(2)


# ─────────────────────────────────────────────────────────────
# ⑧ 1 人表: 本周只有一个组
# ─────────────────────────────────────────────────────────────
func _t_solo() -> void:
	print("── ⑧ 1 人冠军杯赛 ──")
	_reset_gs()
	var t := _wk + 6 * 86400 + 20 * 3600 + 10 * 60
	P2C.now_override_ts = t
	## 一个 4 人组: 我(决赛输)⇒ 组冠军是别人; 冠军杯赛只有他 1 人
	var done := {"1-0": 0, "1-1": 0, "2-0": 0}
	var me_seed := -1
	var champ := B.champion_seed(4, done)
	for s0 in range(4):
		if bool(B.my_progress(s0, 4, done).get("runner_up", false)):
			me_seed = s0
	_ok("⑧ ★分母: 这份结果里算得出冠军与亚军", champ >= 0 and me_seed >= 0 and champ != me_seed, "冠 %d 亚 %d" % [champ, me_seed])
	var names := ["阿龟", "小乙", "老丙", "丁丁"]
	var ents: Array = []
	for s1 in range(4):
		ents.append(_ent(s1, names[s1], ME if s1 == me_seed else "uid-g%d" % s1))
	var g := {"bucket": 0, "n": 4, "round": 2, "closed": true, "round_at": 0, "revealed_at": 0, "done": done, "entrants": ents}
	var cup := {"bucket": P2C.FINALS_CUP_BUCKET, "n": 1, "round": 1, "closed": true, "round_at": t - 600,
		"revealed_at": t - 600, "done": {}, "entrants": [_ent(0, names[champ], "uid-g%d" % champ)]}
	var gm := g.duplicate(true)
	gm["ok"] = true
	gm["now"] = t
	_mine_body = JSON.stringify(gm)
	_week_body = JSON.stringify({"ok": true, "week": _wk, "now": t, "buckets": [g], "cup": cup})
	SB.finals_clear()
	SB.finals_week_clear()
	var m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	_ok("⑧ ★1 人表也算成表 ⇒ 晚上默认看冠军杯赛", str(m._view) == L.VIEW_FINALS, str(m._view))
	var et := str(m._empty_lb.text)
	_ok("⑧ ★★分类 = 直接夺冠", str(m._empty_kind()) == BMS.EK_CUP_SOLO, str(m._empty_kind()))
	_ok("⑧ ★★写出「直接夺冠」和冠军名字", et.find("直接夺冠") >= 0 and et.find("冠军 · " + names[champ]) >= 0, et)
	_ok("⑧ 页签「冠军杯赛」(不缀未开赛)", str((m._tabs.get_child(1) as Button).text) == "冠军杯赛")
	_ok("⑧ ★★★我(组决赛输) ⇒ 冠亚四强组冠军一个都没有(不再拿组里的名次兜底)",
		not P2C.title_has(GameState.titles, P2C.TITLE_RUNNER_UP, _wk) and not P2C.title_has(GameState.titles, P2C.TITLE_SEMIFINAL, _wk)
		and not P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, _wk)
		and not P2C.title_has(GameState.titles, P2C.TITLE_GROUP_CHAMPION, _wk), str(GameState.titles))
	m.queue_free()
	await _frames(2)
	## 我就是那 1 人 ⇒【冠军】
	_reset_gs()
	var cup_me := cup.duplicate(true)
	cup_me["entrants"] = [_ent(0, "我龟", ME)]
	_week_body = JSON.stringify({"ok": true, "week": _wk, "now": t, "buckets": [g], "cup": cup_me})
	SB.finals_clear()
	SB.finals_week_clear()
	m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	_ok("⑧ ★★★1 人冠军杯赛就是我 ⇒【冠军】, 没有亚军", P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, _wk)
		and not P2C.title_has(GameState.titles, P2C.TITLE_RUNNER_UP, _wk), str(GameState.titles))
	m.queue_free()
	await _frames(2)


## 1 人组(N=3: 三个 1 人组, 上午没有对局, 20:00 三人进冠军杯赛)
func _t_group_solo() -> void:
	print("── ⑧b 1 人组 ──")
	_reset_gs()
	var noon := _wk + 6 * 86400 + 12 * 3600
	P2C.now_override_ts = noon
	var gs: Array = []
	var nm := ["我龟", "乙龟", "丙龟"]
	for i in range(3):
		gs.append({"bucket": i, "n": 1, "round": 1, "closed": true, "round_at": noon - 3600, "revealed_at": noon - 3600,
			"done": {}, "entrants": [_ent(0, nm[i], ME if i == 0 else "uid-s%d" % i)]})
	var gm: Dictionary = (gs[0] as Dictionary).duplicate(true)
	gm["ok"] = true
	gm["now"] = noon
	_mine_body = JSON.stringify(gm)
	_week_body = JSON.stringify({"ok": true, "week": _wk, "now": noon, "buckets": gs, "cup": null})
	SB.finals_clear()
	SB.finals_week_clear()
	var m = BMS.new()
	add_child(m)
	await _frames(3)
	m._on_poll()
	await _frames(2)
	var et := str(m._empty_lb.text)
	_ok("⑧b ★★分类 = 1 人组(直接晋级)", str(m._bucket_kind()) == BMS.EK_GROUP_SOLO and str(m._view) == L.VIEW_BUCKET,
		"%s / %s" % [str(m._bucket_kind()), str(m._view)])
	_ok("⑧b ★★页签「小组赛 · 直接晋级」", str((m._tabs.get_child(0) as Button).text) == "小组赛 · 直接晋级",
		str((m._tabs.get_child(0) as Button).text))
	_ok("⑧b ★★正文说清去向: 「第 1 组仅 1 人 · 直接晋级冠军杯赛」+ 开赛时刻", et.begins_with("第 1 组仅 1 人 · 直接晋级冠军杯赛")
		and et.find("开赛") >= 0 and m._empty_lb.visible, et)
	_ok("⑧b ★★★1 人组的那一位 ⇒【组冠军】(不设门槛)", P2C.title_has(GameState.titles, P2C.TITLE_GROUP_CHAMPION, _wk),
		str(GameState.titles))
	m.pick_view(L.VIEW_FINALS)
	await _frames(1)
	var ct := str(m._empty_lb.text)
	_ok("⑧b ★冠军杯赛开赛前名单列出三个 1 人组的冠军", ct.find("我龟") >= 0 and ct.find("乙龟") >= 0 and ct.find("丙龟") >= 0
		and ct.find("全部产生 · 共 3 组") >= 0, ct)
	m.queue_free()
	await _frames(2)
	## 2 人组(N=9~16 时的常态): 只有决赛一格 ⇒ 必须在屏幕正中、够宽(实拍抓到过被推到最右边、名字撞小签)
	var m2 = BMS.new()
	add_child(m2)
	await _frames(1)
	m2.set_data({"size": 2, "round": 1, "me": 0, "names": ["我龟", "乙龟"], "done": {}, "bucket": 2}, {}, noon)
	await _frames(2)
	var nb2: Button = _find_btn(m2, Vector2i(1, 0))
	var vpw: float = get_viewport().get_visible_rect().size.x
	var gr: Rect2 = nb2.get_global_rect() if nb2 != null else Rect2()
	_ok("⑧b ★★2 人组那一格在屏幕正中且够宽", nb2 != null and absf(gr.get_center().x - vpw * 0.5) < 2.0 and gr.size.x >= 280.0,
		"中心 %.1f / 屏宽 %.0f / 宽 %.0f" % [gr.get_center().x, vpw, gr.size.x])
	m2.queue_free()
	await _frames(2)


# ─────────────────────────────────────────────────────────────
# ⑨ 排行榜头衔(纯函数)
# ─────────────────────────────────────────────────────────────
func _pb(no: int, n: int, closed: bool, done: Dictionary, accs: Array) -> Dictionary:
	return {"bucket": no, "size": n, "closed": closed, "done": done, "accs": accs}


func _t_leaderboard() -> void:
	print("── ⑨ 排行榜头衔 ──")
	var groups := [_pb(0, 2, true, {"1-0": 0}, ["a", "b"]), _pb(1, 2, true, {"1-0": 1}, ["c", "d"])]
	var no_cup: Dictionary = LB.finals_titles(groups, {})
	_ok("⑨ ★★杯没成表 ⇒ 组冠军挂「组冠军」, 不挂冠军", str(no_cup.get("a", {}).get("id", "")) == P2C.TITLE_GROUP_CHAMPION
		and str(no_cup.get("d", {}).get("id", "")) == P2C.TITLE_GROUP_CHAMPION, str(no_cup))
	_ok("⑨ 败者挂进入决赛日", str(no_cup.get("b", {}).get("id", "")) == P2C.TITLE_FINALS_DAY)
	var cup := _pb(P2C.FINALS_CUP_BUCKET, 2, true, {"1-0": 1}, ["a", "d"])
	var with_cup: Dictionary = LB.finals_titles(groups, cup)
	_ok("⑨ ★★★杯决赛赢的 d ⇒ 冠军; 输的 a ⇒ 亚军", str(with_cup.get("d", {}).get("id", "")) == P2C.TITLE_CHAMPION
		and str(with_cup.get("a", {}).get("id", "")) == P2C.TITLE_RUNNER_UP, str(with_cup))
	_ok("⑨ ★冠军/亚军那条的「打完没有」跟着杯走", bool(with_cup.get("d", {}).get("closed", false)))
	_ok("⑨ 排行榜挂得出「组冠军」字样", LB.row_mark(P2C.PHASE_FINALS, "", {"id": P2C.TITLE_GROUP_CHAMPION, "closed": true}) == "组冠军")
	var solo_g := [_pb(0, 4, true, {"1-0": 0, "1-1": 0, "2-0": 0}, ["p0", "p1", "p2", "p3"])]
	var champ := B.champion_seed(4, {"1-0": 0, "1-1": 0, "2-0": 0})
	var solo: Dictionary = LB.finals_titles(solo_g, _pb(P2C.FINALS_CUP_BUCKET, 1, true, {}, ["p%d" % champ]))
	var n_other := 0
	for k in solo:
		if str(solo[k]["id"]) in [P2C.TITLE_RUNNER_UP, P2C.TITLE_SEMIFINAL]:
			n_other += 1
	_ok("⑨ ★★★单组 + 1 人杯: 那一人挂冠军, 组里没有亚军 / 四强", str(solo.get("p%d" % champ, {}).get("id", "")) == P2C.TITLE_CHAMPION
		and n_other == 0, str(solo))
	var ones := [_pb(0, 1, true, {}, ["x0"]), _pb(1, 1, true, {}, ["x1"])]
	var t1: Dictionary = LB.finals_titles(ones, {})
	_ok("⑨ ★★1 人组 ⇒ 各挂「组冠军」", str(t1.get("x0", {}).get("id", "")) == P2C.TITLE_GROUP_CHAMPION
		and str(t1.get("x1", {}).get("id", "")) == P2C.TITLE_GROUP_CHAMPION, str(t1))


# ─────────────────────────────────────────────────────────────
# ⑩ 分组容量: SQL 与规格逐个人数对
# ─────────────────────────────────────────────────────────────
func _t_sizing() -> void:
	print("── ⑩ 分组容量 ──")
	var seg := _seg(_read(MIGRATION))
	var fn := _fn(seg, "finals_bucket_size")
	## 把 SQL 的 case 原样读出来: `when n <= X then Y` 依次 + `else Z`(只认这一种写法; 读不出来 ⇒ 分母红)
	var re := RegEx.new()
	re.compile("when n <= (\\d+) then (\\d+)")
	var arms: Array = []
	for mt in re.search_all(fn):
		arms.append([int(mt.get_string(1)), int(mt.get_string(2))])
	var re2 := RegEx.new()
	re2.compile("else (\\d+)")
	var el = re2.search(fn)
	_ok("⑩ ★分母: 读出 SQL 的分档(n<=0/8/16/32/64/128 共 6 档 + else)", arms.size() == 6 and el != null, "%d 档" % arms.size())
	var bad: Array = []
	for n in range(1, 1001):
		var sql := int(el.get_string(1)) if el != null else -1
		for arm in arms:
			if n <= int(arm[0]):
				sql = int(arm[1])
				break
		if sql != B.bucket_size_for(n):
			bad.append("N=%d SQL %d / 规格 %d" % [n, sql, B.bucket_size_for(n)])
	_ok("⑩ ★★★每组人数: SQL 与 bracket.bucket_size_for 在 N=1..1000 逐个一致", bad.is_empty(), str(bad.slice(0, 3)))
	var st := _fn(seg, "finals_seat")
	_ok("⑩ ★★1 人组坐下即收盘(finals_seat 重新定义在本段里)", st.find("count(*) = 1,") >= 0
		and st.find("case when count(*) = 1 then now() else null end") >= 0, "%d 字" % st.length())
	_ok("⑩ ★全周只有 1 人仍不开赛", st.find("if total < 2 then") >= 0)
