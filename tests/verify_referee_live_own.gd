extends Node
## verify_referee_live_own.gd — 周六配上之后跟播自己这一局(2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md
##   §4.4~§4.6 B7 / §6「B 配上即跟播」「B 记账不丢、不重」「B 收尾等结果、失败能出来」「B 旧路与陪练号不变」)。
## 用户 10-29「就跟lol观战一样呢」: 裁判一开算(任务 claimed)就进战斗场看这一局的直播, 结果播到最后才揭晓。
##
## 全程走产品入口: 真匹配屏 → referee_run(进队 → 配上 → 查任务)→ referee_live → StreamWatch.enter_own_live → 真战斗场(stream 模式)
##   → 真结算屏按钮 / 真「退出」(`_replay_exit`)→ 真主菜单。Supabase 走注入传输(不连网), 任务状态由门禁按段落拨:
##   pending → claimed → done / failed。状态流 = 本进程最小 HTTP 服务(tests/_stream_http.gd), 块 = 裁判程序在本进程真算一局录下的。
##
## 段落:
##   K 纯函数 / 直接调用: 种子查找、左右名字、配上回包留 job_status、开关; ★R2 预演 → 还原 → 真记(两次 view 逐键相同、币只加一次);
##     不在这一局的沙盒里 ⇒ on_done 什么都不做
##   A 我是 A: pending 时留在 VS 卡「等待服务器开始对局」、不问列表 → claimed 后才问列表拿种子、进跟播(进场时任务没算完)→
##     流先播完、任务仍 claimed ⇒ 收尾处「正在确认结果」(不出结算屏 / 不出回放收尾卡)→ done ⇒ 结算屏(服务器那一份数, 沙盒里预演)→
##     「前往商店」⇒ 商店进场时已是记完账的钱; 离场后真记一次、单子清掉、不飘「上一场闯关」
##   M 结果没到就退出 ⇒ 不记、单子留着; 主菜单补记一次; 再走一遍离场记账 / 主菜单补查 ⇒ 不记两次
##   N 我是 B: 左对手右我、「我方」= 右; 跟播中算完 ⇒ 结果原地填; 没看到结算屏就退出 ⇒ 记一次 + 主菜单飘「上一场闯关：…」
##   P 跟播中算完、播放中杀进程(守卫不回调)⇒ 还原后币回原值、单子还在; 下次主菜单补记一次(R2)
##   F 跟播中任务失败 ⇒ 回主菜单飘「结算失败，请重新开战」、销单、账不动
##   T 收尾等结果等满上限 ⇒ 回主菜单飘「稍后自动记入」、单子留着
##   S 陪练号(skip_play)⇒ claimed 也不进跟播; done ⇒ 旧路(先记账、不播)
##   O 列表里找不到这一局(种子没拿到)就已算完 ⇒ 旧路(当场记账, 没进跟播)
##   E 「进入对局」进度条(用户 10-29「那段的时间为什么不能够融入这个进度条里面呢？」): pending 在走、走不满 → claimed 后 VS 卡上
##     按已到块数走 → 块够开播那几块才进场、进场前条满、播放器接着用同一份来源、进去就开播; 全程只增不减
##   E2 拿到种子后块一直不来 ⇒ 等到上限照原来进场(不卡在 VS 卡上)

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RL := preload("res://scripts/systems/replay/referee_live.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const BE := preload("res://scripts/net/backend.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const H := preload("res://tests/_stream_http.gd")
const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const RUN_PATH := "res://scripts/systems/replay/referee_run.gd"
const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const SHOP_SCENE := "res://scenes/Shop.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MY_NAME := "LiveTester"
const FOE_NAME := "kevin_99"
const FOE := {"profile": {"name": FOE_NAME, "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF"}, "leaders": ["ninja", "dice", "pirate"]}
const MID_A := "6a000000-0000-4000-8000-00000000000a"
const MID_M := "6a000000-0000-4000-8000-00000000000b"
const MID_N := "6a000000-0000-4000-8000-00000000000c"
const MID_P := "6a000000-0000-4000-8000-00000000000d"
const MID_F := "6a000000-0000-4000-8000-00000000000e"
const MID_T := "6a000000-0000-4000-8000-00000000000f"
const MID_S := "6a000000-0000-4000-8000-000000000010"
const MID_O := "6a000000-0000-4000-8000-000000000011"
const MID_E := "6a000000-0000-4000-8000-000000000012"
const MID_E2 := "6a000000-0000-4000-8000-000000000013"

var _fail := 0
var _n := 0
var _gs
var _http: Node = null
var _hits := {}
var _chunks: Array = []
var _meta: Dictionary = {}
var _seed := 0
## 假服务器: 任务号 → {status, mid, side, won, gw, gl, coins}; 下一次进队配上哪一局; 直播列表开不开
var _jobs := {}
var _next_job := 700
var _cur := -1
var _live_rows_on := true
var _status_log: Array = []       # [任务号, 回的状态]
var _live_log: Array = []         # 每次问直播列表时当前那一局的状态


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


func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	_gs.tutorial_active = false
	_gs.test_mode = true
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	## 状态流: 裁判程序在本进程真算一局三路打满并录流(与 verify_stream_referee_paths 同一份对局)
	var job: Dictionary = J.mirror(_gs)
	var nat: Dictionary = await P.record_referee(self, job, func(_n2: int) -> bool: return false)
	var res: Dictionary = nat["res"]
	_chunks = res.get("stream_chunks", [])
	_meta = (res.get("stream", {}) as Dictionary).duplicate()
	_seed = int(nat["seed"])
	_ok("分母 · 裁判程序算完一局并录流(%d 块 / %d 步)" % [_chunks.size(), int(_meta.get("steps", 0))],
		bool(res.get("ok", false)) and _chunks.size() > 100 and _seed > 0)
	if _chunks.is_empty():
		_finish()
		return
	_setup_gs()
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_http = H.new()
	add_child(_http)
	_ok("分母 · 本机状态流服务起来了", _http.start())
	OS.set_environment(SW.ENV_BASE, _http.base())
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_ok("分母 · 周六、闯关赛上线、开关开(周六裁判 + 逐帧直播)", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and RW.gauntlet_on() and RN.stream_on())
	_t_k()
	await _t_a()
	await _t_m()
	await _t_n()
	await _t_p()
	await _t_f()
	await _t_t()
	await _t_s()
	await _t_o()
	await _t_e()
	await _t_e2()
	await _leave()
	_cleanup()
	_finish()


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.nickname = MY_NAME
	_gs.tutorial_active = false
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
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_gs.battles_total = 9                 # 不是「第一次进主菜单」(那一屏会先开赛程页)
	_gs.meta_deepsea_coins = 40
	_gs.referee_pending = {}
	_gs.replay_pending_id = ""
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true, RN.K_STREAM: true, RN.K_STREAM_VER: ReplayRecorder.client_version()}
	_gs.dual_active = true


