extends Node
## 探针(不是门禁, 2026-11-18): 开场地图幕 → 上路对阵幕 换幕那几帧, 新旧两块幕布各自的透明度 / 是否还在树上 / 闪白层透明度。
## 用户 11-18「从闪白跳到那个双方角色对立的那个，中间过渡有点不自然」; 录帧量出第 150→151 帧亮度 194 → 106 一帧掉一半。
## 跑法: APPDATA=<隔离> XDG_DATA_HOME=<同> DUALLANE=1 SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " WINDOW=1 \
##   bash godot-quiet.sh --path . --resolution 1560x720 --position 2000,80 --fixed-fps 30 --quit-after 200 res://tests/probes/_probe_flash_switch.tscn

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
var _b = null
var _el := 0.0
var _seen: Array = []


func _ready() -> void:
	var scr: GDScript = load("res://tests/_setup_appstore.gd")
	scr.run()
	await get_tree().process_frame
	_b = load(BATTLE_SCENE).instantiate()
	add_child(_b)


func _process(d: float) -> void:
	_el += d
	if _b == null or not is_instance_valid(_b) or _b._ui_layer == null:
		return
	if _el < 4.85 or _el > 5.45:
		return
	var parts: Array = []
	for c in _b._ui_layer.get_children():
		if c is ColorRect and (c as ColorRect).z_index == 50:
			var cr := c as ColorRect
			var id := cr.get_instance_id()
			if not _seen.has(id):
				_seen.append(id)
			var fl := _find_flash(cr)
			var tr := _find_view(cr)
			parts.append("幕%d a=%.3f del=%s vis=%s 闪白=%s 地图=%s" % [_seen.find(id), cr.modulate.a, str(cr.is_queued_for_deletion()), str(cr.is_visible_in_tree()),
				("%.3f" % fl.modulate.a) if fl != null else "-",
				("vis=%s tex=%s" % [str(tr.is_visible_in_tree()), str(tr.texture != null)]) if tr != null else "-"])
	print("[PROBE] f=%d t=%.3f state=%s cur=%s | %s" % [Engine.get_frames_drawn(), _el, str(_b._dl_state),
		str(_seen.find(_b._dl_present_root.get_instance_id())) if _b._dl_present_root != null else "null", " || ".join(parts)])


func _find_flash(n: Node) -> ColorRect:
	for c in n.get_children():
		if c is ColorRect and (c as ColorRect).color.is_equal_approx(Color(1.0, 0.97, 0.88, 1.0)):
			return c
		var r := _find_flash(c)
		if r != null:
			return r
	return null


func _find_view(n: Node) -> TextureRect:
	for c in n.get_children():
		if c is TextureRect and (c as TextureRect).texture is ViewportTexture:
			return c
		var r := _find_view(c)
		if r != null:
			return r
	return null
