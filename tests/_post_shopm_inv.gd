extends Node
## 截图用(2026-10-21 手机版): 背包页选中一件 —— SHOT_INV=bench(默认, 选背包第 0 件 → 底部操作条)
##   / unit(选上战场第 0 只 → 底部「卸下」条) / help(「?」阵容说明)。


static func run(scene: Node) -> void:
	match OS.get_environment("SHOT_INV"):
		"unit":
			scene.call("_dl_click", "top", 0)
		"help":
			scene.call("_show_lineup_help")
		_:
			scene.call("_on_bench_click", 0)
