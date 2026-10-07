extends Node
## verify_week_leaderboard — 排行榜读**服务端**的周榜, 问不到才退回本机记录(并在屏上标出来);
## 一周四天各是各的榜(2026-10-06 · 用户「积分赛写上名字，剩余生命，胜场，总场次啊 ，都给我做」)。
##
## 由来: 实操截图 `tour_07_leaderboard` 前 9 行全是「1 胜」, 而那几个号几小时前已经打到 9-6 / 10-6。
##   原来的榜是 `Backend.leaderboard(本机快照池)` 拼的 —— 新玩家只拉过场次 N / N+1 的快照,
##   那是「我碰巧拉到过的那一份」, 不是排行榜。
##
## 全部走**真入口**(实例化 `Leaderboard.tscn`, 网络走 `SupabaseNet._transport_for_test`,
##   时钟走 `phase2_config.now_override_ts`), 量的是**真实发出去的请求**与**屏上真画出来的字**:
##   ①  SQL v1 静态: 起止标记唯一 / security definer / 本周过滤 / 每账号最新一行 / 胜场→余命→横扫 / 只读
##   ①b SQL v2 静态: 同上 + 下发 battles(总场次)与 standings.title; 在 schema.sql 里排在 v1 之后(重放以 v2 为准)
##   ②  没配后端 ⇒ 一个请求都不发, 画本机记录且标「本机记录」, 且「本机记录」不压列名
##   ③  周二 · 服务端 12 行(末行是我·第 20 名)⇒ 名字/名次/剩余生命/胜场/总场次逐行 = 服务端
##   ③b 服务端只在 `me` 里给我(不在 rows 里)⇒ 同样钉在末行、名次 20
##   ④  请求失败(断网 / 404)⇒ 退回本机记录, 屏上有「本机记录」标记
##   ⑤  四天: 周一(上周终榜·请求上周锚点·冠军/亚军/四强/进决赛日) / 周二(本周排行·无标记无入口)
##       / 周六(积分赛终榜·已晋级·「全场赛况」→ GauntletBoard) / 周日(同上·「查看对阵图」→ BracketMap·
##       决赛打完才换挂冠军/亚军/四强)
##
## 跑法: QUIET=1 TURTLE_SUPABASE=" " godot --headless --path . res://tests/verify_week_leaderboard.tscn --quit-after 3000

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")

const SCHEMA := "res://server/supabase/schema.sql"
const MIGRATION := "res://server/supabase/migrations/20261006_week_leaderboard.sql"
const MARK_BEGIN := "-- >>> BEGIN week_leaderboard 20261006-A2 >>>"
const MARK_END := "-- <<< END week_leaderboard 20261006-A2 <<<"
const MIGRATION2 := "res://server/supabase/migrations/20261006b_week_leaderboard_v2.sql"
const MARK2_BEGIN := "-- >>> BEGIN week_leaderboard_v2 20261006b >>>"
const MARK2_END := "-- <<< END week_leaderboard_v2 20261006b <<<"

## 假周锚点: 一个**真的周一 00:00 UTC**(下面 ⑤ 把钟钉在这一周的周二/周六/周日、下一周的周一)。
const WEEK := 1790553600
const DAY := 86400
const ME := "uid-gate-me"
const ME_NAME := "我自己龟"
## 本机池里那份**过期**的快照: 名字服务端榜上一个都没有 ⇒ 屏上出现它 = 画的是本机那一路。
const STALE := ["旧快照甲", "旧快照乙", "旧快照丙"]

var _n := 0
var _fail := 0
var _reqs: Array = []
var _reply: Dictionary = {}
var _freply: Dictionary = {}
var _key0 = ""


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	GameState.test_mode = true
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	print("=== 周榜: 服务端优先 / 本机兜底且标明 / 一周四种榜 ===")
	_t_sql()
	_t_sql_v2()
	var acc0 := str(GameState.account_id)
	var wk0 := int(GameState.week_anchor_ts)
	var bt0 := int(GameState.season_total_battles)
	var ov0 := int(P2C.now_override_ts)
	GameState.week_anchor_ts = WEEK
	GameState.season_total_battles = 7
	P2C.now_override_ts = WEEK + DAY + 10 * 3600          # 周二 10:00
	BE.pool_override = _stale_pool()
	await _t_off()
	await _t_server()
	await _t_fail()
	await _t_days()
	## 收尾: static 活过本测试, 全部还原
	_backend_on(false)
	SB._transport_for_test = Callable()
	SB._token = ""
	BE.pool_override = {}
	P2C.now_override_ts = ov0
	GameState.account_id = acc0
	GameState.week_anchor_ts = wk0
	GameState.season_total_battles = bt0
	_ok("★收尾: 后端已关回去、钟已还原", not SB.enabled() and int(P2C.now_override_ts) == ov0)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 周榜" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① SQL 静态核对
