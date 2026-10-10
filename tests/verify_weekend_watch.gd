extends Node
## verify_weekend_watch — 周末观战第三轮(2026-10-07, 用户「回放我说最重要的是周六周日啊，观看别人的啊」)
## 方案书: docs/plans/20261005-回放体验打磨.md「第三轮」。
##
## 量的是**真场景**(GauntletBoard.tscn / BracketMap.tscn, 走它们自己的喂数入口 set_rows / set_data / set_week):
##   ① 周六赛况板: 每张对局卡上有「观看」⇔ 这一场有录像(`Board.watchable`); 有的那颗短边 ≥ 81;
##      卡上双方各三只统领头像(阵容来自查询里的 la / ra); 战绩榜每行有头像
##   ② 周日对阵图: 每一场已揭晓的对局都有一颗「观看」(短边 ≥ 81, 字是「观看」); 未揭晓的一颗都没有;
##      每一格两侧都有头像节点; 喂了 #ID → 头像的人画的是那只龟, 没喂的画名字首字
##   ③ 空态: 没数据时两屏都是正中一块提示框(不是一行裸字), 框里的字就是那句话
##   ①b 版本闸(2026-10-10): 「最近对局」/「正在打」卡 —— 版本不同 ⇒ 没有按钮、灰签「版本不同」; 相同 / 不知道 ⇒ 按钮照旧
## ★每条断言都带分母(卡数 / 场数 / 头像数), 防 0 张卡也全绿。

const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const B := preload("res://scripts/gamedata/bracket.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const TOUCH := 81.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 周末观战: 赛况板对局卡 / 对阵图观看木牌 / 头像 / 空态 ===")
	await _t_board()
	await _t_bracket()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 周末观战" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 头像节点(`MatchCard.avatar` 打了 meta "Portrait")。`deep` = 递归。
func _portraits(n: Node, deep: bool = true) -> Array:
	var out: Array = []
	for c in n.find_children("*", "PanelContainer", deep, false):
		if (c as Node).has_meta("Portrait"):
			out.append(c)
	return out


func _short(c: Control) -> float:
	var r := c.get_global_rect()
	return minf(r.size.x, r.size.y)


# ① ─────────────────────────────────────────────────────────────
func _rows() -> Array:
	var ppl := []
	for i in range(6):
		ppl.append({"name": "选手%d" % i, "tag": P2C.player_tag("acct-w%d" % i), "avatar": "basic", "id": "g_%d" % i})
	var lu := ["stone", "bamboo", "ice"]
	var rows: Array = []
	for k in range(5):
		## 第 3 张(k == 2)的 match_id 不是 uuid ⇒ 不该有「观看」
		var id := ("%08d-1111-4222-8333-%012d" % [k + 1, k + 1]) if k != 2 else "legacy-%d" % k
		rows.append({"match_id": id, "created_at": "2026-10-03T1%d:00:00+00:00" % k,
			"result": {"won": k % 2 == 0, "gw": 2, "gl": 1}, "lp": ppl[k], "rp": ppl[(k + 1) % 6],
			"la": lu, "ra": lu, "rw": 1, "rl": 1})
	return rows


## ①b 版本闸(2026-10-10 内测前): 录下时的版本已知且与本机不同 ⇒ 卡上没有按钮、换成灰签「版本不同」;
##   相同 ⇒ 按钮照旧; 不知道(老行没有 client_version)⇒ 照旧。「最近对局」与「正在打」两种卡各量一遍。
## 返回 {"btn": 按钮数, "off": 灰签数, "off_text": 灰签上的字}。
func _card_gate(c: Node, btn_name: String) -> Dictionary:
	var offs: Array = c.find_children(MatchCard.N_VER_OFF, "", true, false)
	var tx := ""
	for o in offs:
		for l in (o as Node).find_children("*", "Label", true, false):
			tx += str((l as Label).text)
	return {"btn": c.find_children(btn_name, "Button", true, false).size(), "off": offs.size(), "off_text": tx}


