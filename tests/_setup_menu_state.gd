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
