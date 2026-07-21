# class_name MapEditor   # 不用 class_name: 需 --import 注册后才可用, 宿主改用 preload 常量引用
extends RefCounted

## 🖌 局内地图刷子编辑器 —— 从 RealtimeBattle3DScene 拆出(2026-07-21)。
##
## 【为什么能安全拆】实测: 本簇 7 个函数对伤害管线的调用是 0, 只读 _cam/_arena_center,
##   其余状态(_grid/_height/_meta/_type/_undo)全是自己的, 跟着一起搬走。
##   对外只有 2 个入口: build_ui() 与 paint_at_screen()。
##
## 【拆分模板】照抄 scripts/scenes/dmg_stats_panel.gd:
##   RefCounted + 构造注入宿主要素 + Callable 回调宿主 —— 主场景侧只剩几行。
##   ★注意 scripts/engine/ 不是拆分模板(那是回合制旧引擎), 别参考那边。
##
## 【开发工具, 不进正式对局】MAPEDIT=1 才开; 纯视觉编辑, 不改玩法数值。

const TYPE_NAMES := ["grass", "water", "stone", "sand", "void"]
const HEIGHTS := {0: 0.0, 1: -0.30, 2: 0.25, 3: -0.05, 4: 0.0}
const MAP_PATH := "res://data/maps/arena.json"
const UNDO_CAP := 300

# ── 注入的宿主要素(只读) ──
var _host: Node = null                 # 挂 CanvasLayer 用
var _cam: Camera3D = null              # 屏幕→地面射线
var _arena_center := Vector2.ZERO
var _ws := 0.024                       # 像素→米
var _redraw: Callable                  # 回调宿主重绘 tile: func(meta, grid, height)

# ── 自有状态 ──
var _meta: Dictionary = {}
var _grid: Array = []
var _height: Array = []
var _type: int = 0
var _type_label: Label = null
var _undo: Array = []


func setup(host: Node, cam: Camera3D, arena_center: Vector2, ws: float, redraw: Callable) -> void:
	_host = host
	_cam = cam
	_arena_center = arena_center
	_ws = ws
	_redraw = redraw


## 宿主把已载入的地图数据交进来(宿主负责读 json, 这里只管编辑)
func load_data(meta: Dictionary, grid: Array, height: Array) -> void:
	_meta = meta
	_grid = grid
	_height = height


func grid() -> Array:
	return _grid


func height() -> Array:
	return _height


func meta() -> Dictionary:
	return _meta


func build_ui() -> void:
	if _host == null:
		return
	var cl := CanvasLayer.new()
	cl.layer = 60
	_host.add_child(cl)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 80)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "🖌 地图编辑器 (左键刷格 · MAPEDIT)"
	vb.add_child(title)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for ti in range(TYPE_NAMES.size()):
		var b := Button.new()
		b.text = "%d %s" % [ti, TYPE_NAMES[ti]]
		b.pressed.connect(set_type.bind(ti))
		hb.add_child(b)
	_type_label = Label.new()
	_type_label.text = "当前: grass (0)"
	vb.add_child(_type_label)
	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	var bsave := Button.new(); bsave.text = "💾保存"; bsave.pressed.connect(save); hb2.add_child(bsave)
	var brel := Button.new(); brel.text = "↻重载"; brel.pressed.connect(reload); hb2.add_child(brel)
	var bclr := Button.new(); bclr.text = "清空"; bclr.pressed.connect(clear); hb2.add_child(bclr)
	var bund := Button.new(); bund.text = "撤销"; bund.pressed.connect(undo_last); hb2.add_child(bund)
	cl.add_child(panel)


func set_type(ti: int) -> void:
	_type = ti
	if _type_label != null and is_instance_valid(_type_label):
		_type_label.text = "当前: %s (%d)" % [TYPE_NAMES[ti], ti]


## 屏幕 → Y=0 地面射线 → 格子 → 刷 type+height → 重绘
func paint_at_screen(mpos: Vector2) -> void:
	if _cam == null or not is_instance_valid(_cam) or _grid.is_empty():
		return
	var origin := _cam.project_ray_origin(mpos)
	var dir := _cam.project_ray_normal(mpos)
	if absf(dir.y) < 0.0001:
		return
	var t := -origin.y / dir.y
	if t < 0.0:
		return
	var wp := origin + dir * t
	var px := wp.x / _ws + _arena_center.x
	var py := wp.z / _ws + _arena_center.y
	var tile: float = float(_meta.get("tile", 48.0))
	var c := int((px - float(_meta.get("origin_x", 0.0))) / tile)
	var r := int((py - float(_meta.get("origin_y", 0.0))) / tile)
	if r < 0 or r >= _grid.size():
		return
	var grow: Array = _grid[r]
	if c < 0 or c >= grow.size():
		return
	if int(grow[c]) == _type:
		return
	_undo.append([r, c, int(grow[c]), float(_height[r][c])])
	if _undo.size() > UNDO_CAP:
		_undo.pop_front()
	grow[c] = _type
	_height[r][c] = float(HEIGHTS[_type])
	_emit_redraw()


func save() -> void:
	_meta["grid"] = _grid
	_meta["height"] = _height
	var f := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_meta))
		f.close()


func reload() -> void:
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_meta = data
		_grid = data.get("grid", [])
		_height = data.get("height", [])
		_emit_redraw()


func clear() -> void:
	for r in range(_grid.size()):
		var grow: Array = _grid[r]
		for c in range(grow.size()):
			grow[c] = 0
			_height[r][c] = 0.0
	_emit_redraw()


func undo_last() -> void:
	if _undo.is_empty():
		return
	var op = _undo.pop_back()
	var r: int = op[0]
	var c: int = op[1]
	if r < _grid.size() and c < (_grid[r] as Array).size():
		_grid[r][c] = op[2]
		_height[r][c] = op[3]
		_emit_redraw()


func _emit_redraw() -> void:
	if _redraw.is_valid():
		_redraw.call(_meta, _grid, _height)