func _t_board_version(bs: Node) -> void:
	print("── ①b 版本闸 ──")
	var cur := ReplayRecorder.client_version()
	_ok("①b 分母: 本机版本号不是空的", cur != "" and cur != "0.0.1", cur)
	_ok("①b 纯判据: 相同 ⇒ 不拦 / 不同 ⇒ 拦 / 不知道 ⇒ 不拦",
		not Board.version_differs({"ver": cur}) and Board.version_differs({"ver": "0.0.1"})
		and not Board.version_differs({}) and not Board.version_differs({"ver": ""}))
	var all: Array = _rows()
	var vr: Array = [all[0], all[1], all[3]]
	vr[0]["client_version"] = cur
	vr[1]["client_version"] = "0.0.1"
	var want := {str(vr[0]["match_id"]): "same", str(vr[1]["match_id"]): "diff", str(vr[2]["match_id"]): "unknown"}
	bs.set_rows(vr)
	await _frames(6)
	var seen := {}
	for c in bs.find_children("GameCard*", "PanelContainer", true, false):
		var k := str(want.get(str((c as Node).get_meta("match_id", "")), ""))
		if k != "":
			seen[k] = _card_gate(c, "GameBtn")
	_ok("①b 分母: 三种行各一张「最近对局」卡", seen.size() == 3, str(seen.keys()))
	_ok("①b ★版本相同 ⇒「观看」照旧、没有灰签", seen.has("same") and int(seen["same"]["btn"]) == 1 and int(seen["same"]["off"]) == 0,
		str(seen.get("same", {})))
	_ok("①b ★★版本不同 ⇒ 没有「观看」, 换成灰签「版本不同」", seen.has("diff") and int(seen["diff"]["btn"]) == 0
		and int(seen["diff"]["off"]) == 1 and str(seen["diff"]["off_text"]) == "版本不同", str(seen.get("diff", {})))
	_ok("①b ★版本不知道(老行) ⇒「观看」照旧", seen.has("unknown") and int(seen["unknown"]["btn"]) == 1
		and int(seen["unknown"]["off"]) == 0, str(seen.get("unknown", {})))
	## 正在打: 三行直播(都还在心跳), 版本 同 / 不同 / 不知道
	var now: int = P2C.now_utc()
	var iso := Time.get_datetime_string_from_unix_time(now - 2) + "+00:00"
	var live: Array = []
	var lwant := {}
	var kinds := ["same", "diff", "unknown"]
	for k in range(3):
		var id := "%08d-2222-4333-8444-%012d" % [k + 1, k + 1]
		var lr := {"match_id": id, "started_at": iso, "updated_at": iso, "ended": false,
			"lp": vr[k]["lp"], "rp": vr[k]["rp"], "la": vr[k]["la"], "ra": vr[k]["ra"]}
		if k == 0:
			lr["client_version"] = cur
		elif k == 1:
			lr["client_version"] = "0.0.1"
		live.append(lr)
		lwant[id] = kinds[k]
	bs.set_live_rows(live)
	await _frames(6)
	var lseen := {}
	for c in bs.find_children("LiveCard*", "PanelContainer", true, false):
		var k2 := str(lwant.get(str((c as Node).get_meta("match_id", "")), ""))
		if k2 != "":
			lseen[k2] = _card_gate(c, "LiveBtn")
	_ok("①b 分母: 三种直播各一张「正在打」卡", lseen.size() == 3, str(lseen.keys()))
	_ok("①b ★直播版本相同 ⇒「观赛」照旧", lseen.has("same") and int(lseen["same"]["btn"]) == 1 and int(lseen["same"]["off"]) == 0,
		str(lseen.get("same", {})))
	_ok("①b ★★直播版本不同 ⇒ 没有「观赛」, 换成灰签「版本不同」", lseen.has("diff") and int(lseen["diff"]["btn"]) == 0
		and int(lseen["diff"]["off"]) == 1 and str(lseen["diff"]["off_text"]) == "版本不同", str(lseen.get("diff", {})))
	_ok("①b ★直播版本不知道 ⇒「观赛」照旧", lseen.has("unknown") and int(lseen["unknown"]["btn"]) == 1
		and int(lseen["unknown"]["off"]) == 0, str(lseen.get("unknown", {})))
	bs.set_live_rows([])
	await _frames(2)


