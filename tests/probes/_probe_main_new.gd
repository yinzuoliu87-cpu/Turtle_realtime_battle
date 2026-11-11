extends Node
## 诊断探针(11-11): 进程一开始就 load(主场景脚本).new(), 看 SpiritEqVfx / AxeSystem 是否实例化失败(verify_tutorial 报的那条)
func _ready() -> void:
	await get_tree().process_frame
	for p in ["res://scripts/scenes/battle/spirit_eq_vfx.gd", "res://scripts/systems/equip/axe_system.gd", "res://scripts/systems/equip/eq_spirit_batch.gd"]:
		var g: GDScript = load(p)
		print("[PROBE] %s can_instantiate=%s" % [p.get_file(), str(g.can_instantiate())])
	var s = load("res://scripts/scenes/RealtimeBattle3DScene.gd").new()
	print("[PROBE] main new ok=%s" % str(s != null))
	add_child(s)
	for _i in range(3):
		await get_tree().process_frame
	get_tree().quit()
