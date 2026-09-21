extends Node
## verify_ghost_upload.gd — D-4a：每场都传 + 投降局不传（2026-09-21）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## E18 已定 2026-09-17：① **每场都传**（按 D5，**正式推翻 2026-08-27 的「打赢才传」**）；
## ② **投降局不传**。
##
## ★为什么要改：只传赢的 ⇒ **同场次的池子里只有赢家，越往后越偏强**。
##   而 D5 的匹配硬条件是「双方总场次相同」，池子偏了就配不到势均力敌的对手。
##
## ★**投降局不传**的代价 E18 记过，不是没想到：等于给了「不想让别人打到我的阵容就投降」的口子，
##   但投降要付**一条命 + 一个配额**，成本是真的。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★★① **走真入口** `_settle_season()`，量的是**本地 ghost 池有没有多一份**。
##     为什么能这么量：`Backend.upload_ghost()` 的第一件事就是写本地池
##     （远端那步是追加的、失败静默）。所以「本地池多了一份」= 上传这条路真的走到了。
##     ⚠ 不去断言「SupabaseNet 被调了几次」—— 那是**数我自己插的钩子**
##     （memory `fb-gate-must-measure-requirement-not-my-hook`）。
## ★★② **三态必须分得开**：赢了 +1 / **输了也 +1**（这就是本次改动）/ **投降 +0**。
##     只验「输了也传」的话，一个「无条件传」的实现连投降局也会传，照样绿。
## ★③ 行构造 `ghost_row_from_snapshot` 的**前提缺失分支**逐条喂：
##     缺 account_id / 缺周锚点 / 场次为负 ⇒ 返回 `{}` **不传**，
##     而不是填 0 或空串凑一行 —— 那会在服务端造出主键 `("",0,0)` 的垃圾行，
##     还会把别人的行覆盖掉。
## ★④ 上传回包记账：2xx 才升「阵容已上传」那面旗；非 2xx 不升。
##     这条反馈的全部设计是「成功了才吱一声，失败时体验与功能不存在一样」。
## ★⚠ 网络那一段验不到（门禁进程 `TURTLE_SUPABASE=" "`）。
##     真实往返是 2026-09-21 手工打 curl 验的，结论记在 CHANGELOG：
##     201 建行 / 同键再传 200 覆盖（不是 409）/ **拿 anon key 当 Bearer 写 → 401 RLS violation**。

