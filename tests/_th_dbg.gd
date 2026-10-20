extends Node
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready() -> void:
	OS.set_environment("REVIEW", "1"); OS.set_environment("REVIEW_TURTLE", "two_head"); OS.set_environment("REVIEW_SKILL", "1")
	var s = RB.new(); add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	for n in range(820):
		await get_tree().process_frame
		if n < 690 or n % 4 != 0: continue
		for u in s._units:
			if str(u.get("id","")) == "two_head":
				var sp = u["sprite"]
				print("%d t=%.3f pos=%s slam=%s voff=%s sprpos=%s st=%s" % [n, s._t, str(u["pos"]), str(u.get("_slam",false)), str(u.get("_slam_voff", Vector3.ZERO)), str(sp.position), str(u.get("state",""))])
	get_tree().quit()
