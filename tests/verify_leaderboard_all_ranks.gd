extends Node
## verify_leaderboard_all_ranks — 排行榜**所有名次都翻得到**, 「我」钉在列表下沿, 「我的位置」一键滚到我那一行。
##
## 由来: 用户 2026-10-19「排行榜你学一下其他游戏的，开放所有排名」。
##   原来服务端只回前 30 名, 屏上只画 11 行(前 9 名 + ⋯ + 我) —— 第 10 名到第 N 名谁都看不到。
##   参考(docs/plans/ref/20261019-排行榜参考/): 荒野乱斗 / 使命召唤手游 / Flash Party 列表可滚、自己钉底;
##   Golf Clash 列表直接滚到自己那一段。
##
## 全部走**真入口**: 实例化 `Leaderboard.tscn`, 网络走 `SupabaseNet._transport_for_test`(假服务端照 SQL 的
##   `rk > p_offset and rk <= p_offset + p_limit` 按页切), 量的是**真建出来的行节点上的字**与**真发出去的请求**。
##   ① 服务端 137 人、我第 118 名: 开屏只取第 1 页 / 列表长 137 / 钉住那一行 = 我·118·「你」
##   ② 一路往下滚到底: 每一页都真去取了(offset 0/50/100), 最后一行 = 第 137 名的名字与成绩, 一路上没有一行停在「待取」
##   ③ 滚回顶 → 按「我的位置」: 第 118 名那一行整行落在滚动区里、带「你」签与整行底签, 滚动位置 = (118-1-4)×40
##   ④ 我不在榜上(服务端 me 为空): 钉住那一行名次画「—」, 「我的位置」置灰
##   ⑤ 本机那一路(没配后端)120 人 + 我: 列表长 121, 滚到底是最后一名, 「我的位置」同样落到我
##   ⑥ 触摸: 行里没有吞触摸的控件(否则手指按在行上拖不动列表); 「我的位置」热区 ≥ 81 且在屏内
##   ⑦ 两个比例(16:9 1280×720 / 19.5:9 1560×720): 面板、列表、钉住那一行都在视口内
##   ⑧ 屏上没有「机器人 / 陪练 / bot」字样(用户 10-04: 机器人对手不许露馅)
##
## 跑法: TURTLE_SUPABASE=" " godot --headless --path . res://tests/verify_leaderboard_all_ranks.tscn --quit-after 6000

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

## 钉在一个周三(积分赛日, 本周榜)。
const WEEK := 1790553600
const DAY := 86400
const ME := "uid-allranks-me"
const ME_NAME := "我自己龟"
const TOTAL := 137
const ME_RANK := 118

var _n := 0
var _fail := 0
var _reqs: Array = []
var _me_on_board := true
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
	var acc0 := str(GameState.account_id)
	var ov0 := int(P2C.now_override_ts)
	P2C.now_override_ts = WEEK + 2 * DAY + 12 * 3600
	print("=== 排行榜: 全部名次 / 钉住我 / 我的位置 ===")
	_ok("⓪ ★分母: 钟在积分赛日(本周榜)", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_RANKED,
		P2C.phase_at_utc(P2C.now_utc()))
	GameState.account_id = ME
	await _t_server()
	await _t_not_on_board()
	await _t_local()
	await _t_ratios()
	## 收尾: static 活过本测试, 全部还原
	_backend_on(false)
	SB._transport_for_test = Callable()
	SB._token = ""
	BE.pool_override = {}
	P2C.now_override_ts = ov0
	GameState.account_id = acc0
	get_tree().root.size = Vector2i(1280, 720)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 排行榜全部名次" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# 工装: 假服务端
