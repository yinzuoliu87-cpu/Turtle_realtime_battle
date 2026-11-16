extends Node
## verify_finals_lineup_push.gd —— 周末决赛「确定阵容」(2026-11-16 · 方案书 docs/plans/20261116b-周末确定阵容按钮.md)。
## 用户 11-16:「加个按钮，就加在背包里面…加个确定阵容，然后在点确定阵容的时候，就顺便把那个选择技能…跳出来让玩家选择」。
## (这条门禁原来守 0.23.4 的「背包一改就自动推」; 11-16 起不再自动推, 交阵容只走背包按钮 → 选龟页决赛模式 →「提交阵容」。)
## 判据(注入传输, 量真发出去的请求; 钟钉死):
##   ① ★全局层每拍不再推任何阵容(0 个写请求); 备战窗开着、背包没提交 ⇒ 每轮提醒一次
##   ② 提交: 发 finals_confirm_snapshot, 带周锚点与快照(快照里有技能 loadouts); 回 now ⇒「本轮按这套阵容出战」; 之后「阵容已确定」
##   ③ ★换了技能 ⇒ 不再算已确定 ⇒ 下一轮又提醒
##   ④ 回包翻成一句话: seat / now / next / cup / bad_lineup / closed / not_entered / 网络失败
##   ⑤ 窗外 / 观众 / 组已收盘: 不提醒
##   ⑥ 按钮该不该出现(stage): 没晋级 ⇒ 无; 晋级后周日 18:00 前 ⇒ pre
##   ⑦ 背包: pre ⇒ 顶栏「背包」页签右边有「确定阵容」+ 红点; 提交过 ⇒「阵容已确定」、没红点; 不该出现 ⇒ 没有
##   ⑧ 选龟页决赛模式: 页名「决赛阵容」、主按钮「提交阵容」; 点了 ⇒ 交阵容、回背包(不进匹配); 返回 ⇒ 回背包; 标记取一次就清
##   ⑨ 接线: 对阵图 / backend / supabase 里那条自动推送链删干净; 全局层仍调 tick
## 反向验证(2026-11-16 做过): tick 里加回推送 ⇒ ① 红; remind 去掉 is_confirmed ⇒ ② 末条红; receipt_of 把 next 翻成 now ⇒ ④ 红。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const FLP := preload("res://scripts/net/finals_lineup_push.gd")

var _n := 0
var _fail := 0
var _sent: Array = []
var _reply: Array = ['{"ok": true, "applies": "now"}']
var _code: Array = [200]
var _nav: Array = []


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _rpc(fn: String) -> Array:
	return _sent.filter(func(x): return str(x["u"]).ends_with("/rpc/" + fn))


func _writes() -> int:
	return _sent.filter(func(x): return str(x["u"]).find("/rpc/finals_") >= 0).size()


