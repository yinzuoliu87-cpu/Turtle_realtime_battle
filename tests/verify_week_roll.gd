extends Node
## verify_week_roll.gd — 「一大轮 = 一个自然周」换轮判定 (2026-09-20)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么 —— 它补的是一个**两套时钟并存**的洞
## ══════════════════════════════════════════════════════════════════════
## 周赛制(A 阶段)落地时, 代码里同时留着两套互不相干的「一大轮」:
##   · 赛季换轮   `ensure_season()` 看【距上次开赛满 5 天没有】(`SEASON_DURATION_SEC := 432000`)
##   · 赛程阶段   `phase_at_utc()` 看【今天星期几】(周一休赛/周二~五积分赛/周六闯关/周日决赛)
## 5 和 7 永远合不上: 第一轮周一开、第二轮就从周六开、第三轮周四开……
## 而**积分赛配额 `ranked_used` 只在 `start_new_season()` 里清零** ⇒
## 配额跟着 5 天滚、赛程跟着 7 天滚, 玩家会在周三被清配额、或整整一周只领到一次。
##
## 同一件事的另一半: `week_anchor_ts` 这个字段从 A2 起就**写了没人读** ——
## 声明/保存/载入/reset_save/start_new_season 五处齐全, 但**没有任何判定读它**
## (memory `fb-zero-caller-is-a-whole-class` / `fb-read-a-field-nobody-writes` 同族)。
## 更糟的是当时的门禁 `verify_week_season ②` 断言「切轮后 week_anchor_ts == 0」——
## **门禁把死字段的死法给钉住了**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 拿**真实日历上已知的日期**验 `week_anchor_utc`, 不是自己再算一遍星期几去比 ——
##     那是拿同一份推导验它自己。日期用 `get_datetime_string_from_unix_time` 印出来核对,
##     那是与 `weekday` 不同的另一条格式化路径。
## ★② **改 `week_anchor_ts` 一个字段, 看产品的判定翻不翻面** —— 这是「字段是活的」的唯一证据。
##     「断言字段存在」守不住「还有没有人读」(memory `fb-verify-must-run-the-real-path`)。
## ★③ 把 `season_start_ts` 推到 10 年前而锚点不动 ⇒ **不许过期**。
##     这条专门钉「5 天时钟真的拔掉了」, 光删常量不算 —— 得证明没人再按时长判。
## ★④ `ensure_season()` 四条分支**逐条**走真入口, 尤其分支②(老存档迁移)必须证明
##     命/币/配额/赛季号**一个都没动** —— 迁移当成「过期」处理的话, 老玩家升级那一刻被平白清档。
## ★⑤ 换周那一刻**就是**赛程从「周日决赛」翻到「周一休赛」那一刻 —— 两套时钟从此是同一套。
## ★⚠ 本门禁会调 `ensure_season()`, 而它内部 `save()` ⇒ 全程 `test_mode = true`,
##     并**量存档文件的修改时刻**证明真没写盘(memory `fb-debug-stage-writes-real-save`)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 真实日历样本(UTC)
const MON := 1789344000      # 2026-09-14 00:00:00 周一
const THU := 1789603200      # 2026-09-17 周四
const SUN := 1789862400      # 2026-09-20 周日
const MON2 := 1789948800     # 2026-09-21 00:00:00 下一个周一

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
		print("  [FAIL] 缺 autoload GameState")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	_ok("★分母: test_mode 已置位(下面要调 ensure_season, 它内部会 save())",
		bool(_gs.test_mode), "test_mode=%s" % str(_gs.test_mode))

	var save_p: String = str(_gs.SAVE_PATH)
	var had: bool = FileAccess.file_exists(save_p)
	var mtime0: int = FileAccess.get_modified_time(save_p) if had else -1

	print("=== 自然周换轮 ===")
	_t_anchor_math()
	_t_field_is_alive()
	_t_five_day_clock_is_gone()
	_t_ensure_season_branches()
	_t_roll_moment_matches_phase()

	## ★收尾分母: 全程没碰存档文件
	var mtime1: int = FileAccess.get_modified_time(save_p) if FileAccess.file_exists(save_p) else -1
	_ok("★收尾: 存档文件没被写过(有/无 与 修改时刻都没变)",
		FileAccess.file_exists(save_p) == had and mtime1 == mtime0,
		"跑之前 %s/mtime=%d, 跑之后 %s/mtime=%d" % [
			"有" if had else "无", mtime0,
			"有" if FileAccess.file_exists(save_p) else "无", mtime1])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 自然周换轮" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① week_anchor_utc 本身: 拿真实日历日期 + 一遍性质扫
