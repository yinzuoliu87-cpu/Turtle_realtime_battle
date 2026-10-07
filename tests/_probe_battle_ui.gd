extends Node
## 走玩家真路径: 主菜单 → _start_battle_flow()(与点「开始战斗」同一个函数) → 匹配 → 双路对局; 进场后点开我方统领信息面板。
func _ready() -> void:
	await get_tree().process_frame
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy          # 让换场景只释放 dummy, 本节点活着继续驱动
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await get_tree().create_timer(3.0).timeout
	var m = get_tree().current_scene
	print("[PROBE] block=", m._battle_block_msg())
	m._start_battle_flow()
	await get_tree().create_timer(14.0).timeout
	var s = get_tree().current_scene
	print("[PROBE] scene=", s.name, " theme=", load("res://scripts/gamedata/arena_theme.gd").active)
	if s != null and s.get("_units") != null:
		for u in s._units:
			if str(u.get("side", "")) == "left" and str(u.get("kind", "")) == "leader":
				s._hud._show_unit_info_panel(u)
				break
