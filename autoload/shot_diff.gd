extends Node

const Backend = preload("res://scripts/engine/backend.gd")

## 比对截图工具 (dev only). 设环境变量 SHOTDIFF=1 (或 SHOTDIFF=<秒数>) 启动:
##   等 N 秒(默认2.8, 让场景建好+入场动画结束) → 截当前场景视口存 res://_shot.png → quit.
## 用法: SHOTDIFF=1 Godot --path . --resolution 1280x720 res://scenes/X.tscn
## 不设环境变量时完全无副作用 (直接 return), 可安全留在项目里.
func _ready() -> void:
	if not OS.has_environment("SHOTDIFF"):
		return
	# 可选: 截战斗前预置 GameState (autoload 早于主场景 _ready → 主场景能读到)
	if OS.has_environment("SHOT_SETUP"):
		var setup: String = OS.get_environment("SHOT_SETUP")
		var lt: Array[String] = ["basic", "stone", "bamboo"]
		if setup == "test":
			GameState.mode = "test"
			GameState.left_team = lt
			GameState.dungeon_stage = 1
		elif setup == "chain":
			# 闯关链场景(Dungeon/BossPick/RewardPick/ChoiceEvent/BattleEnd)统一预置 dungeon run 态
			GameState.mode = "dungeon"
			GameState.dungeon_stage = 2
			GameState.left_team = lt
			GameState.right_team = ["lava", "star", "shock"]   # 预置敌队 → 满足 has_team() 不回菜单
			GameState.dungeon_bonuses = []
			GameState.dungeon_carry_hp = {}
			GameState.dungeon_dead_ids = []
			GameState.coins = 50
			GameState.last_battle_result = {
				"result": "win", "player_won": true, "tie": false, "turn": 8, "mode": "dungeon",
				"dungeon_stage": 2, "is_boss": false, "left_alive": 2, "right_alive": 0,
				"total_dmg": 700, "rule": "",
				"player_stats": [
					{"id": "basic", "name": "小龟", "side": "left", "dmgDealt": 340, "dmgTaken": 120, "healing": 0, "kills": 2, "alive": true},
					{"id": "stone", "name": "石头龟", "side": "left", "dmgDealt": 210, "dmgTaken": 200, "healing": 0, "kills": 1, "alive": true},
					{"id": "bamboo", "name": "竹叶龟", "side": "left", "dmgDealt": 150, "dmgTaken": 80, "healing": 50, "kills": 0, "alive": false},
				],
			}
		elif setup == "inv":
			# V2 背包/出战配置 截图: 预置锁定阵容 + 装备 + 背包样例
			GameState.season_leaders = ["basic", "stone", "bamboo"]
			GameState.season_total_battles = 6
			GameState.season_level = 5; GameState.season_xp = 8   # → 装备槽 equip_slots_for_level(5)=3
			GameState.meta_deepsea_coins = 240
			var _eids: Array = []
			for _e in DataRegistry.phase2_equipment:
				if int((_e as Dictionary).get("shopAvailable", 0)) == 1:
					_eids.append(str((_e as Dictionary)["id"]))
			if _eids.size() >= 5:
				GameState.persistent_equipped = {"basic": [{"id": _eids[0], "star": 2}], "stone": [{"id": _eids[1], "star": 1}]}
				GameState.persistent_bench = [{"id": _eids[2], "star": 1}, {"id": _eids[2], "star": 1}, {"id": _eids[3], "star": 3}, {"id": _eids[4], "star": 1}]
		elif setup == "lb":
			# V2 排行榜截图: 种 5 个样例 ghost 进池 (写盘; 用户 ghost 池本由对局生成, 此为 dev 截图)
			GameState.season_eggs_killed = 12
			var _rng2 := RandomNumberGenerator.new(); _rng2.seed = 7
			var _pool := {"brackets": {}}
			var _names := ["深海霸主", "龟界传说", "咸鱼翻身", "退役龟皇", "萌新龟龟"]
			for _i in range(5):
				var _b := Backend.make_bot(2, _rng2)
				_b["profile"]["name"] = _names[_i]
				_b["season_eggs_killed"] = 22 - _i * 4
				Backend.pool_add(_pool, _b)
			Backend.save_pool(_pool)
	var s: String = OS.get_environment("SHOTDIFF")
	var delay: float = 2.8
	if s.is_valid_float() and s.to_float() > 0.5:
		delay = s.to_float()
	await get_tree().create_timer(delay).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var out: String = "res://_shot.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")   # 并行 agent 各用唯一文件名防互相覆盖
	img.save_png(out)
	get_tree().quit()
