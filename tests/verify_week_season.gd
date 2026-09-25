extends Node
## verify_week_season.gd — 大轮赛制 v2 周赛制的存档字段(A2)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## A2 给 `GameState` 加了 8 个字段，每个都要走**五处**：
##   ① 声明 ② 保存 ③ 载入 ④ `reset_save` ⑤ `start_new_season`
## **漏任何一处都不会报错**，只会在切轮或重启之后悄悄漂 —— 这正是它难自己发现的原因：
##   · 漏「保存」或「载入」⇒ 重启后清零，玩家以为进度丢了
##   · 漏 `start_new_season` ⇒ 新的一周带着上周的配额/战绩开局
##   · 漏 `reset_save` ⇒ 清档清不干净
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★**八个字段逐个验，不抽查** —— 缺口的形状就是「某一个字段漏了某一处」，
##   抽查三个通过不能说明第四个没漏。
## ★① 用**真存档往返**（产品自己的 `save()` → `_load()`，真过一次文件），不是自己拼字典读回来 ——
##   自己拼就绕开了产品的保存/载入代码，等于没验（同族 memory `fb-gate-subject-never-constructed`）。
##   ⚠ `save()` 在 `test_mode` 下直接 return，所以往返这一段必须**临时把 test_mode 关掉**。
##   为此本门禁**先把原存档整份备份、跑完按字节还原**（没有就删掉新建的那份）——
##   这样即使有人不带隔离 APPDATA 手跑，也不会动到玩家真存档
##   （memory `fb-debug-stage-writes-real-save`：台子写真存档是踩过的）。
## ★② 塞的值**全部非零且各不相同**，否则「切轮后 == 0」在字段本来就是 0 时是恒真式。
## ★①**确实会写一次盘**（否则 `save()`→`_load()` 走不通），靠「备份→还原」兜底；②③ 纯内存。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const FIELDS_INT := ["ranked_used", "season_sweeps", "backfill_paid",
	"week_anchor_ts", "gauntlet_wins", "gauntlet_losses",
	"gauntlet_backfill_paid"]                 # E-A(2026-09-22) 新增, 闯关补发的已补计数

## ★②(切轮归零)要把 `week_anchor_ts` **排除**在"归零"之外 —— 见 `_t_new_season_resets` 里的长注释。
##   ①(存档往返)和 ③(清档)仍然逐个验它, 一条都没少。
const FIELDS_ZERO_ON_NEW_SEASON := ["ranked_used", "season_sweeps", "backfill_paid",
	"gauntlet_wins", "gauntlet_losses", "gauntlet_backfill_paid"]

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 周赛制存档字段(A2) ===")

	_t_roundtrip()
	_t_new_season_resets()
	_t_reset_save_clears()
	await _t_quota_and_sweep()
	_t_schedule()
	_t_weekend_interim()

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 周赛制存档字段" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 塞一组【非零且互不相同】的值 —— 相同值会让"往返保值"在错位赋值时也能蒙对。
func _fill_distinct() -> Dictionary:
	var want := {}
	var v := 11
	for f in FIELDS_INT:
		_gs.set(f, v)
		want[f] = v
		v += 7
	_gs.week_phase = "gauntlet"
	want["week_phase"] = "gauntlet"
	_gs.promoted = true
	want["promoted"] = true
	return want


