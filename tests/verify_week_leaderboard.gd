extends Node
## verify_week_leaderboard — 排行榜读**服务端**的本周榜, 问不到才退回本机记录(并在屏上标出来)
## (2026-10-06 · 60 人实操严重项 A2)
##
## 由来: 实操截图 `tour_07_leaderboard` 前 9 行全是「1 胜」, 而那几个号几小时前已经打到 9-6 / 10-6。
##   原来的榜是 `Backend.leaderboard(本机快照池)` 拼的 —— 新玩家只拉过场次 N / N+1 的快照,
##   那是「我碰巧拉到过的那一份」, 不是排行榜。
##
## 五节, 全部走**真入口**(实例化 `Leaderboard.tscn`, 网络走 `SupabaseNet._transport_for_test`,
##   量的是**真实发出去的请求**与**屏上真画出来的字**):
##   ① SQL 静态: 起止标记唯一 / security definer / 本周过滤 / 每账号最新一行 / 胜场→余命→横扫 / 只读
##   ② 没配后端 ⇒ 一个请求都不发, 画本机记录且标「本机记录」
##   ③ 服务端 12 行(末行是我·第 20 名)⇒ 屏上就是服务端那几行(名字 + 胜场逐行对), 我钉在末行且名次 20
##   ③b 服务端只在 `me` 里给我(不在 rows 里)⇒ 同样钉在末行、名次 20
##   ④ 请求失败(断网 / 404)⇒ 退回本机记录, 屏上有「本机记录」标记
##
## 跑法: QUIET=1 TURTLE_SUPABASE=" " godot --headless --path . res://tests/verify_week_leaderboard.tscn --quit-after 3000

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")

const SCHEMA := "res://server/supabase/schema.sql"
const MIGRATION := "res://server/supabase/migrations/20261006_week_leaderboard.sql"
const MARK_BEGIN := "-- >>> BEGIN week_leaderboard 20261006-A2 >>>"
const MARK_END := "-- <<< END week_leaderboard 20261006-A2 <<<"

const WEEK := 1790467200          # 假周号(只是个数, 请求体里要原样出现)
const ME := "uid-gate-me"
const ME_NAME := "我自己龟"
## 本机池里那份**过期**的快照: 名字服务端榜上一个都没有 ⇒ 屏上出现它 = 画的是本机那一路。
const STALE := ["旧快照甲", "旧快照乙", "旧快照丙"]

var _n := 0
var _fail := 0
var _reqs: Array = []
var _reply: Dictionary = {}
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
	print("=== 本周排行榜: 服务端优先 / 本机兜底且标明 ===")
	_t_sql()
	var acc0 := str(GameState.account_id)
	var wk0 := int(GameState.week_anchor_ts)
	GameState.week_anchor_ts = WEEK
	BE.pool_override = _stale_pool()
	await _t_off()
	await _t_server()
	await _t_fail()
	## 收尾: static 活过本测试, 全部还原
	BE.pool_override = {}
	GameState.account_id = acc0
	GameState.week_anchor_ts = wk0
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 本周排行榜" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① SQL 静态核对
# ─────────────────────────────────────────────────────────────
func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().replace("\r\n", "\n")


