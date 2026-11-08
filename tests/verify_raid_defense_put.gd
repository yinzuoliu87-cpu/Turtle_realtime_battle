extends Node
## verify_raid_defense_put.gd —— 偷袭防守阵容上传(2026-11-08 · 方案书 20261107 §4.2 · 契约 §3 `raid_defense_put`)
##
## ① 离开背包页(真场景 Inventory.tscn 出树)⇒ POST rpc/raid_defense_put, 正文恰好三个参数:
##    p_week = 当前周锚点 / p_snapshot = build_ghost_snapshot 的产物(统领、分路、装备)/ p_device = OS.get_unique_id()
## ② 阵容没变 ⇒ 再进再出背包一个请求都不发; 阵容变了(卸一件装备)⇒ 再传一次
## ③ 离开选龟页(真场景 TeamSelect.tscn 出树)⇒ 阵容变了才传
## ④ 每打完一局(`Backend.upload_ghost`, 积分赛结算的真入口)⇒ 顺手传一次
## ⑤ 本周没开轮(统领不满 3 只 / 本机赛季是上一周)⇒ 不传; 教程沙盒 / test_mode(门禁闸没开)⇒ 不传; 没配后端 ⇒ 不传
## ⑥ 失败(连不上 / 服务器回 ok:false)静默, 不记成已传 ⇒ 下次离开背包再传; 传成之后不再传
##
## 跑法: bash godot-quiet.sh res://tests/verify_raid_defense_put.tscn --quit-after 500

