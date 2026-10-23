extends Node
## verify_friends_flow.gd —— 好友页 / 玩家菜单「加好友」/ 切磋取阵容(方案书 docs/plans/20261023-好友切磋.md §6 第二条)。
##
## 用户 2026-10-23「好友系统，主要实现切磋 … 切磋是当前的背包阵容vs好友的最新背包阵容」; 加好友 = 双方同意(用户选)。
## 注入传输层(`SB._transport_for_test`)= 一个记账的假服务端; 服务端本身的规则(好友才读得到阵容 / 上限 / 拒绝不再打扰)
##   由 server/supabase/tests/20261024_friends_check.sql 在真 PG16 上量, 这里只量客户端。
##
##   A 回包判据: 2xx + {ok:true} 才算成; {ok:false, reason} 原样带回; 非 2xx / 出口拦下 = net
##   B 阵容版本闸: 规则版本不同(谁旧说谁) / 快照结构旧 / 没统领 ⇒ 不打; 对上 ⇒ 打
##   C put_lineup: 同一份阵容只传一次; 变了再传; 教程沙盒 / test_mode 不传; 传的是 build_ghost_snapshot 的产物
##   D 好友页: 我的 ID / 好友 N / 100 / 好友行(切磋 · 删除)/ 收到的申请(同意 · 拒绝)/ 发出的(撤回)
##   E 同意 ⇒ 发 friend_respond(对的人, true) ⇒ 重新取列表; 删除要按两次
##   F 查找: 一个人 ⇒ 一行「申请好友」⇒ 发 friend_request; ID 撞号回两个 ⇒ 两行 + 提示核对昵称; 坏 ID 不发请求
##   G 切磋: 规则版本不同 ⇒ 屏上说原因、不开局; 对上 ⇒ 用对方快照开局(spar_start 拿到的就是服务端那份)
##   H 玩家菜单「加好友」: 有账号直接申请; 只有 ID ⇒ 查人后申请; 撞号按昵称挑; 认不出 ⇒ 不发申请
##   I 没配后端 ⇒ 屏上「未连接服务器」、一个请求都不发

const SB := preload("res://scripts/net/supabase.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const PM := preload("res://scripts/scenes/social/player_menu.gd")
const BE := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const FS := preload("res://scripts/scenes/FriendsScene.gd")

const ME := "11111111-1111-4111-8111-111111111111"
const F1 := "22222222-2222-4222-8222-222222222222"
const F2 := "33333333-3333-4333-8333-333333333333"
const R1 := "44444444-4444-4444-8444-444444444444"
const O1 := "55555555-5555-4555-8555-555555555555"
const P1 := "66666666-6666-4666-8666-666666666666"
const P2 := "77777777-7777-4777-8777-777777777777"

var _fail := 0
var _n := 0
var _key0 = ""
## 假服务端: 每个请求记一行 {fn, body}。
var _reqs: Array = []
var _friends: Array = []
var _incoming: Array = []
var _outgoing: Array = []
var _people: Array = []
var _lineup: Dictionary = {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _card(acc: String, nm: String, lead: String, has := true) -> Dictionary:
	return {"account": acc, "name": nm, "tag": P2C.player_tag(acc), "lead": lead, "has_lineup": has,
		"updated_at": "2026-10-24T08:00:00.000+00:00"}


func _good_snap() -> Dictionary:
	return {"schema_ver": BE.SCHEMA_VER, "leaders": ["lava", "stone", "basic"],
		"lane_assign": {"top": ["lava"], "bottom": ["stone", "basic"]},
		"profile": {"name": "好友甲", "avatar": "lava", "id": "g_x", "tag": P2C.player_tag(F1)}}


func _spy(method, url, headers, body, cb) -> void:
	var fn := str(url).get_file()
	var bj = JSON.parse_string(str(body))
	var b: Dictionary = bj if bj is Dictionary else {}
	_reqs.append({"fn": fn, "body": b})
	var out := {}
	match fn:
		"put_lineup":
			out = {"ok": true, "tag": P2C.player_tag(ME)}
		"friend_list":
			out = {"ok": true, "tag": P2C.player_tag(ME), "friends": _friends, "incoming": _incoming,
				"outgoing": _outgoing, "cap": 100}
		"friend_lookup":
			out = {"ok": true, "people": _people} if not _people.is_empty() else {"ok": false, "reason": "not_found"}
		"friend_request":
			out = {"ok": true, "status": "pending"}
		"friend_respond":
			if bool(b.get("p_accept", false)):
				for c in _incoming:
					if str(c["account"]) == str(b.get("p_other", "")):
						_friends.append(c)
			_incoming = _incoming.filter(func(c) -> bool: return str(c["account"]) != str(b.get("p_other", "")))
			out = {"ok": true, "status": "accepted" if bool(b.get("p_accept", false)) else "declined"}
		"friend_remove":
			_friends = _friends.filter(func(c) -> bool: return str(c["account"]) != str(b.get("p_other", "")))
			out = {"ok": true}
		"friend_lineup":
			out = _lineup
		_:
			cb.call({"ok": false, "code": 404, "body": ""})
			return
	cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})