# ─────────────────────────────────────────────────────────────
func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().replace("\r\n", "\n")


func _segment(t: String, mb: String = MARK_BEGIN, me: String = MARK_END) -> String:
	var a := t.find(mb)
	var b := t.find(me)
	if a < 0 or b < a:
		return ""
	return t.substr(a, b + me.length() - a)


## 只留代码(去掉 `--` 注释), 小写, 空白压成一格 —— 判据量的是 SQL 本身, 不是注释里写了什么。
func _code_of(seg: String) -> String:
	var out := PackedStringArray()
	for ln in seg.split("\n"):
		var i := ln.find("--")
		out.append(ln.substr(0, i) if i >= 0 else ln)
	var s := " ".join(out).to_lower()
	var re := RegEx.new()
	re.compile("\\s+")
	return re.sub(s, " ", true)


## 两版共用的口径核对(排序键 / 本周 / 最新一行 / 陪练机器人 / me / 授权 / 只读)。
func _check_sql_common(tag: String, c: String) -> void:
	_ok("%s ★security definer + 定死 search_path" % tag, c.find("security definer set search_path = public") >= 0)
	_ok("%s ★只认本周: season_week = p_week" % tag, c.find("where g.season_week = p_week") >= 0)
	_ok("%s ★每个账号只留最新一行: distinct on (account_id) ... order by account_id, battles desc, uploaded_at desc" % tag,
		c.find("distinct on (g.account_id)") >= 0
		and c.find("order by g.account_id, g.battles desc, g.uploaded_at desc") >= 0)
	var re := RegEx.new()
	re.compile("row_number\\(\\) over \\( order by ([^)]*)\\)")
	var m := re.search(c)
	var keys := m.get_string(1) if m != null else ""
	_ok("%s ★分母: 找到名次那一句 row_number() over (order by …)" % tag, keys != "", keys)
	_ok("%s ★★名次排序 = 胜场 desc → 余命 desc → 横扫 desc(严格这个先后)" % tag,
		keys.begins_with("l.season_wins desc, l.hearts desc, l.season_sweeps desc"), keys)
	_ok("%s 陪练不上榜(seed_ 前缀, 与 Backend.is_sparring 同一判据)" % tag,
		c.find("left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'") >= 0)
	_ok("%s 机器人不上榜(is_bot)" % tag, c.find("coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'") >= 0)
	_ok("%s 我自己那一行(me)按 auth.uid() 认" % tag, c.find("filter (where r.account_id = auth.uid())") >= 0)
	_ok("%s 授权: 只给 authenticated, 收回 anon" % tag,
		c.find("grant execute on function public.week_leaderboard(bigint, int) to authenticated") >= 0
		and c.find("revoke execute on function public.week_leaderboard(bigint, int) from anon") >= 0)
	var bad := []
	for w in ["insert into", "update ", "delete from", "alter table", "create table", "drop ", "truncate"]:
		if c.find(w) >= 0:
			bad.append(w)
	_ok("%s ★只读: 不建表/改表/写行" % tag, bad.is_empty(), str(bad))


func _t_sql() -> void:
	print("── ① SQL v1 静态 ──")
	var t := _read(SCHEMA)
	_ok("① ★分母: schema.sql 读得到", t.length() > 1000, "%d 字" % t.length())
	_ok("① ★起止标记在 schema.sql 里各恰好一次(主会话按它截段上线)",
		t.count(MARK_BEGIN) == 1 and t.count(MARK_END) == 1,
		"BEGIN %d / END %d" % [t.count(MARK_BEGIN), t.count(MARK_END)])
	var seg := _segment(t)
	var mig := _segment(_read(MIGRATION))
	_ok("① ★分母: 截到了那一段", seg.length() > 500, "%d 字" % seg.length())
	_ok("① 迁移文件那一段与 schema.sql 逐字相同(两份不许漂)", seg != "" and seg == mig,
		"%d / %d 字" % [seg.length(), mig.length()])
	_check_sql_common("①", _code_of(seg))


