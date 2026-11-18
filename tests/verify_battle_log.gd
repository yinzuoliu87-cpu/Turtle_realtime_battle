extends Node
## verify_battle_log —— 战绩页重做(2026-11-18 · 方案书 docs/plans/20261118-对局记录重做.md)。
##
## 用户 11-18「对局记录现在就只有…积分赛…周日是不是没有啊？偷袭的是不是也没有啊？…时间双方的装备也没有。」
##   ① BattleLogNet.parse: 四种赛事都收; 不认识的种类 / 没 id 的行丢掉; lanes 只认 me / foe; equipped 只留三统领; 我在 b 方有记号
##   ② BattleLogCard.time_text: 今天 / 昨天 / 周X / 月-日 + 时长(时钟注入)
##   ③ 真页面(假服务器回四种各一场 + 本机两条老记录, 其中一条与服务器同一局):
##     · 卡数 = 服务器 4 + 本机去重后 1; 新的在前、本机那条按时间插在对的位置
##     · 每张服务器卡: 赛事签字对(偷袭写进攻 / 防守、决赛写第几轮)、时间那行有「时长」、双方三统领各自的装备格(带 eq_id)、两路胜负签
##     · 「观看」只在有录像的行出(服务器 replay = true / 决赛), 没录像的闯关赛不出
##     · 页签: 点「偷袭」只剩偷袭那一张, 总览场次跟着变; 页签上的数对
##   ④ 断网(服务器回失败): 只剩本机两条, 列表上方说「连不上服务器」
## 变异: 去掉 equipped 的统领过滤 / 页签不过滤 / 去重不按录像号 ⇒ 对应条目红(本文件头注列的每一条都有断言)。