func _backend_on(on: bool) -> void:
	if on:
		OS.set_environment(SB.ENV_URL, "http://gate.local")
		ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	else:
		OS.set_environment(SB.ENV_URL, " ")
		ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
	SB._token = "gate-token"
	SB._expires_at = 0
	SB._transport_for_test = _spy


## 一个列表里的人卡(同名兄弟会被引擎改成 @…@ 名 ⇒ 按卡上的 account 标记认, 不按名字)。
func _rows(box: Node) -> Array:
	return box.get_children().filter(func(c) -> bool: return c is PanelContainer and (c as Node).has_meta("account"))


func _count(fn: String) -> int:
	return _reqs.filter(func(r) -> bool: return str(r["fn"]) == fn).size()


func _last(fn: String) -> Dictionary:
	for i in range(_reqs.size() - 1, -1, -1):
		if str(_reqs[i]["fn"]) == fn:
			return _reqs[i]["body"]
	return {}


func _wait(frames: int = 6) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	GameState.test_mode = true
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var acc0 := str(GameState.account_id)
	GameState.account_id = ME
	GameState.tutorial_active = false
	GameState.season_leaders = ["ninja", "stone", "basic"]
	print("=== 好友 / 切磋 ===")
	_t_parse()
	_t_lineup_check()
	await _t_put()
	await _t_page()
	await _t_menu()
	await _t_off()
	_backend_on(false)
	SB._transport_for_test = Callable()
	SB._token = ""
	GameState.account_id = acc0
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 好友 / 切磋" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit()


# ── A ──
func _t_parse() -> void:
	var a := FN.parse(true, 200, '{"ok":true,"tag":"#222222"}')
	var b := FN.parse(true, 200, '{"ok":false,"reason":"full"}')
	var c := FN.parse(true, 500, '{"ok":true}')
	var d := FN.parse(true, 200, '{"ok":true}', true)
	var e := FN.parse(true, 200, "not json")
	_ok("A 2xx + {ok:true} ⇒ ok, 回包原样带回", bool(a["ok"]) and str((a["data"] as Dictionary).get("tag", "")) == "#222222")
	_ok("A {ok:false, reason} ⇒ 不 ok、reason 原样", not bool(b["ok"]) and str(b["reason"]) == "full")
	_ok("A 非 2xx / 出口拦下 / 不是 JSON ⇒ net",
		str(c["reason"]) == "net" and str(d["reason"]) == "net" and str(e["reason"]) == "net" and not bool(c["ok"]))
	_ok("A 每个 reason 都有一句话(不认识的 ⇒ 网络异常)",
		FN.msg("full").contains("100") and FN.msg("没见过") == FN.msg("net"))