func _cleanup() -> void:
	RL.confirm_max_for_test = 0.0
	RW.skip_play = false
	RW.notice = ""
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	OS.set_environment(SW.ENV_BASE, "")
	_gs.referee_flags = {}
	_gs.referee_pending = {}


## 开一局: 下一次进队就配上它(我是 side); 服务器账本 = 现在的战绩 + 这一场。
##   ★每一局开打前战绩拨回 1-0: 一路赢下去会撞上第 4 胜(晋级当场补发「省下的场次」币, 不在这一场的奖励里), 各段的账就对不上了。
func _new_job(mid: String, side: String, won: bool, coins: int, status: String = "pending") -> int:
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_next_job += 1
	var gw := int(_gs.gauntlet_wins) + (1 if won else 0)
	var gl := int(_gs.gauntlet_losses) + (0 if won else 1)
	_jobs[_next_job] = {"status": status, "mid": mid, "side": side, "won": won, "gw": gw, "gl": gl, "coins": coins}
	_cur = _next_job
	return _next_job


func _job(jid: int) -> Dictionary:
	return _jobs.get(jid, {})


func _asks_for(jid: int, st: String) -> int:
	var k := 0
	for e in _status_log:
		if int(e[0]) == jid and str(e[1]) == st:
			k += 1
	return k


func _transport(m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600, "user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(_gs.referee_flags)})
			return
		"gauntlet_queue_join", "gauntlet_queue_poll":
			var j := _job(_cur)
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "paired", "job_id": _cur,
				"match_id": str(j.get("mid", "")), "side": str(j.get("side", "a")), "job_status": str(j.get("status", "pending")),
				"opp": FOE, "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "waited_sec": 3})})
			return
		"referee_job_status":
			var q = JSON.parse_string(str(b))
			var jid := int((q as Dictionary).get("p_job_id", -1)) if q is Dictionary else -1
			var j := _job(jid)
			if j.is_empty():
				_status_log.append([jid, "no_job"])
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "no_job"})})
				return
			var st := str(j["status"])
			_status_log.append([jid, st])
			if st == "done":
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": str(j["mid"]),
					"won": bool(j["won"]), "score": 0, "gw": int(j["gw"]), "gl": int(j["gl"]), "coins": int(j["coins"]), "error": null})})
			else:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": st, "match_id": str(j["mid"])})})
			return
		"referee_live_gauntlet":
			_live_log.append(str(_job(_cur).get("status", "")))
			var rows: Array = []
			if _live_rows_on:
				var now := Time.get_datetime_string_from_unix_time(P2C.now_utc()) + "Z"
				for k in _jobs:
					if str(_jobs[k]["status"]) == "claimed":
						rows.append({"match_id": str(_jobs[k]["mid"]), "started_at": now, "updated_at": now, "seed": _seed,
							"client_version": ReplayRecorder.client_version(),
							"lp": {"name": "甲", "avatar": "basic", "id": "", "tag": ""}, "rp": {"name": "乙", "avatar": "stone", "id": "", "tag": ""}})
			cb.call({"ok": true, "code": 200, "body": JSON.stringify(rows)})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _leave() -> void:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(4)


func _open_mmk() -> Node:
	await _leave()
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _status_text(m) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var l := (m as Node).find_child("RefereeStatus", true, false) as Label
	return l.text if l != null else ""


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null and str((n.get_script() as Script).resource_path) == RB_PATH


func _battle_now() -> Node:
	var cs := get_tree().current_scene
	return cs if _is_battle(cs) and cs.get("_replay") != null and cs._replay.player != null else null


func _is_menu(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == MENU


func _menu_now() -> Node:
	var cs := get_tree().current_scene
	return cs if _is_menu(cs) else null


func _toasts(menu: Node) -> Array:
	var out: Array = []
	if menu == null or not is_instance_valid(menu):
		return out
	for c in menu.get_children():
		if c is Label and not (c as Node).is_queued_for_deletion():
			out.append(str((c as Label).text))
	return out


func _run():
	var r = load(RUN_PATH).active
	return r if r != null and is_instance_valid(r) and not (r as Node).is_queued_for_deletion() else null


func _bill_job() -> int:
	var p = _gs.referee_pending
	return int((p as Dictionary).get("job_id", -1)) if p is Dictionary else -1


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"mh": (_gs.match_history as Array).size()}


func _confirm_label(b: Node) -> Label:
	if b == null or not is_instance_valid(b):
		return null
	var l := b.find_child(BattleHud.N_LIVE_CONFIRM_TEXT, true, false) as Label
	return l if l != null and not l.is_queued_for_deletion() else null


func _settle_of(b: Node) -> Node:
	if b == null or not is_instance_valid(b) or b._hud == null:
		return null
	var s = b._hud._settle
	return s if s != null and is_instance_valid(s) else null


func _card_of(b: Node):
	if b == null or not is_instance_valid(b) or b._hud == null or b._hud._replay_ui == null:
		return null
	var c = b._hud._replay_ui.card
	return c if c != null and is_instance_valid(c) else null


## 进队 → 配上 → 查任务(门禁拨到 claimed)→ 进跟播。返回战斗场(没进 = null)。
##   served 默认 0 = 刚好够进场的块数(`StreamPlayer.live_start_chunks()`: 开场那段 + 开播缓冲; 会话在 VS 卡上攒够才进场, 不够要等满上限)。
func _enter_live(jid: int, mid: String, served: int = 0, ended: bool = false) -> Node:
	if served == 0:
		served = StreamPlayer.live_start_chunks()
	if served < 0:
		_http.put(mid, _chunks, _meta)
	else:
		_http.put(mid, _chunks, _meta, served, ended)
	_job(jid)["status"] = "claimed"
	await _open_mmk()
	if not await _wait(func() -> bool: return _battle_now() != null, 20000):
		return null
	return _battle_now()


## 战斗场里把流播到结尾(引擎每帧驱动, 倍速只改每帧推几步)。
func _play_to_end(b: Node) -> bool:
	var p: StreamPlayer = b._replay.player
	p.speed = 40.0
	return await _wait(func() -> bool: return not is_instance_valid(b) or p.state == "ended" or p.state == "error", 120000) \
		and is_instance_valid(b) and p.state == "ended"