func _t_board() -> void:
	print("── ① 周六赛况板 ──")
	var bs: Node = (load("res://scenes/GauntletBoard.tscn") as PackedScene).instantiate()
	add_child(bs)
	await _frames(3)
	## ③ 空态先量(门禁里后端关着 ⇒ no_backend)
	var np: Control = bs.find_child("NoticePanel", true, false) as Control
	_ok("③ 赛况板空态 ⇒ 正中一块提示框", np != null and np.visible and not (bs.get("_status") as Label).visible,
		str(np != null))
	if np != null:
		var tx := ""
		for l in np.find_children("*", "Label", true, false):
			tx += str((l as Label).text)
		_ok("③ 框里说的就是那句话(与 `_status.text` 同一份)", tx.find(str((bs.get("_status") as Label).text)) >= 0
			and str((bs.get("_status") as Label).text) != "", tx)
	bs.set_rows(_rows())
	await _frames(6)
	## ★顶上那行带晋级 / 出局人数(2026-10-10), 数字与榜上状态逐个数出来的对得上。
	var n_in := 0
	var n_out := 0
	for pp in bs.data.get("players", []):
		n_in += 1 if str(pp.get("state", "")) == P2C.GAUNTLET_IN else 0
		n_out += 1 if str(pp.get("state", "")) == P2C.GAUNTLET_OUT else 0
	var st_txt := str((bs.get("_status") as Label).text)
	_ok("① 顶上那行写出「晋级 %d · 出局 %d」(与榜上状态对得上)" % [n_in, n_out], st_txt.contains("晋级 %d · 出局 %d" % [n_in, n_out]), st_txt)
	_ok("③ 有数据 ⇒ 提示框收起", np != null and not np.visible)
	var games: Array = bs.data.get("games", [])
	var cards: Array = bs.find_children("GameCard*", "PanelContainer", true, false)
	_ok("① 分母: 5 场 = 5 张卡", games.size() == 5 and cards.size() == 5, "%d / %d" % [games.size(), cards.size()])
	var bad := 0
	var with_btn := 0
	var without := 0
	var short_bad := 0
	var por_bad := 0
	for c in cards:
		var mid := str((c as Node).get_meta("match_id", ""))
		var g: Dictionary = {}
		for x in games:
			if str(x["id"]) == mid:
				g = x
		var btns: Array = (c as Node).find_children("GameBtn", "Button", true, false)
		var want: bool = not g.is_empty() and Board.watchable(g)
		if (btns.size() == 1) != want or btns.size() > 1:
			bad += 1
		if btns.size() == 1:
			with_btn += 1
			var bt := btns[0] as Button
			if _short(bt) < TOUCH or str(bt.text) != "观看" or str(bt.get_meta("key", "")) != mid:
				short_bad += 1
		else:
			without += 1
		if _portraits(c).size() != 6:
			por_bad += 1
	_ok("① ★★「观看」⇔ 这一场有录像(Board.watchable), 一张卡至多一颗", bad == 0, "%d 张不对" % bad)
	_ok("① 分母: 有的 4 张 / 没有的 1 张(两边都量到)", with_btn == 4 and without == 1, "%d / %d" % [with_btn, without])
	_ok("① ★「观看」短边 ≥ 81、字是「观看」、key = 那一场", short_bad == 0, "%d 颗不对" % short_bad)
	_ok("① ★每张卡双方各三只头像(6 个 Portrait)", por_bad == 0, "%d 张不对" % por_bad)
	var with_tex := 0
	for c in cards:
		for pn in _portraits(c):
			for t in (pn as Node).get_children():
				if t is TextureRect and (t as TextureRect).texture != null:
					with_tex += 1
	_ok("① ★阵容头像真画出来了(la / ra → 贴图)", with_tex == 30, "%d / 30" % with_tex)
	## 行的节点名会被引擎改成 @…@(同名兄弟), 按 meta "tag" 认。
	var rows: Array = []
	for c in bs.find_children("*", "PanelContainer", true, false):
		if (c as Node).has_meta("tag"):
			rows.append(c)
	var rp := 0
	for r in rows:
		rp += _portraits(r).size()
	## ★选手5 只以对手身份出现过 ⇒ 不进榜(2026-10-10: 机器人的样子, 见 gauntlet_board.build) ⇒ 5 行。
	_ok("① 战绩榜每行一个头像", rows.size() == 5 and rp == 5, "%d 行 / %d 头像" % [rows.size(), rp])
	await _t_board_version(bs)
	bs.queue_free()
	await _frames(2)


