extends Node
## verify_finals_watch_only.gd — 周日决赛「只看不打」门禁(方案书 docs/plans/20261019-服务器裁判.md 验收 / 20261018-周日只看不打.md)。
##
## 用户 10-18「在框那里点开始对局有啥意义，就是本地的，又不是服务器的」; 10-19「周六周日让服务器记」。
## 服务器裁判开关 `finals_on` 开着时: 对阵图点开自己那一场 = 看服务器算的那一局; 不在本机打、不调 finals_report。
## 开关关着时: 老路一字不变(照旧能打)。
##
## 段落(全部走产品自己的入口, 网络走注入传输, 不连网):
##   ① 纯函数: 开关回包(开 / 关 / 404 = 关 / 问不到 = 不动)、问到即落存档、断网冷启动读存档那份
##   ② 开关关: 自己那一场「开始对战」、点开 = 去要对手快照(老路)
##   ③ 开关开 + 购物窗内: 「观看」、点开只说「备战阶段」, 不要对手、不给轮次币
##   ④ 开关开 + 购物窗关: 点开(弹卡真按钮)⇒ 不要对手快照、不进本地对局、屏上「正在结算」、轮次币给一次(再点不重复)
##   ⑤ 揭晓(对阵图拿到这一场的结果)⇒ 自动取录像(服务器裁判算的那一份, RefereeRunner 真跑出来的)⇒ 进战斗场「播」不是「录」
##      ⇒ 放完: 不分叉、全程零 finals_report、没有补报单; 揭晓那半(胜场)按服务器的结果记
## 每条判据都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「验收清单」那一行。

const SB := preload("res://scripts/net/supabase.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const BRACKET := "res://scenes/BracketMap.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "7a1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"

var _fail := 0
var _n := 0
var _gs
var _now := 0
var _flags_body := ""            # 传输回的开关(空 = 404)
var _hits := {}                  # rpc 名 → 次数
var _bodies := {}                # rpc 名 → 最后一次请求体
var _rec_b64 := ""
var _a_won := false


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
	OS.set_environment("TURTLE_SEED", "")
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.finals_pending_reveal = {}
	_gs.finals_report_pending = {}
	_gs.referee_flags = {}
	## 一个周日晚上(服务器钟)
	_now = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 20 * 3600
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	await _t_flags()
	await _t_off()
	await _make_replay()
	await _t_on_shop()
	await _t_on_watch()
	_cleanup()
	_finish()


func _cleanup() -> void:
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	_gs.referee_flags = {}
	_gs.finals_pending_reveal = {}
	_gs.finals_report_pending = {}


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


func _transport(_m, u, _h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
		_bodies[rpc] = str(b)
	match rpc:
		"referee_flags":
			if _flags_body == "":
				cb.call({"ok": true, "code": 404, "body": "{\"code\":\"PGRST202\"}"})
			else:
				cb.call({"ok": true, "code": 200, "body": _flags_body})
			return
		"finals_replay":
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "match_id": MID, "replay": _rec_b64})})
			return
		"finals_report":
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"referee\"}"})
			return
		"finals_opponent":
			cb.call({"ok": true, "code": 200, "body": "{\"ok\":false,\"reason\":\"already_asked\",\"asked\":3}"})
			return
	cb.call({"ok": true, "code": 200, "body": "[]"})


