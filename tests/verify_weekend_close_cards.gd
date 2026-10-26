extends Node
## verify_weekend_close_cards.gd — 周末收盘卡 / 深海币入账动画 / 拦截卡 / 结算屏闯关文案(2026-10-26)
##
## 方案书 docs/plans/20261026b-周六流程.md §4 A~F。用户 10-26:
##   「晋级的人……补发深海币和经验，有任何提示方式吗」「没晋级的你第一次进搞个弹窗？你设计一下」
##   「获得深海币有动画吗，看看商业游戏」「文案你学习商业游戏的说法」「不要加下一局按钮」
##
## ① WeekCloseCard.due 时间 × 状态矩阵(收盘前不弹 / 收盘后按状态弹哪一张 / 本周弹过不再弹 / 换周再弹 / 存档还在上一周不弹)
## ② 卡上的钱与真发钱的账同一份: 走产品自己的 settle_ranked_close / settle_gauntlet_close 发钱, 再读卡
## ③ 真入口: MainMenu 当 current_scene 建起来 ⇒ 卡真弹 ⇒ 钱包先显示旧值 ⇒ 点「领取」⇒ 币飞完钱包 == 真余额 ⇒ 再建一次不弹
## ④ CoinFly: 份额拆分(枚数封顶、余数落最后一枚)/ gain_since_seen / 播完数字 == 终值 / 点一下立刻收尾
## ⑤ 结算屏闯关文案: 战绩 + 处境(关键节点换说法)/ 第 4 胜大字「已晋级！」/ 经验格 / 结算屏按钮没有「下一局」
## ⑥ 开始战斗被拦: 弹一张卡(不是飘字), 正文 == `_battle_block_msg`, 周末没资格的给「观战」; 模式卡锁着时第三格是去处
## ⑦ 模式卡第二行放得下(去掉补发长尾之后, 所有周末状态都是一行)
## ⑧ 文案规矩: 卡与拦截句不含「补发 / 折算 / ·」
##
## 跑法: <godot> --headless --path . res://tests/verify_weekend_close_cards.tscn --quit-after 3000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const HUD := preload("res://scripts/scenes/battle/battle_hud.gd")
const WCC := preload("res://scripts/scenes/week_close_card.gd")
const CF := preload("res://scripts/util/coin_fly.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")

## 2026-10-26 周一 00:00 UTC
const MON := 1792972800
const DAY := 86400

var _fail := 0
var _n := 0
var _bak := {}
const FIELDS := ["week_anchor_ts", "season_start_ts", "promoted", "ranked_used", "season_wins", "hearts", "gauntlet_wins",
	"gauntlet_losses", "backfill_paid", "gauntlet_backfill_paid", "close_card_ranked_wk", "close_card_gauntlet_wk",
	"meta_deepsea_coins", "season_total_battles", "season_leaders", "week_phase"]


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


class FakeBattle extends RefCounted:
	var _had_season := true
	var _last_reward := 8
	var _last_was_exhibition := false
	var _last_settle_kind := ""


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周末收盘卡 / 入账动画 / 拦截卡 / 闯关结算文案 ===")
	for f in FIELDS:
		_bak[f] = GameState.get(f)
	_t_due()
	_t_amounts()
	_t_coinfly_pure()
	_t_settle_copy()
	_t_copy_rules()
	await _t_real_menu_card()
	await _t_coinfly_play()
	await _t_block_card()
	_t_mode_rule_fits()
	for f in FIELDS:
		GameState.set(f, _bak[f])
	print("ALL PASS — 周末收盘卡 (%d 条)" % _n if _fail == 0 else "FAIL x%d / %d" % [_fail, _n])
	get_tree().quit()


## 摆一个「本周」的干净局面。
func _fresh(promoted: bool, ranked_used: int, wins: int, hearts: int) -> void:
	GameState.week_anchor_ts = MON
	GameState.season_start_ts = MON
	GameState.promoted = promoted
	GameState.ranked_used = ranked_used
	GameState.season_wins = wins
	GameState.hearts = hearts
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 0
	GameState.backfill_paid = 0
	GameState.gauntlet_backfill_paid = 0
	GameState.close_card_ranked_wk = 0
	GameState.close_card_gauntlet_wk = 0