# ─────────────────────────────────────────────────────────────
# ① 存档往返: 存进去再读回来, 八个字段一个都不许变
#    —— 守「漏了保存」或「漏了载入」
# ─────────────────────────────────────────────────────────────
func _t_roundtrip() -> void:
	print("── ① 存档往返保值(真过一次文件) ──")
	var want: Dictionary = _fill_distinct()
	_ok("① ★分母: 塞进去的值都非零且互不相同",
		want["ranked_used"] != 0 and want["season_sweeps"] != want["ranked_used"], str(want))

	## ★备份原存档 —— 跑完按字节还原, 绝不动玩家真存档
	var had_save: bool = FileAccess.file_exists(_gs.SAVE_PATH)
	var backup: PackedByteArray = PackedByteArray()
	if had_save:
		var bf := FileAccess.open(_gs.SAVE_PATH, FileAccess.READ)
		if bf != null:
			backup = bf.get_buffer(bf.get_length())
			bf.close()
	_ok("① ★分母: 备份拿到了(原来有存档就该非空)", (not had_save) or backup.size() > 0,
		"原存档 %s, 备份 %d 字节" % ["有" if had_save else "无", backup.size()])

	var was_test: bool = bool(_gs.test_mode)
	_gs.test_mode = false          # save() 在 test_mode 下直接 return, 这一段必须放开
	_gs.save()
	_gs.test_mode = was_test

	## 先把内存全打乱, 确保"读回来对"不是因为内存里本来就是对的
	for f in FIELDS_INT:
		_gs.set(f, -999)
	_gs.week_phase = "__dirty__"
	_gs.promoted = false
	_ok("① ★分母: 读回来之前内存确实被打乱了", int(_gs.ranked_used) == -999,
		"ranked_used=%d" % int(_gs.ranked_used))

	_gs._load()

	for f in want.keys():
		var got = _gs.get(f)
		_ok("① 往返保值: %s" % f, got == want[f], "存 %s / 回读 %s" % [str(want[f]), str(got)])

	## ★还原 —— 无论上面绿红都要做
	if had_save:
		var wf := FileAccess.open(_gs.SAVE_PATH, FileAccess.WRITE)
		if wf != null:
			wf.store_buffer(backup)
			wf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_gs.SAVE_PATH))
	_ok("① ★收尾: 存档已还原成跑之前的样子",
		FileAccess.file_exists(_gs.SAVE_PATH) == had_save,
		"原来%s, 现在%s" % ["有" if had_save else "无", "有" if FileAccess.file_exists(_gs.SAVE_PATH) else "无"])


# ─────────────────────────────────────────────────────────────
# ② 切大轮: 八个字段全部归零 —— 守「漏了 start_new_season」
# ─────────────────────────────────────────────────────────────
func _t_new_season_resets() -> void:
	print("── ② start_new_season() 后全部归零 ──")
	var want: Dictionary = _fill_distinct()
	_ok("② ★分母: 切轮之前它们确实是非零的", int(_gs.ranked_used) > 0 and bool(_gs.promoted),
		"ranked_used=%d promoted=%s" % [int(_gs.ranked_used), str(_gs.promoted)])
	_gs.start_new_season()
	for f in FIELDS_ZERO_ON_NEW_SEASON:
		_ok("② 切轮归零: %s" % f, int(_gs.get(f)) == 0, "实得 %s" % str(_gs.get(f)))
	_ok("② 切轮归零: week_phase", str(_gs.week_phase) == "", "实得「%s」" % str(_gs.week_phase))
	_ok("② 切轮归零: promoted", bool(_gs.promoted) == false, "实得 %s" % str(_gs.promoted))

	## ★★`week_anchor_ts` 是这一组里**唯一不归零**的 —— 它不是"本轮攒了多少",
	##   而是"本轮是哪一周"。切轮之后它必须**换成新那一周的锚点**。
	##   2026-09-20 之前这里写的是「== 0」, 于是产品侧只能配合着写 `week_anchor_ts = 0`,
	##   而 `ensure_season()` 把 0 当"老存档待迁移" ⇒ **再也不滚轮**。
	##   门禁把死字段的死法给钉住了 —— 这条判据本身就是那个 bug 的一部分。
	## ★分母写在判据里: 既要**非 0**、又要**正好等于当前这一周的锚点**。
	##   只判非 0 的话, 随便写个 `week_anchor_ts = 1` 也能绿。
	var now_anchor: int = _P2.week_anchor_utc(int(Time.get_unix_time_from_system()))
	_ok("② ★分母: 切轮前塞的那个值不等于真锚点, 所以下面那条不是恒真式",
		int(want["week_anchor_ts"]) != now_anchor,
		"塞的 %d / 真锚点 %d" % [int(want["week_anchor_ts"]), now_anchor])
	_ok("② ★week_anchor_ts 不归零, 而是换成【本周锚点】",
		int(_gs.week_anchor_ts) == now_anchor,
		"实得 %d / 应为 %d" % [int(_gs.week_anchor_ts), now_anchor])
	_ok("② ★切轮后 season_start_ts 也落在本周一 00:00(不是'开游戏那一刻')",
		int(_gs.season_start_ts) == now_anchor,
		"实得 %d / 应为 %d" % [int(_gs.season_start_ts), now_anchor])