func _submit() -> Array:
	var got: Array = []
	FinalsConfirm.submit(func(m: String, ok: bool) -> void: got.append([m, ok]))
	for _i in 6:
		await get_tree().process_frame
	return got[0] if not got.is_empty() else ["", false]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周末决赛「确定阵容」 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	gs.account_id = "uid-me"
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = func(_m, u, _h, b, cb):
		_sent.append({"u": str(u), "b": str(b)})
		cb.call({"ok": _code[0] == 200, "code": _code[0], "body": _reply[0]})
	SceneNav.nav_for_test = func(p): _nav.append(str(p))
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.dual_lineup = {}
	gs.loadouts = {"basic": 1, "stone": 1, "bamboo": 1}
	gs.week_anchor_ts = 1793577600 + 604800
	FinalsConfirm.reset_for_test()
	P2C.now_override_ts = 1794240000
	var srv: int = P2C.now_override_ts
	_ok("分母: 后端打开了(注入传输) / 背包里有一套能交的阵容", SB.enabled() and FinalsConfirm.current_sig() != "")
	## 我那一组: 2 人、我是 0 号、第 1 轮刚开打 30 秒(备战窗 180 秒还开着)
	var lv := {"size": 2, "round": 1, "me": 0, "bucket": 4, "closed": false, "round_at": srv - 30, "srv_now": srv, "recv_at": srv}

	## ── ① 不再自动推; 没提交 ⇒ 每轮提醒一次 ──
	var m1 := FLP.tick(lv, {}, srv)
	var m1b := FLP.tick(lv, {}, srv + 1)
	for _i in 4:
		await get_tree().process_frame
	_ok("① ★★全局层每拍不推阵容(0 个决赛写请求)", _writes() == 0, "writes=%d" % _writes())
	_ok("① 备战窗开着、背包没提交 ⇒ 提醒一次", m1 == FinalsConfirm.REMIND, m1)
	_ok("① 同一轮不重复提醒", m1b == "", m1b)

	## ── ② 提交 ──
	var r2: Array = await _submit()
	var req: Array = _rpc("finals_confirm_snapshot")
	_ok("② ★发 finals_confirm_snapshot 一次", req.size() == 1, "%d" % req.size())
	var body: Dictionary = JSON.parse_string(str(req[0]["b"])) if req.size() == 1 else {}
	_ok("② 带周锚点与快照, 快照里有技能 loadouts", int(body.get("p_week", 0)) == int(gs.week_anchor_ts)
		and body.get("p_snapshot", null) is Dictionary and (body["p_snapshot"] as Dictionary).has("loadouts"), str(body.keys()))
	_ok("② 回 now ⇒「本轮按这套阵容出战」", r2[0] == FinalsConfirm.R_NOW and bool(r2[1]), str(r2))
	_ok("② ★提交过 ⇒ 阵容已确定", FinalsConfirm.is_confirmed())
	var lv2 := lv.duplicate()
	lv2["round_at"] = srv + 600
	lv2["srv_now"] = srv + 630
	lv2["recv_at"] = srv + 630
	P2C.now_override_ts = srv + 630
	_ok("② 已确定 ⇒ 下一轮备战不再提醒", FLP.tick(lv2, {}, srv + 630) == "")

	## ── ③ 换技能 ⇒ 又算没提交 ──
	gs.loadouts["stone"] = 2
	_ok("③ ★换了技能 ⇒ 不再算已确定", not FinalsConfirm.is_confirmed())
	var lv3 := lv.duplicate()
	lv3["round_at"] = srv + 1200
	lv3["srv_now"] = srv + 1230
	lv3["recv_at"] = srv + 1230
	P2C.now_override_ts = srv + 1230
	_ok("③ 下一轮备战 ⇒ 又提醒", FLP.tick(lv3, {}, srv + 1230) == FinalsConfirm.REMIND)

	## ── ④ 回包 → 一句话 ──
	var cases := [
		[{"ok": true, "data": {"applies": "seat"}}, FinalsConfirm.R_SEAT],
		[{"ok": true, "data": {"applies": "now"}}, FinalsConfirm.R_NOW],
		[{"ok": true, "data": {"applies": "next"}}, FinalsConfirm.R_NEXT],
		[{"ok": true, "data": {"applies": "cup"}}, FinalsConfirm.R_CUP],
		[{"ok": false, "reason": "bad_lineup"}, FinalsConfirm.E_BAD],
		[{"ok": false, "reason": "closed"}, FinalsConfirm.E_CLOSED],
		[{"ok": false, "reason": "not_entered"}, FinalsConfirm.E_NOT_ENTERED],
		[{"ok": false, "reason": "net"}, FinalsConfirm.E_NET],
	]
	var bad4: Array = []
	for c in cases:
		if FinalsConfirm.receipt_of(c[0]) != str(c[1]):
			bad4.append(str(c[0]))
	_ok("④ ★回包翻成一句话(8 种)", bad4.is_empty(), str(bad4))
	_code[0] = 500
	var r4: Array = await _submit()
	_ok("④ 网络失败 ⇒「网络不通」、不算已确定", r4[0] == FinalsConfirm.E_NET and not bool(r4[1]) and not FinalsConfirm.is_confirmed(), str(r4))
	_code[0] = 200

	## ── ⑤ 窗外 / 观众 / 收盘 ──
	var lv5 := lv.duplicate()
	lv5["round_at"] = srv - 400
	FinalsConfirm.reset_for_test()
	P2C.now_override_ts = srv
	_ok("⑤ 备战窗外不提醒", FLP.tick(lv5, {}, srv) == "")
	var spec := lv.duplicate()
	spec["me"] = -1
	var shut := lv.duplicate()
	shut["closed"] = true
	_ok("⑤ 观众 / 组已收盘不提醒", FLP.tick(spec, {}, srv) == "" and FLP.tick(shut, {}, srv) == "")

	## ── ⑥ stage ──
	gs.gauntlet_wins = 0
	gs.gauntlet_losses = 0
	_ok("⑥ 没晋级 ⇒ 不出现", FinalsConfirm.stage(srv) == "")
	gs.gauntlet_wins = 4
	var wk: int = int(gs.week_anchor_ts)
	_ok("⑥ ★晋级了、周六中午 ⇒ pre(入座前就能交)", FinalsConfirm.stage(wk + 5 * 86400 + 12 * 3600) == FinalsConfirm.STAGE_PRE,
		FinalsConfirm.stage(wk + 5 * 86400 + 12 * 3600))
	_ok("⑥ 晋级了、周日入座前一刻 ⇒ pre", FinalsConfirm.stage(P2C.finals_seat_ts(wk) - 60) == FinalsConfirm.STAGE_PRE)
	_ok("⑥ 入座后还没收到分组 / 下周一 ⇒ 不出现", FinalsConfirm.stage(P2C.finals_seat_ts(wk) + 600) == ""
		and FinalsConfirm.stage(wk + 7 * 86400 + 3600) == "")
	gs.gauntlet_wins = 0
	FinalsConfirm.override_stage = "pre"
	_ok("⑥ 注入 pre ⇒ pre(背包 / 选龟页门禁走这条)", FinalsConfirm.stage(srv) == FinalsConfirm.STAGE_PRE)
	FinalsConfirm.override_stage = ""

	## ── ⑦ 背包按钮 ──
	FinalsConfirm.override_stage = "pre"
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	for _i in 3:
		await get_tree().process_frame
	var btn: Button = inv.find_child("FinalsConfirmBtn", true, false) as Button
	_ok("⑦ ★分母: pre ⇒ 背包顶栏有「确定阵容」", btn != null and btn.text == FinalsConfirm.BTN_CONFIRM, btn.text if btn != null else "无")
	var tab: Button = null
	if btn != null:
		for b in btn.get_parent().get_children():
			if b is Button and (b as Button).text == "背包":
				tab = b
	_ok("⑦ 紧跟在「背包」页签右边、同一高度", btn != null and tab != null and btn.position.x >= tab.position.x + tab.size.x
		and absf(btn.position.y + btn.size.y * 0.5 - tab.position.y - tab.size.y * 0.5) < 2.0)
	_ok("⑦ 没提交 ⇒ 红点", btn != null and btn.find_child("FinalsConfirmDot", true, false) != null)
	_nav.clear()
	if btn != null:
		btn.pressed.emit()
	_ok("⑦ ★点了 ⇒ 进选龟页、置决赛模式标记", _nav == ["res://scenes/TeamSelect.tscn"] and FinalsConfirm.pick_mode, str(_nav))
	FinalsConfirm.pick_mode = false
	inv.queue_free()
	await get_tree().process_frame
	await _submit()
	var inv2 = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv2)
	for _i in 3:
		await get_tree().process_frame
	var btn2: Button = inv2.find_child("FinalsConfirmBtn", true, false) as Button
	_ok("⑦ 提交过 ⇒「阵容已确定」、没红点", btn2 != null and btn2.text == FinalsConfirm.BTN_DONE
		and btn2.find_child("FinalsConfirmDot", true, false) == null, btn2.text if btn2 != null else "无")
	inv2.queue_free()
	FinalsConfirm.override_stage = "none"
	var inv3 = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv3)
	for _i in 3:
		await get_tree().process_frame
	_ok("⑦ 不该出现 ⇒ 没有按钮", inv3.find_child("FinalsConfirmBtn", true, false) == null)
	inv3.queue_free()
	FinalsConfirm.override_stage = ""
	await get_tree().process_frame

	## ── ⑧ 选龟页决赛模式 ──
	FinalsConfirm.pick_mode = true
	var ts = load("res://scenes/TeamSelect.tscn").instantiate()
	add_child(ts)
	for _i in 3:
		await get_tree().process_frame
	_ok("⑧ 标记取一次就清", not FinalsConfirm.pick_mode)
	_ok("⑧ ★决赛模式: 页名「决赛阵容」、主按钮「提交阵容」", bool(ts._fc_mode)
		and _has_label(ts, FinalsConfirm.PAGE_TITLE) and (ts._start_btn as Button).text == FinalsConfirm.PAGE_SUBMIT,
		(ts._start_btn as Button).text)
	_nav.clear()
	var before := _rpc("finals_confirm_snapshot").size()
	ts._on_start()
	for _i in 6:
		await get_tree().process_frame
	_ok("⑧ ★点「提交阵容」⇒ 交阵容一次、回背包(不进匹配)", _rpc("finals_confirm_snapshot").size() == before + 1
		and _nav == ["res://scenes/Inventory.tscn"], str(_nav))
	_nav.clear()
	ts._on_back()
	_ok("⑧ 返回 ⇒ 回背包", _nav == ["res://scenes/Inventory.tscn"], str(_nav))
	ts.queue_free()
	await get_tree().process_frame
	var ts2 = load("res://scenes/TeamSelect.tscn").instantiate()
	add_child(ts2)
	for _i in 3:
		await get_tree().process_frame
	_ok("⑧ 对照: 不带标记进来 ⇒ 平常的「本大轮统领 / 出战」", not bool(ts2._fc_mode) and (ts2._start_btn as Button).text == "出战",
		(ts2._start_btn as Button).text)
	ts2.queue_free()

	## ── ⑨ 接线 ──
	var bm := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var be := FileAccess.get_file_as_string("res://scripts/net/backend.gd")
	var sb := FileAccess.get_file_as_string("res://scripts/net/supabase.gd")
	var lay := FileAccess.get_file_as_string("res://scripts/ui/finals_day_layer.gd")
	_ok("⑨ ★自动推送链删干净: 没有 finals_push_snapshot / finals_update_snapshot 的客户端调用",
		not bm.contains("finals_push_snapshot") and not be.contains("static func finals_push_snapshot")
		and not sb.contains("rpc/finals_update_snapshot"))
	_ok("⑨ 全局层仍每拍调 tick(提醒)", lay.contains("_FLP.tick(group, cup"))

	SceneNav.nav_for_test = Callable()
	SB._transport_for_test = Callable()
	FinalsConfirm.reset_for_test()
	P2C.now_override_ts = 0
	if _fail == 0 and _n >= 25:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


func _has_label(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			return true
	return false
