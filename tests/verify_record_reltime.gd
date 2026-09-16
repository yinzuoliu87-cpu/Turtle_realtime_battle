extends Node
## verify_record_reltime.gd — 战绩屏「多久之前」的单位必须和写入侧一致
##
## ══════════════════════════════════════════════════════════════════════
##  由来（2026-09-17，查大轮赛制 v2 的 §8 E2「夏令时」时顺手撞上的现成 bug）
## ══════════════════════════════════════════════════════════════════════
## 写入侧 `RealtimeBattle3DScene.gd:7582` 存的是【秒】：
##     gs.match_history[0]["ts"] = int(Time.get_unix_time_from_system())
## 而读取侧 `RecordScene._rel_time` 原来拿【毫秒】去减它：
##     var d := int(Time.get_unix_time_from_system() * 1000.0) - ts
## ⇒ 差值恒等于"当前毫秒数"本身 ⇒ **刚打完的一局显示「20691 天前」**。
## 用户存档里 50 条战绩的 ts 实测全是秒（`1788701132.0` 这种），所以修的是读取侧。
##
## **这块以前零门禁覆盖** —— 全仓没有任何测试碰过 `_rel_time`，所以它坏了很久没人发现。
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁的判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★不在测试里自己挑一个单位去喂 —— 那只能验"我喂的和我判的一致"，是恒真式。
##   要拴住的是【写入侧和读取侧两个真实现】，所以：
##     ① 走**真结算** `_settle_season(true)` 让产品自己写一条战绩（ts 由产品决定单位）
##     ② 把产品写出来的那个 ts 喂给**真渲染函数** `RecordScene._rel_time`
##     ③ 断言渲染结果是「刚刚」
##   任何一侧把单位改了，这条都会红。
## ★阈值用的偏移量（60 / 3600 / 86400 秒）在本文件里**写死**，不从产品常量取。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RecordSceneScript := preload("res://scripts/scenes/RecordScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 战绩屏「多久之前」 ===")

	var rs = RecordSceneScript.new()      # 只调纯函数, 不进树

	# ── ① 分母: 产品真的写得出一条带 ts 的战绩 ──
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame
	gs.season_start_ts = int(Time.get_unix_time_from_system())   # 防赛季过期滚动
	gs.season_leaders = ["basic", "stone", "ice"]                # _had_season=true
	gs.hearts = 8
	var n0: int = (gs.match_history as Array).size() if gs.match_history is Array else -1
	scene._settle_season(true)
	var n1: int = (gs.match_history as Array).size() if gs.match_history is Array else -1
	_ok("① ★分母: 走真结算后战绩多了一条", n1 == n0 + 1, "%d → %d" % [n0, n1])
	if n1 <= 0:
		_done(rs, scene)
		return
	var rec: Dictionary = (gs.match_history as Array)[0]
	var ts: int = int(rec.get("ts", 0))
	_ok("① ★分母: 这条战绩带了 ts 且不为 0", ts > 0, "ts=%d" % ts)

	# ── ② 真正的判据: 产品写的 ts 喂给产品的渲染函数, 必须是「刚刚」 ──
	#    这一条同时拴住写入侧与读取侧 —— 任一侧改单位都会红。
	var now_txt: String = rs._rel_time(ts)
	_ok("② ★刚打完的一局显示「刚刚」(写入侧与读取侧单位一致)",
		now_txt == "刚刚", "实际显示「%s」(ts=%d)" % [now_txt, ts])

	# ── ③ 各档阈值(偏移量在本文件写死, 不从产品取) ──
	_ok("③ 2 小时前", rs._rel_time(ts - 7200) == "2 小时前", "实际「%s」" % rs._rel_time(ts - 7200))
	_ok("③ 3 天前", rs._rel_time(ts - 3 * 86400) == "3 天前", "实际「%s」" % rs._rel_time(ts - 3 * 86400))
	_ok("③ 5 分钟前", rs._rel_time(ts - 300) == "5 分钟前", "实际「%s」" % rs._rel_time(ts - 300))
	# 边界: 59 秒仍是「刚刚」, 61 秒进「分钟前」
	_ok("③ 59 秒 → 刚刚", rs._rel_time(ts - 59) == "刚刚", "实际「%s」" % rs._rel_time(ts - 59))
	_ok("③ 61 秒 → 1 分钟前", rs._rel_time(ts - 61) == "1 分钟前", "实际「%s」" % rs._rel_time(ts - 61))

	# ── ④ 没有 ts 的老记录不显示(空串), 不是显示一个假时间 ──
	_ok("④ ts=0(老记录) → 空串", rs._rel_time(0) == "", "实际「%s」" % rs._rel_time(0))

	_done(rs, scene)


func _done(rs, scene) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if rs != null:
		rs.free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 战绩「多久之前」" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
