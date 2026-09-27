extends Node
## 实拍用的一次性种子: 把【战绩页】填成有数据的样子。
##
## ★为什么要它: 不喂的话 `RecordScene` 画的是「还没有对局记录, 去打一场」那一屏 ——
##   2026-09-27 我改完对局行/头像去截图, 截到的就是那块空屏, **什么都验不到**。
##   (同族: 门禁 `verify_ui_consistency` 也要自己钉一份合成记录, 见它 Record 那段注释。)
## ★只改内存, 不 save()(`test_mode = true` 保证不写真存档)。
static func run() -> void:
	GameState.test_mode = true
	GameState.season_total_battles = 6
	var hist: Array = []
	for i in range(6):
		hist.append({
			"result": "win" if i % 2 == 0 else "lose",
			"lineup": ["basic", "fire", "shell"],
			"mode": "实时",
			"turn": 28 + i * 3,
		})
	GameState.match_history = hist
