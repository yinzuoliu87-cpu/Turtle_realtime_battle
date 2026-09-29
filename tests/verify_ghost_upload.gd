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
	"season_id", "account_id", "week_anchor_ts", "tutorial_active", "season_sweeps",
	## ★⑤ 往返那一节要摆阵容/装备/训龟技能 —— 都是**存档里的**字段, 必须还原。
	"trainer_skill"]
## ★★这三个是 Dictionary —— `GameState.get(k)` 拿回来是**引用**, 就地被改过的话
##   「还原」等于什么都没做。⇒ 单独深拷贝一份(⑤ 那一节会整个替换它们)。
const KEYS_DEEP := ["dual_lineup", "persistent_equipped", "loadouts", "dual_ghost",
	"foe_loadouts"]
var _bak_deep := {}


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
	for k in KEYS_DEEP:
		var v = GameState.get(k)
		_bak_deep[k] = (v as Dictionary).duplicate(true) if v is Dictionary else v
	_backup_files()
	print("=== D-4a 每场都传 ===")
	_t_row_builder()
	_t_flash()
	await _t_real_settle()
	for k in KEYS:
		GameState.set(k, _bak[k])
	for k in KEYS_DEEP:
		GameState.set(k, _bak_deep[k])
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
## 池子是两层: `pool[BE.POOL_KEY][场次]` 才是数组(★2026-09-26 键从 brackets 换成 by_battles)。
## ★只数 `origin == local` 的 —— 内置策划队的种子(`_ensure_seeded`)也在同一个池里,
##   数总数会把它们算进来。“我传上去的”在产品里就是靠这个章认的(`_is_self_ghost`)。
func _pool_size() -> int:
	var p = BE.load_pool()
	var n := 0
	var br = p.get(BE.POOL_KEY, null)
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

	## ★★★⑤ GHOST_ROUNDTRIP —— 必须在**这个窗口里**跑: `Backend.save_pool()` 有
	##   `test_mode` 闸, 闸关着的话池子一个字节都落不了盘, 往返就成了"两边都空也叫一致"。
	_t_roundtrip(scene)

	GameState.test_mode = _tm
	scene.queue_free()
	await get_tree().process_frame
