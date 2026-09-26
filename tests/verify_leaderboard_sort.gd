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
		"origin": Backend.ORIGIN_REMOTE, "profile": {"name": name},
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
	var p1 := {Backend.POOL_KEY: {"3": [_g("低胜高命", 2, 8, 9), _g("高胜低命", 7, 1, 0)]}}
	var r1 := Backend.leaderboard(p1, "我", 0, 0, 0, 99)
	var n1 := _names(r1)
	_chk("① ★分母: 三行都在(自己 + 两份快照)", r1.size() == 3, str(n1))
	_chk("① ★胜场是第一键(高胜在前, 哪怕它命少横扫也少)",
		n1.find("高胜低命") < n1.find("低胜高命"), str(n1))

	## ② 第二层: 胜场相同 ⇒ 比余命(横扫故意反着给)
	var p2 := {Backend.POOL_KEY: {"3": [_g("同胜低命", 5, 2, 9), _g("同胜高命", 5, 7, 0)]}}
	var n2 := _names(Backend.leaderboard(p2, "我", 0, 0, 0, 99))
	_chk("② ★胜场相同 ⇒ 余命多的在前(哪怕它横扫少)",
		n2.find("同胜高命") < n2.find("同胜低命"), str(n2))

	## ③ 第三层(方案书点名的那组): 同胜同命、横扫不同
	var p3 := {Backend.POOL_KEY: {"3": [_g("横扫少", 5, 5, 1), _g("横扫多", 5, 5, 6), _g("横扫中", 5, 5, 3)]}}
	var n3 := _names(Backend.leaderboard(p3, "我", 0, 0, 0, 99))
	_chk("③ ★同胜同命 ⇒ 横扫多的在前(多→中→少)",
		n3.find("横扫多") < n3.find("横扫中") and n3.find("横扫中") < n3.find("横扫少"), str(n3))

	## ④ 旧快照缺字段 ⇒ 当 0, 不崩也不作废
	var old := {"schema_ver": Backend.SCHEMA_VER, "ghost_id": "r_old", "is_bot": false,
		"origin": Backend.ORIGIN_REMOTE, "profile": {"name": "老快照"}}
	var p4 := {Backend.POOL_KEY: {"3": [old, _g("新快照", 3, 3, 3)]}}
	var r4 := Backend.leaderboard(p4, "我", 0, 0, 0, 99)
	var n4 := _names(r4)
	_chk("④ ★分母: 老快照没被丢掉(旧池不作废)", n4.has("老快照"), str(n4))
	_chk("④ ★缺字段当 0 ⇒ 排在有成绩的后面", n4.find("新快照") < n4.find("老快照"), str(n4))

	## ⑤ 自己也参与排序(不是永远置顶)
	var p5 := {Backend.POOL_KEY: {"3": [_g("比我强", 9, 9, 9)]}}
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

	## ══════════════════════════════════════════════════════════════════
	## ⑦ ★★★两条 2026-09-26 从真数据量出来的: 榜上不许有【我自己】和【陪练】
	##
	## ⑦a **自己的历史快照**: `ghost_id` 带**场次**这一维(A6), 而 `pool_add` 只按精确
	##     id 去重 ⇒ 同一个玩家**每个场次各占一条**, 且快照里的 `profile.name`
	##     就是他自己的昵称 ⇒ 一周打 N 场, 榜上 N 行同一个名字, 而面板只画 11 行。
	##     跨周还会叠(`start_new_season` 不碰 ghost 池) ⇒ 周一榜首是**上周的自己**,
	##     而「◀ 你」被钉在末行显示 0 胜。
	##     ★同文件三处匹配路径都有 `_is_self_ghost`, 只有 `leaderboard()` 漏了。
	##
	## ⑦b **陪练**: 种子池 396 条原来一律按 0/0/0 参与排序并**占掉名次**
	##     ⇒ 10 个人测试看到「#57 你」这种数字(分母 ~400 不是 10)。
	##
	## ★为什么原来的 ①~⑥ 守不住: 它们的池子里**既没有自己的快照、也没有陪练**
	##   —— 每组 1~3 条、全是 `origin=remote` 且名字互不相同
	##   (memory fb-gate-subject-never-constructed)。
	## ══════════════════════════════════════════════════════════════════
	print("── ⑦ 榜上不许有【我自己】和【陪练】 ──")
	var mine: Array = []
	for bt in range(4):
		var g7 := _g("我自己", 7 + bt, 5, 1)
		g7["ghost_id"] = "mine_b%d" % bt
		g7["origin"] = Backend.ORIGIN_LOCAL          # ★本机产的 = 自己那份
		mine.append(g7)
	var bot7 := _g("陪练", 0, 0, 0)
	## ★★陪练那一份要**长得和真种子池一模一样**。我第一版写 `is_bot = true`
	##   ⇒ 门禁绿, **而真机上一条都没滤掉**: 种子池 396 条的 `is_bot` 实测全是 **false**
	##   (队列模拟跑出来的"真玩家"数据)。⇒ 判据在测我自己喂进去的那个字段。
	## ★现在按**产品自己认种子的那条**(`seed_` 前缀)造, 并**刻意把 `is_bot` 留成 false**。
	bot7["is_bot"] = false
	bot7["ghost_id"] = "seed_autoplay_coh_s0_41_b24"
	var p7 := {Backend.POOL_KEY: {"3": mine + [bot7, _g("别人", 6, 4, 0)]}}
	var r7: Array = Backend.leaderboard(p7, "我", 3, 8, 0, 99)
	var n7 := _names(r7)
	_chk("⑦ ★分母: 池子里确实放了 4 条自己的 + 1 条陪练 + 1 个别人",
		(p7[Backend.POOL_KEY]["3"] as Array).size() == 6)
	_chk("⑦a ★★★自己的历史快照一条都不上榜(否则榜上 N 行同一个名字)",
		not n7.has("我自己"), str(n7))
	_chk("⑦b ★★★陪练不上榜(否则名次分母是 ~400 不是 10)",
		not n7.has("陪练"), str(n7))
	_chk("⑦ ★★分母: 别人**还在**榜上(证明上面两条不是把所有人都滤光了)",
		n7.has("别人"), str(n7))
	_chk("⑦ ★★分母: 「我」那一行还在(它是注入的, 不该被这两道筛带走)",
		n7.has("我"), str(n7))
	_chk("⑦ ★★名次的分母就是真人数: 2 行(别人 + 我)", r7.size() == 2, "%d 行" % r7.size())

	## ★★★最后拿**真种子池**量一遍 —— 上面全是合成快照, 而这个 bug 正是
	##   「合成的能滤掉、真的滤不掉」。不读真文件就永远发现不了
	##   (是真机上点开排行榜看见 11 行里 10 行是陪练才拓出来的)。
	var seedp: Dictionary = Backend.load_pool()
	var seed_rows: Array = Backend.leaderboard(seedp, "我", 0, 0, 0, 9999)
	var seed_n := 0
	for b8 in (seedp.get(Backend.POOL_KEY, {}) as Dictionary):
		seed_n += ((seedp[Backend.POOL_KEY] as Dictionary)[b8] as Array).size()
	_chk("⑦ ★分母: 真池子里确实有一堆种子(否则下面是空检查)", seed_n >= 100, "%d 条" % seed_n)
	_chk("⑦ ★★★**真种子池**上榜的行数 = 1(只有我自己那行) —— 合成的滤得掉不等于真的滤得掉",
		seed_rows.size() == 1, "%d 行 / 池里 %d 条" % [seed_rows.size(), seed_n])

	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 终榜排序 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
