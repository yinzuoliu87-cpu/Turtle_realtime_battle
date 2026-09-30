extends Node
## 探针: 打满配额的存档, 开机时「满配额」称号会不会发出来。
func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[探针] 拿不到 GameState"); get_tree().quit(1); return
	var P2 = load("res://scripts/gamedata/phase2_config.gd")
	print("[探针] ranked_used=%d  RANKED_QUOTA=%d  week_anchor_ts=%d"
		% [int(gs.ranked_used), int(P2.RANKED_QUOTA), int(gs.week_anchor_ts)])
	print("[探针] 开机后 titles = %s" % str(gs.titles))
	## 手动再调一次 sync_titles —— 如果这一下就发出来了, 说明条件本来就满足,
	## 缺的只是"打满那一刻之后再有人调一次"。
	var got: int = gs.sync_titles()
	print("[探针] 手动 sync_titles() 新发 %d 条 ⇒ titles = %s" % [got, str(gs.titles)])
	get_tree().quit(0)
