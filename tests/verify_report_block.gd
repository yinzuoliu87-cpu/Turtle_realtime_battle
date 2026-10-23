extends Node
## verify_report_block.gd —— 昵称举报 / 拉黑(2026-10-20 · App Store 审核指南 1.2)
##
## A 黑名单本体: 只认合法玩家 ID; 落盘(丢掉内存重读还在); 被拉黑 ⇒ 默认昵称(确定性、与原名不同);
##   mask 递归换名并留原名; 移出 ⇒ 同一份数据换回原名; 名单可撤销
## B 玩家菜单: 自己 / 没有玩家 ID 不弹; 拉黑 ⇔ 移出 来回切, 每次回调宿主; 没配后端举报 ⇒ 失败不发请求;
##   配上(注入传输)⇒ POST rpc/report_nickname, 正文恰好 p_tag/p_name/p_context, 拉黑之后举报的仍是原名;
##   回 ok ⇒「已举报」且键不可再点; 回 duplicate ⇒「24 小时内已举报过」; 回 200 + true(不是对象)⇒ 失败
## C 排行榜: 别人的行有入口、自己的行没有; 走入口拉黑 ⇒ 原地重画, 那一行显示默认昵称; 移出 ⇒ 换回
## D 周六赛况板: 选中别人 ⇒ 右栏有入口; 选中自己 ⇒ 没有; 拉黑 ⇒ 战绩榜那一行显示默认昵称
## E 周日对阵图: 对局卡弹窗里对手一侧有入口、我这一侧没有; 拉黑 ⇒ 格子里显示默认昵称
## F 对局顶栏: 对手头像上有入口; 拉黑 ⇒ 顶栏对手名显示默认昵称
## G 设置 → 黑名单: 列出被拉黑的人, 点「移出」⇒ 名单变空, 写着「黑名单为空」
## H 主菜单: 昵称被管理员重置过 ⇒ 清掉自己起的名(显示回默认昵称); 别的名字被重置 ⇒ 不动; 没起过名 ⇒ 不发请求