# ① ─────────────────────────────────────────────────────────────
func _t_due() -> void:
	print("── ① 什么时候弹哪一张 ──")
	var fri_pre: int = P2.ranked_close_ts(MON) - 60
	var fri_post: int = P2.ranked_close_ts(MON) + 60
	var sun_pre: int = P2.gauntlet_close_ts(MON) - 60
	var sun_post: int = P2.gauntlet_close_ts(MON) + 60
	_ok("① 分母: 积分赛收盘 = 周五 23:00 / 闯关赛收盘 = 周日 17:30(UTC)",
		P2.ranked_close_ts(MON) == MON + 4 * DAY + 23 * 3600 and P2.gauntlet_close_ts(MON) == MON + 6 * DAY + 17 * 3600 + 1800)
	_fresh(true, 12, 12, 5)
	_ok("① 收盘前(周五 22:59)一张都不弹", WCC.due(GameState, fri_pre).is_empty(), str(WCC.due(GameState, fri_pre)))
	_ok("① 收盘后 + 晋级 ⇒ 积分赛已晋级卡", WCC.due(GameState, fri_post) == [WCC.KIND_RANKED_IN], str(WCC.due(GameState, fri_post)))
	_fresh(false, 16, 9, 1)
	_ok("① 收盘后 + 没晋级(打过) ⇒ 积分赛已结束卡", WCC.due(GameState, fri_post) == [WCC.KIND_RANKED_OUT], str(WCC.due(GameState, fri_post)))
	_fresh(false, 0, 0, 6)
	_ok("① 本周一场没打的号不弹(他没参加)", WCC.due(GameState, fri_post).is_empty())
	_fresh(true, 12, 12, 5)
	GameState.close_card_ranked_wk = MON
	_ok("① ★本周弹过 ⇒ 不再弹", WCC.due(GameState, fri_post).is_empty())
	GameState.close_card_ranked_wk = MON - 7 * DAY
	_ok("① ★记的是上一周 ⇒ 这一周照弹", WCC.due(GameState, fri_post) == [WCC.KIND_RANKED_IN])
	GameState.close_card_ranked_wk = 0
	GameState.week_anchor_ts = MON - 7 * DAY
	_ok("① 存档还停在上一周(没滚轮)⇒ 不弹(那时的晋级 / 战绩是上一周的)", WCC.due(GameState, fri_post).is_empty())
	## 闯关赛
	_fresh(true, 12, 16, 5)
	GameState.close_card_ranked_wk = MON
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 0
	_ok("① 周日 17:29(闯关赛还没收盘)⇒ 不弹闯关卡", WCC.due(GameState, sun_pre).is_empty(), str(WCC.due(GameState, sun_pre)))
	_ok("① ★周日 17:31 + 4 胜 ⇒ 闯关赛已晋级卡", WCC.due(GameState, sun_post) == [WCC.KIND_GAUNTLET_IN], str(WCC.due(GameState, sun_post)))
	GameState.gauntlet_wins = 2
	GameState.gauntlet_losses = 1
	_ok("① 收盘时还没打完(2-1)⇒ 闯关赛已截止卡", WCC.due(GameState, sun_post) == [WCC.KIND_GAUNTLET_CUT])
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 0
	_ok("① 晋级了但闯关赛一场没打 ⇒ 不弹闯关卡", WCC.due(GameState, sun_post).is_empty())
	GameState.gauntlet_wins = 1
	GameState.gauntlet_losses = 3
	_ok("① 已出局(结算屏当场说过)⇒ 不再弹", WCC.due(GameState, sun_post).is_empty())
	GameState.close_card_ranked_wk = 0
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 1
	_ok("① 周末一次没开游戏、周日晚上才来 ⇒ 两张按先后都弹", WCC.due(GameState, sun_post) == [WCC.KIND_RANKED_IN, WCC.KIND_GAUNTLET_IN],
		str(WCC.due(GameState, sun_post)))
	WCC.mark_seen(GameState, WCC.KIND_RANKED_IN, sun_post)
	WCC.mark_seen(GameState, WCC.KIND_GAUNTLET_IN, sun_post)
	_ok("① mark_seen 之后两张都不再弹", WCC.due(GameState, sun_post).is_empty()
		and int(GameState.close_card_ranked_wk) == MON and int(GameState.close_card_gauntlet_wk) == MON)


