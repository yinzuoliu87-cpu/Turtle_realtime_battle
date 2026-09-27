extends Node
## 探针: **命数 × 闯关赛资格 × 七天** 全矩阵 —— 有没有不该放行的格子?
## ★周日那条无限刷(v0.19.458)就是「某一格没人管」。换一根轴再扫一遍。
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const SUN0 := 1789862400
const DAY := ["日", "一", "二", "三", "四", "五", "六"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.account_email = "t@x.co"
	await get_tree().process_frame
	var mm = MM.new()
	add_child(mm)
	for _i in range(8):
		await get_tree().process_frame
	print("=== 命数 × 资格 × 七天: 【O】=可打  【.】=挡住 ===")
	print("     %-22s %s" % ["", "日 一 二 三 四 五 六"])
	var open_cells: Array = []
	for hearts in [3, 1, 0]:
		for prom in [false, true]:
			for gw in [0, 4]:
				gs.hearts = hearts
				gs.promoted = prom
				gs.gauntlet_wins = gw
				gs.gauntlet_losses = 0
				gs.ranked_used = 0
				gs.season_total_battles = 5
				var row := ""
				for d in range(7):
					mm.clock_override_ts = SUN0 + d * 86400 + 12 * 3600
					var m: String = str(mm._battle_block_msg(mm._now_ts()))
					row += ("O  " if m == "" else ".  ")
					if m == "":
						open_cells.append("%d命/%s/闯%d胜/周%s" % [hearts, ("有资格" if prom else "无资格"), gw, DAY[d]])
				print("  %d 命 %-6s 闯关 %d 胜   %s" % [hearts, ("有资格" if prom else "无资格"), gw, row])
	print("")
	print("  可打的格子共 %d 个:" % open_cells.size())
	for c in open_cells:
		print("     " + str(c))
	get_tree().quit(0)
