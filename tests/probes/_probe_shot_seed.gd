extends Node
## 截图用的一次性种子 (2026-09-29 台账 ④ 的两张实拍)。SHOT_CASE 选场景:
##
##   SHOT_CASE=quota   主菜单: 本周配额打满 ⇒ 「开始战斗」与「商店」**都该画着锁**
##   SHOT_CASE=acct    设置页: 把后端配上 ⇒ 账号那四行真的建出来(门禁环境下它本来不在场)
##
## ★强制 test_mode —— 演示数据绝不许写进真存档(`_shot_scene` 不是 headless,
##   而 `GameState.test_mode` 只在无头下自动置位)。


static func run() -> void:
	GameState.test_mode = true
	var case_id := OS.get_environment("SHOT_CASE")
	GameState.season_id = 2
	GameState.season_level = 4
	GameState.coins = 1240
	GameState.meta_deepsea_coins = 380
	GameState.season_total_battles = 24
	GameState.battles_won = 16
	GameState.battles_total = 24
	if case_id == "quota":
		## 打满本周配额、命还剩着 —— 台账 ④ 那一条就是这个状态:
		## 商店正确上锁, 而「开始战斗」原来还是亮的。
		GameState.hearts = 5
		GameState.ranked_used = int(preload("res://scripts/gamedata/phase2_config.gd").RANKED_QUOTA)
	elif case_id == "acct":
		## 设置页要有账号行, 就得让 `supabase.enabled()` 为真(URL + key 都要).
		OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
		ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forshot")
		GameState.account_id = "ae08e589-1111-2222-3333-444455556666"
		GameState.account_email = ""
