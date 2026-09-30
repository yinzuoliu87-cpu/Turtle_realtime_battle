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
	_t_hearts_one_source()
	_t_promote_line_derived()

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
	_gs.hearts = _P2.HEARTS_MAX
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
	_gs.hearts = _P2.HEARTS_MAX                                    # 重置: 上面输掉的两场别把命耗到 0
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
	_gs.hearts = _P2.HEARTS_MAX
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
	_gs.hearts = _P2.HEARTS_MAX                                   # 淘汰态下另有一条闸, 排掉它
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


# ─────────────────────────────────────────────────────────────
# ⑨ HEARTS_ONE_SOURCE —— 命数上限只有一个事实源
#
# 由来（用户 2026-09-29 14:05）：「现在是 24 场 8 条命对吧，**之后**我们改为 16 场 6 条命了」。
# ★这一节不改值（仍是 8 + 24），它要保证的是：**将来改 16/6 时只需改一处**。
#   原来 `8` 散在三处：`GameState` 的声明 / `reset_all()` / `start_new_season()`，
#   改漏一处就会在切轮之后悄悄漂（本仓 `fb-hand-rolled-copies-drift` 那一族）。
#
# ★★判据分两层，缺哪层都不算守住：
#   ① **行为层**：三条路（初值 / reset_all / start_new_season）拿到的都必须 == `HEARTS_MAX`。
#      —— 只有这层的话，有人把 `HEARTS_MAX` 也改成字面量 8 它照样绿。
#   ② **源码层**：`autoload/` + `scripts/` 里不许再出现 `hearts = <数字>`。
#      —— 这层挡的是「将来又长出第四处」。扫的是产品源码，不是测试自己。
# ★分母：源码层必须真的扫到文件、真的扫到 `hearts` 这个词（扫了 0 个文件是空检查）。
# ─────────────────────────────────────────────────────────────
func _t_hearts_one_source() -> void:
	var hm: int = int(_P2.HEARTS_MAX)
	_ok("⑨ ★分母: `HEARTS_MAX` 是个正数(%d)" % hm, hm > 0, str(hm))

	## ① 行为层：三条路
	_gs.reset_save()
	_ok("⑨ ★★`reset_save()` 后命数 == HEARTS_MAX(%d)" % hm, int(_gs.hearts) == hm,
		"实得 %d" % int(_gs.hearts))
	_gs.hearts = 1
	_gs.start_new_season()
	_ok("⑨ ★★`start_new_season()` 后命数 == HEARTS_MAX(%d)" % hm, int(_gs.hearts) == hm,
		"实得 %d" % int(_gs.hearts))

	## ② 源码层：不许再长出第四处写死的命数
	var files: Array = []
	for root in ["res://autoload", "res://scripts"]:
		_collect_gd(root, files)
	var offenders: Array = []
	var saw_hearts: int = 0
	var re := RegEx.create_from_string("hearts[ \t]*=[ \t]*[0-9]")
	for fp in files:
		var f := FileAccess.open(str(fp), FileAccess.READ)
		if f == null:
			continue
		var txt: String = f.get_as_text()
		f.close()
		if txt.find("hearts") >= 0:
			saw_hearts += 1
		if re == null:
			continue
		for ln in txt.split("\n"):
			var s2: String = str(ln).strip_edges()
			if s2.begins_with("#") or s2.begins_with("##"):
				continue      # 注释里写「8 命」是记账, 不是事实源
			if re.search(s2) != null:
				offenders.append("%s: %s" % [str(fp).get_file(), s2.substr(0, 70)])
	print("  [分母] HEARTS_ONE_SOURCE: 扫了 %d 个 .gd / 其中 %d 个提到 hearts" % [files.size(), saw_hearts])
	_ok("⑨ ★分母: 真的扫到文件且真的扫到 `hearts`(0 = 空检查)",
		files.size() >= 50 and saw_hearts >= 3, "%d 文件 / %d 提到" % [files.size(), saw_hearts])
	_ok("⑨ ★★★HEARTS_ONE_SOURCE: 产品源码里不许再写死命数(要读 `_P2.HEARTS_MAX`)",
		offenders.is_empty(), "; ".join(offenders))

	## ── ③ 更刁的一族: 拿【满命那个数字本身】当字面量写在断言/夹具里 ──
	##
	## ★由来(2026-09-30 翻 16/6 当场遇到): 产品源码是干净的(第 ② 层守着),
	##   但**五处测试**写着「hearts 回到 8」「range(7)」这种 —— 8 是满命, 7 是满命−1。
	##   命一改这五条全红, **而错在尺子不在产品**。
	## ★★判据设计得很窄, 不是"禁止 hearts 附近出现数字":
	##   只在**那个字面量恰好等于当前 HEARTS_MAX** 时才报。
	##   ⇒ 测试写 `hearts = 1`(模拟残命)、`== 3`(扣了三次) 一律放过 —— 那是真夹具;
	##     写到跟满命一样的数, 就说明它想表达的是"满命", 那就该读常量。
	##   ⇒ 这条规则**在满命改变之后自动仍然正确**, 不需要跟着改。
	## ★用 `\b` 边界: `hearts_y = 160` 里的 6 不算(否则一堆假违规)。
	var lit_offenders: Array = []
	## ★★判据必须**刚好卡住那个形状** —— 宽一格会造假 bug(深海币公式
	##   `8 + 余命 + 2×已失命 + 胜6` 里那些数字不是命数, 只是碰巧长得一样)。
	##   ⇒ 只认三种**真正意味着"满命"**的写法:
	##     A `hearts` 被赋值/比较成一个**恰好等于满命**的字面量 —— 那就是在说"满命"
	##       (写 `hearts = 1` / `== 3` 一律放过, 那是真夹具)
	##     B `<数字> - …hearts…` —— 那个位置上唯一讲得通的数就是满命,
	##       所以**不论取值都报**(这样连"改漏了、还留着旧满命 8"也抓得到)
	##     C 同一行里 `/ <数字>` 且提到 hearts —— 屏幕上的分母就是满命
	##       (`battle_hud` 的「%d / 8」就是这么被抓到的, 那是真 bug)
	var shapes: Array = [
		["A 赋值/比较成满命", RegEx.create_from_string("hearts\"?[ \t]*[:=]=?[ \t]*(?<![0-9])%d(?![0-9])" % hm)],
		["B <数> - hearts(那个数就是满命)", RegEx.create_from_string("(?<![A-Za-z_0-9])[0-9]+[ \t]*-[ \t]*[^,;]*hearts")],
		["C 屏上分母 / <数>", RegEx.create_from_string("/[ \t]*[0-9]+")],
	]
	var files2: Array = []
	for root2 in ["res://autoload", "res://scripts", "res://tests"]:
		_collect_gd(root2, files2)
	for fp2 in files2:
		var f2 := FileAccess.open(str(fp2), FileAccess.READ)
		if f2 == null:
			continue
		var txt2: String = f2.get_as_text()
		f2.close()
		## ★`_probe_*` 是开发期探针草稿(run-tests.sh 不自动发现它们, 也不上屏) ⇒ 不纳入。
		##   纳入的话这条判据会被一堆一次性脚本长期钉红, 而它们本来就该随手写随手改。
		if str(fp2).get_file().begins_with("_probe_"):
			continue
		if txt2.find("hearts") < 0:
			continue
		var lno: int = 0
		for ln2 in txt2.split("\n"):
			lno += 1
			var t2: String = str(ln2).strip_edges()
			if t2.begins_with("#") or t2.begins_with("##"):
				continue
			## ★行尾注释要剥掉: 注释里出现「砍到约1/3」这种会被 shape C 当成屏上分母
			##   (2026-09-30 实测误判过一次)。只按第一个不在引号里的 # 切。
			var q2: String = ""
			var cut2: int = -1
			for ci2 in range(t2.length()):
				var ch2: String = t2[ci2]
				if q2 != "":
					if ch2 == q2:
						q2 = ""
				elif ch2 == "\"" or ch2 == "'":
					q2 = ch2
				elif ch2 == "#":
					cut2 = ci2
					break
			if cut2 >= 0:
				t2 = t2.substr(0, cut2)
			if t2.find("hearts") < 0:
				continue
			if t2.find("HEARTS_MAX") >= 0:
				continue        # 已经读常量了, 顺带把常量声明那行也放过
			var shape_hit: String = ""
			for sh in shapes:
				var rx = sh[1]
				if rx != null and rx.search(t2) != null:
					shape_hit = str(sh[0])
					break
			if shape_hit == "":
				continue
			lit_offenders.append("[%s] %s:%d: %s" % [shape_hit, str(fp2).get_file(), lno, t2.substr(0, 58)])
	print("  [分母] HEARTS_ONE_SOURCE ③: 扫了 %d 个 .gd(含 tests/), 满命字面量 = %d" % [files2.size(), hm])
	_ok("⑨ ★分母: 第三层真的扫到文件(0 = 空检查)", files2.size() >= 100, "%d 文件" % files2.size())
	_ok("⑨ ★★★HEARTS_ONE_SOURCE: 不许拿【满命那个数字】当字面量(要读 `HEARTS_MAX`) —— "
		+ "写成字面量的话, 满命一改这些地方就集体红, 而错在尺子不在产品",
		lit_offenders.is_empty(), "; ".join(lit_offenders))


