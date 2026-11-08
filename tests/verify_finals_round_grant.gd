extends Node
## verify_finals_round_grant.gd — 周日轮次奖励「结果到手就发」(用户 2026-11-08「冠军杯赛和小组赛都有 bug，整个深海币和经验压根是没给啊」)。
##
## 修前(0.22.9 / 6d34ea63): 只有「点开自己那一场、且那一刻还没出结果」(RefereeWatch.finals_seal)才发 8 币 + 2 经验 + 1 场;
##   正式服 11-08 第 4 组 购物窗 18:03 关、18:06 出结果(第 2 轮只有约 1 分钟)⇒ 测试号赛季 21 场里周日 0 场。
## 判据全量存档里的结果(深海币 / 赛季经验 / 赛季场数 / 胜场 / 已发清单), 走产品真入口
##   `BracketMapScene.record_progress_from` / `record_cup_from`(对阵图轮询与主菜单拉一次都调它们):
##   ① 我那一场出了结果、从没点开 ⇒ 喂一次数据就发: +8 币 +2 经验 +1 场; 我赢了 ⇒ 胜场 +1
##   ② 同一份数据再喂 3 次 ⇒ 一分不多(幂等)
##   ③ 第 2 轮出结果 ⇒ 再发一次(按场)
##   ④ 先点开(那一刻还没结果)、后出结果 ⇒ 对称那部分只发一次、胜负只揭晓一次
##   ⑤ 先出结果(已发)、后点开 ⇒ finals_seal 不再发、不挂待揭晓单
##   ⑥ 旧存档: 点开过、挂着待揭晓单、已发清单里没有这一场 ⇒ 不重发, 只揭晓一次
##   ⑦ 不是我的场 / 纯观众 / 服务器裁判开关关着 ⇒ 不发
##   ⑧ 冠军杯赛那一张同样发(组号不同: 与小组赛同坐标的场不冲突)
##   ⑨ 已发清单进存档(序列化读回还在)、换周清掉
##   ⑩ 真对阵图(set_data → _record_progress)喂到我那一场的结果 ⇒ 屏上当场「本轮奖励：深海币 +8　经验 +2」、币真到账
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_finals_round_grant.tscn

