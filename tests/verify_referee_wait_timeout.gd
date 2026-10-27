extends Node
## verify_referee_wait_timeout.gd — 周六服务器局等到上限还没算完 ⇒ 不许把人停在匹配屏(2026-10-22)。
##
## 由来: 内测服整周彩排(docs/plans/ref/内测服整周彩排台账.md 六 ③): 裁判机 1 个工作进程、一局约 29 秒,
##   一齐开局时提交 → 算完 > 180 秒的 7 / 100 局, 8 个号停在匹配屏「结算未完成，下次打开时补记」, 要自己按「←」才回主菜单补记。
## 全程走产品自己的入口(真匹配屏 → `referee_run.gd` → 真主菜单), 传输注入(不连网); 等待上限走缝 `RefereeWatch.poll_max_for_test`。
##
## 段落:
##   A 分母: 缝默认关(上限 = POLL_MAX)、玩家路径的上限 = POLL_SEC × POLL_MAX = 180 秒
##   B ★等到上限还没算完 ⇒ 自己回主菜单; 主菜单飘「稍后自动记入」; 没有本地成绩、单子留着;
##     ★主菜单开着时到点再查 ⇒ 服务器算完了当场补记(战绩 / 币 / 战绩页 = 服务器那一份), 飘结果、撤掉「稍后」那一句; 单子清了就不再查
##   C 还在等结果时按「←」⇒ 主菜单同样飘那一句(那一场照样记)
##   D 没有单子 ⇒ 主菜单不建查任务的计时器(不白发请求)
## ── 2026-10-27 周六改在线排队: 交阵容换成进队 gauntlet_queue_join, 假服务器让它当场配上(我是 a), 之后一字不变。
##   180 秒上限量的是「配上之后等裁判算完」那一段(POLL_SEC × POLL_MAX), 排队本身另有心跳 / 取消(verify_gauntlet_online_queue)。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MMK := preload("res://scripts/scenes/MatchmakingScene.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const LIMIT := 3                      # 门禁里的等待上限(次); 玩家路径是 POLL_MAX

var _fail := 0
var _n := 0
var _gs
var _job := 41
var _status_asks := 0
var _srv_done := false
var _srv_coins := 7


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


## 墙钟上限等条件成立(匹配屏有真计时器: 动画 2.2 秒 + 每 POLL_SEC 秒查一次)。
func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_setup_gs()
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_ok("分母: 周六、闯关赛上线、开关开", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and P2C.phase_mode_live(P2C.PHASE_GAUNTLET) and RW.gauntlet_on())
	_t_a()
	await _t_b()
	await _t_c()
	await _t_d()
	_cleanup()
	_finish()


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 1
	_gs.battles_total = 9                 # 不是「第一次进主菜单」(那一屏会先开赛程页)
	_gs.referee_pending = {}
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true}
	_gs.dual_active = true


func _cleanup() -> void:
	var cs := get_tree().current_scene
	if cs != null and is_instance_valid(cs) and cs != self:
		cs.queue_free()
	RW.poll_max_for_test = 0
	RW.notice = ""
	MMK._may_leave_for_test = Callable()
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	_gs.referee_flags = {}
	_gs.referee_pending = {}


func _transport(_m, u, _h, _b, cb) -> void:
	var url := str(u)
	if url.find("/rpc/gauntlet_queue_join") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "paired", "side": "a", "job_id": _job, "match_id": MID,
			"opp": {"profile": {"name": "kevin_99", "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF"},
				"leaders": ["ninja", "dice", "pirate"]},
			"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses)})})
		return
	if url.find("/rpc/referee_flags") >= 0:
		cb.call({"ok": true, "code": 200, "body": "{\"finals_on\":false,\"gauntlet_on\":true}"})
		return
	if url.find("/rpc/referee_job_status") >= 0:
		_status_asks += 1
		if not _srv_done:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": MID})})
			return
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": MID,
			"won": true, "score": 0, "gw": _srv_gw(), "gl": _srv_gl(), "coins": _srv_coins, "error": null})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


## 服务器账本: 交上去那一刻的战绩 + 这一场赢(B 段开局记下)。
var _gw0 := 0
var _gl0 := 0
func _srv_gw() -> int:
	return _gw0 + 1
func _srv_gl() -> int:
	return _gl0


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).size()}


func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _status_text(m) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var l := (m as Node).find_child("RefereeStatus", true, false) as Label
	return l.text if l != null else ""


