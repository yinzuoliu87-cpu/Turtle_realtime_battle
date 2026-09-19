extends Node
## verify_leaderboard_sort.gd — A8：终榜按**字典序「胜场 → 余命 → 横扫」**排
##
## ★方案书门禁⑨: 构造同胜同命、横扫不同的三份快照, 断言顺序。
##   反向验证: 比较器改回只比碎蛋数 ⇒ ⑨ 红。
##
## ★★判据要把【字典序】的三层都压住, 不能只验"横扫多的在前" ——
##   只验最后一层的话, 「无视胜场只比横扫」这种改法也能绿。
##   ⇒ 三层各造一组: 胜场不同 / 胜场同·余命不同 / 胜场余命都同·横扫不同。
##
## ★旧快照缺这三个字段要当 0(不作废旧池) —— 单列一条验它。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_leaderboard_sort.tscn --quit-after 900

const Backend := preload("res://scripts/net/backend.gd")

var _ok := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

func _g(name: String, wins: int, hearts: int, sweeps: int) -> Dictionary:
	return {"schema_ver": Backend.SCHEMA_VER, "ghost_id": "r_" + name, "is_bot": false,
		"bracket": 3, "origin": Backend.ORIGIN_REMOTE, "profile": {"name": name},
		"season_wins": wins, "hearts": hearts, "season_sweeps": sweeps}

func _names(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str((r as Dictionary).get("name", "?")))
	return out

func _ready() -> void:
	await get_tree().process_frame
	print("── A8: 终榜字典序 胜场 → 余命 → 横扫 ──")

	## ① 第一层: 胜场不同 ⇒ 胜场多的在前(其余两键故意反着给, 挡住"只看后面那两键")
	var p1 := {"brackets": {"3": [_g("低胜高命", 2, 8, 9), _g("高胜低命", 7, 1, 0)]}}
	var r1 := Backend.leaderboard(p1, "我", 0, 0, 0, 99)
	var n1 := _names(r1)
	_chk("① ★分母: 三行都在(自己 + 两份快照)", r1.size() == 3, str(n1))
	_chk("① ★胜场是第一键(高胜在前, 哪怕它命少横扫也少)",
		n1.find("高胜低命") < n1.find("低胜高命"), str(n1))

	## ② 第二层: 胜场相同 ⇒ 比余命(横扫故意反着给)
	var p2 := {"brackets": {"3": [_g("同胜低命", 5, 2, 9), _g("同胜高命", 5, 7, 0)]}}
	var n2 := _names(Backend.leaderboard(p2, "我", 0, 0, 0, 99))
	_chk("② ★胜场相同 ⇒ 余命多的在前(哪怕它横扫少)",
		n2.find("同胜高命") < n2.find("同胜低命"), str(n2))

	## ③ 第三层(方案书点名的那组): 同胜同命、横扫不同
	var p3 := {"brackets": {"3": [_g("横扫少", 5, 5, 1), _g("横扫多", 5, 5, 6), _g("横扫中", 5, 5, 3)]}}
	var n3 := _names(Backend.leaderboard(p3, "我", 0, 0, 0, 99))
	_chk("③ ★同胜同命 ⇒ 横扫多的在前(多→中→少)",
		n3.find("横扫多") < n3.find("横扫中") and n3.find("横扫中") < n3.find("横扫少"), str(n3))

	## ④ 旧快照缺字段 ⇒ 当 0, 不崩也不作废
	var old := {"schema_ver": Backend.SCHEMA_VER, "ghost_id": "r_old", "is_bot": false,
		"bracket": 3, "origin": Backend.ORIGIN_REMOTE, "profile": {"name": "老快照"}}
	var p4 := {"brackets": {"3": [old, _g("新快照", 3, 3, 3)]}}
	var r4 := Backend.leaderboard(p4, "我", 0, 0, 0, 99)
	var n4 := _names(r4)
	_chk("④ ★分母: 老快照没被丢掉(旧池不作废)", n4.has("老快照"), str(n4))
	_chk("④ ★缺字段当 0 ⇒ 排在有成绩的后面", n4.find("新快照") < n4.find("老快照"), str(n4))

	## ⑤ 自己也参与排序(不是永远置顶)
	var p5 := {"brackets": {"3": [_g("比我强", 9, 9, 9)]}}
	var n5 := _names(Backend.leaderboard(p5, "我", 1, 1, 1, 99))
	_chk("⑤ ★自己按真实成绩排, 不置顶", n5.find("比我强") < n5.find("我"), str(n5))

	## ── ⑥ ★★生产侧: `build_ghost_snapshot` 真的把这三个字段写进快照了吗 ──
	##   ★★这条是补上来的: 第一版全部用测试自己造的快照(`_g()`), **从来没走过生产的
	##   快照生成函数** ⇒ 变异「把三个字段从 build_ghost_snapshot 里删掉」**一条都没红**。
	##   典型的「判据没错但被测对象不在场」/「写了没人读」同族 —— 排序器再对,
	##   生产侧不写这三个字段, 线上所有人的榜都是 0/0/0。
	var snap = Backend.build_ghost_snapshot("probe_snap", {})
	_chk("⑥ ★分母: 生产的 build_ghost_snapshot 返回了字典", snap is Dictionary)
	if snap is Dictionary:
		var sd: Dictionary = snap
		for key in ["season_wins", "hearts", "season_sweeps"]:
			_chk("⑥ ★快照带了排序键 `%s`(生产侧不写它, 线上榜就全是 0)" % key,
				sd.has(key), "keys=%d" % sd.size())

	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 终榜排序 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