# ② ─────────────────────────────────────────────────────────────
func _t_amounts() -> void:
	print("── ② 卡上的钱 == 真发出去的钱 ──")
	var fri_post: int = P2.ranked_close_ts(MON) + 60
	_fresh(false, 12, 12, 5)
	var c0: int = 100
	GameState.meta_deepsea_coins = c0
	var paid: int = GameState.settle_ranked_close(fri_post)   # 产品自己的收盘补算(晋级判定 + 发钱)
	_ok("② 分母: 收盘补算真把人判成晋级、发了 4 场", bool(GameState.promoted) and paid == 4, "paid=%d promoted=%s" % [paid, GameState.promoted])
	var d: Dictionary = WCC.spec(WCC.KIND_RANKED_IN, GameState, fri_post)
	var got: int = int(GameState.meta_deepsea_coins) - c0
	_ok("② ★卡上深海币 == 真进钱包的那一笔", int(d["coins"]) == got and got == 4 * int(P2.RANKED_BACKFILL_COINS), "卡=%d 钱包多了=%d" % [int(d["coins"]), got])
	_ok("② ★卡上经验 == backfill_summary 的经验", int(d["xp"]) == int(GameState.backfill_summary()["xp"]) and int(d["xp"]) == 4 * int(P2.RANKED_BACKFILL_XP))
	var body: String = "".join(PackedStringArray(d["body"]))
	_ok("② 正文报战绩(12 胜 1 负)与场数(4 场)", body.find("12 胜 1 负") >= 0 and body.find("4 场") >= 0, body)
	## ★用户 10-26「玩家比如4-0，他是不明白为什么会有未打完的2场的」⇒ 句子里先把上限说出来
	_ok("② ★正文把上限说出来(每周最多 %d 场), 才说没打的几场照发" % int(P2.RANKED_QUOTA),
		body.find("最多 %d 场" % int(P2.RANKED_QUOTA)) >= 0 and body.find("照发") >= 0, body)
	_ok("② ★闯关赛截止时刻按设备时区说(local_wd_hhmm)", body.find(P2.local_wd_hhmm(P2.gauntlet_close_ts(MON))) >= 0, body)
	_ok("② 有奖励 ⇒ 主按钮「领取」", str((d["primary"] as Array)[0]) == WCC.TXT_CLAIM)
	## 打满 16 场的晋级者: 没有化成的场次 ⇒ 没有奖励行、按钮「好的」
	_fresh(false, 16, 13, 4)
	GameState.settle_ranked_close(fri_post)
	var d2: Dictionary = WCC.spec(WCC.KIND_RANKED_IN, GameState, fri_post)
	_ok("② 16 场打满的晋级者: 没有奖励、按钮「好的」、正文不提化成", int(d2["coins"]) == 0 and str((d2["primary"] as Array)[0]) == WCC.TXT_OK
		and "".join(PackedStringArray(d2["body"])).find("化成") < 0, str(d2))
	## 闯关 4-0 ⇒ 省下的 2 场在第 4 胜那一刻就发(2026-10-26), 收盘那条惰性补算不再重复发
	var sun_post: int = P2.gauntlet_close_ts(MON) + 60
	_fresh(true, 12, 16, 5)
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 0
	GameState.meta_deepsea_coins = c0
	var bp: int = GameState.gauntlet_promote_bonus()
	_ok("② ★4-0 晋级当场发省下的 2 场", bp == 2 and int(GameState.meta_deepsea_coins) - c0 == 2 * int(P2.GAUNTLET_BACKFILL_COINS),
		"发了 %d 场 / 钱包 +%d" % [bp, int(GameState.meta_deepsea_coins) - c0])
	var gp: int = GameState.settle_gauntlet_close(sun_post)
	_ok("② ★收盘时那条惰性补算不再重复发(幂等)", gp == 0 and int(GameState.meta_deepsea_coins) - c0 == 2 * int(P2.GAUNTLET_BACKFILL_COINS), "paid=%d" % gp)
	var g: Dictionary = WCC.spec(WCC.KIND_GAUNTLET_IN, GameState, sun_post)
	_ok("② ★闯关卡不再发奖励(当场就发过了, 不出「领取」)", int(g["coins"]) == 0 and int(g["xp"]) == 0
		and str((g["primary"] as Array)[0]) == WCC.TXT_BRACKET, str(g))
	_ok("② 闯关卡正文: 4 胜 0 负 + 决赛日几点", "".join(PackedStringArray(g["body"])).find("4 胜 0 负") >= 0
		and "".join(PackedStringArray(g["body"])).find(P2.STAGE_GROUP) >= 0, str(g["body"]))
	_ok("② 对照: 没晋级(3-0)时一场都不发", (func() -> bool:
		GameState.gauntlet_wins = 3
		GameState.gauntlet_backfill_paid = 0
		return GameState.gauntlet_promote_bonus() == 0).call())
	_t_referee_bonus(c0)
	## 没晋级: 胜场不够 / 命用完 两种说法
	_fresh(false, 16, 9, 1)
	var o: String = "".join(PackedStringArray(WCC.spec(WCC.KIND_RANKED_OUT, GameState, P2.ranked_close_ts(MON) + 60)["body"]))
	_ok("② 没晋级(胜场不够): 报战绩 + 还差几胜", o.find("9 胜 5 负") >= 0 and o.find("还差 %d 胜" % (int(P2.PROMOTE_WINS) - 9)) >= 0, o)
	_fresh(false, 14, 8, 0)
	var o2: String = "".join(PackedStringArray(WCC.spec(WCC.KIND_RANKED_OUT, GameState, P2.ranked_close_ts(MON) + 60)["body"]))
	_ok("② 没晋级(命用完): 说生命已经用完", o2.find("生命已经用完") >= 0 and o2.find("8 胜 6 负") >= 0, o2)
	var od: Dictionary = WCC.spec(WCC.KIND_RANKED_OUT, GameState, P2.ranked_close_ts(MON) + 60)
	_ok("② 没晋级的卡给「观战」(周六去全场赛况)", (od["primary"] as Array) == [WCC.TXT_WATCH, WCC.DOOR_BOARD], str(od["primary"]))