# ─────────────────────────────────────────────────────────────
# ⑤ GHOST_ROUNDTRIP —— 存进去的【分路 / 装备 / 训龟技能】, 拉回来必须一模一样
# ─────────────────────────────────────────────────────────────
## ★★★由来(2026-09-29, 用户在屏幕上看到的那个 bug):
##   「对手上场是 6 个小将, 一个统领都没有」。
##   根因在**上传**这一步 —— `build_ghost_snapshot()` 读的三个字段没人往里写 / 是局内临时的:
##     `GameState.lane_assign`  全仓零写入点(真数据在 `dual_lineup`)
##     `GameState.equipped_p2`  `reset_dual_lane()` 每局清空、不进存档(真数据在 `persistent_equipped`)
##     `trainer_skill`          压根没写进快照(消费侧 `battle_spawn.gd:575` 在读, 取不到回落 `hook`)
##   真机池实测: 非种子快照 30/30 分路空、装备空; 396 条内置种子**一条都不空**
##   (它们走 `make_bot` / `_cohort._snapshot_of`, 自己从阵容算分路)。
##
## ★★为什么必须是**端到端**而不是"断言 build_ghost_snapshot 的返回值":
##   这个 bug 活了三个月, 而这期间 `verify_ghost_chest` / `verify_ghost_loadouts` /
##   `verify_leaderboard_sort ⑥` 三条门禁**都在调 `build_ghost_snapshot()`** ——
##   它们各自只看自己关心的那个键, 没有一条问过「这份快照拿去当对手, 场上站得出人吗」。
##   ⇒ 这一节走**三段真路**: 真上传(`_settle_season`) → 真选靶(`find_opponent`)
##      → 真消费(`_dual_foe_lane`), 每段都断言。
##
## ★★★分母(本仓栽过的形状: 两边都空也叫"一致"):
##   先证明**存进去的那一份自己非空**(分路 3 只、装备 3 件、训龟技能非默认),
##   再比"拉回来的 == 存进去的"。缺了前一半, 修复被撤掉时这一节会**照样绿**。
## ★训龟技能**故意不用 `hook`** —— 那正是取不到时的回落值(`battle_spawn.gd:577`),
##   拿它当期望值判据恒真。
func _t_roundtrip(scene) -> void:
	print("── ⑤ GHOST_ROUNDTRIP: 存进去的【分路/装备/训龟技能】拉回来一模一样 ──")
	## ── 造一支**有分路、有装备、有非默认训龟技能**的队 ──
	var TEAM := ["basic", "stone", "ice"]
	## ★挑一个内置种子池没有的场次(种子只覆盖 0~35) ⇒ 那一桶里只有我这一份, 往返无歧义。
	var SEED_BAT := 4242
	GameState.season_leaders = TEAM.duplicate()
	GameState.left_team = ["basic", "stone", "ice"] as Array[String]
	GameState.hearts = 8
	GameState.week_phase = "ranked"
	GameState.tutorial_active = false
	GameState.account_id = ""
	GameState.lane_results = {"top": "left", "bottom": "right", "final": "left"}
	GameState.season_total_battles = SEED_BAT
	GameState.trainer_skill = "glacier"        # ★不是 "hook"(回落值)
	## ★阵型故意**不用默认**: 上路 2 统领 + 1 小将 / 下路 1 统领 + 2 小将, 小将还带装备。
	GameState.dual_lineup = {
		"top": [{"kind": "leader", "id": "basic", "slot": 0},
			{"kind": "leader", "id": "stone", "slot": 1},
			{"kind": "minion", "role": "front", "equips": [{"id": "p2eq_003", "star": 1}]}],
		"bottom": [{"kind": "leader", "id": "ice", "slot": 2},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"}],
	}
	GameState.persistent_equipped = {
		"basic": [{"id": "p2eq_001", "star": 2}, {"id": "p2eq_005", "star": 1}],
		"ice": [{"id": "p2eq_007", "star": 1}],
	}

	## ── 第一段: 真上传路径(`_settle_season` 里那两行 build_ghost_snapshot + upload_ghost) ──
	scene._settle_season(true)

	## ★★场次要取**打完之后**的那个值: `_settle_season` 先 `season_total_battles += 1`
	##   (`RealtimeBattle3DScene.gd:7610`), 再用它拼 ghost_id / 写进快照(`:7659`)。
	##   拿打之前那个数去找桶 ⇒ 永远找不到(第一版就是这么红的, 桶里 -1 条)。
	var BAT := int(GameState.season_total_battles)
	_chk("⑤ ★分母: 场次按产品自己的账走(打完 +1) —— 摆 %d ⇒ 快照记 %d" % [SEED_BAT, BAT],
		BAT == SEED_BAT + 1, "%d → %d" % [SEED_BAT, BAT])

	## ── 取出"存进去的那一份" = 真池子里本机产的、场次 = BAT 的那条 ──
	var pool: Dictionary = BE.load_pool()
	var stored: Dictionary = {}
	var bucket = (pool.get(BE.POOL_KEY, {}) as Dictionary).get(str(BAT), null)
	if bucket is Array:
		for g in (bucket as Array):
			if g is Dictionary and str((g as Dictionary).get(BE.ORIGIN_KEY, "")) == BE.ORIGIN_LOCAL:
				stored = g
				break
	_chk("⑤ ★分母: 真上传路径确实把一份快照写进了池子(场次 %d 桶)" % BAT,
		not stored.is_empty(),
			"桶里 %d 条" % ((bucket as Array).size() if bucket is Array else -1))
	if stored.is_empty():
		return

	## ── ★★★分母: **存进去的那一份自己**三样都非空/非默认 ──
	var s_la: Dictionary = stored.get("lane_assign", {}) if stored.get("lane_assign") is Dictionary else {}
	var s_lead_n: int = (s_la.get("top", []) as Array).size() + (s_la.get("bottom", []) as Array).size()
	var s_eq: Dictionary = stored.get("equipped", {}) if stored.get("equipped") is Dictionary else {}
	var s_eq_n := 0
	for k in s_eq.keys():
		s_eq_n += (s_eq[k] as Array).size()
	_chk("⑤ ★★★分母: 存进去的那份**分路非空** —— 统领 3 只(2 上 + 1 下)",
		s_lead_n == 3 and (s_la.get("top", []) as Array).size() == 2,
		"top=%s bottom=%s" % [str(s_la.get("top", [])), str(s_la.get("bottom", []))])
	_chk("⑤ ★★★分母: 存进去的那份**装备非空** —— 统领身上 3 件",
		s_eq_n == 3, "%d 件 %s" % [s_eq_n, str(s_eq)])
	_chk("⑤ ★★★分母: 存进去的那份**训龟技能**是我摆的 glacier(不是回落值 hook)",
		str(stored.get("trainer_skill", "")) == "glacier", str(stored.get("trainer_skill", "<缺>")))
	_chk("⑤ ★分母: 存进去的那份**小将也带装备**(小将装备存在 dual_lineup 里, 另一条链)",
		_minion_eq_n(stored) == 1, "%d 件" % _minion_eq_n(stored))
	_chk("⑤ ★分母: `leaders` 与分路同源(输的那局 left_team 可能是空的)",
		(stored.get("leaders", []) as Array).size() == 3, str(stored.get("leaders", [])))

	## ── 第二段: 真拉取/选靶路径 `Backend.find_opponent()` ──
	## ★`SELF_GHOST=1` 是产品自带的自测开关(`_is_self_ghost` 第一行) —— 不加它,
	##   刚上传的那份会被"不打到自己"筛掉, 这一段就永远只能拿到 bot。
	var had_self_env := OS.has_environment("SELF_GHOST")
	if not had_self_env:
		OS.set_environment("SELF_GHOST", "1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var got: Dictionary = BE.find_opponent(BAT, [], rng)
	if not had_self_env:
		OS.unset_environment("SELF_GHOST")

	_chk("⑤ ★★分母: 选靶拿回来的**不是 bot**(是 bot 的话下面全是在比 bot 的字段)",
		not bool(got.get("is_bot", false)),
		"ghost_id=%s" % str(got.get("ghost_id", "")))
	_chk("⑤ ★★★拉回来的就是存进去的那一份(ghost_id 逐字相同)",
		str(got.get("ghost_id", "")) == str(stored.get("ghost_id", "")),
		"拉=%s / 存=%s" % [str(got.get("ghost_id", "")), str(stored.get("ghost_id", ""))])
	_chk("⑤ ★★★拉回来的**分路**与存进去的逐字相同",
		JSON.stringify(got.get("lane_assign", {})) == JSON.stringify(stored.get("lane_assign", {})),
		"拉=%s" % JSON.stringify(got.get("lane_assign", {})))
	_chk("⑤ ★★★拉回来的**装备**与存进去的逐字相同(件数 %d)" % s_eq_n,
		JSON.stringify(got.get("equipped", {})) == JSON.stringify(stored.get("equipped", {})),
		"拉=%s" % JSON.stringify(got.get("equipped", {})))
	_chk("⑤ ★★★拉回来的**训龟技能**还是 glacier",
		str(got.get("trainer_skill", "")) == "glacier", str(got.get("trainer_skill", "<缺>")))

	## ── 第三段: 真消费路径 `_dual_foe_lane()` —— 玩家眼里的"对面上了几个统领" ──
	## ★★★这里故意喂**存进去的那一份**(`stored`)而不是选靶拿回来的 `got` ——
	##   两者在一切正常时是同一个字典, 但**撤掉上传侧的修复时形状不同**:
	##   那时 `find_opponent` 会被第一道闸挡住、给我一个 bot(分路是好的),
	##   于是"对面几个统领"这条断言会**照样绿** —— 判据就量不到上传那一步了。
	##   喂 `stored` = 绕过匹配那道闸, 让这一条**只**回答「玩家真上传的那份
	##   拿去当对手, 场上站得出几个统领」。撤掉修复时它红成「0 统领 / 6 小将」,
	##   正是用户在屏幕上看到的那个形状。
	GameState.dual_ghost = stored
	var top: Array = scene._dual_foe_lane("top")
	var bot: Array = scene._dual_foe_lane("bottom")
	var lead_ids: Array = []
	var min_n := 0
	var spec_eq := 0
	for arr in [top, bot]:
		for sp in (arr as Array):
			if str((sp as Dictionary).get("kind", "")) == "leader":
				lead_ids.append(str((sp as Dictionary).get("id", "")))
			else:
				min_n += 1
			var e = (sp as Dictionary).get("equips", null)
			if e is Array:
				spec_eq += (e as Array).size()
	_chk("⑤ ★分母: 每路都规整到 3 个单位(与玩家同规则)",
		top.size() == 3 and bot.size() == 3, "top=%d bottom=%d" % [top.size(), bot.size()])
	_chk("⑤ ★★★**对面上了 3 个统领**(这就是用户看到的那个 bug: 原来是 0 统领 + 6 小将)",
		lead_ids.size() == 3, "%d 统领 / %d 小将 %s" % [lead_ids.size(), min_n, str(lead_ids)])
	_chk("⑤ ★★★统领 id 对得上(上路 basic+stone / 下路 ice)",
		str(top[0].get("id", "")) == "basic" and str(top[1].get("id", "")) == "stone"
			and str(bot[0].get("id", "")) == "ice", str(lead_ids))
	_chk("⑤ ★★★装备真的挂到了 spec 上: 统领 3 件 + 小将 1 件 = 4 件",
		spec_eq == 4, "%d 件" % spec_eq)

	## ── ★反面: 一份**分路空**的坏快照(= 修好之前每一份真人快照的样子)不许当对手 ──
	var rotten: Dictionary = stored.duplicate(true)
	rotten["ghost_id"] = "g_rotten_%d_b%d" % [int(GameState.season_id), BAT]
	rotten["lane_assign"] = {"top": [], "bottom": []}
	rotten["equipped"] = {}
	rotten[BE.ORIGIN_KEY] = BE.ORIGIN_REMOTE
	_chk("⑤ ★分母: 这份坏快照除了分路**一切合法**(`snapshot_valid` 会放它入池)",
		bool(RP.snapshot_valid(rotten).get("ok", false)), str(RP.snapshot_valid(rotten)))
	_chk("⑤ ★★★`ghost_lanes_broken`: 好的判 false / 坏的判 true",
		(not BE.ghost_lanes_broken(stored)) and BE.ghost_lanes_broken(rotten))
	BE.pool_override = {BE.POOL_KEY: {str(BAT): [rotten]}}
	var got2: Dictionary = BE.find_opponent(BAT, [], rng)
	BE.pool_override = {}
	_chk("⑤ ★★★池子里**只有坏快照**时 ⇒ 退到 bot(不是拿它拼一支 6 小将的队)",
		bool(got2.get("is_bot", false)), "ghost_id=%s" % str(got2.get("ghost_id", "")))
	## ★分母: 同一个池子里**再放一份好的**, 必须选中好的那份 ——
	##   证明上面那条不是"有坏快照就一律掉 bot"(那会把好对手也一起扔掉)。
	if not had_self_env:
		OS.set_environment("SELF_GHOST", "1")
	BE.pool_override = {BE.POOL_KEY: {str(BAT): [rotten, stored]}}
	var got3: Dictionary = BE.find_opponent(BAT, [], rng)
	BE.pool_override = {}
	if not had_self_env:
		OS.unset_environment("SELF_GHOST")
	_chk("⑤ ★★分母: 坏快照压在好快照**上面**时, 仍然选中好的那份(不是掉 bot)",
		str(got3.get("ghost_id", "")) == str(stored.get("ghost_id", "")),
		"选中 %s" % str(got3.get("ghost_id", "")))
	GameState.dual_ghost = {}


## 快照里小将身上的装备件数(小将装备走 dual_lineup 那条链, 与统领的不是一个来源)。
func _minion_eq_n(snap: Dictionary) -> int:
	var n := 0
	var m = snap.get("minions", null)
	if m is Dictionary:
		for lk in ["top", "bottom"]:
			var arr = (m as Dictionary).get(lk, null)
			if arr is Array:
				for u in (arr as Array):
					if u is Dictionary and (u as Dictionary).get("equips") is Array:
						n += ((u as Dictionary)["equips"] as Array).size()
	return n
