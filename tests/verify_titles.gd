extends Node
## verify_titles.gd — 头衔 (E-B5 · D12 四档, 2026-09-24)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 头衔是**跨大轮唯一保留的资产**（D12）。它最致命的失败方式不是"发错了"，
## 是**静默丢失**：大轮切换或清档时被顺手清掉，玩家不会收到任何提示。
## ⇒ 这份门禁的头等大事是那两条「活下来」，而且**反向验证**必须证明
##   把它加进任一清除名单都会当场红。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① **两种重置各验一次**：`start_new_season()`（大轮切换）与 `reset_save()`（清档）
##      是两段**各自手写**的清除列表 —— 本仓正因为"两处各写一份"栽过好几次。
##      只验一条的话，另一条漏了没人知道。
## ★② **发放走真入口**：不直接调 `award_title()` 就算数，要让 `ensure_season()`
##      在"配额满 / 已晋级"的真实存档状态下自己发（memory `fb-verify-must-run-the-real-path`）。
## ★③ **没上线的档发不出来**：冠军/四强要周日玩法上线。这一条配分母 ——
##      把开关打开（纯函数层面）就必须发得出来，否则"发不出来"可能只是函数坏了。
## ★④ **同一周不重复发**：打满两次配额不该变成两个头衔。
## ★⑤ 每条"拿不到/没变化"都配分母。
## ★⑥ **冠军/四强的依据必须是服务端的 `done`，不是本地 `won`**（2026-09-26 新增第 ⑤ 段）。
##      周日是双方各自在本地打对方的快照、两边都可能算出自己赢（服务端
##      `finals_report` 用 `on conflict do nothing`，先报的算）⇒ 拿本地结果发冠军
##      头衔就是一个桶里出两个冠军。⇒ 判据全部从 `done` 造。
##
## 跑法: <godot> --headless --path . res://tests/verify_titles.tscn --quit-after 600