# ④ ─────────────────────────────────────────────────────────────
func _t_coinfly_pure() -> void:
	print("── ④ 入账动画: 份额 / 记账 ──")
	_ok("④ +8 ⇒ 8 枚各 1", CF.split(8) == [1, 1, 1, 1, 1, 1, 1, 1], str(CF.split(8)))
	var s56: Array = CF.split(56)
	_ok("④ ★+56 ⇒ 封顶 10 枚, 前 9 枚各 5、最后一枚 11(余数落最后)", s56.size() == int(CF.MAX_COINS) and int(s56[0]) == 5 and int(s56[9]) == 11, str(s56))
	var tot := 0
	for x in CF.split(1234):
		tot += int(x)
	_ok("④ 份额加起来 == 金额(1234)", tot == 1234)
	_ok("④ 0 ⇒ 不拆", CF.split(0).is_empty())
	CF.seen = -1
	_ok("④ 进程刚起第一次看钱包 ⇒ 不算收入", CF.gain_since_seen(500) == 0)
	_ok("④ 之后多了 8 ⇒ 收入 8", CF.gain_since_seen(508) == 8)
	_ok("④ 花掉了(变少)⇒ 0, 不倒着飞", CF.gain_since_seen(400) == 0 and CF.seen == 400)


# ⑤ ─────────────────────────────────────────────────────────────
func _t_settle_copy() -> void:
	print("── ⑤ 闯关赛结算屏 ──")
	var cases := [
		[0, 1, "再胜 4 场晋级决赛日，再负 2 场出局"],
		[1, 1, "再胜 3 场晋级决赛日，再负 2 场出局"],
		[3, 0, "再胜一场即可晋级决赛日"],
		[2, 2, "再负一场，本周闯关赛即结束"],
		[3, 2, "下一场决定去留"],
		[4, 1, "你已晋级周日决赛日"],
		[1, 3, "你本周的闯关赛到此结束"],
	]
	var bad: Array = []
	for c in cases:
		var t: String = P2.gauntlet_settle_line(int(c[0]), int(c[1]))
		if t.find(str(c[2])) < 0 or t.find("%d-%d" % [int(c[0]), int(c[1])]) < 0:
			bad.append("%d-%d「%s」" % [int(c[0]), int(c[1]), t])
	_ok("⑤ ★七种战绩各说各的处境, 且都带战绩", bad.is_empty(), str(bad))
	_ok("⑤ 结果页不写「出局」二字(1-3 那句)", P2.gauntlet_settle_line(1, 3).find("出局") < 0)
	var fb := FakeBattle.new()
	fb._last_settle_kind = P2.SETTLE_GAUNTLET
	var hud = HUD.new(fb)
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 1
	_ok("⑤ ★第 4 胜那一局大字「已晋级！」", str(hud._result_headline(true, false, GameState)) == "已晋级！", str(hud._result_headline(true, false, GameState)))
	GameState.gauntlet_backfill_paid = 1       # 4-1 晋级当场发了省下的 1 场(GameState.gauntlet_promote_bonus)
	_ok("⑤ ★晋级那一局的小字说周日几点开打(设备时区)", str(hud._result_detail(GameState)).find(P2.STAGE_GROUP) >= 0
		and str(hud._result_detail(GameState)).find(":") >= 0, str(hud._result_detail(GameState)))
	var det: String = str(hud._result_detail(GameState))
	_ok("⑤ ★★4-1 ⇒ 小字先说「最多 %d 场」, 再说用了 5 场、省下的 1 场照发(用户「他是不明白为什么会有未打完的2场的」)" % int(P2.GAUNTLET_QUOTA),
		det.find("最多 %d 场" % int(P2.GAUNTLET_QUOTA)) >= 0 and det.find("用 5 场") >= 0 and det.find("省下的 1 场照发奖励") >= 0
			and det.find("+%d" % int(P2.GAUNTLET_BACKFILL_COINS)) >= 0, det)
	GameState.gauntlet_backfill_paid = 0
	GameState.gauntlet_losses = 2
	_ok("⑤ 对照: 4-2(6 场都打了)⇒ 没有省下的场次那一句", str(hud._result_detail(GameState)).find("省下") < 0, str(hud._result_detail(GameState)))
	GameState.gauntlet_losses = 1
	GameState.gauntlet_wins = 3
	GameState.gauntlet_losses = 1
	_ok("⑤ 对照: 3-1 赢了 ⇒ 大字照旧「胜利」", str(hud._result_headline(true, false, GameState)) == "胜利")
	fb._last_settle_kind = P2.SETTLE_RANKED
	GameState.gauntlet_wins = 4
	_ok("⑤ 对照: 不是闯关赛那一局 ⇒ 4 胜也不写「已晋级！」", str(hud._result_headline(true, false, GameState)) == "胜利")
	fb._last_settle_kind = P2.SETTLE_GAUNTLET
	GameState.gauntlet_wins = 1
	GameState.gauntlet_losses = 1
	GameState.hearts = 3                 # 没出局(出局那一局不发币, 深海币那一格本来就不画)
	var chips = hud._build_reward_chips(GameState)
	var txt := _all_text(chips) if chips != null else ""
	_ok("⑤ ★闯关赛结算多一格「经验 +%d」" % int(P2.GAUNTLET_XP_PER_MATCH), txt.find("经验|+%d" % int(P2.GAUNTLET_XP_PER_MATCH)) >= 0, txt)
	_ok("⑤ 深海币那一格有名字(数出来的动画按名字找)", chips != null and chips.find_child("RewardCoins", true, false) != null)
	if chips != null:
		chips.free()
	## 不加「下一局」(用户 10-26「不要加下一局按钮，玩家会尽量去看商店的」): 源码里结算按钮那段不许出现这个词
	var src: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	var i0: int = src.find("func _settle_buttons(")
	var i1: int = src.find("\nfunc ", i0 + 10)
	_ok("⑤ ★结算屏按钮没有「下一局」(分母: 找到了 _settle_buttons)", i0 >= 0 and src.substr(i0, i1 - i0).find("下一局") < 0)