func _t_sql_v2() -> void:
	print("── ①b SQL v2 静态(总场次 + 头衔) ──")
	var t := _read(SCHEMA)
	_ok("①b ★v2 起止标记在 schema.sql 里各恰好一次", t.count(MARK2_BEGIN) == 1 and t.count(MARK2_END) == 1,
		"BEGIN %d / END %d" % [t.count(MARK2_BEGIN), t.count(MARK2_END)])
	var m2 := _read(MIGRATION2)
	_ok("①b ★v2 起止标记在迁移文件里各恰好一次", m2.count(MARK2_BEGIN) == 1 and m2.count(MARK2_END) == 1)
	var seg := _segment(t, MARK2_BEGIN, MARK2_END)
	var mig := _segment(m2, MARK2_BEGIN, MARK2_END)
	_ok("①b ★分母: 截到了 v2 那一段", seg.length() > 500, "%d 字" % seg.length())
	_ok("①b v2 迁移文件与 schema.sql 那一段逐字相同", seg != "" and seg == mig, "%d / %d 字" % [seg.length(), mig.length()])
	_ok("①b ★schema.sql 里 v2 排在 v1 之后(整份重放时最后生效的是 v2)",
		t.find(MARK2_BEGIN) > t.find(MARK_END) and t.find(MARK_END) > 0)
	var c := _code_of(seg)
	_check_sql_common("①b", c)
	_ok("①b ★最新一行带出 battles", c.find("g.account_id, g.season_wins, g.hearts, g.season_sweeps, g.battles") >= 0)
	_ok("①b ★★rows 与 me 两处都下发 'battles'(总场次)", c.count("'battles', r.battles") == 2,
		"%d 处" % c.count("'battles', r.battles"))
	_ok("①b ★头衔取 standings.title(左连接, 没有就空串), rows 与 me 两处都下发",
		c.find("left join public.standings s on s.season_week = p_week and s.account_id = l.account_id") >= 0
		and c.count("'title', coalesce(r.title, '')") == 2)
	_ok("①b 签名不变(create or replace 原地换函数体, 授权照旧)",
		c.find("create or replace function public.week_leaderboard(p_week bigint, p_limit int default 30)") >= 0)


# ─────────────────────────────────────────────────────────────
# 工装
# ─────────────────────────────────────────────────────────────
func _stale_pool() -> Dictionary:
	var pool: Dictionary = {BE.POOL_KEY: {}}
	for i in range(STALE.size()):
		BE.pool_add(pool, {"schema_ver": BE.SCHEMA_VER, "ghost_id": "wlb_stale_%d" % i, "is_bot": false,
			"origin": BE.ORIGIN_REMOTE, "profile": {"name": STALE[i]},
			"season_wins": 1, "hearts": P2C.HEARTS_MAX, "season_sweeps": 0, "season_total_battles": 1})
	return pool


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body), "headers": str(headers)})
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard"):
		cb.call(_reply)
	elif str(url).ends_with("/rest/v1/rpc/finals_week_view"):
		cb.call(_freply)
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _backend_on(on: bool) -> void:
	if on:
		OS.set_environment(SB.ENV_URL, "http://gate.local")
		ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
		SB._token = "gate-token"
		SB._expires_at = 0
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
		## ★令牌**照样给着**: 让「没配后端」成为唯一挡住请求的那道闸 ——
		##   令牌也空的话, 删掉 enabled() 那道闸请求照样发不出去(等令牌那步就停了), ② 会假绿。
		SB._token = "gate-token"
		SB._expires_at = 0
	SB._transport_for_test = _spy


func _open() -> Node:
	var inst: Node = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(8):
		await get_tree().process_frame
	return inst


func _close(inst: Node) -> void:
	inst.queue_free()
	await get_tree().process_frame


## 屏上画出来的数据行(按 y 从上到下): {rank, name, s0, s1, s2(三列成绩文本), mark, you: bool}
## ★读 `_body` 下真建出来的 Label, 位置用本屏自己的列常量认列(判据不另抄一份坐标)。
func _screen_rows(inst: Node) -> Array:
	var body: Control = inst.get("_body")
	if body == null:
		return []
	var by_y := {}
	var you_ys: Array = []
	for ch in body.get_children():
		var y := -1.0
		var col := ""
		var txt := ""
		if ch is Label:
			var l := ch as Label
			y = l.position.y
			txt = str(l.text)
			if absf(l.position.x - LB.NAME_X) < 0.5:
				col = "name"
			elif absf(l.position.x - LB.RANK_X) < 0.5:
				col = "rank"
			elif str(l.name).begins_with("RowMark_"):
				col = "mark"
				y -= 1.0
			else:
				for i in range(3):
					if absf(l.position.x - (LB.STAT_X0 + float(i) * LB.STAT_CELL)) < 0.5 and y >= LB.ROW_TOP - 1.0:
						col = "s%d" % i
		elif ch is Panel and absf((ch as Panel).position.x - LB.RANK_X) < 0.5:
			y = (ch as Panel).position.y
			col = "rank"
			for g in ch.get_children():
				if g is Label:
					txt = str((g as Label).text)
		elif ch is Panel and (ch as Panel).position.x > LB.NAME_X:
			for g in ch.get_children():
				if g is Label and str((g as Label).text) == "你":
					you_ys.append((ch as Panel).position.y)
		if col == "" or y < 0.0:
			continue
		var k := int(round(y))
		if not by_y.has(k):
			by_y[k] = {"y": k}
		(by_y[k] as Dictionary)[col] = txt
	var out: Array = []
	var ys := []
	for k in by_y.keys():
		if (by_y[k] as Dictionary).has("name") and str((by_y[k] as Dictionary)["name"]) != "—":
			ys.append(k)
	ys.sort()
	for k in ys:
		var r: Dictionary = by_y[k]
		r["you"] = false
		for yy in you_ys:
			if absf(float(yy) - float(k)) < ROW_TOL:
				r["you"] = true
		out.append(r)
	return out

