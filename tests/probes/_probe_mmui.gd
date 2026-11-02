extends Node
## _probe_mmui.gd — 探针(不是门禁): 撮合屏在缝注入之后**到底撑不撑得到被量**。
##
## 只回答四个问题, 全部打真数字:
##   ① 缝注入后, 这一屏在第几秒建出「对手卡」(VS 态), 可见控件多少个
##   ② `_may_leave_for_test` 回调在第几秒被调, 传进来的目标是什么
##   ③ 回调返回 false 之后, 实例还在树里吗 / current_scene 还是我吗
##   ④ 12px 圆角 + 2px 描边的假违规塞进去, 判据数得出来吗(这里只数 stylebox, 不搬整套 _audit)
const MM := preload("res://scripts/scenes/MatchmakingScene.gd")

var _leave_at: float = -1.0
var _leave_path: String = ""
var _leave_calls: int = 0
var _t0: float = 0.0


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0 - _t0


func _may_leave(path: String) -> bool:
	_leave_calls += 1
	_leave_at = _now()
	_leave_path = path
	return false


## 只数 web/round 两条(与 verify_ui_consistency 的同一个 if 同口径), 探针够用。
func _count(root: Node) -> Dictionary:
	var d := {"ctrl": 0, "web": 0, "round": 0}
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			d["ctrl"] = int(d["ctrl"]) + 1
			for slot in ["panel", "normal", "background", "fill"]:
				if not c.has_theme_stylebox_override(slot):
					continue
				var sb = c.get_theme_stylebox(slot)
				if sb is StyleBoxFlat:
					var f := sb as StyleBoxFlat
					if f.corner_radius_top_left > 0:
						d["round"] = int(d["round"]) + 1
					if f.border_width_top > 0 and f.border_width_bottom > 0 \
							and f.border_width_left > 0 and f.border_width_right > 0 \
							and f.bg_color.a < 0.95:
						d["web"] = int(d["web"]) + 1
		for ch in n.get_children():
			st.append(ch)
	return d


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	var me_scene: Node = get_tree().current_scene
	print("=== _probe_mmui ===")
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	MM._may_leave_for_test = _may_leave
	var inst = (load("res://scenes/Matchmaking.tscn") as PackedScene).instantiate()
	add_child(inst)
	var opp_name := ""
	var seen_at := -1.0
	var w := 0
	while _now() < 12.0:
		await get_tree().process_frame
		w += 1
		if opp_name == "" and GameState.dual_opponent is Dictionary:
			opp_name = str((GameState.dual_opponent as Dictionary).get("name", ""))
		if seen_at < 0.0 and opp_name != "" and _has_label(inst, opp_name):
			seen_at = _now()
			print("  [对手名 %s] 上屏 t=%.2fs  帧=%d  可见控件=%d" % [opp_name, seen_at, w,
				int(_count(inst)["ctrl"])])
		if _leave_calls > 0 and _now() > _leave_at + 1.0:
			break
	var d0 := _count(inst)
	print("  [稳态] t=%.2fs  ctrl=%d web=%d round=%d" % [_now(), int(d0["ctrl"]), int(d0["web"]), int(d0["round"])])
	# ④ 假违规探子
	var bad := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.2, 0.3, 0.5)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	bad.add_theme_stylebox_override("panel", sb)
	bad.size = Vector2(150, 90)
	bad.position = Vector2(560, 610)
	bad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inst.add_child(bad)
	await get_tree().process_frame
	var d1 := _count(inst)
	print("  [探子在场] ctrl=%d web=%d round=%d  (期望 web/round 各 +1)" % [
		int(d1["ctrl"]), int(d1["web"]), int(d1["round"])])
	bad.free()
	await get_tree().process_frame
	var d2 := _count(inst)
	print("  [探子已摘] ctrl=%d web=%d round=%d  (期望与稳态逐个相等)" % [
		int(d2["ctrl"]), int(d2["web"]), int(d2["round"])])
	print("  [缝] 回调次数=%d  t=%.2fs  目标=%s" % [_leave_calls, _leave_at, _leave_path])
	print("  [没跳场] 实例还在树里=%s  current_scene 还是我=%s" % [
		str(is_instance_valid(inst) and inst.is_inside_tree()),
		str(get_tree().current_scene == me_scene)])
	MM._may_leave_for_test = Callable()
	print("PROBE DONE")
	get_tree().quit(0)


func _has_label(root: Node, txt: String) -> bool:
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label and str((n as Label).text).find(txt) >= 0 and (n as Label).is_visible_in_tree():
			return true
		for ch in n.get_children():
			st.append(ch)
	return false