# ── B ──
func _t_lineup_check() -> void:
	var rv := int(P2C.RULES_VER)
	_ok("B 对上 ⇒ 能打", FN.lineup_check({"rules_ver": rv, "snapshot": _good_snap()}) == "")
	_ok("B 对方规则版本旧 ⇒ 说对方", FN.lineup_check({"rules_ver": rv - 1, "snapshot": _good_snap()}) == "rules_old_theirs")
	_ok("B 我的规则版本旧 ⇒ 说我", FN.lineup_check({"rules_ver": rv + 1, "snapshot": _good_snap()}) == "rules_old_mine")
	var old := _good_snap()
	old["schema_ver"] = BE.SCHEMA_VER - 1
	_ok("B 快照结构版本旧 ⇒ 不打", FN.lineup_check({"rules_ver": rv, "snapshot": old}) == "rules_old_theirs")
	var empty := _good_snap()
	empty["leaders"] = []
	_ok("B 没统领 ⇒ 读取失败", FN.lineup_check({"rules_ver": rv, "snapshot": empty}) == "bad_lineup")


# ── C ──
func _t_put() -> void:
	_backend_on(true)
	_reqs.clear()
	FN._last_put = ""
	var got: Array = []
	FN.put_lineup(func(r: Dictionary) -> void: got.append(r), true)
	await _wait()
	var body := _last("put_lineup")
	_ok("C 传了一次, 快照是 build_ghost_snapshot 的产物(统领 = 我的 season_leaders)",
		_count("put_lineup") == 1 and (body.get("p_snapshot", {}) as Dictionary).get("leaders", []) == ["ninja", "stone", "basic"]
			and int(body.get("p_rules_ver", -1)) == int(P2C.RULES_VER) and got.size() == 1 and bool(got[0]["ok"]),
		str(body.keys()))
	FN.put_lineup(Callable(), true)
	await _wait()
	_ok("★C 同一份阵容第二次不发(force 只跳过 test_mode 闸, 不跳过「没变不传」)", _count("put_lineup") == 1,
		"%d" % _count("put_lineup"))
	var n0 := _count("put_lineup")
	FN.put_lineup(Callable(), false)
	await _wait()
	_ok("★C test_mode 里不传", _count("put_lineup") == n0)
	GameState.season_leaders = ["lava", "stone", "basic"]
	FN.put_lineup(Callable(), true)
	await _wait()
	_ok("C 阵容变了 ⇒ 再传", _count("put_lineup") == n0 + 1 and
		(_last("put_lineup").get("p_snapshot", {}) as Dictionary).get("leaders", []) == ["lava", "stone", "basic"])
	FN.put_lineup(Callable(), true)
	await _wait()
	_ok("★C 阵容没变 ⇒ 不再传", _count("put_lineup") == n0 + 1, "%d" % _count("put_lineup"))
	GameState.tutorial_active = true
	GameState.season_leaders = ["ice", "stone", "basic"]
	FN.put_lineup(Callable(), true)
	await _wait()
	_ok("★C 教程沙盒里不传(那时内存里不是我的阵容)", _count("put_lineup") == n0 + 1)
	GameState.tutorial_active = false
	GameState.season_leaders = ["ninja", "stone", "basic"]