const SB := preload("res://scripts/net/supabase.gd")
const BL := preload("res://scripts/util/blocklist.gd")
const PM := preload("res://scripts/scenes/social/player_menu.gd")
const RPT := preload("res://scripts/net/report_net.gd")
const BLP := preload("res://scripts/scenes/settings/blocklist_panel.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN_AM := 1789862400 + 10 * 3600
const T_OTHER := "#XHVRJV"
const T_THIRD := "#VK7GGP"
const NEED := 59   # 分母: 断言条数一条不能少(少了 = 半路中止)。2026-10-23 +1: C 段「入口真收得到点击」

var _n := 0
var _fail := 0
var _gs = null
var _got: Array = []
var _reply := [{"ok": true, "code": 200, "body": "{\"ok\": true}"}]


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 昵称举报 / 拉黑 ===")
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		_ok("分母: GameState", false)
		_finish()
		return
	_gs.test_mode = true
	_gs.account_id = "00000000-0000-0000-0000-000000000001"
	BL.clear_all()
	await _t_blocklist()
	await _t_menu()
	await _t_leaderboard()
	await _t_board()
	await _t_bracket()
	await _t_battle()
	await _t_settings()
	await _t_nick_reset()
	_finish()


# ── A ──────────────────────────────────────────────────────────────
func _t_blocklist() -> void:
	print("  ── A 黑名单本体 ──")
	_ok("A 分母: 我的玩家 ID 是合法的、不是 T_OTHER", P2.tag_valid(PM.my_tag()) and PM.my_tag() != T_OTHER, PM.my_tag())
	_ok("A 不合法的 ID 拉不进去", not BL.add("#AAAAAA", "x") and not BL.add("", "x") and BL.count() == 0)
	_ok("A ★拉黑 ⇒ is_blocked", BL.add(T_OTHER, "坏名字探针") and BL.is_blocked(T_OTHER))
	BL._reset_cache_for_test()
	_ok("A ★落盘: 丢掉内存重读还在", BL.is_blocked(T_OTHER) and BL.entries()[0]["name"] == "坏名字探针")
	var m1 := BL.masked_name(T_OTHER)
	_ok("A ★默认昵称: 与原名不同、合法、同一个 ID 每次一样、与没起名的默认名同一个生成器",
		m1 != "坏名字探针" and P2.nickname_valid(m1) and m1 == BL.masked_name(T_OTHER)
		and m1 == P2.nickname_fallback(BL.SEED_PREFIX + T_OTHER), m1)
	var data := {"players": [{"name": "坏名字探针", "tag": T_OTHER}, {"name": "好人", "tag": T_THIRD}],
		"games": [{"l": {"name": "坏名字探针", "tag": T_OTHER}, "r": {"name": "好人", "tag": T_THIRD}}]}
	BL.mask(data)
	_ok("A ★mask 递归换名(两层深的也换)、没拉黑的不动",
		data["players"][0]["name"] == m1 and data["games"][0]["l"]["name"] == m1
		and data["players"][1]["name"] == "好人" and data["games"][0]["r"]["name"] == "好人")
	_ok("A 换名后原名还在(举报要用)", BL.raw_name(data["players"][0]) == "坏名字探针" and BL.raw_name(data["players"][1]) == "好人")
	_ok("A ★移出 ⇒ 可撤销", BL.remove(T_OTHER) and not BL.is_blocked(T_OTHER) and BL.count() == 0)
	BL.mask(data)
	_ok("A ★移出后同一份数据换回原名", data["players"][0]["name"] == "坏名字探针" and data["games"][0]["l"]["name"] == "坏名字探针"
		and not (data["players"][0] as Dictionary).has(BL.RAW_KEY))


# ── B ──────────────────────────────────────────────────────────────
func _t_menu() -> void:
	print("  ── B 玩家菜单 ──")
	var cs := get_tree().current_scene
	_ok("B 自己不弹", PM.open(cs, {"name": "我", "tag": PM.my_tag()}) == null)
	_ok("B 没有玩家 ID 不弹", PM.open(cs, {"name": "待定", "tag": ""}) == null)
	var changed := [0]
	var lay = PM.open(cs, {"name": "坏名字探针", "tag": T_OTHER, "ctx": RPT.CTX_LEADERBOARD}, func() -> void: changed[0] += 1)
	_ok("B ★别人 ⇒ 菜单打开(举报 / 拉黑 / 关闭 都在)", lay != null and lay.find_child(PM.BTN_REPORT, true, false) is Button
		and lay.find_child(PM.BTN_BLOCK, true, false) is Button and lay.find_child(PM.BTN_CLOSE, true, false) is Button)
	if lay == null:
		return
	_ok("B 再开不叠第二个", PM.open(cs, {"name": "坏名字探针", "tag": T_OTHER}) == lay)
	var blk := lay.find_child(PM.BTN_BLOCK, true, false) as Button
	var rep := lay.find_child(PM.BTN_REPORT, true, false) as Button
	var st := lay.find_child(PM.STATUS, true, false) as Label
	var ttl := lay.find_child(PM.TITLE, true, false) as Label
	_ok("B 拉黑键写「拉黑」", blk.text == PM.L_BLOCK, blk.text)
	blk.pressed.emit()
	_ok("B ★点拉黑 ⇒ 进黑名单、键变「移出黑名单」、标题换默认昵称、回调宿主",
		BL.is_blocked(T_OTHER) and blk.text == PM.L_UNBLOCK and ttl.text == BL.masked_name(T_OTHER) and changed[0] == 1,
		"%s / %s / %d" % [blk.text, ttl.text, changed[0]])
	blk.pressed.emit()
	_ok("B ★再点 ⇒ 移出、换回原名、再回调", not BL.is_blocked(T_OTHER) and blk.text == PM.L_BLOCK and ttl.text == "坏名字探针"
		and changed[0] == 2 and st.text == PM.MSG_UNBLOCKED)
	blk.pressed.emit()   # 留着拉黑状态: 下面量「拉黑之后举报的仍是原名」

	## 没配后端
	var p0: int = RPT.report_posts
	_ok("B 分母: 门禁里后端没配", not SB.enabled())
	rep.pressed.emit()
	await _frames(3)
	_ok("B ★没配后端 ⇒ 不发请求、举报失败、键可再点", RPT.report_posts == p0 and st.text == PM.MSG[RPT.R_FAIL] and not rep.disabled, st.text)

	## 配上后端
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	_backend_on()
	rep.pressed.emit()
	await _frames(15)
	_ok("B ★发了 1 个请求", _got.size() == 1, str(_got.size()))
	if _got.size() >= 1:
		_ok("B POST 到 rpc/report_nickname", _got[0]["m"] == "POST" and str(_got[0]["u"]).ends_with("/rest/v1/rpc/report_nickname"), str(_got[0]["u"]))
		var j = JSON.parse_string(str(_got[0]["b"]))
		var ks: Array = (j as Dictionary).keys() if j is Dictionary else []
		ks.sort()
		_ok("B ★正文恰好 3 个参数", ks == ["p_context", "p_name", "p_tag"], str(ks))
		_ok("B ★举报的是玩家 ID + 原名(拉黑后屏幕上是默认名, 举报仍报原名) + 场景",
			j is Dictionary and j["p_tag"] == T_OTHER and j["p_name"] == "坏名字探针" and j["p_context"] == RPT.CTX_LEADERBOARD, str(j))
	_ok("B ★回 ok ⇒「已举报」、键不可再点", st.text == PM.MSG[RPT.R_OK] and rep.disabled, st.text)
	var res := [""]
	_reply[0] = {"ok": true, "code": 200, "body": "{\"ok\": false, \"reason\": \"duplicate\"}"}
	RPT.report(T_OTHER, "坏名字探针", RPT.CTX_BOARD, func(c: String) -> void: res[0] = c)
	await _frames(15)
	_ok("B 回 duplicate ⇒ 24 小时内已举报过", res[0] == RPT.R_DUP and PM.MSG[RPT.R_DUP].contains("24 小时"), res[0])
	_reply[0] = {"ok": true, "code": 200, "body": "true"}
	RPT.report(T_OTHER, "坏名字探针", RPT.CTX_BOARD, func(c: String) -> void: res[0] = c)
	await _frames(15)
	_ok("B 回 200 + 不是对象 ⇒ 失败(2xx ≠ 收下了)", res[0] == RPT.R_FAIL, res[0])
	_ok("B 纯判据: limit / self / 坏回包", RPT.report_result(true, 200, "{\"ok\":false,\"reason\":\"limit\"}") == RPT.R_LIMIT
		and RPT.report_result(true, 200, "{\"ok\":false,\"reason\":\"self\"}") == RPT.R_SELF
		and RPT.report_result(true, 500, "{\"ok\":true}") == RPT.R_FAIL)
	_backend_off(env0, key0)
	(lay.find_child(PM.BTN_CLOSE, true, false) as Button).pressed.emit()
	await _frames(2)
	_ok("B 关闭 ⇒ 菜单没了", cs.get_node_or_null(PM.LAYER) == null or cs.get_node(PM.LAYER).is_queued_for_deletion())
	await _frames(1)
	BL.remove(T_OTHER)


# ── C ──────────────────────────────────────────────────────────────
func _t_leaderboard() -> void:
	print("  ── C 排行榜 ──")
	var lb = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(lb)
	await _frames(6)
	var rows := [
		{"rank": 1, "name": "我自己探针", "tag": PM.my_tag(), "wins": 3, "hearts": 8, "sweeps": 0, "battles": 3, "is_self": true},
		{"rank": 2, "name": "坏名字探针", "tag": T_OTHER, "wins": 2, "hearts": 8, "sweeps": 0, "battles": 3, "account_id": "x"},
	]
	lb._render(rows, lb.SRC_SERVER, 2)
	await _frames(1)
	var es: Array = lb.find_children(PM.ENTRY, "Button", true, false)
	_ok("C ★别人的行有入口、自己的行没有(入口恰 1 个且是 T_OTHER)", es.size() == 1 and str((es[0] as Button).get_meta("tag", "")) == T_OTHER, str(es.size()))
	if es.is_empty():
		lb.queue_free()
		return
	## ★★2026-10-23 查实的老 bug: 列表行建好之后整行被 `_ignore_mouse` 一律改成 MOUSE_FILTER_IGNORE(为了不挡拖动),
	##   这颗入口也被一并改掉 ⇒ **真机上点名字什么都不会发生**; 而下面一条直接 `pressed.emit()` 绕过了鼠标层, 一直是绿的。
	##   ⇒ 量它**收不收得到点击**: 它自己不是 IGNORE(父节点 IGNORE 不挡孩子收点击, 只有它自己那一格算数)。
	var eb := es[0] as Button
	_ok("C ★★入口真收得到点击(mouse_filter 不是 IGNORE —— 原来被整行放行那一步改死了)",
		eb.mouse_filter != Control.MOUSE_FILTER_IGNORE and eb.is_visible_in_tree() and eb.size.x >= 200.0,
		"mouse_filter=%d 宽 %.0f" % [eb.mouse_filter, eb.size.x])
	(es[0] as Button).pressed.emit()
	await _frames(1)
	var lay = get_tree().current_scene.get_node_or_null(PM.LAYER)
	_ok("C 点入口 ⇒ 菜单打开(挂在当前场景上)", lay != null)
	if lay == null:
		lb.queue_free()
		return
	(lay.find_child(PM.BTN_BLOCK, true, false) as Button).pressed.emit()
	await _frames(1)
	_ok("C ★拉黑 ⇒ 原地重画, 那一行显示默认昵称、原名不在屏上",
		_has_text(lb, BL.masked_name(T_OTHER)) and not _has_text(lb, "坏名字探针") and _has_text(lb, "我自己探针"))
	## 拉黑之后从重画出来的新入口举报: 报上去的必须是原名(屏幕上那个默认名是本机换的, 管理员拿它查不到人)
	lay.free()
	var es2: Array = lb.find_children(PM.ENTRY, "Button", true, false).filter(func(x): return not (x as Node).is_queued_for_deletion())
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	_backend_on()
	var g0 := _got.size()
	if es2.size() == 1:
		(es2[0] as Button).pressed.emit()
		await _frames(1)
		lay = get_tree().current_scene.get_node_or_null(PM.LAYER)
		if lay != null:
			(lay.find_child(PM.BTN_REPORT, true, false) as Button).pressed.emit()
			await _frames(15)
	var jb = JSON.parse_string(str(_got[_got.size() - 1]["b"])) if _got.size() > g0 else null
	_ok("C ★拉黑后从排行榜举报 ⇒ 报的是原名 + 排行榜场景", jb is Dictionary and jb["p_name"] == "坏名字探针"
		and jb["p_context"] == RPT.CTX_LEADERBOARD, str(jb))
	_backend_off(env0, key0)
	if lay == null:
		lb.queue_free()
		return
	(lay.find_child(PM.BTN_BLOCK, true, false) as Button).pressed.emit()
	await _frames(1)
	_ok("C ★移出 ⇒ 换回原名", _has_text(lb, "坏名字探针") and not _has_text(lb, BL.masked_name(T_OTHER)))
	lay.queue_free()
	lb.queue_free()
	await _frames(2)


# ── D ──────────────────────────────────────────────────────────────
func _t_board() -> void:
	print("  ── D 周六赛况板 ──")
	var gb = (load("res://scenes/GauntletBoard.tscn") as PackedScene).instantiate()
	add_child(gb)
	await _frames(6)
	gb._base = {"players": [
		_bp("我自己探针", PM.my_tag(), true), _bp("坏名字探针", T_OTHER, false)], "games": []}
	gb.set_live_rows([])
	await _frames(1)
	gb._on_player_pressed(PM.my_tag())
	await _frames(1)
	_ok("D 选中自己 ⇒ 右栏没有入口", gb._games_box.find_children(PM.ENTRY, "Button", true, false).is_empty())
	gb._on_player_pressed(T_OTHER)
	await _frames(1)
	var es: Array = gb._games_box.find_children(PM.ENTRY, "Button", true, false)
	_ok("D ★选中别人 ⇒ 右栏有入口「举报 / 拉黑」", es.size() == 1 and (es[0] as Button).text == PM.L_ENTRY, str(es.size()))
	if es.is_empty():
		gb.queue_free()
		return
	(es[0] as Button).pressed.emit()
	await _frames(1)
	var lay = get_tree().current_scene.get_node_or_null(PM.LAYER)
	_ok("D 点入口 ⇒ 菜单打开", lay != null)
	if lay == null:
		gb.queue_free()
		return
	(lay.find_child(PM.BTN_BLOCK, true, false) as Button).pressed.emit()
	await _frames(2)
	_ok("D ★拉黑 ⇒ 战绩榜那一行显示默认昵称、原名不在屏上", _has_text(gb, BL.masked_name(T_OTHER)) and not _has_text(gb, "坏名字探针"))
	lay.queue_free()
	gb.queue_free()
	BL.remove(T_OTHER)
	await _frames(2)


func _bp(nm: String, tag: String, me: bool) -> Dictionary:
	return {"name": nm, "tag": tag, "avatar": "basic", "state": "running", "state_text": "进行中",
		"w": 1, "l": 0, "me": me, "live": false}


# ── E ──────────────────────────────────────────────────────────────
func _t_bracket() -> void:
	print("  ── E 周日对阵图 ──")
	var mp = BMS.new()
	add_child(mp)
	await _frames(2)
	mp.set_data({"size": 2, "round": 1, "me": 0, "names": ["我自己探针", "坏名字探针"], "tags": [PM.my_tag(), T_OTHER],
		"round_at": 1, "srv_now": 100000}, {}, SUN_AM)
	await _frames(2)
	_ok("E 分母: 对手那一格是原名", str(mp.competitor(1, 0, 1).get("name", "")) == "坏名字探针", str(mp.competitor(1, 0, 1)))
	var mine: Control = mp._popup_side(1, 0, 0, -1)
	var foe: Control = mp._popup_side(1, 0, 1, -1)
	add_child(mine)
	add_child(foe)
	var ef: Array = foe.find_children(PM.ENTRY, "Button", true, false)
	_ok("E ★对局卡里对手一侧有入口、我这一侧没有", ef.size() == 1 and mine.find_children(PM.ENTRY, "Button", true, false).is_empty()
		and str((ef[0] as Button).get_meta("tag", "")) == T_OTHER)
	BL.add(T_OTHER, "坏名字探针")
	_ok("E ★拉黑 ⇒ 格子里显示默认昵称; 举报菜单拿到的仍是原名",
		str(mp.competitor(1, 0, 1).get("name", "")) == BL.masked_name(T_OTHER) and str(mp.competitor(1, 0, 1).get("raw", "")) == "坏名字探针")
	mp._on_block_changed()
	await _frames(2)
	_ok("E 重画后整张图上不再有原名", not _has_text(mp, "坏名字探针") and _has_text(mp, BL.masked_name(T_OTHER)))
	BL.remove(T_OTHER)
	mine.queue_free()
	foe.queue_free()
	mp.queue_free()
	await _frames(2)


# ── F ──────────────────────────────────────────────────────────────
func _t_battle() -> void:
	print("  ── F 对局顶栏 ──")
	_gs.reset_dual_lane()
	_gs.tutorial_active = false
	_gs.season_level = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_gs.dual_ghost = Backend.make_bot(3, rng)
	var ftag := str(Backend.profile_tag(_gs.dual_ghost["profile"]))
	var fname := str(_gs.dual_ghost["profile"]["name"])
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.dual_active = true
	_gs.current_lane = "top"
	_gs.lane_results = {}
	var s = RB.new()
	add_child(s)
	await _frames(40)
	s._deterministic = true
	s.set_process(false)
	var tb = s._hud._topbar if s._hud != null else null
	_ok("F 分母: 双路对局、顶栏状态层建出来了、对手有合法玩家 ID", tb != null and P2.tag_valid(ftag), ftag)
	if tb == null:
		s.queue_free()
		return
	var holder: Node = s.find_child("TopPortrait_R", true, false)
	var es: Array = holder.find_children(PM.ENTRY, "Button", true, false) if holder != null else []
	_ok("F ★对手头像上有入口(且是这个对手)", es.size() == 1 and str((es[0] as Button).get_meta("tag", "")) == ftag, str(es.size()))
	var hl: Node = s.find_child("TopPortrait_L", true, false)
	_ok("F 自己头像上没有入口", hl != null and hl.find_children(PM.ENTRY, "Button", true, false).is_empty())
	var nr := s.find_child("TopName_R", true, false) as Label
	_ok("F 分母: 顶栏对手名 = 原名", nr != null and nr.text == fname, nr.text if nr != null else "<无>")
	if es.size() == 1 and nr != null:
		(es[0] as Button).pressed.emit()
		await _frames(1)
		var lay = get_tree().current_scene.get_node_or_null(PM.LAYER)
		if lay != null:
			(lay.find_child(PM.BTN_BLOCK, true, false) as Button).pressed.emit()
			await _frames(1)
			lay.queue_free()
		_ok("F ★拉黑 ⇒ 顶栏对手名显示默认昵称", nr.text == BL.masked_name(ftag) and nr.text != fname, nr.text)
		_ok("F 重建顶栏时也是默认昵称(名字由 side_names 现换)", str(tb.side_names()["r"]) == BL.masked_name(ftag))
	BL.remove(ftag)
	s.queue_free()
	_gs.dual_active = false
	await _frames(3)


# ── G ──────────────────────────────────────────────────────────────
func _t_settings() -> void:
	print("  ── G 设置 → 黑名单 ──")
	BL.add(T_OTHER, "坏名字探针")
	BL.add(T_THIRD, "另一个探针")
	var sc: Control = SET.new()
	sc.acct_override = 1
	add_child(sc)
	await _frames(2)
	var bb = sc.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_BLOCKLIST, true, false)
	_ok("G 分母: 设置页有「黑名单」", bb is Button)
	if not (bb is Button):
		sc.queue_free()
		return
	(bb as Button).pressed.emit()
	await _frames(1)
	var lay = sc.get_node_or_null(BLP.LAYER)
	var rows: Array = lay.find_children(BLP.ROW_PREFIX + "*", "", true, false) if lay != null else []
	_ok("G ★名单列出 2 人(新拉黑的在前)、空提示藏着", rows.size() == 2 and str((rows[0] as Node).get_meta("tag", "")) == T_THIRD
		and not (lay.find_child(BLP.EMPTY, true, false) as Label).visible, str(rows.size()))
	if rows.size() == 2:
		((rows[0] as Node).find_child(BLP.BTN_REMOVE, true, false) as Button).pressed.emit()
		await _frames(2)
		rows = lay.find_children(BLP.ROW_PREFIX + "*", "", true, false).filter(func(x): return not (x as Node).is_queued_for_deletion())
		_ok("G ★点「移出」⇒ 那个人出名单、只剩一行", rows.size() == 1 and not BL.is_blocked(T_THIRD) and BL.is_blocked(T_OTHER), str(rows.size()))
		((rows[0] as Node).find_child(BLP.BTN_REMOVE, true, false) as Button).pressed.emit()
		await _frames(2)
		_ok("G ★全移出 ⇒「黑名单为空」", BL.count() == 0 and (lay.find_child(BLP.EMPTY, true, false) as Label).visible
			and (lay.find_child(BLP.EMPTY, true, false) as Label).text == BLP.MSG_EMPTY)
	sc.queue_free()
	await _frames(2)