# K ─────────────────────────────────────────────────────────────
func _t_k() -> void:
	print("── K 纯函数 / 直接调用 ──")
	var res := {"rows": [{"match_id": MID_A, "seed": 4242}, {"match_id": MID_M, "seed": 7}]}
	_ok("K 种子按录像号找那一行; 找不到 / 录像号不对 / 没有列表 ⇒ -1", RL.seed_in(res, MID_A) == 4242 and RL.seed_in(res, MID_M) == 7
		and RL.seed_in(res, MID_N) == -1 and RL.seed_in(res, "x") == -1 and RL.seed_in({"reason": "offline"}, MID_A) == -1)
	var nb := RL.names_for("b", FOE)
	_ok("K 名字(与看录像那条 watch_names 同一个口径): A ⇒ {}(左我右对手); B ⇒ {左对手, 右我, side b}; B 没对手名 ⇒ {}",
		RL.names_for("a", FOE).is_empty() and str(nb.get("l", "")) == FOE_NAME and str(nb.get("r", "")) == MY_NAME
		and str(nb.get("side", "")) == "b" and nb.size() == 3 and RL.names_for("b", {}).is_empty(), str(nb))
	var pq := RN.parse_queue(true, 200, JSON.stringify({"ok": true, "status": "paired", "job_id": 9, "side": "a", "match_id": MID_A,
		"job_status": "claimed", "opp": FOE}))
	var pq0 := RN.parse_queue(true, 200, JSON.stringify({"ok": true, "status": "paired", "job_id": 9, "side": "a"}))
	_ok("K 配上回包留下 job_status(配上那一刻就知道开没开算); 缺 ⇒ \"\"", str(pq.get("job_status", "?")) == "claimed"
		and str(pq0.get("job_status", "?")) == "", "%s / %s" % [str(pq.get("job_status")), str(pq0.get("job_status"))])
	_ok("K 走不走跟播: 逐帧直播开 ⇒ 走", RL.wanted())
	RW.skip_play = true
	var w_skip := RL.wanted()
	RW.skip_play = false
	_gs.referee_flags[RN.K_STREAM] = false
	var w_off := RL.wanted()
	_gs.referee_flags[RN.K_STREAM] = true
	_ok("K ★陪练号(skip_play)/ 逐帧直播关 ⇒ 不走跟播", not w_skip and not w_off)
	_ok("K 收尾等结果的上限: 缝默认关 = %.0f 秒" % RL.CONFIRM_MAX_SEC, RL.confirm_max_for_test == 0.0
		and is_equal_approx(RL.confirm_max_sec(), RL.CONFIRM_MAX_SEC) and is_equal_approx(RL.CONFIRM_MAX_SEC, 120.0))
	## ★R2: 同一份回包, 沙盒里预演 → 还原 → 真记
	var wk: int = P2C.week_anchor_utc(int(P2C.now_utc()))
	_gs.referee_pending = RW.pending_for(901, MID_A, wk, FOE)
	var s0 := _snap()
	var st := {"err": "", "status": "done", "match_id": MID_A, "won": 1, "gw": int(s0["gw"]) + 1, "gl": int(s0["gl"]), "coins": 4,
		"chest": {}, "incense": {}}
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH) + 4
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	var v1 := RW.settle(_gs, 901, st, true)
	var in_sb := _snap()
	var bill_in_sb := _bill_job()
	var rp_in_sb := str(_gs.replay_pending_id)
	ReplayRecorder.end_play()
	var after_restore := _snap()
	var v2 := RW.settle(_gs, 901, st)
	var s2 := _snap()
	_ok("K ★R2 预演: 沙盒里币 +%d、战绩 %d-%d、场次 +1" % [reward, int(st["gw"]), int(st["gl"])],
		int(in_sb["coins"]) == int(s0["coins"]) + reward and int(in_sb["gw"]) == int(st["gw"]) and int(in_sb["bt"]) == int(s0["bt"]) + 1, str(in_sb))
	_ok("K ★R2 预演不碰还原撤不掉的: 单子还在、战绩页没多一行、录像号没挂", bill_in_sb == 901 and int(in_sb["mh"]) == int(s0["mh"])
		and rp_in_sb == "")
	_ok("K ★R2 离场还原 ⇒ 账回到播之前(预演的一枚不剩)", after_restore == s0, "%s → %s" % [str(s0), str(after_restore)])
	_ok("K ★R2 真记: 两次 view 逐键相同(结算屏的数 = 真记的数)", not v1.is_empty() and str(v1) == str(v2), "%s / %s" % [str(v1), str(v2)])
	_ok("K ★R2 真记之后: 币只加一次(+%d)、场次 +1、战绩页 +1、单子清掉" % reward, int(s2["coins"]) == int(s0["coins"]) + reward
		and int(s2["bt"]) == int(s0["bt"]) + 1 and int(s2["mh"]) == int(s0["mh"]) + 1 and _bill_job() == -1, str(s2))
	_ok("K 再记一次 ⇒ {}(单子已清, 不记两次)", RW.settle(_gs, 901, st).is_empty() and _snap() == s2)
	_gs.referee_pending = RW.pending_for(903, MID_A, wk - 7 * 86400, FOE)
	var vw := RW.settle(_gs, 903, st, true)
	_ok("K 上一周的单子: 预演 ⇒ {}、不销单、账不动(离场后真记那一遍才销)", vw.is_empty() and _bill_job() == 903 and _snap() == s2)
	_gs.referee_pending = {}
	## 不在这一局的沙盒里 ⇒ on_done 什么都不做(玩家已离开跟播: 单子留给主菜单)
	_gs.referee_pending = RW.pending_for(902, MID_A, wk, FOE)
	var fr: Node = load(RUN_PATH).new()
	fr.job_id = 902
	fr.match_id = MID_A
	fr.opp = FOE.duplicate(true)
	var s3 := _snap()
	SW.current = {}
	RL.on_done(fr, st)
	var no_sess := _snap() == s3 and _bill_job() == 902
	SW.current = {"kind": SW.KIND_REFEREE, "own": true, "job_id": 902, "result": {}}
	RL.on_done(fr, st)                    # 会话对得上, 但 GameState 没有备份(不在沙盒里)
	var no_sb := _snap() == s3 and _bill_job() == 902 and (SW.current["result"] as Dictionary).is_empty()
	SW.current = {}
	fr.free()
	_ok("K ★不在这一局的沙盒里(没有会话 / 没有备份)⇒ on_done 不预演、不动账、不动单子", no_sess and no_sb)
	_gs.referee_pending = {}