const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0
## ★收尾要还原的存档字段（门禁不许污染玩家存档）
const KEYS := ["titles", "ranked_used", "promoted", "week_anchor_ts", "season_id",
	"season_start_ts", "hearts", "season_wins", "season_total_battles", "week_phase",
	"gauntlet_wins", "gauntlet_losses", "install_uid", "account_id", "account_email",
	## ★2026-09-26 冠军/四强的发放依据(见第 ⑤ 段)。漏登记 = 门禁把玩家存档改了不还原。
	"finals_deepest_round", "finals_rounds_total", "finals_champion"]
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== 头衔 (E-B5) ===")
	_t_rules()
	_t_award()
	await _t_real_entry()
	_t_survive_resets()
	await _t_finals_titles()
	_t_quota_title_no_restart()
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 头衔" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 规则层(纯函数)
# ─────────────────────────────────────────────────────────────
func _t_rules() -> void:
	print("── ① 规则 ──")
	_ok("① 四档都有显示名", P2C.TITLE_LABEL.size() == 4 and P2C.TITLE_ORDER.size() == 4,
		"%d / %d" % [P2C.TITLE_LABEL.size(), P2C.TITLE_ORDER.size()])
	_ok("① ★展示顺序 = 含金量从高到低(冠军在最前)",
		str(P2C.TITLE_ORDER[0]) == P2C.TITLE_CHAMPION
			and str(P2C.TITLE_ORDER[3]) == P2C.TITLE_FULL_QUOTA, str(P2C.TITLE_ORDER))

	## ══════════════════════════════════════════════════════════════════
	## 冠军/四强这两档**跟着周日玩法的上线开关走**。
	##
	## ★★2026-09-25 用户「周日要打开」⇒ `PHASE_MODE_LIVE[PHASE_FINALS]` 翻成 true,
	##   这两档从此拿得到。原来这里写死「拿不到」+「开关确实是 false」两条,
	##   翻开关的当天它们必红 —— 而**那正是对的**: 判据钉住了当时的状态。
	##
	## ★判据不能只改成「现在拿得到」—— 那样把 `title_earnable` 退化成恒 true 也全绿。
	##   ⇒ 改成**跟着开关走的一对**: 开=拿得到 / 关=拿不到, 两边都验。
	##   `title_earnable` 直接吃 `phase_mode_live(PHASE_FINALS)`,而那是 **const 字典**
	##   (Godot 里改不动) ⇒ 只能拿真实值当分母, 但**两档对照**能挡住恒 true/恒 false:
	##   另两档(决赛日出场/满配额)与开关无关, 必须恒为 true。
	var finals_live := P2C.phase_mode_live(P2C.PHASE_FINALS)
	_ok("① ★分母: 打印现在的开关状态(判据跟着它走)", true, "PHASE_FINALS live = %s" % finals_live)
	_ok("① ★★冠军/四强 == 周日玩法上线状态(开就拿得到, 关就拿不到)",
		P2C.title_earnable(P2C.TITLE_CHAMPION) == finals_live
			and P2C.title_earnable(P2C.TITLE_SEMIFINAL) == finals_live,
		"冠军=%s 四强=%s 开关=%s" % [P2C.title_earnable(P2C.TITLE_CHAMPION),
			P2C.title_earnable(P2C.TITLE_SEMIFINAL), finals_live])
	_ok("① ★★分母: 另两档**与开关无关**恒拿得到(挡住 title_earnable 退化成恒值)",
		P2C.title_earnable(P2C.TITLE_FINALS_DAY) and P2C.title_earnable(P2C.TITLE_FULL_QUOTA))

	## 去重判据
	var lst: Array = [P2C.title_row(P2C.TITLE_FULL_QUOTA, 100)]
	_ok("① 同档同周 ⇒ 认得出已经有了",
		P2C.title_has(lst, P2C.TITLE_FULL_QUOTA, 100))
	_ok("① ★同档**不同周** ⇒ 不算重复(下一周再满配额该再拿一个)",
		not P2C.title_has(lst, P2C.TITLE_FULL_QUOTA, 200))
	_ok("① ★同周**不同档** ⇒ 不算重复",
		not P2C.title_has(lst, P2C.TITLE_FINALS_DAY, 100))

	## 计数与文字
	var many: Array = [
		P2C.title_row(P2C.TITLE_FULL_QUOTA, 1), P2C.title_row(P2C.TITLE_FULL_QUOTA, 2),
		P2C.title_row(P2C.TITLE_FINALS_DAY, 2), P2C.title_row(P2C.TITLE_CHAMPION, 3)]
	var cnt: Dictionary = P2C.title_counts(many)
	_ok("① 计数对", int(cnt.get(P2C.TITLE_FULL_QUOTA, 0)) == 2
		and int(cnt.get(P2C.TITLE_CHAMPION, 0)) == 1, str(cnt))
	var line := str(P2C.title_line(many))
	print("     完整串: 「%s」" % line)
	_ok("① ★按含金量排序, 只拿过一次的不写 ×1(×1 是噪声)",
		line == "冠军 · 进决赛日 · 满配额 ×2", line)
	_ok("① ★★主菜单只取**最高一档**(那一行 382px 放不下完整串)",
		str(P2C.title_top(many)) == "冠军", str(P2C.title_top(many)))
	_ok("① ★最高一档也带计数", str(P2C.title_top([
		P2C.title_row(P2C.TITLE_CHAMPION, 1), P2C.title_row(P2C.TITLE_CHAMPION, 2)])) == "冠军 ×2")
	_ok("① 空列表 ⇒ 空串(由调用方决定没头衔时显示什么)",
		P2C.title_line([]) == "" and P2C.title_top([]) == "")


# ─────────────────────────────────────────────────────────────
# ② 发放
# ─────────────────────────────────────────────────────────────
func _t_award() -> void:
	print("── ② 发放 ──")
	GameState.titles = []
	GameState.week_anchor_ts = 1789344000
	_ok("② ★分母: 一开始一个头衔都没有", GameState.titles.is_empty())
	_ok("② 发一个满配额 ⇒ 真的加了", GameState.award_title(P2C.TITLE_FULL_QUOTA))
	_ok("② ★★同一周再发一次 ⇒ **不重复加**(打满两次不该变成两个头衔)",
		not GameState.award_title(P2C.TITLE_FULL_QUOTA), "%d 条" % GameState.titles.size())
	_ok("② ★分母: 列表里就是一条", GameState.titles.size() == 1, str(GameState.titles))
	_ok("② ★下一周再满 ⇒ 再拿一个",
		GameState.award_title(P2C.TITLE_FULL_QUOTA, 1789344000 + 604800))
	_ok("② ★分母: 现在两条", GameState.titles.size() == 2, str(GameState.titles))

	## ★★2026-09-25 用户「周日要打开」⇒ 冠军这一档从「发不出来」变成「发得出来」。
	##   判据跟着 `title_earnable` 走(而它吃 `phase_mode_live(PHASE_FINALS)`),
	##   ★不是写死哪一边 —— 写死哪一边都会在下一次翻开关时变成假失败/假通过。
	var champ_ok := P2C.title_earnable(P2C.TITLE_CHAMPION)
	var n_before := GameState.titles.size()
	var awarded := GameState.award_title(P2C.TITLE_CHAMPION)
	_ok("② ★★冠军能不能发 == title_earnable 说的(现在 = %s)" % champ_ok,
		awarded == champ_ok, "实际发出=%s" % awarded)
	_ok("② ★分母: 列表条数跟着动(发了才 +1, 没发就不变)",
		GameState.titles.size() == n_before + (1 if champ_ok else 0),
		"%d → %d" % [n_before, GameState.titles.size()])

	## 赛程没初始化时不发 —— 发了记不清是哪一周
	GameState.titles = []
	GameState.week_anchor_ts = 0
	_ok("② ★赛程还没初始化(锚点=0) ⇒ 不发(发了记不清是哪一周)",
		not GameState.award_title(P2C.TITLE_FULL_QUOTA) and GameState.titles.is_empty())
	GameState.week_anchor_ts = 1789344000