## 递归收 .gd（★不按我以为的层级走 —— 一律递归到底，memory `fb-recursive-scan-not-structured-walk`）
func _collect_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.begins_with("."):
			fn = d.get_next()
			continue
		var full: String = dir_path.path_join(fn)
		if d.current_is_dir():
			_collect_gd(full, out)
		elif fn.get_extension() == "gd":
			out.append(full)
		fn = d.get_next()
	d.list_dir_end()

# ─────────────────────────────────────────────────────────────
# ⑩ PROMOTE_LINE_DERIVED —— 晋级线是算出来的，不是拍的
#
# 用户 2026-09-30:「满足11胜且不出局就是唯一晋级条件了啊」
# ★而 11 不是第四个魔法数字: PROMOTE_WINS = RANKED_QUOTA − (HEARTS_MAX − 1)
#   = 「把配额打满而不被淘汰所需的最少胜场」。
#   ⇒ 以后改配额或命数, 这条线自己跟着走, 不用有人记得来改它。
#
# ★★这一节守三件事(缺哪件都会让那句话变成空话):
#   ① 派生关系本身: 常量真的等于那个算式 —— 防有人哪天把它改回写死的数
#   ② 「不出局」那半条的**冗余性质**: 在当前数字下, 过线就必然还活着
#      (过线 + 出局 = 胜线 + 命 = 11 + 6 = 17 场 > 16 配额, 打不出来)。
#      ⚠ 冗余是巧合带来的, 不是定理。哪天配额放宽到 ≥17, 这条会红 ——
#        那时该做的是**重读晋级线那段文字**, 而不是删掉这条断言。
#   ③ 走产品自己的 `gauntlet_line_reached()` 穷举翻转点, 不自己抄公式。
# ─────────────────────────────────────────────────────────────
func _t_promote_line_derived() -> void:
	var q: int = int(_P2.RANKED_QUOTA)
	var hm: int = int(_P2.HEARTS_MAX)
	var pw: int = int(_P2.PROMOTE_WINS)
	_ok("⑩ ★★★PROMOTE_LINE_DERIVED: 晋级线 == 配额 − (满命 − 1) = %d − %d = %d"
		% [q, hm - 1, pw], pw == q - (hm - 1), "实得 %d" % pw)
	_ok("⑩ ★分母: 三个数都是正的且线 ≤ 配额(否则谁都晋级不了)",
		q > 0 and hm > 0 and pw > 0 and pw <= q, "q=%d hm=%d pw=%d" % [q, hm, pw])

	## ② 冗余性质: 过线 + 出局 需要 pw + hm 场, 而配额只有 q 场
	_ok("⑩ ★★「不出局」那半条在当前数字下是**冗余**的(过线 %d + 打光 %d 命 = %d 场 > 配额 %d)"
		% [pw, hm, pw + hm, q], pw + hm > q,
		"若它红了: 说明配额已经大到能「过线后再被淘汰」 ⇒ 去重读晋级线那段文字, 别删这条")

	## ③ 走产品自己的函数穷举翻转点 —— 不自己抄 `>=` 那个公式
	var bak_w = _gs.season_wins
	var bak_h = _gs.hearts
	var flip: int = -1
	for w in range(0, q + 1):
		_gs.season_wins = w
		_gs.hearts = hm                      # 活着
		if _gs.gauntlet_line_reached():
			flip = w
			break
	_ok("⑩ ★★★翻转点就在 %d 胜(走产品自己的 `gauntlet_line_reached()` 穷举 0~%d)"
		% [pw, q], flip == pw, "实测翻转点 %d" % flip)
	## 出局的人一律不过线 —— 这是规则的另一半, 必须单独验
	_gs.season_wins = q                      # 胜场拉满
	_gs.hearts = 0                           # 但出局了
	_ok("⑩ ★★★出局的人**一律不晋级**(哪怕胜场拉满 %d) —— 这是规则的另一半" % q,
		not _gs.gauntlet_line_reached(), "season_wins=%d hearts=0" % q)
	_gs.season_wins = bak_w
	_gs.hearts = bak_h