# A ─────────────────────────────────────────────────────────────
func _t_a() -> void:
	print("── A 我是 A · pending → claimed(进跟播)→ 流先播完(正在确认结果)→ done(结算屏)→「前往商店」 ──")
	RW.notice = ""
	var jid := _new_job(MID_A, "a", true, 5)
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH) + 5
	_http.put(MID_A, _chunks, _meta, StreamPlayer.live_start_chunks(), false)
	_live_log.clear()
	var s0 := _snap()
	var e0: int = SW.own_enters
	var la0 := _hit("referee_live_gauntlet")
	var m: Node = await _open_mmk()
	var pend := await _wait(func() -> bool: return _status_text(m) == RW.TXT_LIVE_PENDING and _asks_for(jid, "pending") >= 2, 20000)
	_ok("A ★任务 pending ⇒ 留在 VS 卡, 下面一行「%s」(查了 %d 次)" % [RW.TXT_LIVE_PENDING, _asks_for(jid, "pending")],
		pend and get_tree().current_scene == m, _status_text(m))
	_ok("A ★pending 期间不问直播列表、不进跟播", _hit("referee_live_gauntlet") == la0 and SW.own_enters == e0
		and SW.current.is_empty() and _battle_now() == null)
	_ok("A 分母: 任务单 = 这一局", _bill_job() == jid)
	_job(jid)["status"] = "claimed"
	var got := await _wait(func() -> bool: return _battle_now() != null, 20000)
	var b: Node = _battle_now()
	var st_at_enter := str(_job(jid)["status"])
	_ok("A ★claimed ⇒ 问了直播列表拿种子(%d 次; 全在 claimed 之后)" % (_hit("referee_live_gauntlet") - la0),
		_hit("referee_live_gauntlet") > la0 and not _live_log.has("pending"), str(_live_log))
	_ok("A ★进了战斗场跟播(stream 模式), 进场那一刻任务还没算完(%s)" % st_at_enter, got and b != null
		and str(b._replay.mode) == "stream" and st_at_enter == "claimed" and SW.own_enters == e0 + 1)
	if b == null:
		return
	var p: StreamPlayer = b._replay.player
	_ok("A ★会话 = 裁判局 + 自己那一局、result 先空、任务号 / 录像号对", str(SW.current.get("kind", "")) == SW.KIND_REFEREE
		and bool(SW.current.get("own", false)) and (SW.current.get("result", {}) as Dictionary).is_empty()
		and int(SW.current.get("job_id", -1)) == jid and str(SW.current.get("id", "")) == MID_A, str(SW.current))
	_ok("A 边算边播(没说早算完 ⇒ 404 永不判没有)、地图种子 = 列表那一行", p.src is StreamSource.Http and not bool(p.src.finished)
		and int(b._battle_rng.seed) == _seed)
	await _frames(6)
	_ok("A 跟播没有操作条, 只有「退出」", not p.controls and b.find_child(RC.N_PAUSE, true, false) == null
		and b.find_child(RC.N_EXIT, true, false) != null)
	var nm: Dictionary = StreamHud.side_names()
	_ok("A ★名字两边都非空: 左 = 我(%s)、右 = 对手(%s); 「我方」= 左" % [str(nm.get("l")), str(nm.get("r"))],
		str(nm.get("l", "")) == MY_NAME and str(nm.get("r", "")) == FOE_NAME and ReplayRecorder.viewer_side(b) == "a")
	_ok("A 沙盒: GameState 已备份 + 存盘空转; 账还没动", ReplayRecorder._has_backup and bool(_gs.test_mode) and _snap() == s0)
	## R11: 服务器录完了(end.json 已发)但任务还是 claimed
	_http.put(MID_A, _chunks, _meta)
	var ended := await _play_to_end(b)
	_ok("分母 · A 流播到结尾(应用 %d / %d 步)、任务仍 %s" % [p.steps_applied, int(_meta.get("steps", 0)), str(_job(jid)["status"])],
		ended and p.steps_applied == int(_meta.get("steps", -1)) and str(_job(jid)["status"]) == "claimed")
	var lb_ok := await _wait(func() -> bool: return _confirm_label(b) != null, 8000)
	var lb := _confirm_label(b)
	_ok("A ★结果还没到 ⇒ 收尾处「%s」; 不出结算屏、不出回放收尾卡" % RW.TXT_LIVE_CONFIRM, lb_ok and lb != null
		and lb.text == RW.TXT_LIVE_CONFIRM and lb.is_visible_in_tree() and _settle_of(b) == null and _card_of(b) == null and not b._settled)
	await _frames(40)
	_ok("A 等结果期间一直不出结算屏 / 收尾卡", is_instance_valid(b) and _settle_of(b) == null and _card_of(b) == null
		and _confirm_label(b) != null)
	_job(jid)["status"] = "done"
	var shown := await _wait(func() -> bool: return _settle_of(b) != null, 12000)
	var res: Dictionary = SW.current.get("result", {})
	_ok("A ★done ⇒ 撤掉「%s」、出正常结算屏" % RW.TXT_LIVE_CONFIRM, shown and _confirm_label(b) == null and _card_of(b) == null)
	_ok("A ★结算屏的数 = 服务器那一份: 胜、奖励 %d(场次币 + 铸币 5)" % reward, bool(res.get("won", false))
		and int(res.get("reward", -1)) == reward and int(b._last_reward) == reward and bool(SW.current.get("shown", false)), str(res))
	var sb_snap := _snap()
	_ok("A ★沙盒里预演: 战绩 %d-%d、币 +%d(结算屏 / 晋级仪式照原来的读法)" % [int(_job(jid)["gw"]), int(_job(jid)["gl"]), reward],
		int(sb_snap["gw"]) == int(_job(jid)["gw"]) and int(sb_snap["gl"]) == int(_job(jid)["gl"])
		and int(sb_snap["coins"]) == int(s0["coins"]) + reward, str(sb_snap))
	_ok("A ★R2 预演没碰还原撤不掉的: 单子还在、战绩页没多一行、录像号没挂", _bill_job() == jid and int(sb_snap["mh"]) == int(s0["mh"])
		and str(_gs.replay_pending_id) == "")
	## 「前往商店」: 商店进场(_ready 之前)那一刻读到的钱
	var sbtn: Button = null
	if _settle_of(b) != null:
		for c in _settle_of(b).find_children("*", "Button", true, false):
			if (c as Button).text == BattleHud.SHOP_BTN_TEXT:
				sbtn = c
	_ok("分母 · 结算屏有「%s」" % BattleHud.SHOP_BTN_TEXT, sbtn != null)
	if sbtn == null:
		return
	var at_shop := [-1]
	var hook := func(n: Node) -> void:
		if int(at_shop[0]) < 0 and str(n.scene_file_path) == SHOP_SCENE:
			at_shop[0] = int(_gs.meta_deepsea_coins)
	get_tree().node_added.connect(hook)
	sbtn.pressed.emit()
	await _wait(func() -> bool: return int(at_shop[0]) >= 0, 10000)
	get_tree().node_added.disconnect(hook)
	_ok("A ★「前往商店」⇒ 商店进场时读到的已是记完账的钱(%d)" % int(at_shop[0]), int(at_shop[0]) == int(s0["coins"]) + reward)
	var s1 := _snap()
	_ok("A ★离场后真记了一次: 币 +%d、战绩 %d-%d、场次 +1、胜场 +1、战绩页 +1" % [reward, int(s1["gw"]), int(s1["gl"])],
		int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["gw"]) == int(_job(jid)["gw"]) and int(s1["gl"]) == int(_job(jid)["gl"])
		and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["bw"]) == int(s0["bw"]) + 1 and int(s1["mh"]) == int(s0["mh"]) + 1,
		"%s → %s" % [str(s0), str(s1)])
	var row: Dictionary = (_gs.match_history as Array)[0] if not (_gs.match_history as Array).is_empty() else {}
	_ok("A 战绩页那一行 = 服务器的结果、挂录像号、对手名", str(row.get("result", "")) == "win" and str(row.get("replay_id", "")) == MID_A
		and str(row.get("foe_name", "")) == FOE_NAME, str(row))
	_ok("A ★单子清掉、沙盒还原(备份清掉)、会话清掉; 看过结算屏 ⇒ 不飘「上一场闯关」", _bill_job() == -1
		and not ReplayRecorder._has_backup and SW.current.is_empty() and RW.notice == "", "notice「%s」" % RW.notice)
	await _wait(func() -> bool: return _run() == null, 6000)
	_ok("A 会话自删", _run() == null)
	await _leave()