const ROW_TOL := 10.0


func _label_named(inst: Node, nm: String) -> Label:
	var body: Control = inst.get("_body")
	if body == null:
		return null
	for ch in body.get_children():
		if ch is Label and str(ch.name) == nm and (ch as Label).is_visible_in_tree():
			return ch as Label
	return null


func _mark_text(inst: Node) -> String:
	var l := _label_named(inst, "LbSourceMark")
	return str(l.text) if l != null else ""


func _all_text(n: Node) -> String:
	var s := ""
	for ch in n.get_children():
		if ch is Label:
			s += str((ch as Label).text) + "|"
		s += _all_text(ch)
	return s


func _title_of(inst: Node) -> String:
	var tb = inst.get("_top_bar")
	if tb == null or tb.title_label == null:
		return ""
	return str(tb.title_label.text)


## 表头三列: 文字逐字 = 用户的词, 且与下面数字**右沿对齐**(≤1px)。
func _check_heads(tag: String, inst: Node, rows_n: int) -> void:
	var heads: Array = []
	var right_bad: Array = []
	var seen := 0
	var body: Control = inst.get("_body")
	for i in range(3):
		var h := _label_named(inst, "LbColHead%d" % i)
		heads.append(str(h.text) if h != null else "(缺)")
		if h == null or body == null:
			continue
		var hr: float = h.position.x + h.size.x
		for ch in body.get_children():
			if ch is Label and str(ch.name).begins_with("RowStat%d_" % i):
				seen += 1
				var cr: float = (ch as Label).position.x + (ch as Label).size.x
				if absf(cr - hr) > 1.0:
					right_bad.append("列%d %.1f≠%.1f" % [i, cr, hr])
	_ok("%s ★★表头三列 = 「剩余生命」「胜场」「总场次」(用户原词, 顺序不许乱)" % tag,
		heads == ["剩余生命", "胜场", "总场次"], str(heads))
	_ok("%s 表头与数字右沿对齐(≤1px)" % tag, right_bad.is_empty() and rows_n > 0 and seen >= rows_n * 3,
		"量了 %d 格 %s" % [seen, str(right_bad.slice(0, 3))])
	var icons := 0
	for ch in (body.get_children() if body != null else []):
		if ch is TextureRect:
			icons += 1
	_ok("%s 格里不画图标(用户「排行榜里的奖杯是？」)" % tag, icons == 0, "%d 个" % icons)


# ─────────────────────────────────────────────────────────────
# ② 没配后端 ⇒ 不发请求, 画本机记录且标明
# ─────────────────────────────────────────────────────────────
func _t_off() -> void:
	print("── ② 没配后端 ──")
	_backend_on(false)
	GameState.account_id = ME
	_ok("② ★分母: 后端确实是关着的", not SB.enabled())
	_reqs.clear()
	var inst := await _open()
	_ok("② ★★没配后端 ⇒ 一个请求都不发", _reqs.is_empty(), "%d 条 %s" % [_reqs.size(), str(_reqs)])
	_ok("② 画的是本机那一路", str(inst.get("source")) == LB.SRC_LOCAL, str(inst.get("source")))
	var rows := _screen_rows(inst)
	var names := rows.map(func(r): return str(r.get("name", "")))
	_ok("② ★分母: 屏上真画出了本机池里的行", names.has(STALE[0]), str(names))
	_ok("② ★★屏上标着「本机记录」", _mark_text(inst) == LB.FALLBACK_MARK, "「%s」" % _mark_text(inst))
	## ★「本机记录」不许压在列名/规模数上(2026-10-06 之前它占右半边, 正好压住列名)。
	var mk := _label_named(inst, "LbSourceMark")
	var clash: Array = []
	if mk != null:
		var mr := Rect2(mk.position, mk.size)
		for nm in ["LbColHead0", "LbColHead1", "LbColHead2", "LbCapLine"]:
			var o := _label_named(inst, nm)
			if o != null and mr.intersects(Rect2(o.position, o.size)):
				clash.append(nm)
	_ok("② ★★「本机记录」与列名/规模数互不相交", mk != null and clash.is_empty(), str(clash))
	var me_row: Dictionary = {}
	for r in rows:
		if bool(r.get("you", false)):
			me_row = r
	_ok("② 本机那一路: 我的总场次 = 存档里的 season_total_battles(7)", str(me_row.get("s2", "")) == "7", str(me_row))
	var stale_row: Dictionary = {}
	for r2 in rows:
		if str(r2.get("name", "")) == STALE[0]:
			stale_row = r2
	_ok("② 本机那一路: 别人的总场次 = 快照里的 season_total_battles(1)", str(stale_row.get("s2", "")) == "1", str(stale_row))
	_check_heads("②", inst, rows.size())
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ③ 服务端回 12 行, 末行是我·第 20 名(钟在周二)
# ─────────────────────────────────────────────────────────────
const SRV_NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将",
	"浪里白条", "霜甲先生", "赤焰小将", "沙洲隐士", "雷纹守卫"]
