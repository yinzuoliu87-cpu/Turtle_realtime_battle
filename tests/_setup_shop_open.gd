extends Node
## 截图用的一次性种子: 把商店【开店】。
## 商店上锁条件是 `season_total_battles < 1`(大轮开局未打第一场) —— 不种这个,
## 截出来永远是"🔒 商店未开", 而我曾把那张空图当成"截图工具坏了"查了半天。
##
## ★强制 test_mode —— 演示数据绝不许写进真存档(2026-08-12: INV_DEMO 曾把演示装备写进玩家存档)。


static func run() -> void:
	GameState.test_mode = true
	GameState.season_total_battles = 1
	GameState.meta_shop_battles = -1        # ≠ season_total_battles ⇒ 强制重新 _roll 一套货
	GameState.meta_shop_offer = []
	GameState.meta_deepsea_coins = 9999
