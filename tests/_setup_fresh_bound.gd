extends Node
## 实拍用: 一个**刚绑完邮箱的全新玩家** —— 除了账号什么都没有。
static func run() -> void:
	GameState.test_mode = true
	GameState.account_email = "tester01@example.com"
	GameState.account_id = "uid-new"
	GameState.nickname = "新来的"
	GameState.onboarded = true          ## 已过教程确认, 看的是常规主菜单
	GameState.season_total_battles = 0
	GameState.season_wins = 0
	GameState.ranked_used = 0
	GameState.hearts = 8
	GameState.meta_deepsea_coins = 0
