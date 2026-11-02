extends Node
func _ready() -> void:
	await get_tree().process_frame
	var p: Dictionary = DataRegistry.all_pets[0]
	for t in ["伤害 {NOSUCHVAR:zzz} 点", "伤害 {N:0.5*ATK} 点", "伤害 {crit*100}% ", "伤害 {N:BADVAR*2} 点"]:
		print("  「%s」 → 「%s」" % [t, SkillText.render_plain(t, p, {})])
	print("PROBE DONE")
	get_tree().quit(0)