# ① ─────────────────────────────────────────────────────────────
func _t_flags() -> void:
	print("── ① 开关: 回包 / 落盘 / 断网读存档 ──")
	var on := RN.parse_flags(true, 200, "{\"finals_on\":true,\"gauntlet_on\":false}")
	_ok("① 回包 → 周日开、周六关", bool(on.get(RN.K_FINALS, false)) and not bool(on.get(RN.K_GAUNTLET, true)))
	var nf := RN.parse_flags(true, 404, "")
	_ok("① ★404(服务端没部署这条函数)⇒ 明确是关, 不是「不知道」", nf.has(RN.K_FINALS) and not bool(nf[RN.K_FINALS]))
	_ok("① 问不到(断网 / 500 / 非 JSON)⇒ {}(不动上一次的)", RN.parse_flags(false, 0, "").is_empty()
		and RN.parse_flags(true, 500, "x").is_empty() and RN.parse_flags(true, 200, "nope").is_empty())
	_gs.referee_flags = {}
	_ok("① 分母: 存档里还没有开关 ⇒ 关", not RN.finals_on())
	_flags_body = "{\"finals_on\":true,\"gauntlet_on\":true}"
	var got := [false]
	var asks0 := RN.flag_asks
	RN.refresh_flags_async(func(_r: Dictionary) -> void: got[0] = true)
	for _i in range(240):
		if got[0]:
			break
		await get_tree().process_frame
	_ok("① ★真发了 referee_flags(走 SupabaseNet 出口)且回调了", got[0] and RN.flag_asks == asks0 + 1 and _hit("referee_flags") >= 1)
	_ok("① ★问到的开关落进存档 ⇒ 周日开", RN.finals_on() and bool((_gs.referee_flags as Dictionary).get(RN.K_FINALS, false)))
	## 断网冷启动: 问不到 ⇒ 存档那份还在
	var keep: Dictionary = (_gs.referee_flags as Dictionary).duplicate()
	RN.note_flags({})
	_ok("① 问不到不覆盖存档里那份", _gs.referee_flags == keep)
	RN.note_flags({RN.K_FINALS: false, RN.K_GAUNTLET: false})
	_ok("① 问到「关」⇒ 关", not RN.finals_on() and not RN.gauntlet_on())


# 对阵图 ─────────────────────────────────────────────────────────
## 4 人组, 我是 0 号, 第 1 轮已打完(我赢了), 当前第 2 轮(决赛)我对 1 号的胜者。
func _bucket(round_at: int, done: Dictionary, rnd: int = 2, closed: bool = false, revealed: int = 0) -> Dictionary:
	var ents: Array = []
	var nm := ["我自己", "乙", "丙", "丁"]
	for i in range(4):
		ents.append({"seed": i, "name": nm[i], "account_id": ME if i == 0 else "acct-x%d" % i})
	return SB.parse_finals(true, 200, JSON.stringify({"ok": true, "bucket": 0, "n": 4, "round": rnd, "closed": closed,
		"round_at": round_at, "revealed_at": revealed, "next_at": round_at + 480, "now": _now, "entrants": ents,
		"done": done}), ME, _now)