const SB := preload("res://scripts/net/supabase.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const RP := preload("res://scripts/net/remote_pool.gd")

var _ok := 0
var _fail := 0
var _tree: SceneTree = null
var _bak := {}
## ★鬼影池要**自己备份还原**: `Backend.save_pool()` 直写 `user://ghost_pool.json`,
##   它**不走 `GameState.save()` 的 test_mode 闸** ⇒ 手动单跑会往玩家真实池里塞 3 个假阵容。
var _files_bak := {}
const GUARDED := ["user://ghost_pool.json", "user://savegame.json"]
var _touched: Array[String] = []
const KEYS := ["season_leaders", "left_team", "hearts", "week_phase", "lane_results",
	"season_total_battles", "season_wins", "season_eggs_killed", "ranked_used",
	"season_id", "account_id", "week_anchor_ts", "tutorial_active", "season_sweeps"]


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	_backup_files()
	print("=== D-4a 每场都传 ===")
	_t_row_builder()
	_t_flash()
	await _t_real_settle()
	for k in KEYS:
		GameState.set(k, _bak[k])
	SB._reset_upload_for_test()
	_restore_files()
	_chk("★收尾: test_mode 已掉回 true", bool(GameState.test_mode))
	_chk("★收尾: 两个存档文件逐字节还原了(含中途被建出来的 %d 个)" % _touched.size(),
		_files_restored(), _files_diff())
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-4a 每场都传" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ③ 行构造: 前提缺失就不传, 不凑残行
# ─────────────────────────────────────────────────────────────
## ★★为什么要备份文件而不是依赖 test_mode —— 见 ①② 那段长注释。
func _backup_files() -> void:
	for path in GUARDED:
		_files_bak[path] = (FileAccess.get_file_as_string(path)
			if FileAccess.file_exists(path) else null)


func _restore_files() -> void:
	for path in GUARDED:
		var had = _files_bak.get(path, null)
		if had == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(str(had))
				f.close()


func _files_restored() -> bool:
	for path in GUARDED:
		var had = _files_bak.get(path, null)
		if had == null:
			if FileAccess.file_exists(path):
				return false
		elif (not FileAccess.file_exists(path)) or FileAccess.get_file_as_string(path) != str(had):
			return false
	return true


func _files_diff() -> String:
	var out: Array[String] = []
	for path in GUARDED:
		var had = _files_bak.get(path, null)
		var now = (FileAccess.get_file_as_string(path)
			if FileAccess.file_exists(path) else null)
		out.append("%s %d→%d" % [path.get_file(),
			(-1 if had == null else str(had).length()),
			(-1 if now == null else str(now).length())])
	return " · ".join(out)


func _t_row_builder() -> void:
	print("── ③ 行构造(缺前提就不传) ──")
	var snap := {"leaders": ["basic"], "season_wins": 3, "hearts": 7, "season_sweeps": 1,
		"season_total_battles": 5}
	var good := SB.ghost_row_from_snapshot(snap, "uid-1", 1789948800, 5, "0.19.421")
	_chk("③ ★分母: 三维齐全时确实产出一行(否则下面全是空检查)", not good.is_empty(), str(good.size()))
	_chk("③ 主键三维都在行里",
		str(good.get("account_id", "")) == "uid-1"
		and int(good.get("season_week", 0)) == 1789948800
		and int(good.get("battles", -1)) == 5, str(good))
	_chk("③ 排序三键从快照里取(不是我另算的)",
		int(good.get("season_wins", -1)) == 3 and int(good.get("hearts", -1)) == 7
		and int(good.get("season_sweeps", -1)) == 1)

	var bads := [
		["缺 account_id", SB.ghost_row_from_snapshot(snap, "", 1789948800, 5, "v")],
		["缺周锚点(0)", SB.ghost_row_from_snapshot(snap, "uid-1", 0, 5, "v")],
		["周锚点为负", SB.ghost_row_from_snapshot(snap, "uid-1", -1, 5, "v")],
		["场次为负(还没打过)", SB.ghost_row_from_snapshot(snap, "uid-1", 1789948800, -1, "v")],
		["空快照", SB.ghost_row_from_snapshot({}, "uid-1", 1789948800, 5, "v")],
	]
	var leaked := 0
	for b in bads:
		var r: Dictionary = b[1]
		if not r.is_empty():
			leaked += 1
		_chk("③ %s → 返回空(不传)" % str(b[0]), r.is_empty(), str(r))
	_chk("③ ★★五种缺前提一个都没凑出残行(凑了会在服务端造主键 (\"\",0,0) 的垃圾并覆盖别人)",
		leaked == 0, "违例 %d/5" % leaked)


# ─────────────────────────────────────────────────────────────
# ④ 上传回包记账: 成功才升旗
# ─────────────────────────────────────────────────────────────
func _t_flash() -> void:
	print("── ④ 只有成功才升「阵容已上传」那面旗 ──")
	SB._reset_upload_for_test()
	while RP.consume_upload_flash():
		pass                                    # 先把旗取空, 免得读到别处升的
	_chk("④ ★分母: 旗现在是落下的", not RP.consume_upload_flash())

	_chk("④ HTTP 500 → 记账为失败", not SB.apply_upload_response(true, 500))
	_chk("④ ★失败【不升旗】", not RP.consume_upload_flash())
	_chk("④ 传输失败 → 也是失败", not SB.apply_upload_response(false, 0))
	_chk("④ ★传输失败也不升旗", not RP.consume_upload_flash())

	_chk("④ HTTP 201 → 记账为成功", SB.apply_upload_response(true, 201))
	_chk("④ ★★成功才升旗", RP.consume_upload_flash())
	_chk("④ 旗是一次性的(取过就没了)", not RP.consume_upload_flash())
	_chk("④ ★分母: 试了 3 次、成功 1 次(证明上面不是全都没跑)",
		SB.upload_try_count() == 3 and SB.upload_ok_count() == 1,
		"try=%d ok=%d" % [SB.upload_try_count(), SB.upload_ok_count()])


# ─────────────────────────────────────────────────────────────
# ①② ★★走真入口: 赢 +1 / 输也 +1 / 投降 +0
# ─────────────────────────────────────────────────────────────
## 池子是两层: `pool["brackets"][档位]` 才是数组。
## ★只数 `origin == local` 的 —— 内置策划队的种子(`_ensure_seeded`)也在同一个池里,
##   数总数会把它们算进来。“我传上去的”在产品里就是靠这个章认的(`_is_self_ghost`)。
func _pool_size() -> int:
	var p = BE.load_pool()
	var n := 0
	var br = p.get("brackets", null)
	if br is Dictionary:
		for k in (br as Dictionary).keys():
			var v = (br as Dictionary)[k]
			if v is Array:
				for g in (v as Array):
					if g is Dictionary and str((g as Dictionary).get(BE.ORIGIN_KEY, "")) == BE.ORIGIN_LOCAL:
						n += 1
	return n


func _setup_match() -> void:
	GameState.season_leaders = ["basic", "stone", "ice"]
	GameState.left_team = ["basic", "stone", "ice"] as Array[String]
	GameState.hearts = 8
	GameState.week_phase = "ranked"
	GameState.tutorial_active = false
	GameState.account_id = ""            # 停用态: 不走网络, 只量本地池
	GameState.lane_results = {"top": "left", "bottom": "right", "final": "left"}


func _t_real_settle() -> void:
	print("── ①② 走真入口 _settle_season(): 赢 / 输 / 投降 ──")
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame

	## ★★为什么这里要把 `test_mode` 关掉 —— 这是写这条门禁时才查出来的事实：
	##   `Backend.save_pool()` 自己带着一道闸 ——
	##       `if path == POOL_PATH and GameState.test_mode: return`
	##   而无头下 `test_mode` 是**自动置位的**(三道存档闸之一) ⇒
	##   **`Backend.upload_ghost()` 在门禁里不留任何痕迹**:
	##   本地池不落盘、旧后端没配是 no-op、Supabase 没配也是 no-op。
	##
	## ⇒ 两条路: 要么改成**数我自己插的计数器**(就是 memory
	##   `fb-gate-must-measure-requirement-not-my-hook` 禁的那件事 —— 插一行数一行必绿),
	##   要么让写盘真发生再逐字节还原。选后者。
	## ★安全垫: 上面已经把 `ghost_pool.json` 与 `savegame.json` **两份都备份了**,
	##   收尾逐字节写回并断言还原成功 —— 比光靠 test_mode 更紧，
	##   因为它连「手动单跑忘了隔离 APPDATA」那种情况也盖住了。
	var _tm: bool = bool(GameState.test_mode)
	GameState.test_mode = false
	_chk("① ★分母: 存档闸已临时打开(否则下面三条全是 0→0 的空检查)",
		not bool(GameState.test_mode))

	# ── 赢了一局(对照组: 改动之前就该 +1) ──
	_setup_match()
	var n0 := _pool_size()
	scene._settle_season(true)
	var n1 := _pool_size()
	_chk("① ★分母: 赢一局之后本地池多了一份(证明这条路本来就通)", n1 > n0,
		"%d → %d" % [n0, n1])

	# ── ★输了一局: 这就是本次改动 ──
	_setup_match()
	var n2 := _pool_size()
	scene._settle_season(false)
	var n3 := _pool_size()
	_chk("② ★★输了一局【也传】—— E18「每场都传」正式推翻 08-27 的「打赢才传」",
		n3 > n2, "%d → %d" % [n2, n3])

	# ── ★投降局: 不传 ──
	_setup_match()
	GameState.lane_results = {}          # 实测过: 投降不写任何一路的结果
	_chk("② ★分母: 这确实是一局投降(lane_results 是空字典)",
		(GameState.lane_results as Dictionary).is_empty())
	var n4 := _pool_size()
	scene._settle_season(false)
	var n5 := _pool_size()
	_chk("② ★★投降局【不传】(E18 第②条)", n5 == n4, "%d → %d" % [n4, n5])

	## ★★这三条合起来才有意义: 一个「无条件传」的实现会让第三条红,
	##   一个「只传赢的」实现会让第二条红 —— 少任何一条都挡不住。
	_chk("② ★★三态确实分得开(赢+1 / 输+1 / 投降+0)",
		n1 > n0 and n3 > n2 and n5 == n4,
		"赢 %d→%d · 输 %d→%d · 投降 %d→%d" % [n0, n1, n2, n3, n4, n5])

	## ★分母: 证明这三局真的**建出了文件** ——
	##   否则收尾那条「逐字节还原」在两个文件始终不存在时是恒真式。
	for path in GUARDED:
		if FileAccess.file_exists(path):
			_touched.append(path)
	_chk("① ★分母: 这三局确实落盘了(收尾那条还原断言才不是恒真式)",
		not _touched.is_empty(), str(_touched))

	GameState.test_mode = _tm
	scene.queue_free()
	await get_tree().process_frame