const TOTAL := 57


## 三个成绩两两错开(胜 14−i / 命 满命−(i%3) / 场 20+i), 列顺序调乱了逐行对账当场红。
func _srv_row(i: int) -> Dictionary:
	var hp: int = P2C.HEARTS_MAX - (i % 3)
	return {"rank": i + 1, "name": SRV_NAMES[i], "tag": "", "account_id": "uid-srv-%d" % i,
		"wins": 14 - i, "hearts": hp, "sweeps": i % 2, "battles": 20 + i, "title": null}


func _me_row() -> Dictionary:
	return {"rank": 20, "name": ME_NAME, "tag": "", "account_id": ME, "wins": 3, "hearts": 2, "sweeps": 1,
		"battles": 9, "title": null}


func _srv_reply(with_me_in_rows: bool) -> Dictionary:
	var rows := []
	for i in range(11):
		rows.append(_srv_row(i))
	if with_me_in_rows:
		rows.append(_me_row())
	return {"ok": true, "code": 200, "body": JSON.stringify(
		{"ok": true, "week": WEEK, "total": TOTAL, "rows": rows, "me": _me_row()})}


func _check_server_screen(label: String, inst: Node, cap_word: String = "本周") -> void:
	_ok("%s ★分母: 画的是服务端那一路" % label, str(inst.get("source")) == LB.SRC_SERVER, str(inst.get("source")))
	var rows := _screen_rows(inst)
	print("    [屏上] ", rows.map(func(r): return "%s/%s/%s/%s/%s%s%s" % [r.get("rank", "?"), r.get("name", "?"),
		r.get("s0", "?"), r.get("s1", "?"), r.get("s2", "?"), (" [" + str(r["mark"]) + "]") if r.has("mark") else "",
		" 你" if bool(r.get("you", false)) else ""]))
	## 面板画得下 11 行, 我在第 20 名 ⇒ 前 9 名 + ⋯ + 我 = 10 行数据
	_ok("%s ★分母: 屏上数据行 = 前 9 名 + 我 = 10" % label, rows.size() == 10, "%d 行" % rows.size())
	var bad := []
	for i in range(mini(9, rows.size())):
		var r: Dictionary = rows[i]
		var want := _srv_row(i)
		var got := [str(r.get("rank", "")), str(r.get("name", "")), str(r.get("s0", "")), str(r.get("s1", "")),
			str(r.get("s2", ""))]
		var exp := [str(want["rank"]), str(want["name"]), str(want["hearts"]), str(want["wins"]), str(want["battles"])]
		if got != exp:
			bad.append("第%d行 屏上 %s ≠ 服务端 %s" % [i + 1, str(got), str(exp)])
	_ok("%s ★★前 9 行逐行 = 服务端的 名次/名字/剩余生命/胜场/总场次" % label, bad.is_empty() and rows.size() >= 9, str(bad))
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	_ok("%s ★★我钉在末行: 名字是我、带「你」签" % label,
		str(last.get("name", "")) == ME_NAME and bool(last.get("you", false)), str(last))
	_ok("%s ★★我的名次是服务端给的 20(不是屏上下标)" % label, str(last.get("rank", "")) == "20",
		str(last.get("rank", "")))
	_ok("%s 我的 剩余生命/胜场/总场次 = 服务端的 2/3/9" % label,
		[str(last.get("s0", "")), str(last.get("s1", "")), str(last.get("s2", ""))] == ["2", "3", "9"], str(last))
	var all := _all_text(inst)
	_ok("%s ★本机那份过期快照一行都没画出来" % label,
		all.find(STALE[0]) < 0 and all.find(STALE[1]) < 0, "")
	_ok("%s 没有「本机记录」标记(这是实时榜)" % label, _mark_text(inst) == "" and all.find(LB.FALLBACK_MARK) < 0)
	_ok("%s 「%s共 %d 人上榜」用的是服务端的总人数" % [label, cap_word, TOTAL],
		all.find("%s共 %d 人上榜" % [cap_word, TOTAL]) >= 0)
	_check_heads(label, inst, rows.size())


func _wl_reqs() -> Array:
	return _reqs.filter(func(r): return str(r["url"]).ends_with("/rest/v1/rpc/week_leaderboard"))


func _fw_reqs() -> Array:
	return _reqs.filter(func(r): return str(r["url"]).ends_with("/rest/v1/rpc/finals_week_view"))


func _p_week_of(rq: Dictionary) -> int:
	var bj = JSON.parse_string(str(rq["body"]))
	return int((bj as Dictionary).get("p_week", 0)) if bj is Dictionary else 0


