extends Node
## verify_weekend_visible_monday.gd — 周末赛况留到周一 + 赛况板列表与战绩一致 + 对阵图能看所有组
##
## 用户 2026-10-19(首轮内测刚结束):
##   「此外我希望周六，周日的对战情况能也一直保留到周一」「现在玩家都看不到周六，周日的赛况」
##   「周六的时候，你随便看一个人的对局，怎么就和4-1不符，这到底怎么设计？」
##   「周日查看不了其他小组？」
##
## ★时钟用产品自己的缝 `Phase2Config.now_override_ts`(全屏「现在」都从 `now_utc()` 取), 网络用
##   `SupabaseNet._transport_for_test`(假的是服务器, 不连任何外部服务)。时刻都是**已知日期**, 不挂在「今天星期几」上。
##
## 段落:
##   ① 纯判据: 周一 ⇒ 上周; 周日 / 周二 ⇒ 本周; 服务端留存(server_keeps / VISIBLE_SEC)覆盖到周一结束
##   ② 赛况板真屏(周一): 问的是上周、顶上说「上周闯关赛」、不发直播请求; 周二问本周
##   ③ 对阵图真屏(周一): 名册 / 各组 / 头像 / 回放 都问上周; 默认冠军杯赛; 不开打、不记进度; 周二问本周
##   ④ 主菜单(周一): 休赛日那张卡上两扇门(周六赛况 / 周日对阵图), 接了处理函数, 点了真进对阵图; 周二没有
##   ⑤ 赛况板「点人」: 列表行数 == 战绩场次(只列他自己打的 + 缺录像的占位行)
##   ⑥ 对阵图: 选手也能翻到别的组(只能看、可点已揭晓的看回放), 翻得回自己那组; 1 人组也翻得回来

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const BOARD := preload("res://scripts/systems/replay/gauntlet_board.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")
const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const BOARD_SCENE := "res://scenes/GauntletBoard.tscn"
const MAP_SCENE := "res://scenes/BracketMap.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const TOKEN := "tok-monday"

## 首轮内测那一周(生产实测: 上周 1791763200 有闯关 206 行 / 决赛 26 行 / 7 个组, 新周 1792368000 一行都没有)。
const W0 := 1791763200                 # 2026-10-12 周一 00:00 UTC(比赛那一周)
const W1 := 1792368000                 # 2026-10-19 周一 00:00 UTC(新一周)
const MON := W1 + 10 * 3600            # 2026-10-19 周一 10:00 UTC
const TUE := W1 + 86400 + 10 * 3600    # 2026-10-20 周二 10:00 UTC
const SUN := W0 + 6 * 86400 + 21 * 3600

var _fail := 0
var _n := 0
var _gs
var _reqs: Array = []
var _sections := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


# ─────────────────────────────── 假服务器 ───────────────────────────────
func _ents(names: Array, acc0: String = "") -> Array:
	var out: Array = []
	for i in range(names.size()):
		out.append({"seed": i, "name": str(names[i]), "account_id": acc0 if (i == 0 and acc0 != "") else "acct-%s" % str(names[i])})
	return out


func _bucket_json(bk: int, names: Array, me_acc: String) -> Dictionary:
	return {"bucket": bk, "n": names.size(), "round": 2, "closed": true,
		"round_at": W0 + 6 * 86400 + 19 * 3600, "revealed_at": W0 + 6 * 86400 + 19 * 3600,
		"done": {"1-0": 0, "1-1": 1, "2-0": 0}, "scores": {}, "entrants": _ents(names, me_acc)}


func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	var meth := str(m)
	_reqs.append({"m": meth, "u": url, "b": str(b)})
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": TOKEN, "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rpc/finals_view") >= 0:
		var d := _bucket_json(0, ["我龟", "乙", "丙", "丁"], ME)
		d["ok"] = true
		d["now"] = MON
		d["next_at"] = int(d["round_at"]) + 480
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(d)})
		return
	if url.find("/rpc/finals_week_view") >= 0:
		var cup := _bucket_json(int(P2C.FINALS_CUP_BUCKET), ["我龟", "戊", "己", "庚"], ME)
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": W0, "now": MON,
			"buckets": [_bucket_json(0, ["我龟", "乙", "丙", "丁"], ME), _bucket_json(1, ["戊", "己", "庚", "辛"], "")],
			"cup": cup})})
		return
	if url.find("/rpc/finals_replay") >= 0:
		cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"no_replay\"}"})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _bodies(frag: String) -> Array:
	var out: Array = []
	for r in _reqs:
		if str(r["u"]).find(frag) >= 0:
			var j = JSON.parse_string(str(r["b"]))
			out.append(j if j is Dictionary else {})
	return out