# ── D/E/F/G ──
func _t_page() -> void:
	_backend_on(true)
	_reqs.clear()
	_friends = [_card(F1, "好友甲", "lava"), _card(F2, "好友乙", "ice", false)]
	_incoming = [_card(R1, "申请人丙", "ninja")]
	_outgoing = [_card(O1, "等我丁", "basic")]
	var page: Node = (load("res://scenes/Friends.tscn") as PackedScene).instantiate()
	add_child(page)
	await _wait(10)
	var fb: Node = page.find_child("Friends", true, false)
	var rq: Node = page.find_child("Requests", true, false)
	_ok("D 进页先传阵容、再取列表", _count("put_lineup") <= 1 and _count("friend_list") == 1, str(_reqs.map(func(r): return r["fn"])))
	_ok("D 我的玩家 ID 显示服务端回的那个", (page.find_child("MyTag", true, false) as Label).text == P2C.player_tag(ME))
	_ok("D 好友计数 2 / 100", (page.find_child("FriendCount", true, false) as Label).text == "2 / 100")
	var rows: Array = _rows(fb)
	_ok("D 两行好友, 每行有「切磋」「删除」", rows.size() == 2
		and (rows[0] as Node).find_child("SparBtn", true, false) != null and (rows[0] as Node).find_child("DelBtn", true, false) != null,
		str(rows.size()))
	if rows.size() == 2:
		_ok("D 没配阵容的好友写「还没有配好阵容」", ((rows[1] as Node).find_child("Sub", true, false) as Label).text == FS.TXT_NO_LINEUP)
		_ok("D 有阵容的写「阵容更新于 …」", ((rows[0] as Node).find_child("Sub", true, false) as Label).text.begins_with("阵容更新于"))
	var reqrows: Array = _rows(rq)
	_ok("D 申请区: 收到的(同意 · 拒绝)+ 发出的(撤回)",
		reqrows.size() == 2 and (reqrows[0] as Node).find_child("AcceptBtn", true, false) != null
			and (reqrows[1] as Node).find_child("CancelBtn", true, false) != null, str(reqrows.size()))
	_ok("D 按钮是卡片按钮(深棕底, 不是木牌)",
		rows.size() > 0 and ((rows[0] as Node).find_child("SparBtn", true, false) as Button).get_theme_stylebox("normal") is StyleBoxFlat)
	# E 同意
	if reqrows.size() == 2:
		((reqrows[0] as Node).find_child("AcceptBtn", true, false) as Button).pressed.emit()
		await _wait(10)
		_ok("E 同意 ⇒ 发 friend_respond(这个人, true), 然后重新取列表",
			str(_last("friend_respond").get("p_other", "")) == R1 and bool(_last("friend_respond").get("p_accept", false))
				and _count("friend_list") == 2, str(_last("friend_respond")))
		_ok("E 重新取到之后好友变成 3 个", (page.find_child("FriendCount", true, false) as Label).text == "3 / 100")
	# E 删除两步
	rows = _rows(fb)
	var del: Button = (rows[0] as Node).find_child("DelBtn", true, false)
	del.pressed.emit()
	await _wait()
	rows = _rows(fb)
	_ok("★E 第一次按「删除」⇒ 只变成「确认删除」、不发请求",
		_count("friend_remove") == 0 and ((rows[0] as Node).find_child("DelBtn", true, false) as Button).text == FS.TXT_DEL_SURE)
	((rows[0] as Node).find_child("DelBtn", true, false) as Button).pressed.emit()
	await _wait(10)
	_ok("E 第二次按 ⇒ 发 friend_remove(这个人)", _count("friend_remove") == 1 and str(_last("friend_remove").get("p_other", "")) == F1)
	# F 查找
	var ed: LineEdit = page.find_child("IdEdit", true, false)
	ed.text = "abc"
	(page.find_child("FindBtn", true, false) as Button).pressed.emit()
	await _wait()
	_ok("★F 坏 ID ⇒ 不发请求、屏上说格式不对", _count("friend_lookup") == 0 and page.last_msg == FN.msg("bad_tag"), page.last_msg)
	_people = [_card(P1, "路人甲", "phoenix")]
	ed.text = P2C.player_tag(P1).substr(1).to_lower()
	(page.find_child("FindBtn", true, false) as Button).pressed.emit()
	await _wait()
	var found: Array = _rows(page.find_child("FindResults", true, false))
	_ok("F 不带 # / 小写也认: 查到一个人一行「申请好友」",
		str(_last("friend_lookup").get("p_tag", "")) == P2C.player_tag(P1) and found.size() == 1
			and (found[0] as Node).find_child("AskBtn", true, false) != null, str(_last("friend_lookup")))
	if found.size() == 1:
		((found[0] as Node).find_child("AskBtn", true, false) as Button).pressed.emit()
		await _wait(10)
		_ok("F 点「申请好友」⇒ 发 friend_request(这个人)", str(_last("friend_request").get("p_other", "")) == P1)
	_people = [_card(P1, "路人甲", "phoenix"), _card(P2, "路人乙", "ice")]
	ed.text = P2C.player_tag(P1)
	(page.find_child("FindBtn", true, false) as Button).pressed.emit()
	await _wait()
	found = _rows(page.find_child("FindResults", true, false))
	_ok("★F ID 撞号回两个 ⇒ 两行 + 提示核对昵称", found.size() == 2 and page.last_msg.contains("核对昵称"), page.last_msg)
	# G 切磋
	var started: Array = []
	page.spar_start = func(_t, snap: Dictionary, info: Dictionary) -> String:
		started.append([snap, info])
		return ""
	_friends = [_card(F1, "好友甲", "lava")]
	page.refresh()
	await _wait(10)
	rows = _rows(fb)
	_lineup = {"ok": true, "source": "lineup", "name": "好友甲", "tag": P2C.player_tag(F1), "snapshot": _good_snap(),
		"rules_ver": int(P2C.RULES_VER) - 1, "client_version": "0.21.9"}
	((rows[0] as Node).find_child("SparBtn", true, false) as Button).pressed.emit()
	await _wait(10)
	_ok("★G 对方规则版本旧 ⇒ 屏上说原因、不开局", started.is_empty() and page.last_msg == FN.msg("rules_old_theirs"), page.last_msg)
	_lineup["rules_ver"] = int(P2C.RULES_VER)
	((rows[0] as Node).find_child("SparBtn", true, false) as Button).pressed.emit()
	await _wait(10)
	_ok("★G 对上 ⇒ 用服务端那份快照开局(取的是这个好友)",
		started.size() == 1 and (started[0][0] as Dictionary).get("leaders", []) == ["lava", "stone", "basic"]
			and str((started[0][1] as Dictionary).get("account", "")) == F1
			and str(_last("friend_lineup").get("p_other", "")) == F1, str(started.size()))
	GameState.season_leaders = []
	((rows[0] as Node).find_child("SparBtn", true, false) as Button).pressed.emit()
	await _wait(10)
	_ok("★G 我这边统领没选满 ⇒ 不去取阵容、屏上说原因", started.size() == 1 and page.last_msg == Spar.my_side_check(), page.last_msg)
	GameState.season_leaders = ["ninja", "stone", "basic"]
	page.queue_free()
	await _wait()