# ─────────────────────────────────────────────────────────────
# ③ ★★走真入口: ensure_season 自己把该发的发了
# ─────────────────────────────────────────────────────────────
func _t_real_entry() -> void:
	print("── ③ 真入口(ensure_season 补齐) ──")
	GameState.titles = []
	GameState.season_id = 1
	GameState.season_start_ts = int(Time.get_unix_time_from_system())
	GameState.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	GameState.ranked_used = 0
	GameState.promoted = false
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★分母: 什么都没达成 ⇒ 一个头衔都不发", GameState.titles.is_empty(),
		str(GameState.titles))

	GameState.ranked_used = int(P2C.RANKED_QUOTA)
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★★配额打满 ⇒ **真入口自己发了**满配额",
		P2C.title_has(GameState.titles, P2C.TITLE_FULL_QUOTA, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	var n1: int = GameState.titles.size()
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★再走一次入口 ⇒ 不重复发(%d 条没变)" % n1, GameState.titles.size() == n1,
		str(GameState.titles.size()))

	## ★★2026-10-03 周六实操 S4: 原来这里断言「promoted(积分赛过线)⇒ 发进决赛日」—— 门禁替 bug 站岗:
	##   周六 0-0 就挂着「进决赛日」, 3-3 出局后还挂着。头衔要的是**周六闯关赛晋级**。
	GameState.promoted = true
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 0
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★★只是有资格打周六(0-0) ⇒ **不发**「进决赛日」",
		not P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	GameState.gauntlet_wins = 3
	GameState.gauntlet_losses = 3
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★★周六 3-3 出局 ⇒ **不发**",
		not P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 0
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★★周六 4 胜晋级 ⇒ 真入口发「进决赛日」",
		P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	_ok("③ ★分母: 现在两条(两档各一个)", GameState.titles.size() == 2, str(GameState.titles))
	## ③b 回收(用户 2026-10-04「只回收本周的」): 本周错发的「进决赛日」在不是 4 胜晋级时收回, 上周的不动
	var wk: int = int(GameState.week_anchor_ts)
	GameState.titles = [P2C.title_row(P2C.TITLE_FINALS_DAY, wk), P2C.title_row(P2C.TITLE_FINALS_DAY, wk - 604800)]
	GameState.gauntlet_wins = 3
	GameState.gauntlet_losses = 3
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③b ★★本周 3-3 出局 ⇒ 本周那条「进决赛日」收回", not P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, wk), str(GameState.titles))
	_ok("③b ★★上周那条不动(上周战绩已清, 判不了)", P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, wk - 604800), str(GameState.titles))
	GameState.titles = [P2C.title_row(P2C.TITLE_FINALS_DAY, wk)]
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 1
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③b ★分母: 本周真晋级(4-1)的不收", P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, wk), str(GameState.titles))