func _t_server() -> void:
	print("── ③ 服务端榜(周二) ──")
	_backend_on(true)
	GameState.account_id = ME
	P2C.now_override_ts = WEEK + DAY + 10 * 3600
	_ok("③ ★分母: 后端真的打开了(关着的话下面全是空检查)", SB.enabled())
	_reply = _srv_reply(true)
	_reqs.clear()
	var inst := await _open()
	var wl := _wl_reqs()
	_ok("③ ★分母: 真的发了 week_leaderboard 请求(恰好一次)", wl.size() == 1, "%d 条" % wl.size())
	if not wl.is_empty():
		var rq: Dictionary = wl[0]
		var bj = JSON.parse_string(str(rq["body"]))
		_ok("③ 请求 = POST, 带登录令牌", str(rq["method"]) == "POST"
			and str(rq["headers"]).find("Bearer gate-token") >= 0, str(rq["method"]))
		_ok("③ ★请求体键名与服务端参数对得上: p_week = 本周锚点, p_limit = %d" % SB.WEEK_LB_LIMIT,
			bj is Dictionary and int((bj as Dictionary).get("p_week", 0)) == WEEK
			and int((bj as Dictionary).get("p_limit", 0)) == SB.WEEK_LB_LIMIT, str(rq["body"]))
		_ok("③ 这条 RPC 算「读」(时间穿越期间不拦)", not SB.is_write_request("POST", str(rq["url"])))
	_check_server_screen("③", inst)
	await _close(inst)

	print("── ③b 我不在 rows 里, 只在 me 里 ──")
	_reply = _srv_reply(false)
	var inst2 := await _open()
	_check_server_screen("③b", inst2)
	await _close(inst2)


# ─────────────────────────────────────────────────────────────
# ④ 请求失败 ⇒ 退回本机记录, 屏上标明
# ─────────────────────────────────────────────────────────────
func _t_fail() -> void:
	print("── ④ 请求失败 ──")
	_backend_on(true)
	GameState.account_id = ME
	for cs in [["断网", {"ok": false, "code": 0, "body": ""}],
			["没部署(404)", {"ok": true, "code": 404,
				"body": '{"code":"PGRST202","message":"Could not find the function public.week_leaderboard"}'}]]:
		_reply = cs[1]
		_reqs.clear()
		var inst := await _open()
		_ok("④[%s] ★分母: 请求真的发了" % cs[0], _reqs.size() >= 1, "%d 条" % _reqs.size())
		_ok("④[%s] ★退回本机那一路" % cs[0], str(inst.get("source")) == LB.SRC_LOCAL, str(inst.get("source")))
		var names := _screen_rows(inst).map(func(r): return str(r.get("name", "")))
		_ok("④[%s] ★分母: 屏上是本机池里的行" % cs[0], names.has(STALE[0]), str(names))
		_ok("④[%s] ★★屏上标着「本机记录」" % cs[0], _mark_text(inst) == LB.FALLBACK_MARK,
			"「%s」" % _mark_text(inst))
		await _close(inst)


# ─────────────────────────────────────────────────────────────
# ⑤ 一周四天
# ─────────────────────────────────────────────────────────────
## 决赛一组 8 人(种子 0..7 = 服务端榜前 8 名), 每场上半区赢。closed 决定「打完没有」。
func _finals_reply(closed: bool) -> Dictionary:
	var ents := []
	for s in range(8):
		ents.append({"seed": s, "name": SRV_NAMES[s], "account_id": "uid-srv-%d" % s})
	var done := {}
	for m in range(4):
		done["1-%d" % m] = 0
	done["2-0"] = 0
	done["2-1"] = 0
	done["3-0"] = 0
	var b := {"bucket": 0, "n": 8, "round": 3, "closed": closed, "entrants": ents, "done": done}
	## ★★冠军杯赛(2026-10-07): 这一周只有一个组 ⇒ 组决赛打完后 20:00 冠军杯赛只有组冠军一人(直接夺冠)。
	##   冠亚四强只从冠军杯赛来(主会话 10-07) ⇒ 组里其余 7 人挂「进入决赛日」。组冠军 = 全 0 侧赢 ⇒ 0 号种子。
	var cup = null
	if closed:
		cup = {"bucket": P2C.FINALS_CUP_BUCKET, "n": 1, "round": 1, "closed": true, "done": {},
			"entrants": [{"seed": 0, "name": SRV_NAMES[0], "account_id": "uid-srv-0"}]}
	return {"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "now": 0,
		"buckets": [b], "cup": cup})}


## 独立算出这一组的冠军是谁(走对阵图「本周冠军」页那条 `champion_seed`, 不走排行榜自己的推导)。
func _expected_champion() -> String:
	var pf: Dictionary = SB.parse_finals_week(true, 200, str(_finals_reply(true)["body"]), "", 0)
	var bs: Array = pf.get("buckets", [])
	if bs.is_empty():
		return ""
	var sd: int = BMS.champion_seed(bs[0])
	return str(SRV_NAMES[sd]) if sd >= 0 and sd < SRV_NAMES.size() else ""