func _is_menu(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == MENU


## 主菜单上正飘着的那一行(直接挂在主菜单下的 Label, `_toast` 建的)。
func _toasts(menu: Node) -> Array:
	var out: Array = []
	if menu == null or not is_instance_valid(menu):
		return out
	for c in menu.get_children():
		if c is Label and not (c as Node).is_queued_for_deletion():
			out.append(str((c as Label).text))
	return out


# ─────────────────────────────────────────────────────────────
func _t_a() -> void:
	print("── A 分母: 缝默认关 ──")
	_ok("A 缝默认关: 上限 = POLL_MAX(%d)" % RW.POLL_MAX, RW.poll_max_for_test == 0 and RW.poll_max() == RW.POLL_MAX)
	_ok("A 玩家路径的等待上限 = %.0f 秒(POLL_SEC × POLL_MAX)" % (RW.POLL_SEC * RW.POLL_MAX),
		is_equal_approx(RW.POLL_SEC * float(RW.POLL_MAX), 180.0))
	_ok("A 屏上那一句: 短句、无感叹号、不说「下次打开」(主菜单开着时就会补记)",
		RW.TXT_LATER != "" and RW.TXT_LATER.find("！") < 0 and RW.TXT_LATER.find("!") < 0
		and RW.TXT_LATER.find("下次打开") < 0, RW.TXT_LATER)


func _t_b() -> void:
	print("── B 等到上限还没算完 ⇒ 回主菜单, 主菜单开着时补记 ──")
	_srv_done = false
	RW.notice = ""
	RW.poll_max_for_test = LIMIT
	var s0 := _snap()
	_gw0 = int(s0["gw"])
	_gl0 = int(s0["gl"])
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return (_status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job), 15000)
	_ok("B 分母: 交上去了、屏上「%s」、单子落了" % RW.TXT_SETTLING, _status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, _status_text(m))
	## 匹配屏离场前最后看到的那一行字、离场那一刻查过几次任务
	var last_text := ""
	var asks_at_leave := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and not _is_menu(get_tree().current_scene):
		if is_instance_valid(m):
			var tx := _status_text(m)
			if tx != "":
				last_text = tx
			if asks_at_leave < 0 and is_instance_valid(m) and m.find_child("RefereeRun", true, false) != null \
					and str(m.find_child("RefereeRun", true, false).state) == RW.ST_LATER:
				asks_at_leave = _status_asks
		await get_tree().process_frame
	var menu := get_tree().current_scene
	_ok("B ★分母: 匹配屏真的等到了上限(查了 %d 次 = 上限 %d, 不是断网那一支)" % [asks_at_leave, LIMIT], asks_at_leave == LIMIT)
	_ok("B ★没停在匹配屏: 自己回到主菜单", _is_menu(menu), str(menu.scene_file_path) if menu != null else "null")
	_ok("B 离开前那一行字是「%s」" % RW.TXT_LATER, last_text == RW.TXT_LATER, last_text)
	if not _is_menu(menu):
		RW.poll_max_for_test = 0
		return
	await _wait(func() -> bool: return _toasts(menu).has(RW.TXT_LATER), 4000)
	_ok("B ★主菜单飘「%s」" % RW.TXT_LATER, _toasts(menu).has(RW.TXT_LATER), str(_toasts(menu)))
	_ok("B 那一句读走即清(不会下一次进主菜单再飘)", RW.notice == "")
	var s1 := _snap()
	_ok("B ★没有本地成绩: 战绩 / 币 / 场次 / 战绩页都没动", s1 == s0, "%s → %s" % [str(s0), str(s1)])
	_ok("B ★待记账单留着(这一场)", int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job)
	## 主菜单开场那一次查(resume_if_any)落定了再量计时器那几次
	await _wait(func() -> bool: return _status_asks >= asks_at_leave + 1, 4000)
	_ok("B 分母: 主菜单开场查了一次(还在算 ⇒ 单子留着)", _status_asks == asks_at_leave + 1
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, "asks %d" % _status_asks)
	await _frames(5)
	var tm := menu.get_node_or_null(MENU.REF_RESUME_TIMER) as Timer
	_ok("B ★主菜单挂了查任务的计时器(每 %.0f 秒, 在走)" % RW.MENU_POLL_SEC,
		tm != null and not tm.is_stopped() and is_equal_approx(tm.wait_time, RW.MENU_POLL_SEC),
		"timer=%s" % str(tm))
	if tm == null:
		RW.poll_max_for_test = 0
		return
	## 计时器到点但裁判机还在算 ⇒ 问一次、单子照旧留着
	var a0 := _status_asks
	tm.timeout.emit()
	await _wait(func() -> bool: return _status_asks > a0, 4000)
	await _frames(3)
	_ok("B 到点还没算完: 问了一次、单子留着、战绩没动", _status_asks == a0 + 1
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job and _snap() == s0, "asks %d → %d" % [a0, _status_asks])
	## 裁判机算完了(赢 + 战斗内铸币) ⇒ 下一次到点当场补记
	_srv_done = true
	a0 = _status_asks
	tm.timeout.emit()
	await _wait(func() -> bool: return (_gs.referee_pending as Dictionary).is_empty(), 4000)
	await _frames(3)
	var s2 := _snap()
	_ok("B ★主菜单开着就补记了: 战绩 = 服务器账本 %d-%d" % [_srv_gw(), _srv_gl()],
		int(s2["gw"]) == _srv_gw() and int(s2["gl"]) == _srv_gl(), str(s2))
	_ok("B ★币 + 场次币 %d + 服务器那一局的铸币 %d、场次 +1、战绩页 +1" % [P2C.GAUNTLET_COINS_PER_MATCH, _srv_coins],
		int(s2["coins"]) == int(s0["coins"]) + int(P2C.GAUNTLET_COINS_PER_MATCH) + _srv_coins
		and int(s2["bt"]) == int(s0["bt"]) + 1 and int(s2["mh"]) == int(s0["mh"]) + 1, "%s → %s" % [str(s0), str(s2)])
	var row: Dictionary = (_gs.match_history as Array)[0] if not (_gs.match_history as Array).is_empty() else {}
	_ok("B 战绩页那一行 = 服务器的结果、挂录像号", str(row.get("result", "")) == "win" and str(row.get("replay_id", "")) == MID, str(row))
	_ok("B ★待记账单清了", (_gs.referee_pending as Dictionary).is_empty())
	_ok("B ★主菜单飘结果「%s」、撤掉「稍后自动记入」那一句" % RW.TXT_RESUMED_WIN,
		_toasts(menu).has(RW.TXT_RESUMED_WIN) and not _toasts(menu).has(RW.TXT_LATER), str(_toasts(menu)))
	## 单子清了 ⇒ 再到点不再发请求, 计时器拆掉
	a0 = _status_asks
	tm.timeout.emit()
	await _frames(5)
	_ok("B 单子清了: 再到点不发请求、计时器拆掉", _status_asks == a0
		and (not is_instance_valid(tm) or tm.is_queued_for_deletion()), "asks %d → %d" % [a0, _status_asks])
	RW.poll_max_for_test = 0


