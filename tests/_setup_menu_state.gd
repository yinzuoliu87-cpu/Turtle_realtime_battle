extends Node
## 截图用的一次性种子: 让主菜单显出【有进度的真实态】。
## 不种就是全 0 空态(战绩"暂无战绩"、商店灰锁), 我会把"没配对环境"报成"这块没做"。
##
## ★强制 test_mode —— 演示数据绝不许写进真存档。


static func run() -> void:
	GameState.test_mode = true
	GameState.season_total_battles = 3
	GameState.season_id = 2
	GameState.season_level = 4
	GameState.hearts = 5
	GameState.coins = 1240
	GameState.meta_deepsea_coins = 380
	GameState.battles_won = 7
	GameState.battles_total = 11
	## ★★战绩页的列表读的是 `match_history`, **不是** 上面这两个聚合计数。
	##   只种计数不种记录 ⇒ 实拍出来是「总场次 11 / 胜 7 / 负 4」配上
	##   「最近对局 (0) · 还没有对局记录, 去打一场吧！」—— **同一屏自相矛盾**,
	##   2026-09-19 实拍巡检时我差点把这个「没配对的环境」报成产品 bug。
	GameState.match_history = [
		{"result": "win",  "lineup": ["basic", "stone", "bamboo"], "mode": "single", "turn": 14},
		{"result": "lose", "lineup": ["angel", "ice", "ninja"],    "mode": "single", "turn": 11},
		{"result": "win",  "lineup": ["basic", "ice", "ninja"],    "mode": "dungeon", "turn": 18},
		{"result": "win",  "lineup": ["stone", "bamboo", "angel"], "mode": "single", "turn": 9},
		{"result": "lose", "lineup": ["basic", "angel", "ice"],    "mode": "custom", "turn": 7},
	]
