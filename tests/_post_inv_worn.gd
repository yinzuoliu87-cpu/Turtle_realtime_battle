extends Node
## 截图用: 点单位卡上已装的那一件(说明小卡弹在那张卡旁边, 卡底「卸下 / 详情」)。
##   SHOT_WORN=lane,idx,cell   默认 top,0,0


static func run(scene: Node) -> void:
	var spec := OS.get_environment("SHOT_WORN") if OS.has_environment("SHOT_WORN") else "top,0,0"
	var p := spec.split(",")
	scene.call("_on_worn_click", p[0], int(p[1]), int(p[2]))
