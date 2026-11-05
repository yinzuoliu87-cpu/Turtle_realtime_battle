extends Node
## 起实走探针: 把 runner 挂到 root 上(本场景会被切走)
func _ready() -> void:
	var r: Node = (load("res://tests/probes/_walk_pages_runner.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(r)