# ─────────────────────────────────────────────────────────────
## 第 rk 名那一行。胜场/命按名次单调下降(名次越后越少), 三个成绩两两错开, 列错位一眼红。
func _row(rk: int) -> Dictionary:
	if rk == ME_RANK:
		return {"rank": rk, "name": ME_NAME, "tag": "", "account_id": ME, "wins": 2, "hearts": 3,
			"sweeps": 0, "battles": 11, "title": null}
	return {"rank": rk, "name": "龟友%03d" % rk, "tag": "", "account_id": "uid-ar-%d" % rk,
		"wins": maxi(0, 15 - rk / 10), "hearts": P2C.HEARTS_MAX - (rk % P2C.HEARTS_MAX), "sweeps": rk % 2, "battles": 16 - (rk % 5),
		"title": null}


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard_page"):
		var bj = JSON.parse_string(str(body))
		var off: int = int((bj as Dictionary).get("p_offset", 0)) if bj is Dictionary else 0
		var lim: int = int((bj as Dictionary).get("p_limit", 50)) if bj is Dictionary else 50
		var rows := []
		for rk in range(off + 1, mini(TOTAL, off + lim) + 1):
			if rk == ME_RANK and not _me_on_board:
				rows.append(_row(rk).merged({"account_id": "uid-ar-%d" % rk, "name": "龟友%03d" % rk}, true))
			else:
				rows.append(_row(rk))
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "total": TOTAL,
			"offset": off, "rows": rows, "me": _row(ME_RANK) if _me_on_board else null})})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _backend_on(on: bool) -> void:
	if on:
		OS.set_environment(SB.ENV_URL, "http://gate.local")
		ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
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


func _page_offsets() -> Array:
	var out := []
	for r in _reqs:
		if str(r["url"]).ends_with("/rest/v1/rpc/week_leaderboard_page"):
			var bj = JSON.parse_string(str(r["body"]))
			out.append(int((bj as Dictionary).get("p_offset", -1)) if bj is Dictionary else -1)
	return out


## 一行节点上的字: {rank, name, s0, s1, s2, you, band(整行底签的染色或 null)}。
func _read_row(row: Control) -> Dictionary:
	var r := {"you": false, "band": null}
	for ch in row.get_children():
		if ch is Label:
			var l := ch as Label
			if absf(l.position.x - LB.NAME_X) < 0.5:
				r["name"] = str(l.text)
			elif absf(l.position.x - LB.RANK_X) < 0.5:
				r["rank"] = str(l.text)
			else:
				for i in range(3):
					if absf(l.position.x - (LB.STAT_X0 + float(i) * LB.STAT_CELL)) < 0.5:
						r["s%d" % i] = str(l.text)
		elif str(ch.name).begins_with("RowHearts_"):
			## ★2026-10-24 剩余生命画成心形: 屏上读法 = **数红心贴图**(不信 `hearts` 元数据)。
			var lit := 0
			for hc in ch.get_children():
				if hc is TextureRect and (hc as TextureRect).texture != null \
						and (hc as TextureRect).texture.resource_path == LB.HEART_TEX:
					lit += 1
			r["s0"] = str(lit)
		elif ch is Panel:
			var p := ch as Panel
			if absf(p.position.x - LB.RANK_X) < 0.5:
				for g in p.get_children():
					if g is Label:
						r["rank"] = str((g as Label).text)
			elif p.size.x > LB.PANEL_W * 0.8:
				var sb = p.get_theme_stylebox("panel")
				if sb is StyleBoxTexture:
					r["band"] = (sb as StyleBoxTexture).modulate_color
			else:
				for g in p.get_children():
					if g is Label and str((g as Label).text) == "你":
						r["you"] = true
	return r


## 两个染色差得够不够(与 verify_leaderboard_header 的 `_far` 同一把尺)。
func _far(a: Color, c: Color) -> bool:
	return absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b) > 0.15


## 现在建着的列表行: 名次 → 节点。
func _built(inst: Node) -> Dictionary:
	var out := {}
	var lst = inst.get("_list")
	if not (lst is Control):
		return out
	for ch in (lst as Control).get_children():
		if str(ch.name).begins_with("LbRow_") and not ch.is_queued_for_deletion():
			out[int(str(ch.name).substr(6))] = ch
	return out


## 这一行整行都在滚动区的可见框里吗(全局坐标)。
func _fully_visible(inst: Node, row: Control) -> bool:
	var sc = inst.get("_scroll")
	if not (sc is Control):
		return false
	var vis: Rect2 = (sc as Control).get_global_rect().grow(0.5)
	return vis.encloses(row.get_global_rect())