func _urls(frag: String) -> Array:
	return _reqs.filter(func(r): return str(r["u"]).find(frag) >= 0).map(func(r): return str(r["u"]))


# ─────────────────────────────── 主流程 ───────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.account_id = ME
	_gs.week_anchor_ts = W1
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = TOKEN
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_ok("★分母: 后端真的打开了(假服务器)", SB.enabled())

	_t_pure()
	await _t_board()
	await _t_bracket()
	await _t_menu()
	await _t_board_consistency()
	await _t_other_groups()

	P2C.now_override_ts = 0
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	SB.finals_clear()
	SB.finals_week_clear()
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	_finish()


# ① ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── ① 纯判据 ──")
	_ok("① 分母: 时刻钉对了(周一 / 周二 / 周日)", P2C.phase_at_utc(MON) == P2C.PHASE_REST
		and P2C.phase_at_utc(TUE) == P2C.PHASE_RANKED and P2C.phase_at_utc(SUN) == P2C.PHASE_FINALS
		and P2C.week_anchor_utc(MON) == W1 and P2C.week_anchor_utc(SUN) == W0)
	_ok("① ★★周一 ⇒ 看上周(刚结束的那个周末)", P2C.weekend_view_week(MON) == W0, str(P2C.weekend_view_week(MON)))
	_ok("① ★周一 00:00:00 那一秒就已经是上周", P2C.weekend_view_week(W1) == W0)
	_ok("① ★周一 23:59:59 仍是上周", P2C.weekend_view_week(W1 + 86399) == W0)
	_ok("① ★★周二 00:00 ⇒ 切到新一周", P2C.weekend_view_week(W1 + 86400) == W1)
	_ok("① 周日 ⇒ 本周(不变)", P2C.weekend_view_week(SUN) == W0)
	_ok("① 周一 = 看过去; 周日 / 周二不是", P2C.weekend_view_is_past(MON) and not P2C.weekend_view_is_past(SUN)
		and not P2C.weekend_view_is_past(TUE))
	## 服务端留存: 周二 00:00 UTC 才清(cron '0 0 * * 2'); 客户端两处判据与之一致 ⇒ 周一整天按钮都在。
	var sun_game := W0 + 6 * 86400 + 18 * 3600
	_ok("① ★服务端还留着: 周一看周日那一场 ⇒ 留着", RF.server_keeps(sun_game, MON))
	_ok("① 周一最后一秒仍留着 / 周二 00:00 起已清", RF.server_keeps(sun_game, W1 + 86399)
		and not RF.server_keeps(sun_game, W1 + 86400))
	_ok("① 上传队列可见期截止 = 下周二 00:00(周一整天还能补传)", W0 + RU.VISIBLE_SEC == W1 + 86400,
		"%d vs %d" % [W0 + RU.VISIBLE_SEC, W1 + 86400])
	_sections += 1


# ② ─────────────────────────────────────────────────────────────
func _open_scene(path: String) -> Node:
	var sc: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child(sc)
	get_tree().current_scene = sc
	await _frames(6)
	return sc


func _labels_text(n: Node) -> String:
	var out := PackedStringArray()
	for c in n.find_children("*", "Label", true, false):
		out.append(str((c as Label).text))
	for c in n.find_children("*", "Button", true, false):
		out.append(str((c as Button).text))
	return " | ".join(out)


func _board_row(id: int, t: String, lp: Dictionary, rp: Dictionary, won: bool, gw: int, gl: int, rw = null, rl = null) -> Dictionary:
	return {"match_id": _uid(id), "created_at": t, "lp": lp, "rp": rp, "rw": rw, "rl": rl,
		"result": {"won": won, "steps": 100, "surrendered": false, "gw": gw, "gl": gl}}