func _open_map(bk: Dictionary) -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	var m: Node = (load(BRACKET) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(3)
	m.set_data(bk, {}, _now)
	await _frames(4)
	return m


func _node_btn(m: Node, r: int, mm: int) -> Button:
	for c in m._canvas.find_children(BMS.N_NODE_BTN, "Button", true, false):
		if (c as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return c
	return null


func _popup_texts(m: Node) -> Array:
	var out: Array = []
	var p: Node = m.find_child("MatchPopup", true, false)
	if p != null:
		for c in p.find_children("*", "Label", true, false):
			out.append((c as Label).text)
		for c in p.find_children("*", "Button", true, false):
			out.append("[%s]" % (c as Button).text)
	return out


func _msg(m: Node) -> String:
	var l := m.find_child("ReplayMsg", true, false) as Label
	return l.text if l != null else ""


func _shop_closed() -> int:
	return _now - P2C.FINALS_SHOP_SEC - 10


# ② ─────────────────────────────────────────────────────────────
func _t_off() -> void:
	print("── ② 开关关: 老路(照旧能打) ──")
	## ★对阵图自己联网那条路会再问一次开关(`_pull`) ⇒ 服务端那边也得是关(不然它把存档改回开)。
	_flags_body = "{\"finals_on\":false,\"gauntlet_on\":false}"
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: false}
	var m: Node = await _open_map(_bucket(_shop_closed(), {"1-0": 0, "1-1": 1}))
	_ok("② 分母: 我那一组、第 2 轮、我在决赛那一格", int(m.cur().get("me", -1)) == 0 and m.is_my_match(2, 0))
	_ok("② ★开关关 ⇒ 照旧可以开打(问得出对手)", m.should_fetch_opponent(2, 0) and not m.referee_watch_open(2, 0))
	_node_btn(m, 2, 0).pressed.emit()
	await _frames(2)
	var pt := _popup_texts(m)
	_ok("② 弹卡「开始对战」", pt.has("[开始对战]"), str(pt))
	m._close_popup()
	SB._opp_inflight = false
	var opp0 := _hit("finals_opponent")
	m._on_match_opened(2, 0)
	for _i in range(120):
		if _hit("finals_opponent") > opp0:
			break
		await get_tree().process_frame
	_ok("② ★点开 = 去要对手快照(老路: 本机打)", _hit("finals_opponent") == opp0 + 1)
	m._await_match = Vector2i(-1, -1)
	SB.opponent_clear()


# 录像: 服务器裁判(RefereeRunner)真算一场 ────────────────────────────
func _make_replay() -> void:
	print("── 服务器裁判算一场(当作服务器写回的那一份) ──")
	_gs.reset_dual_lane()
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var a: Dictionary = RW.my_snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var b: Dictionary = Backend.make_bot(3, rng)
	var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": 9, "match_id": MID, "mode": "finals",
		"key": {"week": 1, "bucket": 0, "round": 2, "match": 0}, "seed": 2000023,
		"client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
	var res: Dictionary = await RefereeRunner.run(self, job)
	_rec_b64 = str(res.get("replay_b64", ""))
	_a_won = bool(res.get("a_won", false))
	_ok("分母: 裁判算完一场、有录像(%d 步)" % int(res.get("steps", 0)), bool(res.get("ok", false)) and _rec_b64.length() > 100,
		str(res.get("error", "")))


# ③ ─────────────────────────────────────────────────────────────
func _t_on_shop() -> void:
	print("── ③ 开关开 + 购物窗内 ──")
	_flags_body = "{\"finals_on\":true,\"gauntlet_on\":false}"
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: false}
	var m: Node = await _open_map(_bucket(_now - 10, {"1-0": 0, "1-1": 1}))
	_ok("③ ★开关开 ⇒ 不开打(should_fetch_opponent 恒假)、可以点开看", not m.should_fetch_opponent(2, 0)
		and m.referee_watch_open(2, 0) and m.can_open(2, 0))
	_node_btn(m, 2, 0).pressed.emit()
	await _frames(2)
	var pt := _popup_texts(m)
	_ok("③ ★弹卡: 横幅「本轮对战」、按钮「观看」、没有「开始对战」", pt.has("本轮对战") and pt.has("[观看]")
		and not pt.has("[开始对战]"), str(pt))
	m._close_popup()
	var coins0 := int(_gs.meta_deepsea_coins)
	var opp0 := _hit("finals_opponent")
	m._on_match_opened(2, 0)
	await _frames(3)
	_ok("③ ★购物窗内: 屏上「%s」, 不等结果、不给轮次币、不要对手" % RW.TXT_SHOP, _msg(m) == RW.TXT_SHOP
		and m.await_watch.x < 0 and int(_gs.meta_deepsea_coins) == coins0 and _hit("finals_opponent") == opp0
		and (_gs.finals_pending_reveal as Dictionary).is_empty(), _msg(m))


# ④⑤ ────────────────────────────────────────────────────────────
func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