## 期望的格子字(与 `_stat_cell` 同口径: 数字原样)。
func _want(rk: int) -> Array:
	var w := _row(rk)
	return [str(rk), str(w["name"]), str(w["hearts"]), str(w["wins"]), str(w["battles"])]


func _got(r: Dictionary) -> Array:
	return [str(r.get("rank", "")), str(r.get("name", "")), str(r.get("s0", "")), str(r.get("s1", "")),
		str(r.get("s2", ""))]


func _all_text(n: Node) -> String:
	var s := ""
	for ch in n.get_children():
		if ch is Label:
			s += str((ch as Label).text) + "|"
		elif ch is Button:
			s += str((ch as Button).text) + "|"
		s += _all_text(ch)
	return s


# ─────────────────────────────────────────────────────────────
# ①②③⑥⑧ 服务端 137 人
# ─────────────────────────────────────────────────────────────
func _t_server() -> void:
	print("── ① 服务端 %d 人, 我第 %d 名 ──" % [TOTAL, ME_RANK])
	_backend_on(true)
	_me_on_board = true
	_ok("① ★分母: 后端真的打开了", SB.enabled())
	_reqs.clear()
	var inst := await _open()
	_ok("① ★分母: 画的是服务端那一路", str(inst.get("source")) == LB.SRC_SERVER, str(inst.get("source")))
	_ok("① ★★开屏只取第 1 页(offset 0)", _page_offsets() == [0], str(_page_offsets()))
	_ok("① ★★列表长 = 全榜人数 %d(不是前 30 名)" % TOTAL, int(inst.get("list_len")) == TOTAL,
		str(inst.get("list_len")))
	var b0 := _built(inst)
	var ks: Array = b0.keys()
	ks.sort()
	_ok("① 只建了露出来的那几行(第 1~%d 名), 不是把 %d 行全建出来" % [LB.VIS_ROWS, TOTAL],
		ks == range(1, LB.VIS_ROWS + 1), str(ks))
	var pin = inst.get("_pin")
	var pr: Dictionary = _read_row(pin as Control) if pin is Control else {}
	_ok("① ★★钉住那一行 = 我 · 第 %d 名 · 带「你」签" % ME_RANK,
		str(pr.get("name", "")) == ME_NAME and str(pr.get("rank", "")) == str(ME_RANK) and bool(pr.get("you", false)),
		str(pr))
	_ok("① 钉住那一行的成绩 = 服务端的我(剩余生命/胜场/总场次)", _got(pr) == _want(ME_RANK), str(_got(pr)))
	## ★2026-10-23 排行榜重做: 现在每一行都是一张行卡(都有整行底签) ⇒ 「有底签」不再说明什么,
	##   要守的是「钉住那张和普通行(第 4 名起)那张颜色不一样」。
	var b5: Dictionary = _built(inst)
	var plain = (_read_row(b5[5] as Control) if b5.has(5) else {}).get("band", null)
	_ok("① 钉住那一行有整行底签, 且颜色不同于普通行卡(不是只把字换个颜色)", pr.get("band", null) != null
		and plain != null and _far(pr["band"] as Color, plain as Color), "%s / 普通行 %s" % [str(pr.get("band", null)), str(plain)])
	var all := _all_text(inst)
	_ok("⑧ 屏上没有「机器人 / 陪练 / bot」字样", all.find("机器人") < 0 and all.find("陪练") < 0
		and all.to_lower().find("bot") < 0, "")

	## ⑥ 触摸: 行里一个吞触摸的控件都没有(签牌/斑马纹默认 STOP, 会挡住列表拖动)。
	var stop: Array = []
	var stk: Array = [inst.get("_list")]
	while not stk.is_empty():
		var nd = stk.pop_back()
		if nd is Control and nd != inst.get("_list") and (nd as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			stop.append(str((nd as Node).name))
		stk.append_array((nd as Node).get_children())
	_ok("⑥ ★行里没有吞触摸的控件(手指按在行上也拖得动列表)", stop.is_empty(), str(stop.slice(0, 4)))
	var jb = inst.get("jump_btn")
	_ok("⑥ ★分母: 顶栏有「我的位置」", jb is Button and str((jb as Button).text) == LB.JUMP_TEXT,
		str((jb as Button).text) if jb is Button else "(没有)")
	if jb is Button:
		var jr: Rect2 = (jb as Button).get_global_rect()
		_ok("⑥ 「我的位置」热区 ≥ 81 且整颗在屏内", jr.size.y >= 81.0 and jr.size.x >= 81.0
			and Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size)).grow(0.5).encloses(jr), str(jr))
		_ok("⑥ 我在榜上 ⇒ 「我的位置」可按", not (jb as Button).disabled)

	## ── ② 一路滚到底 ──
	print("── ② 一路往下滚到最后一名 ──")
	var sc: ScrollContainer = inst.get("_scroll")
	var visited := {}
	var pending_seen: Array = []
	var bad_rows: Array = []
	var steps := 0
	var v := 0
	var vmax: int = int(float(TOTAL - LB.VIS_ROWS) * LB.ROW_H)
	## 第一轮不滚(先把开屏那一屏记上), 之后每步往下 3 行。
	while steps < 200:
		if steps > 0:
			v = mini(v + int(LB.ROW_H * 3.0), vmax)
			sc.scroll_vertical = v
			await get_tree().process_frame
		steps += 1
		for rk in _built(inst).keys():
			var r := _read_row(_built(inst)[rk] as Control)
			visited[int(rk)] = true
			if not r.has("name"):
				pending_seen.append(int(rk))
			elif _got(r) != _want(int(rk)):
				bad_rows.append("第%d名 屏上 %s ≠ %s" % [int(rk), str(_got(r)), str(_want(int(rk)))])
		if sc.scroll_vertical >= vmax:
			break
	_ok("② ★分母: 真的滚到了底(scroll_vertical = %d)" % vmax, sc.scroll_vertical == vmax,
		"%d / %d 步" % [sc.scroll_vertical, steps])
	_ok("② ★★%d 个名次一个不落都上过屏" % TOTAL, visited.size() == TOTAL, "%d 个" % visited.size())
	var offs := _page_offsets()
	offs.sort()
	_ok("② ★★每一页都真去取了(offset 0 / 50 / 100), 且每页只取一次", offs == [0, 50, 100], str(offs))
	_ok("② 一路上没有一行停在「待取」(只有名次没名字)", pending_seen.is_empty(), str(pending_seen.slice(0, 5)))
	_ok("② ★★上过屏的每一行 = 服务端那一名的 名次/名字/剩余生命/胜场/总场次", bad_rows.is_empty(),
		str(bad_rows.slice(0, 3)))
	var bl := _built(inst)
	var last_r: Dictionary = _read_row(bl[TOTAL] as Control) if bl.has(TOTAL) else {}
	_ok("② ★★最后一行 = 第 %d 名(%s)" % [TOTAL, str(_row(TOTAL)["name"])], _got(last_r) == _want(TOTAL), str(last_r))
	_ok("② 最后一行整行在滚动区里", bl.has(TOTAL) and _fully_visible(inst, bl[TOTAL] as Control))
	var pr2: Dictionary = _read_row(inst.get("_pin") as Control)
	_ok("② 滚到底时钉住的仍是我(第 %d 名)" % ME_RANK, str(pr2.get("rank", "")) == str(ME_RANK)
		and str(pr2.get("name", "")) == ME_NAME, str(pr2))
	var kk: Array = bl.keys()
	kk.sort()
	_ok("② 滚到底时也只建着一屏左右的行(≤ %d)" % (LB.VIS_ROWS + 1), kk.size() <= LB.VIS_ROWS + 1, str(kk))

	## ── ③ 滚回顶 → 「我的位置」 ──
	print("── ③ 滚回顶, 按「我的位置」 ──")
	sc.scroll_vertical = 0
	await get_tree().process_frame
	_ok("③ ★分母: 先回到了顶(第 %d 名那一行不在屏上)" % ME_RANK, sc.scroll_vertical == 0
		and not _built(inst).has(ME_RANK), str(sc.scroll_vertical))
	_reqs.clear()
	if jb is Button:
		(jb as Button).pressed.emit()
	for _i in range(3):
		await get_tree().process_frame
	var want_s: int = int(float(ME_RANK - 1 - LB.JUMP_ABOVE) * LB.ROW_H)
	_ok("③ ★★滚动位置 = (%d-1-%d)×%d = %d" % [ME_RANK, LB.JUMP_ABOVE, int(LB.ROW_H), want_s],
		sc.scroll_vertical == want_s, "%d" % sc.scroll_vertical)
	var bm := _built(inst)
	_ok("③ ★★第 %d 名那一行建出来了并且整行落在滚动区里" % ME_RANK, bm.has(ME_RANK)
		and _fully_visible(inst, bm[ME_RANK] as Control), str(bm.keys()))
	if bm.has(ME_RANK):
		var mr := _read_row(bm[ME_RANK] as Control)
		_ok("③ ★那一行是我: 名字 + 「你」签 + 成绩 = 服务端的我", str(mr.get("name", "")) == ME_NAME
			and bool(mr.get("you", false)) and _got(mr) == _want(ME_RANK), str(mr))
		## ★2026-10-23: 每行都有行卡 ⇒ 高亮 = 我那张与上下两名那两张颜色不一样(照 Golf Clash 列表里自己那行高亮)。
		var nb_up = (_read_row(bm[ME_RANK - 1] as Control) if bm.has(ME_RANK - 1) else {}).get("band", null)
		var nb_dn = (_read_row(bm[ME_RANK + 1] as Control) if bm.has(ME_RANK + 1) else {}).get("band", null)
		_ok("③ 那一行有整行底签且与上下两名的行卡颜色不同(列表里也高亮, 照 Golf Clash)", mr.get("band", null) != null
			and nb_up != null and nb_dn != null and _far(mr["band"] as Color, nb_up as Color)
			and _far(mr["band"] as Color, nb_dn as Color), "%s / 上 %s / 下 %s" % [str(mr.get("band", null)), str(nb_up), str(nb_dn)])
		var up: Dictionary = _read_row(bm[ME_RANK - 1] as Control) if bm.has(ME_RANK - 1) else {}
		var dn: Dictionary = _read_row(bm[ME_RANK + 1] as Control) if bm.has(ME_RANK + 1) else {}
		_ok("③ 我上下两名也在屏上(看得到「附近」)", _got(up) == _want(ME_RANK - 1) and _got(dn) == _want(ME_RANK + 1),
			"%s / %s" % [str(_got(up)), str(_got(dn))])
	_ok("③ 跳过去不重复取已经取过的页", _page_offsets().is_empty(), str(_page_offsets()))
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ④ 我不在榜上
# ─────────────────────────────────────────────────────────────
func _t_not_on_board() -> void:
	print("── ④ 我本周一份都没传过(服务端 me 为空) ──")
	_backend_on(true)
	_me_on_board = false
	_reqs.clear()
	var inst := await _open()
	_ok("④ ★分母: 服务端那一路", str(inst.get("source")) == LB.SRC_SERVER, str(inst.get("source")))
	var pr: Dictionary = _read_row(inst.get("_pin") as Control)
	_ok("④ ★★钉住那一行仍是我, 名次画「—」(不编一个名次)", str(pr.get("rank", "")) == "—"
		and bool(pr.get("you", false)), str(pr))
	var jb = inst.get("jump_btn")
	_ok("④ ★「我的位置」置灰(榜上没有我, 无处可跳)", jb is Button and (jb as Button).disabled)
	var sc: ScrollContainer = inst.get("_scroll")
	if jb is Button:
		jump_noop(inst)
	_ok("④ 置灰时直接调也不滚", sc != null and sc.scroll_vertical == 0, str(sc.scroll_vertical) if sc != null else "")
	_me_on_board = true
	await _close(inst)


