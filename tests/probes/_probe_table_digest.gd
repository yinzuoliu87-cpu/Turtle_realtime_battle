extends Node
## 探针: verify_rules_fingerprint 的数值表静态摘要逐个常量打 md5(查哪个常量跨进程不稳定)。
const PATHS := ["res://scripts/gamedata/equip_stats.gd", "res://scripts/gamedata/turtle_stats.gd",
	"res://scripts/gamedata/phase2_minion.gd"]

func _ready() -> void:
	var T = load("res://tests/verify_rules_fingerprint.gd").new()
	for path in PATHS:
		var cm: Dictionary = (load(path) as Script).get_script_constant_map()
		var ks: Array = cm.keys()
		ks.sort()
		for k in ks:
			var v = cm[k]
			if v is int or v is float or v is Dictionary or v is Array:
				var s: String = T._canon(v)
				print("TBL ", str(path).get_file(), "::", k, " ", s.md5_text(), " len=", s.length(), " head=", s.left(120))
	T.free()
	get_tree().quit(0)
