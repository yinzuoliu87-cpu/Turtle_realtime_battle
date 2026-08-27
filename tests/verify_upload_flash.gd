extends Node
## verify_upload_flash.gd — 结算屏「阵容已上传」的一次性正反馈 (2026-08-27)
##
## 用户 2026-08-27 定的口径:
##   · 上传**成功** → 结算屏显示一句「阵容已上传」
##   · 上传**失败 / 断网** → **什么都不显示**, 体验与"没有这个功能"一模一样
##   （明确**不做**"在线/离线"状态灯: 根本不存在两种模式, 一个"离线"角标等于
##     告诉玩家"你是残缺状态去修"，而服务器在海外、国内玩家多半修不了。）
##
## ★判据落在【结算屏上真的有一个可见的 Label 写着这句话】——
##   不是"标记被置位了"(那是数我自己插的钩子, memory [[fb-gate-must-measure-requirement-not-my-hook]])。
##
## ★★这份门禁最要紧的是**反面那条**: 没成功时必须【一个字都不显示】。
##   只验"成功了会显示"守不住"失败了也显示" —— 而后者正好是用户明确否掉的那种设计。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_upload_flash.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RemotePool := preload("res://scripts/net/remote_pool.gd")
const HUD := preload("res://scripts/scenes/battle/battle_hud.gd")

const WANT := "阵容已上传"

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 递归找结算卡片里【可见且写着那句话】的 Label。返回 null = 没有。
func _find_flash(root: Node):
	var stk: Array = [root]
	while not stk.is_empty():
		var n = stk.pop_back()
		if n is Label and str((n as Label).text).find(WANT) >= 0:
			if (n as Label).is_visible_in_tree():
				return n
		for c in n.get_children():
			stk.append(c)
	return null


## 结算卡片里【所有】Label 的文字 —— 用来做分母(证明卡片真的建起来了)。
func _all_text(root: Node) -> Array:
	var out: Array = []
	var stk: Array = [root]
	while not stk.is_empty():
		var n = stk.pop_back()
		if n is Label:
			out.append(str((n as Label).text))
		for c in n.get_children():
			stk.append(c)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 结算屏「阵容已上传」正反馈 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	## ★★必须走【玩家真正的入口】`_show_banner(won)` —— 那才是结算屏的建法。
	##   我第一版直接调 `_attach_upload_flash(card)`, 结果**把调用点删掉门禁照样全绿**
	##   ⇒ 那份门禁在保护一段死代码, 守不住"还有没有人调它"
	##   (memory [[fb-verify-must-run-the-real-path]]: 断言函数存在 ≠ 断言有人调)。
	_s._hud._show_banner(true)
	await get_tree().process_frame
	await get_tree().process_frame
	## 结算卡挂在 HUD 的 CanvasLayer 下 —— 从那儿往下找, 而不是自己造个 Control。
	var card: Node = _s._hud._layer if _s._hud.get("_layer") != null else _s
	_ok("★分母: 走真入口 _show_banner 之后, 结算层里真的建出东西了",
		card != null and card.get_child_count() > 0,
		"子节点 %d 个" % (card.get_child_count() if card != null else -1))

	## ── 分母: 那一行真的被挂上去了(不管可不可见) ──
	var texts := _all_text(card)
	_ok("★分母: 结算卡片上挂了写着「%s」的 Label(共 %d 个 Label)" % [WANT, texts.size()],
		texts.size() > 0 and str(texts).find(WANT) >= 0, str(texts))

	## ── ① 没有回执时: 一个字都不许显示 ──
	## 这是用户明确要的那一半 —— 失败/断网时体验与"没有这个功能"一模一样。
	var waited := 0
	while waited < 12:
		await get_tree().process_frame
		waited += 1
	_ok("★★① 没上传成功时【完全不显示】(断网/失败的体验 = 没有这个功能)",
		_find_flash(card) == null,
		"实得 %s" % ("仍然是隐藏的" if _find_flash(card) == null else "竟然显示了!"))

	## ── ② 上传成功后: 那一行要真的【可见】 ──
	RemotePool._upload_flash = true
	## 轮询节奏是 0.4 秒一次 —— 等够两拍再判(墙钟, 不数帧: CI 帧率极高, 数帧会等不到)。
	var t0 := Time.get_ticks_msec()
	var found = null
	while Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
		found = _find_flash(card)
		if found != null:
			break
	_ok("★★② 上传成功后, 结算屏上【真的可见】那一行", found != null,
		"文字=%s" % (str((found as Label).text) if found != null else "没出现"))

	## ── ③ 旗子是【一次性】的: 取走之后不该再有第二次 ──
	## 不做这条的话, 一局打完弹一次、下一局没传成功也弹, 玩家会以为传了。
	_ok("★★③ 回执是一次性的(consume 之后再取是 false)",
		not RemotePool.consume_upload_flash(),
		"第二次取还有旗子 = 会重复弹")

	## ── ④ 失败【不】置旗 —— 从产品那条路验, 不是我手动 set ──
	## 把后端指到不可达地址, 真发一次上传, 断言旗子仍然是空的。
	RemotePool._upload_flash = false
	OS.set_environment(RemotePool.ENV_KEY, "http://127.0.0.1:9")
	var rp := RemotePool.new()
	add_child(rp)
	rp.upload(_snap())
	var w2 := 0
	while w2 < 900 and not RemotePool._upload_flash:
		await get_tree().process_frame
		w2 += 1
	_ok("★★④ 上传【失败】不置旗(真发一次到不可达地址, 等了 %d 帧)" % w2,
		not RemotePool._upload_flash,
		"失败却置了旗 = 断网也会弹「已上传」")
	rp.queue_free()
	OS.unset_environment(RemotePool.ENV_KEY)
	_done()


## 一份能过校验的快照(否则 upload() 会在本地就拒掉, 根本走不到网络那步)。
func _snap() -> Dictionary:
	var pid := str(RemotePool._TS.STATS.keys()[0])
	var eid := str(RemotePool._ES.STATS.keys()[0])
	return {
		"schema_ver": 2, "ghost_id": "g_1_" + pid, "is_bot": false, "bracket": 3,
		"profile": {"name": "玩家阵容", "avatar": pid, "id": "g_1_" + pid},
		"leaders": [pid], "pet_levels": {pid: 5},
		"equipped": {pid: [{"id": eid, "star": 1}]},
		"minions": {}, "loadouts": {}, "lane_assign": {},
		"season_total_battles": 12, "season_eggs_killed": 0,
		"chest_treasures_won": [], "chest_treasure_value": 0.0,
	}


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 6:
		print("  [FAIL] ★分母: 断言只有 %d 条(<6) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 结算屏上传正反馈" if _fail == 0 else "FAIL x%d — 结算屏上传正反馈" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