# ─────────────────────────────────────────────────────────────
# ③ 清档: 同样八个字段 —— 守「漏了 reset_save」
# ─────────────────────────────────────────────────────────────
func _t_reset_save_clears() -> void:
	print("── ③ reset_save() 后全部归零 ──")
	var want: Dictionary = _fill_distinct()
	_ok("③ ★分母: 清档之前它们确实是非零的", int(_gs.gauntlet_wins) > 0,
		"gauntlet_wins=%d" % int(_gs.gauntlet_wins))
	_gs.reset_save()
	for f in FIELDS_INT:
		_ok("③ 清档归零: %s" % f, int(_gs.get(f)) == 0, "实得 %s" % str(_gs.get(f)))
	_ok("③ 清档归零: week_phase", str(_gs.week_phase) == "", "实得「%s」" % str(_gs.week_phase))
	_ok("③ 清档归零: promoted", bool(_gs.promoted) == false, "实得 %s" % str(_gs.promoted))


# ─────────────────────────────────────────────────────────────
# ④⑤ A3 结算接线: 配额消耗 + 横扫计数
#     走**真入口** `_settle_season(true/false)`(照 verify_combat_sanity.gd:61-65 的调法),
#     不是直接改字段 —— 直接改就只验了我自己会加法。
# ─────────────────────────────────────────────────────────────
func _t_quota_and_sweep() -> void:
	print("── ④ 配额消耗(走真结算入口) ──")
	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame

	## 摆一个「有赛季、没淘汰」的干净局面
	_gs.season_start_ts = int(Time.get_unix_time_from_system())   # 防赛季过期滚动
	_gs.season_leaders = ["basic", "stone", "ice"]                # _had_season=true
	_gs.hearts = 8
	_gs.ranked_used = 0
	_gs.season_sweeps = 0
	_gs.week_phase = "ranked"
	_gs.lane_results = {}

	scene._settle_season(false)
	_ok("④ 积分赛阶段: 打一场 → 配额 +1", int(_gs.ranked_used) == 1,
		"ranked_used=%d" % int(_gs.ranked_used))
	scene._settle_season(false)
	_ok("④ 再打一场 → 配额 +1(累计 2)", int(_gs.ranked_used) == 2,
		"ranked_used=%d" % int(_gs.ranked_used))

	## ★★2026-09-22 换判据。原来这两条断言的是
	##   「闯关赛/决赛日打一场 → 积分赛配额【不动】」——
	##   **那正是把 bug 钉在原地的判据**(memory `fb-gate-can-pin-the-bug-in-place`):
	##   闯关赛/决赛日的玩法一行都没有, 那三天却照常开局、照常发奖、`season_wins` 照加,
	##   只是不吃配额 ⇒ 一周七天里三天无限刷, 24 场配额形同虚设。
	##   判据没错、代码也"照设计写了", 错的是**这两件事没有同时上线**。
	## ⇒ 现在判据跟着 `PHASE_MODE_LIVE` 那张表走, 每个阶段各断言各的;
	##   而且卡的是【加了几】(0 或 1), 不是"变了没有" —— 后者在连打两场时也会蒙对。
	_gs.hearts = 8                                    # 重置: 上面输掉的两场别把命耗到 0
	## ★期望**写死**在这张表里, 不问 `phase_mode_live()` ——
	##   问被测函数等于拿它当尺子(今天栽过一次: 它退化成空串时判据跟着全绿)。
	##   周六闯关赛 E-A 已上线 ⇒ 它吃自己的 6 场配额, **不吃**积分赛的 24 场。
	##   ★★2026-09-25 用户「周日要打开」 ⇒ **finals 1 → 0**: 决赛日玩法上线了,
	##     它有自己的淡汰赛赛制(不掍命、固定回合奖), **不再吃积分赛配额**。
	##     这一改正好是上面那段长注释说的那个条件到了 ——
	##     「不吃配额」与「玩法真做完了」终于同时成立, 不再是无限刷的后门。
	##   周一休赛设计上就没玩法 ⇒ 照走积分赛规则, **吃**配额。
	var quota_case := {"gauntlet": 0, "finals": 0, "rest": 1}
	for ph in quota_case.keys():
		_gs.week_phase = ph
		var before: int = int(_gs.ranked_used)
		## ★分母: 表演赛(0 命进场)不掉命也不记配额 —— 不排掉它, 下面 delta==0 会为了
		##   完全错误的理由变绿(memory `fb-gate-subject-never-constructed`)。
		_ok("④ ★分母(%s): 这一场是真赛不是表演赛" % ph, not _gs.is_eliminated(),
			"hearts=%d" % int(_gs.hearts))
		scene._settle_season(false)
		var delta: int = int(_gs.ranked_used) - before
		var want: int = int(quota_case[ph])
		_ok("④ ★%s 阶段: 打一场 → 积分赛配额 +%d" % [ph, want],
			delta == want, "实得 +%d (打之前 %d, 打之后 %d)" % [delta, before, int(_gs.ranked_used)])

	print("── ⑤ 横扫(2-0)计数 ──")
	_gs.week_phase = "ranked"
	_gs.hearts = 8
	_gs.season_sweeps = 0

	## 2-0 横扫: 两路都是我方赢、没打终极
	_gs.lane_results = {"top": "left", "bottom": "left"}
	_ok("⑤ ★分母: 这是一局真 2-0(两路都有结果且同为 left)",
		_gs.dual_lane_was_sweep(), "lane_results=%s" % str(_gs.lane_results))
	scene._settle_season(true)
	_ok("⑤ 2-0 赢 → 横扫 +1", int(_gs.season_sweeps) == 1,
		"season_sweeps=%d" % int(_gs.season_sweeps))

	## 1-1 打到终极才赢: **不算**横扫
	_gs.lane_results = {"top": "left", "bottom": "right", "final": "left"}
	scene._settle_season(true)
	_ok("⑤ ★打到终极战场才赢 → 不算横扫", int(_gs.season_sweeps) == 1,
		"season_sweeps=%d(应仍为 1)" % int(_gs.season_sweeps))

	## 投降局: lane_results 是空的 —— 实测过(tests/_probe_draw_surrender.gd)
	_gs.lane_results = {}
	_ok("⑤ ★分母: 投降局的 lane_results 确实是空字典",
		(_gs.lane_results as Dictionary).is_empty())
	_ok("⑤ ★空 lane_results 不算横扫(不崩也不误记)", not _gs.dual_lane_was_sweep())
	scene._settle_season(true)
	_ok("⑤ 投降后赢的那局不记横扫", int(_gs.season_sweeps) == 1,
		"season_sweeps=%d(应仍为 1)" % int(_gs.season_sweeps))

	## 2-0 但**输**的那方是我 ⇒ 不算我的横扫
	_gs.lane_results = {"top": "right", "bottom": "right"}
	_ok("⑤ ★对方 2-0 → 不是我的横扫", not _gs.dual_lane_was_sweep(),
		"lane_results=%s" % str(_gs.lane_results))

	## ⑥b(结算屏「本周场次」读数) 原本写在这里, 2026-09-22 撤掉了 ——
	##   `tests/verify_settle_quota.gd` 就是这件事的**专职门禁**(比这里早、而且更全),
	##   我当初搜「有没有门禁管它」时 `head -5` 把答案截掉了, 于是写了第二份。
	##   同一判据两份必然有一份落后(memory `fb-hand-rolled-copies-drift`)。

	scene.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ⑥ 赛程判定(A5 的纯函数) —— 全部按 UTC, 拿【已知日期】当样本
