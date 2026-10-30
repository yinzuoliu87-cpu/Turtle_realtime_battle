extends Node
## verify_leaderboard_spar.gd —— 排行榜上点玩家可以切磋(2026-10-30 · 方案书 docs/plans/20261030-排行榜切磋.md §6)。
##
## 用户 10-30「排行榜里面需要做一个这个切磋功能，也就是点击这个这个玩家之后，除了加好友选项，那还应该有这个切磋选项。」
## 注入传输层(`SB._transport_for_test`)= 一个记账的假服务端(friend_lineup 只认好友 / ghosts 按行回)。
##   L 排行榜行: 服务端行的入口带这张榜的周号 + 账号 ⇒ 点开的菜单里真有「切磋」
##   P 菜单: 给了周号 + 账号 ⇒ 有「切磋」; 不给周号(对阵图 / 赛况板 / 对局顶栏)或没账号 ⇒ 没有; 五颗键都在盒里、互不重叠
##   N 纯判据: pick_board_row 去闯关行 / 机器人 / seed_ 取第一行; board_query 账号不像 uuid / 没周号 ⇒ 不查
##   F 取阵容: 好友 ⇒ friend_lineup、不读 ghosts; 非好友 ⇒ 读 ghosts(这个人 + 这一周); 规则版本不同 / 没快照 ⇒ 不能打
##   S 按键: 我这边不能打 ⇒ 不发请求、说原因; 成 ⇒ 用取回的快照开局、回排行榜; 取不到 ⇒ 说原因、键恢复可点
##   B 结算屏回哪: 排行榜发起 ⇒「返回排行榜」; 好友页发起 ⇒「返回好友」; battle_hud 按 Spar 走、不写死好友页

const SB := preload("res://scripts/net/supabase.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const PM := preload("res://scripts/scenes/social/player_menu.gd")
const BE := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RPT := preload("res://scripts/net/report_net.gd")

const ME := "11111111-1111-4111-8111-111111111111"
const OTHER := "22222222-2222-4222-8222-222222222222"
## 周号 = 那一周开始的 unix 秒(排行榜 board_week_ts 与 ghosts.season_week 同一口径; 正式服 10-30 只读查到 1792972800)。
const WEEK := 1792972800

var _fail := 0
var _n := 0
var _key0 = ""
var _reqs: Array = []          # {fn, url}
var _lineup: Dictionary = {}
var _ghost_rows: Array = []
var _started: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _wait(frames: int = 8) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _snap(leaders: Array, extra: Dictionary = {}) -> Dictionary:
	var s := {"schema_ver": BE.SCHEMA_VER, "leaders": leaders,
		"lane_assign": {"top": [leaders[0]], "bottom": leaders.slice(1)},
		"profile": {"name": "路人甲", "avatar": leaders[0], "id": "g_x", "tag": P2C.player_tag(OTHER)}}
	s.merge(extra, true)
	return s


func _spy(_method, url, _headers, _body, cb) -> void:
	var fn := str(url).get_file()
	_reqs.append({"fn": fn.split("?")[0], "url": str(url)})
	if fn.begins_with("ghosts"):
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_ghost_rows)})
		return
	if fn == "friend_lineup":
		cb.call({"ok": true, "code": 200, "body": JSON.stringify(_lineup)})
		return
	cb.call({"ok": false, "code": 404, "body": ""})


func _count(fn: String) -> int:
	return _reqs.filter(func(r) -> bool: return str(r["fn"]) == fn).size()


func _backend_on(on: bool) -> void:
	if on:
		OS.set_environment(SB.ENV_URL, "http://gate.local")
		ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
		SB._token = "gate-token"
		SB._expires_at = 0
		SB._transport_for_test = _spy
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
		SB._transport_for_test = Callable()
		SB._token = ""


func _info(extra: Dictionary = {}) -> Dictionary:
	var d := {"name": "路人甲", "tag": P2C.player_tag(OTHER), "ctx": RPT.CTX_LEADERBOARD,
		"account": OTHER, "spar_week": WEEK, "lead": "lava"}
	d.merge(extra, true)
	return d