# M ─────────────────────────────────────────────────────────────
func _t_m() -> void:
	print("── M 结果没到就退出 ⇒ 不记、单子留着; 主菜单补记一次; 不记两次 ──")
	RW.notice = ""
	var jid := _new_job(MID_M, "a", false, 0)
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH)
	var s0 := _snap()
	var b: Node = await _enter_live(jid, MID_M)
	_ok("分母 · M 进了跟播", b != null and bool(SW.current.get("own", false)))
	if b == null:
		return
	await _frames(10)
	b._hud._replay_exit()                 # 真「退出」(确认框里那颗连的就是它)
	var in_menu := await _wait(func() -> bool: return _menu_now() != null, 10000)
	var menu := _menu_now()
	_ok("分母 · M 回到主菜单", in_menu)
	_ok("M ★离场时结果还没到 ⇒ 不记: 币 / 战绩 / 场次 / 战绩页都没动, 单子留着", _snap() == s0 and _bill_job() == jid,
		"%s → %s" % [str(s0), str(_snap())])
	_ok("M 沙盒还原、会话清掉、不飘「上一场闯关」", not ReplayRecorder._has_backup and SW.current.is_empty()
		and not _toasts(menu).has(RW.TXT_RESUMED_WIN) and not _toasts(menu).has(RW.TXT_RESUMED_LOSE), str(_toasts(menu)))
	await _wait(func() -> bool: return _run() == null, 8000)
	_ok("M 会话发现玩家已离开跟播 ⇒ 自删(之后交给主菜单补记)", _run() == null)
	_job(jid)["status"] = "done"
	await _frames(5)
	var tm := menu.get_node_or_null(MENU.REF_RESUME_TIMER) as Timer if menu != null else null
	_ok("分母 · M 主菜单挂了补记计时器", tm != null)
	if tm == null:
		_gs.referee_pending = {}
		return
	tm.timeout.emit()
	await _wait(func() -> bool: return _bill_job() == -1, 6000)
	await _frames(3)
	var s1 := _snap()
	_ok("M ★主菜单补记了一次: 币 +%d、战绩 %d-%d、场次 +1、战绩页 +1、单子清掉" % [reward, int(_job(jid)["gw"]), int(_job(jid)["gl"])],
		int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["gw"]) == int(_job(jid)["gw"]) and int(s1["gl"]) == int(_job(jid)["gl"])
		and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["mh"]) == int(s0["mh"]) + 1 and _bill_job() == -1, "%s → %s" % [str(s0), str(s1)])
	_ok("M 主菜单飘「%s」" % RW.TXT_RESUMED_LOSE, _toasts(menu).has(RW.TXT_RESUMED_LOSE), str(_toasts(menu)))
	RL.on_left({"own": true, "job_id": jid})
	RW.resume_if_any()
	await _frames(10)
	_ok("M ★不记两次: 再走一遍离场记账 + 主菜单补查 ⇒ 账不变", _snap() == s1, "%s → %s" % [str(s1), str(_snap())])