#    ★不自己算星期几再跟产品比 —— 那是拿同一份推导验它自己。
#      用真实日历上已知的四天(2026-09-14 周一 / 17 周四 / 19 周六 / 20 周日),
#      探针 tests/_probe_weekday.gd 已核实 Godot 的 weekday 是 0=周日。
# ─────────────────────────────────────────────────────────────
func _t_schedule() -> void:
	print("── ⑥ 赛程判定(UTC) ──")
	var MON := 1789344000    # 2026-09-14 00:00 UTC 周一
	var THU := 1789603200    # 2026-09-17 周四
	var SAT := 1789776000    # 2026-09-19 周六
	var SUN := 1789862400    # 2026-09-20 周日
	_ok("⑥ ★分母: 这四个时间戳落在我说的那几天",
		_P2.iso_weekday_utc(MON) == 1 and _P2.iso_weekday_utc(THU) == 4
		and _P2.iso_weekday_utc(SAT) == 6 and _P2.iso_weekday_utc(SUN) == 7,
		"ISO 星期 = %d/%d/%d/%d" % [_P2.iso_weekday_utc(MON), _P2.iso_weekday_utc(THU),
		_P2.iso_weekday_utc(SAT), _P2.iso_weekday_utc(SUN)])
	_ok("⑥ 周一 = 休赛", _P2.phase_at_utc(MON) == _P2.PHASE_REST, _P2.phase_at_utc(MON))
	_ok("⑥ 周四 = 积分赛", _P2.phase_at_utc(THU) == _P2.PHASE_RANKED, _P2.phase_at_utc(THU))
	_ok("⑥ 周六 = 闯关赛", _P2.phase_at_utc(SAT) == _P2.PHASE_GAUNTLET, _P2.phase_at_utc(SAT))
	_ok("⑥ 周日 = 决赛日", _P2.phase_at_utc(SUN) == _P2.PHASE_FINALS, _P2.phase_at_utc(SUN))

	## 收盘: 积分赛看周五 23:00, 闯关赛看周六 23:00
	var thu_left := _P2.close_left_sec(THU)
	_ok("⑥ 周四 00:00 → 距周五 23:00 收盘 = 47 小时",
		thu_left == 47 * 3600, "实得 %d 秒(%.1f 小时)" % [thu_left, float(thu_left) / 3600.0])
	var sat_left := _P2.close_left_sec(SAT)
	_ok("⑥ 周六 00:00 → 距周六 23:00 收盘 = 23 小时",
		sat_left == 23 * 3600, "实得 %d 秒" % sat_left)
	_ok("⑥ 周一(休赛)没有收盘概念 → -1", _P2.close_left_sec(MON) == -1)
	_ok("⑥ 周日(决赛日)同样 -1", _P2.close_left_sec(SUN) == -1)

	## ★★E3 封盘: 闸在收盘前 10 分钟内合上
	##   判据写死 600/601/599, **不引 CLOSE_LOCKOUT_SEC** —— 拿被测常量当尺子等于没量。
	var close_at := SAT + 23 * 3600                 # 周六 23:00 整
	_ok("⑥ 收盘前 11 分钟: 还能开", _P2.can_start_match_utc(close_at - 660))
	_ok("⑥ ★收盘前 9 分钟: 封盘", not _P2.can_start_match_utc(close_at - 540))
	_ok("⑥ 收盘前 601 秒: 还能开(边界外一秒)", _P2.can_start_match_utc(close_at - 601))
	_ok("⑥ ★收盘前 599 秒: 封盘(边界内一秒)", not _P2.can_start_match_utc(close_at - 599))
	_ok("⑥ 休赛日不封盘(没有收盘概念)", _P2.can_start_match_utc(MON))