func _uid(n: int) -> String:
	return "%08x-0000-4000-8000-%012x" % [n, n]


func _prof(nm: String, acc: String) -> Dictionary:
	return {"name": nm, "tag": P2C.player_tag(acc), "avatar": "basic", "id": "g_x"}


func _t_board() -> void:
	print("── ② 赛况板(周一 / 周二) ──")
	for spec in [[MON, W0, "周一"], [TUE, W1, "周二"]]:
		P2C.now_override_ts = int(spec[0])
		_reqs.clear()
		var bs: Node = await _open_scene(BOARD_SCENE)
		var q: Array = _urls("/rest/v1/matches?phase=eq.gauntlet")
		_ok("② 分母(%s): 真去问了赛况" % spec[2], q.size() >= 1, str(_reqs.size()))
		_ok("② ★★%s: 问的是 season_week=%d" % [spec[2], int(spec[1])],
			q.size() >= 1 and str(q[0]).find("season_week=eq.%d" % int(spec[1])) >= 0
			and int(bs.get("view_week")) == int(spec[1]), str(q))
		if int(spec[0]) == MON:
			_ok("② 周一: 不问「正在打」(周末已经结束)", _urls("live_matches").is_empty(), str(_urls("live_matches")))
			## 喂一行上周的数据 ⇒ 顶上那一行说「上周闯关赛」, 不说「周日几点开打」
			bs.set_rows([_board_row(1, "2026-10-17T10:00:00+00:00", _prof("甲龟", "acct:a"), _prof("乙龟", "acct:b"), true, 1, 0, 0, 0)])
			var st := str((bs.get("_status") as Label).text)
			_ok("② ★周一顶上那一行: 「上周闯关赛 … 已结束」, 不报下周日开打", st.begins_with("上周闯关赛")
				and st.find("已结束") >= 0 and st.find("开打") < 0, st)
			_ok("② 周一: 收盘后还没打满的算出局(上周早就截止了)", str((bs.data["players"] as Array)[0]["state_text"]) == "已出局",
				str(bs.data["players"]))
		bs.queue_free()
		await _frames(3)
	_sections += 1