# N ─────────────────────────────────────────────────────────────
func _t_n() -> void:
	print("── N 我是 B · 跟播中算完 · 没看到结算屏就退出 ⇒ 记一次 + 主菜单一句 ──")
	RW.notice = ""
	var jid := _new_job(MID_N, "b", true, 3)
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH) + 3
	var s0 := _snap()
	var b: Node = await _enter_live(jid, MID_N)
	_ok("分母 · N 进了跟播", b != null)
	if b == null:
		return
	var nm: Dictionary = StreamHud.side_names()
	_ok("N ★我是 B: 左 = 对手(%s)、右 = 我(%s); 「我方」指右边(viewer_side = b)" % [str(nm.get("l")), str(nm.get("r"))],
		str(nm.get("l", "")) == FOE_NAME and str(nm.get("r", "")) == MY_NAME and str(ReplayRecorder.play_names.get("side", "")) == "b"
		and ReplayRecorder.viewer_side(b) == "b", str(ReplayRecorder.play_names))
	_job(jid)["status"] = "done"
	var filled := await _wait(func() -> bool: return not (SW.current.get("result", {}) as Dictionary).is_empty(), 10000)
	var res: Dictionary = SW.current.get("result", {})
	_ok("N ★跟播中算完 ⇒ 结果原地填进会话(胜、奖励 %d、我是 B)" % reward, filled and bool(res.get("won", false))
		and int(res.get("reward", -1)) == reward and str(res.get("side", "")) == "b" and str(res.get("foe_name", "")) == FOE_NAME, str(res))
	_ok("N 沙盒里预演了(币 +%d); 流还没播完 ⇒ 还不出结算屏" % reward, int(_gs.meta_deepsea_coins) == int(s0["coins"]) + reward
		and _settle_of(b) == null and not bool(SW.current.get("shown", false)))
	## 主菜单进场(_ready 之前)那一刻: 账必须已由离场那一下记完(主菜单开场补查也能记, 不能拿它顶)
	var at_menu := [{}]
	var hook := func(n: Node) -> void:
		if (at_menu[0] as Dictionary).is_empty() and str(n.scene_file_path) == RW.MAIN_MENU:
			at_menu[0] = {"bill": _bill_job(), "coins": int(_gs.meta_deepsea_coins)}
	get_tree().node_added.connect(hook)
	b._hud._replay_exit()
	var in_menu := await _wait(func() -> bool: return _menu_now() != null, 10000)
	get_tree().node_added.disconnect(hook)
	var menu := _menu_now()
	_ok("N ★主菜单进场时账已记完、单子已清(离场那一下记的, 不靠主菜单补查)", int((at_menu[0] as Dictionary).get("bill", -2)) == -1
		and int((at_menu[0] as Dictionary).get("coins", -1)) == int(s0["coins"]) + reward, str(at_menu[0]))
	await _frames(3)
	var s1 := _snap()
	_ok("N ★中途退出: 账照记一次 — 币 +%d、战绩 %d-%d、场次 +1、战绩页 +1" % [reward, int(_job(jid)["gw"]), int(_job(jid)["gl"])],
		in_menu and int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["gw"]) == int(_job(jid)["gw"])
		and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["mh"]) == int(s0["mh"]) + 1 and _bill_job() == -1, "%s → %s" % [str(s0), str(s1)])
	var row: Dictionary = (_gs.match_history as Array)[0] if not (_gs.match_history as Array).is_empty() else {}
	_ok("N 战绩页那一行记着我在右边(side = b)、对手名", str(row.get("side", "")) == "b" and str(row.get("foe_name", "")) == FOE_NAME, str(row))
	await _wait(func() -> bool: return _toasts(menu).has(RW.TXT_RESUMED_WIN), 4000)
	_ok("N ★没看到结算屏 ⇒ 主菜单飘「%s」" % RW.TXT_RESUMED_WIN, _toasts(menu).has(RW.TXT_RESUMED_WIN), str(_toasts(menu)))
	_ok("N 会话已自删", _run() == null)


# P ─────────────────────────────────────────────────────────────
func _t_p() -> void:
	print("── P 跟播中算完、播放中杀进程 ⇒ 下次主菜单补记一次(R2) ──")
	RW.notice = ""
	var jid := _new_job(MID_P, "a", true, 2)
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH) + 2
	var s0 := _snap()
	var b: Node = await _enter_live(jid, MID_P)
	_ok("分母 · P 进了跟播", b != null)
	if b == null:
		return
	_job(jid)["status"] = "done"
	await _wait(func() -> bool: return not (SW.current.get("result", {}) as Dictionary).is_empty(), 10000)
	_ok("分母 · P 沙盒里预演过(币 +%d)" % reward, int(_gs.meta_deepsea_coins) == int(s0["coins"]) + reward)
	## 杀进程: 守卫不回调(进程没了)、战斗场没了; 重开 = 从盘上读 = 播之前那一份(沙盒里存盘空转, 盘上从没写过预演的数)
	for c in get_tree().root.get_children():
		if c is SW.Guard:
			(c as SW.Guard).retire()
	await _leave()
	ReplayRecorder.end_play()
	SW.current = {}
	RL._bill = {}                         # 静态量随进程没了
	_ok("P ★R2 重开后: 币回到播之前、单子还在(预演没销单)、战绩页没多一行", _snap() == s0 and _bill_job() == jid,
		"%s → %s" % [str(s0), str(_snap())])
	await _wait(func() -> bool: return _run() == null, 8000)
	var got: Array = []
	RW.resume_if_any(func(v: Dictionary) -> void: got.append(v))
	await _wait(func() -> bool: return _bill_job() == -1, 6000)
	var s1 := _snap()
	_ok("P ★主菜单补记一次: 币 +%d(不丢、不重)、场次 +1、战绩页 +1" % reward, got.size() == 1
		and int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["mh"]) == int(s0["mh"]) + 1,
		"%s → %s" % [str(s0), str(s1)])


# F ─────────────────────────────────────────────────────────────
func _t_f() -> void:
	print("── F 跟播中任务失败 ⇒ 回主菜单、销单 ──")
	RW.notice = ""
	var jid := _new_job(MID_F, "a", true, 0)
	var s0 := _snap()
	var b: Node = await _enter_live(jid, MID_F)
	_ok("分母 · F 进了跟播", b != null)
	if b == null:
		return
	## 主菜单进场(_ready 之前)那一刻的单子: 销单必须是跟播这一侧做的(主菜单开场补查也会销, 不能拿它顶)
	var at_menu := [-2]
	var hook := func(n: Node) -> void:
		if int(at_menu[0]) == -2 and str(n.scene_file_path) == RW.MAIN_MENU:
			at_menu[0] = _bill_job()
	get_tree().node_added.connect(hook)
	_job(jid)["status"] = "failed"
	var in_menu := await _wait(func() -> bool: return _menu_now() != null, 10000)
	get_tree().node_added.disconnect(hook)
	var menu := _menu_now()
	await _wait(func() -> bool: return _toasts(menu).has(RW.TXT_FAILED), 4000)
	_ok("F ★任务失败 ⇒ 结束播放回主菜单、飘「%s」" % RW.TXT_FAILED, in_menu and _toasts(menu).has(RW.TXT_FAILED), str(_toasts(menu)))
	_ok("F ★主菜单进场时单子已经销掉(跟播这一侧销的, 不靠主菜单补查)", int(at_menu[0]) == -1, "进场时单子 %d" % int(at_menu[0]))
	_ok("F ★销单、账没动、沙盒还原、会话清掉", _bill_job() == -1 and _snap() == s0 and not ReplayRecorder._has_backup
		and SW.current.is_empty(), "%s → %s" % [str(s0), str(_snap())])
	await _wait(func() -> bool: return _run() == null, 6000)
	_ok("F 会话自删", _run() == null)


