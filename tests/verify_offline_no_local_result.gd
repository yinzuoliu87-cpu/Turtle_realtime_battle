extends Node
## verify_offline_no_local_result.gd — 服务器裁判开着 + 断网 ⇒ 不产生本地战绩(方案书 docs/plans/20261019-服务器裁判.md 验收;
##   问题总表 B1「断网点开战 ⇒ 不出结果, 不再有本地成绩」)。
##
## 周六开关开着(存档里最后一次问到的那份; 这一次问不到), 从匹配屏真入口开战:
##   ① 请求当场失败(没网)        ⇒ 屏上「连接服务器后才能比赛」
##   ② 请求发出去一直没回(超时)  ⇒ 同一句(看门狗兜底, 不是一直转)
##   ③ 两种情况都: 不进战斗场、没有本地对局、战绩 / 币 / 场次 / 战绩页 / 待记账单一个都不动
##   ④ 分母: 同一套布置把网接上 ⇒ 真的交出去了(证明 ①② 不是因为根本没走到交阵容那一步)
## 每条判据都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「验收清单」那一行。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const ME := "11111111-2222-4333-8444-555555555555"

var _fail := 0
var _n := 0
var _gs
var _mode := "offline"            # offline = 当场失败 / hang = 不回 / online = 正常回
var _submits := 0
var _hung: Array = []             # 没回调的 cb(收尾时丢掉)


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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.promoted = true
	_gs.gauntlet_wins = 2
	_gs.gauntlet_losses = 1
	_gs.referee_pending = {}
	## 存档里最后一次问到的开关: 周六开(这一次问不到 —— 断网冷启动就是这个样子)
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true}
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600   # 令牌还新鲜(断网前登录过)
	SB.match_fetch_timeout_for_test = 1.5
	_ok("分母: 周六、闯关赛上线、开关(存档那份)开", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and P2C.phase_mode_live(P2C.PHASE_GAUNTLET) and RW.gauntlet_on())
	for md in ["offline", "hang"]:
		await _case(md)
	await _t_online_denominator()
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	SB.match_fetch_timeout_for_test = 0.0
	_gs.referee_flags = {}
	_gs.referee_pending = {}
	_finish()


func _transport(_m, u, _h, _b, cb) -> void:
	var url := str(u)
	if url.find("/rpc/referee_gauntlet_start") >= 0:
		_submits += 1
		if _mode == "online":
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"job_id\":5,\"match_id\":\"5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b\","
				+ "\"opp\":{\"profile\":{\"name\":\"kevin_99\",\"avatar\":\"ninja\",\"id\":\"g_x\",\"tag\":\"#ABCDEF\"},\"leaders\":[\"ninja\",\"dice\",\"pirate\"]}}"})
			return
	if _mode == "hang":
		_hung.append(cb)                # 发出去了, 一直没回
		return
	if _mode == "online":
		if url.find("/rpc/referee_flags") >= 0:
			cb.call({"ok": true, "code": 200, "body": "{\"finals_on\":false,\"gauntlet_on\":true}"})
		elif url.find("/rpc/") >= 0:
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":true,\"status\":\"pending\"}"})
		else:
			cb.call({"ok": true, "code": 200, "body": "[]"})
		return
	cb.call({"ok": false, "code": 0, "body": ""})


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "bw": int(_gs.battles_won), "stb": int(_gs.season_total_battles),
		"xp": int(_gs.season_xp), "mh": (_gs.match_history as Array).size(),
		"pending": (_gs.referee_pending as Dictionary).duplicate(), "rpid": str(_gs.replay_pending_id)}


func _status(m) -> String:
	var l := m.find_child("RefereeStatus", true, false) as Label if m != null and is_instance_valid(m) else null
	return l.text if l != null else ""


func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _case(md: String) -> void:
	print("── 断网(%s) ──" % ("请求当场失败" if md == "offline" else "请求一直没回"))
	_mode = md
	var s0 := _snap()
	var sub0 := _submits
	var battle_seen := false
	var m: Node = await _open_mmk()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and _status(m) != RW.TXT_NEED_SERVER:
		if get_tree().current_scene != null and get_tree().current_scene.get_script() == RB:
			battle_seen = true
		await get_tree().process_frame
	_ok("%s ★分母: 走到了交阵容那一步(真发了请求)" % md, _submits == sub0 + 1)
	_ok("%s ★屏上「%s」" % [md, RW.TXT_NEED_SERVER], _status(m) == RW.TXT_NEED_SERVER, _status(m))
	for _i in range(90):
		if get_tree().current_scene != null and get_tree().current_scene.get_script() == RB:
			battle_seen = true
		await get_tree().process_frame
	_ok("%s ★没进战斗场(没有本地对局)" % md, not battle_seen and get_tree().current_scene == m)
	var s1 := _snap()
	_ok("%s ★战绩 / 币 / 场次 / 经验 / 战绩页 / 待记账单一个都不动" % md, s1 == s0, "%s → %s" % [str(s0), str(s1)])
	m.queue_free()
	await _frames(3)
	_hung.clear()


func _t_online_denominator() -> void:
	print("── 分母: 同一套布置把网接上 ⇒ 交出去、落待记账单 ──")
	_mode = "online"
	var m: Node = await _open_mmk()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and _status(m) != RW.TXT_SETTLING:
		await get_tree().process_frame
	_ok("在线 ⇒ 屏上「%s」、单子落了(这条反过来证明上面不是没走到)" % RW.TXT_SETTLING, _status(m) == RW.TXT_SETTLING
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == 5, _status(m))
	m.queue_free()
	await _frames(3)
	_gs.referee_pending = {}


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 断网不出本地成绩" if _fail == 0 and _n >= 11 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
