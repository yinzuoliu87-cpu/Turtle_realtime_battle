extends Node
## 截图用的一次性种子: 给当前阵容的第一只龟塞几件装备, 好看到羁绊 chips 的**有数据**形态。
## ★强制 test_mode —— 演示数据绝不许写进真存档(2026-08-12 的教训: INV_DEMO 曾把演示装备
##   写进玩家存档, 导致两个门禁红了半天)。


static func run() -> void:
	GameState.test_mode = true
	var ids: Array = GameState.lineup_leader_ids()
	if ids.is_empty():
		return
	var pid := str(ids[0])
	# 枪 4 件(首档 3 ⇒ 已激活一档, 距二档差 2) + 盾 2 件(首档 3 ⇒ 差 1) + 法器 1 件
	var demo := ["p2eq_048", "p2eq_049", "p2eq_050", "p2eq_051",
		"p2eq_077", "p2eq_079", "p2eq_089"]
	var arr: Array = []
	for iid in demo:
		arr.append({"id": str(iid), "star": 1})
	GameState.persistent_equipped[pid] = arr
