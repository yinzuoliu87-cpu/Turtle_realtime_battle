class_name DaggerEqVfx
extends RefCounted
## 匕首批演出层(2026-11-25)。只画, 不判定; 无头 / 没有世界节点时什么都不做。专属特效逐件补在这里。
var battle
var _fx: Array = []


func _init(b) -> void:
	battle = b


func _ok() -> bool:
	return battle != null and battle.get("_world") != null and is_instance_valid(battle._world)


func tick(_delta: float) -> void:
	pass


func clear() -> void:
	for f in _fx:
		if is_instance_valid(f.get("node", null)):
			f["node"].queue_free()
	_fx.clear()
