extends Node
## 内测服彩排台（不是门禁，2026-10-29）。方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §6「内测服彩排」。
## 两个真客户端连内测服（TURTLE_SERVER=beta），全程走产品入口：真匿名登录、真排队、真裁判机算局、真直播服务器出画面。
##   ROLE=home：进队 4 秒后按「←」回主页，在主页被「匹配成功」带进对局；ROLE=stay：一直停在排队屏。
##   每一阶段打墙钟秒数（配上 / VS 卡 / 进度条每段 / 进场 / 第一帧开打 / 播完 / 结算 / 回主菜单记账），最后一行 SUMMARY 是 JSON。
## 跑法（两个进程同时起，各自一个 user 目录 = 各自一个匿名号）：
##   TURTLE_SERVER=beta ROLE=home APPDATA=<目录A> XDG_DATA_HOME=<目录A> \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_rehearse_gauntlet_beta.tscn --quit-after 2000000
## 前提：内测服假时间在周六闯关时段（tools/beta_ops.py clock set "sat 10:00"）、referee_versions 有本机版本。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RUN := preload("res://scripts/systems/replay/referee_run.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const RB_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const FF_AFTER := 20.0            ## 开打后 1 倍看这么多秒，之后 FF 倍（只为缩短彩排；开头与结尾才是要量的）
const FF := 4.0

var _gs
var _role := "stay"
var _t0 := 0
var _sum := {}
var _last_cap := ""
var _bar_max := -1.0
var _bar_back := 0


func _w() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _log(s: String) -> void:
	print("[REH %s] %7.2fs %s" % [_role, _w(), s])


func _until(pred: Callable, max_s: float) -> bool:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(max_s * 1000.0):
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _sec(s: float) -> void:
	await _until(func() -> bool: return false, s)


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