## ②b 服务器裁判局那条记账路(RefereeWatch.settle): 战绩以服务端为准, 晋级的那一场同样当场发、而且按服务端战绩算
func _t_referee_bonus(c0: int) -> void:
	var wk: int = P2.week_anchor_utc(int(P2.now_utc()))
	for case in [[3, 0, 4, 0, 2], [3, 1, 4, 1, 1], [3, 0, 4, 1, 1], [2, 1, 3, 1, 0]]:
		## [本地胜, 本地负, 服务端胜, 服务端负, 该发几场] —— 第三组: 本地以为 4-0, 服务端说 4-1 ⇒ 只能发 1 场
		GameState.promoted = true
		GameState.week_anchor_ts = wk
		GameState.gauntlet_wins = int(case[0])
		GameState.gauntlet_losses = int(case[1])
		GameState.gauntlet_backfill_paid = 0
		GameState.hearts = 5
		GameState.meta_deepsea_coins = c0
		GameState.referee_pending = {"job_id": 77, "match_id": "", "week": wk, "foe": [], "foe_name": ""}
		var v: Dictionary = RW.settle(GameState, 77, {"won": 1, "gw": int(case[2]), "gl": int(case[3]), "coins": 0})
		var want: int = int(case[4])
		_ok("②b 服务器局 本地 %d-%d → 服务端 %d-%d ⇒ 当场发 %d 场" % [int(case[0]), int(case[1]), int(case[2]), int(case[3]), want],
			not v.is_empty() and int(GameState.gauntlet_backfill_paid) == want
				and int(GameState.meta_deepsea_coins) - c0 == int(P2.GAUNTLET_COINS_PER_MATCH) + want * int(P2.GAUNTLET_BACKFILL_COINS),
			"发了 %d 场 / 钱包 +%d / view=%s" % [int(GameState.gauntlet_backfill_paid), int(GameState.meta_deepsea_coins) - c0, str(v)])
	GameState.referee_pending = {}


