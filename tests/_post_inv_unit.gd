extends Node
## 截图用: 点一张龟卡(属性小卡弹在右边背包那一栏)。
##   SHOT_UNIT=lane,idx   默认 top,0


static func run(scene: Node) -> void:
	var spec := OS.get_environment("SHOT_UNIT") if OS.has_environment("SHOT_UNIT") else "top,0"
	var p := spec.split(",")
	scene.call("_dl_click", p[0], int(p[1]))
