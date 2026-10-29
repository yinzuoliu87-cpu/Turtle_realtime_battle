extends Node
## 闯关赛「排队时回主页 + 配上即跟播」录屏台（不是门禁，2026-10-29）。方案书 docs/plans/20261029c-闯关赛排队时可回主页.md。
## 用户 10-29「锁定了后，还是能回到主页的…开始战斗你得变按钮，在边上也要有取消按钮」「就跟lol观战一样呢」「全部今天做完」。
## 全程走产品入口（真匹配屏 / 真主菜单 / 真战斗场），只有服务器是假的：Supabase 走注入传输，状态流 = 本进程 HTTP（tests/_stream_http.gd），
##   流的内容 = 裁判程序在本进程真算一局录下的（同 verify_referee_live_own）。
## 时间线（[REC] 行打出视频秒数，开头算局那一段剪掉）：
##   匹配屏排队 4 秒 → 按「←」回主页 → 主页排队态 + 锁 3 秒 → 点背包弹被拦卡 3 秒 → 关卡 → 配上：「匹配成功」遮罩 →
##   匹配屏 VS 卡「等待服务器开始对局」2.5 秒 → 裁判开算、块每 0.15 秒到一块「正在载入对局」（开场总览 + 预览那段也在这里拉完）→ 进度条走满进直播、进场就是开打
##   （1 倍 20 秒，之后 REC_FF 倍快进）→ 播完出结算屏 6 秒 → 退出。遮罩到进场是同一条进度条（方案书 §4.7）。
## 跑法：
##   SHIP=1 QUIET=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> \
##   <godot> --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1560x720 --position 2000,80 \
##     --write-movie <输出>/demo.avi --fixed-fps 60 --quit-after 30000 res://tests/_rec_queue_home_live.tscn

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const H := preload("res://tests/_stream_http.gd")
const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MY_NAME := "夜猫子"
const FOE := {"profile": {"name": "kevin_99", "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF"}, "leaders": ["ninja", "dice", "pirate"]}
const MID := "6a000000-0000-4000-8000-0000000000aa"
const JOB := 901
const FPS := 60.0

var _gs
var _http: Node = null
var _chunks: Array = []
var _meta: Dictionary = {}
var _seed := 0
var _pair := false
var _job_status := "pending"
var _t0 := 0
var _join_ms := 0                 ## 进队那一刻（假服务器回的「已等待」按它往上数，像真服务器）
## 这一局真实录下的结果（假服务器的 referee_job_status 照它回）。原来写死「赢」⇒ 片子里终极战场我方团灭、蛋被打爆，结算屏却是「胜利」（2026-10-29 逐帧复查逮到）。
var _a_won := false
var _coins := 0
var _score := 0
var _wall0 := -1                  ## 墙钟限速的起点（微秒）；-1 = 还没开始（算局那一段不限速）
var _wf0 := 0


func _log(s: String) -> void:
	print("[REC] %6.2fs %s" % [float(Engine.get_process_frames() - _t0) / FPS, s])


func _sec(s: float) -> void:
	for _i in range(int(s * FPS)):
		await get_tree().process_frame