# T ─────────────────────────────────────────────────────────────
func _t_t() -> void:
	print("── T 收尾等结果等满上限 ⇒ 回主菜单「稍后自动记入」 ──")
	RW.notice = ""
	RL.confirm_max_for_test = 1.5
	var jid := _new_job(MID_T, "a", true, 0)
	var s0 := _snap()
	var b: Node = await _enter_live(jid, MID_T, -1)
	_ok("分母 · T 进了跟播", b != null)
	if b == null:
		RL.confirm_max_for_test = 0.0
		return
	var ended := await _play_to_end(b)
	var lb_ok := await _wait(func() -> bool: return _confirm_label(b) != null, 8000)
	_ok("分母 · T 流播完、停在「%s」" % RW.TXT_LIVE_CONFIRM, ended and lb_ok)
	var in_menu := await _wait(func() -> bool: return _menu_now() != null, 10000)
	var menu := _menu_now()
	await _wait(func() -> bool: return _toasts(menu).has(RW.TXT_LATER), 4000)
	_ok("T ★等满上限 ⇒ 回主菜单飘「%s」" % RW.TXT_LATER, in_menu and _toasts(menu).has(RW.TXT_LATER), str(_toasts(menu)))
	_ok("T ★单子留着(主菜单补记)、账没动、会话清掉", _bill_job() == jid and _snap() == s0 and SW.current.is_empty())
	RL.confirm_max_for_test = 0.0
	await _wait(func() -> bool: return _run() == null, 8000)
	_job(jid)["status"] = "failed"
	_gs.referee_pending = {}


# S ─────────────────────────────────────────────────────────────
func _t_s() -> void:
	print("── S 陪练号(skip_play)⇒ 不进跟播, 旧路 ──")
	RW.notice = ""
	RW.skip_play = true
	var jid := _new_job(MID_S, "a", true, 0, "claimed")
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH)
	_http.put(MID_S, _chunks, _meta, 3, false)
	var s0 := _snap()
	var la0 := _hit("referee_live_gauntlet")
	var e0: int = SW.own_enters
	var en0: int = RL.enters
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _asks_for(jid, "claimed") >= 2, 15000)
	_ok("S ★任务 claimed 也不问直播列表、不进跟播(查了 %d 次)" % _asks_for(jid, "claimed"), _asks_for(jid, "claimed") >= 2
		and _hit("referee_live_gauntlet") == la0 and SW.own_enters == e0 and RL.enters == en0 and _battle_now() == null)
	_job(jid)["status"] = "done"
	var run = m.get("_ref_run") if is_instance_valid(m) else null
	var sk := await _wait(func() -> bool: return run != null and is_instance_valid(run) and str(run.state) == RW.ST_SKIPPED, 10000)
	var s1 := _snap()
	_ok("S ★done ⇒ 旧路: 先记账(币 +%d、场次 +1、单子清掉)、不取录像不播(%s)" % [reward, RW.ST_SKIPPED], sk
		and int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["bt"]) == int(s0["bt"]) + 1 and _bill_job() == -1
		and SW.own_enters == e0 and _battle_now() == null, "%s → %s" % [str(s0), str(s1)])
	RW.skip_play = false
	await _leave()


# O ─────────────────────────────────────────────────────────────
func _t_o() -> void:
	print("── O 列表里找不到这一局就已算完 ⇒ 旧路 ──")
	RW.notice = ""
	_live_rows_on = false
	var jid := _new_job(MID_O, "a", true, 1, "claimed")
	var reward: int = int(P2C.GAUNTLET_COINS_PER_MATCH) + 1
	var s0 := _snap()
	var e0: int = SW.own_enters
	var l0: int = RL.lookups
	await _open_mmk()
	await _wait(func() -> bool: return RL.lookups >= l0 + 2, 15000)
	_ok("O 列表里没有这一局 ⇒ 每次查到 claimed 都再问一次种子, 不进跟播(问了 %d 次)" % (RL.lookups - l0),
		RL.lookups >= l0 + 2 and SW.own_enters == e0 and _battle_now() == null and _snap() == s0)
	_job(jid)["status"] = "done"
	await _wait(func() -> bool: return _bill_job() == -1, 10000)
	var s1 := _snap()
	_ok("O ★种子没拿到就已算完 ⇒ 旧路: 当场记账(币 +%d、场次 +1、战绩页 +1), 没进跟播" % reward,
		int(s1["coins"]) == int(s0["coins"]) + reward and int(s1["bt"]) == int(s0["bt"]) + 1 and int(s1["mh"]) == int(s0["mh"]) + 1
		and SW.own_enters == e0, "%s → %s" % [str(s0), str(s1)])
	_live_rows_on = true
	await _frames(10)
	await _leave()


# E ─────────────────────────────────────────────────────────────
## ★2026-10-29 用户「匹配成功，那里有个即将进入对局下面的进度条…你给它有含义啊…后面又写等待服务器开始对局，
##   那那段的时间为什么不能够融入这个进度条里面呢？」⇒ 一条进度条从配上走到对局第一帧(方案书 20261029c §4.7)。
##   量的是画出来的那一截(`EnterBar.fill_px` / `value`), 不是会话里的数。
func _ebar(m) -> EnterBar:
	if m == null or not is_instance_valid(m):
		return null
	var b = (m as Node).get("_ref_bar")
	return b if b != null and is_instance_valid(b) and not (b as Node).is_queued_for_deletion() else null


## VS 卡已翻、下面一行是「等待服务器开始对局」、进度条在显示。
func _e_vs_pending(m) -> bool:
	return _status_text(m) == RW.TXT_LIVE_PENDING and not bool(m.get("_searching")) and _ebar(m) != null and _ebar(m).visible


## 进了战斗场之后收尾: 任务失败 ⇒ 跟播那一侧销单、回主菜单。
func _e_close(jid: int) -> void:
	_job(jid)["status"] = "failed"
	await _wait(func() -> bool: return _menu_now() != null, 15000)
	await _wait(func() -> bool: return _run() == null, 8000)
	_gs.referee_pending = {}
	RW.notice = ""
	await _leave()