# ─────────────────────────────────────────────────────────────
# ④ ★★★跨两种重置都要活下来 —— 这份门禁的头等大事
# ─────────────────────────────────────────────────────────────
func _t_survive_resets() -> void:
	print("── ④ 跨重置(头等大事) ──")
	GameState.titles = [P2C.title_row(P2C.TITLE_CHAMPION, 7),
		P2C.title_row(P2C.TITLE_FULL_QUOTA, 8)]
	GameState.ranked_used = 13
	var before: int = GameState.titles.size()
	_ok("④ ★分母: 重置前有 %d 条" % before, before == 2)

	GameState.start_new_season()
	_ok("④ ★★★大轮切换(start_new_season) ⇒ 头衔**一条都不许少**",
		GameState.titles.size() == before, "%d → %d" % [before, GameState.titles.size()])
	_ok("④ ★分母: 同一次切换里 ranked_used 确实被清了(证明清除逻辑真的跑了)",
		int(GameState.ranked_used) == 0, str(GameState.ranked_used))

	GameState.ranked_used = 9
	GameState.reset_save()
	_ok("④ ★★★清档(reset_save) ⇒ 头衔**一条都不许少**",
		GameState.titles.size() == before, "%d → %d" % [before, GameState.titles.size()])
	_ok("④ ★分母: 同一次清档里 ranked_used 确实被清了",
		int(GameState.ranked_used) == 0, str(GameState.ranked_used))
	_ok("④ 内容也没变(还是冠军 + 满配额)",
		P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, 7)
			and P2C.title_has(GameState.titles, P2C.TITLE_FULL_QUOTA, 8), str(GameState.titles))

	## 存档往返
	var payload: Dictionary = GameState.cloud_payload()
	_ok("④ ★头衔进了存档载荷(不然重开游戏就没了)",
		(payload.get("titles", []) as Array).size() == before, str(payload.get("titles")))

# ─────────────────────────────────────────────────────────────
# ⑤ ★★★冠军 / 四强: 依据是服务端 feed 里的 `done`
# ─────────────────────────────────────────────────────────────
## 方案书 `docs/plans/20260926-冠军四强头衔发放.md`。
##
## 在这一段之前，`TITLE_CHAMPION` / `TITLE_SEMIFINAL` **没有任何发放路径** ——
## 常量、中文标签、显示顺序、`title_earnable` 全齐，而 `award_title()` 全仓
## 只有两个调用点（满配额 / 已晋级）。周日夺冠的人拿到的头衔和周六晋级的一模一样。
##
## ★判据分两层，各管一件事：
##   (a) 纯函数 `Bracket.my_progress(me, n, done)` —— 走到第几轮 / 有没有夺冠
##   (b) 真入口 `ensure_season() → sync_titles()` —— 从存档里那三个字段发头衔
## ★「四强」= **被排进**倒数第二轮（那一轮正好 4 人）⇒ 原稿「打进四强」问的是名次，
##   不要求赢。所以 (a) 里「排进决赛但输了」必须**有四强、没有冠军**。
const _BR := preload("res://scripts/gamedata/bracket.gd")

