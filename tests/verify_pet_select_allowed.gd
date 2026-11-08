extends Node
## verify_pet_select_allowed.gd —— 选龟页只显示「拥有 ∪ 本周限免」、拥有的挂等级牌、限免的挂角标且固定 1 级。
## 方案书 20261107 §4.3「周赛选龟同样只能选拥有 ∪ 本周限免」、20261107b §4.5（选龟页拥有的龟挂等级牌、限免龟挂「限免」角标、固定 1 级）。
##
##   S1 ★没登录后端（门禁 / 本机开发）⇒ 龟池 = 全部 28 只、一张「限免」都没有（不碰现有流程）
##   S2 ★登录了（拥有 stone 4 级 / lava 没记录）⇒ 龟池 = WeeklyFree.allowed_ids（9 只，逐只相同），不多不少
##   S3 ★拥有的：等级牌 = 服务器等级（stone「Lv.4」、lava「Lv.1」），没有角标；限免的：「Lv.1」+「限免」
##   S4 ★点 / 拖一只不能上场的 ⇒ 进不了阵容；能上场的照常进；上次阵容里不能上场的不恢复
##   S5 文案：角标字 = 「限免」；页面上没有「主站」「龟币」「金额」、没有「你 / 您」开头的句子
##   S6 问到服务器（新拥有一只）⇒ 重建后龟池跟着变、那只的角标没了

const TS := "res://scenes/TeamSelect.tscn"
const ACCT := "11111111-2222-4333-8444-555555555555"
const WEEK := 1762732800

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _open() -> Node:
	GameState.test_mode = true
	if int(GameState.season_total_battles) <= 0:
		GameState.season_total_battles = 3
	GameState.tutorial_active = false
	GameState.season_leaders = []
	GameState.debug_level = 0
	var ts = (load(TS) as PackedScene).instantiate()
	add_child(ts)
	await _frames(20)
	return ts


func _cards(ts) -> Dictionary:
	var out := {}
	for c in (ts._grid_flow as Node).get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		var pid := str((c as Node).get_meta("pet_id", ""))
		var lv := (c as Node).get_node_or_null("Level") as Label
		var ft := (c as Node).find_child("FreeTag", true, false) as Label
		out[pid] = {"lv": lv.text if lv != null else "", "free": ft.text if ft != null else ""}
	return out


func _texts(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			out.append(str((c as Label).text))
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).is_visible_in_tree():
			out.append(str((c as Button).text))
	return out