func _t_e() -> void:
	print("── E 进入对局进度条: pending 在走、走不满 → claimed 后按已到块数走 → 块够才进场、进场时条满、进去就开播 ──")
	RW.notice = ""
	var jid := _new_job(MID_E, "a", true, 0)
	_http.put(MID_E, _chunks, _meta, 0, false)
	var m: Node = await _open_mmk()
	var pend := await _wait(func() -> bool: return _e_vs_pending(m), 20000)
	_ok("分母 · E pending: VS 卡已翻、下面一行「%s」、下面有进度条在显示" % RW.TXT_LIVE_PENDING, pend, _status_text(m))
	if not pend:
		_job(jid)["status"] = "failed"
		_gs.referee_pending = {}
		await _leave()
		return
	var seq: PackedFloat32Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and _ebar(m) != null:
		seq.append(_ebar(m).value)
		await get_tree().process_frame
	var v0: float = seq[0] if not seq.is_empty() else -1.0
	var v1: float = seq[seq.size() - 1] if not seq.is_empty() else -1.0
	_ok("E ★pending 3 秒: 条在走(%.3f → %.3f)、碰不到下一段起点 0.55, 更没走满" % [v0, v1],
		seq.size() > 30 and v0 >= 0.2 and v1 > v0 + 0.02 and v1 < 0.55)
	_job(jid)["status"] = "claimed"
	var load_ok := await _wait(func() -> bool: return _status_text(m) == RW.TXT_ENTER_LOAD, 10000)
	_ok("E claimed ⇒ VS 卡下那一行改成「%s」" % RW.TXT_ENTER_LOAD, load_ok, _status_text(m))
	var r = _run()
	await _wait(func() -> bool: return r != null and str(r.get("_ep_stage")) == "buffer", 8000)
	var src_buf = r.get("_buf_src") if r != null else null
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1500 and _ebar(m) != null:
		seq.append(_ebar(m).value)
		await get_tree().process_frame
	var vb := _ebar(m).value if _ebar(m) != null else -1.0
	_ok("E ★拿到种子、块一块都没到 ⇒ 1.5 秒里还在 VS 卡上(不对着空场地)、条停在载入段起点附近(%.3f < 0.7)" % vb,
		src_buf is StreamSource.Http and _battle_now() == null and get_tree().current_scene == m and vb >= 0.55 and vb < 0.7)
	## 块一块一块到(每 0.3 秒一块), 逐帧记条与已到块数, 直到进场
	var served := 0
	var tn := Time.get_ticks_msec()
	var last_px := -1.0
	var got_before := -1
	var mid_seen := false
	while _battle_now() == null and Time.get_ticks_msec() - t1 < 20000:
		if Time.get_ticks_msec() - tn >= 300 and served < _chunks.size():
			tn = Time.get_ticks_msec()
			served += 1
			_http.put(MID_E, _chunks, _meta, served, false)
		var eb := _ebar(m)
		if eb != null and get_tree().current_scene == m:
			seq.append(eb.value)
			last_px = eb.fill_px()
			if eb.value > 0.7 and eb.value < 0.95:
				mid_seen = true
		if src_buf != null:
			got_before = int(src_buf.fetched())
		await get_tree().process_frame
	var b: Node = _battle_now()
	_ok("E ★块攒够开播那几块(%d)才进场(进场前已到 %d 块)" % [StreamPlayer.live_start_chunks(), got_before],
		b != null and got_before >= StreamPlayer.live_start_chunks())
	_ok("E ★块陆续到时条按块走(见过 0.7~0.95 之间的值), 进场前最后一帧条是满的(%.0f / %.0f 像素)" % [last_px, EnterBar.BAR_W],
		mid_seen and last_px >= EnterBar.BAR_W)
	var mono := true
	for i in range(1, seq.size()):
		if seq[i] < seq[i - 1] - 0.0001:
			mono = false
	_ok("E ★从 pending 到进场条只增不减(逐帧 %d 个采样)" % seq.size(), mono and seq.size() > 100)
	if b == null:
		_job(jid)["status"] = "failed"
		_gs.referee_pending = {}
		return
	var p: StreamPlayer = b._replay.player
	_ok("E ★播放器接着用 VS 卡上拉块的那一份来源(已到的块不重拉)", src_buf != null and p.src == src_buf)
	var fr := 0
	while fr < 30 and not (p.state == "playing" and str(b._dl_state) == "fight" and not (b._units as Array).is_empty()):
		fr += 1
		await get_tree().process_frame
	_ok("E ★进场就是开打(%d 帧内: 在播、战场状态 fight、场上 %d 个单位; 原来先对着空场地「同步中」再走 10 秒总览 + 预览)"
		% [fr, (b._units as Array).size()], fr <= 10 and p.state == "playing" and str(b._dl_state) == "fight"
		and not (b._units as Array).is_empty(), "%s / %s" % [p.state, str(b._dl_state)])
	_ok("E 开场那段是跳过去的、不是没有: 跳过时事件照放(开场之后才是第一路开打)、`opened` 立起", p.opened and p.applied > p.first_step + 300,
		"applied %d / first %d" % [p.applied, p.first_step])
	await _e_close(jid)


## E2: 拿到种子后块一直不来(直播服务器出问题)⇒ 不卡在 VS 卡上: 等到上限照原来进场(战斗场里「同步中」接着等)。
func _t_e2() -> void:
	print("── E2 块一直不来 ⇒ 等到上限(%.0f 秒)照原来进场 ──" % float(load(RUN_PATH).BUF_MAX_SEC))
	RW.notice = ""
	var jid := _new_job(MID_E2, "a", true, 0, "claimed")
	_http.put(MID_E2, _chunks, _meta, 0, false)
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _run() != null and str(_run().get("_ep_stage")) == "buffer", 20000)
	var r = _run()
	var t0 := Time.get_ticks_msec()
	_ok("分母 · E2 拿到种子、在 VS 卡上拉块", r != null and str(r.get("_ep_stage")) == "buffer")
	var cap_ms := int(float(load(RUN_PATH).BUF_MAX_SEC) * 1000.0)
	await _wait(func() -> bool: return _battle_now() != null, cap_ms - 1500)
	_ok("E2 上限之前一直留在 VS 卡上(不提前放弃)", _battle_now() == null and get_tree().current_scene == m)
	var got := await _wait(func() -> bool: return _battle_now() != null, 6000)
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	_ok("E2 ★等到上限就进场(%.1f 秒), 战斗场里接着「同步中」等块" % dt, got and dt <= float(load(RUN_PATH).BUF_MAX_SEC) + 2.5
		and _battle_now() != null and _battle_now()._replay.player.state != "playing")
	if got:
		await _e_close(jid)
	else:
		_job(jid)["status"] = "failed"
		_gs.referee_pending = {}


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 配上之后跟播自己这一局" if _fail == 0 and _n >= 50 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