# ⑧ ─────────────────────────────────────────────────────────────
func _t_copy_rules() -> void:
	print("── ⑧ 文案规矩 ──")
	var texts: Array = []
	var fri_post: int = P2.ranked_close_ts(MON) + 60
	var sun_post: int = P2.gauntlet_close_ts(MON) + 60
	_fresh(true, 12, 12, 5)
	GameState.backfill_paid = 4
	GameState.gauntlet_wins = 4
	GameState.gauntlet_backfill_paid = 2
	for k in [WCC.KIND_RANKED_IN, WCC.KIND_RANKED_OUT, WCC.KIND_GAUNTLET_IN, WCC.KIND_GAUNTLET_CUT]:
		for ts in [fri_post, sun_post]:
			var d: Dictionary = WCC.spec(str(k), GameState, int(ts))
			texts.append(str(d["title"]))
			texts.append_array(d["body"])
	texts.append(P2.finals_block_msg(true, true))
	texts.append(P2.finals_block_msg(false, true))
	texts.append(P2.finals_block_msg(false, false))
	var bad: Array = []
	for t in texts:
		for w in ["补发", "折算", "·", "您"]:
			if str(t).find(w) >= 0:
				bad.append("「%s」含「%s」" % [t, w])
	_ok("⑧ ★卡与拦截句不含「补发 / 折算 / · / 您」(分母 %d 句)" % texts.size(), bad.is_empty() and texts.size() >= 19, str(bad))


