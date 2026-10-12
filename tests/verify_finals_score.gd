extends Node
## verify_finals_score.gd —— 周日对阵图比分(2026-10-12 · 方案书 docs/plans/20261012-对阵图对照参考改版.md §二)
##
## 用户:「比分呢」「要做」。一场 = 上路 + 下路(1:1 再打终极) ⇒ 比分只有 2:0 / 2:1 ⇒ 服务端只存「败方赢了几路」。
## ① 比分算法(纯函数 phase2_duallane.loser_lanes): 2:0 ⇒ 0 / 2:1 ⇒ 1 / 没打完 · 投降 · 终极没结果 ⇒ -1
## ② 回包解析: `scores` 进组数据; 当前轮(没收盘)不收 —— 与 done 同一道过滤
## ③ 上报: 结果报成功后紧接着补报比分(rpc/finals_report_score, 带 seed); 没有比分(-1)只发结果那一个
## ④ 画: 有比分 ⇒ 每场两枚比分方块(2 与败方路数); 没有 ⇒ 一枚都不画
## ⑤ 服务端迁移: 只认 seed 与采纳那份相同的(P9 两边各打各的, 另一份的比分对不上采纳的胜负)

const DL := preload("res://scripts/gamedata/phase2_duallane.gd")
const SB := preload("res://scripts/net/supabase.gd")
const SCENE := preload("res://scripts/scenes/BracketMapScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日对阵图比分 ===")
	## ① 算法
	_ok("① 两路同一方全胜 ⇒ 2:0 ⇒ 败方 0 路", DL.loser_lanes({"top": "left", "bottom": "left"}) == 0)
	_ok("① 1:1 打终极 ⇒ 2:1 ⇒ 败方 1 路", DL.loser_lanes({"top": "left", "bottom": "right", "final": "right"}) == 1)
	_ok("① ★投降(空)⇒ -1 不报", DL.loser_lanes({}) == -1)
	_ok("① ★1:1 而终极没结果 ⇒ -1 不报", DL.loser_lanes({"top": "left", "bottom": "right"}) == -1)
	_ok("① 只打了一路 ⇒ -1", DL.loser_lanes({"top": "left"}) == -1)

	## ② 解析
	var body := JSON.stringify({"ok": true, "bucket": 3, "n": 4, "round": 2, "closed": false,
		"entrants": [{"seed": 0, "name": "甲"}, {"seed": 1, "name": "乙"}, {"seed": 2, "name": "丙"}, {"seed": 3, "name": "丁"}],
		"done": {"1-0": 0, "1-1": 1}, "scores": {"1-0": 1, "1-1": 0, "2-0": 1}})
	var bk: Dictionary = SB.parse_finals(true, 200, body, "uid-x", 1)
	var sc: Dictionary = bk.get("scores", {})
	_ok("② ★分母: 解析出了组", int(bk.get("size", 0)) == 4, str(bk.keys()))
	_ok("② 已翻面那两场的比分在", int(sc.get("1-0", -1)) == 1 and int(sc.get("1-1", -1)) == 0, str(sc))
	_ok("② ★当前轮(2-0)不收(与 done 同一道过滤)", not sc.has("2-0"), str(sc))

	## ③ 上报: 后端临时打开 + 注入传输(不碰网络)
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	var gs = get_node_or_null("/root/GameState")
	var acc0 := str(gs.account_id) if gs != null else ""
	if gs != null:
		gs.test_mode = true
		gs.account_id = "uid-me"
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	var sent: Array = []
	SB._transport_for_test = func(_m, u, _h, b, cb):
		sent.append({"u": str(u), "b": str(b)})
		cb.call({"ok": true, "code": 200, "body": "{}"})
	_ok("③ ★分母: 后端真的打开了", SB.enabled())
	SB.finals_report_clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 1, 0, 4242, 1)
	for _i in range(6):
		await get_tree().process_frame
	_ok("③ ★报结果 + 补报比分 = 两个请求", sent.size() == 2, str(sent.map(func(x): return x["u"].get_file())))
	if sent.size() == 2:
		_ok("③ 第一个是 finals_report", sent[0]["u"].ends_with("/rpc/finals_report"))
		_ok("③ 第二个是 finals_report_score", sent[1]["u"].ends_with("/rpc/finals_report_score"))
		var j = JSON.parse_string(sent[1]["b"])
		_ok("③ ★比分请求带的 seed 与报结果那份同一个(服务端靠它认采纳的那份)",
			j is Dictionary and int(j.get("p_seed", 0)) == 4242 and int(j.get("p_loser_lanes", -1)) == 1, str(j))
	sent.clear()
	SB.finals_report_clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 2, 0, 4243, -1)
	for _i in range(6):
		await get_tree().process_frame
	_ok("③ ★没有比分(-1)⇒ 只发结果那一个", sent.size() == 1, str(sent.size()))
	SB._transport_for_test = Callable()
	SB.finals_report_clear()
	SB._report_inflight = false
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if gs != null:
		gs.account_id = acc0

	## ④ 画
	var m = SCENE.new()
	add_child(m)
	await get_tree().process_frame
	m.set_data({"size": 4, "round": 2, "me": -1, "names": ["甲", "乙", "丙", "丁"],
		"done": {"1-0": 0, "1-1": 1}, "scores": {"1-0": 1, "1-1": 0}, "bucket": 3}, {}, 0)
	await get_tree().process_frame
	print("  [量] ws 1-0=%d 1-1=%d  match_state 1-0=%s 1-1=%s" % [m.winner_side(1, 0), m.winner_side(1, 1), m.match_state(1, 0), m.match_state(1, 1)])
	var labs: Array = m.find_children("Score*", "Label", true, false)
	var txt: Array = labs.map(func(x): return (x as Label).text)
	txt.sort()
	_ok("④ ★有比分 ⇒ 两场四枚方块(2,2 与败方 1,0)", txt == ["0", "1", "2", "2"], str(txt))
	m.set_data({"size": 4, "round": 2, "me": -1, "names": ["甲", "乙", "丙", "丁"],
		"done": {"1-0": 0, "1-1": 1}, "bucket": 3}, {}, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var labs2: Array = m.find_children("Score*", "Label", true, false).filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	_ok("④ ★没有比分 ⇒ 一枚都不画(不画个假的 0)", labs2.is_empty(), str(labs2.size()))
	m.queue_free()

	## ⑤ 服务端迁移(静态)
	var sql := FileAccess.get_file_as_string("res://server/supabase/migrations/20261012_finals_scores.sql")
	_ok("⑤ ★分母: 迁移文件在", sql.length() > 1000)
	_ok("⑤ ★★只认 seed 与采纳那份相同的(and seed_used = p_seed)", sql.find("and seed_used = p_seed and loser_lanes is null") >= 0)
	_ok("⑤ 两个视图都下发 scores(组 / 杯 / 我那组 共 3 处)", sql.count("'scores', ") == 3, str(sql.count("'scores', ")))
	_ok("⑤ anon 没有执行权", sql.find("finals_report_score(bigint, int, int, int, bigint, int) from public, anon") >= 0)

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
