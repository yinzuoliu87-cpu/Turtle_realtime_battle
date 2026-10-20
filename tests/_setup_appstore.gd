extends Node
## App Store 截图用的一次性种子(2026-10-20): 一个【打了一周的真实玩家】的样子, 六屏共用同一份。
## 方案书 docs/plans/20261020-AppStore上架.md 附录 C。
##
## ★为什么不直接用 _setup_inv_demo / _setup_shop_open: 那几份各种各的 ——
##   背包是 candy+小龟+石头龟、商店 9999 币 + 1 级 + 没统领(「装备 0/0」「背包·空」)、
##   战斗场一个统领都没种(左侧两张统领卡没名字没头像, 顶栏名字是兜底的「路人甲」)。
##   六张图拼在商店页上就是六个不同的号。⇒ 一份种子, 六屏同一个人。
## ★强制 test_mode —— 只改内存, 绝不写进真存档。
const Backend := preload("res://scripts/net/backend.gd")

const NICK := "芝士奶盖"
## 三统领: 新变脸龟 + 两只特效好看的。上路 two_head/phoenix, 下路 lightning(default_dual_lineup 的 slot 0/1 上 · 2 下)。
const LEADERS := ["two_head", "phoenix", "lightning"]


static func run() -> void:
	GameState.test_mode = true
	GameState.nickname = NICK
	GameState.account_id = "5e1c9a7b-3f20-4d8e-9a61-2b7c4f0d8e13"
	GameState.season_id = 3
	GameState.season_level = 6
	GameState.season_total_battles = 7
	GameState.hearts = 5
	GameState.coins = 1240
	GameState.meta_deepsea_coins = 428
	GameState.battles_won = 5
	GameState.battles_total = 7
	GameState.candy_jar_count = 0
	GameState.season_leaders = LEADERS.duplicate()
	GameState.dual_lineup = {}
	var lineup: Dictionary = GameState.get_dual_lineup()

	GameState.persistent_equipped = {
		## 只凑三条羁绊(剑 3 / 法器 3 / 盾 3): 四条以上时背包羁绊列第 4 行被滚动框切一半、商店顶部羁绊条伸进货架。
		"two_head": [{"id": "p2eq_005", "star": 2}, {"id": "p2eq_009", "star": 2}, {"id": "p2eq_007", "star": 1}],
		"phoenix": [{"id": "p2eq_023", "star": 2}, {"id": "p2eq_011", "star": 1}],
		"lightning": [{"id": "p2eq_026", "star": 2}, {"id": "p2eq_021", "star": 1}],
	}
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = [{"id": "p2eq_016", "star": 1}]
				break
	GameState.dual_lineup = lineup

	var ids := ["p2eq_001", "p2eq_009", "p2eq_014", "p2eq_017", "p2eq_028",
		"p2eq_032", "p2eq_035", "p2eq_039", "p2eq_044", "p2eq_048", "p2eq_050", "p2eq_084",
		"p2eq_003", "p2eq_010", "p2eq_012", "p2eq_018", "p2eq_019", "p2eq_025", "p2eq_043", "p2eq_036", "p2eq_049", "p2eq_052"]   # 22 件 = 背包两整行, 不留半行空格
	GameState.persistent_bench = []
	for i in range(ids.size()):
		GameState.persistent_bench.append({"id": ids[i], "star": (i % 3) + 1})

	GameState.match_history = [
		{"result": "win", "lineup": LEADERS.duplicate(), "mode": "single", "turn": 14},
		{"result": "win", "lineup": LEADERS.duplicate(), "mode": "single", "turn": 11},
		{"result": "lose", "lineup": LEADERS.duplicate(), "mode": "single", "turn": 18},
		{"result": "win", "lineup": LEADERS.duplicate(), "mode": "single", "turn": 9},
	]

	## 商店: 开店 + 重新出一套货。
	GameState.meta_shop_battles = -1
	GameState.meta_shop_offer = []

	## 战斗对手: 与真人同一个生成器出的机器人快照(名字/号/装备都是产品自己的), 只把阵容钉成好看的三只。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var bot: Dictionary = Backend.make_bot(7, rng)
	bot["leaders"] = ["lava", "ninja", "crystal"]
	bot["lane_assign"] = {"top": ["lava", "ninja"], "bottom": ["crystal"]}
	var eq: Dictionary = {}
	var old_eq: Dictionary = bot.get("equipped", {})
	var olds: Array = old_eq.values()
	var k := 0
	for pid in ["lava", "ninja", "crystal"]:
		eq[pid] = olds[k] if k < olds.size() else []
		k += 1
	bot["equipped"] = eq
	bot["pet_levels"] = {"lava": 1, "ninja": 1, "crystal": 1}
	bot["loadouts"] = {}
	(bot["profile"] as Dictionary)["avatar"] = "lava"
	GameState.dual_ghost = bot
	print("[APPSTORE] me=%s foe=%s" % [NICK, str((bot["profile"] as Dictionary).get("name", ""))])