# ── H ──
func _t_menu() -> void:
	_backend_on(true)
	_reqs.clear()
	var res: Array = []
	PM.add_friend(P2C.player_tag(P1), "路人甲", P1, func(t: String, ok: bool) -> void: res.append([t, ok]))
	await _wait()
	_ok("H 有账号 ⇒ 不查人、直接申请", _count("friend_lookup") == 0 and str(_last("friend_request").get("p_other", "")) == P1
		and res.size() == 1 and bool(res[0][1]))
	_people = [_card(P1, "路人甲", "phoenix")]
	PM.add_friend(P2C.player_tag(P1), "路人甲", "", func(t: String, ok: bool) -> void: res.append([t, ok]))
	await _wait(10)
	_ok("H 只有 ID ⇒ 先查人再申请", _count("friend_lookup") == 1 and _count("friend_request") == 2)
	_people = [_card(P1, "路人甲", "phoenix"), _card(P2, "路人乙", "ice")]
	PM.add_friend(P2C.player_tag(P1), "路人乙", "", func(t: String, ok: bool) -> void: res.append([t, ok]))
	await _wait(10)
	_ok("★H 撞号 ⇒ 按昵称挑中那一个", _count("friend_request") == 3 and str(_last("friend_request").get("p_other", "")) == P2)
	PM.add_friend(P2C.player_tag(P1), "谁都不是", "", func(t: String, ok: bool) -> void: res.append([t, ok]))
	await _wait(10)
	_ok("★H 撞号又认不出 ⇒ 不发申请、提示去好友页", _count("friend_request") == 3 and str(res[res.size() - 1][0]) == PM.MSG_FRIEND_AMBIG)
	_ok("H 菜单里有「加好友」键(节点名)", PM.BTN_FRIEND != "" and PM.L_FRIEND == "加好友")


# ── I ──
func _t_off() -> void:
	_backend_on(false)
	_reqs.clear()
	var page: Node = (load("res://scenes/Friends.tscn") as PackedScene).instantiate()
	add_child(page)
	await _wait(10)
	_ok("I 没配后端 ⇒ 「未连接服务器」、一个请求都不发", _reqs.is_empty() and page.last_msg == FN.msg("off"), page.last_msg)
	page.queue_free()
	await _wait()
