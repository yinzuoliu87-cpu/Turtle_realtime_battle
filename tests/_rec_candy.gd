extends Node
## 糖果龟普攻【横扫大锤】与技能【糖果锤】特效录像台(不是门禁, 2026-11-15)。
## 用户 11-15「接下来主要针对一下糖果龟的这个特效去专门修一下，尤其这个就是它的普通攻击和糖果锤」。
## 调试场(DEBUG_EDIT): 我方糖果龟(技能选糖果锤) vs 对面 3 个木桩(石头龟, 不打不走)排成一线; 满龟能(反复放糖果锤)。
## 跑法(右屏、静音):
##   APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 \
##     --write-movie <输出>/candy.avi --fixed-fps 60 --quit-after 1500 res://tests/_rec_candy.tscn
## 可选: REC_SECS(默认 12) · REC_SKILL(默认 1 = 糖果锤; 0 = 只有普攻)
## [HIT] 行打每次普攻 / 糖果锤的时刻, 截帧时对照。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"

var _scn = null
var _el := 0.0
var _secs := 12.0
var _cd = null
var _last_atk := -1.0


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		var lo: Dictionary = (gs.loadouts as Dictionary).duplicate()
		lo["candy"] = int(OS.get_environment("REC_SKILL")) if OS.has_environment("REC_SKILL") else 1
		gs.loadouts = lo
	if OS.has_environment("REC_SECS"):
		_secs = float(OS.get_environment("REC_SECS"))
	OS.set_environment("TURTLE_SEED", "424242")
	var RB = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	RB.DEBUG_EDIT = true
	_scn = load(BATTLE_SCENE).instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame
	_scn._debug._edit_clear()
	_scn._edit_dummy_killable = false
	_scn._edit_dummy_hp = 60000.0
	_scn._edit_full_energy = true
	var ar: Rect2 = _scn.ARENA
	var cy: float = ar.position.y + ar.size.y * 0.5
	var lx: float = ar.position.x + ar.size.x * 0.40
	_cd = _scn._debug._edit_place_unit("candy", "left", Vector2(lx, cy))
	for k in range(3):
		_scn._debug._edit_place_unit("stone", "right", Vector2(lx + 110.0 + 55.0 * float(k), cy + float(k - 1) * 12.0))
	_scn._debug._edit_start_battle()
	for u in _scn._units:
		if u is Dictionary and str(u.get("side", "")) == "right":
			u["no_basic"] = true   # 木桩: 不打不走, 只看糖果龟的特效
			u["no_move"] = true
	print("[REC] 开打")


func _process(delta: float) -> void:
	if _scn == null:
		return
	_el += delta
	for nm in ["_edit_palette", "_edit_brush_bar", "_edit_grid_popup"]:
		var c = _scn.get(nm)
		if c != null and is_instance_valid(c) and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
	for u in _scn._units:
		if u is Dictionary and str(u.get("id", "")) == "candy" and str(u.get("side", "")) == "left":
			var act: String = str(u.get("anim_action", ""))
			var t_act: float = float(u.get("_anim_t0", -1.0))
			if act != "" and t_act != _last_atk and act != "idle" and act != "run":
				_last_atk = t_act
				print("[HIT] %.2f 秒 动作 %s" % [_el, act])
	if _el >= _secs:
		get_tree().quit(0)