# ── H ──────────────────────────────────────────────────────────────
func _t_nick_reset() -> void:
	print("  ── H 昵称被重置 ──")
	var body := "{\"ok\": true, \"names\": [\"坏名字探针\"]}"
	_ok("H 纯判据: 我现在就叫被重置的那个 ⇒ 清", RPT.nickname_was_reset(true, 200, body, "坏名字探针"))
	_ok("H 纯判据: 我已经改成别的了 ⇒ 不动", not RPT.nickname_was_reset(true, 200, body, "新名字"))
	_ok("H 纯判据: 坏回包 / 没起名 ⇒ 不动", not RPT.nickname_was_reset(true, 200, "[]", "坏名字探针")
		and not RPT.nickname_was_reset(true, 500, body, "坏名字探针") and not RPT.nickname_was_reset(true, 200, body, ""))
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	_backend_on()
	_gs.nickname = ""
	var p0: int = RPT.reset_posts
	var hit := [null]
	RPT.check_nickname_reset(func(h: bool) -> void: hit[0] = h)
	await _frames(3)
	_ok("H ★没起过名 ⇒ 不发请求", RPT.reset_posts == p0 and hit[0] == false)
	_gs.nickname = "坏名字探针"
	_reply[0] = {"ok": true, "code": 200, "body": body}
	RPT.check_nickname_reset(func(h: bool) -> void: hit[0] = h)
	await _frames(15)
	_ok("H ★被重置 ⇒ 发了 1 次、清掉自己起的名(显示回默认昵称)", RPT.reset_posts == p0 + 1 and hit[0] == true
		and str(_gs.nickname) == "" and str(Backend.player_display_name()) == str(_gs.default_nickname()),
		str(Backend.player_display_name()))
	_ok("H 请求是 rpc/my_nickname_reset", str(_got[_got.size() - 1]["u"]).ends_with("/rest/v1/rpc/my_nickname_reset"))
	_gs.nickname = "新名字"
	RPT.check_nickname_reset(func(h: bool) -> void: hit[0] = h)
	await _frames(15)
	_ok("H 名字已经改过 ⇒ 不动", hit[0] == false and str(_gs.nickname) == "新名字")
	_backend_off(env0, key0)


# ── 工具 ───────────────────────────────────────────────────────────
func _backend_on() -> void:
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._token = "probe-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_reply[0] = {"ok": true, "code": 200, "body": "{\"ok\": true}"}
	SB._transport_for_test = func(method: String, url: String, _h: PackedStringArray, b: String, cb: Callable) -> void:
		_got.append({"m": method, "u": url, "b": b})
		cb.call(_reply[0])


func _backend_off(env0: String, key0) -> void:
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)


func _has_text(root: Node, t: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).is_queued_for_deletion():
			continue
		var p: Node = l
		var dead := false
		while p != null and p != root:
			if p.is_queued_for_deletion():
				dead = true
				break
			p = p.get_parent()
		if not dead and (l as Label).text.contains(t):
			return true
	return false


func _finish() -> void:
	_ok("★分母: 断言条数 = %d" % NEED, _n + 1 == NEED, str(_n + 1))
	BL.clear_all()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