# ─────────────────────────────────────────────────────────────
func _t_anchor_math() -> void:
	print("── ① 周锚点算得对不对(拿真实日历当样本) ──")
	## ★分母: 这三个时间戳确实是我说的那几天。用**日期字符串**核, 不用 weekday ——
	##   换一条格式化路径才算外部尺子。
	var s_mon := Time.get_datetime_string_from_unix_time(MON, true)
	var s_sun := Time.get_datetime_string_from_unix_time(SUN, true)
	var s_mon2 := Time.get_datetime_string_from_unix_time(MON2, true)
	_ok("① ★分母: 三个时间戳印出来就是 09-14 / 09-20 / 09-21",
		s_mon.begins_with("2026-09-14") and s_sun.begins_with("2026-09-20")
		and s_mon2.begins_with("2026-09-21"),
		"%s / %s / %s" % [s_mon, s_sun, s_mon2])

	_ok("① 周一 00:00 的锚点 = 它自己", _P2.week_anchor_utc(MON) == MON,
		"实得 %d" % _P2.week_anchor_utc(MON))
	_ok("① 周四的锚点 = 同一周的周一", _P2.week_anchor_utc(THU) == MON,
		"实得 %d / 应为 %d" % [_P2.week_anchor_utc(THU), MON])
	_ok("① 周日的锚点 = 同一周的周一", _P2.week_anchor_utc(SUN) == MON,
		"实得 %d" % _P2.week_anchor_utc(SUN))
	## ★边界: 周日 23:59:59 还算这一周, 下一秒(周一 00:00:00)就换周
	_ok("① ★周日 23:59:59 仍算本周", _P2.week_anchor_utc(SUN + 86399) == MON,
		"实得 %d" % _P2.week_anchor_utc(SUN + 86399))
	_ok("① ★下一秒(周一 00:00:00)换周, 且正好差一周 604800 秒",
		_P2.week_anchor_utc(SUN + 86400) == MON2 and MON2 - MON == 604800,
		"实得 %d / 应为 %d" % [_P2.week_anchor_utc(SUN + 86400), MON2])

	## ★性质扫: 随机 400 个时刻, 锚点必须 ①落在周一 ②整日对齐 ③ts 减它落在 [0, 一周)
	##   —— 三条同时成立才叫「周锚点」, 少一条都能被一个错实现蒙混过去。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	var bad_wd := 0
	var bad_align := 0
	var bad_range := 0
	for _i in range(400):
		var ts: int = rng.randi_range(1500000000, 2100000000)
		var a: int = _P2.week_anchor_utc(ts)
		if _P2.iso_weekday_utc(a) != 1:
			bad_wd += 1
		if a % 86400 != 0:
			bad_align += 1
		var d: int = ts - a
		if d < 0 or d >= 604800:
			bad_range += 1
	_ok("① 性质扫(400 个随机时刻): 锚点全都落在周一", bad_wd == 0, "违例 %d/400" % bad_wd)
	_ok("① 性质扫: 锚点全都是整日 00:00:00", bad_align == 0, "违例 %d/400" % bad_align)
	_ok("① 性质扫: ts−锚点 全都落在 [0, 604800)", bad_range == 0, "违例 %d/400" % bad_range)


# ─────────────────────────────────────────────────────────────
# ② week_anchor_ts 是【活】的: 只改它, 产品的判定就翻面
# ─────────────────────────────────────────────────────────────
func _t_field_is_alive() -> void:
	print("── ② week_anchor_ts 有人读(不是死字段) ──")
	var now: int = int(Time.get_unix_time_from_system())
	var anchor: int = _P2.week_anchor_utc(now)
	_gs.season_start_ts = anchor        # 其余条件保持一致, 只让 week_anchor_ts 变

	_gs.week_anchor_ts = anchor
	var same_week: bool = bool(_gs.is_season_expired())
	_gs.week_anchor_ts = anchor - 604800
	var last_week: bool = bool(_gs.is_season_expired())
	_gs.week_anchor_ts = 0
	var never_set: bool = bool(_gs.is_season_expired())

	## ★★这几条合起来才是「活的」的证据: **同一个函数、只改这一个字段、答案变了**。
	_ok("② 锚点 = 本周 → 没过期", not same_week)
	_ok("② ★锚点 = 上周 → 过期(只改了这一个字段, 答案就翻面了)", last_week)
	_ok("② 锚点 = 0(未初始化) → 不算过期", not never_set)
	_ok("② ★★分母: 三种取值给出的答案确实不全相同(否则它就没被读)",
		not (same_week == last_week and last_week == never_set),
		"本周=%s 上周=%s 未初始化=%s" % [str(same_week), str(last_week), str(never_set)])