const SB := preload("res://scripts/net/supabase.gd")
const RD := preload("res://scripts/net/raid_defense_net.gd")
const ML := preload("res://scripts/net/mainsite_link.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SETUP := preload("res://tests/_setup_appstore.gd")
const Backend := preload("res://scripts/net/backend.gd")
const INV := "res://scenes/Inventory.tscn"
const TS := "res://scenes/TeamSelect.tscn"
const ACC := "5e1c9a7b-3f20-4d8e-9a61-2b7c4f0d8e13"
const NEED := 29

var _n := 0
var _fail := 0
var _reqs: Array = []
var _reply := {"ok": true, "code": 200, "body": "{\"ok\": true, \"has_defense\": true}"}


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _transport(m: String, u: String, h: PackedStringArray, b: String, cb: Callable) -> void:
	_reqs.append({"m": m, "u": u, "h": h, "b": b})
	if u.ends_with("/rest/v1/rpc/" + RD.RPC):
		cb.call(_reply)
		return
	cb.call({"ok": false, "code": 0, "body": ""})


func _puts() -> Array:
	var out: Array = []
	for r in _reqs:
		if str(r["u"]).ends_with("/rest/v1/rpc/" + RD.RPC):
			out.append(r)
	return out


## 最后一次上传(一次都没有 ⇒ {}; 不越界, 断言照常判红而不是中止)。
func _last_put() -> Dictionary:
	var ps := _puts()
	return ps[ps.size() - 1] if not ps.is_empty() else {}


func _body(r: Dictionary) -> Dictionary:
	var j := JSON.new()
	if j.parse(str(r.get("b", ""))) == OK and j.data is Dictionary:
		return j.data
	return {}


## 进一次背包再出来(真场景出树 ⇒ `_exit_tree`)。
func _visit(path: String) -> void:
	var sc: Node = (load(path) as PackedScene).instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await _frames(4)
	sc.queue_free()
	await _frames(4)


func _wk() -> int:
	return P2.week_anchor_utc(int(P2.now_utc()))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 偷袭防守阵容上传 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("分母: GameState", false)
		_finish()
		return
	SETUP.run()                     # 打了一周的号: 3 统领 + 装备 + 小将(强制 test_mode)
	gs.week_anchor_ts = _wk()
	gs.tutorial_active = false
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	ProjectSettings.set_setting(SB.SETTING_KEY, "test-key")
	SB._reset_auth_for_test()
	SB._token = "probe-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = _transport
	RD._reset_for_test()
	RD.force_in_test = true
	_ok("分母: 后端配上了、本周已开轮(3 统领 + 本周锚点)", SB.enabled() and RD.week_open(gs.season_leaders, int(gs.week_anchor_ts), _wk()))

	## ① 离开背包
	await _visit(INV)
	var ps := _puts()
	_ok("① ★离开背包 ⇒ 传了 1 次 raid_defense_put", ps.size() == 1, str(ps.size()))
	var b := _body(ps[0]) if ps.size() >= 1 else {}
	var snap: Dictionary = b.get("p_snapshot", {}) if b.get("p_snapshot") is Dictionary else {}
	_ok("① POST、带本人令牌", ps.size() >= 1 and str(ps[0]["m"]) == "POST" and "Authorization: Bearer probe-token" in Array(ps[0]["h"]))
	_ok("① 正文恰好三个参数 p_week / p_snapshot / p_device", b.keys().size() == 3 and b.has("p_week") and b.has("p_snapshot") and b.has("p_device"), str(b.keys()))
	_ok("① ★p_week = 当前周锚点", int(b.get("p_week", -1)) == _wk(), "%s vs %d" % [b.get("p_week"), _wk()])
	_ok("① ★p_device = OS.get_unique_id()(非空)", str(b.get("p_device", "?")) == OS.get_unique_id().left(128)
		and str(b.get("p_device", "")) != "", "长 %d" % str(b.get("p_device", "")).length())
	_ok("① ★p_snapshot 就是 build_ghost_snapshot 的产物(与此刻 my_snapshot 逐字相同)",
		JSON.stringify(snap, "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(FN.my_snapshot())), "", true))
	_ok("① 快照带着本周的统领 / 分路 / 装备", snap.get("leaders", []) == SETUP.LEADERS and (snap.get("lane_assign", {}) as Dictionary).has("top")
		and (snap.get("equipped", {}) as Dictionary).has("two_head"), str(snap.get("leaders")))

	## ② 没变不传 / 变了再传
	await _visit(INV)
	_ok("② ★阵容没变 ⇒ 再进再出背包一个请求都不发", _puts().size() == 1, str(_puts().size()))
	(gs.persistent_equipped["two_head"] as Array).pop_back()
	await _visit(INV)
	_ok("② ★阵容变了(卸一件装备) ⇒ 再传一次", _puts().size() == 2, str(_puts().size()))
	var eq2: Dictionary = (_body(_last_put()).get("p_snapshot", {}) as Dictionary).get("equipped", {})
	_ok("② 传上去的是变了之后的那份", (eq2.get("two_head", []) as Array).size() == 2, str(eq2.get("two_head")))

	## ③ 离开选龟页
	var n3 := _puts().size()
	await _visit(TS)
	_ok("③ 离开选龟页, 阵容没变 ⇒ 不传", _puts().size() == n3, str(_puts().size() - n3))
	gs.loadouts["phoenix"] = 2
	await _visit(TS)
	_ok("③ ★离开选龟页, 阵容变了(换技能) ⇒ 传", _puts().size() == n3 + 1, str(_puts().size() - n3))

	## ④ 每打完一局(积分赛结算的真入口)
	var n4 := _puts().size()
	gs.season_total_battles += 1
	var gid: String = Backend.player_ghost_id(int(gs.season_id), gs.season_leaders, int(gs.season_total_battles))
	Backend.upload_ghost(Backend.build_ghost_snapshot(gid, {"name": "门禁", "avatar": "two_head", "id": gid}))
	await _frames(6)
	_ok("④ ★每打完一局(Backend.upload_ghost)⇒ 顺手传一次", _puts().size() == n4 + 1, str(_puts().size() - n4))
	_ok("④ 传的是打完这一局之后的阵容(场次已 +1)", int((_body(_last_put()).get("p_snapshot", {}) as Dictionary).get("season_total_battles", -1))
		== int(gs.season_total_battles))

	## ⑤ 不该传的
	var n5 := _puts().size()
	(gs.persistent_equipped["phoenix"] as Array).pop_back()     # 先让阵容变一点, 下面每一条才不是「没变」挡下的
	gs.week_anchor_ts = _wk() - 7 * 86400
	await _visit(INV)
	_ok("⑤ ★本机赛季是上一周(本周没开轮)⇒ 不传", _puts().size() == n5 and int(RD.skipped.get("not_open", 0)) >= 1, str(RD.skipped))
	gs.week_anchor_ts = _wk()
	var ldr0: Array = (gs.season_leaders as Array).duplicate()
	gs.season_leaders = ["two_head", "phoenix"]
	RD.put_defense()
	await _frames(3)
	_ok("⑤ ★统领不满 3 只 ⇒ 不传", _puts().size() == n5)
	gs.season_leaders = ["two_head", "phoenix", ""]
	RD.put_defense()
	await _frames(3)
	_ok("⑤ 统领里有空位 ⇒ 不传", _puts().size() == n5)
	gs.season_leaders = ldr0
	gs.tutorial_active = true
	RD.put_defense()
	await _frames(3)
	_ok("⑤ 教程沙盒里 ⇒ 不传", _puts().size() == n5)
	gs.tutorial_active = false
	RD.force_in_test = false
	RD.put_defense()
	await _frames(3)
	_ok("⑤ test_mode(回放 / 切磋 / 门禁)⇒ 不传", _puts().size() == n5)
	RD.force_in_test = true
	OS.set_environment(SB.ENV_URL, " ")
	RD.put_defense()
	await _frames(3)
	_ok("⑤ 没配后端 ⇒ 一个请求都不发", _puts().size() == n5 and int(RD.skipped.get("off", 0)) >= 1)
	OS.set_environment(SB.ENV_URL, "https://example.invalid")
	_ok("⑤ 分母: 以上几条都真走到了闸前(各种不传都记了数)", int(RD.skipped.get("skip", 0)) >= 2 and int(RD.skipped.get("not_open", 0)) >= 3, str(RD.skipped))

	## ⑥ 失败静默、下次再传
	_reply = {"ok": false, "code": 0, "body": ""}
	await _visit(INV)
	_ok("⑥ 连不上: 真发了一次", _puts().size() == n5 + 1, str(_puts().size() - n5))
	await _visit(INV)
	_ok("⑥ ★连不上不记成已传 ⇒ 下次离开背包再传", _puts().size() == n5 + 2, str(_puts().size() - n5))
	_reply = {"ok": true, "code": 200, "body": "{\"ok\": false, \"reason\": \"not_signed_in\"}"}
	await _visit(INV)
	_ok("⑥ 服务器回 ok:false ⇒ 也不记成已传", _puts().size() == n5 + 3)
	_reply = {"ok": true, "code": 200, "body": "{\"ok\": true, \"has_defense\": true}"}
	await _visit(INV)
	await _visit(INV)
	_ok("⑥ ★传成之后不再传", _puts().size() == n5 + 4, str(_puts().size() - n5))
	_ok("⑥ 纯判据 week_open: 3 只 + 同一周 ⇒ 开; 差一周 / 2 只 / 空 id / 锚点 0 ⇒ 不开",
		RD.week_open(["a", "b", "c"], 100, 100) and not RD.week_open(["a", "b", "c"], 99, 100)
		and not RD.week_open(["a", "b"], 100, 100) and not RD.week_open(["a", "", "c"], 100, 100)
		and not RD.week_open(["a", "b", "c"], 0, 0) and not RD.week_open(null, 100, 100))
	_ok("分母: 设备标识取的是 OS.get_unique_id()(网页版为空)", ML.device_id() == OS.get_unique_id().left(128))

	RD.force_in_test = false
	RD._reset_for_test()
	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	_ok("还原: 后端又是没配", not SB.enabled())
	_finish()


func _finish() -> void:
	print("")
	_ok("分母: 断言条数 ≥ %d(少了 = 半路中止)" % NEED, _n >= NEED, str(_n))
	if _fail == 0:
		print("ALL PASS — 偷袭防守阵容上传(%d 条)" % _n)
	else:
		print("FAIL x%d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