func _marks(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		if (r as Dictionary).has("mark"):
			out[str(r["name"])] = str(r["mark"])
	return out


func _count(d: Dictionary, v: String) -> int:
	var n := 0
	for k in d:
		if str(d[k]) == v:
			n += 1
	return n


func _entry_method(inst: Node) -> String:
	var b = inst.get("entry_btn")
	if b == null or not (b is Button):
		return ""
	for c in (b as Button).pressed.get_connections():
		return str((c["callable"] as Callable).get_method())
	return "(未连接)"


func _t_days() -> void:
	_backend_on(true)
	GameState.account_id = ME
	var pw: int = P2C.PROMOTE_WINS
	var n_prom := 0
	for i in range(9):
		if int(_srv_row(i)["wins"]) >= pw:
			n_prom += 1
	_ok("⑤ ★分母: 前 9 行里晋级与没晋级的都有(PROMOTE_WINS=%d)" % pw, n_prom > 0 and n_prom < 9, "%d 人" % n_prom)
	var champ := _expected_champion()
	_ok("⑤ ★分母: 独立算得出这组决赛的冠军", champ != "", champ)

	## ── 周一: 上周终榜 ──
	print("── ⑤ 周一(下一周的周一 → 看 WEEK 那一周) ──")
	P2C.now_override_ts = WEEK + 7 * DAY + 10 * 3600
	_reply = _srv_reply(true)
	_freply = _finals_reply(true)
	_reqs.clear()
	var mon := await _open()
	_ok("⑤一 ★分母: 钟真的在周一", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_REST)
	var wl := _wl_reqs()
	_ok("⑤一 ★★请求的是**上周**的周锚点(本周锚点 − 7 天)", wl.size() == 1 and _p_week_of(wl[0]) == WEEK,
		"p_week=%s 应为 %d" % [str(_p_week_of(wl[0])) if not wl.is_empty() else "(没发)", WEEK])
	var fw := _fw_reqs()
	_ok("⑤一 决赛头衔也问的是上周那一周", fw.size() == 1 and _p_week_of(fw[0]) == WEEK, "%d 条" % fw.size())
	_ok("⑤一 ★标题 = 🏆 上周终榜", _title_of(mon) == LB.TITLE_ICON + "上周终榜", _title_of(mon))
	_ok("⑤一 周一没有顶栏入口", mon.get("entry_btn") == null)
	_check_server_screen("⑤一", mon, "上周")
	var mk := _marks(_screen_rows(mon))
	print("    [头衔] ", mk)
	_ok("⑤一 ★★冠军挂在独立算出的那个人名字旁", str(mk.get(champ, "")) == "冠军", "%s → %s" % [champ, str(mk.get(champ, ""))])
	_ok("⑤一 ★8 人组 + 1 人冠军杯赛: 冠军 1 / 亚军 0 / 四强 0 / 进决赛日 7",
		_count(mk, "冠军") == 1 and _count(mk, "亚军") == 0 and _count(mk, "四强") == 0 and _count(mk, "进入决赛日") == 7,
		str(mk))
	_ok("⑤一 不在决赛里的人不挂(第 9 名起)", not mk.has(SRV_NAMES[8]) and not mk.has(ME_NAME), str(mk.keys()))
	_ok("⑤一 周一不挂「已晋级」", _count(mk, LB.MARK_PROMOTED) == 0)
	await _close(mon)

	## ── 周二: 本周排行 ──
	print("── ⑤ 周二 ──")
	P2C.now_override_ts = WEEK + DAY + 10 * 3600
	_reqs.clear()
	var tue := await _open()
	_ok("⑤二 ★标题 = 🏆 本周排行", _title_of(tue) == LB.TITLE_ICON + "本周排行", _title_of(tue))
	_ok("⑤二 请求的是本周锚点", _wl_reqs().size() == 1 and _p_week_of(_wl_reqs()[0]) == WEEK)
	_ok("⑤二 不问决赛", _fw_reqs().is_empty())
	_ok("⑤二 没有顶栏入口", tue.get("entry_btn") == null)
	var tr := _screen_rows(tue)
	_ok("⑤二 ★分母: 有行", tr.size() == 10, "%d" % tr.size())
	_ok("⑤二 ★积分赛进行中 ⇒ 一个标记都不挂(胜场够了也不挂)", _marks(tr).is_empty(), str(_marks(tr)))
	await _close(tue)

	## ── 周六: 积分赛终榜 + 已晋级 + 全场赛况 ──
	print("── ⑤ 周六 ──")
	P2C.now_override_ts = WEEK + 5 * DAY + 15 * 3600
	_reqs.clear()
	var sat := await _open()
	_ok("⑤六 ★分母: 钟真的在周六", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET)
	_ok("⑤六 ★标题 = 🏆 积分赛终榜", _title_of(sat) == LB.TITLE_ICON + "积分赛终榜", _title_of(sat))
	_ok("⑤六 请求的是本周锚点", _wl_reqs().size() == 1 and _p_week_of(_wl_reqs()[0]) == WEEK)
	var sr := _screen_rows(sat)
	var smk := _marks(sr)
	var prom_bad: Array = []
	for r in sr:
		var w := int(str(r.get("s1", "-1")))
		var want := LB.MARK_PROMOTED if w >= pw else ""
		if str(r.get("mark", "")) != want:
			prom_bad.append("%s 胜%d 挂「%s」" % [r.get("name", "?"), w, r.get("mark", "")])
	_ok("⑤六 ★★胜场 ≥ %d 的挂「已晋级」、其余不挂(逐行)" % pw, prom_bad.is_empty() and sr.size() == 10, str(prom_bad))
	_ok("⑤六 ★分母: 真的挂出了 %d 个「已晋级」" % n_prom, _count(smk, LB.MARK_PROMOTED) == n_prom, str(smk))
	var sb = sat.get("entry_btn")
	_ok("⑤六 ★★顶栏入口 = 「全场赛况」(与主菜单那扇门同一个字)",
		sb is Button and str((sb as Button).text) == MM.GAUNTLET_BOARD_LINE and MM.GAUNTLET_BOARD_LINE == "全场赛况",
		str((sb as Button).text) if sb is Button else "(没有)")
	_ok("⑤六 ★★入口连的是 _open_gauntlet_board, 目标 = 主菜单同一个场景 GauntletBoard(且场景文件存在)",
		_entry_method(sat) == "_open_gauntlet_board"
		and str(LB.day_entry(P2C.PHASE_GAUNTLET).get("scene", "")) == MM.GAUNTLET_BOARD_SCENE
		and ResourceLoader.exists("res://scenes/%s.tscn" % MM.GAUNTLET_BOARD_SCENE), _entry_method(sat))
	_ok("⑤六 入口在屏内且够大(触控下限 81)", sb is Button and (sb as Button).size.y >= 81.0
		and (sb as Button).get_global_rect().end.x <= 1280.5, str((sb as Button).get_global_rect()) if sb is Button else "")
	await _close(sat)

	## ── 周日: 积分赛终榜 + 查看对阵图; 决赛没打完 ⇒ 仍是「已晋级」, 打完 ⇒ 冠军/亚军/四强 ──
	print("── ⑤ 周日(决赛还在打) ──")
	P2C.now_override_ts = WEEK + 6 * DAY + 20 * 3600
	_freply = _finals_reply(false)
	_reqs.clear()
	var sun0 := await _open()
	_ok("⑤日 ★分母: 钟真的在周日", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_FINALS)
	_ok("⑤日 ★标题 = 🏆 积分赛终榜", _title_of(sun0) == LB.TITLE_ICON + "积分赛终榜", _title_of(sun0))
	_ok("⑤日 问的是本周的决赛", _fw_reqs().size() == 1 and _p_week_of(_fw_reqs()[0]) == WEEK)
	var m0 := _marks(_screen_rows(sun0))
	_ok("⑤日 决赛没打完 ⇒ 不挂冠军/亚军/四强, 照旧「已晋级」",
		_count(m0, "冠军") + _count(m0, "亚军") + _count(m0, "四强") == 0 and _count(m0, LB.MARK_PROMOTED) == n_prom,
		str(m0))
	var ub = sun0.get("entry_btn")
	_ok("⑤日 ★★顶栏入口 = 「查看对阵图」→ _open_bracket_map → BracketMap(主菜单同一个场景)",
		ub is Button and str((ub as Button).text) == "查看对阵图" and _entry_method(sun0) == "_open_bracket_map"
		and str(LB.day_entry(P2C.PHASE_FINALS).get("scene", "")) == MM.BRACKET_SCENE
		and ResourceLoader.exists("res://scenes/%s.tscn" % MM.BRACKET_SCENE),
		"%s / %s" % [str((ub as Button).text) if ub is Button else "(没有)", _entry_method(sun0)])
	await _close(sun0)

	print("── ⑤ 周日(决赛打完) ──")
	_freply = _finals_reply(true)
	var sun1 := await _open()
	var m1 := _marks(_screen_rows(sun1))
	print("    [头衔] ", m1)
	_ok("⑤日 ★★决赛打完 ⇒ 冠军挂在独立算出的那个人名字旁", str(m1.get(champ, "")) == "冠军", str(m1))
	_ok("⑤日 打完: 冠军 1 / 亚军 0 / 四强 0; 其余晋级者仍挂「已晋级」、周日不挂「进决赛日」",
		_count(m1, "冠军") == 1 and _count(m1, "亚军") == 0 and _count(m1, "四强") == 0
		and _count(m1, "进入决赛日") == 0, str(m1))
	await _close(sun1)