# ③ ─────────────────────────────────────────────────────────────
func _btn_at(m, r: int, mm: int) -> Button:
	for b in m._canvas.find_children("*", "Button", true, false):
		if (b as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return b
	return null


func _tap_node(m, b: Button) -> void:
	b.pressed.emit()
	await _frames(2)
	var go: Button = m.find_child("PopupGoBtn", true, false) as Button
	if go != null:
		go.pressed.emit()
	await _frames(4)


func _t_bracket() -> void:
	print("── ③ 对阵图(周一 / 周二) ──")
	P2C.now_override_ts = MON
	SB.finals_clear()
	SB.finals_week_clear()
	_reqs.clear()
	_gs.finals_champion = false
	_gs.finals_deepest_round = 0
	var champ0: bool = bool(_gs.finals_champion)
	var deep0: int = int(_gs.finals_deepest_round)
	var titles0 := str(_gs.titles)
	var m: Node = await _open_scene(MAP_SCENE)
	var w := 0
	while w < 120 and not (SB.finals_tried() and SB.finals_week_tried()):
		await get_tree().process_frame
		w += 1
	m._on_poll()
	await _frames(3)
	var fv: Array = _bodies("/rpc/finals_view")
	var fw: Array = _bodies("/rpc/finals_week_view")
	var gb: Array = _urls("/rest/v1/matches?phase=eq.gauntlet")
	_ok("③ 分母: 名册 / 各组 / 头像 三个请求都发了", fv.size() >= 1 and fw.size() >= 1 and gb.size() >= 1,
		"%d/%d/%d" % [fv.size(), fw.size(), gb.size()])
	_ok("③ ★★周一: 名册(finals_view)问的是上周", fv.size() >= 1 and int((fv[0] as Dictionary).get("p_week", 0)) == W0, str(fv))
	_ok("③ ★★周一: 各组 + 冠军杯赛(finals_week_view)问的是上周", fw.size() >= 1 and int((fw[0] as Dictionary).get("p_week", 0)) == W0, str(fw))
	_ok("③ 周一: 头像(赛况板)问的是上周", gb.size() >= 1 and str(gb[0]).find("season_week=eq.%d" % W0) >= 0, str(gb))
	_ok("③ 周一: 顶栏写「上周日 · 决赛日」", _labels_text(m).find(MAP.TITLE_PAST) >= 0)
	_ok("③ 分母: 我那一组拿到了(4 人, 我是 0 号)", int((m._bucket as Dictionary).get("size", 0)) == 4
		and int((m._bucket as Dictionary).get("me", -1)) == 0, str(m._bucket.get("size", 0)))
	_ok("③ ★周一默认看冠军杯赛(整个周日都打完了)", str(m._view) == L.VIEW_FINALS and int(m.cur().get("size", 0)) == 4,
		"%s size=%d" % [str(m._view), int(m.cur().get("size", 0))])
	_ok("③ ★★周一只看不记: 决赛进度 / 头衔一个字都没动(否则新一周平白多一个冠军)",
		bool(_gs.finals_champion) == champ0 and int(_gs.finals_deepest_round) == deep0 and str(_gs.titles) == titles0,
		"champ %s→%s deep %d→%d" % [champ0, _gs.finals_champion, deep0, _gs.finals_deepest_round])
	m.pick_view(L.VIEW_BUCKET)
	await _frames(2)
	var any_fetch := false
	for r in range(1, 3):
		for mm in range(2 if r == 1 else 1):
			if m.should_fetch_opponent(r, mm):
				any_fetch = true
	_ok("③ 周一一场都不开打(不问对手)", not any_fetch)
	var b10 := _btn_at(m, 1, 0)
	_ok("③ 分母: 已揭晓的 1-0 能点", b10 != null and m.can_open(1, 0))
	if b10 != null:
		await _tap_node(m, b10)
		await _frames(10)
		var fr: Array = _bodies("/rpc/finals_replay")
		_ok("③ ★★周一点格看回放: 问的是上周那一场 (W0, 组 0, 1, 0)", fr.size() >= 1
			and int((fr[0] as Dictionary).get("p_week", 0)) == W0 and int((fr[0] as Dictionary).get("p_bucket", -1)) == 0
			and int((fr[0] as Dictionary).get("p_round", 0)) == 1 and int((fr[0] as Dictionary).get("p_match", -1)) == 0, str(fr))
	m.queue_free()
	await _frames(3)
	## 周二: 回到本周
	P2C.now_override_ts = TUE
	SB.finals_clear()
	SB.finals_week_clear()
	_reqs.clear()
	var m2: Node = await _open_scene(MAP_SCENE)
	await _frames(4)
	var fv2: Array = _bodies("/rpc/finals_view")
	_ok("③ ★周二: 名册问的是本周(新一周)", fv2.size() >= 1 and int((fv2[0] as Dictionary).get("p_week", 0)) == W1, str(fv2))
	_ok("③ 周二: 顶栏照旧「周日 · 决赛日」", _labels_text(m2).find(MAP.TITLE_NOW) >= 0 and _labels_text(m2).find(MAP.TITLE_PAST) < 0)
	m2.queue_free()
	await _frames(3)
	SB.finals_clear()
	SB.finals_week_clear()
	_sections += 1


# ④ ─────────────────────────────────────────────────────────────
func _t_menu() -> void:
	print("── ④ 主菜单(周一) ──")
	P2C.now_override_ts = MON
	var mm: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	await _frames(3)
	var info: Dictionary = mm.week_card_info(P2C.PHASE_REST, MON)
	_ok("④ 分母: 休赛日那张卡是「今天」", str(info["state"]) == "now", str(info["state"]))
	var blk: Node = mm._week_card(info)
	var d1: Button = blk.find_child("GauntletBoardDoor", true, false) as Button
	var d2: Button = blk.find_child("BracketDoor", true, false) as Button
	_ok("④ ★★周一: 今天那张卡上有两扇门(周六赛况 / 周日对阵图)", d1 != null and d2 != null, _labels_text(blk))
	if d1 != null and d2 != null:
		_ok("④ 门上的字说清是哪一天", str(d1.text) == mm.PAST_BOARD_LINE and str(d2.text) == mm.PAST_BRACKET_LINE,
			"%s / %s" % [d1.text, d2.text])
		var m1 := ""
		for c in d1.pressed.get_connections():
			m1 = (c["callable"] as Callable).get_method()
		var m2 := ""
		for c in d2.pressed.get_connections():
			m2 = (c["callable"] as Callable).get_method()
		_ok("④ ★门接了原来那两处(赛况板 / 对阵图)", m1 == "_open_gauntlet_board" and m2 == "_open_bracket_map", "%s / %s" % [m1, m2])
		var r1 := Rect2(d1.position, d1.custom_minimum_size)
		var r2 := Rect2(d2.position, d2.custom_minimum_size)
		_ok("④ 两扇门不重叠、都在卡里", not r1.intersects(r2) and r1.position.x >= 0.0 and r2.position.x >= 0.0
			and r1.end.x <= mm.WEEK_CARD_SIZE.x and r2.end.x <= mm.WEEK_CARD_SIZE.x, "%s / %s" % [r1, r2])
		_ok("④ 卡上照旧说「不开放对战」", _labels_text(blk).find("不开放对战") >= 0)
	## 周二: 休赛日那张已过去, 没有门; 周六那张(新一周)也还没到, 没有门
	var tb: Node = mm._week_card(mm.week_card_info(P2C.PHASE_REST, TUE))
	var tg: Node = mm._week_card(mm.week_card_info(P2C.PHASE_GAUNTLET, TUE))
	_ok("④ ★周二: 没有上周的门了", tb.find_child("GauntletBoardDoor", true, false) == null
		and tb.find_child("BracketDoor", true, false) == null and tg.find_child("GauntletBoardDoor", true, false) == null)
	tb.free()
	tg.free()
	## 按下去 ⇒ 真进对阵图, 而且问的是上周
	if d2 != null:
		mm.add_child(blk)
		get_tree().current_scene = mm
		SB.finals_clear()
		SB.finals_week_clear()
		_reqs.clear()
		await _frames(2)
		d2.pressed.emit()
		var w := 0
		var cs = null
		while w < 300:
			cs = get_tree().current_scene
			if cs != null and is_instance_valid(cs) and cs.get_script() != null \
					and str((cs.get_script() as Script).resource_path).ends_with("BracketMapScene.gd"):
				break
			await get_tree().process_frame
			w += 1
		_ok("④ ★★点「周日对阵图」⇒ 真进了对阵图", cs != null and str((cs.get_script() as Script).resource_path).ends_with("BracketMapScene.gd"))
		await _frames(6)
		var fv: Array = _bodies("/rpc/finals_view")
		_ok("④ 进去问的就是上周", fv.size() >= 1 and int((fv[0] as Dictionary).get("p_week", 0)) == W0, str(fv))
		if cs != null and is_instance_valid(cs):
			cs.queue_free()
		await _frames(3)
	else:
		blk.free()
		mm.queue_free()
	SB.finals_clear()
	SB.finals_week_clear()
	_sections += 1


# ⑤ ─────────────────────────────────────────────────────────────
## 生产 2026-10-17 那周 rsq0417(4-1)的形状: 自己传了 5 场(gw/gl 逐场 1-0 → 4-1), 另有 7 场是别人挑战他的快照。
func _rsq_rows(drop_n: int = -1) -> Array:
	var me := _prof("rsq", "acct:rsq")
	var seq := [[true, 1, 0], [false, 1, 1], [true, 2, 1], [true, 3, 1], [true, 4, 1]]
	var rows: Array = []
	for i in range(seq.size()):
		var s: Array = seq[i]
		if int(s[1]) + int(s[2]) == drop_n:
			continue
		rows.append(_board_row(100 + i, "2026-10-17T00:%02d:00+00:00" % (10 + i), me, _prof("对手%d" % i, "acct:o%d" % i),
			bool(s[0]), int(s[1]), int(s[2]), int(s[1]) - (1 if s[0] else 0), int(s[2]) - (0 if s[0] else 1)))
	## 别人挑战他的快照(他不在场): 标签是他那一刻的战绩
	var tags := [[1, 0], [1, 1], [3, 1], [2, 1], [1, 0], [3, 1], [3, 1]]
	for k in range(tags.size()):
		rows.append(_board_row(200 + k, "2026-10-17T%02d:00:00+00:00" % (1 + k), _prof("挑战者%d" % k, "acct:c%d" % k), me,
			k % 2 == 0, 1, k % 2, tags[k][0], tags[k][1]))
	return rows


func _row_of(d: Dictionary, tag: String) -> Dictionary:
	for p in d.get("players", []):
		if str(p["tag"]) == tag:
			return p
	return {}


func _t_board_consistency() -> void:
	print("── ⑤ 赛况板: 列表与战绩一致 ──")
	var tag := P2C.player_tag("acct:rsq")
	var d: Dictionary = BOARD.build(_rsq_rows(), "", true)
	var p := _row_of(d, tag)
	_ok("⑤ 分母: rsq 上榜 4-1", int(p.get("w", -1)) == 4 and int(p.get("l", -1)) == 1, str(p))
	_ok("⑤ 分母: 旧口径(games_of)会列出 12 场 —— 就是用户看到的「和 4-1 不符」",
		BOARD.games_of(d["games"], tag).size() == 12, str(BOARD.games_of(d["games"], tag).size()))
	var pg: Array = BOARD.player_games(d["games"], p)
	_ok("⑤ ★★点他 ⇒ 列表 5 场 == 4-1", pg.size() == 5, str(pg.size()))
	var all_own := true
	for g in pg:
		if str(g["l"].get("tag", "")) != tag:
			all_own = false
	_ok("⑤ ★列的都是他自己打的(别人挑战他快照的那几场不算)", all_own)
	var wins := 0
	for g in pg:
		wins += 1 if bool(g["lw"]) else 0
	_ok("⑤ 列表里胜场 == 4", wins == 4, str(wins))
	_ok("⑤ 最近一场在最上(第 5 场)", int(pg[0].get("n", 0)) == 5 and int(pg[4].get("n", 0)) == 1)
	## 缺一场录像(第 4 场 3-1 那一局没传上来): 战绩仍是 4-1(第 5 场带着 4-1) ⇒ 列表 5 行, 第 4 场是「无录像」
	var d2: Dictionary = BOARD.build(_rsq_rows(4), "", true)
	var p2 := _row_of(d2, tag)
	var pg2: Array = BOARD.player_games(d2["games"], p2)
	var miss: Array = pg2.filter(func(g): return bool(g.get("missing", false)))
	_ok("⑤ ★★缺一场录像: 仍是 4-1、列表仍是 5 行(少的那场不消失)", int(p2["w"]) == 4 and int(p2["l"]) == 1 and pg2.size() == 5,
		"%d-%d / %d 行" % [int(p2["w"]), int(p2["l"]), pg2.size()])
	_ok("⑤ ★缺的那一行 = 第 4 场 · 胜(由 2-1 → 3-1 推出)", miss.size() == 1 and int(miss[0]["n"]) == 4 and str(miss[0]["res"]) == "w",
		str(miss))
	_ok("⑤ 缺的那一行没有可播的 id(不摆死按钮)", miss.size() == 1 and not BOARD.watchable(miss[0]))
	## 自己的录像只传到 2-1, 别人打他快照时标签已是 3-1 ⇒ 战绩 3-1, 列表 4 行(1 行无录像)
	var me := _prof("rsq", "acct:rsq")
	var short_rows: Array = []
	for r in _rsq_rows():
		var gw := int((r["result"] as Dictionary)["gw"])
		var gl := int((r["result"] as Dictionary)["gl"])
		if str(r["lp"]["tag"]) == tag and gw + gl > 3:
			continue
		if str(r["rp"]["tag"]) == tag and int(r["rw"]) + int(r["rl"]) > 4:
			continue
		short_rows.append(r)
	var d3: Dictionary = BOARD.build(short_rows, "", true)
	var p3 := _row_of(d3, tag)
	var pg3: Array = BOARD.player_games(d3["games"], p3)
	_ok("⑤ ★战绩来自快照标签(3-1)而录像只到 2-1 ⇒ 列表 4 行, 1 行无录像",
		int(p3["w"]) + int(p3["l"]) == pg3.size() and pg3.filter(func(g): return bool(g.get("missing", false))).size() == 1,
		"%d-%d / %d 行" % [int(p3["w"]), int(p3["l"]), pg3.size()])
	## 真屏: 点人 ⇒ 卡片数 == 战绩场次, 无录像那张写「无录像」且没有「观看」
	P2C.now_override_ts = MON
	var bs: Node = await _open_scene(BOARD_SCENE)
	bs.set_rows(_rsq_rows(4))
	await _frames(2)
	var pb: Button = null
	for b in bs.find_children("PlayerBtn", "Button", true, false):
		if str((b as Button).get_meta("key", "")) == tag:
			pb = b
	_ok("⑤ 分母: 屏上有 rsq 那一行", pb != null)
	if pb != null:
		pb.pressed.emit()
		await _frames(3)
		var gbox: Node = bs.get("_games_box")
		var cards := 0
		var misses: Array = []
		for c in gbox.get_children():
			var nm := str(c.name)
			if nm.begins_with(bs.N_CARD) or nm.begins_with(bs.N_MISSING_CARD):
				cards += 1
			if nm.begins_with(bs.N_MISSING_CARD):
				misses.append(c)
		_ok("⑤ ★★真屏: 点 rsq(4-1) ⇒ 右栏 5 张卡", cards == 5, str(cards))
		_ok("⑤ ★真屏: 无录像那张写着「第 4 场 · 胜」「无录像」、没有「观看」", misses.size() == 1
			and _labels_text(misses[0]).find("第 4 场 · 胜") >= 0 and _labels_text(misses[0]).find(bs.NO_REPLAY) >= 0
			and (misses[0] as Node).find_children("GameBtn", "Button", true, false).is_empty(),
			_labels_text(misses[0]) if not misses.is_empty() else "")
		_ok("⑤ 有录像的 4 张都有「观看」", gbox.find_children("GameBtn", "Button", true, false).size() == 4,
			str(gbox.find_children("GameBtn", "Button", true, false).size()))
	bs.queue_free()
	await _frames(3)
	_sections += 1


# ⑥ ─────────────────────────────────────────────────────────────
func _t_other_groups() -> void:
	print("── ⑥ 对阵图: 选手也能看别的组 ──")
	P2C.now_override_ts = SUN
	var now := SUN
	var mine: Dictionary = SB._bucket_from({"bucket": 0, "n": 4, "round": 2, "closed": false,
		"round_at": now - 600, "now": now, "done": {"1-0": 0, "1-1": 1}, "entrants": _ents(["我龟", "乙", "丙", "丁"], ME)}, ME, now)
	var wv: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": W0, "now": now, "buckets": [
		{"bucket": 0, "n": 4, "round": 2, "closed": false, "round_at": now - 600, "done": {"1-0": 0, "1-1": 1},
			"entrants": _ents(["我龟", "乙", "丙", "丁"], ME)},
		{"bucket": 1, "n": 4, "round": 2, "closed": false, "round_at": now - 600, "done": {"1-0": 1, "1-1": 0},
			"entrants": _ents(["戊", "己", "庚", "辛"])},
		{"bucket": 2, "n": 2, "round": 1, "closed": true, "round_at": now - 6000, "done": {"1-0": 0},
			"entrants": _ents(["壬", "癸"])}]}), ME, now)
	var m: Node = await _open_scene(MAP_SCENE)
	m.set_data(mine, {}, now)
	m.set_week(wv)
	m.pick_view(L.VIEW_BUCKET)
	await _frames(3)
	_ok("⑥ 分母: 我在第 1 组(4 人, 0 号)", int(m.cur().get("bucket", -1)) == 0 and int(m.cur().get("me", -1)) == 0)
	_ok("⑥ ★★选手也看得到换组那一行", bool(m._spec_bar.visible), str(m._spec_lb.text))
	_ok("⑥ 那一行说清现在看的是本组", str(m._spec_lb.text).find("本组") >= 0, str(m._spec_lb.text))
	m._spec_step(1)
	await _frames(2)
	_ok("⑥ ★★下一组 ⇒ 画的是第 2 组(别人那一组), 我不在里面", int(m.cur().get("bucket", -1)) == 1 and int(m.cur().get("me", 0)) == -1,
		"bucket=%d me=%d" % [int(m.cur().get("bucket", -1)), int(m.cur().get("me", 0))])
	_ok("⑥ 那一行说「观战 · 第 2 组」", str(m._spec_lb.text).find("观战") >= 0 and str(m._spec_lb.text).find("第 2 组") >= 0, str(m._spec_lb.text))
	var fetch := false
	for r in range(1, 3):
		for mm in range(2 if r == 1 else 1):
			fetch = fetch or m.should_fetch_opponent(r, mm)
	_ok("⑥ ★别的组只能看: 一场都不会替我去问对手 / 开打", not fetch)
	_ok("⑥ ★已揭晓的能点开看回放, 当前轮点不开", m.can_open(1, 0) and m.can_open(1, 1) and not m.can_open(2, 0))
	var b11 := _btn_at(m, 1, 1)
	_ok("⑥ 分母: 第 2 组 1-1 那一格有按钮", b11 != null)
	if b11 != null:
		_reqs.clear()
		await _tap_node(m, b11)
		await _frames(6)
		var fr: Array = _bodies("/rpc/finals_replay")
		_ok("⑥ ★★点别组已揭晓那一格 ⇒ 问的是那一组 (组 1, 1, 1)", fr.size() >= 1 and int((fr[0] as Dictionary).get("p_bucket", -1)) == 1
			and int((fr[0] as Dictionary).get("p_round", 0)) == 1 and int((fr[0] as Dictionary).get("p_match", -1)) == 1, str(fr))
	m._spec_step(1)
	await _frames(2)
	_ok("⑥ 再下一组: 2 人组(第 3 组)", int(m.cur().get("bucket", -1)) == 2, str(m.cur().get("bucket", -1)))
	m._spec_step(1)
	await _frames(2)
	_ok("⑥ ★★再翻一下回到我这一组(我又是 0 号)", int(m.cur().get("bucket", -1)) == 0 and int(m.cur().get("me", -1)) == 0
		and str(m._spec_lb.text).find("本组") >= 0, str(m._spec_lb.text))
	m.pick_view(L.VIEW_FINALS)
	await _frames(1)
	_ok("⑥ 冠军杯赛页上不出换组那一行", not m._spec_bar.visible)
	m.queue_free()
	await _frames(3)
	## 1 人组(不在可画名单里): 翻出去也翻得回来
	var solo: Dictionary = SB._bucket_from({"bucket": 3, "n": 1, "round": 1, "closed": true, "round_at": now - 600, "now": now,
		"done": {}, "entrants": _ents(["我龟"], ME)}, ME, now)
	var m2 = MAP.new()
	add_child(m2)
	await get_tree().process_frame
	m2.set_data(solo, {}, now)
	m2.set_week(wv)
	m2.pick_view(L.VIEW_BUCKET)
	await _frames(2)
	_ok("⑥ 分母: 1 人组 ⇒ 我这一组没有对局", str(m2._bucket_kind()) == MAP.EK_GROUP_SOLO, str(m2._bucket_kind()))
	_ok("⑥ 1 人组也看得到换组那一行", bool(m2._spec_bar.visible))
	var seen: Array = []
	for _i in range(4):
		m2._spec_step(1)
		await get_tree().process_frame
		seen.append(int(m2.cur().get("bucket", -1)) if bool(m2._peek) else -9)
	_ok("⑥ ★1 人组: 一圈 = 第 1 组 → 第 2 组 → 第 3 组 → 回到我", seen == [0, 1, 2, -9], str(seen))
	m2.queue_free()
	await _frames(2)
	_sections += 1


func _finish() -> void:
	_ok("★分母: 六段都走到了最后一条(没有被中途打断)", _sections == 6, str(_sections))
	print("")
	print("  (共 %d 条断言 · 用了 %d 帧)" % [_n, Engine.get_process_frames()])
	print("ALL PASS — 周末赛况留到周一" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
