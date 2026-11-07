extends Node
## 探针: 换路时在途的训龟大师钩子还在不在, 新一路开局会不会同时有两根(用户 11-07「钩索明明有 CD 的，怎么突然放出两个」)
## 只打印数字, 不判定。跑法: --headless res://tests/probes/_probe_hook_lane.tscn

func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	for _i in range(5):
		await get_tree().process_frame
	var ts = scn._trainer_sys
	var left = null
	for u in scn._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			left = u
	if left == null:
		scn._spawn._spawn_trainers()
		for u in scn._units:
			if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
				left = u
	print("[HOOK] 大师 ", left != null, " 单位数 ", scn._units.size())
	left["_active_cd"] = 0.0
	var ok: bool = ts._cast_hook(left, Vector2.RIGHT)
	print("[HOOK] 放钩 ok=%s 在途=%d 冷却=%.1f" % [str(ok), ts._flights.size(), float(left["_active_cd"])])
	var old_src: Dictionary = (ts._flights[0] as Dictionary)["src"]
	scn._dl_sys._dl_next_lane("top")
	for _i in range(3):
		await get_tree().process_frame
	var left2 = null
	for u in scn._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			left2 = u
	print("[HOOK] 换路后 在途=%d 旧钩的 src 还 alive=%s 是同一个大师=%s" % [ts._flights.size(), str(old_src.get("alive", "无键")), str(is_same(old_src, left2))])
	if left2 != null:
		print("[HOOK] 新大师 冷却=%.1f 主动=%s" % [float(left2.get("_active_cd", 0.0)), str(left2.get("_tr_active", ""))])
		var ok2: bool = ts._cast_hook(left2, Vector2.RIGHT)
		print("[HOOK] 新大师放钩 ok=%s 在途=%d(>1 = 同时两根)" % [str(ok2), ts._flights.size()])
	get_tree().quit(0)