# ─────────────────────────────────────────────────────────────
# ⑦ 周末玩法没上线时的过渡规则 (2026-09-22)
#    守的缺口: `phase_at_utc()` 从 v0.19.417 起真的会返回 gauntlet/finals/rest,
#    但那三天的**玩法一行都没写** —— 于是"按阶段分流"把周六日一变成了
#    无配额的积分赛(照常发奖、season_wins 照加)。
#    ★七天**全量**验, 不抽查: 缺口的形状就是"某一天漏了", 抽查三天说明不了第四天。
# ─────────────────────────────────────────────────────────────
func _t_weekend_interim() -> void:
	print("── ⑦ 周末玩法没上线时的过渡规则 ──")
	var quota_days: Array = []      # 哪几天的场次吃积分赛配额
	var note_days: Array = []       # 哪几天要在赛程条上挂「开发中」
	for wd in range(1, 8):
		var ph: String = _P2.phase_of_weekday(wd)
		if _P2.phase_uses_ranked_quota(ph):
			quota_days.append(wd)
		if _P2.phase_pending_note(ph) != "":
			note_days.append(wd)
	print("  ⑦ 吃积分赛配额的天 = %s ; 要挂「还没上线」的天 = %s" % [
		str(quota_days), str(note_days)])
	## ★两条期望都**写死**(不问 `phase_mode_live()` —— 那是拿被测函数当尺子)。
	## ★★2026-09-25 用户「周日要打开」 ⇒ 周日(7) 从两份名单里**同时移出**:
	##   它不再吃积分赛配额(有自己的淡汰赛赛制), 也不再挂「还没上线」。
	##   ★两份必须一起改: 只改前一份 = 「限制免了而屏幕上还说没上线」,
	##   只改后一份 = 「屏幕上说上线了而还在吃别人的配额」。
	##   周一(1)休赛设计上就没玩法 ⇒ 两份名单里都留着。
	_ok("⑦ ★吃积分赛配额的只有周一~周五(周六周日各有自己的赛制)",
		quota_days == [1, 2, 3, 4, 5], str(quota_days))
	_ok("⑦ ★要挂「还没上线」提示的只剩周一(周六周日都上线了)",
		note_days == [1], str(note_days))
	_ok("⑦ ★分母: 老档没写过赛程(空串)一律按积分赛算", _P2.phase_uses_ranked_quota(""))

	## ★★开闸问的是【现在】, 不是存档里那个"上一场的阶段"。
	##   存档里的 `week_phase` 写在点「开打」那一刻, 之后一直留着 ——
	##   拿它当"现在"用, 上周六打过的人在周二开局时会被当成还在闯关赛而白放一场进来。
	var THU := 1789603200    # 2026-09-17 周四 (与 ⑥ 同一组已知日期)
	var SAT := 1789776000    # 2026-09-19 周六
	var keep_phase = _gs.week_phase
	var keep_used: int = int(_gs.ranked_used)
	var keep_hearts: int = int(_gs.hearts)
	_gs.hearts = 8                                   # 淘汰态下另有一条闸, 排掉它
	_gs.week_phase = "gauntlet"                      # 上一场是上周六打的
	_gs.ranked_used = int(_P2.RANKED_QUOTA)
	_ok("⑦ ★存档里写着 gauntlet + 本周四配额已满 → 仍然拦住(不看存档里的旧阶段)",
		_gs.ranked_quota_full(THU),
		"week_phase=%s ranked_used=%d/%d" % [str(_gs.week_phase),
		int(_gs.ranked_used), int(_P2.RANKED_QUOTA)])
	_gs.ranked_used = int(_P2.RANKED_QUOTA) - 1
	_ok("⑦ ★分母: 差一场没打满 → 放行(证明上一条不是恒真式)",
		not _gs.ranked_quota_full(THU), "ranked_used=%d" % int(_gs.ranked_used))

	_gs.ranked_used = int(_P2.RANKED_QUOTA)
	## ★周六闯关赛已上线 ⇒ 积分赛配额打满**不该**拦住周六(周六有自己的闸)
	_ok("⑦ ★周六: 积分赛配额打满也放行(闯关赛吃自己的 6 场配额)",
		not _gs.ranked_quota_full(SAT), "ranked_used=%d" % int(_gs.ranked_used))

	## `consume_ranked_quota()` 与 `ranked_quota_full()` 必须是同一个答案 ——
	## 这两个函数是这次唯一的两个消费端, 它们各写一份判据正是这个洞的成因。
	for ph2 in ["", "ranked", "gauntlet", "finals", "rest"]:
		_gs.week_phase = ph2
		_gs.ranked_used = 0
		_gs.consume_ranked_quota()
		_ok("⑦ consume(%s) 与 phase_uses_ranked_quota 一致" % ("空串" if ph2 == "" else ph2),
			(int(_gs.ranked_used) == 1) == _P2.phase_uses_ranked_quota(ph2),
			"ranked_used=%d, 规则说 %s" % [int(_gs.ranked_used),
			str(_P2.phase_uses_ranked_quota(ph2))])

	_gs.week_phase = keep_phase
	_gs.ranked_used = keep_used
	_gs.hearts = keep_hearts