func _ready() -> void:
	get_tree().root.size = Vector2i(1560, 720)
	await _frames(2)
	print("=== 选龟页: 拥有 ∪ 本周限免 ===")
	var acct0 := str(GameState.account_id)
	var wk0 := int(GameState.week_anchor_ts)
	PetLevelsNet.override = {}
	PetLevelsNet.owned = []

	# ── S1 没登录 ──
	GameState.account_id = ""
	GameState.pet_lv = {}
	var ts = await _open()
	var c1 := _cards(ts)
	var free1 := 0
	for k in c1:
		if str(c1[k]["free"]) != "":
			free1 += 1
	_ok("S1 ★没登录后端 ⇒ 龟池 = 全部 28 只、没有「限免」角标", c1.size() == 28 and free1 == 0, "%d 张 / 角标 %d" % [c1.size(), free1])
	ts.queue_free()
	await _frames(3)

	# ── S2 / S3 登录了 ──
	GameState.account_id = ACCT
	GameState.week_anchor_ts = WEEK
	GameState.pet_lv = {}
	PetLevelsNet.override = {"linked": true, "owned": ["stone", "lava"], "levels": {"stone": {"lv": 4, "xp": 300}}}
	ts = await _open()
	var allowed := WeeklyFree.allowed_ids(ACCT, WEEK, ["stone", "lava"])
	var c2 := _cards(ts)
	var keys2: Array = c2.keys()
	keys2.sort()
	var want2: Array = allowed.duplicate()
	want2.sort()
	_ok("S2 ★龟池 = 拥有 ∪ 本周限免(%d 只, 逐只相同)" % allowed.size(), keys2 == want2 and allowed.size() == 9, "%s" % str(keys2))
	var bad3: Array = []
	for pid in c2:
		var owned: bool = pid == "stone" or pid == "lava"
		var want_lv: String = "Lv.4" if pid == "stone" else "Lv.1"
		var want_free: String = "" if owned else "限免"
		if str(c2[pid]["lv"]) != want_lv or str(c2[pid]["free"]) != want_free:
			bad3.append("%s %s/%s" % [pid, str(c2[pid]["lv"]), str(c2[pid]["free"])])
	_ok("S3 ★拥有的: 服务器等级(stone Lv.4、lava Lv.1)不挂角标; 限免的 7 只: Lv.1 +「限免」", bad3.is_empty() and c2.size() == 9, str(bad3))
	_ok("S3 右栏默认看的那只也是能上场的(不是龟池里没有的小龟)", allowed.has(str(ts.detail_pet_id)), str(ts.detail_pet_id))
	## S4
	var outside := ""
	for p in WeeklyFree.ALL:
		if not allowed.has(p):
			outside = p
			break
	ts._on_clear_all()
	ts._on_pick_pet(outside)
	_ok("S4 ★点一只不能上场的(%s) ⇒ 进不了阵容" % outside, not (ts.team as Array).has(outside), str(ts.team))
	ts._on_drop_pet(outside, 0)
	_ok("S4 ★拖一只不能上场的到统领位 ⇒ 进不了", not (ts.team as Array).has(outside), str(ts.team))
	var fr := WeeklyFree.free_ids(ACCT, WEEK, ["stone", "lava"])
	ts._on_pick_pet("stone")
	ts._on_pick_pet(fr[0])
	_ok("S4 能上场的(拥有 stone、限免 %s)照常进" % fr[0], (ts.team as Array).has("stone") and (ts.team as Array).has(fr[0]), str(ts.team))
	ts.team = ["stone", outside, fr[0]]
	ts._drop_disallowed()
	_ok("S4 ★阵容里混进不能上场的 ⇒ 拿掉(上次阵容 / 草稿恢复走同一个)", not (ts.team as Array).has(outside)
		and (ts.team as Array).has("stone"), str(ts.team))
	## S5 文案
	var txt: Array = _texts(ts)
	var bad5: Array = []
	for t in txt:
		var s := str(t)
		if s.contains("主站") or s.contains("龟币") or s.contains("金额") or s.begins_with("你") or s.begins_with("您"):
			bad5.append(s)
	_ok("S5 角标字 = 「限免」; 页面上没有「主站 / 龟币 / 金额」、没有「你 / 您」开头(%d 段字)" % txt.size(),
		bad5.is_empty() and txt.has("限免") and txt.size() >= 20, str(bad5))
	ts.queue_free()
	await _frames(3)

	# ── S6 问到服务器: 新拥有一只限免龟 ──
	var newly: String = fr[1]
	PetLevelsNet.override = {"linked": true, "owned": ["stone", "lava", newly], "levels": {"stone": {"lv": 4, "xp": 300}}}
	ts = await _open()
	var c6 := _cards(ts)
	var allowed6 := WeeklyFree.allowed_ids(ACCT, WEEK, ["stone", "lava", newly])
	_ok("S6 ★新拥有 %s ⇒ 龟池 = 新的拥有 ∪ 限免、它不再挂角标" % newly, c6.size() == allowed6.size() and c6.has(newly)
		and str(c6[newly]["free"]) == "" and str(c6[newly]["lv"]) == "Lv.1", str(c6.get(newly, {})))
	ts.queue_free()
	await _frames(3)

	PetLevelsNet.override = {}
	PetLevelsNet.owned = []
	GameState.account_id = acct0
	GameState.week_anchor_ts = wk0
	GameState.pet_lv = {}
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 选龟页拥有 ∪ 限免" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