func _segment(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b := t.find(MARK_END)
	if a < 0 or b < a:
		return ""
	return t.substr(a, b + MARK_END.length() - a)


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


func _t_sql() -> void:
	print("── ① SQL 静态 ──")
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
	var c := _code_of(seg)
	_ok("① ★security definer + 定死 search_path", c.find("security definer set search_path = public") >= 0)
	_ok("① ★只认本周: season_week = p_week", c.find("where g.season_week = p_week") >= 0)
	## 每账号最新一行: distinct on (account_id) + 场次倒序在前(同场次再按上传时刻)
	_ok("① ★每个账号只留最新一行: distinct on (account_id) ... order by account_id, battles desc, uploaded_at desc",
		c.find("distinct on (g.account_id)") >= 0
		and c.find("order by g.account_id, g.battles desc, g.uploaded_at desc") >= 0)
	## 名次的排序键: 胜场 → 余命 → 横扫(与 Backend.leaderboard 的 cmp 同一个字典序)
	var re := RegEx.new()
	re.compile("row_number\\(\\) over \\( order by ([^)]*)\\)")
	var m := re.search(c)
	var keys := m.get_string(1) if m != null else ""
	_ok("① ★分母: 找到名次那一句 row_number() over (order by …)", keys != "", keys)
	_ok("① ★★名次排序 = 胜场 desc → 余命 desc → 横扫 desc(严格这个先后)",
		keys.begins_with("l.season_wins desc, l.hearts desc, l.season_sweeps desc"), keys)
	_ok("① 陪练不上榜(seed_ 前缀, 与 Backend.is_sparring 同一判据)",
		c.find("left(coalesce(g.snapshot ->> 'ghost_id', ''), 5) <> 'seed_'") >= 0)
	_ok("① 机器人不上榜(is_bot)", c.find("coalesce(g.snapshot ->> 'is_bot', 'false') <> 'true'") >= 0)
	_ok("① 我自己那一行(me)按 auth.uid() 认", c.find("filter (where r.account_id = auth.uid())") >= 0)
	_ok("① 授权: 只给 authenticated, 收回 anon",
		c.find("grant execute on function public.week_leaderboard(bigint, int) to authenticated") >= 0
		and c.find("revoke execute on function public.week_leaderboard(bigint, int) from anon") >= 0)
	var bad := []
	for w in ["insert into", "update ", "delete from", "alter table", "create table", "drop ", "truncate"]:
		if c.find(w) >= 0:
			bad.append(w)
	_ok("① ★只读: 不建表/改表/写行", bad.is_empty(), str(bad))


# ─────────────────────────────────────────────────────────────
# 工装
# ─────────────────────────────────────────────────────────────
func _stale_pool() -> Dictionary:
	var pool: Dictionary = {BE.POOL_KEY: {}}
	for i in range(STALE.size()):
		BE.pool_add(pool, {"schema_ver": BE.SCHEMA_VER, "ghost_id": "wlb_stale_%d" % i, "is_bot": false,
			"origin": BE.ORIGIN_REMOTE, "profile": {"name": STALE[i]},
			"season_wins": 1, "hearts": 6, "season_sweeps": 0, "season_total_battles": 1})
	return pool


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body), "headers": str(headers)})
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard"):
		cb.call(_reply)
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
	for _i in range(6):
		await get_tree().process_frame
	return inst


## 屏上画出来的数据行(按 y 从上到下): {rank: 文本, name, wins: 文本, you: bool}
## ★读 `_body` 下真建出来的 Label, 位置用本屏自己的列常量认列(判据不另抄一份坐标)。
func _screen_rows(inst: Node) -> Array:
	var body: Control = inst.get("_body")
	if body == null:
		return []
	var by_y := {}
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
			elif absf(l.position.x - (LB.STAT_X0 + LB.STAT_ICON + 4.0)) < 0.5:
				col = "wins"
		elif ch is Panel and absf((ch as Panel).position.x - LB.RANK_X) < 0.5:
			y = (ch as Panel).position.y
			col = "rank"
			for g in ch.get_children():
				if g is Label:
					txt = str((g as Label).text)
		elif ch is Panel and (ch as Panel).position.x > LB.NAME_X:
			for g in ch.get_children():
				if g is Label and str((g as Label).text) == "你":
					y = -2.0
					by_y["you_y"] = (ch as Panel).position.y
		if col == "" or y < 0.0:
			continue
		var k := int(round(y))
		if not by_y.has(k):
			by_y[k] = {"y": k}
		(by_y[k] as Dictionary)[col] = txt
	var out: Array = []
	var ys := []
	for k in by_y.keys():
		if str(k) != "you_y" and (by_y[k] as Dictionary).has("name") and str((by_y[k] as Dictionary)["name"]) != "—":
			ys.append(k)
	ys.sort()
	for k in ys:
		var r: Dictionary = by_y[k]
		r["you"] = by_y.has("you_y") and absf(float(by_y["you_y"]) - float(k)) < ROW_TOL
		out.append(r)
	return out

const ROW_TOL := 10.0


func _mark_text(inst: Node) -> String:
	var body: Control = inst.get("_body")
	if body == null:
		return ""
	for ch in body.get_children():
		if ch is Label and str(ch.name) == "LbSourceMark" and (ch as Label).is_visible_in_tree():
			return str((ch as Label).text)
	return ""


func _all_text(n: Node) -> String:
	var s := ""
	for ch in n.get_children():
		if ch is Label:
			s += str((ch as Label).text) + "|"
		s += _all_text(ch)
	return s


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
	inst.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ③ 服务端回 12 行, 末行是我·第 20 名
# ─────────────────────────────────────────────────────────────
const SRV_NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将",
	"浪里白条", "霜甲先生", "赤焰小将", "沙洲隐士", "雷纹守卫"]
