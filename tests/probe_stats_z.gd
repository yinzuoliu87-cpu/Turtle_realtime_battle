extends Node
## 探针: 统计面板在 _ui_layer 里的绘制层级, 换路前后对比。
## 同一 CanvasLayer 内【树序 = 绘制层级】, 后加的画在上面。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _idx(layer: CanvasLayer, n: Node) -> int:
	for i in range(layer.get_child_count()):
		if layer.get_child(i) == n:
			return i
	return -1

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false); s.set_physics_process(false)
	print("=== 探针: 统计面板绘制层级 ===")
	s._on_dmg_stats_toggle()            # 首次点开 → 建面板并加进 _ui_layer
	await get_tree().process_frame
	var panel = s._dmg_stats.panel
	print("  _ui_layer 子节点数 = %d" % s._ui_layer.get_child_count())
	print("  [开局] 统计面板 index = %d" % _idx(s._ui_layer, panel))
	print("  [开局] 左队头像栏 index = %d" % _idx(s._ui_layer, s._team_panel_left))
	print("  [开局] 面板在头像栏之上? %s" % str(_idx(s._ui_layer, panel) > _idx(s._ui_layer, s._team_panel_left)))
	# 模拟换路: _spawn_dual_lane 每路都会调 _build_team_panels(battle_spawn.gd:180)
	s._hud._build_team_panels()
	await get_tree().process_frame
	print("  --- 模拟换路(重建左右队头像栏) ---")
	print("  _ui_layer 子节点数 = %d" % s._ui_layer.get_child_count())
	print("  [换路后] 统计面板 index = %d" % _idx(s._ui_layer, panel))
	print("  [换路后] 左队头像栏 index = %d" % _idx(s._ui_layer, s._team_panel_left))
	var covered: bool = _idx(s._ui_layer, panel) < _idx(s._ui_layer, s._team_panel_left)
	print("  ★[换路后·自刷前] 面板被头像栏盖住? %s" % str(covered))
	s._dmg_stats.render()               # 模拟 0.4s 自刷 → 应自愈回最前
	await get_tree().process_frame
	print("  [自刷后] 统计面板 index = %d" % _idx(s._ui_layer, panel))
	print("  [自刷后] 左队头像栏 index = %d" % _idx(s._ui_layer, s._team_panel_left))
	print("  ★[自刷后] 仍被盖住? %s" % str(_idx(s._ui_layer, panel) < _idx(s._ui_layer, s._team_panel_left)))
	# 几何: 两者是否真的重叠(不重叠就算层级低也看不出来)
	print("  面板矩形 %s / 左队栏矩形 %s" % [str(panel.get_rect()), str((s._team_panel_left as Control).get_rect())])
	print("  ★几何重叠? %s" % str(panel.get_rect().intersects((s._team_panel_left as Control).get_rect())))
	get_tree().quit(0)
