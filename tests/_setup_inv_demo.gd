extends Node
## 截图用的一次性种子: 把【背包页】填成有数据的样子。
## 场景自带的 INV_DEMO 走的是 `_inject_demo_inventory()`, 但那条路要靠环境变量,
## 而 `_shot_scene.gd` 的 SHOT_SETUP 钩子更好控(能顺带种统领/糖果罐/深海币)。
##
## ★强制 test_mode —— 演示数据绝不许写进真存档
##   (2026-08-12: INV_DEMO 曾把演示装备写进玩家存档, 之后一串门禁跟着红)。
## ★不 save(), 只改内存。


static func run() -> void:
	GameState.test_mode = true
	GameState.season_level = 6
	GameState.season_total_battles = 7
	GameState.meta_deepsea_coins = 428
	GameState.candy_jar_count = 11
	GameState.candy_jar_broken = false

	# 三只真统领 —— 否则阵容区全是"?"占位, 装备格一个都看不到。
	# ★必须含 candy(糖果龟): `has_candy_jar()` 要求统领里有它, 否则背包里那张糖果罐卡不出现,
	#   而糖果罐正是背包里唯一一张"不是装备"的卡, 截不到就白截。
	var picks: Array = ["candy"]
	for pdef in DataRegistry.launch_pets:
		var pid := str((pdef as Dictionary).get("id", ""))
		if picks.size() < 3 and pid != "candy":
			picks.append(pid)
	GameState.season_leaders = picks.duplicate()
	GameState.dual_lineup = {}
	var lineup: Dictionary = GameState.get_dual_lineup()

	# 背包: 覆盖不同费用 / 不同星级 / 名字长短不一 / 含文案最长那件
	var ids := ["p2eq_001", "p2eq_004", "p2eq_005", "p2eq_007", "p2eq_009",
		"p2eq_011", "p2eq_013", "p2eq_014", "p2eq_016", "p2eq_017",
		"p2eq_021", "p2eq_022", "p2eq_028", "p2eq_032", "p2eq_035",
		"p2eq_039", "p2eq_044", "p2eq_048", "p2eq_050", "p2eq_084"]
	GameState.persistent_bench = []
	for i in range(ids.size()):
		GameState.persistent_bench.append({"id": ids[i], "star": (i % 3) + 1})
	# 临时等级器(糖果罐战利品) —— 背包里第二种"不是装备"的东西, 也要看得到
	GameState.persistent_bench.append({"kind": "item", "id": "temp_level"})

	# 给统领装上装备(占满一只, 另一只装一件 → 能同时看到"满格"和"还有空格")
	GameState.persistent_equipped = {}
	if picks.size() > 0:
		GameState.persistent_equipped[str(picks[0])] = [
			{"id": "p2eq_001", "star": 2}, {"id": "p2eq_005", "star": 1},
			{"id": "p2eq_007", "star": 3}]
	if picks.size() > 1:
		GameState.persistent_equipped[str(picks[1])] = [{"id": "p2eq_011", "star": 1}]
	# 小将也挂两件
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = [{"id": "p2eq_004", "star": 1}, {"id": "p2eq_009", "star": 2}]
				break
	GameState.dual_lineup = lineup