# ③ ─────────────────────────────────────────────────────────────
func _t_real_menu_card() -> void:
	print("── ③ 真入口: 主菜单弹卡 → 领取 → 币飞进钱包 ──")
	var fri_post: int = P2.ranked_close_ts(MON) + 3600
	_fresh(true, 12, 12, 5)
	GameState.season_total_battles = 12
	GameState.season_leaders = ["basic", "stone", "lava"]
	GameState.meta_deepsea_coins = 200
	GameState.settle_ranked_close(fri_post)            # 发 4 场 = 56
	var real: int = int(GameState.meta_deepsea_coins)
	CF.seen = -1                                       # 开机后第一次进主菜单(收盘补算发生在开机时)
	var me := get_tree().current_scene
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	mm.clock_override_ts = fri_post
	get_tree().root.add_child(mm)
	get_tree().current_scene = mm                      # ★卡只在玩家真走到的那一屏弹(current_scene == 主菜单)
	var card: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		card = mm.get_node_or_null(WCC.NODE_NAME)
		if card != null:
			break
	_ok("③ ★分母: 收盘后第一次进主菜单, 卡真弹出来了", card != null)
	var lab: Label = mm._wk().wallet_nodes()[0] as Label
	_ok("③ 分母: 找得到钱包数字", lab != null)
	if card == null or lab == null:
		get_tree().current_scene = me
		mm.queue_free()
		return
	_ok("③ ★卡开着时钱包显示旧值(真余额 − 卡上的钱)", int(lab.text) == real - 56, "钱包=%s 真=%d" % [lab.text, real])
	_ok("③ ★弹出那一刻就记了「本周弹过」(存档字段)", int(GameState.close_card_ranked_wk) == MON)
	var amt := card.find_child("CoinAmount", true, false) as Label
	_ok("③ 卡上奖励行写 +56", amt != null and amt.text == "+56", amt.text if amt != null else "无")
	var prim := card.find_child("Primary", true, false) as Button
	_ok("③ 主按钮是「领取」", prim != null and prim.text == WCC.TXT_CLAIM)
	if prim != null:
		prim.pressed.emit()
	await get_tree().process_frame
	var cf: Node = mm.get_node_or_null(CF.NODE_NAME)
	_ok("③ ★点「领取」⇒ 卡关掉、币开始飞", mm.get_node_or_null(WCC.NODE_NAME) == null or mm.get_node(WCC.NODE_NAME).is_queued_for_deletion(), "")
	_ok("③ ★入账动画在跑(CoinFly 在场)", cf != null)
	var mid_seen := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000 and is_instance_valid(cf) and cf != null and cf.is_inside_tree():
		var v: int = int(lab.text)
		if v > real - 56 and v < real:
			mid_seen = true
		await get_tree().process_frame
	_ok("③ ★数字是一步步走上去的(见过中间值)", mid_seen)
	_ok("③ ★飞完钱包 == 真余额", int(lab.text) == real, "钱包=%s 真=%d" % [lab.text, real])
	_ok("③ 钱一分没多发(动画只管显示)", int(GameState.meta_deepsea_coins) == real)
	get_tree().current_scene = me
	mm.queue_free()
	await get_tree().process_frame
	## 再进一次主菜单: 本周弹过 ⇒ 不再弹
	var mm2 = load("res://scenes/MainMenu.tscn").instantiate()
	mm2.clock_override_ts = fri_post + 60
	get_tree().root.add_child(mm2)
	get_tree().current_scene = mm2
	t0 = Time.get_ticks_msec()
	var again := false
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		if mm2.get_node_or_null(WCC.NODE_NAME) != null:
			again = true
			break
	_ok("③ ★同一周第二次进主菜单不再弹", not again)
	get_tree().current_scene = me
	mm2.queue_free()
	await get_tree().process_frame


# ④ 续 ─────────────────────────────────────────────────────────
func _t_coinfly_play() -> void:
	print("── ④ 入账动画: 播一遍 / 点一下收尾 ──")
	var host := Control.new()
	add_child(host)
	var lab := Label.new()
	host.add_child(lab)
	var ic := Control.new()
	ic.position = Vector2(900, 40)
	ic.size = Vector2(40, 40)
	host.add_child(ic)
	var cf = CF.play(host, Vector2(400, 300), lab, ic, 100, 8)
	_ok("④ 分母: 建出来了, 起点显示旧值 100", cf != null and lab.text == "100")
	var steps: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and is_instance_valid(cf) and not cf.done:
		steps[lab.text] = true
		await get_tree().process_frame
	_ok("④ ★数字一枚一跳(+8 = 8 枚 ⇒ 见过 ≥5 个不同的中间值)", steps.size() >= 5, str(steps.keys()))
	_ok("④ ★播完 == 终值 108", lab.text == "108", lab.text)
	var cf2 = CF.play(host, Vector2(400, 300), lab, ic, 108, 56)
	await get_tree().process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	cf2._input(ev)
	_ok("④ ★点一下 ⇒ 立刻收尾、数字到终值 164", lab.text == "164" and bool(cf2.done), lab.text)
	_ok("④ amount ≤ 0 ⇒ 什么都不建", CF.play(host, Vector2.ZERO, lab, ic, 1, 0) == null)
	host.queue_free()
	await get_tree().process_frame