func _t_on_watch() -> void:
	print("── ④ 开关开 + 购物窗关: 点开 = 看 ──")
	_gs.referee_flags = {RN.K_FINALS: true, RN.K_GAUNTLET: false}
	var m: Node = await _open_map(_bucket(_shop_closed(), {"1-0": 0, "1-1": 1}))
	_ok("④ 分母: 弹卡按钮的信号接着 _on_match_opened(对阵图自己接的, 走真按钮)", m.match_opened.is_connected(m._on_match_opened))
	var coins0 := int(_gs.meta_deepsea_coins)
	var tb0 := int(_gs.battles_total)
	var opp0 := _hit("finals_opponent")
	var rep0 := _hit("finals_report")
	_node_btn(m, 2, 0).pressed.emit()
	await _frames(2)
	var go := m.find_child(BMS.N_POPUP_GO, true, false) as Button
	_ok("④ 弹卡按钮「观看」", go != null and go.text == BMS.WATCH_LABEL)
	if go == null:
		return
	go.pressed.emit()
	await _frames(6)
	_ok("④ ★不要对手快照(不在本机打)", _hit("finals_opponent") == opp0)
	_ok("④ ★没有进本地对局(当前场景仍是对阵图)", get_tree().current_scene == m and not _is_battle(get_tree().current_scene))
	_ok("④ ★屏上「%s」, 在等这一场" % RW.TXT_SETTLING, _msg(m) == RW.TXT_SETTLING and m.await_watch == Vector2i(2, 0), _msg(m))
	_ok("④ ★轮次币 / 场次此刻就给(与胜负无关的那部分) +%d" % P2C.FINALS_COINS_PER_ROUND,
		int(_gs.meta_deepsea_coins) == coins0 + int(P2C.FINALS_COINS_PER_ROUND) and int(_gs.battles_total) == tb0 + 1,
		"%d → %d" % [coins0, int(_gs.meta_deepsea_coins)])
	var pr: Dictionary = _gs.finals_pending_reveal
	_ok("④ 待揭晓单 = 这一场(组 0 / 第 2 轮 / 第 0 场)", int(pr.get("round", -1)) == 2 and int(pr.get("match", -1)) == 0
		and int(pr.get("bucket", -1)) == 0, str(pr))
	m._on_match_opened(2, 0)
	await _frames(2)
	_ok("④ ★再点一次不重复给币", int(_gs.meta_deepsea_coins) == coins0 + int(P2C.FINALS_COINS_PER_ROUND))
	## 还没揭晓: 再喂一次同样的数据(= 轮询拿回来还是这一轮)⇒ 继续等, 不取录像
	var fr0 := _hit("finals_replay")
	m.set_data(_bucket(_shop_closed(), {"1-0": 0, "1-1": 1}), {}, _now)
	await _frames(3)
	_ok("④ 没揭晓 ⇒ 继续等、不取录像", m.await_watch == Vector2i(2, 0) and _hit("finals_replay") == fr0)

	print("── ⑤ 揭晓 ⇒ 自动播服务器那一份 ──")
	## 揭晓: 服务端到点翻面(决赛收盘), 结果按裁判写回的那一侧。翻面在很久之前 ⇒ 不在开播窗口里 ⇒ 直接是回放。
	var ws := 0 if _a_won else 1
	var sw0 := int(_gs.season_wins)
	m.set_data(_bucket(_shop_closed(), {"1-0": 0, "1-1": 1, "2-0": ws}, 2, true, _now - 3600), {}, _now)
	var b: Node = null
	for _i in range(300):
		if _is_battle(get_tree().current_scene):
			b = get_tree().current_scene
			break
		await get_tree().process_frame
	_ok("⑤ ★揭晓即取录像(finals_replay 第 2 轮第 0 场)", _hit("finals_replay") == fr0 + 1
		and str(_bodies.get("finals_replay", "")).find("\"p_round\":2") >= 0)
	_ok("⑤ ★进了战斗场, 是「播」不是「录」(不在本机打)", b != null and b._replay.is_playing() and str(b._replay.mode) == "play")
	_ok("⑤ 揭晓那半按服务器结果记(胜场 %s)" % ("+1" if _a_won else "不变"),
		int(_gs.season_wins) == sw0 + (1 if _a_won else 0) and (_gs.finals_pending_reveal as Dictionary).is_empty(),
		"%d → %d" % [sw0, int(_gs.season_wins)])
	if b == null:
		return
	b.set_process(false)
	var guard := 0
	while guard < 4000 and not b._replay.finished and b._replay.diverged_at < 0:
		b._process(0.13)
		guard += 1
		if guard % 6 == 0:
			await get_tree().process_frame
	_ok("⑤ ★放完: 不分叉、终局一致(录像是服务器那一份)", b._replay.finished and b._replay.diverged_at < 0,
		"%s %s" % [str(b._replay.finished), str(b._replay.diverge_why)])
	await _frames(4)
	_ok("⑤ ★全程零 finals_report、没有补报单(结果只由服务器写)", _hit("finals_report") == rep0
		and (_gs.finals_report_pending as Dictionary).is_empty(), "finals_report %d 次" % (_hit("finals_report") - rep0))
	b._hud._replay_exit()
	await _frames(6)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周日只看不打" if _fail == 0 and _n >= 31 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