func _fail(why: String) -> void:
	_log("REH FAIL: " + why)
	_sum["fail"] = why
	print("SUMMARY " + JSON.stringify(_sum))
	get_tree().quit(1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_role = OS.get_environment("ROLE") if OS.get_environment("ROLE") != "" else "stay"
	_t0 = Time.get_ticks_msec()
	_sum = {"role": _role}
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_gs.tutorial_active = false
	StudioIntro.played = true
	_log("内测服? %s · 版本 %s" % [str(load("res://scripts/net/server_env.gd").is_beta()), ReplayRecorder.client_version()])
	SB.ensure_signed_in_async()
	if not await _until(func() -> bool: return str(_gs.account_id) != "", 30.0):
		_fail("匿名登录 30 秒没拿到账号")
		return
	_sum["account"] = str(_gs.account_id)
	SB.fetch_status_async()
	RN.refresh_flags_async()
	if not await _until(func() -> bool: return P2C.beta_clock_heard, 20.0):
		_fail("20 秒没拿到内测服假时间")
		return
	if not await _until(func() -> bool: return RW.gauntlet_on() and RN.stream_on(), 20.0):
		_fail("20 秒没拿到开关（闯关 %s / 直播 %s）" % [str(RW.gauntlet_on()), str(RN.stream_on())])
		return
	await _sec(1.0)
	var now := int(P2C.now_utc())
	_log("登录 %s · 假时间 %s · 阶段 %s · 开关 %s" % [str(_gs.account_id).substr(0, 8), Time.get_datetime_string_from_unix_time(now),
		str(P2C.phase_at_utc(now)), JSON.stringify(_gs.referee_flags)])
	if P2C.phase_at_utc(now) != P2C.PHASE_GAUNTLET:
		_fail("假时间不在闯关时段")
		return
	_setup_gs(now)
	await _flow()


func _setup_gs(now: int) -> void:
	_gs.ensure_season()
	_gs.nickname = "Reh" + _role.capitalize()
	_gs.onboarded = true
	_gs.week_anchor_ts = P2C.week_anchor_utc(now)
	_gs.week_phase = P2C.phase_at_utc(now)
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"] if _role == "home" else ["ninja", "dice", "pirate"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": _gs.season_leaders[0], "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": _gs.season_leaders[1], "equips": []},
			{"kind": "leader", "slot": 2, "id": _gs.season_leaders[2], "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	_gs.persistent_equipped = {}
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 0
	_gs.gauntlet_losses = 0
	_gs.battles_total = 9
	_gs.season_total_battles = 9
	_gs.referee_pending = {}
	_gs.dual_active = true
	_gs.close_card_ranked_wk = int(_gs.week_anchor_ts)
	_gs.close_card_gauntlet_wk = int(_gs.week_anchor_ts)
	_gs.save()
	_sum["gw0"] = 0
	_sum["gl0"] = 0
	_sum["coins0"] = int(_gs.meta_deepsea_coins)


func _flow() -> void:
	## 留在排队屏的那个晚 START_DELAY 秒进队（默认 15）：让回主页的那个先排上、先回到主页，配上发生在它人在主页的时候
	##   （第一轮两个同时进队 ⇒ 第二个一进队就配上、根本没出排队界面；第一个按「←」那一刻其实已配上 ⇒ 走了「稍后记入」那条）。
	if _role == "stay":
		var d := float(OS.get_environment("START_DELAY")) if OS.get_environment("START_DELAY").is_valid_float() else 15.0
		await _sec(d)
	var old := _scene()
	var mm: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	get_tree().current_scene = mm
	if old != null and old != self:
		old.queue_free()
	if not await _until(func() -> bool: return _queued_or_paired(mm), 30.0):
		var r = RUN.active
		_fail("30 秒没进排队（会话 %s / %s）" % [str(r.state) if r != null else "-", str(r.msg) if r != null else "-"])
		return
	_sum["t_queue"] = _w()
	_log("① 进队，排队中")
	if _role == "home":
		await _sec(4.0)
		var back: Button = mm.get("_cancel_btn")
		back.pressed.emit()
		if not await _until(func() -> bool: return _scene() != null and _scene().get_script() == MENU, 10.0):
			_fail("按「←」10 秒没回到主页")
			return
		_sum["t_home"] = _w()
		_log("② 回到主页，排队继续（会话 %s）" % str(RUN.active.state if RUN.active != null else "-"))
	## 等配上：回主页的那一个看遮罩出现；留在排队屏的看会话出了排队状态
	if not await _until(func() -> bool: return _found_seen(), 240.0):
		_fail("240 秒没配上")
		return
	_sum["t_found"] = _w()
	_log("③ 配上（%s）" % ("遮罩「匹配成功」" if _role == "home" else "排队屏翻 VS 卡"))
	await _watch_until_live()
	if _sum.has("fail"):
		return
	await _watch_live()


## 进了队：排队界面出来了，或者一进队就配上了（会话已出排队状态）。
func _queued_or_paired(mm: Node) -> bool:
	if is_instance_valid(mm) and mm.find_child("QueueBox", true, false) != null:
		return true
	var r = RUN.active
	return r != null and is_instance_valid(r) and str(r.state) != "" and str(r.state) != RW.ST_SUBMIT and not RW.in_queue(str(r.state))


func _found_seen() -> bool:
	if get_tree().root.get_node_or_null(QueueFoundOverlay.NODE) != null:
		return true
	var r = RUN.active
	return r != null and is_instance_valid(r) and not RW.in_queue(str(r.state))


## 配上 → 进场：逐帧记进度条（遮罩里 / VS 卡下）与阶段那句话；只增不减量的是画出来的值。
func _watch_until_live() -> void:
	var t_end := Time.get_ticks_msec() + 180000
	var last_log := -1.0
	var buf_seen := -1
	while Time.get_ticks_msec() < t_end:
		var cs := _scene()
		if _is_battle(cs) and cs.get("_replay") != null and cs._replay.player != null:
			_sum["t_live"] = _w()
			_sum["chunks_at_enter"] = buf_seen
			_log("⑥ 进场（VS 卡上已拉 %d 块）· 进度条最大 %.3f · 往回退 %d 次" % [buf_seen, _bar_max, _bar_back])
			return
		var bar: EnterBar = null
		var ov := get_tree().root.get_node_or_null(QueueFoundOverlay.NODE)
		if ov != null:
			bar = ov.find_child("Bar", true, false) as EnterBar
		elif cs != null and cs.get("_ref_bar") != null and is_instance_valid(cs.get("_ref_bar")):
			bar = cs.get("_ref_bar")
		var r = RUN.active
		var cap := ""
		if r != null and is_instance_valid(r):
			cap = str(r.enter_caption())
			if r.get("_buf_src") != null:
				buf_seen = int(r._buf_src.fetched())
		if bar != null and bar.visible:
			if bar.value < _bar_max - 0.0001:
				_bar_back += 1
			_bar_max = maxf(_bar_max, bar.value)
		if cap != _last_cap:
			_last_cap = cap
			_sum["t_cap_" + cap] = _w()
			_log("   阶段「%s」· 条 %.3f · 会话 %s" % [cap, bar.value if bar != null else -1.0, str(r.state) if r != null else "-"])
		if _w() - last_log >= 1.0 and bar != null:
			last_log = _w()
			_log("   条 %.3f（%s）· 块 %d" % [bar.value, "遮罩" if ov != null else "VS 卡", buf_seen])
		if r == null and not _is_battle(cs):
			_fail("会话没了还没进场（场景 %s）" % str(cs.scene_file_path if cs != null else "-"))
			return
		if r != null and (str(r.state) == RW.ST_ERROR or str(r.state) == RW.ST_LATER):
			_fail("会话 %s：%s" % [str(r.state), str(r.msg)])
			return
		await get_tree().process_frame
	_fail("配上之后 180 秒没进场")


func _watch_live() -> void:
	var bt := _scene()
	var p: StreamPlayer = bt._replay.player
	if not await _until(func() -> bool: return not is_instance_valid(bt) or (p.state == "playing" and str(bt._dl_state) == "fight"
			and not (bt._units as Array).is_empty()), 30.0):
		_fail("进场 30 秒没开打（%s / %s）" % [p.state, str(bt._dl_state) if is_instance_valid(bt) else "-"])
		return
	_sum["t_fight"] = _w()
	_log("⑦ 第一帧开打（进场后 %.2f 秒）" % (_w() - float(_sum["t_live"])))
	var sped := false
	var stalls := 0
	var was_stall := false
	while is_instance_valid(bt) and p.state != "ended" and p.state != "error" and _w() < 900.0:
		if not sped and _w() - float(_sum["t_fight"]) >= FF_AFTER:
			sped = true
			p.speed = FF
			_log("   之后 %.0f 倍（彩排缩时）" % FF)
		if p.state == "stalled" and not was_stall:
			stalls += 1
		was_stall = p.state == "stalled"
		await get_tree().process_frame
	_sum["stalls"] = stalls
	if not is_instance_valid(bt) or p.state != "ended":
		_fail("流没播完（%s）" % (p.state if is_instance_valid(bt) else "离场"))
		return
	_sum["t_ended"] = _w()
	_log("⑧ 流播完（追上服务器停下 %d 次）" % stalls)
	var settled := await _until(func() -> bool: return _press_text(_scene(), "返回主菜单"), 150.0)
	_sum["t_settle"] = _w()
	var res: Dictionary = (SW.current.get("result", {}) as Dictionary) if not SW.current.is_empty() else {}
	_log("⑨ 结算屏%s · 服务器结果 %s" % ["（按了返回主菜单）" if settled else "（150 秒没等到）", JSON.stringify(res)])
	if not await _until(func() -> bool: return _scene() != null and _scene().get_script() == MENU, 20.0):
		_fail("结算后 20 秒没回主菜单")
		return
	await _sec(3.0)
	_sum["gw1"] = int(_gs.gauntlet_wins)
	_sum["gl1"] = int(_gs.gauntlet_losses)
	_sum["coins1"] = int(_gs.meta_deepsea_coins)
	_sum["pending_after"] = JSON.stringify(_gs.referee_pending)
	_log("⑩ 回主菜单记账：闯关 %d 胜 %d 负 · 深海币 %d → %d · 待记账单 %s" % [_sum["gw1"], _sum["gl1"], _sum["coins0"], _sum["coins1"],
		_sum["pending_after"]])
	print("SUMMARY " + JSON.stringify(_sum))
	get_tree().quit(0)