# ⑥ ─────────────────────────────────────────────────────────────
func _t_block_card() -> void:
	print("── ⑥ 开始战斗被拦 ⇒ 一张卡 ──")
	var sat: int = MON + 5 * DAY + 12 * 3600
	_fresh(false, 16, 9, 1)
	GameState.season_total_battles = 16
	var mm = MENU.new()
	mm.clock_override_ts = sat
	add_child(mm)
	for _i in range(4):
		await get_tree().process_frame
	var msg: String = str(mm._battle_block_msg(sat))
	_ok("⑥ 分母: 周六没晋级 ⇒ 被拦", msg != "", msg)
	if msg == "":
		mm.queue_free()
		return
	mm._start_battle_flow()
	var bc: Node = mm.get_node_or_null(str(mm.BLOCK_CARD_NAME))
	_ok("⑥ ★被拦 ⇒ 弹一张卡(不是飘字)", bc != null)
	var body := bc.find_child("Body0", true, false) as Label if bc != null else null
	_ok("⑥ ★卡上那句 == _battle_block_msg(同一处)", body != null and body.text == msg, body.text if body != null else "无")
	var prim := bc.find_child("Primary", true, false) as Button if bc != null else null
	_ok("⑥ ★周末没资格 ⇒ 主按钮「观战」", prim != null and prim.text == WCC.TXT_WATCH, prim.text if prim != null else "无")
	_ok("⑥ ★模式卡锁着 ⇒ 第三格是去处「观看全场赛况」, 不是收盘倒计时", str(mm.mode_card_lines(sat)[2]) == str(mm.MODE_WATCH_BOARD), str(mm.mode_card_lines(sat)))
	## 对照: 晋级了、4-0 ⇒ 卡上只有「好的」, 模式卡照常倒计时 / 指周日
	GameState.promoted = true
	GameState.gauntlet_wins = 4
	var msg2: String = str(mm._battle_block_msg(sat))
	mm._start_battle_flow()
	var bc2: Node = mm.get_node_or_null(str(mm.BLOCK_CARD_NAME))
	var p2 := bc2.find_child("Primary", true, false) as Button if bc2 != null else null
	_ok("⑥ 对照: 已晋级决赛日 ⇒ 卡上只有「好的」(新卡顶掉旧卡、名字不变)", p2 != null and p2.text == WCC.TXT_OK
		and bc2.find_child("Secondary", true, false) == null, p2.text if p2 != null else "无")
	_ok("⑥ 对照: 晋级那句说周日几点开打(设备时区)", msg2.find(P2.local_wd_hhmm(P2.finals_seat_ts(MON))) >= 0, msg2)
	_ok("⑥ 对照: 模式卡没锁 ⇒ 第三格不是观战去处", str(mm.mode_card_lines(sat)[2]) != str(mm.MODE_WATCH_BOARD), str(mm.mode_card_lines(sat)))
	mm.queue_free()
	await get_tree().process_frame


# ⑦ ─────────────────────────────────────────────────────────────
func _t_mode_rule_fits() -> void:
	print("── ⑦ 模式卡第二行放得下 ──")
	var mm = MENU.new()
	var f: Font = mm._bold_font()
	var rule_w: float = float(mm.MODE_SIZE.x) - 36.0
	var sat: int = MON + 5 * DAY + 12 * 3600
	var worst := 0.0
	var worst_t := ""
	var n := 0
	_fresh(true, 12, 12, 5)
	GameState.backfill_paid = 4          # ★原来就是这一笔让那一行折行被裁(方案书 §2 A)
	for w in range(0, 5):
		for l in range(0, 4):
			if w + l > int(P2.GAUNTLET_QUOTA):
				continue
			GameState.gauntlet_wins = w
			GameState.gauntlet_losses = l
			var t: String = mm._strip_phase_head(str(mm._gauntlet_status_line(sat)), str(P2.PHASE_LABEL[P2.PHASE_GAUNTLET]))
			var ink: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(mm.MODE_RULE_FONT) + 1).x
			n += 1
			if ink > worst:
				worst = ink
				worst_t = t
	_ok("⑦ ★闯关赛所有战绩 + 有补发时, 模式卡第二行都是一行(最宽 %.0f ≤ %.0f, 分母 %d 种)" % [worst, rule_w, n],
		n >= 15 and worst <= rule_w, worst_t)
	mm.free()


func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += str((n as Label).text) + "|"
	for c in n.get_children():
		s += _all_text(c)
	return s