const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const SB := preload("res://scripts/net/supabase.gd")
const B := preload("res://scripts/gamedata/bracket.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const ME := "11111111-2222-3333-4444-555555555555"
const BK := 4                       # 我那一组的组号
const N := 4                        # 4 人组
const SEED_ME := 1                  # 我是 1 号种子

var _gs = null
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _transport(_m, u, _h, _b, cb) -> void:
	if str(u).find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"access_token": "tok", "refresh_token": "r", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


## 存档里要量的那几项。
func _snap() -> Dictionary:
	return {"coins": int(_gs.meta_deepsea_coins), "xp": int(_gs.season_xp), "stb": int(_gs.season_total_battles),
		"wins": int(_gs.season_wins), "granted": (_gs.finals_granted as Array).size()}


func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := {}
	for k in a:
		d[k] = int(b[k]) - int(a[k])
	return d


func _fresh() -> void:
	_gs.finals_granted = []
	_gs.finals_pending_reveal = {}
	_gs.finals_coins_pending = []
	_gs.hearts = 3
	_gs.season_level = P2C.MAX_LEVEL     # 满级: 经验只累加不进位, 差值就是发了多少
	_gs.season_xp = 0
	_gs.referee_flags = {RN.K_FINALS: true}


## 我在第 r 轮的那一场(用已有结果推): 返回 [m, 我的侧]; 找不到 ⇒ [-1, -1]。
func _my_match(r: int, done: Dictionary, me: int = SEED_ME, n: int = N) -> Array:
	for m in range(B.matches_in_round(n, r)):
		var s := B.my_side_in(me, r, m, n, done)
		if s >= 0:
			return [m, s]
	return [-1, -1]


func _bucket(done: Dictionary, me: int = SEED_ME, bk: int = BK) -> Dictionary:
	return {"size": N, "me": me, "bucket": bk, "round": 1, "done": done.duplicate(true)}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_done()
		return
	print("=== 周日轮次奖励: 结果到手就发 ===")
	_gs.test_mode = true
	_gs.account_id = ME
	OS.set_environment(SB.ENV_URL, "http://grant.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "grant-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	_fresh()
	_ok("★分母: 服务器裁判开关开着(产品判据 RN.finals_on)", RN.finals_on())

	## ① 第 1 轮出结果、从没点开: 我赢
	var r1: Array = _my_match(1, {})
	_ok("★分母: 1 号种子第 1 轮有一场", int(r1[0]) >= 0, "第 1 轮第 %d 场 · 我在 %d 侧" % [int(r1[0]), int(r1[1])])
	var done1 := {"1-%d" % int(r1[0]): int(r1[1]), "1-%d" % (1 - int(r1[0])): 0}
	var s0 := _snap()
	BMS.record_progress_from(_bucket(done1), -1)
	var d1 := _diff(s0, _snap())
	_ok("★★① 第 1 轮出结果、从没点开 ⇒ +%d 币 +%d 经验 +1 场、胜场 +1" % [P2C.FINALS_COINS_PER_ROUND, P2C.FINALS_XP_PER_ROUND],
		d1["coins"] == P2C.FINALS_COINS_PER_ROUND and d1["xp"] == P2C.FINALS_XP_PER_ROUND and d1["stb"] == 1 and d1["wins"] == 1 and d1["granted"] == 1, str(d1))

	## ② 同一份数据再喂 3 次
	var s1 := _snap()
	for _i in range(3):
		BMS.record_progress_from(_bucket(done1), -1)
	_ok("★★② 同一份数据再喂 3 次 ⇒ 一分不多", _diff(s1, _snap()).values().all(func(v): return int(v) == 0), str(_diff(s1, _snap())))

	## ③ 第 2 轮出结果: 我输
	var r2: Array = _my_match(2, done1)
	var done2 := done1.duplicate()
	done2["2-%d" % int(r2[0])] = 1 - int(r2[1])
	var s2 := _snap()
	BMS.record_progress_from(_bucket(done2), -1)
	var d2 := _diff(s2, _snap())
	_ok("★★③ 第 2 轮出结果(我输) ⇒ 再 +%d 币 +%d 经验 +1 场、胜场不变" % [P2C.FINALS_COINS_PER_ROUND, P2C.FINALS_XP_PER_ROUND],
		int(r2[0]) >= 0 and d2["coins"] == P2C.FINALS_COINS_PER_ROUND and d2["xp"] == P2C.FINALS_XP_PER_ROUND and d2["stb"] == 1 and d2["wins"] == 0, str(d2))

	## ④ 先点开(那一刻还没结果)、后出结果
	_fresh()
	var s3 := _snap()
	var sealed: bool = RW.finals_seal(_gs, BK, 1, int(r1[0]), -1)
	var d3a := _diff(s3, _snap())
	BMS.record_progress_from(_bucket(done1), -1)
	var d3 := _diff(s3, _snap())
	_ok("★★④ 先点开后出结果 ⇒ 点开时发一次, 出结果只揭晓不重发(合计 +%d 币 / +1 场 / 胜场 +1)" % P2C.FINALS_COINS_PER_ROUND,
		sealed and d3a["coins"] == P2C.FINALS_COINS_PER_ROUND and d3["coins"] == P2C.FINALS_COINS_PER_ROUND and d3["stb"] == 1 and d3["wins"] == 1
		and (_gs.finals_pending_reveal as Dictionary).is_empty(), "点开后 %s · 出结果后 %s" % [str(d3a), str(d3)])

	## ⑤ 先出结果(已发)、后点开
	_fresh()
	BMS.record_progress_from(_bucket(done1), -1)
	var s4 := _snap()
	var sealed2: bool = RW.finals_seal(_gs, BK, 1, int(r1[0]), -1)
	BMS.record_progress_from(_bucket(done1), -1)
	_ok("★★⑤ 先出结果后点开 ⇒ finals_seal 不再发、不挂待揭晓单、胜负不再揭晓",
		not sealed2 and _diff(s4, _snap()).values().all(func(v): return int(v) == 0) and (_gs.finals_pending_reveal as Dictionary).is_empty(),
		"seal=%s %s" % [str(sealed2), str(_diff(s4, _snap()))])

	## ⑥ 旧存档: 挂着待揭晓单、已发清单里没有
	_fresh()
	_gs.finals_pending_reveal = {"round": 1, "match": int(r1[0]), "bucket": BK}
	var s5 := _snap()
	BMS.record_progress_from(_bucket(done1), -1)
	var d5 := _diff(s5, _snap())
	_ok("★★⑥ 旧存档挂着待揭晓单(已发清单里没有) ⇒ 不重发对称那部分、胜负只揭晓一次",
		d5["coins"] == 0 and d5["stb"] == 0 and d5["wins"] == 1 and (_gs.finals_pending_reveal as Dictionary).is_empty(), str(d5))

	## ⑦ 不是我的场 / 纯观众 / 开关关
	_fresh()
	var other := {"1-%d" % (1 - int(r1[0])): 0}
	var s6 := _snap()
	BMS.record_progress_from(_bucket(other), -1)
	_ok("★⑦ 只出了别人那一场的结果 ⇒ 不发", _diff(s6, _snap()).values().all(func(v): return int(v) == 0), str(_diff(s6, _snap())))
	BMS.record_progress_from(_bucket(done1, -1), -1)
	_ok("★⑦ 纯观众(me = -1) ⇒ 不发", _diff(s6, _snap()).values().all(func(v): return int(v) == 0), str(_diff(s6, _snap())))
	_gs.referee_flags = {RN.K_FINALS: false}
	BMS.record_progress_from(_bucket(done1), -1)
	_ok("★⑦ 服务器裁判开关关着(周日本机打, 打完那一刻已发) ⇒ 这里不发", _diff(s6, _snap()).values().all(func(v): return int(v) == 0), str(_diff(s6, _snap())))

	## ⑧ 冠军杯赛
	_fresh()
	BMS.record_progress_from(_bucket(done1), -1)
	var s7 := _snap()
	var cup := {"size": N, "me": SEED_ME, "bucket": int(P2C.FINALS_CUP_BUCKET), "round": 1, "done": done1.duplicate(true)}
	BMS.record_cup_from(cup, -1)
	var d7 := _diff(s7, _snap())
	_ok("★★⑧ 冠军杯赛同坐标那一场出结果 ⇒ 另发一次(组号不同, 不被小组赛那场挡住)",
		d7["coins"] == P2C.FINALS_COINS_PER_ROUND and d7["stb"] == 1 and d7["granted"] == 1, str(d7))

	## ⑩ 真对阵图: 喂一份「我那一场已出结果」⇒ 屏上当场说「本轮奖励」(用户「你每轮每轮就应该发呀」), 币真到账
	_fresh()
	var now := P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 20 * 3600
	var mine0: Array = _my_match(1, {}, 0)
	var ents: Array = []
	for i in range(N):
		ents.append({"seed": i, "name": "选手%d" % i, "account_id": ME if i == 0 else "acct-x%d" % i})
	var lv: Dictionary = SB.parse_finals(true, 200, JSON.stringify({"ok": true, "bucket": BK, "n": N, "round": 2, "closed": false,
		"round_at": now - 600, "revealed_at": 0, "next_at": now + 480, "now": now, "entrants": ents,
		"done": {"1-%d" % int(mine0[0]): int(mine0[1]), "1-%d" % (1 - int(mine0[0])): 0}}), ME, now)
	var m: Node = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(m)
	for _i in range(3):
		await get_tree().process_frame
	var s9 := _snap()
	m.set_data(lv, {}, now)
	for _i in range(3):
		await get_tree().process_frame
	var lb := m.find_child("ReplayMsg", true, false) as Label
	var want: String = RW.TXT_ROUND_REWARD % [P2C.FINALS_COINS_PER_ROUND, P2C.FINALS_XP_PER_ROUND]
	var d9 := _diff(s9, _snap())
	_ok("★★⑩ 真对阵图喂到我那一场的结果 ⇒ 屏上「%s」、币 +%d" % [want, P2C.FINALS_COINS_PER_ROUND],
		lb != null and lb.text == want and d9["coins"] == P2C.FINALS_COINS_PER_ROUND and d9["granted"] == 1,
		"屏上「%s」 %s" % [lb.text if lb != null else "(没有提示)", str(d9)])
	m.queue_free()
	await get_tree().process_frame

	## ⑨ 存档与换周
	var dict: Dictionary = _gs._save_dict()
	var keep: Array = (_gs.finals_granted as Array).duplicate()
	_gs.finals_granted = []
	_gs._apply_save_dict(dict)
	_ok("★⑨ 已发清单进存档(序列化读回还在)", (_gs.finals_granted as Array) == keep and keep.size() == 1, str(_gs.finals_granted))
	_gs.start_new_season()
	_ok("★⑨ 换周清掉", (_gs.finals_granted as Array).is_empty(), str(_gs.finals_granted))

	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	_gs.referee_flags = {}
	_done()


func _done() -> void:
	if _n < 15:
		print("  [FAIL] ★分母: 断言只有 %d 条(<15) —— 有用例没跑到" % _n)
		_fail += 1
	print("—— %d 项, %d 失败 ——" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