func _t_c() -> void:
	print("── C 还在等结果时按「←」⇒ 主菜单同样说一句 ──")
	_srv_done = false
	_job += 1
	RW.notice = ""
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return (_status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job), 15000)
	_ok("C 分母: 在等结果(「%s」、单子 %d)" % [RW.TXT_SETTLING, _job], _status_text(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job, _status_text(m))
	m._on_cancel()                        # 左上「←」的真回调
	await _wait(func() -> bool: return _is_menu(get_tree().current_scene), 5000)
	var menu := get_tree().current_scene
	_ok("C 分母: 回到主菜单", _is_menu(menu))
	await _wait(func() -> bool: return _toasts(menu).has(RW.TXT_LATER), 4000)
	_ok("C ★主菜单飘「%s」(那一场照样算、照样记)" % RW.TXT_LATER, _toasts(menu).has(RW.TXT_LATER), str(_toasts(menu)))
	_ok("C 单子留着、计时器挂上", int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job
		and is_instance_valid(menu) and menu.get_node_or_null(MENU.REF_RESUME_TIMER) != null)
	_gs.referee_pending = {}


func _t_d() -> void:
	print("── D 没有单子 ⇒ 主菜单不建计时器 ──")
	_gs.referee_pending = {}
	RW.notice = ""
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var a0 := _status_asks
	var menu: Node = (load(RW.MAIN_MENU) as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(20)
	_ok("D 分母: 主菜单建起来了", _is_menu(menu) and menu.get("content_root") != null)
	_ok("D ★没有单子: 不建计时器、不查任务、不飘那一句", menu.get_node_or_null(MENU.REF_RESUME_TIMER) == null
		and _status_asks == a0 and not _toasts(menu).has(RW.TXT_LATER), "asks %d → %d" % [a0, _status_asks])


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 裁判局等不到结果不停在匹配屏" if _fail == 0 and _n >= 25 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