func _close_menu() -> void:
	var lay := get_node_or_null(PM.LAYER)
	if lay != null:
		lay.free()


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	GameState.test_mode = true
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var acc0 := str(GameState.account_id)
	GameState.account_id = ME
	GameState.tutorial_active = false
	GameState.season_leaders = ["ninja", "stone", "basic"]
	print("=== 排行榜上切磋 ===")
	await _t_leaderboard()
	_t_menu()
	_t_pure()
	_backend_on(true)
	await _t_fetch()
	await _t_press()
	_t_back()
	_backend_on(false)
	PM.spar_start = Spar.start
	GameState.account_id = acc0
	print("")
	print("分母: %d 条断言" % _n)
	print("ALL PASS — 排行榜上切磋 (%d/%d)" % [_n, _n] if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ── L ──
func _t_leaderboard() -> void:
	print("  ── L 排行榜行 ──")
	var lb = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(lb)
	await _wait(6)
	var wk := int(lb.board_week_ts)
	_ok("L 分母: 排行榜有周号", wk > 0, str(wk))
	lb._render([
		{"rank": 1, "name": "我自己", "tag": PM.my_tag(), "wins": 3, "hearts": 8, "sweeps": 0, "battles": 3, "is_self": true},
		{"rank": 2, "name": "路人甲", "tag": P2C.player_tag(OTHER), "wins": 2, "hearts": 8, "sweeps": 0, "battles": 3,
			"account_id": OTHER, "lead": "lava"},
	], lb.SRC_SERVER, 2)
	await _wait(1)
	var es: Array = lb.find_children(PM.ENTRY, "Button", true, false)
	_ok("L 分母: 别人那行有入口", es.size() == 1, str(es.size()))
	if es.size() == 1:
		(es[0] as Button).pressed.emit()
		await _wait(1)
		var lay := get_node_or_null(PM.LAYER)
		var sp := lay.find_child(PM.BTN_SPAR, true, false) as Button if lay != null else null
		_ok("L ★排行榜点别人 ⇒ 菜单里有「切磋」", sp != null)
		_ok("L 「加好友」仍在", lay != null and lay.find_child(PM.BTN_FRIEND, true, false) != null)
		## 真按下去: 非好友 ⇒ 读的是这个人、这张榜那一周的快照(周号是排行榜自己的 board_week_ts, 不是测试编的)
		if sp != null:
			_started.clear()
			PM.spar_start = func(_t, snap: Dictionary, info: Dictionary) -> String:
				_started.append([snap, info])
				return ""
			_lineup = {"ok": false, "reason": "not_friends"}
			_ghost_rows = [{"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": int(P2C.RULES_VER), "battles": 7}]
			_backend_on(true)
			sp.pressed.emit()
			await _wait(20)
			_backend_on(false)
			var urls: Array = _reqs.filter(func(r) -> bool: return str(r["fn"]) == "ghosts").map(func(r) -> String: return str(r["url"]))
			_ok("L ★从排行榜按切磋 ⇒ 读这个人、这张榜那一周的快照", urls.size() == 1 and str(urls[0]).contains(OTHER)
				and str(urls[0]).contains("season_week=eq.%d" % wk), str(urls))
			_ok("L ★开局、回排行榜、头像是榜上那只", _started.size() == 1 and str((_started[0][1] as Dictionary).get("back", "")) == Spar.LEADERBOARD_SCENE
				and str((_started[0][1] as Dictionary).get("avatar", "")) == "lava", str(_started))
	_close_menu()
	lb.queue_free()
	await _wait(2)


# ── P ──
func _t_menu() -> void:
	print("  ── P 菜单 ──")
	var lay = PM.open(self, _info())
	_ok("P 分母: 菜单打开了", lay != null)
	if lay == null:
		return
	var names := [PM.BTN_SPAR, PM.BTN_FRIEND, PM.BTN_REPORT, PM.BTN_BLOCK, PM.BTN_CLOSE]
	var bs: Array = []
	for nm in names:
		var b := lay.find_child(nm, true, false) as Button
		if b != null:
			bs.append(b)
	_ok("P ★给了周号 + 账号 ⇒ 五颗键齐(切磋 / 加好友 / 举报 / 拉黑 / 关闭)", bs.size() == 5, str(bs.size()))
	_ok("P 切磋键写「切磋」", bs.size() == 5 and (bs[0] as Button).text == PM.L_SPAR)
	if bs.size() == 5:
		var box := (bs[0] as Control).get_parent() as Control
		var inside := true
		var overlap := ""
		for i in range(bs.size()):
			var r := Rect2((bs[i] as Control).position, (bs[i] as Control).size)
			if not Rect2(Vector2.ZERO, box.size).encloses(r):
				inside = false
			for j in range(i + 1, bs.size()):
				if r.intersects(Rect2((bs[j] as Control).position, (bs[j] as Control).size)):
					overlap += "%s×%s " % [names[i], names[j]]
		_ok("P ★五颗键都在盒子里", inside, "盒 %s" % str(box.size))
		_ok("P ★五颗键互不重叠", overlap == "", overlap)
	_close_menu()
	for case in [["对阵图 / 赛况板 / 对局顶栏(不给周号)", {"spar_week": 0, "ctx": RPT.CTX_BRACKET}], ["没有账号", {"account": ""}]]:
		lay = PM.open(self, _info(case[1]))
		_ok("P ★%s ⇒ 没有「切磋」, 原来四颗键照旧" % case[0], lay != null and lay.find_child(PM.BTN_SPAR, true, false) == null
			and lay.find_child(PM.BTN_CLOSE, true, false) != null)
		_close_menu()


# ── N ──
func _t_pure() -> void:
	print("  ── N 纯判据 ──")
	var rv := int(P2C.RULES_VER)
	var good := {"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": rv, "battles": 7}
	var rows := [
		{"snapshot": _snap(["ice", "stone", "basic"], {"gl_w": 2, "gl_l": 1}), "rules_ver": rv, "battles": 9},
		{"snapshot": _snap(["ice", "stone", "basic"], {"ghost_id": "seed_x"}), "rules_ver": rv, "battles": 8},
		{"snapshot": _snap(["ice", "stone", "basic"], {"is_bot": true}), "rules_ver": rv, "battles": 8},
		good,
		{"snapshot": _snap(["ninja", "stone", "basic"]), "rules_ver": rv, "battles": 5},
	]
	var pick := FN.pick_board_row(rows)
	_ok("N ★跳过闯关行 / seed_ / 机器人, 取第一行积分赛快照", (pick.get("snapshot", {}) as Dictionary).get("leaders", []) == ["lava", "stone", "basic"],
		str((pick.get("snapshot", {}) as Dictionary).get("leaders", [])))
	_ok("N 一行都挑不出 ⇒ {}", FN.pick_board_row([rows[0], rows[1]]).is_empty() and FN.pick_board_row(null).is_empty())
	var q := FN.board_query(OTHER, WEEK)
	_ok("N ★查询串: 这个人 + 这一周 + 场次倒序", q.contains("account_id=eq." + OTHER) and q.contains("season_week=eq.%d" % WEEK)
		and q.contains("order=battles.desc"), q)
	_ok("N 账号不像 uuid / 没周号 ⇒ 不查", FN.board_query("x&season_week=eq.1", WEEK) == "" and FN.board_query(OTHER, 0) == "")


# ── F ──
func _fetch(account: String, week: int) -> Dictionary:
	var box := [{}]
	FN.fetch_for_spar(account, week, func(r: Dictionary) -> void: box[0] = r)
	for _i in range(60):
		if not (box[0] as Dictionary).is_empty():
			break
		await get_tree().process_frame
	return box[0]


func _t_fetch() -> void:
	print("  ── F 取阵容 ──")
	var rv := int(P2C.RULES_VER)
	_lineup = {"ok": true, "source": "lineup", "name": "路人甲", "tag": P2C.player_tag(OTHER),
		"snapshot": _snap(["phoenix", "stone", "basic"]), "rules_ver": rv}
	_ghost_rows = [{"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": rv, "battles": 7}]
	var g0 := _count("ghosts")
	var r := await _fetch(OTHER, WEEK)
	_ok("F 分母: 回调到了", not r.is_empty())
	_ok("F ★好友 ⇒ 打他最新的背包阵容、不读 ghosts", bool(r.get("ok", false))
		and ((r.get("data", {}) as Dictionary).get("snapshot", {}) as Dictionary).get("leaders", []) == ["phoenix", "stone", "basic"]
		and _count("ghosts") == g0, str(r.get("reason", "")))
	_lineup = {"ok": false, "reason": "not_friends"}
	r = await _fetch(OTHER, WEEK)
	var last_url: String = str(_reqs[_reqs.size() - 1]["url"]) if not _reqs.is_empty() else ""
	_ok("F ★非好友 ⇒ 读 ghosts 里这个人这一周的那份", bool(r.get("ok", false))
		and str((r.get("data", {}) as Dictionary).get("source", "")) == "board"
		and ((r.get("data", {}) as Dictionary).get("snapshot", {}) as Dictionary).get("leaders", []) == ["lava", "stone", "basic"]
		and last_url.contains("/rest/v1/ghosts?") and last_url.contains(OTHER) and last_url.contains("season_week=eq.%d" % WEEK),
		"%s · %s" % [str(r.get("reason", "")), last_url])
	_ghost_rows = [{"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": rv - 1, "battles": 7}]
	r = await _fetch(OTHER, WEEK)
	_ok("F ★对方规则版本旧 ⇒ 不能打, 说是对方旧", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "rules_old_theirs", str(r))
	_ghost_rows = []
	r = await _fetch(OTHER, WEEK)
	_ok("F 这一周没有快照 ⇒ 对方尚未配置阵容", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "no_lineup", str(r))


# ── S ──
func _t_press() -> void:
	print("  ── S 按键 ──")
	_started.clear()
	PM.spar_start = func(_t, snap: Dictionary, info: Dictionary) -> String:
		_started.append([snap, info])
		return ""
	var rv := int(P2C.RULES_VER)
	_lineup = {"ok": false, "reason": "not_friends"}
	_ghost_rows = [{"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": rv, "battles": 7}]

	GameState.season_leaders = []
	var lay = PM.open(self, _info())
	var sp := lay.find_child(PM.BTN_SPAR, true, false) as Button if lay != null else null
	var st := lay.find_child(PM.STATUS, true, false) as Label if lay != null else null
	_ok("S 分母: 切磋键 / 状态行在", sp != null and st != null)
	if sp == null or st == null:
		_close_menu()
		return
	var n0 := _reqs.size()
	sp.pressed.emit()
	await _wait()
	_ok("S ★我这边统领没选满 ⇒ 不发请求、状态行说原因", _reqs.size() == n0 and _started.is_empty() and st.text == Spar.my_side_check()
		and st.text != "", st.text)
	GameState.season_leaders = ["ninja", "stone", "basic"]

	_ghost_rows = []
	sp.pressed.emit()
	await _wait(20)
	_ok("S ★取不到 ⇒ 不开局、说原因、键恢复可点", _started.is_empty() and st.text == FN.msg("no_lineup") and not sp.disabled, st.text)

	_ghost_rows = [{"snapshot": _snap(["lava", "stone", "basic"]), "rules_ver": rv, "battles": 7}]
	sp.pressed.emit()
	await _wait(20)
	var ok := _started.size() == 1
	_ok("S ★取到 ⇒ 用那份快照开局", ok and (_started[0][0] as Dictionary).get("leaders", []) == ["lava", "stone", "basic"], str(_started.size()))
	if ok:
		var info: Dictionary = _started[0][1]
		_ok("S ★开局信息: 对方账号 / 昵称 / 头像 + 回排行榜", str(info.get("account", "")) == OTHER and str(info.get("name", "")) == "路人甲"
			and str(info.get("avatar", "")) == "lava" and str(info.get("back", "")) == Spar.LEADERBOARD_SCENE, str(info))
	_close_menu()


# ── B ──
func _t_back() -> void:
	print("  ── B 结算屏回哪 ──")
	## 走真的 Spar.begin(备份 / 只读开关 / 记下对方)再 end 还原 —— back 要真被它记住。
	var began := Spar.begin(_snap(["lava", "stone", "basic"]), {"account": OTHER, "name": "路人甲", "back": Spar.LEADERBOARD_SCENE})
	_ok("B 分母: Spar.begin 开起来了", began)
	_ok("B ★排行榜发起 ⇒「返回排行榜」、回排行榜", Spar.back_label() == "返回排行榜" and Spar.back_scene() == Spar.LEADERBOARD_SCENE,
		"%s · %s" % [Spar.back_label(), Spar.back_scene()])
	Spar.end()
	began = Spar.begin(_snap(["lava", "stone", "basic"]), {"account": OTHER, "name": "好友甲"})
	_ok("B ★好友页发起(不带 back)⇒「返回好友」、回好友页", began and Spar.back_label() == "返回好友" and Spar.back_scene() == Spar.FRIENDS_SCENE)
	Spar.end()
	_ok("B 分母: end 之后切磋已结束", not Spar.is_active())
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("B ★结算屏按 Spar 决定回哪, 不再写死好友页", src.contains("Spar.back_label()") and src.contains("Spar.back_scene()")
		and not src.contains("Spar.FRIENDS_SCENE"))