const TOTAL := 57


func _srv_row(i: int) -> Dictionary:
	return {"rank": i + 1, "name": SRV_NAMES[i], "tag": "", "account_id": "uid-srv-%d" % i,
		"wins": 14 - i, "hearts": 6 - (i % 3), "sweeps": int((11 - i) / 2.0)}


func _me_row() -> Dictionary:
	return {"rank": 20, "name": ME_NAME, "tag": "", "account_id": ME, "wins": 3, "hearts": 2, "sweeps": 1}


func _check_server_screen(label: String, inst: Node) -> void:
	_ok("%s ★分母: 画的是服务端那一路" % label, str(inst.get("source")) == LB.SRC_SERVER, str(inst.get("source")))
	var rows := _screen_rows(inst)
	print("    [屏上] ", rows.map(func(r): return "%s/%s/%s%s" % [r.get("rank", "?"), r.get("name", "?"),
		r.get("wins", "?"), " 你" if bool(r.get("you", false)) else ""]))
	## 面板画得下 11 行, 我在第 20 名 ⇒ 前 9 名 + ⋯ + 我 = 10 行数据
	_ok("%s ★分母: 屏上数据行 = 前 9 名 + 我 = 10" % label, rows.size() == 10, "%d 行" % rows.size())
	var bad := []
	for i in range(mini(9, rows.size())):
		var r: Dictionary = rows[i]
		var want := _srv_row(i)
		if str(r.get("name", "")) != str(want["name"]) or str(r.get("wins", "")) != str(want["wins"]) \
				or str(r.get("rank", "")) != str(want["rank"]):
			bad.append("第%d行 屏上 %s/%s/%s ≠ 服务端 %s/%s/%s" % [i + 1, r.get("rank", "?"), r.get("name", "?"),
				r.get("wins", "?"), want["rank"], want["name"], want["wins"]])
	_ok("%s ★★前 9 行逐行 = 服务端的名次/名字/胜场" % label, bad.is_empty() and rows.size() >= 9, str(bad))
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	_ok("%s ★★我钉在末行: 名字是我、带「你」签" % label,
		str(last.get("name", "")) == ME_NAME and bool(last.get("you", false)), str(last))
	_ok("%s ★★我的名次是服务端给的 20(不是屏上下标)" % label, str(last.get("rank", "")) == "20",
		str(last.get("rank", "")))
	_ok("%s 我的胜场是服务端的 3" % label, str(last.get("wins", "")) == "3", str(last.get("wins", "")))
	var all := _all_text(inst)
	_ok("%s ★本机那份过期快照一行都没画出来" % label,
		all.find(STALE[0]) < 0 and all.find(STALE[1]) < 0, "")
	_ok("%s 没有「本机记录」标记(这是实时榜)" % label, _mark_text(inst) == "" and all.find(LB.FALLBACK_MARK) < 0)
	_ok("%s 「本周共 %d 人上榜」用的是服务端的总人数" % [label, TOTAL], all.find("本周共 %d 人上榜" % TOTAL) >= 0)


func _t_server() -> void:
	print("── ③ 服务端榜 ──")
	_backend_on(true)
	GameState.account_id = ME
	_ok("③ ★分母: 后端真的打开了(关着的话下面全是空检查)", SB.enabled())
	var rows := []
	for i in range(11):
		rows.append(_srv_row(i))
	rows.append(_me_row())
	_reply = {"ok": true, "code": 200, "body": JSON.stringify(
		{"ok": true, "week": WEEK, "total": TOTAL, "rows": rows, "me": _me_row()})}
	_reqs.clear()
	var inst := await _open()
	var wl: Array = _reqs.filter(func(r): return str(r["url"]).ends_with("/rest/v1/rpc/week_leaderboard"))
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
	inst.queue_free()
	await get_tree().process_frame

	print("── ③b 我不在 rows 里, 只在 me 里 ──")
	var rows11 := []
	for i in range(11):
		rows11.append(_srv_row(i))
	_reply = {"ok": true, "code": 200, "body": JSON.stringify(
		{"ok": true, "week": WEEK, "total": TOTAL, "rows": rows11, "me": _me_row()})}
	var inst2 := await _open()
	_check_server_screen("③b", inst2)
	inst2.queue_free()
	await get_tree().process_frame


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
		inst.queue_free()
		await get_tree().process_frame
	_backend_on(false)
	SB._transport_for_test = Callable()
	SB._token = ""
	_ok("④ ★收尾: 后端已关回去", not SB.enabled())