const SB := preload("res://scripts/net/supabase.gd")
const BLN := preload("res://scripts/net/battle_log_net.gd")
const BLC := preload("res://scripts/scenes/record/battle_log_card.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _fails := 0
var _n := 0
var _body := "[]"
var _fail_net := false


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _side(name: String, leaders: Array, extra: String = "") -> Dictionary:
	var eq := {}
	var all := leaders.duplicate()
	if extra != "":
		all.append(extra)
	for i in range(all.size()):
		eq[all[i]] = [{"id": "p2eq_00%d" % (i + 1), "star": 2}, {"id": "p2eq_010", "star": 1}, {"id": "p2eq_011", "star": 3}]
	return {"name": name, "tag": "#" + name.to_upper(), "avatar": leaders[0], "leaders": leaders, "equipped": eq,
		"lanes": {"top": leaders.slice(0, 2), "bottom": leaders.slice(2, 3)}}


func _fake(method, url, _h, _b, cb) -> void:
	if str(url).ends_with("/rest/v1/rpc/my_battle_log"):
		if _fail_net:
			cb.call({"ok": false, "code": 0, "body": ""})
		else:
			cb.call({"ok": true, "code": 200, "body": _body})
		return
	cb.call({"ok": true, "code": 200, "body": "{}"})


func _wait(cond: Callable, frames: int = 120) -> bool:
	for _i in range(frames):
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true
	var now := int(P2C.now_utc())
	var me := _side("me", ["lava", "ice", "stone"], "candy")
	var foe := _side("foe", ["crystal", "dice", "chest"])
	var rows := [
		{"id": 40, "kind": "raid", "week": 1, "at": now - 600, "side": "a", "won": true, "secs": 112,
			"lanes": {"top": "foe", "bottom": "me"}, "match_id": "aaaaaaaa-0000-4000-8000-000000000040", "replay": true,
			"finals": null, "raid_role": "attack", "me": me, "foe": foe},
		{"id": 30, "kind": "finals", "week": 1, "at": now - 7200, "side": "b", "won": false, "secs": 68,
			"lanes": {"top": "foe", "bottom": "foe"}, "match_id": "aaaaaaaa-0000-4000-8000-000000000030", "replay": false,
			"finals": {"bucket": 3, "round": 2, "match": 1}, "raid_role": null, "me": me, "foe": foe},
		{"id": 20, "kind": "gauntlet", "week": 1, "at": now - 90000, "side": "b", "won": true, "secs": 100,
			"lanes": {"top": "me", "bottom": "weird"}, "match_id": "aaaaaaaa-0000-4000-8000-000000000020", "replay": false,
			"finals": null, "raid_role": null, "me": me, "foe": foe},
		{"id": 10, "kind": "ranked", "week": 1, "at": now - 400000, "side": "a", "won": false, "secs": 75,
			"lanes": {"top": "me", "bottom": "foe"}, "match_id": "aaaaaaaa-0000-4000-8000-000000000010", "replay": true,
			"finals": null, "raid_role": null, "me": me, "foe": foe},
		{"id": 5, "kind": "mystery", "at": now, "me": me, "foe": foe},
		{"kind": "ranked", "at": now, "me": me, "foe": foe},
	]
	_body = JSON.stringify(rows)

	print("=== ① 解析 ===")
	var p := BLN.parse(true, 200, _body)
	var got: Array = p.get("rows", [])
	_ok("① 分母: 回包 6 行, 收下 4 行(不认识的种类 / 没 id 的丢掉)", bool(p.get("ok", false)) and got.size() == 4, str(got.size()))
	_ok("① 四种赛事都在", got.map(func(r) -> String: return str(r["kind"])) == ["raid", "finals", "gauntlet", "ranked"])
	_ok("① ★equipped 只留三统领(快照里多带的 candy 不进来)", (got[0]["me"]["equipped"] as Dictionary).keys() == ["lava", "ice", "stone"],
		str((got[0]["me"]["equipped"] as Dictionary).keys()))
	_ok("① lanes 只认 me / foe(weird ⇒ 空)", got[2]["lanes"] == {"top": "me", "bottom": ""}, str(got[2]["lanes"]))
	_ok("① 我在 b 方有记号(决赛 / 闯关), a 方没有", bool(got[1]["b_side"]) and bool(got[2]["b_side"]) and not bool(got[0]["b_side"]))
	_ok("① 断网 ⇒ ok false、没有行", not bool(BLN.parse(false, 0, "").get("ok", true)) and (BLN.parse(false, 0, "")["rows"] as Array).is_empty())

	## ★11-18 CI 抓到: 进页后立刻换屏, 回包时回调方已释放 ⇒ `null::_on_fetched` SCRIPT ERROR(run-tests FATAL 正则会抓)。
	var gone := Node.new()
	var cb := Callable(gone, "get_name")
	gone.free()
	var d0: int = BLN.dropped
	BLN._reply(cb, {"ok": true, "rows": []})
	_ok("① 回调方已释放 ⇒ 回包丢掉、不报错", BLN.dropped == d0 + 1, str(BLN.dropped - d0))

	print("=== ② 时间 ===")
	var d := P2C.local_dict(now)
	var noon := now - (int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))) + 12 * 3600
	_ok("② 今天 12:00 · 时长 1:52", BLC.time_text(noon, 112, noon + 60) == "今天 12:00  ·  时长 1:52", BLC.time_text(noon, 112, noon + 60))
	_ok("② 昨天 12:00", BLC.time_text(noon - 86400, 0, noon + 60) == "昨天 12:00", BLC.time_text(noon - 86400, 0, noon + 60))
	_ok("② 三天前 ⇒ 周X 12:00", BLC.time_text(noon - 3 * 86400, 0, noon + 60) == P2C.local_wd_hhmm(noon - 3 * 86400))
	var old := P2C.local_dict(noon - 10 * 86400)
	_ok("② 十天前 ⇒ 月-日 时:分", BLC.time_text(noon - 10 * 86400, 0, noon + 60) == "%d-%02d 12:00" % [int(old["month"]), int(old["day"])],
		BLC.time_text(noon - 10 * 86400, 0, noon + 60))

	print("=== ③ 真页面 ===")
	var hist_keep: Array = (gs.match_history as Array).duplicate(true)
	gs.match_history = [
		{"result": "win", "lineup": ["basic", "ghost", "pirate"], "mode": "实时", "turn": 50, "ts": now - 3600, "foe": ["ninja"], "foe_name": "本机一"},
		{"result": "lose", "lineup": ["basic", "ghost", "pirate"], "mode": "实时", "turn": 60, "ts": now - 600,
			"replay_id": "aaaaaaaa-0000-4000-8000-000000000040", "foe_name": "重复的那局"},
	]
	OS.set_environment("TURTLE_SUPABASE", "http://127.0.0.1:9")
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1","user":{"id":"uid-log","email":"e@x.co"}}')
	SB._transport_for_test = _fake
	var rs: Node = (load("res://scenes/Record.tscn") as PackedScene).instantiate()
	add_child(rs)
	await _wait(func() -> bool: return str(rs.server_state) == "ok")
	await get_tree().process_frame
	var cards: Array = rs.find_children("RecordCard*", "", true, false)
	var kinds: Array = cards.map(func(c) -> String: return str((c as Node).get_meta("row_kind", "")))
	_ok("③ ★卡数 = 服务器 4 + 本机去重后 1(与服务器同一局的那条不重复)", cards.size() == 5, str(kinds))
	_ok("③ ★新的在前、本机那条(1 小时前)插在偷袭(10 分钟前)和决赛(2 小时前)之间", kinds == ["raid", "local", "finals", "gauntlet", "ranked"], str(kinds))
	var c0: Node = rs.find_child("RecordCard0", true, false)
	var c2: Node = rs.find_child("RecordCard2", true, false)
	_ok("③ 赛事签: 偷袭 · 进攻 / 周日决赛 · 第2轮", _label(c0, "KindTag") == "偷袭 · 进攻" and _label(c2, "KindTag") == "周日决赛 · 第2轮",
		_label(c0, "KindTag") + " / " + _label(c2, "KindTag"))
	_ok("③ 时间那行带时长", _label(c0, "TimeText").contains("时长 1:52"), _label(c0, "TimeText"))
	var eq0: Array = c0.find_children("EqSlot*", "", true, false).filter(func(s) -> bool: return (s as Node).has_meta("eq_id"))
	_ok("③ ★双方三统领各自的装备格都画出来(2 × 3 × 3 = 18 格有装备)", eq0.size() == 18, str(eq0.size()))
	_ok("③ 两路胜负签: 上路 负 / 下路 胜", _label(c0, "LaneTagtop") == "上路 负" and _label(c0, "LaneTagbottom") == "下路 胜",
		_label(c0, "LaneTagtop") + " / " + _label(c0, "LaneTagbottom"))
	var watch_rows: Array = []
	for i in range(cards.size()):
		var c: Node = rs.find_child("RecordCard%d" % i, true, false)
		if c.find_children("ReplayBtn", "Button", true, false).size() > 0:
			watch_rows.append(kinds[i])
	_ok("③ ★「观看」只在有录像的行(偷袭 replay / 决赛 / 积分赛 replay), 闯关赛没录像不出、本机没录像不出", watch_rows == ["raid", "finals", "ranked"], str(watch_rows))
	(rs.find_child("Tab_raid", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var cards2: Array = rs.find_children("RecordCard*", "", true, false)
	_ok("③ ★点「偷袭」页签: 只剩偷袭那一张", cards2.size() == 1 and str((cards2[0] as Node).get_meta("row_kind", "")) == "raid", str(cards2.size()))
	_ok("③ 页签上的数: 全部 5 / 偷袭 1 / 闯关赛 1", _btn(rs, "Tab_all") == "全部 5" and _btn(rs, "Tab_raid") == "偷袭 1" and _btn(rs, "Tab_gauntlet") == "闯关赛 1",
		_btn(rs, "Tab_all") + " " + _btn(rs, "Tab_raid"))
	rs.queue_free()
	await get_tree().process_frame

	print("=== ④ 断网 ===")
	_fail_net = true
	var rs2: Node = (load("res://scenes/Record.tscn") as PackedScene).instantiate()
	add_child(rs2)
	await _wait(func() -> bool: return str(rs2.server_state) != "loading")
	await get_tree().process_frame
	var cards3: Array = rs2.find_children("RecordCard*", "", true, false)
	_ok("④ 断网: 只剩本机两条、列表上方说连不上", cards3.size() == 2 and rs2._list_title.text == rs2.TXT_OFFLINE, "%d %s" % [cards3.size(), rs2._list_title.text])
	rs2.queue_free()

	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	gs.match_history = hist_keep
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 and _n >= 20 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _label(root: Node, nm: String) -> String:
	var n: Node = root.find_child(nm, true, false) if root != null else null
	if n is Label:
		return (n as Label).text
	if n != null:
		for ch in n.get_children():
			if ch is Label:
				return (ch as Label).text
	return ""


func _btn(rs: Node, nm: String) -> String:
	var b := rs.find_child(nm, true, false) as Button
	return b.text if b != null else ""