func _until(pred: Callable, max_s: float) -> bool:
	for _i in range(int(max_s * FPS)):
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.tutorial_active = false
	_gs.test_mode = true
	StudioIntro.played = true          # 工作室开场只在冷启动播一次（手机上开 App 时早播过了）
	var job: Dictionary = J.mirror(_gs)
	var nat: Dictionary = await P.record_referee(self, job, func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	_chunks = res.get("stream_chunks", [])
	_meta = (res.get("stream", {}) as Dictionary).duplicate()
	_seed = int(nat["seed"])
	_a_won = bool(res.get("a_won", false))     # 我方 = A（配对回的 side = "a"）
	_coins = int(res.get("coins", 0))
	_score = int(res.get("score_code", 0))
	print("[REC] 本局录下的结果: 我方%s · 各路 %s · 铸币 %d" % ["胜" if _a_won else "负", str(res.get("lane_results", {})), _coins])
	if _chunks.is_empty():
		print("REC FAIL: 没录到流")
		get_tree().quit(1)
		return
	_setup_gs()
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	## 真流程在选队那一步把开局阶段钉进存档（TeamSelectScene `week_phase = phase_at_utc(now)`）；录屏台跳过了选队，这里补上，
	##   否则结算屏按「积分赛」多放一格「本周场次 0/16」（2026-10-29 逐帧复查逮到，是录屏台的漏洞不是游戏的）。
	_gs.week_phase = P2C.phase_at_utc(P2C.now_utc())
	_http = H.new()
	add_child(_http)
	_http.start()
	OS.set_environment(SW.ENV_BASE, _http.base())
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_t0 = Engine.get_process_frames()
	_wall0 = Time.get_ticks_usec()
	_wf0 = _t0
	_log("START 演示开始（这之前是本进程算局录流，剪掉）")
	await _demo()


## 墙钟限速：Movie Maker 按固定 60 帧出片、菜单页渲染比真时间快 ⇒ 按墙钟走的「已等待」在片子里只走半速
##   （片子第 4 秒还写「已等待 1 秒」，2026-10-29 逐帧复查逮到）。这里让墙钟不快于片子（只会等，不会追：渲染慢的那几段照旧）。
func _process(_d: float) -> void:
	if _wall0 < 0:
		return
	var due := _wall0 + int(float(Engine.get_process_frames() - _wf0) * 1000000.0 / FPS)
	var now := Time.get_ticks_usec()
	if due > now:
		OS.delay_usec(due - now)


func _setup_gs() -> void:
	_gs.account_id = ME
	_gs.nickname = MY_NAME
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.persistent_equipped = {}
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	_gs.battles_total = 9
	_gs.season_total_battles = 9      # 能打到周六闯关赛的人本大轮必然打过积分赛；不设则商店那一行写「首战后解锁」而不是「匹配中」
	_gs.meta_deepsea_coins = 40
	_gs.referee_pending = {}
	_gs.replay_pending_id = ""
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true, RN.K_STREAM: true, RN.K_STREAM_VER: ReplayRecorder.client_version()}
	_gs.dual_active = true
	var anchor: int = P2C.week_anchor_utc(P2C.now_utc())
	_gs.close_card_ranked_wk = anchor
	_gs.close_card_gauntlet_wk = anchor


func _waiting() -> String:
	return JSON.stringify({"ok": true, "status": "waiting", "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses),
		"waited_sec": maxi(0, (Time.get_ticks_msec() - _join_ms) / 1000)})


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600, "user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(_gs.referee_flags)})
			return
		"gauntlet_queue_join":
			_join_ms = Time.get_ticks_msec()
			cb.call({"ok": true, "code": 200, "body": _waiting()})
			return
		"gauntlet_queue_poll":
			if _pair:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "paired", "job_id": JOB,
					"match_id": MID, "side": "a", "job_status": _job_status, "opp": FOE,
					"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "waited_sec": 9})})
			else:
				cb.call({"ok": true, "code": 200, "body": _waiting()})
			return
		"gauntlet_queue_cancel":
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"status\":\"cancelled\"}"})
			return
		"referee_job_status":
			if _job_status == "done":
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": MID,
					"won": _a_won, "score": _score, "gw": int(_gs.gauntlet_wins) + (1 if _a_won else 0),
					"gl": int(_gs.gauntlet_losses) + (0 if _a_won else 1), "coins": _coins, "error": null})})
			else:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": _job_status, "match_id": MID})})
			return
		"referee_live_gauntlet":
			var rows: Array = []
			if _job_status == "claimed":
				var now := Time.get_datetime_string_from_unix_time(P2C.now_utc()) + "Z"
				rows.append({"match_id": MID, "started_at": now, "updated_at": now, "seed": _seed,
					"client_version": ReplayRecorder.client_version(),
					"lp": {"name": MY_NAME, "avatar": "basic", "id": "", "tag": ""}, "rp": {"name": "kevin_99", "avatar": "ninja", "id": "", "tag": ""}})
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(rows)})
			return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _scene() -> Node:
	return get_tree().current_scene


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null and str((n.get_script() as Script).resource_path) == RB_PATH