# ② ─────────────────────────────────────────────────────────────
func _btn_at(m, r: int, mm: int) -> Button:
	for b in m._canvas.find_children("*", "Button", true, false):
		if (b as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return b
	return null


func _t_bracket() -> void:
	print("── ② 周日对阵图 ──")
	var now := 1789862400 + 12 * 3600
	var m: Node = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	add_child(m)
	m.set_data({}, {}, now)
	m.set_week({"buckets": []})
	await _frames(3)
	_ok("③ 对阵图空态 ⇒ 提示框可见, 字在框里", m._empty_box.visible and m._empty_lb.visible
		and m._empty_box.is_ancestor_of(m._empty_lb) and str(m._empty_lb.text) != "", str(m._empty_lb.text))
	var gr: Rect2 = m._empty_box.get_global_rect()
	_ok("③ 提示框高度贴着内容(不是被 0 宽折行撑成半屏)", gr.size.y < 220.0 and gr.size.y >= 100.0, str(gr.size))
	var ents: Array = []
	var nm := ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛"]
	for i in range(8):
		ents.append({"seed": i, "name": nm[i] + "龟", "account_id": "acct-%d" % i})
	var wv: Dictionary = SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": 1, "now": now,
		"buckets": [{"bucket": 0, "n": 8, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents}]}), "", now)
	m.set_week(wv)
	## 喂 #ID → 头像: 0..5 号有, 6 / 7 号没有(该画名字首字)
	var por := {}
	for i in range(6):
		por[P2C.player_tag("acct-%d" % i)] = "stone"
	m.set_portraits(por)
	await _frames(4)
	_ok("② 分母: 画的是 8 人那一组", int(m.cur().get("size", 0)) == 8, str(m.cur().get("size", 0)))
	var n := 8
	var done_n := 0
	var other_n := 0
	var bad: Array = []
	for r in range(1, B.rounds_for(n) + 1):
		for mm in range(B.matches_in_round(n, r)):
			var bt := _btn_at(m, r, mm)
			var holder: Node = bt.get_parent() if bt != null else null
			var pm: bool = holder != null and holder.find_child("PlayMark", false, false) != null
			if str(m.match_state(r, mm)) == MAP.ST_DONE:
				done_n += 1
				## 审图第三版: 整格就是热区(盖满这一格、短边 ≥ 81)、右沿一枚 ▶; 对阵图上没有「观看」字样的按钮
				var nr: Rect2 = L.node_rect(n, r, mm)
				if bt == null or not pm or _short(bt) < TOUCH or not bt.visible or str(bt.text) != "" 						or absf(bt.size.x - nr.size.x) > 1.0 or absf(bt.size.y - nr.size.y) > 1.0:
					bad.append("%d-%d %s" % [r, mm, ("btn %s ▶=%s" % [str(bt.size), pm]) if bt != null else "无按钮"])
			else:
				other_n += 1
				if bt != null:
					bad.append("%d-%d 未揭晓却有按钮" % [r, mm])
	var pm_all := 0
	for h in m._canvas.get_children():
		if (h as Node).find_child("PlayMark", false, false) != null:
			pm_all += 1
	_ok("② 分母: 已揭晓 4 场 / 未揭晓 3 场", done_n == 4 and other_n == 3, "%d / %d" % [done_n, other_n])
	_ok("② ★★已揭晓的每一格 = 整格热区(短边 ≥ 81) + 右沿 ▶; 未揭晓的没有热区", bad.is_empty(), str(bad))
	_ok("② ★▶ 只在能点的格子上(全图 ▶ 数 = 4)", pm_all == 4, str(pm_all))
	_ok("② ★对阵图上不挂「观看」按钮(用户「哪个游戏观赛按钮会这样弄？」)",
		m._canvas.find_children("*", "Button", true, false).all(func(x): return str((x as Button).text) == ""))
	## 点一格 ⇒ 弹出对局卡: 两边头像 + 名字, 「观看」+「关闭」; 「观看」= 原来那条路(match_opened)
	var opened: Array = []
	m.match_opened.connect(func(rr: int, mm2: int): opened.append(Vector2i(rr, mm2)))
	_btn_at(m, 1, 1).pressed.emit()
	await _frames(2)
	var pop: Node = m.find_child("MatchPopup", true, false)
	var go: Button = m.find_child("PopupGoBtn", true, false) as Button
	var cl: Button = m.find_child("PopupCloseBtn", true, false) as Button
	_ok("② ★点已揭晓那一格 ⇒ 弹出对局卡, 卡里「观看」(短边 ≥ 81) +「关闭」", pop != null and go != null and cl != null
		and str(go.text) == "观看" and _short(go) >= TOUCH, "%s %s" % [str(pop), str(go)])
	_ok("② 对局卡两边各一个头像", pop != null and _portraits(pop).size() == 2,
		str(_portraits(pop).size()) if pop != null else "")
	_ok("② 弹卡这一下还没开始取回放(要再按「观看」)", opened.is_empty(), str(opened))
	if go != null:
		go.pressed.emit()
		await _frames(2)
	_ok("② ★卡里「观看」⇒ 走原来那条路: match_opened(1, 1)", opened == [Vector2i(1, 1)], str(opened))
	_ok("② 按下后卡收起", m.find_child("MatchPopup", true, false) == null or not is_instance_valid(m._popup))
	## 「关闭」
	_btn_at(m, 1, 0).pressed.emit()
	await _frames(2)
	var cl2: Button = m.find_child("PopupCloseBtn", true, false) as Button
	if cl2 != null:
		cl2.pressed.emit()
	await _frames(2)
	_ok("② 「关闭」⇒ 卡收起, 不触发取回放", m._popup == null and opened.size() == 1, str(opened))
	## 头像: 每一格两侧各一个 Portrait
	var holders := 0
	var por_bad := 0
	var tex_n := 0
	var letter_n := 0
	for h in m._canvas.get_children():
		var ps: Array = _portraits(h, false)
		if ps.is_empty():
			continue
		holders += 1
		if ps.size() != 2:
			por_bad += 1
		for p in ps:
			for k in (p as Node).get_children():
				if k is TextureRect and (k as TextureRect).texture != null:
					tex_n += 1
				elif k is Label and str((k as Label).text) != "":
					letter_n += 1
	_ok("② ★每一格两侧各一个头像节点(7 格)", holders == 7 and por_bad == 0, "%d 格 / %d 格不对" % [holders, por_bad])
	## 第一轮 8 个人全在 + 第二轮 4 个人(胜者) ⇒ 12 个有人的坑; 庚(6)/辛(7)没喂头像 ⇒ 写首字。
	_ok("② ★喂了头像的人画龟, 没喂的写名字首字(不编造)", tex_n >= 8 and letter_n >= 2, "龟 %d / 首字 %d" % [tex_n, letter_n])
	m.queue_free()
	await _frames(2)
	## 我这一场(当前轮、对手已定): 格子上金色 ▶ +「对战」小签; 点了弹卡, 主按钮「开始对战」
	var mine: Dictionary = SB._bucket_from({"bucket": 0, "n": 8, "round": 2, "closed": false,
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}, "entrants": ents}, "acct-0", now)
	var m3 = MAP.new()
	add_child(m3)
	await get_tree().process_frame
	m3.set_data(mine, {}, now)
	await _frames(2)
	var b20 := _btn_at(m3, 2, 0)
	_ok("② 分母: 选手视角, 2-0 是我这一场且该开打", int(m3.cur().get("me", -1)) == 0 and m3.should_fetch_opponent(2, 0) and b20 != null)
	if b20 != null:
		_ok("② ★我这一场: 格子里有 ▶ 与「对战」小签(不另起按钮)",
			b20.get_parent().find_child("PlayMark", false, false) != null
			and b20.get_parent().find_child("PlayTag", false, false) != null and str(b20.text) == "")
		b20.pressed.emit()
		await _frames(2)
		var g3: Button = m3.find_child("PopupGoBtn", true, false) as Button
		_ok("② ★点我这一场 ⇒ 卡里主按钮是「开始对战」", g3 != null and str(g3.text) == "开始对战", str(g3))
	m3.queue_free()
	await _frames(2)