# ─────────────────────────────────────────────────────────────
# ③ 5 天时钟真的拔掉了 —— 光删常量不算, 得证明没人再按「时长」判
# ─────────────────────────────────────────────────────────────
func _t_five_day_clock_is_gone() -> void:
	print("── ③ 旧的 5 天时钟已拔除 ──")
	var now: int = int(Time.get_unix_time_from_system())
	var anchor: int = _P2.week_anchor_utc(now)
	_gs.week_anchor_ts = anchor
	_gs.season_start_ts = now - 10 * 365 * 86400     # 把「开赛时刻」推到十年前
	_ok("③ ★season_start_ts 推到十年前, 只要锚点还是本周就【不许过期】",
		not bool(_gs.is_season_expired()),
		"season_start_ts=%d(十年前) / 锚点=%d" % [int(_gs.season_start_ts), anchor])

	## ★常量表里不许再有它 —— 再加回来就意味着又有人想按「时长」滚轮。
	##   这条是**回归钉**: 判据落在「这个名字不存在」, 加回来当场红。
	## ⚠ 不能写 `_P2.get_script_constant_map()` —— `_P2` 是 const 类引用, 解析期会报
	##   「Cannot call non-static function ... directly」。`load()` 拿到的是**值**, 才调得动。
	##   ★判据落在**符号表**而不是源码子串: 注释里出现这个名字不该让门禁红
	##   (memory `fb-weld-visual-lessons-into-gate`: 源码子串匹配是假判据)。
	var sc: GDScript = load("res://scripts/gamedata/phase2_config.gd") as GDScript
	var cmap: Dictionary = sc.get_script_constant_map()
	_ok("③ ★分母: 常量表读得到(里面有周赛制的常量)",
		cmap.size() > 0 and cmap.has("RANKED_QUOTA"), "%d 个常量" % cmap.size())
	_ok("③ ★SEASON_DURATION_SEC 已经不在常量表里(别再按时长滚轮)",
		not cmap.has("SEASON_DURATION_SEC"),
		"实得 %s" % str(cmap.get("SEASON_DURATION_SEC", "(不存在)")))


# ─────────────────────────────────────────────────────────────
# ④ ensure_season() 四条分支, 逐条走真入口
# ─────────────────────────────────────────────────────────────
func _t_ensure_season_branches() -> void:
	print("── ④ ensure_season() 四条分支 ──")
	var now: int = int(Time.get_unix_time_from_system())
	var anchor: int = _P2.week_anchor_utc(now)

	# ── 分支①: 全新存档 ──
	_gs.season_start_ts = 0
	_gs.week_anchor_ts = 0
	var sid0: int = int(_gs.season_id)
	_gs.ensure_season()
	_ok("④ 分支①(全新存档): 锚点被填成本周", int(_gs.week_anchor_ts) == anchor,
		"实得 %d / 应为 %d" % [int(_gs.week_anchor_ts), anchor])
	_ok("④ 分支①: season_start_ts 也落在本周一 00:00", int(_gs.season_start_ts) == anchor,
		"实得 %d" % int(_gs.season_start_ts))
	_ok("④ ★分支①【不算滚轮】: season_id 不许 +1", int(_gs.season_id) == sid0,
		"跑之前 %d, 跑之后 %d" % [sid0, int(_gs.season_id)])

	# ── 分支②: 老存档迁移(5 天档 → 周档) ──
	#    ★这是本次改动里最容易写错的一条: 把「锚点=0」当成过期处理的话,
	#      所有老玩家升级到这一版的那一刻, 命/币/配额被平白清一次。
	_gs.season_start_ts = now - 3 * 86400     # 老档: 三天前按 5 天时钟开的赛季
	_gs.week_anchor_ts = 0                    # 老档没有这个字段 ⇒ 读出来是 0
	_gs.season_id = 5
	_gs.hearts = 3
	_gs.ranked_used = 7
	_gs.gauntlet_wins = 2
	_ok("④ ★分母: 迁移之前的局面确实是【打了一半】的(非默认值)",
		int(_gs.hearts) == 3 and int(_gs.ranked_used) == 7 and int(_gs.season_id) == 5,
		"hearts=3 ranked_used=7 season_id=5")
	_gs.ensure_season()
	_ok("④ 分支②(迁移): 锚点补上了", int(_gs.week_anchor_ts) == anchor,
		"实得 %d" % int(_gs.week_anchor_ts))
	_ok("④ ★★分支②: 命 / 配额 / 闯关战绩 / 赛季号 一个都没动(老玩家不被清档)",
		int(_gs.hearts) == 3 and int(_gs.ranked_used) == 7
		and int(_gs.gauntlet_wins) == 2 and int(_gs.season_id) == 5,
		"hearts=%d ranked_used=%d gauntlet_wins=%d season_id=%d" % [
			int(_gs.hearts), int(_gs.ranked_used), int(_gs.gauntlet_wins), int(_gs.season_id)])

	# ── 分支③: 同一周内再开游戏 → 什么都不该发生 ──
	_gs.ranked_used = 9
	_gs.hearts = 4
	var sid1: int = int(_gs.season_id)
	_gs.ensure_season()
	_ok("④ ★分支③(同一周再开): 配额不清、命不回满、赛季号不动",
		int(_gs.ranked_used) == 9 and int(_gs.hearts) == 4 and int(_gs.season_id) == sid1,
		"ranked_used=%d hearts=%d season_id=%d" % [
			int(_gs.ranked_used), int(_gs.hearts), int(_gs.season_id)])

	# ── 分支④: 跨周 → 滚下一大轮, 配额跟着自然周清 ──
	_gs.week_anchor_ts = anchor - 604800      # 上周的锚点
	_gs.ranked_used = 19
	_gs.hearts = 1
	_gs.gauntlet_wins = 3
	var sid2: int = int(_gs.season_id)
	_ok("④ ★分母: 滚轮之前配额是 19、命剩 1(不是默认值, 所以下面不是恒真式)",
		int(_gs.ranked_used) == 19 and int(_gs.hearts) == 1)
	_gs.ensure_season()
	_ok("④ ★★分支④(跨周): 积分赛配额清零 —— 这就是用户要的「配额跟着自然周滚」",
		int(_gs.ranked_used) == 0, "实得 %d" % int(_gs.ranked_used))
	_ok("④ 分支④: 命回到 8", int(_gs.hearts) == 8, "实得 %d" % int(_gs.hearts))
	_ok("④ 分支④: 闯关战绩清零", int(_gs.gauntlet_wins) == 0, "实得 %d" % int(_gs.gauntlet_wins))
	_ok("④ 分支④: 赛季号 +1", int(_gs.season_id) == sid2 + 1,
		"%d → %d" % [sid2, int(_gs.season_id)])
	_ok("④ ★★分支④: 锚点换成【本周】, 不是清成 0 —— 清成 0 就再也滚不动了",
		int(_gs.week_anchor_ts) == anchor,
		"实得 %d / 应为 %d" % [int(_gs.week_anchor_ts), anchor])
	## ★滚完立刻再调一次: 不许连滚两轮(幂等)
	var sid3: int = int(_gs.season_id)
	_gs.ensure_season()
	_ok("④ ★滚完再调一次不许再滚(幂等)", int(_gs.season_id) == sid3,
		"%d → %d" % [sid3, int(_gs.season_id)])