func jump_noop(inst: Node) -> void:
	inst.call("jump_to_me")


# ─────────────────────────────────────────────────────────────
# ⑤ 本机那一路 120 人 + 我
# ─────────────────────────────────────────────────────────────
const LOCAL_N := 120

func _t_local() -> void:
	print("── ⑤ 本机那一路(没配后端) %d 人 + 我 ──" % LOCAL_N)
	_backend_on(false)
	_ok("⑤ ★分母: 后端关着", not SB.enabled())
	var pool: Dictionary = {BE.POOL_KEY: {}}
	for i in range(LOCAL_N):
		BE.pool_add(pool, {"schema_ver": BE.SCHEMA_VER, "ghost_id": "lbar_%d" % i, "is_bot": false,
			"origin": BE.ORIGIN_REMOTE, "profile": {"name": "本机龟%03d" % i},
			"season_wins": 20 - i / 6, "hearts": P2C.HEARTS_MAX - (i % P2C.HEARTS_MAX), "season_sweeps": 0, "season_total_battles": 9})
	BE.pool_override = pool
	var w0 := int(GameState.season_wins)
	var h0 := int(GameState.hearts)
	GameState.season_wins = 5
	GameState.hearts = 1
	var inst := await _open()
	_ok("⑤ ★分母: 本机那一路", str(inst.get("source")) == LB.SRC_LOCAL, str(inst.get("source")))
	var ll := int(inst.get("list_len"))
	_ok("⑤ ★★列表长 = %d 人 + 我 = %d" % [LOCAL_N, LOCAL_N + 1], ll == LOCAL_N + 1, str(ll))
	var me_rank := int((inst.get("me_row") as Dictionary).get("rank", 0))
	_ok("⑤ ★分母: 我在本机榜上有名次, 而且在一屏开外", me_rank > LB.VIS_ROWS, str(me_rank))
	var sc: ScrollContainer = inst.get("_scroll")
	sc.scroll_vertical = int(float(ll - LB.VIS_ROWS) * LB.ROW_H)
	await get_tree().process_frame
	var bl := _built(inst)
	var last_r: Dictionary = _read_row(bl[ll] as Control) if bl.has(ll) else {}
	_ok("⑤ ★★滚到底: 最后一行名次 = %d 且有名字" % ll, str(last_r.get("rank", "")) == str(ll)
		and str(last_r.get("name", "")) != "" and str(last_r.get("name", "")) != "—", str(last_r))
	sc.scroll_vertical = 0
	await get_tree().process_frame
	(inst.get("jump_btn") as Button).pressed.emit()
	for _i in range(3):
		await get_tree().process_frame
	var bm := _built(inst)
	var mr: Dictionary = _read_row(bm[me_rank] as Control) if bm.has(me_rank) else {}
	_ok("⑤ ★★「我的位置」: 我那一行整行在滚动区里且带「你」签", bm.has(me_rank)
		and _fully_visible(inst, bm[me_rank] as Control) and bool(mr.get("you", false)), str(mr))
	GameState.season_wins = w0
	GameState.hearts = h0
	BE.pool_override = {}
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ⑦ 两个比例
# ─────────────────────────────────────────────────────────────
func _t_ratios() -> void:
	_backend_on(true)
	_me_on_board = true
	for sz in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		print("── ⑦ 视口 %dx%d ──" % [sz.x, sz.y])
		get_tree().root.size = sz
		await get_tree().process_frame
		var inst := await _open()
		var vp := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size)).grow(0.5)
		var panel = inst.get("_panel")
		var sc = inst.get("_scroll")
		var pin = inst.get("_pin")
		var jb = inst.get("jump_btn")
		_ok("⑦[%dx%d] ★分母: 视口真的是这个尺寸" % [sz.x, sz.y], absf(vp.size.x - float(sz.x) - 1.0) < 1.5,
			str(vp.size))
		_ok("⑦[%dx%d] 面板 / 列表 / 钉住那一行 / 「我的位置」都在视口内" % [sz.x, sz.y],
			panel is Control and vp.encloses((panel as Control).get_global_rect())
			and sc is Control and vp.encloses((sc as Control).get_global_rect())
			and pin is Control and vp.encloses((pin as Control).get_global_rect())
			and jb is Button and vp.encloses((jb as Button).get_global_rect()),
			"面板 %s / 「我的位置」 %s" % [str((panel as Control).get_global_rect()) if panel is Control else "?",
				str((jb as Button).get_global_rect()) if jb is Button else "?"])
		_ok("⑦[%dx%d] 列表与钉住那一行不重叠" % [sz.x, sz.y], sc is Control and pin is Control
			and not (sc as Control).get_global_rect().intersects((pin as Control).get_global_rect()))
		await _close(inst)
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
