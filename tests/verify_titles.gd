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
##
## 跑法: <godot> --headless --path . res://tests/verify_titles.tscn --quit-after 600

const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0
## ★收尾要还原的存档字段（门禁不许污染玩家存档）
const KEYS := ["titles", "ranked_used", "promoted", "week_anchor_ts", "season_id",
	"season_start_ts", "hearts", "season_wins", "season_total_battles", "week_phase",
	"gauntlet_wins", "gauntlet_losses", "install_uid", "account_id", "account_email"]
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

	## ★没上线的档: 冠军/四强现在拿不到
	_ok("① ★★周日玩法没上线 ⇒ 冠军/四强**拿不到**",
		not P2C.title_earnable(P2C.TITLE_CHAMPION)
			and not P2C.title_earnable(P2C.TITLE_SEMIFINAL))
	_ok("① ★分母: 另两档现在拿得到(证明上面那条是「没上线」挡的, 不是函数恒 false)",
		P2C.title_earnable(P2C.TITLE_FINALS_DAY) and P2C.title_earnable(P2C.TITLE_FULL_QUOTA))
	_ok("① ★分母: 现在 PHASE_MODE_LIVE 里决赛日确实是 false",
		not P2C.phase_mode_live(P2C.PHASE_FINALS))

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

	_ok("② ★★没上线的档发不出来(冠军)",
		not GameState.award_title(P2C.TITLE_CHAMPION), str(GameState.titles.size()))
	_ok("② ★分母: 列表没变(还是两条)", GameState.titles.size() == 2)

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

	GameState.promoted = true
	GameState.ensure_season()
	await get_tree().process_frame
	_ok("③ ★★晋级了 ⇒ 真入口发「进决赛日」",
		P2C.title_has(GameState.titles, P2C.TITLE_FINALS_DAY, int(GameState.week_anchor_ts)),
		str(GameState.titles))
	_ok("③ ★分母: 现在两条(两档各一个)", GameState.titles.size() == 2, str(GameState.titles))


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