# ─────────────────────────────────────────────────────────────
# ⑤ 两套时钟合成一套: 换周那一刻 == 赛程翻到「周一休赛」那一刻
# ─────────────────────────────────────────────────────────────
func _t_roll_moment_matches_phase() -> void:
	print("── ⑤ 换轮时刻 == 赛程换阶段时刻 ──")
	## 拿真实日历那一周逐天走: 七天的锚点必须**全都一样**, 阶段则按设计逐天变。
	var anchors: Array = []
	var phases: Array = []
	for d in range(7):
		var ts: int = MON + d * 86400 + 43200      # 每天中午, 避开边界
		anchors.append(_P2.week_anchor_utc(ts))
		phases.append(_P2.phase_at_utc(ts))
	var all_same := true
	for a in anchors:
		if int(a) != MON:
			all_same = false
	_ok("⑤ ★一周七天的锚点全都是同一个(周一~周日不换轮)", all_same, str(anchors))
	_ok("⑤ ★分母: 这七天的阶段确实是按设计变的(休赛/积分×4/闯关/决赛)",
		phases == ["rest", "ranked", "ranked", "ranked", "ranked", "gauntlet", "finals"],
		str(phases))

	## ★★换周的那一秒, 阶段正好从「决赛日」翻到「休赛」—— 两件事是同一件事。
	var t_before: int = MON2 - 1      # 周日 23:59:59
	var t_after: int = MON2           # 周一 00:00:00
	_ok("⑤ ★★换周那一秒之前: 锚点=上周 且 阶段=决赛日",
		_P2.week_anchor_utc(t_before) == MON and _P2.phase_at_utc(t_before) == _P2.PHASE_FINALS,
		"锚点 %d / 阶段 %s" % [_P2.week_anchor_utc(t_before), _P2.phase_at_utc(t_before)])
	_ok("⑤ ★★换周那一秒之后: 锚点=新一周 且 阶段=休赛(周一维护窗口)",
		_P2.week_anchor_utc(t_after) == MON2 and _P2.phase_at_utc(t_after) == _P2.PHASE_REST,
		"锚点 %d / 阶段 %s" % [_P2.week_anchor_utc(t_after), _P2.phase_at_utc(t_after)])