func _press_text(root: Node, text: String) -> bool:
	if root == null:
		return false
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text == text and (c as Button).is_visible_in_tree():
			(c as Button).pressed.emit()
			return true
	return false


func _demo() -> void:
	## ① 匹配屏：锁定阵容、排队
	var old := _scene()
	var mm: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	get_tree().current_scene = mm
	if old != null and old != self:
		old.queue_free()
	await _until(func() -> bool: return mm.find_child("QueueBox", true, false) != null, 10.0)
	_log("① 匹配屏排队中（左上「←」可回主页）")
	await _sec(4.0)
	## ② 按「←」回主页
	var back: Button = mm.get("_cancel_btn")
	back.pressed.emit()
	_log("② 按「←」回主页、继续匹配")
	await _until(func() -> bool: return _scene() != null and _scene().get_script() == MENU, 6.0)
	var menu := _scene()
	_log("③ 主页：主按钮「匹配中 / 已等待」+ 左侧取消；背包 / 商店 / 训龟大师 / ? 锁着")
	await _sec(3.5)
	## ④ 点背包 ⇒ 被拦卡
	var pb = menu.get("page_box")
	var holder: Node = pb.get_node_or_null(str(MENU.SQ_NAME_PREFIX) + "背包") if pb != null else null
	var bag: Button = null
	if holder != null:
		var bs := holder.find_children("*", "Button", true, false)
		bag = (bs[0] as Button) if not bs.is_empty() else (holder as Button if holder is Button else null)
	if bag != null:
		bag.pressed.emit()
		_log("④ 点背包 ⇒ 被拦卡")
		await _sec(3.0)
		_press_text(menu, "确定")
		await _sec(1.0)
	## ⑤ 配上 ⇒ 遮罩 ⇒ 匹配屏 VS 卡（裁判机还在排队：「等待服务器开始对局」）
	_pair = true
	_log("⑤ 服务器配上对手")
	await _until(func() -> bool: return _scene() != null and str(_scene().scene_file_path) == MMK_SCENE, 8.0)
	_log("⑥ 匹配屏 VS 卡 · 等待服务器开始对局（进度条在这一段里慢慢走、不走满）")
	await _sec(2.5)
	## ⑦ 裁判开算 ⇒ 边算边推流：块一块一块到（每 0.15 秒一块），VS 卡上进度条最后一段按已到块数走，攒够开场那段 + 开播那几块才进场
	var n := _chunks.size()
	var served := 0
	_http.put(MID, _chunks, _meta, served, false)
	_job_status = "claimed"
	_log("⑦ 服务器开始算 ⇒ VS 卡上「正在载入对局」拉开播那几块")
	var t_buf := 0.0
	while not (_is_battle(_scene()) and _scene()._replay.player != null) and t_buf < 15.0:
		await _sec(0.15)
		t_buf += 0.15
		if served < mini(StreamPlayer.live_start_chunks() + 2, n):
			served += 1
			_http.put(MID, _chunks, _meta, served, false)
	_log("   进场（进场那一刻已到 %d 块）" % served)
	var bt := _scene()
	_log("⑧ 正在看直播（1 倍速）")
	var t_live := 0.0
	var ff := float(OS.get_environment("REC_FF")) if OS.get_environment("REC_FF").is_valid_float() else 5.0
	var sped := false
	while is_instance_valid(bt) and bt._replay.player != null and str(bt._replay.player.state) != "ended" and t_live < 240.0:
		await _sec(0.5)
		t_live += 0.5
		if served < n:
			served = mini(n, served + maxi(1, n / 40))
			_http.put(MID, _chunks, _meta, served, served >= n)
			if served >= n:
				_job_status = "done"
				_log("   服务器算完（画面还在后面）")
		if not sped and t_live >= 20.0:
			sped = true
			bt._replay.player.speed = ff
			_log("   ⏩ 之后 %.0f 倍速快进（演示用；玩家看到的是 1 倍）" % ff)
	_log("⑨ 播完 ⇒ 结算屏")
	await _sec(7.0)
	_log("END")
	get_tree().quit(0)