func _t_finals_titles() -> void:
	print("── ⑤ 冠军/四强(依据 = 服务端 done) ──")

	## ── (a) 纯函数 ──────────────────────────────────────────────
	## 4 人桶: 2 轮。第 1 轮两场(0/1) = 四强, 第 2 轮一场 = 决赛。
	var n4 := 4
	_ok("⑤a ★分母: 4 人桶共 2 轮", _BR.rounds_for(n4) == 2, "%d 轮" % _BR.rounds_for(n4))
	## 我是 0 号种子。先看「一场都还没打」
	var p0: Dictionary = _BR.my_progress(0, n4, {})
	_ok("⑤a 一场没打 ⇒ 最深 1 轮、没夺冠",
		int(p0.get("deepest", -1)) == 1 and not bool(p0.get("champion", true)), str(p0))
	_ok("⑤a ★分母: 这时还不算四强(total=2 ⇒ 要走到第 1 轮才算… 第 1 轮就是四强)",
		_BR.semifinal_reached(int(p0.get("deepest", 0)), 2))

	## 我赢了第 1 轮 ⇒ 被排进决赛
	var my_side_r1: int = _BR.my_side_in(0, 1, 0, n4, {})
	_ok("⑤a ★分母: 我(0 号种子)在第 1 轮第 0 场里有一侧", my_side_r1 >= 0, "side=%d" % my_side_r1)
	var done_semi := {"1-%d" % 0: my_side_r1}
	var p1: Dictionary = _BR.my_progress(0, n4, done_semi)
	_ok("⑤a 赢下第 1 轮 ⇒ 最深变成 2(被排进决赛)", int(p1.get("deepest", -1)) == 2, str(p1))
	_ok("⑤a ★★被排进决赛但决赛还没结果 ⇒ **不算夺冠**",
		not bool(p1.get("champion", true)), str(p1))

	## 决赛我赢 ⇒ 冠军; 决赛我输 ⇒ 只有四强
	var my_side_f: int = _BR.my_side_in(0, 2, 0, n4, done_semi)
	_ok("⑤a ★分母: 我在决赛里有一侧", my_side_f >= 0, "side=%d" % my_side_f)
	var done_win := done_semi.duplicate()
	done_win["2-0"] = my_side_f
	var done_lose := done_semi.duplicate()
	done_lose["2-0"] = 1 - my_side_f
	_ok("⑤a ★★★决赛 done 说我那一侧赢 ⇒ 夺冠",
		bool(_BR.my_progress(0, n4, done_win).get("champion", false)))
	_ok("⑤a ★★★决赛 done 说**对手那一侧**赢 ⇒ 不夺冠(这一条挡住「两边都赢」)",
		not bool(_BR.my_progress(0, n4, done_lose).get("champion", true)))

	## 纯观众 / 2 人桶
	var pv: Dictionary = _BR.my_progress(-1, n4, done_win)
	_ok("⑤a ★★纯观众(me < 0) ⇒ 最深 0、不夺冠", int(pv.get("deepest", -1)) == 0
		and not bool(pv.get("champion", true)), str(pv))
	_ok("⑤a ★★2 人桶只有决赛那一轮 ⇒ **不发四强**(那一轮就是冠军赛)",
		_BR.rounds_for(2) == 1 and not _BR.semifinal_reached(1, 1),
		"2 人 %d 轮" % _BR.rounds_for(2))
	_ok("⑤a ★分母: 4 人桶走到第 1 轮就算四强(证明上一条不是恒 false)",
		_BR.semifinal_reached(1, 2))

	## ── (b) 真入口: ensure_season → sync_titles ─────────────────
	GameState.titles = []
	GameState.season_id = 1
	GameState.season_start_ts = int(Time.get_unix_time_from_system())
	GameState.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	GameState.ranked_used = 0
	GameState.promoted = false
	GameState.finals_deepest_round = 0
	GameState.finals_rounds_total = 0
	GameState.finals_champion = false
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("⑤b ★分母: 什么都没达成 ⇒ 一个头衔都不发", GameState.titles.is_empty(),
		str(GameState.titles))

	## 走到四强(4 人桶第 1 轮)但没夺冠
	GameState.record_finals_progress(1, 2, false)
	GameState.ensure_season()
	await get_tree().process_frame
	var has_semi: bool = P2C.title_has(GameState.titles, P2C.TITLE_SEMIFINAL,
		int(GameState.week_anchor_ts))
	var has_champ: bool = P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION,
		int(GameState.week_anchor_ts))
	_ok("⑤b ★★★走到四强 ⇒ 真入口把【四强】发了", has_semi, str(GameState.titles))
	_ok("⑤b ★★★没夺冠 ⇒ **冠军一条都不许有**", not has_champ, str(GameState.titles))

	## 夺冠
	GameState.record_finals_progress(2, 2, true)
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("⑤b ★★★夺冠 ⇒ 真入口把【冠军】发了",
		P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	_ok("⑤b ★分母: 四强还在(夺冠不该顶掉四强)",
		P2C.title_has(GameState.titles, P2C.TITLE_SEMIFINAL, int(GameState.week_anchor_ts)))
	var n_before := GameState.titles.size()
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("⑤b ★★再对一次账 ⇒ 不重复发", GameState.titles.size() == n_before,
		"%d → %d" % [n_before, GameState.titles.size()])

	## ── (c) 只增不减 ───────────────────────────────────────────
	## feed 故意不下发当前轮 ⇒ 这几个值只会往上走。喂一个更小的进来不许把依据抹掉。
	_ok("⑤c ★★喂更小的值 ⇒ 不变(返回 false)",
		not GameState.record_finals_progress(1, 1, false))
	_ok("⑤c ★分母: 大的值确实还在",
		int(GameState.finals_deepest_round) == 2 and int(GameState.finals_rounds_total) == 2
		and bool(GameState.finals_champion),
		"%d/%d/%s" % [GameState.finals_deepest_round, GameState.finals_rounds_total,
			str(GameState.finals_champion)])

	## ── (d) 周换轮把依据清掉(头衔本身不清) ─────────────────────
	var titles_before := GameState.titles.size()
	GameState.start_new_season()
	_ok("⑤d ★★★切轮 ⇒ 三个依据字段都清零(上周的冠军不许顺延成本周的头衔)",
		int(GameState.finals_deepest_round) == 0 and int(GameState.finals_rounds_total) == 0
		and not bool(GameState.finals_champion),
		"%d/%d/%s" % [GameState.finals_deepest_round, GameState.finals_rounds_total,
			str(GameState.finals_champion)])
	_ok("⑤d ★分母: 头衔本身一条都没少(清的是依据不是荣誉)",
		GameState.titles.size() == titles_before,
		"%d → %d" % [titles_before, GameState.titles.size()])


# ─────────────────────────────────────────────────────────────
# ⑥ QUOTA_TITLE_NO_RESTART —— 打满那一刻称号就该在, 不用重启游戏
#
# 由来(2026-09-30 台账 ⑱): 用户的十个真号有 7 个打满了 24 场, 而存档里
#   `titles` **全是空的**。
# ★根因不是发放逻辑坏了, 是**顺序**: `_settle_season()` 调 `ensure_season()`
#   在 `ranked_used++` 的**前面**(那行注释自己写着「下方 season_total_battles++
#   /coins+= 全在这行之后」) ⇒ 打满那一场结束时它看到的还是 23 ⇒ 不发；
#   而**打满之后不会再有下一场**(配额把门关了) ⇒ 唯一的补发时机再也不会到来。
#   探针实测: 拿 `ranked_used=24` 的真存档开机, `titles` 当场就有 `full_quota`,
#   手动再 `sync_titles()` 新发 **0** 条 ⇒ 条件一直满足, 缺的只是有人再调一次。
#
# ★★判据必须走**产品自己的那个函数** `consume_ranked_quota()`(结算路径调的就是它),
#   不许在测试里自己 `ranked_used = QUOTA` 再 `sync_titles()` —— 那样测的是我的
#   复现步骤, 不是产品的路径(memory `fb-verify-must-run-the-real-path`)。
# ★★并且**不许调 `ensure_season()`** —— 那正是"重启才看得见"的那条路。
#   这一节的全部意思就是「不靠它也得有」。
# ★分母两条: ①打满前那一刻称号**不能**已经在(否则整节恒真)
#            ②`ranked_used` 真的从 QUOTA-1 走到了 QUOTA(否则量的是别的东西)
# ─────────────────────────────────────────────────────────────
func _t_quota_title_no_restart() -> void:
	var wk: int = 1789344000            # 一个固定的周一锚点(与本文件别处同一个口径)
	GameState.titles = []
	GameState.week_anchor_ts = wk
	GameState.season_start_ts = wk
	GameState.week_phase = P2C.PHASE_RANKED
	GameState.ranked_used = int(P2C.RANKED_QUOTA) - 1
	GameState.promoted = false
	GameState.finals_deepest_round = 0
	GameState.finals_rounds_total = 0
	GameState.finals_champion = false

	## ★分母①: 差一场的时候不许已经有 —— 证明下面那条断言不是恒真的
	_ok("⑥ ★分母: 差 1 场时「满配额」还不该有",
		not P2C.title_has(GameState.titles, P2C.TITLE_FULL_QUOTA, wk),
		"ranked_used=%d / titles=%s" % [GameState.ranked_used, str(GameState.titles)])

	var used_before: int = int(GameState.ranked_used)
	## 产品自己的那一步: 打完这一场吃掉一格配额。**故意不调 ensure_season()**。
	GameState.consume_ranked_quota()

	## ★分母②: 配额真的走到了打满, 不然上面那一步等于没发生
	_ok("⑥ ★分母: 配额真的从 %d 走到 %d" % [used_before, int(P2C.RANKED_QUOTA)],
		int(GameState.ranked_used) == int(P2C.RANKED_QUOTA)
			and int(GameState.ranked_used) == used_before + 1,
		"%d → %d" % [used_before, int(GameState.ranked_used)])

	## ★★★正题: 打满那一刻称号就在 —— 没有重启、没有 ensure_season()
	_ok("⑥ ★★★QUOTA_TITLE_NO_RESTART: 打满的那一场结束就该有「满配额」(不用关掉游戏重开)",
		P2C.title_has(GameState.titles, P2C.TITLE_FULL_QUOTA, wk),
		"ranked_used=%d/%d  titles=%s" % [GameState.ranked_used,
			int(P2C.RANKED_QUOTA), str(GameState.titles)])

	## ★幂等: 再打一场(超配额)不许多发一条 —— `sync_titles` 按 {id, week} 去重
	var n_before: int = GameState.titles.size()
	GameState.consume_ranked_quota()
	_ok("⑥ 幂等: 再吃一格配额不许多发一条同周同档",
		GameState.titles.size() == n_before,
		"%d → %d  titles=%s" % [n_before, GameState.titles.size(), str(GameState.titles)])
